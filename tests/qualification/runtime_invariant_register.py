#!/usr/bin/env python3
"""Adversarial tests for AsmWeb READY-state invariant register."""

import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "qualification/tools/runtime_invariant_register.py"

spec = importlib.util.spec_from_file_location("ri_register", PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

baseline = module.validate()
baseline_bytes = module.serialize(baseline)

def rejected(payload):
    try:
        module.validate(payload)
    except (module.RegisterError, ValueError, UnicodeError):
        return True
    return False

mutations = [
    ("false_completion", lambda d:
        d.update(normative_invariant_register_complete=True)),
    ("false_blocker_resolution", lambda d:
        d.update(m0_blocker_resolved=True)),
    ("false_qualification", lambda d:
        d["entries"][0].update(qualification_result="PASS")),
    ("missing_entry", lambda d:
        d["entries"].pop()),
    ("duplicate_entry", lambda d:
        d["entries"].append(copy.deepcopy(d["entries"][0]))),
    ("wrong_count", lambda d:
        d.update(entry_count=10)),
    ("wrong_failure_code", lambda d:
        d["entries"][0].update(failure_code=99)),
    ("wrong_symbol", lambda d:
        d["entries"][0].update(implementation_symbol="invented")),
    ("wrong_test", lambda d:
        d["entries"][0].update(qualification_case_numbers=[99])),
    ("wrong_header_digest", lambda d:
        d["source_digests"].update(header_sha256="0" * 64)),
    ("wrong_source_digest", lambda d:
        d["source_digests"].update(implementation_sha256="0" * 64)),
    ("wrong_test_digest", lambda d:
        d["source_digests"].update(qualification_sha256="0" * 64)),
    ("extra_field", lambda d: d.update(invented=True)),
    ("changed_scope", lambda d: d.update(register_scope="M16")),
]

passed = 0

for name, mutation in mutations:
    candidate = copy.deepcopy(baseline)
    mutation(candidate)

    if not rejected(module.serialize(candidate)):
        raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

    passed += 1
    print(f"{name}=REJECTED")

raw = [
    baseline_bytes + b"{}",
    baseline_bytes + b"\xff",
    baseline_bytes.rstrip()[:-1] + b', "entry_count": 11}',
    baseline_bytes.rstrip()[:-1] + b', "invented": NaN}',
]

for index, payload in enumerate(raw, 1):
    if not rejected(payload):
        raise SystemExit(f"raw_case_{index}=INCORRECTLY_ACCEPTED")
    passed += 1
    print(f"raw_case_{index}=REJECTED")

# Exercise the parser against changed assembly definitions.
header = module.HEADER.read_bytes()
source = module.SOURCE.read_bytes()
qual = module.QUAL.read_bytes()

source_mutations = [
    (
        "changed_failure_code",
        header.replace(
            b"ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT                  1",
            b"ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT                  99",
            1,
        ),
        source,
        qual,
    ),
    (
        "missing_runtime_failure_path",
        header,
        source.replace(
            b".fail_process:",
            b".removed_process:",
            1,
        ),
        qual,
    ),
    (
        "missing_qualification_case",
        header,
        source,
        qual.replace(
            b"; CASE 10 ",
            b"; REMOVED 10 ",
            1,
        ),
    ),
]

for name, hb, sb, qb in source_mutations:
    if (hb, sb, qb) == (header, source, qual):
        raise SystemExit(f"{name}=MUTATION_NOT_APPLIED")

    try:
        module.generate(hb, sb, qb)
    except module.RegisterError:
        passed += 1
        print(f"{name}=REJECTED")
    else:
        raise SystemExit(f"{name}=INCORRECTLY_ACCEPTED")

if passed != 21:
    raise SystemExit(f"unexpected test count: {passed}")

print(f"adversarial_cases_passed={passed}")
print("adversarial_cases_total=21")
print("RUNTIME_INVARIANT_REGISTER_ADVERSARIAL=PASS")
