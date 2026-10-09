#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "qualification/tools/qualification_foundation.py"


def run(*args: str, expect: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["python3", str(TOOL), *args],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    if result.returncode != expect:
        raise SystemExit(
            "unexpected command result\n"
            f"args={args!r}\n"
            f"expected={expect}\n"
            f"actual={result.returncode}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}\n"
        )

    return result


def qrr_entry(rule_id: str) -> dict:
    return {
        "rule_id": rule_id,
        "title": "fixture",
        "status": "ACTIVE",
        "normative_statement": "fixture SHALL validate",
        "verification_classes": ["TEST"],
        "verification_methods": ["fixture"],
        "applies_to_profiles": [],
        "architecture_refs": [],
        "requirement_refs": [],
        "assembly_rule_refs": [],
        "runtime_rule_refs": [],
        "security_rule_refs": [],
        "invariant_refs": [],
        "limit_refs": [],
        "protocol_rule_refs": [],
        "procedure_refs": [],
        "test_refs": [],
        "tool_refs": [],
        "evidence_refs": [],
        "first_required_milestone": "M0",
        "qualification_milestone": "M0",
        "prerequisite_refs": [],
        "waiver_refs": [],
        "supersedes": [],
        "superseded_by": [],
        "notes": ""
    }


# ---------------------------------------------------------------------------
# CASE 0 — repository path identity normalises both relative and absolute
# representations to the same canonical repository-relative value.
# ---------------------------------------------------------------------------

import importlib.util

spec = importlib.util.spec_from_file_location(
    "qualification_foundation_module",
    TOOL,
)

if spec is None or spec.loader is None:
    raise SystemExit("CASE 0 failed: unable to load qualification tool")

module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

relative_identity = module.repo_relative(Path("build/asmweb"))
absolute_identity = module.repo_relative(ROOT / "build/asmweb")

if relative_identity != "build/asmweb":
    raise SystemExit(
        f"CASE 0 failed: relative identity={relative_identity!r}"
    )

if absolute_identity != "build/asmweb":
    raise SystemExit(
        f"CASE 0 failed: absolute identity={absolute_identity!r}"
    )


# ---------------------------------------------------------------------------
# CASE 1 — canonical vocabulary / M0 record validate.
# ---------------------------------------------------------------------------

result = run("validate-foundation")

if "qualification_foundation_validation_status=0" not in result.stdout:
    raise SystemExit("CASE 1 failed")


# ---------------------------------------------------------------------------
# CASE 2 — valid structural QRR representation passes.
# ---------------------------------------------------------------------------

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "qrr.json"

    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "entries": [
                    qrr_entry("QUA-GOV-001")
                ]
            }
        ),
        encoding="utf-8",
    )

    run("validate-qrr", str(path))


# ---------------------------------------------------------------------------
# CASE 3 — duplicate rule identity fails.
# ---------------------------------------------------------------------------

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "qrr.json"

    entry = qrr_entry("QUA-GOV-001")

    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "entries": [entry, entry]
            }
        ),
        encoding="utf-8",
    )

    run("validate-qrr", str(path), expect=1)


# ---------------------------------------------------------------------------
# CASE 4 — unknown verification class fails.
# ---------------------------------------------------------------------------

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "qrr.json"

    entry = qrr_entry("QUA-GOV-001")
    entry["verification_classes"] = ["MAGIC"]

    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "entries": [entry]
            }
        ),
        encoding="utf-8",
    )

    run("validate-qrr", str(path), expect=1)


# ---------------------------------------------------------------------------
# CASE 5 — ACTIVE rule with no verification method fails.
# ---------------------------------------------------------------------------

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "qrr.json"

    entry = qrr_entry("QUA-GOV-001")
    entry["verification_methods"] = []

    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "entries": [entry]
            }
        ),
        encoding="utf-8",
    )

    run("validate-qrr", str(path), expect=1)


# ---------------------------------------------------------------------------
# CASE 6 — malformed rule identity fails.
# ---------------------------------------------------------------------------

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "qrr.json"

    entry = qrr_entry("BAD-RULE")

    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "entries": [entry]
            }
        ),
        encoding="utf-8",
    )

    run("validate-qrr", str(path), expect=1)


print("qualification_foundation_selftest_status=0")
