#!/usr/bin/env python3
"""Controlled full-schema IR from normative source and M0 assessment."""

import argparse
import hashlib
import json
import subprocess
import tempfile
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

# A signed assessment authorises recorded normative approvals, not merely
# milestone scope. An unsigned edit can never create an ACTIVE invariant.
APPROVAL_SIGNATURE = ASSESSMENT.with_suffix(ASSESSMENT.suffix + ".sig")
TRUSTED_KEY = Path.home() / ".config/asmweb/owner-public.pem"


def verify_approval_signature(assessment_bytes):
    require(APPROVAL_SIGNATURE.is_file() and not APPROVAL_SIGNATURE.is_symlink(),
            "normative approval signature missing or unsafe")
    require(TRUSTED_KEY.is_file() and not TRUSTED_KEY.is_symlink(),
            "independent owner trust anchor unavailable")
    with tempfile.TemporaryDirectory(prefix="asmweb-ir-") as directory:
        payload = Path(directory) / "assessment.json"
        payload.write_bytes(assessment_bytes)
        try:
            result = subprocess.run(
                ["openssl", "pkeyutl", "-verify", "-pubin", "-inkey",
                 str(TRUSTED_KEY), "-rawin", "-in", str(payload),
                 "-sigfile", str(APPROVAL_SIGNATURE)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=10, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError("normative signature verifier unavailable") from exc
        require(result.returncode == 0, "normative approval signature invalid")



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
    from m0_invariant_scope import verified_decisions
    scope_doc, scope_counts = verified_decisions()
    # The IR builder may be given temporary inputs by adversarial tests;
    # never verify one assessment and silently render another.
    from m0_invariant_scope import ASSESSMENT as SCOPE_ASSESSMENT
    require(assessment_bytes == SCOPE_ASSESSMENT.read_bytes(),
            "IR input differs from authenticated scope assessment")
    scope_rows = {row["invariant_id"]: row for row in scope_doc["entries"]}

    if any(row.get("normative_approval") is True
           for row in assessment["entries"]):
        verify_approval_signature(assessment_bytes)

    # An owner signature is necessary but insufficient: all associated
    # executable qualification targets must pass for any ACTIVE record.
    approved_targets = sorted({target
        for row in assessment["entries"] if row.get("normative_approval") is True
        for target in row.get("qualification_refs", [])})
    if approved_targets:
        makefile = (ROOT / "Makefile").read_text()
        import re
        declared = set(re.findall(r"^([A-Za-z][A-Za-z0-9_-]*):", makefile, re.M))
        require(set(approved_targets) <= declared,
                "unknown invariant qualification target")
        try:
            result = subprocess.run(
                ["make", "--no-print-directory", *approved_targets], cwd=ROOT,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=180, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError("invariant qualification execution unavailable") from exc
        require(result.returncode == 0,
                "approved invariant qualification execution failed")

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

        require(type(assessment_entry["normative_approval"]) is bool,
                "invalid normative approval type")
        if assessment_entry["normative_approval"]:
            require(candidate and scope_rows[identity]["decision"] == "M0_REQUIRED",
                    "approval outside authenticated M0 scope")


        record = {field: None for field in FIELDS}

        for field in LIST_FIELDS:
            record[field] = []

        implementation = assessment_entry["implementation_refs"]
        qualification = assessment_entry["qualification_refs"]
        if assessment_entry["normative_approval"]:
            require(bool(implementation) and bool(qualification),
                    "approved invariant missing executable mapping: " + identity)
            require(all(ref.startswith("qualify-") for ref in qualification),
                    "approved invariant has non-executable target: " + identity)

        for reference in implementation:
            require(
                (ROOT / reference).is_file(),
                "implementation reference missing: " + reference,
            )

        record.update({
            "invariant_id": identity,
            "title": identity,
            # Approval is accepted only from the signed assessment.
            "status": "ACTIVE" if assessment_entry["normative_approval"] else None,
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
                "Normative approval signed." if assessment_entry["normative_approval"]
                else "Normative status and qualification not approved.",
            ],
        })

        if assessment_entry["normative_approval"]:
            record["qualification_milestone"] = "M0"
            record["detection_method"] = "Executable qualification targets: " + ", ".join(qualification)
            record["evidence_refs"] = [ref for ref in implementation if ref.startswith(("tests/qualification/", "qualification/"))]
            require(bool(record["evidence_refs"]),
                    "approved invariant has no evidence artifact: " + identity)

        if candidate:
            decision = scope_rows[identity]
            if decision["decision"] != "REVIEW_REQUIRED":
                # Owner-signed scope is not an IR qualification. Preserve
                # status=None until the independent per-invariant contract
                # has been proved and normatively adopted.
                record["scope"] = (
                    "M0_FOUNDATION" if decision["decision"] == "M0_REQUIRED"
                    else "DEFERRED_FROM_M0"
                )
                record["first_required_milestone"] = (
                    decision["first_mandatory_milestone"]
                )
                if not assessment_entry["normative_approval"]:
                    record["evidence_refs"] = list(
                        decision["qualified_evidence_refs"]
                    )
                record["notes"].append(
                    "Owner-signed scope decision: " + decision["decision"]
                )
                record["notes"].append(decision["semantic_rationale"])

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
        require(record["status"] in (None, "ACTIVE"),
                "invalid normative status")
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
    print("M0_APPROVED_IR_RECORDS=" + str(sum(
        record["status"] == "ACTIVE" for record in document["entries"])))
    print("AUTHORITATIVE_IR_COMPLETE=" +
          str(document["authoritative_ir_complete"]))
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
