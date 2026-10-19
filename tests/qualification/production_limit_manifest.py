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

assert baseline["production_mot_count"] == 8
assert baseline["production_rct_count"] == 0
assert len(baseline["mot_entries"]) == 8
assert baseline["M_direct_capacity_max"] > 0

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
