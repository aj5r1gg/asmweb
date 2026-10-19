#!/usr/bin/env python3
"""AsmWeb M0 READY-state invariant implementation trace register."""

import argparse
import json
import re
import sys
from pathlib import Path
from hashlib import sha256

ROOT = Path(__file__).resolve().parents[2]

HEADER = ROOT / "include/asmweb/runtime_invariant.inc"
SOURCE = ROOT / "src/runtime/runtime_invariant.asm"
QUAL = ROOT / "tests/qualification/runtime_invariant.asm"
REGISTER = ROOT / "qualification/invariants/runtime-ready-v0.1.json"

# Existing, independently authored assembly qualification cases.
# These are trace relationships, not new normative requirement identities.
COVERAGE = {
    "INPUT": [2],
    "PROCESS": [3],
    "REGISTRY": [5],
    "STARTUP_MEMORY": [6],
    "DEPENDENCY": [7],
    "STARTUP_STATE": [8],
    "ENTROPY": [9],
    "CPU": [10],
    "TIME": [11, 12],
    "MEMORY_RECONCILIATION": [13, 14],
    "READY_STATE": [4],
}

DETAILS = {
    "INPUT": "Mandatory input view and authority pointers",
    "PROCESS": "Process runtime structure validity",
    "REGISTRY": "OLR/MOT/RCT registry consistency",
    "STARTUP_MEMORY": "Startup memory account validity",
    "DEPENDENCY": "Capacity dependency graph validity",
    "STARTUP_STATE": "Page size and borrowed entropy pointer",
    "ENTROPY": "Entropy bootstrap publication",
    "CPU": "CPU readiness and SSE2 baseline",
    "TIME": "Normalized and checked monotonic time",
    "MEMORY_RECONCILIATION": "MOT capacity and startup memory agreement",
    "READY_STATE": "M0 READY lifecycle and transition invariants",
}

class RegisterError(Exception):
    pass

def require(condition, reason):
    if not condition:
        raise RegisterError(reason)

def strict_json(data):
    def pairs(items):
        obj = {}
        for key, value in items:
            require(key not in obj, "duplicate JSON key")
            obj[key] = value
        return obj

    def reject_constant(value):
        raise RegisterError("nonfinite JSON value")

    return json.loads(
        data.decode("utf-8"),
        object_pairs_hook=pairs,
        parse_constant=reject_constant,
    )

def digest(data):
    return sha256(data).hexdigest()

def inspect_sources(header, source, qualification):
    pattern = re.compile(
        r"^%define\s+ASMWEB_RUNTIME_INVARIANT_FAIL_"
        r"([A-Z_]+)\s+(\d+)\s*$",
        re.MULTILINE,
    )

    matches = pattern.findall(header)

    require(len(matches) == 11, "failure-class count")
    require(
        [name for name, _ in matches] == list(COVERAGE),
        "failure-class identity or order"
    )
    require(
        [int(number) for _, number in matches]
        == list(range(1, 12)),
        "failure-class numeric identity"
    )

    require(set(DETAILS) == set(COVERAGE), "missing descriptions")

    # Check actual class-specific failure paths, not just declarations.
    for name, number in matches:
        label = {
            "READY_STATE": "ready",
        }.get(name, name.lower())

        block = re.search(
            rf"(?m)^\.fail_{label}:\s*\n"
            rf"\s*mov edx, "
            rf"ASMWEB_RUNTIME_INVARIANT_FAIL_{name}\b",
            source,
        )

        require(
            block is not None,
            f"implementation missing: {name}",
        )

        for case in COVERAGE[name]:
            require(
                re.search(
                    rf"(?m)^\s*; CASE {case}\s",
                    qualification,
                ) is not None,
                f"qualification case missing: {case}",
            )

            require(
                f"ASMWEB_RUNTIME_INVARIANT_FAIL_{name}"
                in qualification,
                f"qualification classification missing: {name}",
            )

    require(
        "global asm_runtime_invariant_validate_ready" in source,
        "public runtime symbol missing",
    )
    require(
        "asm_runtime_invariant_validate_ready:" in source,
        "runtime implementation missing",
    )
    require(
        "call asm_runtime_invariant_validate_ready" in qualification,
        "executable qualification missing",
    )

    require(
        len(set(
            case for cases in COVERAGE.values()
            for case in cases
        )) == 13,
        "adversarial case mapping"
    )

    return matches

def generate(header_bytes=None, source_bytes=None, qual_bytes=None):
    hb = HEADER.read_bytes() if header_bytes is None else header_bytes
    sb = SOURCE.read_bytes() if source_bytes is None else source_bytes
    qb = QUAL.read_bytes() if qual_bytes is None else qual_bytes

    header = hb.decode("utf-8")
    source = sb.decode("utf-8")
    qualification = qb.decode("utf-8")

    classes = inspect_sources(header, source, qualification)

    entries = []

    for name, number in classes:
        entries.append({
            "id": f"ASMWEB-M0-RUNTIME-INV-{int(number):02d}",
            "failure_class": name,
            "failure_code": int(number),
            "description": DETAILS[name],
            "implementation_symbol":
                "asm_runtime_invariant_validate_ready",
            "definition":
                "ASMWEB_RUNTIME_INVARIANT_FAIL_" + name,
            "qualification_case_numbers": COVERAGE[name],
            "qualification_source":
                "tests/qualification/runtime_invariant.asm",
            "qualification_result": "NOT_RECORDED_IN_REGISTER",
        })

    return {
        "schema_version": 1,
        "register_id": "ASMWEB-M0-RUNTIME-READY-IR",
        "register_version": "0.1",
        "register_scope": "M0_READY_STATE",
        "authoring_status": "IMPLEMENTATION_TRACE_DRAFT",
        "normative_invariant_register_complete": False,
        "m0_blocker_resolved": False,
        "implementation_header":
            "include/asmweb/runtime_invariant.inc",
        "implementation_source":
            "src/runtime/runtime_invariant.asm",
        "qualification_source":
            "tests/qualification/runtime_invariant.asm",
        "source_digests": {
            "header_sha256": digest(hb),
            "implementation_sha256": digest(sb),
            "qualification_sha256": digest(qb),
        },
        "entry_count": len(entries),
        "entries": entries,
    }

def serialize(obj):
    return (
        json.dumps(obj, indent=2, ensure_ascii=False)
        + "\n"
    ).encode("utf-8")

def validate(data=None):
    expected = generate()
    actual = strict_json(
        REGISTER.read_bytes() if data is None else data
    )

    require(type(actual) is dict, "invalid root")
    require(
        set(actual) == set(expected),
        "top-level schema disagreement",
    )
    require(
        actual == expected,
        "register differs from actual controlled implementation",
    )

    return actual

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--generate", action="store_true",
        help="Write initial register only if absent"
    )
    args = parser.parse_args()

    try:
        if args.generate:
            # Complete all source validation and serialization first.
            payload = serialize(generate())

            REGISTER.parent.mkdir(parents=True, exist_ok=True)

            temporary = REGISTER.with_name(
                REGISTER.name + ".pending"
            )

            # Never overwrite either an existing register or an
            # existing pending publication.
            require(
                not REGISTER.exists(),
                "register already exists",
            )

            try:
                with temporary.open("xb") as stream:
                    stream.write(payload)
                    stream.flush()
                    import os
                    os.fsync(stream.fileno())

                # Exclusive destination creation prevents replacing
                # an existing authoritative register. This is not
                # a crash-atomic multi-file transaction.
                os.link(temporary, REGISTER)

            finally:
                if temporary.exists():
                    temporary.unlink()

        document = validate()

    except (
        RegisterError, OSError, ValueError,
        UnicodeError, KeyError, TypeError,
    ) as exc:
        print(f"RUNTIME_INVARIANT_REGISTER=FAIL: {exc}")
        return 1

    print(f"registered_failure_classes={document['entry_count']}")
    print("implementation_traceability=VERIFIED")
    print("normative_register_complete=False")
    print("M0_BLOCK_IR=OPEN")
    print("RUNTIME_INVARIANT_REGISTER=PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
