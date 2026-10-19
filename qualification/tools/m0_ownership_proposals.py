#!/usr/bin/env python3
"""Fail-closed validation of the five pending M0 ownership proposals."""

import argparse
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "qualification/requirements"

PROPOSAL = BASE / "m0-ownership-proposals-v0.3.json"
SOURCE = BASE / "requirements-source-v0.3.json"
MEMBERSHIP = BASE / "requirements-membership-v0.3.json"
REGISTRY = BASE / "requirements-registry-v0.3.json"
OWNERSHIP = BASE / "requirements-milestone-ownership-v0.3.json"
M0 = ROOT / "qualification/milestones/M0.json"

SOURCE_REF = "qualification/requirements/requirements-source-v0.3.json"
OWNERSHIP_REF = (
    "qualification/requirements/"
    "requirements-milestone-ownership-v0.3.json"
)

EXPECTED_IDS = [f"REQ-M0-{i:03d}" for i in range(1, 6)]

TOP_FIELDS = {
    "schema_version", "artifact_name", "requirements_authority",
    "source_authority_ref", "ownership_register_ref",
    "target_milestone", "artifact_status", "coverage_status",
    "proposal_count", "approved_assignment_count",
    "all_requirements_reviewed", "proposals",
}

ENTRY_FIELDS = {
    "requirement_id", "candidate_first_mandatory_milestone",
    "proposal_status", "normative_text", "source_authority_ref",
    "source_requirement_id", "discovery_basis",
    "review_rationale", "review_evidence_refs",
    "approval_record_ref", "approved", "review_notes",
}

RATIONALE = (
    "The normative requirement expressly identifies M0. "
    "Its first-mandatory milestone is proposed for review, "
    "not established by this artifact."
)

def import_tool(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

authority = import_tool(
    "proposal_source_authority",
    ROOT / "qualification/tools/requirements_authority.py"
)
registry_tool = import_tool(
    "proposal_registry",
    ROOT / "qualification/tools/requirements_registry.py"
)
ownership_tool = import_tool(
    "proposal_ownership",
    ROOT / "qualification/tools/requirements_ownership.py"
)

class ProposalError(Exception):
    pass

def require(condition, message):
    if not condition:
        raise ProposalError(message)

def validate(path=PROPOSAL):
    try:
        authority.validate(MEMBERSHIP, SOURCE)
        registry_tool.validate(REGISTRY)
        ownership_tool.validate(OWNERSHIP)

        document = authority.load(path)
        source = authority.load(SOURCE)
        membership = authority.load(MEMBERSHIP)
        milestone = authority.load(M0)
    except (
        authority.AuthorityError,
        registry_tool.RegistryError,
        ownership_tool.OwnershipError
    ) as exc:
        raise ProposalError(str(exc)) from exc

    require(type(document) is dict, "root must be object")
    require(set(document) == TOP_FIELDS, "root fields mismatch")

    fixed = {
        "schema_version": 1,
        "artifact_name": "M0 Requirements Ownership Proposals",
        "requirements_authority": source["authority"],
        "source_authority_ref": SOURCE_REF,
        "ownership_register_ref": OWNERSHIP_REF,
        "target_milestone": "M0",
        "artifact_status": "DRAFT_PENDING_REVIEW",
        "coverage_status": "INCOMPLETE",
        "proposal_count": 5,
        "approved_assignment_count": 0,
        "all_requirements_reviewed": False,
    }

    for field, expected in fixed.items():
        require(
            type(document[field]) is type(expected)
            and document[field] == expected,
            f"{field}: invalid"
        )

    source_entries = source["entries"]
    ids = membership["requirement_ids"]

    require(len(source_entries) == 1001, "source count mismatch")
    require(len(ids) == 1001, "membership count mismatch")
    require(
        [entry["requirement_id"] for entry in source_entries] == ids,
        "source membership mismatch"
    )

    require(
        [identity for identity in ids if identity.startswith("REQ-M0-")]
        == EXPECTED_IDS,
        "explicit M0 requirement set mismatch"
    )

    require(
        type(milestone) is dict
        and milestone.get("milestone_id") == "M0"
        and milestone.get("closure_status") == "BLOCKED"
        and milestone.get("first_mandatory_requirement_refs") == [],
        "unexpected M0 milestone state"
    )

    proposals = document["proposals"]
    require(type(proposals) is list, "proposals must be array")
    require(len(proposals) == 5, "proposal cardinality mismatch")

    source_by_id = {
        entry["requirement_id"]: entry["normative_statement"]
        for entry in source_entries
    }

    for index, (entry, identity) in enumerate(
        zip(proposals, EXPECTED_IDS)
    ):
        label = f"proposal {index} ({identity})"

        require(type(entry) is dict, f"{label}: expected object")
        require(set(entry) == ENTRY_FIELDS, f"{label}: fields mismatch")

        fixed_entry = {
            "requirement_id": identity,
            "candidate_first_mandatory_milestone": "M0",
            "proposal_status": "PENDING_REVIEW",
            "normative_text": source_by_id[identity],
            "source_authority_ref": SOURCE_REF,
            "source_requirement_id": identity,
            "discovery_basis": "EXPLICIT_M0_NAMED_REQUIREMENT",
            "review_rationale": RATIONALE,
            "review_evidence_refs": [],
            "approval_record_ref": None,
            "approved": False,
            "review_notes": None,
        }

        require(
            entry == fixed_entry,
            f"{label}: unsupported proposal mutation or approval"
        )

    return {
        "proposal_count": len(proposals),
        "pending_review": len(proposals),
        "approved_assignments": 0,
        "coverage_status": "INCOMPLETE",
        "approval_validation": "NOT_IMPLEMENTED",
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proposal", type=Path, default=PROPOSAL)
    args = parser.parse_args()

    try:
        result = validate(args.proposal)
    except (ProposalError, OSError, ValueError, TypeError) as exc:
        print(f"M0_OWNERSHIP_PROPOSAL_VALIDATION=FAIL: {exc}")
        return 1

    for key, value in result.items():
        print(f"{key}={value}")

    print("M0_OWNERSHIP_PROPOSAL_VALIDATION=PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
