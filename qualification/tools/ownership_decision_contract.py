#!/usr/bin/env python3
"""Validate the intact, unadopted AsmWeb M0 ownership decision contract."""

import argparse
import json
import sys
from hashlib import sha256
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "qualification/requirements"

CONTRACT = BASE / "ownership-decision-contract-v0.1.json"

CONTRACT_DIGEST = (
    "398d9a6bd3f2a6197809f01af52bb68e82a9991ffa5217062581fbc94b4b4ecc"
)

BASELINES = {
    "requirements-source-v0.3.json":
        "aec927c00604e39ef69f4d355de570786bcff6bd0b2b727d44bfe6b19d279daf",
    "requirements-membership-v0.3.json":
        "f755127d6311907c05f7fa178f67fe0f22fd27f16bbc5c36180a3584eda3f97e",
    "requirements-registry-v0.3.json":
        "0cde3f41c499ff8b169408c0806878fe8e96445e8aab7bab844bbb1c6740bf2e",
    "requirements-milestone-ownership-v0.3.json":
        "75801d3edc6478ea7cf227d7bb176325b1f46fe975ed743ce0e4ffdf768233ec",
    "m0-ownership-proposals-v0.3.json":
        "ef63381462544092fd1d743115df3496b9c303567b12c259d9d2649c760293c5",
}

class ContractError(Exception):
    pass

def require(value, reason):
    if not value:
        raise ContractError(reason)

def strict_json(payload):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ContractError("duplicate JSON key")
            result[key] = value
        return result

    def reject_constant(value):
        raise ContractError("nonfinite JSON constant")

    try:
        return json.loads(
            payload.decode("utf-8"),
            object_pairs_hook=pairs,
            parse_constant=reject_constant,
        )
    except (UnicodeError, ValueError) as exc:
        raise ContractError(str(exc)) from exc

def validate(payload=None):
    if payload is None:
        payload = CONTRACT.read_bytes()

    require(type(payload) is bytes, "payload must be bytes")

    document = strict_json(payload)

    require(type(document) is dict, "root must be object")
    require(
        sha256(payload).hexdigest() == CONTRACT_DIGEST,
        "draft content differs from controlled baseline",
    )

    require(
        document["contract_id"] == "ASMWEB-M0-OWNERSHIP-APPROVAL-001",
        "contract identity mismatch",
    )
    require(document["contract_version"] == "0.1", "version mismatch")
    require(
        document["contract_status"] == "DRAFT_UNADOPTED",
        "contract unexpectedly adopted",
    )
    require(
        document["authority_status"] == "NOT_ESTABLISHED",
        "authority unexpectedly established",
    )

    for field in ("approval_enabled", "effective_writes_enabled"):
        require(document[field] is False, f"{field} must be false")

    authority = document["authority_contract"]

    for field in (
        "designated_approval_authority",
        "designation_evidence_ref",
        "authentication_mechanism",
        "authorisation_verifier",
        "revocation_and_supersession_policy",
    ):
        require(authority[field] is None, f"{field} unexpectedly assigned")

    require(
        authority["unresolved_authority_blocks_approval"] is True,
        "unresolved authority must block approval",
    )
    require(
        authority["self_declared_authority_is_sufficient"] is False,
        "self-declared authority prohibited",
    )

    transaction = document["future_transaction_model"]

    require(
        transaction["effective_transaction_implemented"] is False,
        "effective transaction unexpectedly enabled",
    )
    require(
        transaction["partial_effectiveness_permitted"] is False,
        "partial effectiveness prohibited",
    )
    require(
        transaction["publication_atomicity_design"] is None
        and transaction["publication_recovery_design"] is None,
        "unverified publication design",
    )

    coverage = document["coverage_contract"]

    require(
        type(coverage["unreviewed_requirement_count"]) is int
        and coverage["unreviewed_requirement_count"] == 1001,
        "unreviewed count mismatch",
    )
    require(
        type(coverage["pending_m0_proposal_count"]) is int
        and coverage["pending_m0_proposal_count"] == 5,
        "proposal count mismatch",
    )
    require(
        type(coverage["approved_assignment_count"]) is int
        and coverage["approved_assignment_count"] == 0,
        "unsupported approval count",
    )
    require(coverage["coverage_complete"] is False, "false coverage")

    separation = document["qualification_separation"]

    for field in (
        "ownership_approval_changes_implementation_state",
        "ownership_approval_changes_qualification_result",
        "ownership_approval_closes_milestone",
    ):
        require(separation[field] is False, field)

    require(
        separation["m0_closure_status"] == "BLOCKED",
        "false M0 closure claim",
    )

    for filename, expected in BASELINES.items():
        path = BASE / filename
        require(
            sha256(path.read_bytes()).hexdigest() == expected,
            f"protected baseline mismatch: {filename}",
        )

    source = strict_json(
        (BASE / "requirements-source-v0.3.json").read_bytes()
    )
    membership = strict_json(
        (BASE / "requirements-membership-v0.3.json").read_bytes()
    )
    registry = strict_json(
        (BASE / "requirements-registry-v0.3.json").read_bytes()
    )
    ownership = strict_json(
        (BASE / "requirements-milestone-ownership-v0.3.json").read_bytes()
    )
    proposals = strict_json(
        (BASE / "m0-ownership-proposals-v0.3.json").read_bytes()
    )
    m0 = strict_json(
        (ROOT / "qualification/milestones/M0.json").read_bytes()
    )

    ids = membership["requirement_ids"]

    require(len(ids) == len(set(ids)) == 1001, "membership mismatch")
    require(
        ids == [e["requirement_id"] for e in source["entries"]],
        "source membership mismatch",
    )
    require(
        ids == [e["id"] for e in registry["entries"]],
        "registry membership mismatch",
    )
    require(
        ids == [e["requirement_id"] for e in ownership["entries"]],
        "ownership membership mismatch",
    )

    require(
        all(e["review_status"] == "UNREVIEWED"
            for e in ownership["entries"]),
        "existing reviewed ownership",
    )
    require(
        all(e["first_mandatory_milestone"] is None
            for e in registry["entries"]),
        "existing milestone assignments",
    )
    require(
        proposals["approved_assignment_count"] == 0
        and proposals["coverage_status"] == "INCOMPLETE",
        "proposal state mismatch",
    )
    require(
        m0["closure_status"] == "BLOCKED"
        and m0["first_mandatory_requirement_refs"] == [],
        "M0 state mismatch",
    )

    require(
        document["controlled_baseline"]["requirements_authority"]
        == source["authority"],
        "source authority mismatch",
    )

    return {
        "contract_status": "DRAFT_UNADOPTED",
        "authority_status": "NOT_ESTABLISHED",
        "approval_enabled": False,
        "effective_writes_enabled": False,
        "unreviewed_requirements": 1001,
        "pending_m0_proposals": 5,
        "effective_approvals": 0,
        "m0_closure": "BLOCKED",
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, default=CONTRACT)
    args = parser.parse_args()

    try:
        result = validate(args.contract.read_bytes())
    except (ContractError, OSError, KeyError, TypeError) as exc:
        print(f"OWNERSHIP_DECISION_CONTRACT_VALIDATION=FAIL: {exc}")
        return 1

    for name, value in result.items():
        print(f"{name}={value}")

    print("OWNERSHIP_DECISION_CONTRACT_VALIDATION=PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
