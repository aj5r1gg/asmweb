from __future__ import annotations

from pathlib import Path
import json
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]

TOOL = ROOT / "qualification/tools/qrr_slice.py"

CANONICAL = (
    ROOT
    / "qualification/qrr/slices/qrr-slice-01-governance.json"
)


def run(
    path: Path,
    expected: int,
) -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(TOOL),
            str(path),
        ],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    if result.returncode != expected:
        print("unexpected qrr slice result")
        print(f"expected={expected}")
        print(f"actual={result.returncode}")
        print("stdout:")
        print(result.stdout)
        print("stderr:")
        print(result.stderr)
        raise SystemExit(1)


# CASE 1 — canonical Slice-01 passes.
run(CANONICAL, 0)


canonical = json.loads(
    CANONICAL.read_text()
)


# CASE 2 — missing entry fails exact slice membership.
with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"].pop()
    data["entry_count"] -= 1

    path.write_text(
        json.dumps(data)
    )

    run(path, 1)


# CASE 3 — altered normative statement fails source authority.
with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"][0]["normative_statement"] += " altered"

    path.write_text(
        json.dumps(data)
    )

    run(path, 1)


# CASE 4 — unknown verification method fails.
with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"][0]["verification_methods"] = [
        "INVENTED_METHOD"
    ]

    path.write_text(
        json.dumps(data)
    )

    run(path, 1)


# CASE 5 — class not supported by method mapping fails.
with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"][0]["verification_classes"] = [
        "FUZZ"
    ]

    path.write_text(
        json.dumps(data)
    )

    run(path, 1)


# CASE 6 — empty verification mechanism fails.
with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"][0]["verification_methods"] = []

    path.write_text(
        json.dumps(data)
    )

    run(path, 1)



# CASE 7 — malformed JSON is a controlled validation failure.
with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    path.write_text(
        '{"schema_version": 1, "entries": [',
        encoding="utf-8",
    )

    run(path, 1)


print("qrr_slice_selftest_status=0")
