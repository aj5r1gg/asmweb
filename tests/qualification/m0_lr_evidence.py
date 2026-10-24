#!/usr/bin/env python3
"""Verify production LR evidence and independently reject forged adoption."""

import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/tools"))

import m0_normative_lr as lr

EXPECTED = set(lr.M0_EVIDENCE_REFS)

def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)

def main():
    lr.verify()

    register = json.loads(lr.OUTPUT.read_text())
    production = json.loads(
        (ROOT / "qualification/limits/m0-limit-register-v0.1.json")
        .read_text()
    )
    configuration = json.loads(
        (ROOT / "qualification/limits/m0-effective-configuration-v0.1.json")
        .read_text()
    )

    entries = register["entries"]
    production_ids = {
        e["limit_id"] for e in production["entries"]
    }

    require(len(entries) == 9, "WRONG_ENTRY_COUNT")
    require(
        {e["limit_id"] for e in entries} == production_ids,
        "LIMIT_IDENTITY_MISMATCH",
    )

    for entry in entries:
        require(
            set(entry["evidence_refs"]) == EXPECTED,
            "INCOMPLETE_EVIDENCE=" + entry["limit_id"],
        )
        require(
            entry["status"] == (
                "ACTIVE" if register["authoritative_lr_complete"]
                else "PROVISIONAL"
            ),
            "INCONSISTENT_LIMIT_STATUS",
        )
        for ref in entry["evidence_refs"]:
            target = (ROOT / ref).resolve()
            require(
                target.is_relative_to(ROOT.resolve()),
                "PATH_ESCAPE",
            )
            require(target.is_file(), "MISSING_ARTIFACT=" + ref)

    require(
        register["authoritative_lr_complete"] is True,
        "M0_LR_ADOPTION_NOT_ESTABLISHED",
    )
    require(
        configuration["normative_lr_complete"] is True
        and configuration["authoritative_elm_adopted"] is True,
        "M0_ELM_ADOPTION_NOT_ESTABLISHED",
    )

    # Verify that neither an ACTIVE flag nor a complete flag can
    # override the NASM-derived canonical register and adoption record.
    # Never mutate the live normative Limit Register.
    # Redirect the existing verifier to an isolated temporary file.
    import tempfile

    original_path = lr.OUTPUT
    original = original_path.read_bytes()

    with tempfile.TemporaryDirectory(prefix="asmweb-m0-lr-test-") as tmp:
        temporary_path = Path(tmp) / "normative-lr.json"

        try:
            lr.OUTPUT = temporary_path

            def reject_tampering(change, label):
                forged = json.loads(original)
                change(forged)
                forged_bytes = lr.canonical(forged)

                require(
                    forged_bytes != original,
                    "INEFFECTIVE_MUTATION=" + label,
                )

                temporary_path.write_bytes(forged_bytes)

                try:
                    lr.verify()
                except (ValueError, AssertionError):
                    pass
                else:
                    raise RuntimeError(
                        "FORGED_ADOPTION_ACCEPTED=" + label
                    )

            reject_tampering(
                lambda d: d.update(
                    authoritative_lr_complete=False
                ),
                "FALSE_COMPLETION",
            )

            reject_tampering(
                lambda d: d["entries"][0].update(
                    status="PROVISIONAL"
                ),
                "STATUS_DOWNGRADE",
            )

            reject_tampering(
                lambda d: d["entries"][0].update(
                    configured_value=2
                ),
                "CAPACITY_MUTATION",
            )

        finally:
            lr.OUTPUT = original_path

    require(
        original_path.read_bytes() == original,
        "LIVE_REGISTER_MODIFIED",
    )

    lr.verify()
    print("FORGED_LR_ADOPTION_MUTATIONS=REJECTED")
    require(
        bool(configuration.get("effective_configuration_sha256")),
        "CONFIGURATION_IDENTITY_MISSING",
    )

    # Dimensional mismatches and malformed numerical bounds must fail.
    sample = entries[0]
    for changes in (
        {"unit": "BYTES"},
        {"dimension": "TIME"},
        {"quantity": "DURATION"},
        {"expression": "configured_value / 2"},
        {"rounding_semantics": "NEAREST"},
        {"maximum_permitted": -1},
        {"configured_value": True},
        {"configured_value": 2},
    ):
        altered = copy.deepcopy(sample)
        altered.update(changes)
        try:
            lr.validate_m0_dimensions(altered)
        except ValueError:
            pass
        else:
            raise RuntimeError("INVALID_M0_DIMENSION_ACCEPTED=" + str(changes))

    print("M0_DIMENSION_AND_BOUND_MUTATIONS=REJECTED")

    print("CANONICAL_LIMIT_IDENTITIES=9/9")
    print("CONTROLLED_EVIDENCE_MAPPINGS=9/9")
    print("EVIDENCE_PATHS=VERIFIED")
    print("FALSE_APPROVAL_PREVENTION=PASS")
    print("M0_LR_EVIDENCE_QUALIFICATION=PASS")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError) as exc:
        print("M0_LR_EVIDENCE_QUALIFICATION=FAIL:", exc,
              file=sys.stderr)
        sys.exit(1)
