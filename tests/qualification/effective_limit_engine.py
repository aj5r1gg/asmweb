#!/usr/bin/env python3
"""Adversarial qualification for MOT-shaped limit calculation."""

from copy import deepcopy
import importlib.util
import json
from pathlib import Path

path = (
    Path(__file__).resolve().parents[2]
    / "qualification/tools/effective_limit_engine.py"
)
spec = importlib.util.spec_from_file_location("engine", path)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)

FIXTURE = {
    "schema_version": 1,
    "entries": [
        {
            "limit_id": 2,
            "maximum_count": 10,
            "physical_capacity": 8,
            "configured_capacity": 5,
            "effective_stride_bytes": 64,
            "pool_metadata_bytes": 16,
            "mapping_overhead_bytes": 8,
        },
        {
            "limit_id": 1,
            "maximum_count": 4,
            "physical_capacity": 4,
            "configured_capacity": 2,
            "effective_stride_bytes": 128,
            "pool_metadata_bytes": 0,
            "mapping_overhead_bytes": 0,
        },
    ],
}

def source_bytes(d):
    return json.dumps(d, allow_nan=False).encode("utf-8")

def require(ok, message):
    if not ok:
        raise SystemExit(message)

baseline = engine.calculate_bytes(source_bytes(FIXTURE))

require(
    [x["limit_id"] for x in baseline["entries"]] == [1, 2],
    "canonical ordering",
)
require(
    baseline["total_direct_capacity_bytes"] == 576,
    "direct capacity arithmetic",
)
require(
    baseline["total_overhead_bytes"] == 24,
    "overhead arithmetic",
)
require(
    baseline["total_projected_bytes"] == 600,
    "total arithmetic",
)
require(
    baseline["authoritative_manifest"] is False,
    "false authoritative claim",
)

reordered = deepcopy(FIXTURE)
reordered["entries"].reverse()
require(
    engine.canonical(engine.calculate(reordered))
    == engine.canonical(baseline),
    "input reordering changed output",
)

print("BASELINE=PASS")
print("ARITHMETIC=PASS")
print("DETERMINISTIC_ORDERING=PASS")

def mutate(f):
    d = deepcopy(FIXTURE)
    f(d)
    return source_bytes(d)

cases = [
    ("duplicate_identity", mutate(
        lambda d: d["entries"][1].update(limit_id=2))),
    ("zero_identity", mutate(
        lambda d: d["entries"][0].update(limit_id=0))),
    ("negative_capacity", mutate(
        lambda d: d["entries"][0].update(configured_capacity=-1))),
    ("boolean_capacity", mutate(
        lambda d: d["entries"][0].update(configured_capacity=True))),
    ("fractional_capacity", mutate(
        lambda d: d["entries"][0].update(configured_capacity=1.5))),
    ("configured_exceeds_physical", mutate(
        lambda d: d["entries"][0].update(configured_capacity=9))),
    ("physical_exceeds_maximum", mutate(
        lambda d: d["entries"][0].update(physical_capacity=11))),
    ("zero_stride", mutate(
        lambda d: d["entries"][0].update(effective_stride_bytes=0))),
    ("zero_maximum", mutate(
        lambda d: d["entries"][0].update(maximum_count=0))),
    ("multiply_overflow", mutate(
        lambda d: d["entries"][0].update(
            effective_stride_bytes=(1 << 64)-1))),
    ("overhead_overflow", mutate(
        lambda d: d["entries"][0].update(
            pool_metadata_bytes=(1 << 64)-1))),
    ("total_overflow", mutate(
        lambda d: d["entries"][0].update(
            mapping_overhead_bytes=(1 << 64)-1))),
    ("missing_field", mutate(
        lambda d: d["entries"][0].pop("maximum_count"))),
    ("extra_field", mutate(
        lambda d: d["entries"][0].update(invented=1))),
    ("empty_entries", mutate(
        lambda d: d.update(entries=[]))),
    ("wrong_schema", mutate(
        lambda d: d.update(schema_version=2))),
    ("boolean_schema", mutate(
        lambda d: d.update(schema_version=True))),
    ("nonfinite", b'{"schema_version":1,"entries":NaN}'),
    ("trailing_document", source_bytes(FIXTURE) + b"{}"),
    ("invalid_utf8", source_bytes(FIXTURE) + b"\xff"),
    (
        "duplicate_json_key",
        source_bytes(FIXTURE).replace(
            b'"schema_version": 1,',
            b'"schema_version": 1, "schema_version": 1,',
            1,
        ),
    ),
]

passed = 0

for name, payload in cases:
    try:
        engine.calculate_bytes(payload)
    except engine.LimitError:
        print(name + "=REJECTED")
        passed += 1
    else:
        raise SystemExit(name + "=INCORRECTLY_ACCEPTED")

require(passed == 21, "adversarial count")
print(f"adversarial_passed={passed}")
print("EFFECTIVE_LIMIT_ENGINE_QUALIFICATION=PASS")
