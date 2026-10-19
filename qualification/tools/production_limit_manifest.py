#!/usr/bin/env python3
"""M0 production MOT limit derivation from NASM-resolved authority."""

import argparse
import hashlib
import importlib.util
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INC = ROOT / "include/asmweb/production_registry.inc"
ASM = ROOT / "src/runtime/production_registry.asm"
RULES = ROOT / "include/asmweb/runtime_rules.def"
REGISTRY = ROOT / "include/asmweb/registry.inc"
OUTPUT = ROOT / "qualification/limits/production-m0-v0.1.json"

ENGINE_PATH = ROOT / "qualification/tools/effective_limit_engine.py"
spec = importlib.util.spec_from_file_location("limit_engine", ENGINE_PATH)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)

class ManifestError(Exception):
    pass

def require(ok, message):
    if not ok:
        raise ManifestError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def parse_invocations(source, kind):
    pattern = re.compile(
        r"(?m)^[ \t]*ASMWEB_PRODUCTION_" + kind
        + r"_ENTRY[ \t]*\\[ \t]*\n"
        + r"((?:[ \t]*[^\n]*\n){4})"
    )
    matches = pattern.findall(source)
    require(len(matches) == 8, kind + " population count")

    result = []
    for body in matches:
        lines = body.splitlines()
        require(len(lines) == 4, kind + " argument count")
        fields = []
        for index, line in enumerate(lines):
            value = line.strip()
            if index < 3:
                require(value.endswith("\\"), kind + " continuation")
                value = value[:-1].strip()
            require(value.endswith(",") == (index < 3),
                    kind + " argument separator")
            fields.append(value.rstrip(",").strip())
        require(fields[0].isdigit(), kind + " numeric index")
        result.append((int(fields[0]), *fields[1:]))

    require([row[0] for row in result] == list(range(8)),
            kind + " index order")
    return result

def inspect_production_source(source):
    olr = parse_invocations(source, "OLR")
    mot = parse_invocations(source, "MOT")

    # OLR arguments:
    #   index, object_id, actual_size, mot_ref
    #
    # MOT arguments:
    #   index, limit_id, object_id, actual_size
    #
    # Compare semantically equivalent fields, not tuple order.
    normalized_olr = [
        (index, limit_id, object_id, size)
        for index, object_id, size, limit_id in olr
    ]

    require(
        normalized_olr == mot,
        "OLR/MOT index or mapping mismatch",
    )

    for index, object_id, size, limit_id in olr:
        require(object_id.startswith("ASMWEB_PROD_OBJECT_"),
                "OLR object identity")
        require(limit_id.startswith("ASMWEB_PROD_LIMIT_"),
                "OLR MOT reference")
        require(
            object_id[len("ASMWEB_PROD_OBJECT_"):]
            == limit_id[len("ASMWEB_PROD_LIMIT_"):],
            "object/limit name mismatch",
        )
        require(
            re.fullmatch(r"ASMWEB_[A-Za-z_0-9]+", size) is not None,
            "invalid size expression",
        )

    # These statements are the actual current production materialisation
    # policy, not sample numbers supplied to the Python engine.
    expected_assignments = {
        "status": "ASMWEB_REGISTRY_STATUS_ACTIVE",
        "pool_metadata_bytes": "0",
        "mapping_overhead_bytes": "0",
        "maximum_count": "1",
        "physical_capacity": "1",
        "configured_capacity": "1",
        "owner_resource_id": "0",
    }

    start = source.find("%macro ASMWEB_PRODUCTION_MOT_ENTRY 4")
    end = source.find("%endmacro", start)
    require(start >= 0 and end > start, "MOT macro missing")
    macro = source[start:end]

    for field, value in expected_assignments.items():
        require(
            re.search(
                r"mov qword \[r10 \+ "
                r"ASMWEB_MOT_VALIDATION_ENTRY\."
                + re.escape(field)
                + r"\],\s*(?:\\\s*\n\s*)?"
                + re.escape(value)
                + r"\b",
                macro,
            ) is not None,
            "production MOT assignment changed: " + field,
        )

    for field, value in (
        ("actual_size_bytes", "%4"),
        ("effective_stride_bytes", "%4"),
        ("limit_id", "%2"),
        ("object_id", "%3"),
    ):
        require(
            re.search(
                r"mov qword \[r10 \+ ASMWEB_MOT_VALIDATION_ENTRY\."
                + re.escape(field)
                + r"\],\s*"
                + re.escape(value)
                + r"\b",
                macro,
            ) is not None,
            "MOT parameter binding changed: " + field,
        )

    return mot

def nasm_resolve(mappings):
    includes = (
        "startup.inc", "entropy.inc", "cpu.inc", "time.inc",
        "process_runtime.inc", "startup_memory.inc",
        "registry.inc", "production_registry.inc",
    )

    lines = ["bits 64"]
    lines += [
        '%include "asmweb/' + name + '"'
        for name in includes
    ]
    lines.append("section .data")

    # Use NASM's own assembly evaluation of struct sizes, EQU
    # expressions and production IDs.
    lines.append("dq ASMWEB_PRODUCTION_OLR_COUNT")
    lines.append("dq ASMWEB_PRODUCTION_MOT_COUNT")
    lines.append("dq ASMWEB_PRODUCTION_RCT_COUNT")

    for _, limit_name, object_name, size_name in mappings:
        lines.append("dq " + limit_name)
        lines.append("dq " + object_name)
        lines.append("dq " + size_name)

    with tempfile.TemporaryDirectory(prefix="asmweb-mot-") as directory:
        directory = Path(directory)
        source = directory / "resolve.asm"
        output = directory / "resolve.bin"
        source.write_text("\n".join(lines) + "\n", encoding="ascii")

        result = subprocess.run(
            [
                "nasm", "-f", "bin",
                "-I", str(ROOT / "include") + "/",
                "-o", str(output),
                str(source),
            ],
            capture_output=True,
            text=True,
        )

        require(
            result.returncode == 0,
            "NASM authority resolution failed: "
            + result.stderr[:1000],
        )
        data = output.read_bytes()

    expected_words = 3 + len(mappings) * 3
    require(len(data) == expected_words * 8,
            "unexpected NASM probe output size")

    words = struct.unpack("<" + "Q" * expected_words, data)
    require(words[:3] == (8, 8, 0),
            "production registry population counts")

    return [
        words[3 + index * 3:6 + index * 3]
        for index in range(len(mappings))
    ]

def build():
    source = ASM.read_text(encoding="utf-8")
    mappings = inspect_production_source(source)
    resolved = nasm_resolve(mappings)

    mot_entries = []
    descriptive = []
    seen_limits = set()
    seen_objects = set()

    for mapping, (limit_id, object_id, size) in zip(
        mappings, resolved
    ):
        index, limit_name, object_name, size_name = mapping

        require(limit_id != 0 and limit_id not in seen_limits,
                "invalid/duplicate production limit identity")
        require(object_id != 0 and object_id not in seen_objects,
                "invalid/duplicate production object identity")
        require(size > 0, "zero production structure size")

        seen_limits.add(limit_id)
        seen_objects.add(object_id)

        mot_entries.append({
            "limit_id": limit_id,
            "status": engine.MOT_ACTIVE,
            "object_id": object_id,
            "actual_size_bytes": size,
            "effective_stride_bytes": size,
            "pool_metadata_bytes": 0,
            "mapping_overhead_bytes": 0,
            "maximum_count": 1,
            "physical_capacity": 1,
            "configured_capacity": 1,
            "owner_resource_id": 0,
        })

        descriptive.append({
            "index": index,
            "limit_symbol": limit_name,
            "object_symbol": object_name,
            "size_symbol": size_name,
            "limit_id": limit_id,
            "object_id": object_id,
            "size_bytes": size,
        })

    projection = engine.calculate_mot_ceiling({
        "schema_version": 1,
        "entries": mot_entries,
    })

    require(projection["active_entry_count"] == 8,
            "unexpected active limit count")
    require(
        projection["M_direct_capacity_max"]
        == sum(item["size_bytes"] for item in descriptive),
        "production capacity reconciliation",
    )

    provenance = {
        str(path.relative_to(ROOT)): sha(path)
        for path in (
            INC, ASM, RULES, REGISTRY, ENGINE_PATH,
            ROOT / "include/asmweb/startup.inc",
            ROOT / "include/asmweb/entropy.inc",
            ROOT / "include/asmweb/cpu.inc",
            ROOT / "include/asmweb/time.inc",
            ROOT / "include/asmweb/process_runtime.inc",
            ROOT / "include/asmweb/startup_memory.inc",
        )
    }

    return {
        "schema_version": 1,
        "document_type": "PRODUCTION_M0_MOT_LIMIT_PROJECTION",
        "status": "CONTROLLED_IMPLEMENTATION_PROJECTION",
        "authoritative_effective_limit_manifest": False,
        "normative_limit_register_complete": False,
        "configuration_identity_published": False,
        "assembly_structure_resolution": "NASM",
        "source_sha256": provenance,
        "production_mot_count": len(mot_entries),
        "production_rct_count": 0,
        "definitions": descriptive,
        "mot_entries": mot_entries,
        "M_direct_capacity_max": projection["M_direct_capacity_max"],
    }

def canonical(value):
    return engine.canonical(value)

def validate(raw=None):
    expected = build()
    source = OUTPUT.read_bytes() if raw is None else raw

    def unique_pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate JSON key")
            result[key] = value
        return result

    actual = json.loads(
        source.decode("utf-8"),
        object_pairs_hook=unique_pairs,
        parse_constant=lambda _: (
            (_ for _ in ()).throw(ManifestError("nonfinite JSON"))
        ),
    )
    require(type(actual) is dict, "manifest root type")
    require(actual == expected, "manifest/source disagreement")
    require(source == canonical(expected),
            "noncanonical manifest encoding")
    return actual

def publish_exclusive(payload):
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    require(not OUTPUT.exists(), "manifest already exists")
    pending = OUTPUT.with_name(OUTPUT.name + ".pending")

    try:
        with pending.open("xb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.link(pending, OUTPUT)
    finally:
        if pending.exists():
            pending.unlink()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate", action="store_true")
    args = parser.parse_args()

    try:
        if args.generate:
            publish_exclusive(canonical(build()))
        document = validate()
    except (
        ManifestError, engine.LimitError, OSError,
        UnicodeError, ValueError, subprocess.SubprocessError,
    ) as exc:
        print("PRODUCTION_LIMIT_MANIFEST=FAIL: " + str(exc))
        return 1

    print("production_mot_entries=" +
          str(document["production_mot_count"]))
    print("M_direct_capacity_max=" +
          str(document["M_direct_capacity_max"]))
    print("NASM_AUTHORITY_RESOLUTION=PASS")
    print("SOURCE_PROVENANCE=VERIFIED")
    print("AUTHORITATIVE_ELM=False")
    print("PRODUCTION_LIMIT_MANIFEST=PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
