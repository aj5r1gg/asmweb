from __future__ import annotations

from pathlib import Path
import json
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]

TOOL = ROOT / "qualification/tools/qrr_slice.py"

SLICE_01 = (
    ROOT
    / "qualification/qrr/slices/qrr-slice-01-governance.json"
)

SLICE_02 = (
    ROOT
    / "qualification/qrr/slices/"
    "qrr-slice-02-evidence-traceability.json"
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
run(SLICE_01, 0)


# CASE 2 — canonical Slice-02 passes.
run(SLICE_02, 0)


canonical = json.loads(
    SLICE_01.read_text()
)


# CASE 3 — missing entry fails exact slice membership.
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


# CASE 4 — altered normative statement fails source authority.
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


# CASE 5 — unknown verification method fails.
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


# CASE 6 — class not supported by method mapping fails.
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


# CASE 7 — empty verification mechanism fails.
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



# CASE 8 — malformed JSON is a controlled validation failure.
with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    path.write_text(
        '{"schema_version": 1, "entries": [',
        encoding="utf-8",
    )

    run(path, 1)



# CASE 9 — canonical slices do not overlap and aggregate to 85 authored rules.
slice_01_data = json.loads(
    SLICE_01.read_text()
)

slice_02_data = json.loads(
    SLICE_02.read_text()
)

slice_01_ids = {
    entry["rule_id"]
    for entry in slice_01_data["entries"]
}

slice_02_ids = {
    entry["rule_id"]
    for entry in slice_02_data["entries"]
}

overlap = slice_01_ids & slice_02_ids

if overlap:
    raise SystemExit(
        "CASE 9 failed: slice overlap: "
        + ",".join(sorted(overlap))
    )

if len(slice_01_ids | slice_02_ids) != 85:
    raise SystemExit(
        "CASE 9 failed: expected 85 total authored rules"
    )


print("qrr_slice_selftest_status=0")
