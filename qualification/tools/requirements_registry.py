#!/usr/bin/env python3
"""Validate AsmWeb Requirements Registry v0.3 draft metadata."""

import argparse
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "qualification/requirements/requirements-registry-v0.3.json"
MEMBERSHIP = ROOT / "qualification/requirements/requirements-membership-v0.3.json"
SOURCE = ROOT / "qualification/requirements/requirements-source-v0.3.json"
VOCAB = ROOT / "qualification/schema/qualification-vocabulary.json"
AUTHORITY_TOOL = ROOT / "qualification/tools/requirements_authority.py"

spec = importlib.util.spec_from_file_location(
    "asmweb_registry_source_authority", AUTHORITY_TOOL
)
authority = importlib.util.module_from_spec(spec)
spec.loader.exec_module(authority)

class RegistryError(Exception):
    pass

def require(condition, message):
    if not condition:
        raise RegistryError(message)

FIELDS = {
    "id", "title", "normative_text", "source", "rationale",
    "verification_classes", "first_mandatory_milestone",
    "priority", "implementation_status", "qualification_status",
    "implementation_refs", "test_refs", "evidence_refs",
    "release_claim_refs", "notes",
}

ARRAYS = (
    "verification_classes", "implementation_refs", "test_refs",
    "evidence_refs", "release_claim_refs",
)

REFERENCE_ARRAYS = (
    "implementation_refs", "test_refs", "evidence_refs",
    "release_claim_refs",
)

NULLABLE_STRINGS = ("title", "rationale", "priority", "notes")
MILESTONES = {f"M{i}" for i in range(17)}

TOP_FIELDS = {
    "schema_version", "authority", "registry_name",
    "source_membership_authority", "source_text_authority",
    "authoring_status", "entry_count", "entries",
}

MEMBERSHIP_REF = (
    "qualification/requirements/requirements-membership-v0.3.json"
)
SOURCE_REF = (
    "qualification/requirements/requirements-source-v0.3.json"
)

def validate(path=REGISTRY):
    # The existing source-authority validator enforces independent
    # pinned digests, exact membership and frozen normative text.
    authority.validate(MEMBERSHIP, SOURCE)

    try:
        data = authority.load(path)
        membership = authority.load(MEMBERSHIP)
        source = authority.load(SOURCE)
        vocabulary = authority.load(VOCAB)
    except authority.AuthorityError as exc:
        raise RegistryError(str(exc)) from exc

    require(type(data) is dict, "registry root must be object")
    require(set(data) == TOP_FIELDS, "registry top-level fields mismatch")
    require(
        type(data["schema_version"]) is int
        and data["schema_version"] == 1,
        "registry schema version mismatch"
    )
    require(
        data["authority"] == source["authority"],
        "registry authority mismatch"
    )
    require(
        data["registry_name"] == "Requirements Registry",
        "registry name mismatch"
    )
    require(
        data["source_membership_authority"] == MEMBERSHIP_REF,
        "membership authority reference mismatch"
    )
    require(
        data["source_text_authority"] == SOURCE_REF,
        "source authority reference mismatch"
    )

    require(
        data["authoring_status"] == "DRAFT_PARTIAL_METADATA",
        "unrecognised or unsupported authoring status"
    )

    entries = data["entries"]
    ids = membership["requirement_ids"]
    frozen = source["entries"]

    require(type(entries) is list, "entries must be array")
    require(
        type(data["entry_count"]) is int
        and data["entry_count"] == 1001,
        "declared entry count mismatch"
    )
    require(len(entries) == 1001, "actual entry count mismatch")
    require(len(ids) == len(frozen) == 1001, "authority count mismatch")

    classes = vocabulary["verification_classes"]
    states = vocabulary["implementation_states"]
    results = vocabulary["qualification_results"]

    require(
        type(classes) is list
        and len(classes) == 10
        and len(set(classes)) == 10
        and "ANALYSIS" in classes,
        "ten-class vocabulary mismatch"
    )
    require(
        type(states) is list and "NOT_STARTED" in states,
        "implementation state vocabulary invalid"
    )
    require(
        type(results) is list and "NOT_RUN" in results
        and "PASS" in results,
        "qualification result vocabulary invalid"
    )

    unresolved = 0
    positive_results = 0

    for index, (entry, identity, frozen_entry) in enumerate(
        zip(entries, ids, frozen)
    ):
        label = f"entry {index} ({identity})"

        require(type(entry) is dict, f"{label}: expected object")
        require(set(entry) == FIELDS, f"{label}: field mismatch")

        require(entry["id"] == identity, f"{label}: identity mismatch")
        require(
            entry["normative_text"]
            == frozen_entry["normative_statement"],
            f"{label}: normative text mismatch"
        )
        require(
            entry["source"] == source["source_document"],
            f"{label}: source provenance mismatch"
        )

        for field in NULLABLE_STRINGS:
            value = entry[field]
            require(
                value is None
                or (
                    type(value) is str
                    and bool(value.strip())
                    and value == value.strip()
                ),
                f"{label}: invalid {field}"
            )

        for field in ARRAYS:
            values = entry[field]
            require(type(values) is list, f"{label}: {field} not array")
            require(
                all(type(value) is str and bool(value.strip())
                    and value == value.strip() for value in values),
                f"{label}: invalid {field} member"
            )
            require(
                len(values) == len(set(values)),
                f"{label}: duplicate {field} member"
            )

        require(
            set(entry["verification_classes"]) <= set(classes),
            f"{label}: unknown verification class"
        )

        milestone = entry["first_mandatory_milestone"]
        require(
            milestone is None or (
                type(milestone) is str and milestone in MILESTONES
            ),
            f"{label}: invalid milestone"
        )

        state = entry["implementation_status"]
        outcome = entry["qualification_status"]

        require(
            state is None or (
                type(state) is str and state in states
            ),
            f"{label}: invalid implementation status"
        )
        require(
            type(outcome) is str and outcome in results,
            f"{label}: invalid qualification result"
        )

        # Draft structural validation cannot certify evidence,
        # test applicability or cross-registry reference integrity.
        # Positive qualification requires a separate formal gate.
        require(
            outcome != "PASS" and state != "QUALIFIED",
            f"{label}: positive qualification prohibited in partial draft"
        )

        # Retain these defensive conditions for any future
        # explicitly governed, qualification-capable registry mode.
        if outcome == "PASS":
            positive_results += 1
            require(
                bool(entry["evidence_refs"]),
                f"{label}: PASS without evidence"
            )
            require(
                bool(entry["verification_classes"]),
                f"{label}: PASS without verification class"
            )
            require(
                milestone is not None,
                f"{label}: PASS without milestone assignment"
            )

        if state == "QUALIFIED":
            require(
                outcome == "PASS",
                f"{label}: QUALIFIED state without PASS"
            )
            require(
                bool(entry["evidence_refs"]),
                f"{label}: QUALIFIED state without evidence"
            )

        if state == "NOT_APPLICABLE":
            require(
                type(entry["notes"]) is str
                and bool(entry["notes"].strip()),
                f"{label}: NOT_APPLICABLE lacks justification"
            )

        # Do not assert that references exist merely because
        # they are syntactically well-formed. Cross-registry
        # resolution belongs to the Traceability Registry.
        if any(entry[field] is None for field in (
            "title", "rationale", "priority",
            "first_mandatory_milestone", "implementation_status"
        )) or not entry["verification_classes"]:
            unresolved += 1

    # Draft status cannot masquerade as completed metadata.
    require(
        unresolved > 0,
        "draft status inconsistent with fully populated metadata"
    )

    return {
        "entries": len(entries),
        "unresolved_entries": unresolved,
        "positive_results": positive_results,
        "authoring_status": data["authoring_status"],
        "cross_registry_resolution": "NOT_PERFORMED",
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=Path, default=REGISTRY)
    args = parser.parse_args()

    try:
        result = validate(args.registry)
    except (RegistryError, authority.AuthorityError, OSError,
            ValueError, TypeError) as exc:
        print(f"REQUIREMENTS_REGISTRY_VALIDATION=FAIL: {exc}")
        return 1

    for key, value in result.items():
        print(f"{key}={value}")

    print("REQUIREMENTS_REGISTRY_VALIDATION=PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
