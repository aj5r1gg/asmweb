#!/usr/bin/env python3
"""Source-bound M0 requirements ownership review register.

Produces a complete, deterministic review worklist.
Does not decide applicability, assign milestones or grant authority.
"""

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "qualification/requirements"
OUTPUT = BASE / "review/m0-ownership-review-v0.1.json"


def load(filename):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate key: " + key)
            result[key] = value
        return result

    return json.loads(
        (BASE / filename).read_text(encoding="utf-8"),
        object_pairs_hook=unique,
        parse_constant=lambda value: (_ for _ in ()).throw(
            ValueError("nonfinite JSON: " + value)
        ),
    )


def canonical(document):
    return (
        json.dumps(
            document,
            sort_keys=True,
            ensure_ascii=False,
            separators=(",", ":"),
            allow_nan=False,
        ) + "\n"
    ).encode("utf-8")


def digest(filename):
    return hashlib.sha256(
        (BASE / filename).read_bytes()
    ).hexdigest()


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def build():
    source_file = "requirements-source-v0.3.json"
    member_file = "requirements-membership-v0.3.json"
    owner_file = "requirements-milestone-ownership-v0.3.json"
    registry_file = "requirements-registry-v0.3.json"

    source = load(source_file)
    members = load(member_file)
    ownership = load(owner_file)
    registry = load(registry_file)

    ids = members["requirement_ids"]
    statements = source["entries"]
    decisions = ownership["entries"]
    registry_entries = registry["entries"]

    require(
        len(ids) == len(set(ids)) == 1001,
        "invalid frozen membership",
    )
    require(
        members["requirement_count"] == 1001,
        "membership count mismatch",
    )
    require(
        source["requirement_count"] == 1001,
        "source count mismatch",
    )
    require(
        ownership["entry_count"] == 1001,
        "ownership count mismatch",
    )
    require(
        registry["entry_count"] == 1001,
        "registry count mismatch",
    )

    require(
        [e["requirement_id"] for e in statements] == ids,
        "source order/identity mismatch",
    )
    require(
        [e["requirement_id"] for e in decisions] == ids,
        "ownership order/identity mismatch",
    )
    require(
        [e["id"] for e in registry_entries] == ids,
        "registry order/identity mismatch",
    )

    entries = []

    for index, (identity, statement, owner, reg) in enumerate(
        zip(ids, statements, decisions, registry_entries), 1
    ):
        normative = statement["normative_statement"]

        require(
            isinstance(normative, str) and normative.strip(),
            "empty normative statement: " + identity,
        )

        require(
            reg["normative_text"] == normative,
            "registry/source disagreement: " + identity,
        )

        # The baseline has no approved assignments.
        # Any unexpected change must receive separate reconciliation.
        require(
            owner["review_status"] == "UNREVIEWED",
            "unexpected review status: " + identity,
        )
        require(
            owner["approved_first_mandatory_milestone"] is None,
            "unexpected approval: " + identity,
        )

        entries.append({
            "sequence": index,
            "requirement_id": identity,
            "normative_statement": normative,
            "current_review_status": owner["review_status"],
            "current_approved_milestone":
                owner["approved_first_mandatory_milestone"],
            "proposed_first_mandatory_milestone": None,
            "review_rationale": None,
            "candidate_implementation_refs": [],
            "candidate_qualification_refs": [],
            "review_evidence_refs": [],
            "review_disposition": "REQUIRES_INDIVIDUAL_REVIEW",
            "normative_approval": False,
        })

    return {
        "schema_version": 1,
        "document_type": "ASMWEB_M0_OWNERSHIP_REVIEW_WORKLIST",
        "status": "DRAFT_NOT_AUTHORITATIVE",
        "approval_enabled": False,
        "requirement_count": len(entries),
        "approved_decision_count": 0,
        "unreviewed_count": len(entries),
        "source_sha256": digest(source_file),
        "membership_sha256": digest(member_file),
        "ownership_sha256": digest(owner_file),
        "registry_sha256": digest(registry_file),
        "entries": entries,
    }


def verify():
    expected = build()
    require(
        OUTPUT.read_bytes() == canonical(expected),
        "review worklist differs from controlled inputs",
    )

    require(
        expected["requirement_count"] == 1001,
        "population error",
    )
    require(
        expected["approved_decision_count"] == 0,
        "false approval count",
    )
    require(
        all(not e["normative_approval"] for e in expected["entries"]),
        "false normative approval",
    )
    require(
        all(
            e["proposed_first_mandatory_milestone"] is None
            for e in expected["entries"]
        ),
        "fabricated proposal",
    )

    print("FROZEN_REQUIREMENTS=1001")
    print("SOURCE_TEXT_ALIGNMENT=VERIFIED")
    print("OWNERSHIP_ALIGNMENT=VERIFIED")
    print("REVIEW_WORKLIST_POPULATION=1001/1001")
    print("APPROVALS_INVENTED=0")
    print("M0_OWNERSHIP_REVIEW=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("build", "verify"))
    args = parser.parse_args()

    if args.action == "build":
        require(
            not OUTPUT.exists(),
            "review artifact already exists",
        )
        OUTPUT.write_bytes(canonical(build()))

    verify()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print("M0_OWNERSHIP_REVIEW=FAIL:", exc)
        raise SystemExit(1)
