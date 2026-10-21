#!/usr/bin/env python3
"""Adversarial tests for non-effective signed authority verification."""

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import ownership_authority as authority


def run(*args, **kwargs):
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        check=True,
        **kwargs,
    )


def expected_rejection(name, operation):
    try:
        operation()
    except (ValueError, OSError):
        print(f"{name}=REJECTED")
        return
    raise AssertionError(f"{name}=INCORRECTLY_ACCEPTED")


with tempfile.TemporaryDirectory(
    prefix="asmweb-authority-"
) as temporary:
    root = Path(temporary)

    key = root / "root-key"
    other_key = root / "other-key"
    trusted = root / "trusted-signers"
    revoked = root / "revocations.json"
    designation = root / "designation.json"

    for item in (key, other_key):
        run(
            "ssh-keygen",
            "-q",
            "-t", "ed25519",
            "-N", "",
            "-f", str(item),
        )

    # Only root-key is trusted. Neither the proposed decision
    # nor the designation can introduce a trusted signer.
    trusted.write_text(
        authority.TRUST_PRINCIPAL
        + " "
        + (root / "root-key.pub").read_text(),
        encoding="utf-8",
    )

    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [],
    }))

    document = {
        "schema_version": 1,
        "designation_id": "TEST-DESIGNATION-001",
        "principal": "test-reviewer",
        "granted_requirement_ids": ["REQ-M0-001"],
        "granted_milestones": ["M0"],
        "valid_from": "2020-01-01T00:00:00Z",
        "valid_until": "2099-01-01T00:00:00Z",
    }

    def write_designation(value):
        designation.write_bytes(authority.canonical(value))

    def sign(signing_key):
        signature = Path(str(designation) + ".sig")
        signature.unlink(missing_ok=True)
        run(
            "ssh-keygen",
            "-Y", "sign",
            "-f", str(signing_key),
            "-n", authority.NAMESPACE,
            str(designation),
        )
        assert signature.is_file()
        return signature

    def verify(requirement="REQ-M0-001", milestone="M0"):
        return authority.verify(
            designation,
            Path(str(designation) + ".sig"),
            trusted,
            revoked,
            requirement,
            milestone,
        )

    write_designation(document)
    signature = sign(key)

    result = verify()

    assert result["signature_verified"] is True
    assert result["ownership_approved"] is False
    assert result["effective_authority_published"] is False
    assert result["milestone_closed"] is False

    print("VALID_SIGNED_DESIGNATION=PASS")

    expected_rejection(
        "OUT_OF_SCOPE_MILESTONE",
        lambda: verify(milestone="M1"),
    )

    expected_rejection(
        "OUT_OF_SCOPE_REQUIREMENT",
        lambda: verify(requirement="REQ-M0-002"),
    )

    expected_rejection(
        "UNKNOWN_REQUIREMENT",
        lambda: verify(requirement="REQ-UNKNOWN-001"),
    )

    # A signed grant must still be checked against revocation state.
    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": ["TEST-DESIGNATION-001"],
    }))

    expected_rejection("REVOKED_DESIGNATION", verify)

    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [],
    }))

    # Altering a signed designation invalidates its signature.
    changed = copy.deepcopy(document)
    changed["principal"] = "other-reviewer"
    write_designation(changed)

    expected_rejection("TAMPERED_DESIGNATION", verify)

    # A different signing key cannot invent a trusted root.
    write_designation(document)
    signature = sign(other_key)

    expected_rejection("UNTRUSTED_SIGNER", verify)

    # Restore the trusted signer and test an expired grant.
    expired = copy.deepcopy(document)
    expired["valid_until"] = "2021-01-01T00:00:00Z"

    write_designation(expired)
    signature = sign(key)

    expected_rejection("EXPIRED_DESIGNATION", verify)

    # Invalid scope must be rejected even with a valid signature.
    invalid = copy.deepcopy(document)
    invalid["granted_milestones"] = ["M99"]

    write_designation(invalid)
    signature = sign(key)

    expected_rejection("INVALID_GRANTED_MILESTONE", verify)

    # Test the actual CLI, not only the importable function.
    write_designation(document)
    signature = sign(key)

    cli = run(
        sys.executable,
        "-B",
        str(
            ROOT / "qualification/tools/"
            "ownership_authority.py"
        ),
        "--designation", str(designation),
        "--signature", str(signature),
        "--trusted-signers", str(trusted),
        "--revocations", str(revoked),
        "--requirement", "REQ-M0-001",
        "--milestone", "M0",
    )

    assert "OWNERSHIP_AUTHORITY_VERIFICATION=PASS" in cli.stdout
    print("CLI_VERIFICATION=PASS")

print("EFFECTIVE_APPROVALS=0")
print("OWNERSHIP_AUTHORITY_ADVERSARIAL=PASS")
