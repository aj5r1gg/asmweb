#!/usr/bin/env python3
"""Executable, M0-scoped invariant assertions for the existing limit projection.

These assertions qualify only the demonstrated operations. They do not approve
normative invariants or claim correctness for unrelated runtime subsystems.
"""

from copy import deepcopy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))
import effective_limit_engine as limits


def require(ok, reason):
    if not ok:
        raise AssertionError(reason)


def expect_rejected(value, name):
    try:
        limits.calculate(value)
    except limits.LimitError:
        return
    raise AssertionError(name + " was accepted")


def main():
    source = json.loads((ROOT / "qualification/invariants/ir-normative-source-v0.3.json").read_text())
    projected = json.loads((ROOT / "qualification/invariants/m0-normative-ir-v0.1.json").read_text())
    assessment = json.loads((ROOT / "qualification/invariants/m0-applicability-v0.1.json").read_text())
    scope = json.loads((ROOT / "qualification/invariants/m0-scope-decisions-v0.1.json").read_text())
    identities = [[entry["invariant_id"] for entry in obj["entries"]] for obj in (source, projected, assessment)]
    require(len(identities[0]) == 144, "invariant source population")
    require(all(identities[0] == row for row in identities[1:]), "canonical source-to-IR identity order")
    require(len(set(identities[0])) == 144, "duplicate canonical invariant identity")
    require(all(identity.startswith("INV-") for identity in identities[0]), "unrecognised invariant identity")
    require(len({x["invariant_id"] for x in scope["entries"]}) == 42, "scope identity collision")
    require(set(x["invariant_id"] for x in scope["entries"]) <= set(identities[0]), "invented scope invariant")
    print("INV-GOV-002_CANONICAL_REGISTER=PASS")

    fixture = {"schema_version": 1, "entries": [
        {"limit_id": 1201, "maximum_count": 9, "physical_capacity": 8,
         "configured_capacity": 5, "effective_stride_bytes": 64,
         "pool_metadata_bytes": 16, "mapping_overhead_bytes": 8},
        {"limit_id": 1202, "maximum_count": 8, "physical_capacity": 6,
         "configured_capacity": 4, "effective_stride_bytes": 32,
         "pool_metadata_bytes": 2, "mapping_overhead_bytes": 1},
    ]}
    result = limits.calculate(fixture)
    require(result["entries"][0]["effective_count"] == 5, "count unit invalid")
    require(result["entries"][0]["direct_capacity_bytes"] == 320, "bytes unit invalid")
    require(result["total_direct_capacity_bytes"] == 448, "byte aggregate invalid")
    require(result["total_overhead_bytes"] == 27, "overhead aggregate invalid")
    require(result["total_projected_bytes"] == 475, "combined byte aggregate invalid")
    require(all(type(e["effective_count"]) is int and type(e["direct_capacity_bytes"]) is int
                for e in result["entries"]), "implicit fractional rounding")

    for change in ({"configured_capacity": 4.5}, {"effective_stride_bytes": 2.25},
                   {"pool_metadata_bytes": -1}, {"physical_capacity": -1},
                   {"maximum_count": True}):
        bad = deepcopy(fixture)
        bad["entries"][0].update(change)
        expect_rejected(bad, repr(change))
    print("INV-GOV-EXPR-003_EXACT_INTEGER_BOUNDS=PASS")
    print("INV-ACC-NONNEG-001_LIMIT_INPUTS=PASS")
    print("INV-CAP-006_COUNT_VERSUS_BYTES=PASS")

    # A changed input must not yield the prior derived value. Multiple chained
    # aggregate outputs must change, while unrelated identities are preserved.
    changed = deepcopy(fixture)
    changed["entries"][0]["configured_capacity"] = 3
    after = limits.calculate(changed)
    require(after["entries"][0]["effective_count"] == 3, "changed count not reevaluated")
    require(after["entries"][0]["direct_capacity_bytes"] == 192, "changed payload not reevaluated")
    require(after["entries"][1] == result["entries"][1], "unrelated limit changed")
    require(after["total_direct_capacity_bytes"] == 320, "dependent total not reevaluated")
    require(after["total_projected_bytes"] == 347, "grand total not reevaluated")
    require(limits.calculate(fixture) == result, "pure reevaluation not deterministic")
    changed["entries"][0]["effective_stride_bytes"] = 128
    twice = limits.calculate(changed)
    require(twice["entries"][0]["direct_capacity_bytes"] == 384, "stride change not propagated")
    require(twice["total_projected_bytes"] == 539, "stride change not propagated to total")
    print("INV-CHG-002_EFFECTIVE_LIMIT_REEVALUATION=PASS")
    print("M0_UNMAPPED_EXECUTABLE_CHECKS=5")
    print("NORMATIVE_APPROVALS_CHANGED=0")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, KeyError, ValueError, TypeError, OSError, limits.LimitError) as exc:
        print("M0_UNMAPPED_RUNTIME_QUALIFICATION=FAIL: " + str(exc), file=sys.stderr)
        sys.exit(1)
