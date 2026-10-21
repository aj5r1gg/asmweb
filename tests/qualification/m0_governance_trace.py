#!/usr/bin/env python3
"""M0 governance evidence integrity; not normative approval."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import m0_normative_ir as ir

IDENTITIES = (
    "INV-GOV-001",
    "INV-GOV-002",
    "INV-GOV-006",
)

def require(ok, reason):
    if not ok:
        raise RuntimeError(reason)

def main():
    ir.verify()

    doc = json.loads(ir.OUTPUT.read_text())
    assessment = json.loads(ir.ASSESSMENT.read_text())

    records = {
        x["invariant_id"]: x for x in doc["entries"]
    }
    assessed = {
        x["invariant_id"]: x for x in assessment["entries"]
    }

    require(len(records) == 144, "IR_POPULATION")
    require(len(assessed) == 144, "ASSESSMENT_POPULATION")

    makefile = (ROOT / "Makefile").read_text()

    for identity in IDENTITIES:
        entry = records[identity]
        review = assessed[identity]

        require(bool(entry["implementation_refs"]),
                identity + ":MISSING_IMPLEMENTATION")
        require(bool(entry["qualification_refs"]),
                identity + ":MISSING_QUALIFICATION")

        require(entry["status"] is None,
                identity + ":FALSE_NORMATIVE_STATUS")
        require(review["normative_approval"] is False,
                identity + ":FALSE_APPROVAL")

        for reference in entry["implementation_refs"]:
            require((ROOT / reference).is_file(),
                    identity + ":MISSING_PATH:" + reference)

        for qualification in entry["qualification_refs"]:
            if qualification == "M0_FULL_SCHEMA_IR":
                require(
                    "m0_normative_ir.py verify"
                    in (ROOT / ".github/workflows/ci.yml").read_text(),
                    identity + ":MISSING_IR_GATE",
                )
            else:
                require(
                    qualification + ":" in makefile,
                    identity + ":MISSING_MAKE_TARGET:" + qualification,
                )

        print(identity + "=ENGINEERING_TRACE_VERIFIED")

    require(doc["authoritative_ir_complete"] is False,
            "FALSE_IR_COMPLETION")

    traced = sum(
        bool(e["implementation_refs"]) and
        bool(e["qualification_refs"])
        for e in records.values()
        if e["invariant_id"] in ir.CANDIDATES
    )

    require(traced >= 8,
            "ORIGINAL_CANDIDATE_TRACES_REGRESSED")

    print(f"M0_CANDIDATES_WITH_ENGINEERING_TRACE={traced}/42")
    print(f"M0_CANDIDATES_REMAINING={42 - traced}")
    print("NORMATIVE_IR_ADOPTION=PENDING")
    print("M0_GOVERNANCE_TRACE=PASS")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError) as exc:
        print("M0_GOVERNANCE_TRACE=FAIL:", exc, file=sys.stderr)
        sys.exit(1)
