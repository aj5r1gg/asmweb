#!/usr/bin/env python3
"""Adversarial production MOT manifest checks."""

import copy
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "qualification/tools/production_limit_manifest.py"

spec = importlib.util.spec_from_file_location("production_manifest", PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

baseline = module.validate()
source = module.ASM.read_text(encoding="utf-8")

assert baseline["production_mot_count"] == 9
assert baseline["production_rct_count"] == 2
assert len(baseline["mot_entries"]) == 9
assert baseline["M_direct_capacity_max"] > 0
assert baseline["definitions"][-1]["index"] == 8
assert (
    baseline["definitions"][-1]["object_symbol"]
    == "ASMWEB_PROD_OBJECT_HTTP_REQUEST_BUFFER"
)
assert (
    baseline["definitions"][-1]["limit_symbol"]
    == "ASMWEB_PROD_LIMIT_HTTP_REQUEST_BUFFER"
)
assert baseline["definitions"][-1]["size_bytes"] == 1024
assert baseline["M_direct_capacity_max"] == 3488

def rejected(value):
    try:
        module.validate(module.canonical(value))
    except module.ManifestError:
        return
    raise SystemExit("INCORRECTLY_ACCEPTED")

mutations = [
    ("false_authority", lambda d:
     d.update(authoritative_effective_limit_manifest=True)),
    ("false_normative_closure", lambda d:
     d.update(normative_limit_register_complete=True)),
    ("false_configuration_publication", lambda d:
     d.update(configuration_identity_published=True)),
    ("wrong_capacity", lambda d:
     d.update(M_direct_capacity_max=0)),
    ("wrong_object_size", lambda d:
     d["mot_entries"][0].update(actual_size_bytes=1)),
    ("wrong_maximum_count", lambda d:
     d["mot_entries"][0].update(maximum_count=2)),
    ("wrong_object_identity", lambda d:
     d["mot_entries"][0].update(object_id=9)),
    ("missing_entry", lambda d:
     d["mot_entries"].pop()),
    ("incorrect_provenance", lambda d:
     d["source_sha256"].update({
         "src/runtime/production_registry.asm": "0" * 64
     })),
    ("invented_field", lambda d: d.update(invented=True)),
    ("missing_dependency", lambda d:
     d["source_sha256"].pop("include/asmweb/abi.inc")),
    ("changed_dependency", lambda d:
     d["source_sha256"].update({
         "include/asmweb/arithmetic.inc": "0" * 64
     })),
    ("changed_closure_identity", lambda d:
     d.update(assembly_dependency_closure_sha256="0" * 64)),
    ("missing_derivation_tool", lambda d:
     d["derivation_tool_sha256"].pop(
         "qualification/tools/production_limit_manifest.py")),
    ("changed_derivation_tool", lambda d:
     d["derivation_tool_sha256"].update({
         "qualification/tools/effective_limit_engine.py": "0" * 64
     })),
]

for name, change in mutations:
    candidate = copy.deepcopy(baseline)
    change(candidate)
    rejected(candidate)
    print(name + "=REJECTED")

for name, old, new in (
    (
        "changed_maximum_count",
        "ASMWEB_MOT_VALIDATION_ENTRY.maximum_count], 1",
        "ASMWEB_MOT_VALIDATION_ENTRY.maximum_count], 2",
    ),
    (
        "changed_population_identity",
        "ASMWEB_PROD_LIMIT_STARTUP_INFO, \\",
        "ASMWEB_PROD_LIMIT_ENTROPY_BOOTSTRAP, \\",
    ),
):
    if source.count(old) < 1:
        raise SystemExit("MUTATION_ANCHOR_MISSING: " + name)
    changed = source.replace(old, new, 1)
    try:
        module.inspect_production_source(changed)
    except module.ManifestError:
        print(name + "=REJECTED")
    else:
        raise SystemExit(name + "=INCORRECTLY_ACCEPTED")

print("PRODUCTION_MOT_MANIFEST_ADVERSARIAL=PASS")
print("PRODUCTION_MOT_MANIFEST_VALIDATION=PASS")
