#!/usr/bin/env python3
"""Regression contract for the ten verification classes."""

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

VOCAB = ROOT / "qualification/schema/qualification-vocabulary.json"
FOUNDATION = ROOT / "qualification/tools/qualification_foundation.py"
QRR = ROOT / "qualification/qrr/qrr-v0.3.json"

EXPECTED = [
    "INSPECTION", "TEST", "CONFORMANCE",
    "INTEROPERABILITY", "BROWSER", "FUZZ",
    "RESOURCE", "BENCHMARK", "ENDURANCE", "ANALYSIS",
]

def check(condition, name):
    if not condition:
        raise SystemExit(f"{name}=FAIL")
    print(f"{name}=PASS")

vocabulary = json.loads(VOCAB.read_text(encoding="utf-8"))
qrr = json.loads(QRR.read_text(encoding="utf-8"))

spec = importlib.util.spec_from_file_location(
    "qualification_foundation_contract", FOUNDATION
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

check(
    vocabulary["verification_classes"] == EXPECTED,
    "TEN_CLASS_MACHINE_VOCABULARY"
)

check(
    module.EXPECTED_VERIFICATION_CLASSES == EXPECTED,
    "TEN_CLASS_VALIDATOR_VOCABULARY"
)

module.validate_vocabulary()
print("FOUNDATION_VOCABULARY_VALIDATION=PASS")

known = set(EXPECTED)

for entry in qrr["entries"]:
    classes = entry["verification_classes"]
    check_condition = (
        isinstance(classes, list)
        and all(
            isinstance(value, str) and value in known
            for value in classes
        )
    )
    if not check_condition:
        raise SystemExit(
            f"QRR_CLASS_COMPATIBILITY=FAIL: {entry['rule_id']}"
        )

for method, classes in qrr["verification_method_class_map"].items():
    if not isinstance(classes, list) or any(
        not isinstance(value, str) or value not in known
        for value in classes
    ):
        raise SystemExit(
            f"QRR_METHOD_CLASS_COMPATIBILITY=FAIL: {method}"
        )

print("QRR_CLASS_COMPATIBILITY=PASS")
print("QRR_METHOD_CLASS_COMPATIBILITY=PASS")
print("VERIFICATION_CLASS_CONTRACT=PASS")
