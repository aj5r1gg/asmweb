#!/usr/bin/env python3
"""Authenticated ownership proposal tests using temporary signing keys."""

import copy
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import ownership_authority as authority
import ownership_decision_preflight as preflight
import ownership_proposal_journal as journal
import ownership_signed_decision as signed
import ownership_snapshot as snapshot


def run(*args):
    subprocess.run(args, check=True, capture_output=True)


def rejected(label, action):
    try:
        action()
    except (OSError, ValueError):
        print(f"{label}=REJECTED")
    else:
        raise AssertionError(label + " incorrectly accepted")


with tempfile.TemporaryDirectory(
    prefix="asmweb-signed-decision-"
) as directory:
    temp = Path(directory)
    root_key = temp / "root"
    reviewer_key = temp / "reviewer"
    attacker_key = temp / "attacker"

    for key in (root_key, reviewer_key, attacker_key):
        run(
            "ssh-keygen", "-q", "-t", "ed25519",
            "-N", "", "-f", str(key),
        )

    trusted = temp / "trusted-root"
    trusted.write_text(
        authority.TRUST_PRINCIPAL + " "
        + root_key.with_suffix(".pub").read_text()
    )

    revocations = temp / "revocations.json"
    revocations.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [],
    }))

    candidate = {
        "schema_version": 1,
        "decision_id": "M0-SIGNED-TEST-001",
        "requirement_id": "REQ-M0-001",
        "first_mandatory_milestone": "M0",
        "decision_status": "PROPOSED",
        "decision_rationale": "Temporary signed test proposal.",
        "source_authority_refs": [
            "qualification/requirements/requirements-source-v0.3.json"
        ],
        "review_evidence_refs": [],
        "authority_designation_ref": None,
        "approval_evidence_ref": None,
        "baseline_snapshot_id": preflight.current_snapshot(),
        "decision_provenance": {
            "verification_status": "UNVERIFIED"
        },
        "supersedes_decision_ref": None,
    }

    journal_dir = temp / "journal"
    journal.append_proposal(candidate, journal_dir)

    designation = temp / "designation.json"
    designation.write_bytes(authority.canonical({
        "schema_version": 1,
        "designation_id": "TEST-REVIEWER-AUTH-001",
        "principal": "test-reviewer",
        "granted_requirement_ids": ["REQ-M0-001", "REQ-M0-002"],
        "granted_milestones": ["M0"],
        "valid_from": "2020-01-01T00:00:00Z",
        "valid_until": "2099-01-01T00:00:00Z",
    }))

    binding = temp / "binding.json"
    reviewer_pub = reviewer_key.with_suffix(".pub").read_text()
    reviewer_pub = " ".join(reviewer_pub.split()[:2])

    binding.write_bytes(authority.canonical({
        "schema_version": 1,
        "designation_id": "TEST-REVIEWER-AUTH-001",
        "principal": "test-reviewer",
        "reviewer_public_key": reviewer_pub,
    }))

    decision_file = temp / "decision.json"
    decision_file.write_bytes(snapshot.canonical(candidate))

    def sign(key, path, namespace):
        signature = Path(str(path) + ".sig")
        signature.unlink(missing_ok=True)
        run(
            "ssh-keygen", "-Y", "sign",
            "-f", str(key),
            "-n", namespace,
            str(path),
        )
        return signature

    designation_sig = sign(
        root_key, designation, authority.NAMESPACE
    )
    binding_sig = sign(
        root_key, binding, signed.BINDING_NAMESPACE
    )
    decision_sig = sign(
        reviewer_key, decision_file, signed.DECISION_NAMESPACE
    )

    def verify(
        chosen_binding=None,
        chosen_binding_sig=None,
        chosen_decision_sig=None,
        chosen_id=None,
    ):
        return signed.verify(
            journal_dir,
            chosen_id or candidate["decision_id"],
            designation,
            designation_sig,
            chosen_binding or binding,
            chosen_binding_sig or binding_sig,
            trusted,
            revocations,
            chosen_decision_sig or decision_sig,
        )

    result = verify()
    assert result["decision_signature_verified"] is True
    assert result["ownership_approved"] is False
    assert result["effective_publication"] is False
    print("VALID_SIGNED_PROPOSAL=PASS")

    rejected(
        "UNKNOWN_DECISION_ID",
        lambda: verify(chosen_id="UNKNOWN-DECISION"),
    )

    attacker_sig = sign(
        attacker_key, decision_file, signed.DECISION_NAMESPACE
    )
    rejected(
        "WRONG_REVIEWER_SIGNER",
        lambda: verify(chosen_decision_sig=attacker_sig),
    )

    forged_binding = temp / "forged-binding.json"
    forged_binding.write_bytes(authority.canonical({
        "schema_version": 1,
        "designation_id": "TEST-REVIEWER-AUTH-001",
        "principal": "test-reviewer",
        "reviewer_public_key": " ".join(
            attacker_key.with_suffix(".pub").read_text().split()[:2]
        ),
    }))
    forged_sig = sign(
        attacker_key, forged_binding, signed.BINDING_NAMESPACE
    )
    rejected(
        "SELF_DECLARED_REVIEWER_KEY",
        lambda: verify(forged_binding, forged_sig),
    )

    revocations.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": ["TEST-REVIEWER-AUTH-001"],
    }))
    rejected("REVOKED_AUTHORITY", verify)

    revocations.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [],
    }))

    # Same reviewer signature cannot authenticate a different
    # candidate, even when its designation remains valid.
    changed = copy.deepcopy(candidate)
    changed["decision_id"] = "M0-SIGNED-TEST-002"
    changed["requirement_id"] = "REQ-M0-002"
    journal.append_proposal(changed, journal_dir)

    # Restore the legitimate reviewer's signature. Both
    # requirements are in scope, so the replay test must
    # reach cryptographic signature verification.
    decision_sig = sign(
        reviewer_key, decision_file, signed.DECISION_NAMESPACE
    )

    rejected(
        "SIGNATURE_REPLAY_ON_OTHER_DECISION",
        lambda: verify(chosen_id=changed["decision_id"]),
    )

    cli = subprocess.run(
        [
            sys.executable, "-B",
            str(ROOT / "qualification/tools/ownership_signed_decision.py"),
            "--journal", str(journal_dir),
            "--decision-id", candidate["decision_id"],
            "--designation", str(designation),
            "--designation-signature", str(designation_sig),
            "--binding", str(binding),
            "--binding-signature", str(binding_sig),
            "--trusted-root", str(trusted),
            "--revocations", str(revocations),
            "--decision-signature", str(decision_sig),
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    print("CLI_RETURN_CODE=", cli.returncode)
    print("CLI_STDOUT=", cli.stdout)
    print("CLI_STDERR=", cli.stderr)

    assert cli.returncode == 0, "CLI verification failed"
    assert "SIGNED_DECISION_VERIFICATION=PASS" in cli.stdout
    print("CLI_VERIFICATION=PASS")

print("EFFECTIVE_APPROVALS=0")
print("SIGNED_OWNERSHIP_DECISION=PASS")
