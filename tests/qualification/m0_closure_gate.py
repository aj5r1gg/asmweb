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
        "M0-DIAGNOSTICS-ACCEPTANCE",
        "M0-FINAL-ATTESTATION",
    }

    require(required <= baseline_ids, "BASELINE_BLOCKER_MISSING")
    # Unresolved future invariants must not themselves block M0 (§34).
    require(
        "M0-IR-APPLICABILITY" not in baseline_ids,
        "FUTURE_IR_INCORRECTLY_BLOCKS_M0",
    )
    print("FUTURE_IR_SCOPE=NOT_A_M0_BLOCKER")

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
    # unsupported ELM, diagnostic and authority attestation.
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
        {"M0-ELM-ACCEPTANCE",
         "M0-DIAGNOSTICS-ACCEPTANCE",
         "M0-FINAL-ATTESTATION"} <= remaining,
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

    print("UNSUPPORTED_AUTHORITY_ATTESTATIONS=REJECTED")
    print("M0_CLOSURE_GATE_ADVERSARIAL=PASS")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, TypeError, OSError) as exc:
        print("M0_CLOSURE_GATE_ADVERSARIAL=FAIL:", exc,
              file=sys.stderr)
        sys.exit(1)
