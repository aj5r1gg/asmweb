#!/usr/bin/env python3
"""M0 production limit identity register derived from NASM authority."""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import production_limit_manifest as production

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "qualification/limits/m0-limit-register-v0.1.json"

# Deliberate, stable canonical identities for the nine existing
# M0 production MOT quantities. These are not numerical defaults.
# Changes require explicit review, not automatic renumbering.
IDENTITIES = (
    ("STARTUP_INFO", "LIM-MEM-001"),
    ("ENTROPY_BOOTSTRAP", "LIM-MEM-002"),
    ("CPU_INFO", "LIM-MEM-003"),
    ("MONOTONIC_TIME", "LIM-MEM-004"),
    ("PROCESS_RUNTIME", "LIM-MEM-005"),
    ("STARTUP_MEMORY_ACCOUNT", "LIM-MEM-006"),
    ("RUNTIME_RULE_STORAGE", "LIM-MEM-007"),
    ("REGISTRY_STORAGE", "LIM-MEM-008"),
    ("HTTP_REQUEST_BUFFER", "LIM-MEM-009"),
)


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def canonical(value):
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ) + "\n"
    ).encode("utf-8")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def derive():
    source = production.validate()

    definitions = source["definitions"]
    mot = source["mot_entries"]

    require(
        len(definitions) == len(mot) == len(IDENTITIES) == 9,
        "unexpected production limit population",
    )

    entries = []
    total = 0

    for index, ((suffix, identity), definition, item) in enumerate(
        zip(IDENTITIES, definitions, mot)
    ):
        symbol = "ASMWEB_PROD_LIMIT_" + suffix
        object_symbol = "ASMWEB_PROD_OBJECT_" + suffix

        require(
            definition["index"] == index
            and definition["limit_symbol"] == symbol
            and definition["object_symbol"] == object_symbol,
            "production limit identity/order mismatch",
        )

        require(
            definition["limit_id"] == item["limit_id"]
            and definition["object_id"] == item["object_id"],
            "MOT reference mismatch",
        )

        maximum = item["maximum_count"]
        physical = item["physical_capacity"]
        configured = item["configured_capacity"]
        stride = item["effective_stride_bytes"]

        require(
            all(
                type(n) is int and n > 0
                for n in (maximum, physical, configured, stride)
            ),
            "invalid numerical limit",
        )

        require(
            configured <= physical <= maximum,
            "invalid capacity ordering",
        )

        direct = configured * stride
        require(direct <= (1 << 64) - 1, "capacity overflow")
        total += direct

        entries.append({
            "limit_id": identity,
            "title": suffix.replace("_", " ").title()
                + " Capacity",
            "status": "PROVISIONAL",
            "limit_kind": "CAPACITY",
            "unit": "OBJECTS",
            "dimension": "COUNT",
            "scope": "M0_PRODUCTION_PROCESS",
            "applies_to_profiles": ["M0_PRODUCTION"],
            "runtime_limit_id": item["limit_id"],
            "runtime_limit_symbol": symbol,
            "runtime_object_id": item["object_id"],
            "runtime_object_symbol": object_symbol,
            "maximum_permitted": maximum,
            "physical_capacity": physical,
            "configured_value": configured,
            "effective_value": configured,
            "effective_stride_bytes": stride,
            "direct_capacity_bytes": direct,
            "value_provenance":
                "NASM_RESOLVED_PRODUCTION_MOT",
            "implementation_refs": [
                "src/runtime/production_registry.asm",
                "include/asmweb/production_registry.inc",
            ],
            "qualification_refs": [
                "qualify-production-registry",
                "qualify-production-limit-manifest",
                "qualify-mot-ceiling-integration",
            ],
            "resolution_milestone": "M0",
            "normative_adoption_status":
                "PENDING_AUTHORITY_RECONCILIATION",
        })

    require(
        total == source["M_direct_capacity_max"] == 3488,
        "production memory ceiling mismatch",
    )

    require(
        len({entry["limit_id"] for entry in entries}) == 9,
        "duplicate canonical identity",
    )

    return {
        "schema_version": 1,
        "document_type":
            "ASMWEB_M0_PRODUCTION_LIMIT_REGISTER_SUBSET",
        "source_specification":
            "AsmWeb — Invariants & Limits Register v0.3",
        "register_scope": "M0_PRODUCTION",
        "status": "PROVISIONAL_PENDING_NORMATIVE_RECONCILIATION",
        "full_normative_lr_complete": False,
        "authoritative_elm_adopted": False,
        "assembly_dependency_closure_sha256":
            source["assembly_dependency_closure_sha256"],
        "source_projection_sha256":
            sha(production.canonical(source)),
        "entry_count": len(entries),
        "entries": entries,
        "M_direct_capacity_max": total,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("publish", "verify"))
    args = parser.parse_args()

    try:
        expected = canonical(derive())

        if args.action == "publish":
            require(
                not OUTPUT.exists() and not OUTPUT.is_symlink(),
                "limit register already exists",
            )
            with OUTPUT.open("xb") as stream:
                stream.write(expected)
                stream.flush()
                import os
                os.fsync(stream.fileno())

        require(
            OUTPUT.read_bytes() == expected,
            "limit register differs from NASM source",
        )

        document = json.loads(expected)

        print("M0_CANONICAL_LIMIT_IDENTITIES=9")
        print(
            "M_DIRECT_CAPACITY_MAX="
            + str(document["M_direct_capacity_max"])
        )
        print("RUNTIME_LIMIT_MAPPING=VERIFIED")
        print("FULL_NORMATIVE_LR_COMPLETE=False")
        print("M0_PRODUCTION_LIMIT_REGISTER=PASS")
        return 0

    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(
            "M0_PRODUCTION_LIMIT_REGISTER=FAIL: " + str(exc),
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
