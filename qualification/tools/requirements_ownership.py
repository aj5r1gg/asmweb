#!/usr/bin/env python3
"""Validate the AsmWeb v0.3 milestone ownership draft."""

import argparse
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "qualification/requirements"
OWNERSHIP = BASE / "requirements-milestone-ownership-v0.3.json"
MEMBERSHIP = BASE / "requirements-membership-v0.3.json"
SOURCE = BASE / "requirements-source-v0.3.json"
REGISTRY = BASE / "requirements-registry-v0.3.json"
M0 = ROOT / "qualification/milestones/M0.json"

AUTHORITY_TOOL = ROOT / "qualification/tools/requirements_authority.py"
REGISTRY_TOOL = ROOT / "qualification/tools/requirements_registry.py"

def import_tool(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

authority = import_tool("ownership_source_authority", AUTHORITY_TOOL)
registry_tool = import_tool("ownership_registry_validator", REGISTRY_TOOL)

class OwnershipError(Exception):
    pass

def require(value, message):
    if not value:
        raise OwnershipError(message)

TOP_FIELDS = {
    "schema_version", "register_name", "requirements_authority",
    "source_membership_ref", "source_text_ref",
    "requirements_registry_ref", "authoring_status",
    "decision_model", "entry_count", "entries",
}

MODEL_FIELDS = {
    "review_statuses", "milestones", "unresolved_ownership",
    "discovery_hints_are_authoritative",
    "proposals_are_approved_assignments",
    "requires_individual_review",
}

ENTRY_FIELDS = {
    "requirement_id", "review_status", "discovery_hints",
    "proposed_first_mandatory_milestone",
    "approved_first_mandatory_milestone",
    "decision_rationale", "decision_authority_refs",
    "review_evidence_refs", "review_notes",
}

STATUSES = ["UNREVIEWED", "PROPOSED", "APPROVED", "DISPUTED"]
MILESTONES = [f"M{i}" for i in range(17)]

PATHS = {
    "source_membership_ref":
        "qualification/requirements/requirements-membership-v0.3.json",
    "source_text_ref":
        "qualification/requirements/requirements-source-v0.3.json",
    "requirements_registry_ref":
        "qualification/requirements/requirements-registry-v0.3.json",
}

def validate(path=OWNERSHIP):
    try:
        authority.validate(MEMBERSHIP, SOURCE)
        registry_tool.validate(REGISTRY)

        document = authority.load(path)
        membership = authority.load(MEMBERSHIP)
        source = authority.load(SOURCE)
        registry = authority.load(REGISTRY)
        milestone = authority.load(M0)
    except (authority.AuthorityError,
            registry_tool.RegistryError) as exc:
        raise OwnershipError(str(exc)) from exc

    require(type(document) is dict, "document must be object")
    require(set(document) == TOP_FIELDS, "top-level field mismatch")

    require(
        type(document["schema_version"]) is int
        and document["schema_version"] == 1,
        "schema version mismatch"
    )
    require(
        document["register_name"]
        == "Requirements Milestone Ownership Decision Register",
        "register name mismatch"
    )
    require(
        document["requirements_authority"] == source["authority"],
        "requirements authority mismatch"
    )

    for field, expected in PATHS.items():
        require(
            type(document[field]) is str
            and document[field] == expected,
            f"{field}: provenance mismatch"
        )

    require(
        document["authoring_status"] == "DRAFT_UNREVIEWED",
        "unsupported authoring status"
    )

    model = document["decision_model"]
    require(type(model) is dict, "invalid decision model")
    require(set(model) == MODEL_FIELDS, "decision model field mismatch")
    require(
        model["review_statuses"] == STATUSES,
        "review status vocabulary mismatch"
    )
    require(
        model["milestones"] == MILESTONES,
        "milestone vocabulary mismatch"
    )
    require(
        model["unresolved_ownership"] is None,
        "unresolved ownership sentinel mismatch"
    )
    for key in (
        "discovery_hints_are_authoritative",
        "proposals_are_approved_assignments",
    ):
        require(model[key] is False, f"{key}: must be false")
    require(
        model["requires_individual_review"] is True,
        "individual review must be required"
    )

    require(type(milestone) is dict, "M0 record invalid")
    require(milestone.get("milestone_id") == "M0", "M0 identity mismatch")
    require(
        milestone.get("first_mandatory_requirement_refs") == [],
        "M0 contains assignments not represented by draft register"
    )

    ids = membership["requirement_ids"]
    source_entries = source["entries"]
    registry_entries = registry["entries"]
    entries = document["entries"]

    require(type(entries) is list, "entries must be array")
    require(
        type(document["entry_count"]) is int
        and document["entry_count"] == 1001,
        "declared entry count mismatch"
    )
    require(len(entries) == 1001, "actual entry count mismatch")
    require(
        len(ids) == len(source_entries) == len(registry_entries) == 1001,
        "authority/registry cardinality mismatch"
    )

    require(
        ids == [item["requirement_id"] for item in source_entries],
        "source order mismatch"
    )
    require(
        ids == [item["id"] for item in registry_entries],
        "registry order mismatch"
    )

    require(
        all(
            entry["first_mandatory_milestone"] is None
            for entry in registry_entries
        ),
        "registry milestone assignments are not reflected in draft"
    )

    explicit = 0

    for index, (entry, identity) in enumerate(zip(entries, ids)):
        label = f"entry {index} ({identity})"

        require(type(entry) is dict, f"{label}: expected object")
        require(set(entry) == ENTRY_FIELDS, f"{label}: field mismatch")
        require(
            type(entry["requirement_id"]) is str
            and entry["requirement_id"] == identity,
            f"{label}: identity/order mismatch"
        )
        require(
            entry["review_status"] == "UNREVIEWED",
            f"{label}: review transition unsupported in draft"
        )

        expected_hints = (
            ["EXPLICIT_M0_NAMED_REQUIREMENT"]
            if identity.startswith("REQ-M0-") else []
        )
        require(
            entry["discovery_hints"] == expected_hints,
            f"{label}: discovery hint mismatch"
        )

        explicit += bool(expected_hints)

        for key in (
            "proposed_first_mandatory_milestone",
            "approved_first_mandatory_milestone",
            "decision_rationale",
            "review_notes",
        ):
            require(
                entry[key] is None,
                f"{label}: unexpected {key}"
            )

        for key in ("decision_authority_refs", "review_evidence_refs"):
            require(
                type(entry[key]) is list and not entry[key],
                f"{label}: invented {key}"
            )

    require(explicit == 5, "explicit M0 hint count mismatch")

    return {
        "entry_count": len(entries),
        "unreviewed": len(entries),
        "explicit_m0_hints": explicit,
        "proposed": 0,
        "approved": 0,
        "authoring_status": "DRAFT_UNREVIEWED",
        "cross_registry_resolution": "NOT_PERFORMED",
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--register", type=Path, default=OWNERSHIP)
    args = parser.parse_args()

    try:
        result = validate(args.register)
    except (OwnershipError, OSError, ValueError, TypeError) as exc:
        print(f"REQUIREMENTS_OWNERSHIP_VALIDATION=FAIL: {exc}")
        return 1

    for key, value in result.items():
        print(f"{key}={value}")

    print("REQUIREMENTS_OWNERSHIP_VALIDATION=PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
