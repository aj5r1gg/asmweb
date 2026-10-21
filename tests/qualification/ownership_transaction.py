#!/usr/bin/env python3
"""End-to-end signed ownership transaction qualification."""

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
import ownership_decision_preflight as preflight
import ownership_proposal_journal as journal
import ownership_signed_decision as signed
import ownership_snapshot as snapshot
import ownership_transaction as transaction
import ownership_transaction_checkpoint as checkpoint


def command(*args):
    subprocess.run(
        args, check=True, capture_output=True
    )


def rejects(label, action):
    try:
        action()
    except (OSError, ValueError, KeyError, TypeError):
        print(label + "=REJECTED")
    else:
        raise AssertionError(label + " was accepted")


with tempfile.TemporaryDirectory(
    prefix="asmweb-transaction-"
) as name:
    base = Path(name)
    evidence = base / "evidence"
    evidence.mkdir()
    proposals = base / "proposals"

    root_key = base / "root"
    reviewer_key = base / "reviewer"

    for key in (root_key, reviewer_key):
        command(
            "ssh-keygen", "-q", "-t", "ed25519",
            "-N", "", "-f", str(key)
        )

    trusted = base / "trusted"
    trusted.write_text(
        "asmweb-root "
        + root_key.with_suffix(".pub").read_text()
    )

    revoked = base / "revocations.json"
    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [],
    }))

    designation = evidence / "designation.json"
    designation.write_bytes(authority.canonical({
        "schema_version": 1,
        "designation_id": "INTEGRATION-TEST-001",
        "principal": "integration-reviewer",
        "granted_requirement_ids": ["REQ-M0-001"],
        "granted_milestones": ["M0"],
        "valid_from": "2020-01-01T00:00:00Z",
        "valid_until": "2099-01-01T00:00:00Z",
    }))

    public_key = " ".join(
        reviewer_key.with_suffix(".pub").read_text().split()[:2]
    )

    binding = evidence / "binding.json"
    binding.write_bytes(authority.canonical({
        "schema_version": 1,
        "designation_id": "INTEGRATION-TEST-001",
        "principal": "integration-reviewer",
        "reviewer_public_key": public_key,
    }))

    candidate = {
        "schema_version": 1,
        "decision_id": "INTEGRATION-DECISION-001",
        "requirement_id": "REQ-M0-001",
        "first_mandatory_milestone": "M0",
        "decision_status": "PROPOSED",
        "decision_rationale": "Signed integration verification.",
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

    journal.append_proposal(candidate, proposals)

    candidate_path = evidence / "decision.json"
    candidate_path.write_bytes(snapshot.canonical(candidate))

    def sign(key, source, namespace):
        command(
            "ssh-keygen", "-Y", "sign",
            "-f", str(key), "-n", namespace,
            str(source),
        )
        return source.name + ".sig"

    designation_sig = sign(
        root_key, designation, authority.NAMESPACE
    )
    binding_sig = sign(
        root_key, binding, signed.BINDING_NAMESPACE
    )
    decision_sig = sign(
        reviewer_key, candidate_path,
        signed.DECISION_NAMESPACE,
    )

    entry = {
        "decision_id": candidate["decision_id"],
        "designation": designation.name,
        "designation_signature": designation_sig,
        "binding": binding.name,
        "binding_signature": binding_sig,
        "decision_signature": decision_sig,
    }

    manifest = {
        "schema_version": 1,
        "format": transaction.FORMAT,
        "baseline_snapshot_id": preflight.current_snapshot(),
        "decisions": [entry],
    }
    path = base / "transaction.json"

    def check(document):
        path.write_bytes(snapshot.canonical(document))
        return transaction.verify(
            path, proposals, evidence, trusted, revoked
        )

    result = check(manifest)
    assert result["decision_count"] == 1
    assert result["effective_approvals"] == 0
    assert result["publication_enabled"] is False
    assert len(result["evidence"]) == 1
    assert result["evidence"][0]["decision_id"] == (
        candidate["decision_id"]
    )

    import hashlib

    evidence_digests = result["evidence"][0]["sha256"]
    assert set(evidence_digests) == (
        transaction.FIELDS - {"decision_id"}
    )

    for field, filename in entry.items():
        if field != "decision_id":
            actual = hashlib.sha256(
                (evidence / filename).read_bytes()
            ).hexdigest()
            assert evidence_digests[field] == actual

    assert result["trusted_root_sha256"] == hashlib.sha256(
        trusted.read_bytes()
    ).hexdigest()

    assert result["revocations_sha256"] == hashlib.sha256(
        revoked.read_bytes()
    ).hexdigest()

    original_receipt = result["receipt_sha256"]

    # A different, still-valid revocation register must produce a
    # different receipt, not masquerade as the prior transaction.
    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [
            "UNRELATED-INTEGRATION-TEST-002"
        ],
    }))

    changed_receipt = check(manifest)

    assert changed_receipt["receipt_sha256"] != original_receipt
    assert (
        changed_receipt["revocations_sha256"]
        != result["revocations_sha256"]
    )

    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [],
    }))

    assert check(manifest)["receipt_sha256"] == original_receipt

    print("EVIDENCE_BYTE_IDENTITY=PASS")
    print("TRUST_AND_REVOCATION_BINDING=PASS")
    print("REVOCATION_CHANGE_CHANGES_RECEIPT=PASS")
    print("DETERMINISTIC_RECEIPT=PASS")
    print("SIGNED_FULL_COVERAGE_TRANSACTION=PASS")

    duplicate = copy.deepcopy(manifest)
    duplicate["decisions"].append(copy.deepcopy(entry))
    rejects(
        "DUPLICATE_DECISION",
        lambda: check(duplicate),
    )

    missing = copy.deepcopy(manifest)
    missing["decisions"] = []
    rejects(
        "MISSING_SIGNED_COVERAGE",
        lambda: check(missing),
    )

    stale = copy.deepcopy(manifest)
    stale["baseline_snapshot_id"] = "0" * 64
    rejects("STALE_BASELINE", lambda: check(stale))

    unsafe = copy.deepcopy(manifest)
    unsafe["decisions"][0]["binding"] = "../binding.json"
    rejects("UNSAFE_EVIDENCE_REFERENCE", lambda: check(unsafe))

    tampered = evidence / "decision.json.sig"
    valid_signature = tampered.read_bytes()
    tampered.write_bytes(valid_signature + b"garbage")

    rejects(
        "TAMPERED_DECISION_SIGNATURE",
        lambda: check(manifest),
    )
    tampered.write_bytes(valid_signature)

    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [
            "INTEGRATION-TEST-001"
        ],
    }))
    rejects("REVOKED_REVIEWER", lambda: check(manifest))

    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [],
    }))

    result = check(manifest)
    assert result["decision_count"] == 1

    cli = subprocess.run(
        [
            sys.executable, "-B",
            str(
                ROOT / "qualification/tools/"
                "ownership_transaction.py"
            ),
            "--manifest", str(path),
            "--journal", str(proposals),
            "--evidence", str(evidence),
            "--trusted-root", str(trusted),
            "--revocations", str(revoked),
        ],
        capture_output=True,
        text=True,
    )

    assert cli.returncode == 0, cli.stderr
    parsed = json.loads(cli.stdout)
    assert parsed["receipt_sha256"] == result["receipt_sha256"]
    print("INDEPENDENT_CLI_RECEIPT=PASS")

    # The checkpoint records the transaction-wide receipt.
    # It never publishes ownership approvals.
    store = base / "checkpoint-store"
    inputs = (path, proposals, evidence, trusted, revoked)

    first = checkpoint.publish(store, *inputs)

    assert first["publication"] == "ATOMIC_ROOT_REPLACEMENT"
    assert first["effective_approvals"] == 0

    root_file = store / "checkpoint-root.json"
    original_root = root_file.read_bytes()

    verified = checkpoint.verify(store, *inputs)

    assert (
        verified["receipt_sha256"]
        == result["receipt_sha256"]
    )

    again = checkpoint.publish(store, *inputs)
    assert again["publication"] == "ALREADY_CURRENT"
    assert root_file.read_bytes() == original_root

    print("SIGNED_TRANSACTION_CHECKPOINT=PASS")
    print("CHECKPOINT_IDEMPOTENCE=PASS")

    # A valid but changed revocation register must invalidate
    # the stored receipt until the original evidence is restored.
    original_revocations = revoked.read_bytes()

    revoked.write_bytes(authority.canonical({
        "schema_version": 1,
        "revoked_designation_ids": [
            "UNRELATED-CHECKPOINT-TEST-002"
        ],
    }))

    rejects(
        "STALE_CHECKPOINT_REVOCATIONS",
        lambda: checkpoint.verify(store, *inputs),
    )

    rejects(
        "STALE_CHECKPOINT_REPUBLICATION",
        lambda: checkpoint.publish(store, *inputs),
    )

    assert root_file.read_bytes() == original_root
    revoked.write_bytes(original_revocations)

    assert (
        checkpoint.verify(store, *inputs)["result"]
        == "VERIFIED_NON_EFFECTIVE_CHECKPOINT"
    )
    print("CHECKPOINT_EXPLICIT_RECOVERY=PASS")

    generation_file = next(
        (store / "generations").glob("*.json")
    )
    original_generation = generation_file.read_bytes()

    generation_file.write_bytes(original_generation + b"x")

    rejects(
        "ALTERED_CHECKPOINT_GENERATION",
        lambda: checkpoint.verify(store, *inputs),
    )

    rejects(
        "ALTERED_CHECKPOINT_REPUBLICATION",
        lambda: checkpoint.publish(store, *inputs),
    )

    generation_file.write_bytes(original_generation)

    root_file.write_bytes(original_root + b"x")

    rejects(
        "CORRUPTED_CHECKPOINT_ROOT",
        lambda: checkpoint.verify(store, *inputs),
    )

    root_file.write_bytes(original_root)

    assert checkpoint.verify(store, *inputs)
    print("CHECKPOINT_INTEGRITY_RECOVERY=PASS")

    checkpoint_cli = subprocess.run(
        [
            sys.executable, "-B",
            str(
                ROOT / "qualification/tools/"
                "ownership_transaction_checkpoint.py"
            ),
            "verify",
            "--store", str(store),
            "--manifest", str(path),
            "--journal", str(proposals),
            "--evidence", str(evidence),
            "--trusted-root", str(trusted),
            "--revocations", str(revoked),
        ],
        capture_output=True,
        text=True,
    )

    assert checkpoint_cli.returncode == 0, (
        checkpoint_cli.stderr
    )

    assert (
        json.loads(checkpoint_cli.stdout)["receipt_sha256"]
        == result["receipt_sha256"]
    )

    print("CHECKPOINT_CLI_VERIFICATION=PASS")

print("EFFECTIVE_APPROVALS=0")
print("INTEGRATED_OWNERSHIP_TRANSACTION=PASS")
