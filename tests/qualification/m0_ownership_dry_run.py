#!/usr/bin/env python3
"""Adversarial tests for non-effective M0 ownership simulations."""

import copy
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

spec = importlib.util.spec_from_file_location(
    "m0_ownership_simulation_target",
    ROOT / "qualification/tools/m0_ownership_dry_run.py",
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

baseline = module.load_baseline()

def rejected(name, mutate, identity="REQ-M0-001"):
    candidate = copy.deepcopy(baseline)
    mutate(candidate)
    try:
        module.evaluate(candidate, identity)
    except module.SimulationError:
        print(f"{name}=REJECTED")
        return
    raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

for identity in module.IDS:
    result = module.evaluate(baseline, identity)
    assert result["transaction_status"] == "SIMULATION_ONLY"
    assert result["effective_assignment_created"] is False
    assert result["approval_record_created"] is False
    assert result["files_written"] == 0
    assert result["effective_decision"] == "BLOCKED_NO_APPROVAL_AUTHORITY"
    assert result["qualification_status_unchanged"] is True
    print(f"{identity}=SIMULATED")

rejected(
    "unknown_requirement",
    lambda d: None,
    "REQ-UNKNOWN-001",
)

rejected(
    "later_milestone_identity",
    lambda d: None,
    "REQ-M1-001",
)

rejected(
    "duplicate_membership",
    lambda d: d["membership"]["requirement_ids"].__setitem__(
        0, d["membership"]["requirement_ids"][1]
    ),
)

rejected(
    "changed_registry_text",
    lambda d: next(
        e for e in d["registry"]["entries"]
        if e["id"] == "REQ-M0-001"
    ).update(normative_text="Tampered"),
)

rejected(
    "changed_proposal_text",
    lambda d: d["proposals"]["proposals"][0].update(
        normative_text="Tampered"
    ),
)

rejected(
    "false_proposal_approval",
    lambda d: d["proposals"]["proposals"][0].update(
        approved=True
    ),
)

rejected(
    "false_approval_reference",
    lambda d: d["proposals"]["proposals"][0].update(
        approval_record_ref="invented"
    ),
)

rejected(
    "false_review_evidence",
    lambda d: d["proposals"]["proposals"][0].update(
        review_evidence_refs=["invented"]
    ),
)

rejected(
    "existing_registry_assignment",
    lambda d: next(
        e for e in d["registry"]["entries"]
        if e["id"] == "REQ-M0-001"
    ).update(first_mandatory_milestone="M1"),
)

rejected(
    "existing_ownership_approval",
    lambda d: next(
        e for e in d["ownership"]["entries"]
        if e["requirement_id"] == "REQ-M0-001"
    ).update(
        review_status="APPROVED",
        approved_first_mandatory_milestone="M0",
    ),
)

rejected(
    "existing_milestone_assignment",
    lambda d: d["milestone"].update(
        first_mandatory_requirement_refs=["REQ-M0-001"]
    ),
)

rejected(
    "false_complete_coverage",
    lambda d: d["proposals"].update(
        coverage_status="COMPLETE"
    ),
)

rejected(
    "false_all_reviewed",
    lambda d: d["proposals"].update(
        all_requirements_reviewed=True
    ),
)

rejected(
    "wrong_proposal_target",
    lambda d: d["proposals"].update(
        target_milestone="M1"
    ),
)

rejected(
    "altered_proposal_identity",
    lambda d: d["proposals"]["proposals"][0].update(
        source_requirement_id="REQ-M0-005"
    ),
)

rejected(
    "incorrect_milestone_state",
    lambda d: d["milestone"].update(
        closure_status="PASS"
    ),
)

rejected(
    "unrelated_registry_text",
    lambda d: next(
        e for e in d["registry"]["entries"]
        if e["id"] == "REQ-M0-005"
    ).update(normative_text="Corrupted"),
)

rejected(
    "unrelated_source_text",
    lambda d: next(
        e for e in d["source"]["entries"]
        if e["requirement_id"] == "REQ-M0-005"
    ).update(normative_statement="Corrupted"),
)

rejected(
    "unrelated_proposal_text",
    lambda d: d["proposals"]["proposals"][4].update(
        normative_text="Corrupted"
    ),
)

rejected(
    "unrelated_proposal_approved",
    lambda d: d["proposals"]["proposals"][4].update(
        approved=True
    ),
)

rejected(
    "unrelated_proposal_evidence",
    lambda d: d["proposals"]["proposals"][4].update(
        review_evidence_refs=["unverified"]
    ),
)

rejected(
    "unrelated_ownership_hints",
    lambda d: next(
        e for e in d["ownership"]["entries"]
        if e["requirement_id"] == "REQ-M0-005"
    ).update(discovery_hints=[]),
)

rejected(
    "unrelated_ownership_authority",
    lambda d: next(
        e for e in d["ownership"]["entries"]
        if e["requirement_id"] == "REQ-M0-005"
    ).update(decision_authority_refs=["unverified"]),
)

rejected(
    "unrelated_registry_assignment",
    lambda d: next(
        e for e in d["registry"]["entries"]
        if e["id"] == "REQ-M0-005"
    ).update(first_mandatory_milestone="M1"),
)

print("adversarial_cases_passed=24")
print("adversarial_cases_total=24")
print("M0_OWNERSHIP_DRY_RUN_ADVERSARIAL_TESTS=PASS")
