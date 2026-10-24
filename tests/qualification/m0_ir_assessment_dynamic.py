#!/usr/bin/env python3
"""Fail-closed qualification of dynamic M0 IR candidate selection."""

import copy
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import m0_normative_ir as ir


def require(condition, reason):
    if not condition:
        raise AssertionError(reason)


def main():
    original_path = ir.ASSESSMENT
    assessment, _ = ir.load(original_path)

    baseline = ir.build()

    require(baseline["entry_count"] == 144, "BASELINE_POPULATION")
    require(baseline["m0_candidate_count"] == 42, "BASELINE_CANDIDATES")
    require(baseline["unassessed_count"] == 102, "BASELINE_UNASSESSED")
    require(
        baseline["authoritative_ir_complete"] is False,
        "FALSE_BASELINE_AUTHORITY",
    )
    require(
        ir.OUTPUT.read_bytes() == ir.canonical(baseline),
        "PUBLISHED_IR_CHANGED",
    )

    candidate = next(
        i for i, entry in enumerate(assessment["entries"])
        if entry["m0_applicability"] == "CANDIDATE_APPLICABLE"
    )

    unapproved_candidate = next(
        i for i, entry in enumerate(assessment["entries"])
        if (
            entry["m0_applicability"] == "CANDIDATE_APPLICABLE"
            and entry["normative_approval"] is False
        )
    )

    unassessed = next(
        i for i, entry in enumerate(assessment["entries"])
        if entry["m0_applicability"] == "UNASSESSED"
    )

    with tempfile.TemporaryDirectory(prefix="asmweb-ir-test-") as directory:
        temporary = Path(directory) / "assessment.json"

        def derive(document):
            temporary.write_bytes(ir.canonical(document))
            ir.ASSESSMENT = temporary
            try:
                return ir.build()
            finally:
                ir.ASSESSMENT = original_path

        def rejected(name, document):
            try:
                derive(document)
            except (ValueError, KeyError, TypeError):
                print(name + "=REJECTED")
                return

            raise AssertionError(name + "_INCORRECTLY_ACCEPTED")

        changed = copy.deepcopy(assessment)
        changed["entries"][candidate]["m0_applicability"] = "UNASSESSED"
        changed["candidate_applicable_count"] = 41
        changed["unassessed_count"] = 103

        rejected("UNAUTHORISED_CANDIDATE_REMOVAL", changed)

        changed = copy.deepcopy(assessment)
        changed["entries"][unassessed][
            "m0_applicability"
        ] = "CANDIDATE_APPLICABLE"
        changed["candidate_applicable_count"] = 43
        changed["unassessed_count"] = 101
        rejected("UNREVIEWED_CANDIDATE_ADDITION", changed)

        changed = copy.deepcopy(assessment)
        changed["entries"][candidate]["m0_applicability"] = "APPROVED"
        rejected("INVALID_DISPOSITION", changed)

        changed = copy.deepcopy(assessment)
        changed["entries"][candidate]["m0_applicability"] = "UNASSESSED"
        rejected("STALE_COUNTS", changed)

        # Select a genuinely unapproved candidate. Mutating an
        # already-approved record to True would be a no-op and would
        # provide no adversarial coverage.
        changed = copy.deepcopy(assessment)

        require(
            changed["entries"][unapproved_candidate][
                "normative_approval"
            ] is False,
            "FORGED_APPROVAL_TARGET_ALREADY_APPROVED",
        )

        changed["entries"][unapproved_candidate][
            "normative_approval"
        ] = True

        rejected("FALSE_NORMATIVE_APPROVAL", changed)

        changed = copy.deepcopy(assessment)
        changed["entries"][1]["invariant_id"] = (
            changed["entries"][0]["invariant_id"]
        )
        rejected("DUPLICATE_IDENTITY", changed)

        changed = copy.deepcopy(assessment)
        changed["entries"].pop()
        rejected("MISSING_IDENTITY", changed)

    require(ir.ASSESSMENT == original_path, "ASSESSMENT_NOT_RESTORED")
    require(
        ir.OUTPUT.read_bytes() == ir.canonical(ir.build()),
        "BASELINE_DID_NOT_REPRODUCE",
    )

    print("PUBLISHED_IR=UNCHANGED")
    approved = sum(
        entry["normative_approval"] is True
        for entry in assessment["entries"]
    )
    require(approved == 36, "APPROVAL_BASELINE_MISMATCH")
    print(f"NORMATIVE_APPROVALS={approved}")
    print("M0_IR_DYNAMIC_ASSESSMENT=PASS")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, ValueError, KeyError, TypeError, OSError) as exc:
        print("M0_IR_DYNAMIC_ASSESSMENT=FAIL:", exc, file=sys.stderr)
        raise SystemExit(1)
