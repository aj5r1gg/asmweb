#!/usr/bin/env python3
"""Non-effective generation publication and recovery tests."""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import ownership_generation as generation


def rejected(label, operation):
    try:
        operation()
    except (OSError, ValueError):
        print(label + "=REJECTED")
    else:
        raise AssertionError(label + " incorrectly accepted")


with tempfile.TemporaryDirectory(
    prefix="asmweb-generation-"
) as temp:
    store = Path(temp) / "publication"

    first = generation.publish(store)

    assert first["publication"] == "ATOMIC_ROOT_REPLACEMENT"
    assert first["effective_approval"] is False
    assert first["milestone_closed"] is False

    print("FIRST_PUBLICATION=PASS")

    verified = generation.verify(store)
    assert verified["generation_sha256"] == first["generation_sha256"]
    print("GENERATION_VERIFICATION=PASS")

    root = store / "effective-root.json"
    original_root = root.read_bytes()

    files = list((store / "generations").glob("*.json"))
    assert len(files) == 1

    record = files[0]
    original_record = record.read_bytes()

    again = generation.publish(store)
    assert again["publication"] == "ALREADY_CURRENT"
    assert root.read_bytes() == original_root
    print("IDEMPOTENT_PUBLICATION=PASS")

    record.write_bytes(original_record + b"x")
    rejected(
        "CORRUPTED_GENERATION",
        lambda: generation.verify(store),
    )
    rejected(
        "CORRUPTED_GENERATION_REPUBLICATION",
        lambda: generation.publish(store),
    )
    record.write_bytes(original_record)

    root.write_bytes(original_root + b"x")
    rejected(
        "CORRUPTED_ROOT",
        lambda: generation.verify(store),
    )
    rejected(
        "CORRUPTED_ROOT_REPUBLICATION",
        lambda: generation.publish(store),
    )
    root.write_bytes(original_root)

    record.unlink()
    rejected(
        "MISSING_GENERATION",
        lambda: generation.verify(store),
    )
    rejected(
        "MISSING_GENERATION_REPUBLICATION",
        lambda: generation.publish(store),
    )
    record.write_bytes(original_record)

    assert generation.verify(store)["result"] == (
        "NON_EFFECTIVE_GENERATION_VERIFIED"
    )
    print("RECOVERY_AFTER_EXPLICIT_RESTORATION=PASS")

    # Replacing a referenced record with a symlink must fail.
    saved = store / "saved-record"
    shutil.copyfile(record, saved)
    record.unlink()
    record.symlink_to(saved)

    rejected(
        "SYMLINK_GENERATION",
        lambda: generation.verify(store),
    )

    record.unlink()
    shutil.copyfile(saved, record)

    # Independent command-line verification.
    cli = subprocess.run(
        [
            sys.executable, "-B",
            str(
                ROOT / "qualification/tools/"
                "ownership_generation.py"
            ),
            "verify",
            "--store", str(store),
        ],
        capture_output=True,
        text=True,
    )

    assert cli.returncode == 0, (
        f"CLI failure:\n{cli.stdout}\n{cli.stderr}"
    )

    result = json.loads(cli.stdout)
    assert result["effective_approval"] is False
    print("CLI_VERIFICATION=PASS")

print("EFFECTIVE_APPROVALS=0")
print("OWNERSHIP_GENERATION=PASS")
