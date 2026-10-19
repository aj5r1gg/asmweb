#!/usr/bin/env python3
"""Bounded MOT-shaped limit calculation.

This is a deterministic engine, not yet an authoritative
source of configured limits or an adopted Effective Limit Manifest.
"""

import json
import sys
import argparse
from hashlib import sha256

U64_MAX = (1 << 64) - 1

class LimitError(Exception):
    pass

def require(ok, reason):
    if not ok:
        raise LimitError(reason)

def u64(value, label):
    require(
        type(value) is int and 0 <= value <= U64_MAX,
        "invalid unsigned 64-bit value: " + label,
    )
    return value

def add(a, b):
    require(a <= U64_MAX - b, "addition overflow")
    return a + b

def multiply(a, b):
    require(b == 0 or a <= U64_MAX // b,
            "multiplication overflow")
    return a * b

FIELDS = (
    "limit_id",
    "maximum_count",
    "physical_capacity",
    "configured_capacity",
    "effective_stride_bytes",
    "pool_metadata_bytes",
    "mapping_overhead_bytes",
)

def calculate(document):
    require(type(document) is dict, "root must be object")
    require(set(document) == {"schema_version", "entries"},
            "unexpected root fields")
    require(type(document["schema_version"]) is int
            and document["schema_version"] == 1,
            "schema version")

    entries = document["entries"]
    require(type(entries) is list and entries,
            "nonempty entries required")
    require(len(entries) <= 65536,
            "entry count exceeds engine bound")

    seen = set()
    result = []
    total_direct = 0
    total_overhead = 0

    for record in entries:
        require(type(record) is dict, "entry type")
        require(set(record) == set(FIELDS), "entry fields")

        values = {
            key: u64(record[key], key)
            for key in FIELDS
        }

        identity = values["limit_id"]
        require(identity != 0, "zero limit identity")
        require(identity not in seen, "duplicate limit identity")
        seen.add(identity)

        maximum = values["maximum_count"]
        physical = values["physical_capacity"]
        configured = values["configured_capacity"]
        stride = values["effective_stride_bytes"]

        require(maximum > 0, "zero maximum")
        require(physical > 0, "zero physical capacity")
        require(configured > 0, "zero configured capacity")
        require(stride > 0, "zero stride")

        require(physical <= maximum,
                "physical capacity exceeds maximum")
        require(configured <= physical,
                "configured capacity exceeds physical")

        # This MVP derives bounded configured capacity.
        # It does not change any runtime MOT quantity.
        effective = min(maximum, physical, configured)

        direct = multiply(effective, stride)
        overhead = add(
            values["pool_metadata_bytes"],
            values["mapping_overhead_bytes"],
        )

        total_direct = add(total_direct, direct)
        total_overhead = add(total_overhead, overhead)

        result.append({
            "limit_id": identity,
            "effective_count": effective,
            "direct_capacity_bytes": direct,
            "overhead_bytes": overhead,
        })

    # Canonical order independent of input record order.
    result.sort(key=lambda item: item["limit_id"])

    grand_total = add(total_direct, total_overhead)

    payload = {
        "schema_version": 1,
        "document_type": "MOT_LIMIT_CALCULATION_PROJECTION",
        "authoritative_manifest": False,
        "entry_count": len(result),
        "entries": result,
        "total_direct_capacity_bytes": total_direct,
        "total_overhead_bytes": total_overhead,
        "total_projected_bytes": grand_total,
    }

    return payload

def canonical(obj):
    return (
        json.dumps(
            obj,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
            allow_nan=False,
        ) + "\n"
    ).encode("ascii")

def calculate_bytes(raw):
    def unique_pairs(pairs):
        obj = {}
        for key, value in pairs:
            require(key not in obj, "duplicate JSON key")
            obj[key] = value
        return obj

    def reject_constant(value):
        raise LimitError("nonfinite number: " + value)

    try:
        doc = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=unique_pairs,
            parse_constant=reject_constant,
        )
    except (ValueError, UnicodeError) as exc:
        raise LimitError("invalid JSON: " + str(exc)) from exc

    return calculate(doc)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "source",
        help="JSON input path; no production default is assumed",
    )
    args = parser.parse_args()

    try:
        with open(args.source, "rb") as handle:
            raw = handle.read()

        require(len(raw) <= 16 * 1024 * 1024,
                "input byte bound exceeded")

        result = calculate_bytes(raw)
        output = canonical(result)

    except (OSError, LimitError) as exc:
        print("EFFECTIVE_LIMIT_ENGINE=FAIL: " + str(exc),
              file=sys.stderr)
        return 1

    sys.stdout.buffer.write(output)
    return 0

if __name__ == "__main__":
    sys.exit(main())
