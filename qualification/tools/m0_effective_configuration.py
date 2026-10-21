#!/usr/bin/env python3
"""Derive the M0 effective configuration from actual production materialisation.

The document is a build-specific implementation projection. It is not a
substitute for adoption of the normative Invariant or Limit Registers.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import production_limit_manifest as production

ROOT = Path(__file__).resolve().parents[2]

OUTPUT = (
    ROOT / "qualification/limits/"
    "m0-effective-configuration-v0.1.json"
)

BINARY = ROOT / "build/asmweb"

FORMAT = "ASMWEB_M0_EFFECTIVE_CONFIGURATION_V1"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(document):
    return (
        json.dumps(
            document,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ) + "\n"
    ).encode("utf-8")


def build():
    # The existing derivation validates the NASM-resolved production
    # OLR/MOT/RCT projection and its complete assembly include closure.
    projection = production.validate()

    require(BINARY.is_file(), "production binary not built")
    binary_sha = sha(BINARY.read_bytes())

    definitions = projection["definitions"]
    entries = projection["mot_entries"]

    require(
        len(definitions) == len(entries)
        == projection["production_mot_count"],
        "production entry count mismatch",
    )

    limits = []
    seen = set()
    total_direct = 0
    total_overhead = 0

    for definition, entry in zip(definitions, entries):
        require(
            definition["limit_id"] == entry["limit_id"]
            and definition["object_id"] == entry["object_id"],
            "definition and MOT disagree",
        )

        identity = entry["limit_id"]
        require(
            type(identity) is int
            and identity > 0
            and identity not in seen,
            "invalid runtime limit identity",
        )
        seen.add(identity)

        maximum = entry["maximum_count"]
        physical = entry["physical_capacity"]
        configured = entry["configured_capacity"]

        require(
            all(
                type(value) is int and value > 0
                for value in (maximum, physical, configured)
            ),
            "invalid capacity",
        )
        require(
            configured <= physical <= maximum,
            "unprovisionable capacity",
        )

        stride = entry["effective_stride_bytes"]
        metadata = entry["pool_metadata_bytes"]
        mapping = entry["mapping_overhead_bytes"]

        require(
            type(stride) is int and stride > 0
            and type(metadata) is int and metadata >= 0
            and type(mapping) is int and mapping >= 0,
            "invalid memory accounting",
        )

        direct = configured * stride
        overhead = metadata + mapping

        require(
            direct <= (1 << 64) - 1
            and overhead <= (1 << 64) - 1,
            "memory arithmetic overflow",
        )

        total_direct += direct
        total_overhead += overhead

        limits.append({
            "runtime_limit_id": identity,
            "runtime_limit_symbol":
                definition["limit_symbol"],
            "runtime_object_id": entry["object_id"],
            "runtime_object_symbol":
                definition["object_symbol"],
            "maximum_count": maximum,
            "physical_capacity": physical,
            "configured_capacity": configured,
            "effective_count": configured,
            "effective_stride_bytes": stride,
            "direct_capacity_bytes": direct,
            "overhead_bytes": overhead,
            "normative_lim_id": None,
            "normative_mapping_status":
                "PENDING_LR_RECONCILIATION",
        })

    require(
        total_direct
        == projection["M_direct_capacity_max"],
        "direct memory ceiling mismatch",
    )

    require(
        total_direct + total_overhead <= (1 << 64) - 1,
        "aggregate memory overflow",
    )

    # Identify the exact build, effective numerical capacities,
    # assembly dependency closure and derivation-tool authority.
    configuration = {
        "schema_version": 1,
        "format": FORMAT,
        "scope": "M0_PRODUCTION_IMPLEMENTATION",
        "binary_sha256": binary_sha,
        "production_projection_sha256": sha(
            production.canonical(projection)
        ),
        "assembly_dependency_closure_sha256":
            projection[
                "assembly_dependency_closure_sha256"
            ],
        "derivation_tool_sha256":
            projection["derivation_tool_sha256"],
        "production_mot_count":
            projection["production_mot_count"],
        "production_rct_count":
            projection["production_rct_count"],
        "limits": sorted(
            limits,
            key=lambda item: item["runtime_limit_id"],
        ),
        "total_direct_capacity_bytes": total_direct,
        "total_overhead_bytes": total_overhead,
        "total_projected_bytes":
            total_direct + total_overhead,
    }

    document = {
        "schema_version": 1,
        "document_type":
            "ASMWEB_M0_EFFECTIVE_CONFIGURATION_PUBLICATION",
        "configuration": configuration,
        "effective_configuration_sha256":
            sha(canonical(configuration)),
        "normative_ir_complete": False,
        "normative_lr_complete": False,
        "authoritative_elm_adopted": False,
        "formal_m0_qualification": False,
    }

    return document


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "action", choices=("publish", "verify")
    )
    args = parser.parse_args()

    try:
        expected = canonical(build())

        if args.action == "publish":
            require(
                not OUTPUT.exists() and not OUTPUT.is_symlink(),
                "published configuration already exists",
            )
            OUTPUT.parent.mkdir(
                parents=True, exist_ok=True
            )
            with OUTPUT.open("xb") as stream:
                stream.write(expected)
                stream.flush()
                import os
                os.fsync(stream.fileno())

        actual = OUTPUT.read_bytes()
        require(
            actual == expected,
            "configuration differs from production build",
        )

        document = json.loads(actual)
        configuration = document["configuration"]

        print(
            "EFFECTIVE_CONFIGURATION_SHA256="
            + document["effective_configuration_sha256"]
        )
        print(
            "PRODUCTION_BINARY_SHA256="
            + configuration["binary_sha256"]
        )
        print(
            "RUNTIME_LIMIT_COUNT="
            + str(configuration["production_mot_count"])
        )
        print(
            "DIRECT_CAPACITY_BYTES="
            + str(
                configuration[
                    "total_direct_capacity_bytes"
                ]
            )
        )
        print("CONFIGURATION_PUBLICATION=VERIFIED")
        print("NORMATIVE_LR_COMPLETE=False")
        return 0

    except (
        ValueError, OSError, KeyError, TypeError,
    ) as exc:
        print(
            f"CONFIGURATION_PUBLICATION=FAIL: {exc}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
