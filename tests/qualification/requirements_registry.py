#!/usr/bin/env python3
"""Adversarial tests for the AsmWeb Requirements Registry."""

import copy
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "qualification/tools/requirements_registry.py"

spec = importlib.util.spec_from_file_location("requirements_registry", TOOL)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

baseline = json.loads(module.REGISTRY.read_text(encoding="utf-8"))
result = module.validate()
assert result["entries"] == 1001
assert result["unresolved_entries"] == 1001
assert result["positive_results"] == 0
print("baseline_acceptance=PASS")

cases = [
    ("duplicate_id", lambda d: d["entries"][1].update(
        id=d["entries"][0]["id"])),
    ("unknown_id", lambda d: d["entries"][1].update(
        id="REQ-FAKE-999")),
    ("missing_entry", lambda d: d["entries"].pop()),
    ("extra_entry", lambda d: d["entries"].append(
        copy.deepcopy(d["entries"][0]))),
    ("reordered_entries", lambda d: d["entries"].__setitem__(
        slice(0, 2), list(reversed(d["entries"][:2])))),
    ("altered_normative_text", lambda d: d["entries"][0].update(
        normative_text="ALTERED")),
    ("altered_source", lambda d: d["entries"][0].update(
        source="uncontrolled.odt")),
    ("wrong_authority", lambda d: d.update(
        authority="Uncontrolled")),
    ("invented_status", lambda d: d["entries"][0].update(
        implementation_status="FINISHED")),
    ("boolean_entry_count", lambda d: d.update(
        entry_count=True)),
    ("unknown_verification_class", lambda d: d["entries"][0].update(
        verification_classes=["MAGIC"])),
    ("unknown_milestone", lambda d: d["entries"][0].update(
        first_mandatory_milestone="M99")),
    ("invalid_qualification_result", lambda d: d["entries"][0].update(
        qualification_status="QUALIFIED")),
    ("pass_without_evidence", lambda d: d["entries"][0].update(
        qualification_status="PASS")),
    ("qualified_without_pass", lambda d: d["entries"][0].update(
        implementation_status="QUALIFIED")),
    ("not_applicable_without_reason", lambda d: d["entries"][0].update(
        implementation_status="NOT_APPLICABLE")),
    ("duplicate_reference", lambda d: d["entries"][0].update(
        test_refs=["test-a", "test-a"])),
    ("invalid_reference_type", lambda d: d["entries"][0].update(
        evidence_refs=[42])),
    ("unknown_entry_field", lambda d: d["entries"][0].update(
        invented=True)),
    ("missing_entry_field", lambda d: d["entries"][0].pop(
        "priority")),
    ("unrecognised_authoring_status", lambda d: d.update(
        authoring_status="QUALIFIED")),
]

with TemporaryDirectory(prefix="asmweb-req-registry-") as temporary:
    path = Path(temporary) / "registry.json"
    passed = 0

    for name, mutate in cases:
        candidate = copy.deepcopy(baseline)
        mutate(candidate)
        path.write_text(
            json.dumps(candidate, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8"
        )

        try:
            module.validate(path)
        except module.RegistryError:
            passed += 1
            print(f"{name}=REJECTED")
        except Exception as exc:
            raise SystemExit(
                f"{name}=UNCONTROLLED_EXCEPTION:"
                f"{type(exc).__name__}: {exc}"
            ) from exc
        else:
            raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

    # A requirement can be implemented without being qualified.
    candidate = copy.deepcopy(baseline)
    candidate["entries"][0]["implementation_status"] = "IMPLEMENTED"
    candidate["entries"][0]["qualification_status"] = "NOT_RUN"
    path.write_text(
        json.dumps(candidate, ensure_ascii=False) + "\n",
        encoding="utf-8"
    )
    module.validate(path)
    print("implemented_not_qualified=ACCEPTED")

    # Justified NOT_APPLICABLE is representable, without claiming PASS.
    candidate = copy.deepcopy(baseline)
    candidate["entries"][0]["implementation_status"] = "NOT_APPLICABLE"
    candidate["entries"][0]["notes"] = (
        "Applicability determination requires independent review."
    )
    path.write_text(
        json.dumps(candidate, ensure_ascii=False) + "\n",
        encoding="utf-8"
    )
    module.validate(path)
    print("justified_not_applicable=ACCEPTED")

# Additional raw JSON and qualification-boundary cases.
raw_cases = [
    (
        "duplicate_top_level_key",
        lambda raw: raw.rstrip()[:-1]
        + b', "entry_count": 1001}',
    ),
    (
        "duplicate_nested_key",
        lambda raw: raw.replace(
            b'"qualification_status":',
            b'"qualification_status": "NOT_RUN", "qualification_status":',
            1,
        ),
    ),
    (
        "nonfinite_number",
        lambda raw: raw.rstrip()[:-1]
        + b', "unrecognised": NaN}',
    ),
    (
        "invalid_utf8",
        lambda raw: raw + b'\xff',
    ),
    (
        "trailing_document",
        lambda raw: raw + b'\n{}\n',
    ),
]

raw_passed = 0

with TemporaryDirectory(prefix="asmweb-req-registry-raw-") as temp:
    path = Path(temp) / "registry.json"
    clean = json.dumps(
        baseline, ensure_ascii=False
    ).encode("utf-8")

    for name, mutation in raw_cases:
        path.write_bytes(mutation(clean))

        try:
            module.validate(path)
        except (module.RegistryError, module.authority.AuthorityError):
            raw_passed += 1
            print(f"{name}=REJECTED")
        except Exception as exc:
            raise SystemExit(
                f"{name}=UNCONTROLLED_EXCEPTION:"
                f"{type(exc).__name__}: {exc}"
            ) from exc
        else:
            raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

    positive_cases = [
        ("draft_pass_with_evidence", "PASS", "NOT_STARTED"),
        ("draft_qualified_with_evidence", "PASS", "QUALIFIED"),
    ]

    for name, outcome, state in positive_cases:
        candidate = copy.deepcopy(baseline)
        entry = candidate["entries"][0]
        entry["qualification_status"] = outcome
        entry["implementation_status"] = state
        entry["evidence_refs"] = ["evidence/example.json"]
        entry["verification_classes"] = ["TEST"]
        entry["first_mandatory_milestone"] = "M0"

        path.write_text(
            json.dumps(candidate, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

        try:
            module.validate(path)
        except module.RegistryError:
            raw_passed += 1
            print(f"{name}=REJECTED")
        except Exception as exc:
            raise SystemExit(
                f"{name}=UNCONTROLLED_EXCEPTION:"
                f"{type(exc).__name__}: {exc}"
            ) from exc
        else:
            raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

print(f"original_mutation_tests={passed}")
print(f"additional_mutation_tests={raw_passed}")
print(f"total_mutation_tests={passed + raw_passed}")
print("REQUIREMENTS_REGISTRY_ADVERSARIAL_TESTS=PASS")
