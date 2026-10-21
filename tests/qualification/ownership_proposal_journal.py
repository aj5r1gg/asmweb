#!/usr/bin/env python3
"""Non-effective ownership journal regression and rejection tests."""

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import ownership_decision_preflight as preflight
import ownership_proposal_journal as journal


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def rejected(operation, label):
    try:
        operation()
    except (ValueError, OSError):
        print(f"{label}=REJECTED")
        return

    raise AssertionError(f"{label}=INCORRECTLY_ACCEPTED")


baseline = preflight.current_snapshot()

candidate = {
    "schema_version": 1,
    "decision_id": "M0-JOURNAL-TEST-001",
    "requirement_id": "REQ-M0-001",
    "first_mandatory_milestone": "M0",
    "decision_status": "PROPOSED",
    "decision_rationale": (
        "Non-effective journal verification candidate."
    ),
    "source_authority_refs": [
        "qualification/requirements/requirements-source-v0.3.json"
    ],
    "review_evidence_refs": [],
    "authority_designation_ref": None,
    "approval_evidence_ref": None,
    "baseline_snapshot_id": baseline,
    "decision_provenance": {
        "verification_status": "UNVERIFIED"
    },
    "supersedes_decision_ref": None,
}

with tempfile.TemporaryDirectory(prefix="asmweb-journal-") as temp:
    directory = Path(temp) / "journal"

    first = journal.append_proposal(candidate, directory)

    check(
        first["result"] == "PROPOSAL_RECORDED_NON_EFFECTIVE",
        "first proposal not recorded",
    )

    check(
        first["effective_publication"] is False,
        "proposal became effective",
    )

    check(
        journal.verify_journal(directory)["decision_count"] == 1,
        "incorrect journal count",
    )

    print("FIRST_APPEND=PASS")
    print("JOURNAL_VERIFICATION=PASS")

    original = (directory / journal.filename(
        candidate["decision_id"]
    )).read_bytes()

    rejected(
        lambda: journal.append_proposal(candidate, directory),
        "DUPLICATE_DECISION_ID",
    )

    conflict = copy.deepcopy(candidate)
    conflict["decision_id"] = "M0-JOURNAL-TEST-002"
    conflict["first_mandatory_milestone"] = "M1"

    rejected(
        lambda: journal.append_proposal(conflict, directory),
        "CONFLICTING_REQUIREMENT_PROPOSAL",
    )

    stale = copy.deepcopy(candidate)
    stale["decision_id"] = "M0-JOURNAL-TEST-003"
    stale["baseline_snapshot_id"] = "0" * 64

    rejected(
        lambda: journal.append_proposal(stale, directory),
        "STALE_BASELINE",
    )

    false_approval = copy.deepcopy(candidate)
    false_approval["decision_id"] = "M0-JOURNAL-TEST-004"
    false_approval["decision_status"] = "APPROVED"

    rejected(
        lambda: journal.append_proposal(
            false_approval, directory
        ),
        "FALSE_APPROVAL",
    )

    check(
        (directory / journal.filename(
            candidate["decision_id"]
        )).read_bytes() == original,
        "original journal entry changed",
    )

    print("ORIGINAL_RECORD_UNCHANGED=PASS")

    second = copy.deepcopy(candidate)
    second["decision_id"] = "M0-JOURNAL-TEST-005"
    second["requirement_id"] = "REQ-M0-002"

    result = journal.append_proposal(second, directory)

    check(
        result["recorded_proposals"] == 2,
        "second independent proposal rejected",
    )

    print("INDEPENDENT_PROPOSAL=PASS")

    # A changed existing record must prevent further submissions.
    first_path = directory / journal.filename(
        candidate["decision_id"]
    )
    first_path.write_bytes(original + b"\n")

    rejected(
        lambda: journal.verify_journal(directory),
        "ALTERED_RECORD_VERIFICATION",
    )

    third = copy.deepcopy(candidate)
    third["decision_id"] = "M0-JOURNAL-TEST-006"
    third["requirement_id"] = "REQ-M0-003"

    rejected(
        lambda: journal.append_proposal(third, directory),
        "ALTERED_JOURNAL_APPEND",
    )

    # Restore the original record and verify the independent
    # CLI inspection path.
    first_path.write_bytes(original)

    cli = subprocess.run(
        [
            sys.executable,
            "-B",
            str(
                ROOT / "qualification/tools/"
                "ownership_proposal_journal.py"
            ),
            "verify",
            "--journal",
            str(directory),
        ],
        capture_output=True,
        text=True,
        check=True,
    )

    check(
        "NON_EFFECTIVE_JOURNAL_VERIFIED" in cli.stdout,
        "CLI journal verification failed",
    )

    print("CLI_VERIFY=PASS")

print("OWNERSHIP_PROPOSAL_JOURNAL=PASS")
