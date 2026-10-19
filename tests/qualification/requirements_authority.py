#!/usr/bin/env python3
"""Adversarial validation of frozen Requirements authorities."""

import copy
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "qualification/tools/requirements_authority.py"

spec = importlib.util.spec_from_file_location("req_authority", TOOL)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

original_membership = module.load(module.MEMBERSHIP)
original_source = module.load(module.SOURCE)

cases = []


def case(name, target, mutation):
    cases.append((name, target, mutation))


def duplicate_id(data):
    data["requirement_ids"][1] = data["requirement_ids"][0]


def unknown_id(data):
    data["requirement_ids"][1] = "REQ-FAKE-999"


def reordered_ids(data):
    data["requirement_ids"][0:2] = reversed(data["requirement_ids"][0:2])


def altered_statement(data):
    data["entries"][0]["normative_statement"] += " altered"


def reordered_statements(data):
    data["entries"][0:2] = reversed(data["entries"][0:2])


def extra_entry(data):
    data["entries"].append(copy.deepcopy(data["entries"][0]))


case("duplicate_identity", "membership", duplicate_id)
case("unknown_identity", "membership", unknown_id)
case("reordered_membership", "membership", reordered_ids)
case("missing_membership", "membership",
     lambda d: d["requirement_ids"].pop())
case("membership_digest_tamper", "membership",
     lambda d: d.update(canonical_membership_sha256="0" * 64))
case("membership_provenance_tamper", "membership",
     lambda d: d.update(source_document_sha256="0" * 64))
case("membership_count_tamper", "membership",
     lambda d: d.update(requirement_count=1000))
case("membership_unknown_field", "membership",
     lambda d: d.update(unexpected=True))
case("membership_schema_tamper", "membership",
     lambda d: d.update(schema_version=2))
case("altered_statement", "source", altered_statement)
case("reordered_source", "source", reordered_statements)
case("duplicate_source_entry", "source", extra_entry)
case("missing_source_entry", "source",
     lambda d: d["entries"].pop())
case("source_digest_tamper", "source",
     lambda d: d.update(canonical_requirement_text_sha256="0" * 64))
case("source_provenance_tamper", "source",
     lambda d: d.update(source_document_sha256="0" * 64))
case("source_canonicalisation_tamper", "source",
     lambda d: d.update(canonicalisation="unspecified"))
case("source_authority_tamper", "source",
     lambda d: d.update(authority="Uncontrolled"))
case("source_missing_statement", "source",
     lambda d: d["entries"][0].pop("normative_statement"))
case("source_empty_statement", "source",
     lambda d: d["entries"][0].update(normative_statement=""))
case("source_extra_field", "source",
     lambda d: d["entries"][0].update(qualification_status="PASS"))
case("source_noncanonical_space", "source",
     lambda d: d["entries"][0].update(
         normative_statement=" " + d["entries"][0]["normative_statement"]))


def write_json(path, data):
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


passed = 0

with TemporaryDirectory(prefix="asmweb-req-authority-") as temporary:
    directory = Path(temporary)
    membership_path = directory / "membership.json"
    source_path = directory / "source.json"

    write_json(membership_path, original_membership)
    write_json(source_path, original_source)

    module.validate(membership_path, source_path)
    print("baseline_acceptance=PASS")

    for name, target, mutation in cases:
        membership = copy.deepcopy(original_membership)
        source = copy.deepcopy(original_source)
        mutation(membership if target == "membership" else source)

        write_json(membership_path, membership)
        write_json(source_path, source)

        try:
            module.validate(membership_path, source_path)
        except module.AuthorityError:
            print(f"{name}=REJECTED")
            passed += 1
        else:
            print(f"{name}=INCORRECTLY_ACCEPTED")
            raise SystemExit(1)

print(f"adversarial_cases_passed={passed}")
print(f"adversarial_cases_total={len(cases)}")

# Strict JSON parser adversarial cases use raw bytes so malformed
# encodings cannot fail inside the test harness before validation.
raw_cases = [
    (
        "duplicate_membership_key",
        "membership",
        lambda raw: raw.rstrip()[:-1]
        + b', "requirement_count": 1001}',
    ),
    (
        "duplicate_source_key",
        "source",
        lambda raw: raw.rstrip()[:-1]
        + b', "requirement_count": 1001}',
    ),
    (
        "duplicate_nested_entry_key",
        "source",
        lambda raw: raw.replace(
            b'"normative_statement":',
            b'"requirement_id": "REQ-GOV-001", "normative_statement":',
            1,
        ),
    ),
    (
        "nonfinite_source_value",
        "source",
        lambda raw: raw.rstrip()[:-1]
        + b', "unexpected": NaN}',
    ),
    (
        "trailing_json_document",
        "membership",
        lambda raw: raw + b'\n{}\n',
    ),
    (
        "invalid_utf8",
        "membership",
        lambda raw: raw + b'\xff',
    ),
    (
        "escaped_surrogate",
        "source",
        lambda raw: raw.replace(
            b'"normative_statement": "',
            b'"normative_statement": "\\ud800',
            1,
        ),
    ),
]

raw_passed = 0

with TemporaryDirectory(prefix="asmweb-req-json-hardening-") as temporary:
    directory = Path(temporary)
    mp = directory / "membership.json"
    sp = directory / "source.json"

    clean_membership = json.dumps(
        original_membership, ensure_ascii=False
    ).encode("utf-8")

    clean_source = json.dumps(
        original_source, ensure_ascii=False
    ).encode("utf-8")

    for name, target, mutation in raw_cases:
        mb = clean_membership
        sb = clean_source

        if target == "membership":
            mb = mutation(mb)
        else:
            sb = mutation(sb)

        mp.write_bytes(mb)
        sp.write_bytes(sb)

        try:
            module.validate(mp, sp)
        except module.AuthorityError:
            print(f"{name}=REJECTED")
            raw_passed += 1
        except Exception as exc:
            raise SystemExit(
                f"{name}=UNCONTROLLED_EXCEPTION:{type(exc).__name__}: {exc}"
            ) from exc
        else:
            raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

print(f"raw_adversarial_cases_passed={raw_passed}")
print(f"raw_adversarial_cases_total={len(raw_cases)}")
print(f"total_adversarial_cases={passed + raw_passed}")
print("REQUIREMENTS_AUTHORITY_ADVERSARIAL_TESTS=PASS")
