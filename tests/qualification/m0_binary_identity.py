#!/usr/bin/env python3
"""REQ-M0-005: verify build-specific binary identity and mutation response."""

import hashlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import m0_effective_configuration as effective


def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    original_binary = effective.BINARY

    require(original_binary.is_file(), "PRODUCTION_BINARY_MISSING")

    binary_bytes = original_binary.read_bytes()
    require(len(binary_bytes) > 0, "EMPTY_BINARY")

    stored = json.loads(effective.OUTPUT.read_text())
    derived = effective.build()

    require(
        effective.OUTPUT.read_bytes() == effective.canonical(derived),
        "PUBLISHED_CONFIGURATION_STALE",
    )

    require(
        derived["configuration"]["binary_sha256"] == sha(binary_bytes),
        "BINARY_HASH_DISAGREEMENT",
    )

    require(
        stored["effective_configuration_sha256"]
        == sha(effective.canonical(stored["configuration"])),
        "CONFIGURATION_HASH_DISAGREEMENT",
    )

    print("PRODUCTION_BINARY_HASH=VERIFIED")
    print("PUBLISHED_CONFIGURATION=REPRODUCED")

    with tempfile.TemporaryDirectory(
        prefix="asmweb-m0-identity-"
    ) as dirname:
        altered_binary = Path(dirname) / "altered-asmweb"

        # Mutate a disposable copy. Never alter the actual executable.
        altered_binary.write_bytes(
            binary_bytes + b"ASMWEB-M0-IDENTITY-NEGATIVE-TEST"
        )

        try:
            effective.BINARY = altered_binary
            altered = effective.build()
        finally:
            effective.BINARY = original_binary

        require(
            altered["configuration"]["binary_sha256"]
            == sha(altered_binary.read_bytes()),
            "MUTATED_BINARY_HASH_DISAGREEMENT",
        )

        require(
            altered["configuration"]["binary_sha256"]
            != derived["configuration"]["binary_sha256"],
            "MUTATED_BINARY_RETAINED_IDENTITY",
        )

        require(
            altered["effective_configuration_sha256"]
            != derived["effective_configuration_sha256"],
            "MUTATED_CONFIGURATION_RETAINED_IDENTITY",
        )

        require(
            effective.canonical(altered)
            != effective.OUTPUT.read_bytes(),
            "ALTERED_BUILD_MATCHED_PUBLISHED_CONFIGURATION",
        )

        print("ALTERED_BINARY_IDENTITY=DIFFERENT")
        print("ALTERED_CONFIGURATION_IDENTITY=DIFFERENT")
        print("STALE_PUBLICATION=REJECTED")

    require(
        effective.BINARY == original_binary,
        "BINARY_PATH_NOT_RESTORED",
    )
    require(
        effective.OUTPUT.read_bytes() == effective.canonical(
            effective.build()
        ),
        "ORIGINAL_PUBLICATION_NOT_REPRODUCIBLE",
    )

    require(
        stored["normative_ir_complete"] is False,
        "FALSE_IR_AUTHORITY",
    )
    # The nine-limit M0 production LR and its reconciled ELM have
    # been authoritatively adopted. This does not imply that the
    # complete normative IR or formal M0 qualification is complete.
    require(
        stored["normative_lr_complete"] is True,
        "M0_LR_AUTHORITY_MISSING",
    )
    require(
        stored["authoritative_elm_adopted"] is True,
        "M0_ELM_ADOPTION_MISSING",
    )
    require(
        stored["formal_m0_qualification"] is False,
        "FALSE_M0_QUALIFICATION",
    )

    print("ORIGINAL_BINARY=UNCHANGED")
    print("ORIGINAL_CONFIGURATION=UNCHANGED")
    print("M0_PRODUCTION_LR_ELM=ADOPTED")
    print("FULL_IR_AND_FORMAL_M0_QUALIFICATION=NOT_CLAIMED")
    print("REQ_M0_005_ENGINEERING_QUALIFICATION=PASS")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError, KeyError, TypeError) as exc:
        print(
            "REQ_M0_005_ENGINEERING_QUALIFICATION=FAIL:",
            exc,
            file=sys.stderr,
        )
        raise SystemExit(1)
