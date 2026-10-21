#!/usr/bin/env python3
"""REQ-M0-004: requirement membership and adversarial identity checks."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import m0_ownership_review as review


class IdentityFailure(Exception):
    pass


def validate(authority, population):
    if not isinstance(authority, list) or not isinstance(population, list):
        raise IdentityFailure("INVALID_COLLECTION")

    if not all(isinstance(x, str) and x for x in authority + population):
        raise IdentityFailure("INVALID_ID")

    if len(authority) != len(set(authority)):
        raise IdentityFailure("AUTHORITY_DUPLICATE")

    if len(population) != len(set(population)):
        raise IdentityFailure("DUPLICATE")

    unknown = set(population) - set(authority)
    if unknown:
        raise IdentityFailure("UNKNOWN")

    missing = set(authority) - set(population)
    if missing:
        raise IdentityFailure("MISSING")

    if population != authority:
        raise IdentityFailure("ORDER_MISMATCH")


def rejected(name, authority, candidate, reason):
    try:
        validate(authority, candidate)
    except IdentityFailure as exc:
        if str(exc) != reason:
            raise AssertionError(
                f"{name}: expected={reason} actual={exc}"
            )
        print(f"{name}=REJECTED_{reason}")
        return

    raise AssertionError(f"{name}: INCORRECTLY_ACCEPTED")


def main():
    review.verify()

    membership = review.load("requirements-membership-v0.3.json")
    source = review.load("requirements-source-v0.3.json")
    ownership = review.load(
        "requirements-milestone-ownership-v0.3.json"
    )
    registry = review.load("requirements-registry-v0.3.json")

    authority = membership["requirement_ids"]
    assert len(authority) == 1001

    populations = {
        "SOURCE": [e["requirement_id"] for e in source["entries"]],
        "OWNERSHIP": [
            e["requirement_id"] for e in ownership["entries"]
        ],
        "REGISTRY": [e["id"] for e in registry["entries"]],
    }

    for name, population in populations.items():
        validate(authority, population)
        print(f"{name}_IDENTITIES=PASS_1001")

    reordered = authority.copy()
    reordered[0], reordered[1] = reordered[1], reordered[0]

    duplicate = authority.copy()
    duplicate[1] = duplicate[0]

    unknown = authority.copy()
    unknown[0] = "REQ-UNKNOWN-999999"

    rejected("DUPLICATE", authority, duplicate, "DUPLICATE")
    rejected("UNKNOWN", authority, unknown, "UNKNOWN")
    rejected("MISSING", authority, authority[:-1], "MISSING")
    rejected("REORDERED", authority, reordered, "ORDER_MISMATCH")
    rejected("EMPTY_ID", authority, [""] + authority[1:],
             "INVALID_ID")
    rejected("DUPLICATE_AUTHORITY", authority + [authority[0]],
             authority, "AUTHORITY_DUPLICATE")

    print("REQ_M0_004_ENGINEERING_QUALIFICATION=PASS")


if __name__ == "__main__":
    try:
        main()
    except (IdentityFailure, AssertionError, ValueError,
            KeyError, TypeError, OSError) as exc:
        print("REQ_M0_004_ENGINEERING_QUALIFICATION=FAIL:", exc,
              file=sys.stderr)
        raise SystemExit(1)
