#!/usr/bin/env python3
"""AsmWeb M0 milestone ownership approval simulation.

Stage 1 is read-only and never establishes approval authority.
"""

import argparse
import json
import sys
from pathlib import Path
from hashlib import sha256

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "qualification/requirements"

PATHS = {
    "source": BASE / "requirements-source-v0.3.json",
    "membership": BASE / "requirements-membership-v0.3.json",
    "registry": BASE / "requirements-registry-v0.3.json",
    "ownership": BASE / "requirements-milestone-ownership-v0.3.json",
    "proposals": BASE / "m0-ownership-proposals-v0.3.json",
    "milestone": ROOT / "qualification/milestones/M0.json",
}

EXPECTED_HASHES = {
    "source": "aec927c00604e39ef69f4d355de570786bcff6bd0b2b727d44bfe6b19d279daf",
    "membership": "f755127d6311907c05f7fa178f67fe0f22fd27f16bbc5c36180a3584eda3f97e",
    "registry": "0cde3f41c499ff8b169408c0806878fe8e96445e8aab7bab844bbb1c6740bf2e",
    "ownership": "75801d3edc6478ea7cf227d7bb176325b1f46fe975ed743ce0e4ffdf768233ec",
    "proposals": "ef63381462544092fd1d743115df3496b9c303567b12c259d9d2649c760293c5",
}

IDS = [f"REQ-M0-{i:03d}" for i in range(1, 6)]

class SimulationError(Exception):
    pass

def require(condition, reason):
    if not condition:
        raise SimulationError(reason)

def load_strict(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise SimulationError("duplicate JSON key")
            result[key] = value
        return result

    def reject_constant(value):
        raise SimulationError("nonfinite JSON value")

    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=pairs,
            parse_constant=reject_constant,
        )
    except (OSError, UnicodeError, ValueError) as exc:
        raise SimulationError(str(exc)) from exc

def load_baseline():
    for name, expected in EXPECTED_HASHES.items():
        path = PATHS[name]
        require(
            sha256(path.read_bytes()).hexdigest() == expected,
            f"baseline integrity mismatch: {name}",
        )
    return {name: load_strict(path) for name, path in PATHS.items()}

def evaluate(data, requirement_id):
    """Return a hypothetical change set, never an effective approval."""

    require(
        type(requirement_id) is str and requirement_id in IDS,
        "unknown or unsupported M0 proposal identity",
    )

    source = data["source"]
    membership = data["membership"]
    registry = data["registry"]
    ownership = data["ownership"]
    proposals = data["proposals"]
    milestone = data["milestone"]

    ids = membership["requirement_ids"]

    require(len(ids) == 1001, "membership cardinality mismatch")
    require(len(set(ids)) == 1001, "duplicate membership identity")

    require(
        ids == [r["requirement_id"] for r in source["entries"]],
        "source membership mismatch",
    )
    require(
        ids == [r["id"] for r in registry["entries"]],
        "registry membership mismatch",
    )
    require(
        ids == [r["requirement_id"] for r in ownership["entries"]],
        "ownership membership mismatch",
    )

    require(
        registry["authoring_status"] == "DRAFT_PARTIAL_METADATA",
        "unexpected registry state",
    )
    require(
        ownership["authoring_status"] == "DRAFT_UNREVIEWED",
        "unexpected ownership state",
    )
    require(
        proposals["artifact_status"] == "DRAFT_PENDING_REVIEW",
        "unexpected proposal state",
    )
    require(
        proposals["coverage_status"] == "INCOMPLETE",
        "unsupported coverage claim",
    )

    require(
        proposals["approved_assignment_count"] == 0,
        "pre-existing proposal approval claim",
    )
    require(
        proposals["all_requirements_reviewed"] is False,
        "false complete-review claim",
    )
    require(
        proposals["target_milestone"] == "M0",
        "proposal milestone mismatch",
    )

    require(
        type(proposals["proposals"]) is list
        and len(proposals["proposals"]) == 5,
        "proposal cardinality mismatch",
    )
    require(
        [r["requirement_id"] for r in proposals["proposals"]] == IDS,
        "proposal identity/order mismatch",
    )
    require(
        [i for i in ids if i.startswith("REQ-M0-")] == IDS,
        "source M0 identity mismatch",
    )

    require(
        milestone["milestone_id"] == "M0",
        "milestone identity mismatch",
    )
    require(
        milestone["implementation_state"] == "BLOCKED"
        and milestone["closure_status"] == "BLOCKED",
        "milestone not blocked",
    )
    require(
        milestone["first_mandatory_requirement_refs"] == [],
        "existing milestone assignment conflicts with simulation",
    )

    require(
        all(
            entry["first_mandatory_milestone"] is None
            for entry in registry["entries"]
        ),
        "existing registry ownership assignments detected",
    )
    require(
        all(
            entry["review_status"] == "UNREVIEWED"
            and entry["proposed_first_mandatory_milestone"] is None
            and entry["approved_first_mandatory_milestone"] is None
            for entry in ownership["entries"]
        ),
        "existing ownership decisions detected",
    )

    # Whole-register checks, not merely selected-record checks.
    require(
        len(source["entries"]) == len(registry["entries"])
        == len(ownership["entries"]) == 1001,
        "cross-register cardinality mismatch",
    )

    for i, identity in enumerate(ids):
        s_all = source["entries"][i]
        r_all = registry["entries"][i]
        o_all = ownership["entries"][i]

        require(
            r_all["normative_text"] == s_all["normative_statement"],
            f"normative text mismatch: {identity}",
        )

        require(
            r_all["first_mandatory_milestone"] is None,
            f"existing registry assignment: {identity}",
        )

        require(
            o_all["review_status"] == "UNREVIEWED"
            and o_all["proposed_first_mandatory_milestone"] is None
            and o_all["approved_first_mandatory_milestone"] is None,
            f"existing ownership decision: {identity}",
        )

        expected_hints = (
            ["EXPLICIT_M0_NAMED_REQUIREMENT"]
            if identity.startswith("REQ-M0-") else []
        )

        require(
            o_all["discovery_hints"] == expected_hints,
            f"incorrect discovery hints: {identity}",
        )

        require(
            o_all["decision_rationale"] is None
            and o_all["decision_authority_refs"] == []
            and o_all["review_evidence_refs"] == [],
            f"unexpected ownership decision evidence: {identity}",
        )

    source_by_id = {
        e["requirement_id"]: e["normative_statement"]
        for e in source["entries"]
    }

    for expected_id, proposal in zip(
        IDS, proposals["proposals"]
    ):
        require(
            proposal["requirement_id"] == expected_id
            and proposal["source_requirement_id"] == expected_id
            and proposal["normative_text"] == source_by_id[expected_id]
            and proposal["candidate_first_mandatory_milestone"] == "M0"
            and proposal["proposal_status"] == "PENDING_REVIEW"
            and proposal["discovery_basis"]
            == "EXPLICIT_M0_NAMED_REQUIREMENT",
            f"proposal inconsistency: {expected_id}",
        )

        require(
            proposal["approved"] is False
            and proposal["approval_record_ref"] is None
            and proposal["review_evidence_refs"] == [],
            f"unsupported approval evidence: {expected_id}",
        )

    index = ids.index(requirement_id)

    s = source["entries"][index]
    r = registry["entries"][index]
    o = ownership["entries"][index]
    p = proposals["proposals"][IDS.index(requirement_id)]

    require(
        r["normative_text"] == s["normative_statement"],
        "source/registry normative text mismatch",
    )

    require(
        p["normative_text"] == s["normative_statement"],
        "proposal/source normative text mismatch",
    )

    require(
        p["requirement_id"] == requirement_id
        and p["source_requirement_id"] == requirement_id
        and p["candidate_first_mandatory_milestone"] == "M0"
        and p["discovery_basis"] == "EXPLICIT_M0_NAMED_REQUIREMENT",
        "proposal identity or discovery mismatch",
    )

    require(
        p["proposal_status"] == "PENDING_REVIEW"
        and p["approved"] is False
        and p["approval_record_ref"] is None
        and p["review_evidence_refs"] == [],
        "proposal contains an approval or evidence claim",
    )

    require(
        o["review_status"] == "UNREVIEWED",
        "ownership record already reviewed",
    )

    # These are projections, not edits to data or files.
    return {
        "schema_version": 1,
        "transaction_type": "M0_OWNERSHIP_APPROVAL_DRY_RUN",
        "requirement_id": requirement_id,
        "target_milestone": "M0",
        "transaction_status": "SIMULATION_ONLY",
        "authority_resolution": "NOT_ESTABLISHED",
        "effective_decision": "BLOCKED_NO_APPROVAL_AUTHORITY",
        "approval_record_created": False,
        "effective_assignment_created": False,
        "files_written": 0,
        "coverage_complete": False,
        "projected_changes": [
            {
                "record": "ownership",
                "field": "review_status",
                "from": "UNREVIEWED",
                "to": "APPROVED",
            },
            {
                "record": "ownership",
                "field": "approved_first_mandatory_milestone",
                "from": None,
                "to": "M0",
            },
            {
                "record": "requirements_registry",
                "field": "first_mandatory_milestone",
                "from": None,
                "to": "M0",
            },
            {
                "record": "M0",
                "field": "first_mandatory_requirement_refs",
                "from": [],
                "to": [requirement_id],
            },
        ],
        "unresolved_preconditions": [
            "APPROVAL_AUTHORITY_NOT_DEFINED",
            "APPROVAL_RECORD_NOT_ESTABLISHED",
            "AUTHORITY_REFERENCE_RESOLUTION_NOT_IMPLEMENTED",
            "CROSS_REGISTRY_COMMIT_NOT_IMPLEMENTED",
            "M0_OWNERSHIP_COVERAGE_INCOMPLETE",
        ],
        "qualification_status_unchanged": True,
        "milestone_closure_unchanged": True,
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--requirement",
        required=True,
        help="Explicit M0 proposal identity, e.g. REQ-M0-001",
    )
    args = parser.parse_args()

    try:
        result = evaluate(load_baseline(), args.requirement)
    except (SimulationError, OSError, KeyError, TypeError) as exc:
        print(f"M0_OWNERSHIP_DRY_RUN=FAIL: {exc}")
        return 1

    print(json.dumps(result, ensure_ascii=False, indent=2))
    print("M0_OWNERSHIP_DRY_RUN=PASS")
    print("M0_APPROVAL_STATUS=BLOCKED")
    print("M0_CLOSURE_STATUS=BLOCKED")
    return 0

if __name__ == "__main__":
    sys.exit(main())
