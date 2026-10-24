#!/usr/bin/env python3
"""Controlled full-schema IR from normative source and M0 assessment."""

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SOURCE = ROOT / (
    "qualification/invariants/ir-normative-source-v0.3.json"
)
ASSESSMENT = ROOT / (
    "qualification/invariants/m0-applicability-v0.1.json"
)
OUTPUT = ROOT / (
    "qualification/invariants/m0-normative-ir-v0.1.json"
)

FIELDS = (
    "invariant_id title status normative_statement "
    "machine_expression scope epochs object_classes "
    "applies_to_profiles applies_to_features security_properties "
    "architecture_refs requirement_refs assembly_rule_refs "
    "runtime_rule_refs security_rule_refs protocol_rule_refs "
    "limit_refs implementation_refs test_refs qualification_refs "
    "evidence_refs detection_method violation_class failure_scope "
    "first_required_milestone qualification_milestone waiver_refs "
    "supersedes superseded_by notes"
).split()

LIST_FIELDS = set((
    "epochs object_classes applies_to_profiles "
    "applies_to_features security_properties architecture_refs "
    "requirement_refs assembly_rule_refs runtime_rule_refs "
    "security_rule_refs protocol_rule_refs limit_refs "
    "implementation_refs test_refs qualification_refs evidence_refs "
    "waiver_refs supersedes superseded_by notes"
).split())

# M0 candidate membership derives from controlled assessment.


# This extraction stops at the introductory clause. Do not present
# it as a complete normative statement.
INCOMPLETE_SOURCE_STATEMENTS = set()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(document):
    return (
        json.dumps(
            document,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ) + "\n"
    ).encode("utf-8")


def load(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key: " + key)
            result[key] = value
        return result

    raw = path.read_bytes()
    document = json.loads(
        raw.decode("utf-8"),
        object_pairs_hook=unique,
        parse_constant=lambda x: (_ for _ in ()).throw(
            ValueError("invalid JSON constant: " + x)
        ),
    )
    return document, raw


def build():
    source, source_bytes = load(SOURCE)
    assessment, assessment_bytes = load(ASSESSMENT)

    require(
        source["normative_statement_count"] == 144,
        "source count mismatch",
    )
    require(
        assessment["source_sha256"] == sha(source_bytes),
        "applicability assessment uses different source",
    )

    # Source-bound scope ledger is mandatory: changing a candidate's
    # applicability cannot silently turn it into a deferral.
    from m0_invariant_scope import LEDGER, load as scope_load, verify_document
    scope_doc, _ = scope_load(LEDGER)
    verify_document(scope_doc, source, source_bytes, assessment, assessment_bytes)

    statements = source["entries"]
    assessed = assessment["entries"]

    require(
        len(statements) == len(assessed) == 144,
        "IR population mismatch",
    )

    mapping = {
        record["invariant_id"]: record
        for record in assessed
    }

    require(
        len(mapping) == 144,
        "duplicate applicability identity",
    )

    allowed = {"CANDIDATE_APPLICABLE", "UNASSESSED"}

    require(
        len({e["invariant_id"] for e in assessed}) == 144,
        "duplicate assessment identity",
    )

    require(
        all(e["m0_applicability"] in allowed for e in assessed),
        "invalid applicability value",
    )

    candidates = {
        e["invariant_id"]
        for e in assessed
        if e["m0_applicability"] == "CANDIDATE_APPLICABLE"
    }

    require(
        assessment["candidate_applicable_count"] == len(candidates),
        "candidate count mismatch",
    )
    require(
        assessment["unassessed_count"] == 144 - len(candidates),
        "unassessed count mismatch",
    )

    entries = []
    seen = set()

    for statement in statements:
        identity = statement["invariant_id"]

        require(
            identity not in seen,
            "duplicate invariant identity",
        )
        seen.add(identity)

        require(
            identity in mapping,
            "missing applicability identity",
        )

        assessment_entry = mapping[identity]

        candidate = identity in candidates

        require(
            assessment_entry["m0_applicability"] in allowed,
            "invalid applicability",
        )

        require(
            assessment_entry["normative_approval"] is False,
            "unexpected normative approval",
        )

        record = {field: None for field in FIELDS}

        for field in LIST_FIELDS:
            record[field] = []

        implementation = assessment_entry["implementation_refs"]
        qualification = assessment_entry["qualification_refs"]

        for reference in implementation:
            require(
                (ROOT / reference).is_file(),
                "implementation reference missing: " + reference,
            )

        record.update({
            "invariant_id": identity,
            "title": identity,
            # No authoritative status decision has yet been made.
            # Null is a draft-only placeholder, not an IR status.
            "status": None,
            "normative_statement":
                statement["normative_statement"],
            "machine_expression": None,
            "scope": None,
            "epochs": [],
            "object_classes": [],
            "applies_to_profiles": [],
            "applies_to_features": [],
            "security_properties": [],
            "implementation_refs": implementation,
            "qualification_refs": qualification,
            "detection_method": None,
            "violation_class": None,
            "failure_scope": None,
            "first_required_milestone":
                assessment_entry["first_required_milestone"],
            "qualification_milestone": None,
            "notes": [
                "Applicability assessment: "
                + assessment_entry["m0_applicability"],
                "Normative status and qualification not approved.",
            ],
        })

        if candidate:
            record["notes"].append(
                "Existing implementation references are "
                "candidates for semantic traceability review; "
                "passing their tests is not complete invariant "
                "qualification."
            )

        if identity in INCOMPLETE_SOURCE_STATEMENTS:
            record["notes"].append(
                "Normative source extraction is incomplete: "
                "restore the entire governing statement before "
                "authoritative adoption."
            )

        require(
            set(record) == set(FIELDS),
            "missing required IR schema field",
        )

        entries.append(record)

    require(
        seen == set(mapping),
        "IR and applicability identity sets disagree",
    )

    require(
        candidates <= seen,
        "missing M0 candidate",
    )

    return {
        "schema_version": 1,
        "document_type": "ASMWEB_FULL_SCHEMA_INVARIANT_REGISTER_DRAFT",
        "source_specification":
            "AsmWeb — Invariants & Limits Register v0.3 §5",
        "source_sha256": sha(source_bytes),
        "applicability_assessment_sha256": sha(assessment_bytes),
        "status": "DRAFT_PENDING_NORMATIVE_RECONCILIATION",
        "authoritative_ir_complete": False,
        "entry_count": len(entries),
        "m0_candidate_count": len(candidates),
        "unassessed_count": len(entries) - len(candidates),
        "known_incomplete_source_statement_ids":
            sorted(INCOMPLETE_SOURCE_STATEMENTS),
        "entries": entries,
    }


def verify():
    document = build()

    require(
        OUTPUT.read_bytes() == canonical(document),
        "stored IR differs from controlled inputs",
    )

    require(
        document["entry_count"] == 144,
        "IR entry count",
    )

    for record in document["entries"]:
        require(
            set(record) == set(FIELDS),
            "IR schema mismatch",
        )
        require(
            record["status"] is None,
            "unapproved normative status",
        )
        for name in LIST_FIELDS:
            require(
                type(record[name]) is list,
                "incorrect list type: " + name,
            )

    print("IR_SCHEMA_FIELDS=" + str(len(FIELDS)))
    print("NORMATIVE_IDENTITIES=144")
    print("M0_IMPLEMENTATION_CANDIDATES="
          + str(document["m0_candidate_count"]))
    print("UNASSESSED_APPLICABILITY=" + str(document["unassessed_count"]))
    print("SOURCE_REPAIR_REQUIRED=" + str(len(INCOMPLETE_SOURCE_STATEMENTS)))
    print("AUTHORITATIVE_IR_COMPLETE=False")
    print("M0_FULL_SCHEMA_IR=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("publish", "verify"))
    args = parser.parse_args()

    try:
        if args.action == "publish":
            require(
                not OUTPUT.exists() and not OUTPUT.is_symlink(),
                "IR already exists",
            )
            OUTPUT.write_bytes(canonical(build()))

        verify()
        return 0

    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(
            "M0_FULL_SCHEMA_IR=FAIL: " + str(exc),
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
