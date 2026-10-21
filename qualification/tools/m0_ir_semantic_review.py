#!/usr/bin/env python3
"""Complete source-bound M0 invariant semantic-review baseline.

Separates engineering assessment from normative adoption.
The baseline contains no invented applicability or status approvals.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SOURCE = ROOT / "qualification/invariants/ir-normative-source-v0.3.json"
ASSESSMENT = ROOT / "qualification/invariants/m0-applicability-v0.1.json"
REGISTER = ROOT / "qualification/invariants/m0-normative-ir-v0.1.json"
OUTPUT = ROOT / "qualification/invariants/review/m0-ir-semantic-review-v0.1.json"


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (
        json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ) + "\n"
    ).encode("utf-8")


def load(path):
    def reject_duplicate(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key: " + key)
            result[key] = value
        return result

    raw = path.read_bytes()

    return json.loads(
        raw.decode("utf-8"),
        object_pairs_hook=reject_duplicate,
        parse_constant=lambda x: (_ for _ in ()).throw(
            ValueError("invalid JSON constant: " + x)
        ),
    ), raw


def build():
    source, source_raw = load(SOURCE)
    assessment, assessment_raw = load(ASSESSMENT)
    register, register_raw = load(REGISTER)

    normative = source["entries"]
    candidates = assessment["entries"]
    actual = register["entries"]

    require(
        len(normative) == len(candidates) == len(actual) == 144,
        "population mismatch",
    )

    require(
        source["normative_statement_count"] == 144,
        "source count mismatch",
    )

    require(
        assessment["source_sha256"] == sha(source_raw),
        "source digest mismatch",
    )

    entries = []

    for sequence, (s, a, r) in enumerate(
        zip(normative, candidates, actual), 1
    ):
        identity = s["invariant_id"]

        require(
            identity == a["invariant_id"] == r["invariant_id"],
            "identity/order disagreement",
        )

        require(
            s["normative_statement"] == r["normative_statement"],
            "normative statement disagreement",
        )

        require(
            a["normative_approval"] is False,
            "unexpected normative approval",
        )

        require(
            r["status"] is None,
            "unexpected authoritative status",
        )

        entries.append({
            "sequence": sequence,
            "invariant_id": identity,
            "normative_statement": s["normative_statement"],
            "engineering_applicability_candidate":
                a["m0_applicability"],
            "existing_implementation_refs":
                a["implementation_refs"],
            "existing_qualification_refs":
                a["qualification_refs"],
            "proposed_first_required_milestone": None,
            "proposed_applicability_disposition": None,
            "proposed_machine_expression": None,
            "proposed_detection_method": None,
            "proposed_failure_scope": None,
            "semantic_review_evidence_refs": [],
            "semantic_review_rationale": None,
            "review_status": "REQUIRES_INDIVIDUAL_SEMANTIC_REVIEW",
            "normative_approval": False,
        })

    require(
        len({e["invariant_id"] for e in entries}) == 144,
        "duplicate invariant identity",
    )

    return {
        "schema_version": 1,
        "document_type": "ASMWEB_M0_IR_SEMANTIC_REVIEW",
        "status": "DRAFT_NOT_AUTHORITATIVE",
        "source_sha256": sha(source_raw),
        "assessment_sha256": sha(assessment_raw),
        "register_sha256": sha(register_raw),
        "entry_count": 144,
        "individual_semantic_reviews_completed": 0,
        "normative_approvals": 0,
        "authoritative_ir_complete": False,
        "entries": entries,
    }


def verify():
    expected = build()

    require(
        OUTPUT.read_bytes() == canonical(expected),
        "controlled review differs from current IR inputs",
    )

    require(expected["entry_count"] == 144, "entry count")
    require(
        all(
            e["proposed_applicability_disposition"] is None
            and e["proposed_first_required_milestone"] is None
            and e["proposed_machine_expression"] is None
            and e["normative_approval"] is False
            for e in expected["entries"]
        ),
        "fabricated semantic review",
    )

    print("IR_NORMATIVE_IDENTITIES=144")
    print("IR_SOURCE_ALIGNMENT=VERIFIED")
    print("IR_SEMANTIC_REVIEW_POPULATION=144/144")
    print("INDIVIDUAL_SEMANTIC_REVIEWS=0")
    print("NORMATIVE_APPROVALS=0")
    print("M0_IR_SEMANTIC_REVIEW=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("build", "verify"))
    args = parser.parse_args()

    if args.action == "build":
        require(not OUTPUT.exists(), "output already exists")
        OUTPUT.write_bytes(canonical(build()))

    verify()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print("M0_IR_SEMANTIC_REVIEW=FAIL:", exc, file=sys.stderr)
        sys.exit(1)
