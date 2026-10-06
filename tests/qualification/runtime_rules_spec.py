#!/usr/bin/env python3

from pathlib import Path
import re
import sys


SOURCE = Path("include/asmweb/runtime_rules.def")


EXPECTED = {
    "MEM-GOV-AUTHORITY":
        "Runtime behaviour defined here SHALL NOT silently override behaviour owned by another authoritative specification.",

    "MEM-GOV-REGISTRATION":
        "A long-lived, externally influenceable or capacity-relevant runtime resource SHALL NOT be introduced without registration in the applicable runtime registry.",

    "MEM-GOV-DEFERRED":
        "An unresolved design or numerical value SHALL remain explicitly unresolved rather than being replaced by an arbitrary implementation convenience.",

    "MEM-OBJ-LAYOUT-VERIFY":
        "Before an object layout contributes to a qualified memory ceiling, its actual assembled size, alignment and effective pool stride SHALL be mechanically derived or verified against the built artefact.",

    "MEM-CAP-NO-HEAP":
        "Steady-state request processing SHALL NOT depend upon unbounded general-purpose allocation.",

    "MEM-CAP-REGISTERED-ACQUISITION":
        "Steady-state acquisition SHALL come from a registered bounded mechanism or explicitly bounded/qualified provider boundary.",

    "MEM-POL-VARIABLE-BOUND":
        "Every variable-size runtime allocator SHALL have a calculable upper memory bound.",

    "MEM-POL-TOO-LARGE":
        "Failure because one requested object exceeds every supported size class SHALL be distinguishable from aggregate resource exhaustion.",

    "MEM-LIFE-ACQUIRE-ROLLBACK":
        "Failed multi-resource acquisition SHALL leave no unowned or unaccounted retained resource.",

    "MEM-LIFE-TERMINAL":
        "An object that has reached a terminal state and has no remaining ownership, borrow, protocol or external-completion dependency SHALL become reclaimable.",

    "MEM-LIFE-STREAM-ABANDONED":
        "Abandoned stream state SHALL progress toward deterministic reclamation under bounded policy.",

    "MEM-LIFE-CONNECTION-CLOSURE":
        "A connection SHALL NOT disappear while ownership of a connection-dependent resource becomes undefined.",

    "MEM-CAP-DEPENDENCY":
        "A configuration SHALL NOT enter READY when its full capacity dependency graph cannot be provisioned or validly bounded.",
}


text = SOURCE.read_text()

pattern = re.compile(
    r"ASMWEB_RUNTIME_RULE\s*\\\s*"
    r"([A-Z0-9_]+),\s*\\\s*"
    r"`([^`]+)`,\s*\\\s*"
    r"([^,]+),\s*\\\s*"
    r"([^,]+),\s*\\\s*"
    r"([^,]+),\s*\\\s*"
    r"`([^`]+)`",
    re.MULTILINE,
)

found = {}

for match in pattern.finditer(text):
    token, rule_id, namespace, status, qualification, statement = match.groups()

    if rule_id in found:
        print(f"duplicate_rule_id={rule_id}")
        sys.exit(1)

    found[rule_id] = {
        "token": token.strip(),
        "namespace": namespace.strip(),
        "status": status.strip(),
        "qualification": qualification.strip(),
        "statement": statement,
    }


if len(found) != 13:
    print(f"rule_count={len(found)} expected=13")
    sys.exit(2)


if set(found) != set(EXPECTED):
    missing = sorted(set(EXPECTED) - set(found))
    extra = sorted(set(found) - set(EXPECTED))

    print(f"missing={missing}")
    print(f"extra={extra}")
    sys.exit(3)


EXPECTED_NAMESPACE = {
    "MEM-GOV-AUTHORITY": "ASMWEB_RRR_NAMESPACE_GOV",
    "MEM-GOV-REGISTRATION": "ASMWEB_RRR_NAMESPACE_GOV",
    "MEM-GOV-DEFERRED": "ASMWEB_RRR_NAMESPACE_GOV",
    "MEM-OBJ-LAYOUT-VERIFY": "ASMWEB_RRR_NAMESPACE_OBJ",
    "MEM-CAP-NO-HEAP": "ASMWEB_RRR_NAMESPACE_CAP",
    "MEM-CAP-REGISTERED-ACQUISITION": "ASMWEB_RRR_NAMESPACE_CAP",
    "MEM-POL-VARIABLE-BOUND": "ASMWEB_RRR_NAMESPACE_POL",
    "MEM-POL-TOO-LARGE": "ASMWEB_RRR_NAMESPACE_POL",
    "MEM-LIFE-ACQUIRE-ROLLBACK": "ASMWEB_RRR_NAMESPACE_LIFE",
    "MEM-LIFE-TERMINAL": "ASMWEB_RRR_NAMESPACE_LIFE",
    "MEM-LIFE-STREAM-ABANDONED": "ASMWEB_RRR_NAMESPACE_LIFE",
    "MEM-LIFE-CONNECTION-CLOSURE": "ASMWEB_RRR_NAMESPACE_LIFE",
    "MEM-CAP-DEPENDENCY": "ASMWEB_RRR_NAMESPACE_CAP",
}


tokens = set()

for rule_id, expected_statement in EXPECTED.items():
    actual = found[rule_id]

    if actual["statement"] != expected_statement:
        print(f"statement_mismatch={rule_id}")
        print(f"expected={expected_statement}")
        print(f"actual={actual['statement']}")
        sys.exit(4)

    if actual["namespace"] != EXPECTED_NAMESPACE[rule_id]:
        print(f"namespace_mismatch={rule_id}")
        print(f"expected={EXPECTED_NAMESPACE[rule_id]}")
        print(f"actual={actual['namespace']}")
        sys.exit(5)

    if actual["status"] != "ASMWEB_REGISTRY_STATUS_ACTIVE":
        print(f"status_mismatch={rule_id}")
        print("expected=ASMWEB_REGISTRY_STATUS_ACTIVE")
        print(f"actual={actual['status']}")
        sys.exit(6)

    if actual["qualification"] != "ASMWEB_QUAL_STATE_NOT_STARTED":
        print(f"qualification_state_mismatch={rule_id}")
        print("expected=ASMWEB_QUAL_STATE_NOT_STARTED")
        print(f"actual={actual['qualification']}")
        sys.exit(7)

    token = actual["token"]

    if token in tokens:
        print(f"duplicate_rule_token={token}")
        sys.exit(8)

    tokens.add(token)


print("runtime_rules_spec_snapshot_status=0")
print(f"runtime_rules_count={len(found)}")

for rule_id in sorted(found):
    print(rule_id)
