#!/usr/bin/env python3
"""Verify M0 production LR engineering evidence; never assert approval."""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import m0_normative_lr as lr

EXPECTED = set(lr.M0_EVIDENCE_REFS)

def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)

def main():
    lr.verify()

    register = json.loads(lr.OUTPUT.read_text())
    production = json.loads(
        (ROOT / "qualification/limits/m0-limit-register-v0.1.json")
        .read_text()
    )
    configuration = json.loads(
        (ROOT / "qualification/limits/m0-effective-configuration-v0.1.json")
        .read_text()
    )

    entries = register["entries"]
    production_ids = {
        e["limit_id"] for e in production["entries"]
    }

    require(len(entries) == 9, "WRONG_ENTRY_COUNT")
    require(
        {e["limit_id"] for e in entries} == production_ids,
        "LIMIT_IDENTITY_MISMATCH",
    )

    for entry in entries:
        require(
            set(entry["evidence_refs"]) == EXPECTED,
            "INCOMPLETE_EVIDENCE=" + entry["limit_id"],
        )
        require(
            entry["status"] == "PROVISIONAL",
            "UNAUTHORISED_LIMIT_STATUS",
        )
        for ref in entry["evidence_refs"]:
            target = (ROOT / ref).resolve()
            require(
                target.is_relative_to(ROOT.resolve()),
                "PATH_ESCAPE",
            )
            require(target.is_file(), "MISSING_ARTIFACT=" + ref)

    require(
        register["authoritative_lr_complete"] is False,
        "FALSE_NORMATIVE_COMPLETION",
    )
    require(
        bool(configuration.get("effective_configuration_sha256")),
        "CONFIGURATION_IDENTITY_MISSING",
    )

    print("CANONICAL_LIMIT_IDENTITIES=9/9")
    print("CONTROLLED_EVIDENCE_MAPPINGS=9/9")
    print("EVIDENCE_PATHS=VERIFIED")
    print("FALSE_APPROVAL_PREVENTION=PASS")
    print("M0_LR_EVIDENCE_QUALIFICATION=PASS")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError) as exc:
        print("M0_LR_EVIDENCE_QUALIFICATION=FAIL:", exc,
              file=sys.stderr)
        sys.exit(1)
