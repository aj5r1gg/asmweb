#!/usr/bin/env python3
"""Adversarial tests for draft ownership decision integrity."""

import copy
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "qualification/tools/requirements_ownership.py"

spec = importlib.util.spec_from_file_location("ownership_test_target", TOOL)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

baseline = module.authority.load(module.OWNERSHIP)
result = module.validate()

assert result["entry_count"] == 1001
assert result["unreviewed"] == 1001
assert result["explicit_m0_hints"] == 5
assert result["approved"] == 0

print("baseline_acceptance=PASS")

cases = [
    ("duplicate_identity", lambda d: d["entries"][1].update(
        requirement_id=d["entries"][0]["requirement_id"])),
    ("unknown_identity", lambda d: d["entries"][0].update(
        requirement_id="REQ-FAKE-999")),
    ("missing_entry", lambda d: d["entries"].pop()),
    ("extra_entry", lambda d: d["entries"].append(
        copy.deepcopy(d["entries"][0]))),
    ("reordered_entries", lambda d: d["entries"].__setitem__(
        slice(0, 2), list(reversed(d["entries"][:2])))),
    ("false_entry_count", lambda d: d.update(entry_count=1000)),
    ("boolean_entry_count", lambda d: d.update(entry_count=True)),
    ("wrong_authority", lambda d: d.update(
        requirements_authority="Uncontrolled")),
    ("wrong_membership_ref", lambda d: d.update(
        source_membership_ref="arbitrary.json")),
    ("wrong_source_ref", lambda d: d.update(
        source_text_ref="arbitrary.json")),
    ("wrong_registry_ref", lambda d: d.update(
        requirements_registry_ref="arbitrary.json")),
    ("invented_review_status", lambda d: d["entries"][0].update(
        review_status="COMPLETE")),
    ("unapproved_proposal", lambda d: d["entries"][0].update(
        review_status="PROPOSED",
        proposed_first_mandatory_milestone="M0")),
    ("unapproved_approval", lambda d: d["entries"][0].update(
        review_status="APPROVED",
        approved_first_mandatory_milestone="M0")),
    ("disputed_without_process", lambda d: d["entries"][0].update(
        review_status="DISPUTED")),
    ("invented_milestone", lambda d: d["entries"][0].update(
        approved_first_mandatory_milestone="M99")),
    ("invented_rationale", lambda d: d["entries"][0].update(
        decision_rationale="Unreviewed assertion")),
    ("invented_authority_ref", lambda d: d["entries"][0].update(
        decision_authority_refs=["unknown"])),
    ("invented_evidence_ref", lambda d: d["entries"][0].update(
        review_evidence_refs=["unknown"])),
    ("invented_review_notes", lambda d: d["entries"][0].update(
        review_notes="Unreviewed decision")),
    ("missing_explicit_m0_hint", lambda d: d["entries"][
        next(i for i, e in enumerate(d["entries"])
             if e["requirement_id"] == "REQ-M0-001")
    ].update(discovery_hints=[])),
    ("false_discovery_hint", lambda d: d["entries"][0].update(
        discovery_hints=["EXPLICIT_M0_NAMED_REQUIREMENT"])),
    ("authoritative_hints", lambda d: d["decision_model"].update(
        discovery_hints_are_authoritative=True)),
    ("approved_proposals", lambda d: d["decision_model"].update(
        proposals_are_approved_assignments=True)),
    ("disabled_individual_review", lambda d: d["decision_model"].update(
        requires_individual_review=False)),
    ("modified_milestones", lambda d: d["decision_model"].update(
        milestones=["M0"])),
    ("modified_status_model", lambda d: d["decision_model"].update(
        review_statuses=["UNREVIEWED"])),
    ("extra_entry_field", lambda d: d["entries"][0].update(
        invented=True)),
    ("missing_entry_field", lambda d: d["entries"][0].pop(
        "review_notes")),
    ("unsupported_authoring_status", lambda d: d.update(
        authoring_status="APPROVED")),
]

passed = 0

with TemporaryDirectory(prefix="asmweb-ownership-test-") as temporary:
    path = Path(temporary) / "ownership.json"

    for name, mutate in cases:
        candidate = copy.deepcopy(baseline)
        mutate(candidate)
        path.write_text(
            json.dumps(candidate, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

        try:
            module.validate(path)
        except module.OwnershipError:
            passed += 1
            print(f"{name}=REJECTED")
        except Exception as exc:
            raise SystemExit(
                f"{name}=UNCONTROLLED_EXCEPTION:"
                f"{type(exc).__name__}: {exc}"
            ) from exc
        else:
            raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

    # Raw JSON parser integrity, inherited from source authority.
    clean = json.dumps(baseline, ensure_ascii=False).encode("utf-8")
    raw_cases = [
        ("duplicate_json_key",
         clean.rstrip()[:-1] + b', "entry_count": 1001}'),
        ("trailing_document", clean + b'\n{}\n'),
        ("invalid_utf8", clean + b'\xff'),
        ("nonfinite_json",
         clean.rstrip()[:-1] + b', "unknown": NaN}'),
    ]

    for name, payload in raw_cases:
        path.write_bytes(payload)

        try:
            module.validate(path)
        except module.OwnershipError:
            passed += 1
            print(f"{name}=REJECTED")
        except Exception as exc:
            raise SystemExit(
                f"{name}=UNCONTROLLED_EXCEPTION:"
                f"{type(exc).__name__}: {exc}"
            ) from exc
        else:
            raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

print(f"adversarial_cases_passed={passed}")
print(f"adversarial_cases_total={len(cases) + len(raw_cases)}")
print("REQUIREMENTS_OWNERSHIP_ADVERSARIAL_TESTS=PASS")
