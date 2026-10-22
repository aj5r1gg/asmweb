#!/usr/bin/env python3
"""M0 full-schema Limit Register, backed by production NASM authority."""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import m0_limit_register as production_lr

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "qualification/limits/m0-normative-lr-v0.1.json"

FIELDS = (
    "limit_id title status limit_kind deadline_kind rate_semantics "
    "quantity unit dimension scope resource_class "
    "applies_to_profiles applies_to_features value_class "
    "configured_value effective_value minimum_permitted "
    "maximum_permitted default_value expression rounding_semantics "
    "alias_of provenance standards_refs protocol_constraint "
    "platform_constraint provider_constraint build_constraint "
    "dependency_refs reserve_refs pressure_refs capacity_refs "
    "quiescent_baseline quiescence_classification_refs "
    "architecture_refs requirement_refs runtime_rule_refs "
    "security_rule_refs protocol_rule_refs mot_refs rct_refs "
    "implementation_refs test_refs qualification_refs evidence_refs "
    "boundary_behaviour over_limit_behaviour first_required_milestone "
    "resolution_milestone qualification_milestone waiver_refs "
    "supersedes superseded_by notes"
).split()

# Controlled implementation-evidence artifacts, not normative approval.
# Each entry is derived from the same NASM-backed production register.
M0_EVIDENCE_REFS = (
    "qualification/limits/m0-limit-register-v0.1.json",
    "qualification/limits/m0-effective-configuration-v0.1.json",
)

LIST_FIELDS = set((
    "applies_to_profiles applies_to_features standards_refs "
    "dependency_refs reserve_refs pressure_refs capacity_refs "
    "quiescence_classification_refs architecture_refs requirement_refs "
    "runtime_rule_refs security_rule_refs protocol_rule_refs "
    "mot_refs rct_refs implementation_refs test_refs "
    "qualification_refs evidence_refs waiver_refs supersedes "
    "superseded_by notes"
).split())


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def canonical(value):
    return (
        json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ) + "\n"
    ).encode("utf-8")


def sha(value):
    return hashlib.sha256(value).hexdigest()


def validate_m0_dimensions(entry):
    """M0 production MOT instance capacities are COUNT, in OBJECTS.

    Do not accept a different unit/dimension by coincidence merely
    because the numerical capacities happen to match.
    """
    require(
        (
            entry.get("limit_kind"),
            entry.get("quantity"),
            entry.get("unit"),
            entry.get("dimension"),
        ) == (
            "CAPACITY", "CONCURRENT_OBJECT_INSTANCES", "OBJECTS", "COUNT"
        ),
        "invalid dimensional or quantity semantics",
    )
    require(
        entry.get("rounding_semantics") == "EXACT_INTEGER"
        and entry.get("expression") is None,
        "unsupported rounded or derived M0 capacity expression",
    )
    for name in ("configured_value", "effective_value", "maximum_permitted"):
        value = entry.get(name)
        require(
            type(value) is int and 0 <= value <= (1 << 64) - 1,
            "invalid integer capacity: " + name,
        )
    require(
        0 < entry["configured_value"]
        == entry["effective_value"]
        <= entry["maximum_permitted"],
        "inconsistent M0 capacity bounds",
    )


def build():
    # This file remains the one numerical authority for the M0
    # production subset, itself derived from NASM.
    existing = production_lr.derive()
    source_bytes = production_lr.canonical(existing)

    require(
        production_lr.OUTPUT.read_bytes() == source_bytes,
        "production Limit Register is stale",
    )

    entries = []

    for item in existing["entries"]:
        record = {field: None for field in FIELDS}

        for field in LIST_FIELDS:
            record[field] = []

        record.update({
            "limit_id": item["limit_id"],
            "title": item["title"],
            "status": "PROVISIONAL",
            "limit_kind": "CAPACITY",
            "deadline_kind": None,
            "rate_semantics": None,
            "quantity": "CONCURRENT_OBJECT_INSTANCES",
            "unit": "OBJECTS",
            "dimension": "COUNT",
            "scope": item["scope"],
            "resource_class": "PRODUCTION_MOT_OBJECT",
            "applies_to_profiles": ["M0_PRODUCTION"],
            "applies_to_features": [],
            "value_class": "NASM_RESOLVED_PROVISIONAL",
            "configured_value": item["configured_value"],
            "effective_value": item["effective_value"],
            "minimum_permitted": None,
            "maximum_permitted": item["maximum_permitted"],
            "default_value": None,
            "expression": None,
            "rounding_semantics": "EXACT_INTEGER",
            "alias_of": None,
            "provenance": {
                "source_kind": "NASM_PRODUCTION_MOT",
                "runtime_limit_symbol":
                    item["runtime_limit_symbol"],
                "runtime_limit_id":
                    item["runtime_limit_id"],
                "runtime_object_symbol":
                    item["runtime_object_symbol"],
                "runtime_object_id":
                    item["runtime_object_id"],
                "physical_capacity":
                    item["physical_capacity"],
                "effective_stride_bytes":
                    item["effective_stride_bytes"],
                "direct_capacity_bytes":
                    item["direct_capacity_bytes"],
            },
            "mot_refs": [
                item["runtime_limit_symbol"]
            ],
            "implementation_refs": item["implementation_refs"],
            "qualification_refs": item["qualification_refs"],
            "evidence_refs": list(M0_EVIDENCE_REFS),
            "first_required_milestone": "M0",
            "resolution_milestone": "M0",
            "qualification_milestone": "M0",
            "notes": [
                "Numerical capacity derives from the current "
                "NASM-resolved production MOT.",
                "Normative adoption and applicability beyond "
                "M0_PRODUCTION are not established.",
                "An exact production capacity is not evidence "
                "that all governing limits are complete.",
            ],
        })

        require(
            set(record) == set(FIELDS),
            "required LR schema incomplete",
        )

        validate_m0_dimensions(record)
        entries.append(record)

    require(
        len(entries) == 9,
        "unexpected M0 production subset",
    )

    require(
        len({x["limit_id"] for x in entries}) == len(entries),
        "duplicate canonical LIM identity",
    )

    return {
        "schema_version": 1,
        "document_type": "ASMWEB_M0_FULL_SCHEMA_LIMIT_REGISTER",
        "source_specification":
            "AsmWeb — Invariants & Limits Register v0.3 §6",
        "source_register_sha256": sha(source_bytes),
        "status": "PROVISIONAL_PENDING_NORMATIVE_ADOPTION",
        "scope": "M0_PRODUCTION_MOT_SUBSET",
        "entry_count": len(entries),
        "authoritative_lr_complete": False,
        "entries": entries,
    }


def verify():
    doc = build()
    expected = canonical(doc)

    require(
        OUTPUT.read_bytes() == expected,
        "full-schema LR differs from verified production source",
    )

    require(doc["entry_count"] == 9, "population mismatch")

    for item in doc["entries"]:
        require(set(item) == set(FIELDS), "LR field mismatch")
        validate_m0_dimensions(item)
        require(item["status"] == "PROVISIONAL", "false status")
        require(
            item["limit_kind"] == "CAPACITY",
            "incorrect limit kind",
        )
        require(
            item["configured_value"]
            == item["effective_value"] == 1,
            "unexpected M0 capacity",
        )
        require(
            item["provenance"]["direct_capacity_bytes"] > 0,
            "missing memory contribution",
        )
        for field in LIST_FIELDS:
            require(
                type(item[field]) is list,
                "invalid LR list field: " + field,
            )

        require(
            item["evidence_refs"] == list(M0_EVIDENCE_REFS),
            "invalid production evidence mapping",
        )

        for reference in item["evidence_refs"]:
            target = ROOT / reference
            require(
                target.is_file(),
                "missing evidence artifact: " + reference,
            )
            require(
                target.resolve().is_relative_to(ROOT.resolve()),
                "evidence escapes repository: " + reference,
            )

    print("FULL_SCHEMA_FIELDS=" + str(len(FIELDS)))
    print("M0_LIMITS=9")
    print("CANONICAL_NASM_MAPPING=VERIFIED")
    print("NORMATIVE_LR_ADOPTION=PENDING")
    print("M0_FULL_SCHEMA_LR=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("publish", "verify"))
    args = parser.parse_args()

    try:
        if args.action == "publish":
            require(
                not OUTPUT.exists() and not OUTPUT.is_symlink(),
                "full-schema LR already exists",
            )
            OUTPUT.write_bytes(canonical(build()))

        verify()
        return 0

    except (
        ValueError, OSError, KeyError,
        TypeError, AssertionError,
    ) as exc:
        print(
            "M0_FULL_SCHEMA_LR=FAIL: " + str(exc),
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
