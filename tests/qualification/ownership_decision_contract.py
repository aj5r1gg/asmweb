#!/usr/bin/env python3
"""Adversarial integrity tests for ownership decision contract v0.1."""

import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "qualification/tools/ownership_decision_contract.py"

spec = importlib.util.spec_from_file_location(
    "ownership_contract_target", TOOL
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

baseline_bytes = module.CONTRACT.read_bytes()
baseline = module.strict_json(baseline_bytes)

result = module.validate(baseline_bytes)

if (
    result["contract_status"] != "DRAFT_UNADOPTED"
    or result["effective_approvals"] != 0
):
    raise SystemExit("baseline_acceptance=FAIL")

print("baseline_acceptance=PASS")

cases = [
    ("adopted_status", lambda d: d.update(
        contract_status="ADOPTED")),
    ("invented_authority", lambda d: d["authority_contract"].update(
        designated_approval_authority="invented")),
    ("invented_designation", lambda d: d["authority_contract"].update(
        designation_evidence_ref="invented")),
    ("invented_authentication", lambda d: d["authority_contract"].update(
        authentication_mechanism="unverified")),
    ("invented_verifier", lambda d: d["authority_contract"].update(
        authorisation_verifier="unverified")),
    ("self_declared_authority", lambda d: d["authority_contract"].update(
        self_declared_authority_is_sufficient=True)),
    ("approval_enabled", lambda d: d.update(
        approval_enabled=True)),
    ("effective_writes_enabled", lambda d: d.update(
        effective_writes_enabled=True)),
    ("false_authority_state", lambda d: d.update(
        authority_status="ESTABLISHED")),
    ("partial_effectiveness", lambda d: d["future_transaction_model"].update(
        partial_effectiveness_permitted=True)),
    ("publication_design_claim", lambda d: d["future_transaction_model"].update(
        publication_atomicity_design="implemented")),
    ("effective_transaction_claim", lambda d: d["future_transaction_model"].update(
        effective_transaction_implemented=True)),
    ("false_coverage", lambda d: d["coverage_contract"].update(
        coverage_complete=True)),
    ("false_approved_count", lambda d: d["coverage_contract"].update(
        approved_assignment_count=1)),
    ("false_unreviewed_count", lambda d: d["coverage_contract"].update(
        unreviewed_requirement_count=0)),
    ("qualification_status_mutation", lambda d: d["qualification_separation"].update(
        ownership_approval_changes_qualification_result=True)),
    ("false_closure", lambda d: d["qualification_separation"].update(
        m0_closure_status="PASS")),
    ("wrong_contract_identity", lambda d: d.update(
        contract_id="invented")),
    ("changed_source_ref", lambda d: d["controlled_baseline"].update(
        requirements_registry="unknown")),
    ("missing_control", lambda d: d["unresolved_controls"].pop()),
    ("additional_control", lambda d: d["unresolved_controls"].append(
        "UNREVIEWED")),
    ("unknown_field", lambda d: d.update(invented=True)),
]

passed = 0

for name, mutate in cases:
    candidate = copy.deepcopy(baseline)
    mutate(candidate)

    payload = (
        json.dumps(candidate, ensure_ascii=False, indent=2) + "\n"
    ).encode("utf-8")

    try:
        module.validate(payload)
    except module.ContractError:
        passed += 1
        print(f"{name}=REJECTED")
    else:
        raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

raw_cases = [
    ("duplicate_top_level_key",
     baseline_bytes.rstrip()[:-1] + b', "approval_enabled": false}'),
    ("duplicate_nested_key",
     baseline_bytes.replace(
         b'"approval_enabled": false',
         b'"approval_enabled": false, "approval_enabled": false',
         1,
     )),
    ("trailing_json",
     baseline_bytes + b'\n{}\n'),
    ("invalid_utf8",
     baseline_bytes + b'\xff'),
    ("nonfinite_json",
     baseline_bytes.rstrip()[:-1] + b', "invented": NaN}'),
]

for name, payload in raw_cases:
    try:
        module.validate(payload)
    except module.ContractError:
        passed += 1
        print(f"{name}=REJECTED")
    else:
        raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

total = len(cases) + len(raw_cases)

print(f"adversarial_cases_passed={passed}")
print(f"adversarial_cases_total={total}")

if passed != total:
    raise SystemExit("OWNERSHIP_DECISION_CONTRACT_ADVERSARIAL_TESTS=FAIL")

print("OWNERSHIP_DECISION_CONTRACT_ADVERSARIAL_TESTS=PASS")
