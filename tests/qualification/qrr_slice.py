from __future__ import annotations

from pathlib import Path
import json
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]

TOOL = (
    ROOT
    / "qualification/tools/qrr_slice.py"
)

SLICE_DIR = (
    ROOT
    / "qualification/qrr/slices"
)

SOURCE = (
    ROOT
    / "qualification/qrr/qrr-source-v0.3.json"
)

SLICE_01 = (
    SLICE_DIR
    / "qrr-slice-01-governance.json"
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
        print(f"path={path}")
        print(f"expected={expected}")
        print(f"actual={result.returncode}")
        print("stdout:")
        print(result.stdout)
        print("stderr:")
        print(result.stderr)
        raise SystemExit(1)


###############################################################################
# CASE 1 — discover all canonical authored slices.
###############################################################################

canonical_slices = sorted(
    SLICE_DIR.glob("qrr-slice-*.json")
)

if not canonical_slices:
    raise SystemExit(
        "CASE 1 failed: no canonical QRR slices found"
    )

if SLICE_01 not in canonical_slices:
    raise SystemExit(
        "CASE 1 failed: Slice 01 missing"
    )


###############################################################################
# CASE 2 — every canonical slice validates independently.
###############################################################################

for path in canonical_slices:
    run(path, 0)


###############################################################################
# CASE 3 — canonical slices do not overlap and contain only frozen QRR IDs.
###############################################################################

source = json.loads(
    SOURCE.read_text(encoding="utf-8")
)

source_ids = {
    entry["rule_id"]
    for entry in source["entries"]
}

authored_ids: set[str] = set()

for path in canonical_slices:
    data = json.loads(
        path.read_text(encoding="utf-8")
    )

    for entry in data["entries"]:
        rule_id = entry["rule_id"]

        if rule_id in authored_ids:
            raise SystemExit(
                "CASE 3 failed: duplicate rule across slices: "
                f"{rule_id}"
            )

        if rule_id not in source_ids:
            raise SystemExit(
                "CASE 3 failed: unknown authored rule: "
                f"{rule_id}"
            )

        authored_ids.add(rule_id)


###############################################################################
# Mutation fixture.
###############################################################################

canonical = json.loads(
    SLICE_01.read_text(encoding="utf-8")
)


###############################################################################
# CASE 4 — missing entry fails exact declared-namespace membership.
###############################################################################

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"].pop()
    data["entry_count"] -= 1

    path.write_text(
        json.dumps(data),
        encoding="utf-8",
    )

    run(path, 1)


###############################################################################
# CASE 5 — altered normative statement fails frozen source authority.
###############################################################################

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"][0][
        "normative_statement"
    ] += " altered"

    path.write_text(
        json.dumps(data),
        encoding="utf-8",
    )

    run(path, 1)


###############################################################################
# CASE 6 — unknown verification method fails.
###############################################################################

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"][0][
        "verification_methods"
    ] = [
        "INVENTED_METHOD"
    ]

    path.write_text(
        json.dumps(data),
        encoding="utf-8",
    )

    run(path, 1)


###############################################################################
# CASE 7 — class not supported by method mapping fails.
###############################################################################

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"][0][
        "verification_classes"
    ] = [
        "FUZZ"
    ]

    path.write_text(
        json.dumps(data),
        encoding="utf-8",
    )

    run(path, 1)


###############################################################################
# CASE 8 — active rule without verification mechanism fails.
###############################################################################

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    data = json.loads(
        json.dumps(canonical)
    )

    data["entries"][0][
        "verification_methods"
    ] = []

    path.write_text(
        json.dumps(data),
        encoding="utf-8",
    )

    run(path, 1)


###############################################################################
# CASE 9 — malformed JSON is a controlled validation failure.
###############################################################################

with tempfile.TemporaryDirectory() as td:
    path = Path(td) / "slice.json"

    path.write_text(
        '{"schema_version": 1, "entries": [',
        encoding="utf-8",
    )

    run(path, 1)


print("qrr_slice_selftest_status=0")
print(
    f"qrr_slice_canonical_file_count="
    f"{len(canonical_slices)}"
)
print(
    f"qrr_slice_authored_rule_count="
    f"{len(authored_ids)}"
)
