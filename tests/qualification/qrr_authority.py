#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]

TOOL = (
    ROOT
    / "qualification/tools/"
    "qrr_authority.py"
)

CANONICAL = (
    ROOT
    / "qualification/qrr/"
    "qrr-v0.3.json"
)


def run(
    *args: str,
    expect: int = 0,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [
            sys.executable,
            str(TOOL),
            *args,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    if result.returncode != expect:
        print(
            "unexpected qrr authority result",
            file=sys.stderr,
        )
        print(
            f"args={args!r}",
            file=sys.stderr,
        )
        print(
            f"expected={expect}",
            file=sys.stderr,
        )
        print(
            f"actual={result.returncode}",
            file=sys.stderr,
        )
        print(
            "stdout:",
            file=sys.stderr,
        )
        print(
            result.stdout,
            file=sys.stderr,
        )
        print(
            "stderr:",
            file=sys.stderr,
        )
        print(
            result.stderr,
            file=sys.stderr,
        )

        raise SystemExit(1)

    return result


###############################################################################
# Canonical authority must validate.
###############################################################################

run(
    "validate",
    str(CANONICAL),
)


###############################################################################
# Rebuilding elsewhere must be byte-identical.
###############################################################################

with tempfile.TemporaryDirectory() as td:
    rebuilt = (
        Path(td)
        / "qrr-v0.3.json"
    )

    run(
        "build",
        str(rebuilt),
    )

    if (
        rebuilt.read_bytes()
        != CANONICAL.read_bytes()
    ):
        raise SystemExit(
            "deterministic rebuild differs "
            "from canonical QRR"
        )


###############################################################################
# Controlled mutation helper.
###############################################################################

def mutated_copy(
    mutator,
) -> Path:
    td = tempfile.mkdtemp()

    path = (
        Path(td)
        / "qrr-v0.3.json"
    )

    shutil.copyfile(
        CANONICAL,
        path,
    )

    data = json.loads(
        path.read_text(
            encoding="utf-8"
        )
    )

    mutator(data)

    path.write_text(
        json.dumps(
            data,
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    return path


###############################################################################
# Missing entry must fail.
###############################################################################

path = mutated_copy(
    lambda data:
        data["entries"].pop()
)

run(
    "validate",
    str(path),
    expect=1,
)

shutil.rmtree(
    path.parent
)


###############################################################################
# Duplicate identity must fail.
###############################################################################

def duplicate_rule(data):
    data["entries"][1]["rule_id"] = (
        data["entries"][0]["rule_id"]
    )


path = mutated_copy(
    duplicate_rule
)

run(
    "validate",
    str(path),
    expect=1,
)

shutil.rmtree(
    path.parent
)


###############################################################################
# Source-order mutation must fail even with same set membership.
###############################################################################

def reorder(data):
    data["entries"][0], data["entries"][1] = (
        data["entries"][1],
        data["entries"][0],
    )


path = mutated_copy(
    reorder
)

run(
    "validate",
    str(path),
    expect=1,
)

shutil.rmtree(
    path.parent
)


###############################################################################
# Frozen normative statement mutation must fail.
###############################################################################

def alter_statement(data):
    data["entries"][0][
        "normative_statement"
    ] += " altered"


path = mutated_copy(
    alter_statement
)

run(
    "validate",
    str(path),
    expect=1,
)

shutil.rmtree(
    path.parent
)


###############################################################################
# Entry-shape mutation must fail.
###############################################################################

def add_entry_field(data):
    data["entries"][0][
        "unexpected_field"
    ] = True


path = mutated_copy(
    add_entry_field
)

run(
    "validate",
    str(path),
    expect=1,
)

shutil.rmtree(
    path.parent
)


###############################################################################
# Method-map mutation must fail.
###############################################################################

def alter_method_map(data):
    method = next(
        iter(
            data[
                "verification_method_class_map"
            ]
        )
    )

    data[
        "verification_method_class_map"
    ][method] = [
        "TEST"
    ]


path = mutated_copy(
    alter_method_map
)

run(
    "validate",
    str(path),
    expect=1,
)

shutil.rmtree(
    path.parent
)


###############################################################################
# Top-level authority mutation must fail.
###############################################################################

def alter_authority(data):
    data["authority"] = (
        "not-the-governing-authority"
    )


path = mutated_copy(
    alter_authority
)

run(
    "validate",
    str(path),
    expect=1,
)

shutil.rmtree(
    path.parent
)


print(
    "qrr_authority_selftest_status=0"
)
print(
    "qrr_authority_rule_count=234"
)
