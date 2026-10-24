#!/usr/bin/env python3
"""REQ-M0-003: verify coverage of known M0 requirement identities.

This verifies engineering traceability. It does not grant
ownership approval or establish formal milestone qualification.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(relative):
    return json.loads(
        (ROOT / relative).read_text(encoding="utf-8")
    )


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def main():
    source = load(
        "qualification/requirements/requirements-source-v0.3.json"
    )
    ownership = load(
        "qualification/requirements/"
        "requirements-milestone-ownership-v0.3.json"
    )
    proposals = load(
        "qualification/requirements/review/"
        "m0-explicit-ownership-proposals-v0.1.json"
    )
    results = load(
        "qualification/requirements/review/"
        "m0-explicit-results-v0.1.json"
    )

    source_ids = [
        e["requirement_id"] for e in source["entries"]
    ]
    require(
        len(source_ids) == len(set(source_ids)) == 1001,
        "INVALID_SOURCE_POPULATION",
    )

    explicit_m0 = {
        identity for identity in source_ids
        if identity.startswith("REQ-M0-")
    }

    proposed_ids = [
        e["requirement_id"] for e in proposals["entries"]
    ]
    result_ids = [
        e["requirement_id"] for e in results["entries"]
    ]

    require(
        len(proposed_ids) == len(set(proposed_ids)),
        "DUPLICATE_PROPOSAL",
    )
    require(
        len(result_ids) == len(set(result_ids)),
        "DUPLICATE_RESULT",
    )

    require(
        set(proposed_ids) == explicit_m0,
        "INCOMPLETE_EXPLICIT_M0_PROPOSALS",
    )
    require(
        set(result_ids) == explicit_m0,
        "INCOMPLETE_EXPLICIT_M0_RESULTS",
    )

    # Include every requirement already assigned to M0.
    approved_m0 = {
        e["requirement_id"]
        for e in ownership["entries"]
        if e.get("approved_first_mandatory_milestone") == "M0"
    }

    required = explicit_m0 | approved_m0

    require(
        required <= set(result_ids),
        "M0_OWNED_REQUIREMENT_WITHOUT_RESULT",
    )

    allowed = {"ENGINEERING_PASS", "BLOCKED"}

    for entry in results["entries"]:
        require(
            entry["engineering_result"] in allowed,
            "UNKNOWN_ENGINEERING_STATUS",
        )
        require(
            bool(entry["normative_statement"]),
            "MISSING_NORMATIVE_STATEMENT",
        )
        require(
            "formal_qualification_status" in entry,
            "MISSING_FORMAL_QUALIFICATION_STATUS",
        )

    print(f"EXPLICIT_M0_IDENTITIES={len(explicit_m0)}")
    print(f"APPROVED_M0_OWNERSHIP_IDENTITIES={len(approved_m0)}")
    print(f"RESULT_IDENTITIES={len(result_ids)}")
    print("KNOWN_M0_REQUIREMENT_COVERAGE=PASS")
    print("FORMAL_OWNERSHIP_COMPLETENESS=NOT_ESTABLISHED")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(
            "M0_REQUIREMENT_COVERAGE=FAIL:",
            exc,
            file=sys.stderr,
        )
        sys.exit(1)
