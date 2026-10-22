#!/usr/bin/env python3
"""Fail-closed behaviour checks for the M0 closure preflight."""

import copy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import m0_closure_gate as gate


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    original = gate.documents()

    baseline = gate.evaluate(original)
    baseline_ids = {identity for identity, _ in baseline}

    required = {
        "M0-BLOCKERS",
        "M0-IR-APPROVAL",
        "M0-IR-CONTENT",
        "M0-IR-AUTHORITY",
        "M0-LR-STATUS",
        "M0-LR-AUTHORITY",
        "M0-OWNERSHIP",
        "M0-AUTHORITY",
        "M0-ELM-ACCEPTANCE",
    }

    require(required <= baseline_ids, "BASELINE_BLOCKER_MISSING")
    # Unresolved future invariants must not themselves block M0 (§34).
    require(
        "M0-IR-APPLICABILITY" not in baseline_ids,
        "FUTURE_IR_INCORRECTLY_BLOCKS_M0",
    )
    # Explicit M0 membership may not be replaced by a convenient
    # single approved requirement to evade local closure obligations.
    partial = copy.deepcopy(original)
    partial["milestone"]["first_mandatory_requirement_refs"] = ["REQ-M0-004"]
    partial_ids = {identity for identity, _ in gate.evaluate(partial)}
    require("M0-OWNERSHIP" in partial_ids, "PARTIAL_M0_SCOPE_ACCEPTED")
    print("PARTIAL_M0_SCOPE=REJECTED")

    print("FUTURE_IR_SCOPE=NOT_A_M0_BLOCKER")

    # Final approval is deliberately after eligibility, not inside it.
    require(
        "M0-FINAL-ATTESTATION" not in baseline_ids,
        "CIRCULAR_CLOSURE_APPROVAL_BLOCKER",
    )
    no_diagnostics = copy.deepcopy(original)
    no_diagnostics["diagnostics_qualified"] = False
    no_diag_ids = {identity for identity, _ in gate.evaluate(no_diagnostics)}
    require(
        "M0-DIAGNOSTICS-ACCEPTANCE" in no_diag_ids,
        "FAILING_DIAGNOSTIC_QUALIFICATION_ACCEPTED",
    )
    dimension_error = copy.deepcopy(original)
    dimension_error["lr"]["entries"][0]["unit"] = "BYTES"
    invalid_ids = {identity for identity, _ in gate.evaluate(dimension_error)}
    require("M0-LR-DIMENSION" in invalid_ids, "INVALID_M0_LIMIT_DIMENSION_ACCEPTED")
    print("INVALID_M0_LIMIT_DIMENSION=REJECTED")

    print("FAILED_DIAGNOSTIC_QUALIFICATION=REJECTED")

    print("FINAL_APPROVAL_SEPARATE_FROM_ELIGIBILITY=PASS")

    print("UNRESOLVED_BASELINE=REJECTED")

    mutations = (
        ("false_milestone_label", "milestone",
         lambda d: d.update(closure_status="CLOSED")),
        ("false_ir_authority", "ir",
         lambda d: d.update(authoritative_ir_complete=True)),
        ("false_lr_authority", "lr",
         lambda d: d.update(authoritative_lr_complete=True)),
        ("false_approval_enablement", "authority",
         lambda d: d.update(approval_enabled=True)),
        ("false_ownership_approval", "ownership",
         lambda d: d["entries"][0].update(
             review_status="APPROVED",
             approved_first_mandatory_milestone="M0",
         )),
    )

    for name, member, mutation in mutations:
        changed = copy.deepcopy(original)
        mutation(changed[member])
        result = gate.evaluate(changed)

        require(bool(result), name + ":FALSE_CLOSURE")
        print(name + "=REJECTED")

    # The all-green-looking fixture must still reject an
    # unsupported ELM. Diagnostic testing is evaluated independently.
    changed = copy.deepcopy(original)

    changed["milestone"]["blocked_items"] = []
    changed["milestone"]["required_verification_refs"] = ["fixture"]
    changed["milestone"]["result_refs"] = ["fixture"]

    changed["assessment"]["unassessed_count"] = 0

    for entry in changed["assessment"]["entries"]:
        entry["m0_applicability"] = "CANDIDATE_APPLICABLE"
        entry["normative_approval"] = True

    for entry in changed["ir"]["entries"]:
        entry["status"] = "ACTIVE"
        entry["machine_expression"] = "fixture"
        entry["first_required_milestone"] = "M0"
        entry["evidence_refs"] = ["fixture"]
        entry["qualification_refs"] = ["fixture"]

    changed["ir"]["authoritative_ir_complete"] = True

    for entry in changed["lr"]["entries"]:
        entry["status"] = "ACTIVE"

    changed["lr"]["authoritative_lr_complete"] = True
    changed["configuration"]["normative_lr_complete"] = True

    for entry in changed["ownership"]["entries"]:
        entry["review_status"] = "APPROVED"
        entry["approved_first_mandatory_milestone"] = "M0"

    changed["authority"]["authority_status"] = "ESTABLISHED"
    changed["authority"]["approval_enabled"] = True

    remaining = {key for key, _ in gate.evaluate(changed)}

    require(
        "M0-ELM-ACCEPTANCE" in remaining,
        "UNSUPPORTED_ATTESTATION_WAS_ACCEPTED"
    )

    # Evidence references must resolve to real qualification artifacts.
    for bad_ref in ("fixture", "../outside", "/tmp/fake", "qualification/missing.json"):
        altered = copy.deepcopy(original)
        altered["milestone"]["required_verification_refs"] = [bad_ref]
        altered["milestone"]["result_refs"] = [bad_ref]
        found = {identity for identity, _ in gate.evaluate(altered)}
        require(
            {"M0-VERIFICATION-RECORD", "M0-RESULTS"} <= found,
            "UNRESOLVED_EVIDENCE_REFERENCE_ACCEPTED",
        )
    print("MISSING_OR_UNSAFE_EVIDENCE=REJECTED")
    accepted = copy.deepcopy(original)
    accepted["milestone"]["required_verification_refs"] = [
        "tests/qualification/m0_requirement_identity.py"
    ]
    accepted["milestone"]["result_refs"] = [
        "qualification/requirements/review/m0-explicit-results-v0.1.json"
    ]
    accepted_ids = {identity for identity, _ in gate.evaluate(accepted)}
    require(
        "M0-VERIFICATION-RECORD" not in accepted_ids
        and "M0-RESULTS" not in accepted_ids,
        "REAL_QUALIFICATION_EVIDENCE_REF_REJECTED",
    )
    print("EXISTING_QUALIFICATION_EVIDENCE_PATHS=ACCEPTED")



    # A forged adoption flag without reconciled LR data cannot pass ELM.
    tampered = copy.deepcopy(changed)
    tampered["configuration"]["authoritative_elm_adopted"] = True
    tampered["configuration"]["configuration"]["limits"][0][
        "configured_capacity"
    ] += 1
    remaining = {key for key, _ in gate.evaluate(tampered)}
    require("M0-ELM-ACCEPTANCE" in remaining, "TAMPERED_ELM_ACCEPTED")
    print("TAMPERED_ELM=REJECTED")

    print("UNSUPPORTED_AUTHORITY_ATTESTATIONS=REJECTED")
    print("M0_CLOSURE_GATE_ADVERSARIAL=PASS")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, TypeError, OSError) as exc:
        print("M0_CLOSURE_GATE_ADVERSARIAL=FAIL:", exc,
              file=sys.stderr)
        sys.exit(1)
