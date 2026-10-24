#!/usr/bin/env python3
"""M0 production-scope invariant engineering checks.

Evidence for selected governance invariants only.
This does not constitute full normative IR approval.
"""

import copy
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import m0_normative_lr as lr
import m0_effective_configuration as elm
import m0_limit_register as production_lr


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def reject_dimension(entry, changes):
    altered = copy.deepcopy(entry)
    altered.update(changes)
    try:
        lr.validate_m0_dimensions(altered)
    except ValueError:
        return
    raise RuntimeError("INVALID_DIMENSION_ACCEPTED: " + repr(changes))


def main():
    # All source objects are derived or read; no live artifact is modified.
    normative = lr.build()
    published = json.loads(lr.OUTPUT.read_text())
    effective = elm.build()
    published_elm = json.loads(elm.OUTPUT.read_text())
    production = production_lr.derive()

    require(
        published == normative,
        "NORMATIVE_LR_SOURCE_MISMATCH",
    )
    require(
        published_elm == effective,
        "EFFECTIVE_CONFIGURATION_SOURCE_MISMATCH",
    )

    limits = normative["entries"]
    projected = effective["configuration"]["limits"]
    source = production["entries"]

    require(
        len(limits) == len(projected) == len(source) == 9,
        "LIMIT_POPULATION_MISMATCH",
    )

    by_id = {x["limit_id"]: x for x in limits}
    by_runtime = {
        x["runtime_limit_id"]: x for x in projected
    }
    by_source = {
        x["runtime_limit_id"]: x for x in source
    }

    require(
        len(by_id) == len(by_runtime) == len(by_source) == 9,
        "DUPLICATE_IDENTITY",
    )

    # INV-GOV-003: canonical identity alignment in the M0
    # production MOT -> LR -> ELM projection.
    for item in limits:
        runtime_id = item["provenance"]["runtime_limit_id"]
        require(runtime_id in by_runtime, "MISSING_ELM_LIMIT")
        require(runtime_id in by_source, "MISSING_MOT_LIMIT")
        require(
            by_runtime[runtime_id]["normative_lim_id"]
            == item["limit_id"]
            == by_source[runtime_id]["limit_id"],
            "COMPETING_LIMIT_IDENTITY",
        )
    print("INV-GOV-003_M0_PRODUCTION_PROJECTION=PASS")

    # INV-GOV-APP-001: deterministic applicability for
    # the identified M0 production profile.
    for item in limits:
        require(
            item["status"] == "ACTIVE"
            and item["applies_to_profiles"] == ["M0_PRODUCTION"]
            and item["first_required_milestone"] == "M0",
            "NONDETERMINISTIC_M0_APPLICABILITY",
        )
    require(
        effective["configuration"]["scope"]
        == "M0_PRODUCTION_IMPLEMENTATION",
        "WRONG_CONFIGURATION_SCOPE",
    )
    print("INV-GOV-APP-001_M0_PRODUCTION=PASS")

    # INV-GOV-UNIT-001: reject invalid M0 capacity
    # dimensions and non-integer numerical values.
    sample = limits[0]
    for changes in (
        {"dimension": "TIME"},
        {"unit": "BYTES"},
        {"quantity": "DURATION"},
        {"configured_value": 1.5},
        {"configured_value": True},
        {"expression": "configured_value / 2"},
        {"rounding_semantics": "NEAREST"},
    ):
        reject_dimension(sample, changes)
    print("INV-GOV-UNIT-001_M0_CAPACITY=PASS")

    # INV-GOV-ALIAS-001: equal numerical capacities
    # are not grounds for collapsing distinct identities.
    symbols = [
        x["provenance"]["runtime_limit_symbol"]
        for x in limits
    ]
    require(len(set(symbols)) == 9, "DUPLICATE_LIMIT_SYMBOL")
    require(len(set(by_id)) == 9, "DUPLICATE_CANONICAL_ID")
    require(
        len({x["configured_value"] for x in limits}) == 1,
        "UNEXPECTED_M0_CAPACITY_FIXTURE",
    )
    require(
        all(x["alias_of"] is None for x in limits),
        "UNVERIFIED_ALIAS",
    )
    print("INV-GOV-ALIAS-001_M0_PRODUCTION=PASS")

    # INV-GOV-MANIFEST-001: evidence attributable
    # to an identifiable binary and configuration.
    cfg = effective["configuration"]
    calculated = hashlib.sha256(
        elm.canonical(cfg)
    ).hexdigest()

    require(
        effective["effective_configuration_sha256"]
        == calculated,
        "CONFIGURATION_DIGEST_MISMATCH",
    )
    require(
        cfg["binary_sha256"]
        == hashlib.sha256(elm.BINARY.read_bytes()).hexdigest(),
        "BINARY_DIGEST_MISMATCH",
    )
    require(
        cfg["production_limit_register_sha256"]
        == hashlib.sha256(
            production_lr.canonical(production)
        ).hexdigest(),
        "SOURCE_REGISTER_DIGEST_MISMATCH",
    )
    print("INV-GOV-MANIFEST-001_M0_CONFIGURATION=PASS")

    # INV-GOV-UNRESOLVED-001: no unresolved production
    # limit reaches the M0 enforcement projection.
    require(
        normative["authoritative_lr_complete"] is True
        and effective["normative_lr_complete"] is True
        and effective["authoritative_elm_adopted"] is True,
        "UNADOPTED_LIMIT_PROJECTION",
    )
    require(
        all(item["status"] == "ACTIVE" for item in limits),
        "UNRESOLVED_M0_LIMIT",
    )
    print("INV-GOV-UNRESOLVED-001_M0_PRODUCTION=PASS")

    print("M0_FOUNDATION_GOVERNANCE_CHECKS=6")
    print("M0_FOUNDATION_GOVERNANCE_QUALIFICATION=PASS")
    print("FORMAL_INVARIANT_ADOPTION=NOT_IMPLIED")


if __name__ == "__main__":
    try:
        main()
    except (
        RuntimeError, ValueError, KeyError,
        TypeError, OSError, AssertionError,
    ) as exc:
        print(
            "M0_FOUNDATION_GOVERNANCE_QUALIFICATION=FAIL:",
            exc,
            file=sys.stderr,
        )
        sys.exit(1)
