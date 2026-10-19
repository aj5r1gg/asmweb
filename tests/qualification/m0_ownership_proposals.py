#!/usr/bin/env python3
"""Adversarial validation of pending M0 ownership proposals."""

import copy
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "qualification/tools/m0_ownership_proposals.py"

spec = importlib.util.spec_from_file_location("m0_proposal_target", TOOL)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

baseline = module.authority.load(module.PROPOSAL)
result = module.validate()

if (
    result["proposal_count"] != 5
    or result["pending_review"] != 5
    or result["approved_assignments"] != 0
):
    raise SystemExit("baseline_acceptance=FAIL")

print("baseline_acceptance=PASS")

cases = [
    ("duplicate_identity", lambda d: d["proposals"][1].update(
        requirement_id="REQ-M0-001")),
    ("unknown_identity", lambda d: d["proposals"][0].update(
        requirement_id="REQ-FAKE-001")),
    ("missing_proposal", lambda d: d["proposals"].pop()),
    ("extra_proposal", lambda d: d["proposals"].append(
        copy.deepcopy(d["proposals"][0]))),
    ("reordered_proposals", lambda d: d["proposals"].reverse()),
    ("altered_normative_text", lambda d: d["proposals"][0].update(
        normative_text="Modified")),
    ("false_source_identity", lambda d: d["proposals"][0].update(
        source_requirement_id="REQ-M0-005")),
    ("unknown_source_ref", lambda d: d["proposals"][0].update(
        source_authority_ref="unknown.json")),
    ("wrong_target_milestone", lambda d: d.update(
        target_milestone="M1")),
    ("wrong_candidate_milestone", lambda d: d["proposals"][0].update(
        candidate_first_mandatory_milestone="M1")),
    ("false_review_status", lambda d: d["proposals"][0].update(
        proposal_status="APPROVED")),
    ("invented_approval", lambda d: d["proposals"][0].update(
        approved=True)),
    ("invented_approval_ref", lambda d: d["proposals"][0].update(
        approval_record_ref="unverified")),
    ("invented_review_evidence", lambda d: d["proposals"][0].update(
        review_evidence_refs=["unverified"])),
    ("invented_review_notes", lambda d: d["proposals"][0].update(
        review_notes="Approved")),
    ("wrong_rationale", lambda d: d["proposals"][0].update(
        review_rationale="Trust this proposal")),
    ("claimed_complete_coverage", lambda d: d.update(
        coverage_status="COMPLETE")),
    ("claimed_all_reviewed", lambda d: d.update(
        all_requirements_reviewed=True)),
    ("false_approval_count", lambda d: d.update(
        approved_assignment_count=1)),
    ("boolean_proposal_count", lambda d: d.update(
        proposal_count=True)),
    ("unknown_entry_field", lambda d: d["proposals"][0].update(
        invented=True)),
    ("missing_entry_field", lambda d: d["proposals"][0].pop(
        "approved")),
]

passed = 0

with TemporaryDirectory(prefix="asmweb-m0-proposal-") as temporary:
    path = Path(temporary) / "proposals.json"

    for name, mutate in cases:
        candidate = copy.deepcopy(baseline)
        mutate(candidate)
        path.write_text(
            json.dumps(candidate, ensure_ascii=False) + "\n",
            encoding="utf-8"
        )

        try:
            module.validate(path)
        except module.ProposalError:
            passed += 1
            print(f"{name}=REJECTED")
        except Exception as exc:
            raise SystemExit(
                f"{name}=UNCONTROLLED_EXCEPTION:"
                f"{type(exc).__name__}: {exc}"
            ) from exc
        else:
            raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

    clean = json.dumps(baseline, ensure_ascii=False).encode("utf-8")
    raw_cases = [
        ("duplicate_json_key",
         clean.rstrip()[:-1] + b', "proposal_count": 5}'),
        ("duplicate_nested_key",
         clean.replace(
             b'"approved": false',
             b'"approved": false, "approved": false',
             1
         )),
        ("trailing_document", clean + b'\n{}\n'),
        ("invalid_utf8", clean + b'\xff'),
        ("nonfinite_json",
         clean.rstrip()[:-1] + b', "unknown": NaN}'),
    ]

    for name, payload in raw_cases:
        path.write_bytes(payload)

        try:
            module.validate(path)
        except module.ProposalError:
            passed += 1
            print(f"{name}=REJECTED")
        except Exception as exc:
            raise SystemExit(
                f"{name}=UNCONTROLLED_EXCEPTION:"
                f"{type(exc).__name__}: {exc}"
            ) from exc
        else:
            raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

total = len(cases) + len(raw_cases)

print(f"adversarial_cases_passed={passed}")
print(f"adversarial_cases_total={total}")

if passed != total:
    raise SystemExit("M0_OWNERSHIP_PROPOSAL_ADVERSARIAL_TESTS=FAIL")

print("M0_OWNERSHIP_PROPOSAL_ADVERSARIAL_TESTS=PASS")
