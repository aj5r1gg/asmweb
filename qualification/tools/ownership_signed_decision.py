#!/usr/bin/env python3
"""Verify signed ownership proposals against independently signed reviewer keys.

NON-EFFECTIVE: This verifies authenticity, not approval or publication.
"""

import argparse
import base64
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import ownership_authority as authority
import ownership_decision_preflight as preflight
import ownership_proposal_journal as journal
import ownership_snapshot as snapshot

BINDING_NAMESPACE = "asmweb-reviewer-key-binding-v1"
DECISION_NAMESPACE = "asmweb-ownership-decision-v1"
REVIEWER_PRINCIPAL = "asmweb-reviewer"


class DecisionError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise DecisionError(message)


def read(path):
    path = authority.independent_file(path)
    data = path.read_bytes()
    require(len(data) <= 65536, "oversized input")
    return data


def signature_check(payload, signature, signers, principal, namespace):
    # OpenSSH may accept a valid armored signature followed by
    # trailing bytes. Qualification evidence must be strictly
    # framed and must not contain ignored or ambiguous material.
    encoded_signature = read(signature)

    # Split only on LF, requiring the exact OpenSSH armor.
    # This deliberately rejects CRLF, leading or trailing data,
    # additional blank lines, and anything after the footer.
    lines = encoded_signature.split(bytes([10]))

    require(
        len(lines) >= 4
        and lines[0] == b"-----BEGIN SSH SIGNATURE-----"
        and lines[-2] == b"-----END SSH SIGNATURE-----"
        and lines[-1] == b"",
        "malformed signature envelope",
    )

    encoded_lines = lines[1:-2]
    alphabet = frozenset(
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        b"abcdefghijklmnopqrstuvwxyz"
        b"0123456789+/="
    )

    require(
        bool(encoded_lines)
        and all(
            bool(line) and all(byte in alphabet for byte in line)
            for line in encoded_lines
        ),
        "invalid armored signature body",
    )

    body = b"".join(encoded_lines)

    try:
        decoded = base64.b64decode(body, validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise DecisionError("malformed signature encoding") from exc

    require(
        base64.b64encode(decoded) == body
        and decoded.startswith(b"SSHSIG"),
        "noncanonical SSH signature",
    )

    result = subprocess.run(
        [
            "ssh-keygen", "-Y", "verify",
            "-f", str(signers),
            "-I", principal,
            "-n", namespace,
            "-s", str(signature),
        ],
        input=payload,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    require(result.returncode == 0, "signature verification failed")


def reviewer_key(value):
    require(type(value) is str, "reviewer key missing")
    parts = value.split()
    require(
        len(parts) == 2 and parts[0] == "ssh-ed25519",
        "only bare Ed25519 reviewer keys permitted",
    )

    try:
        encoded = base64.b64decode(parts[1], validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise DecisionError("malformed reviewer key") from exc

    require(
        base64.b64encode(encoded).decode("ascii") == parts[1],
        "noncanonical reviewer key",
    )
    require(
        len(encoded) >= 20 and len(encoded) <= 1024,
        "invalid reviewer key length",
    )


def verify(
    journal_dir, decision_id, designation, designation_signature,
    binding, binding_signature, trusted_root, revocations,
    decision_signature,
):
    require(
        authority.valid_identifier(decision_id),
        "invalid decision identity",
    )

    journal_dir = Path(journal_dir)
    journal.validate_directory(journal_dir)
    records, _ = journal.inspect_records(journal_dir)

    require(decision_id in records, "decision not in journal")
    candidate = records[decision_id]["candidate"]

    baseline = preflight.current_snapshot()
    preflight.validate(candidate, baseline)

    # The designation is authenticated against the external root,
    # and checked against the exact requirement/milestone pair.
    authority_result = authority.verify(
        designation, designation_signature, trusted_root, revocations,
        candidate["requirement_id"],
        candidate["first_mandatory_milestone"],
    )

    designation_doc = authority.load(read(designation))
    binding_data = read(binding)
    binding_doc = authority.load(binding_data)

    require(
        type(binding_doc) is dict
        and set(binding_doc) == {
            "schema_version", "designation_id",
            "principal", "reviewer_public_key"
        },
        "invalid reviewer binding fields",
    )
    require(
        type(binding_doc["schema_version"]) is int
        and binding_doc["schema_version"] == 1,
        "invalid binding schema",
    )
    require(
        binding_data == authority.canonical(binding_doc),
        "noncanonical reviewer binding",
    )
    require(
        binding_doc["designation_id"]
        == designation_doc["designation_id"]
        and binding_doc["principal"] == designation_doc["principal"],
        "reviewer binding does not match designation",
    )

    reviewer_key(binding_doc["reviewer_public_key"])

    # Only the separately trusted root may bind a reviewer key
    # to a designation. The candidate cannot nominate its signer.
    signature_check(
        binding_data,
        binding_signature,
        trusted_root,
        authority.TRUST_PRINCIPAL,
        BINDING_NAMESPACE,
    )

    # OpenSSH accepts an allowed-signers file; create it exclusively
    # from the authenticated reviewer binding.
    with tempfile.TemporaryDirectory(
        prefix="asmweb-reviewer-"
    ) as temp:
        allowed = Path(temp) / "allowed_signers"
        allowed.write_text(
            REVIEWER_PRINCIPAL + " "
            + binding_doc["reviewer_public_key"] + "\n",
            encoding="utf-8",
        )

        signature_check(
            snapshot.canonical(candidate),
            decision_signature,
            allowed,
            REVIEWER_PRINCIPAL,
            DECISION_NAMESPACE,
        )

    return {
        "result": "SIGNED_PROPOSAL_VERIFIED_NON_EFFECTIVE",
        "decision_id": decision_id,
        "requirement_id": candidate["requirement_id"],
        "milestone": candidate["first_mandatory_milestone"],
        "designation_id": authority_result["designation_id"],
        "designation_signature_verified": True,
        "reviewer_binding_verified": True,
        "decision_signature_verified": True,
        "baseline_verified": True,
        "ownership_approved": False,
        "effective_publication": False,
        "milestone_closed": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)

    for name in (
        "journal", "decision-id", "designation",
        "designation-signature", "binding", "binding-signature",
        "trusted-root", "revocations", "decision-signature",
    ):
        parser.add_argument(
            "--" + name,
            required=True,
            type=str if name == "decision-id" else Path,
        )

    args = parser.parse_args()

    try:
        result = verify(
            args.journal, args.decision_id, args.designation,
            args.designation_signature, args.binding,
            args.binding_signature, args.trusted_root,
            args.revocations, args.decision_signature,
        )
    except (
        OSError, ValueError, TypeError, KeyError,
        subprocess.TimeoutExpired,
    ) as exc:
        print(f"SIGNED_DECISION=REJECT: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2))
    print("SIGNED_DECISION_VERIFICATION=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
