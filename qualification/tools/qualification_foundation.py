#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]

VOCAB_PATH = ROOT / "qualification/schema/qualification-vocabulary.json"
QRR_SCHEMA_PATH = ROOT / "qualification/qrr/qrr-schema.json"
QRR_MEMBERSHIP_PATH = (
    ROOT / "qualification/qrr/qrr-membership-v0.3.json"
)
QRR_SOURCE_PATH = (
    ROOT / "qualification/qrr/qrr-source-v0.3.json"
)
M0_PATH = ROOT / "qualification/milestones/M0.json"

PRODUCTION_BINARY = ROOT / "build/asmweb"

QUALIFICATION_SPEC = "AsmWeb — Qualification & Verification Specification v0.3"

EXPECTED_IMPLEMENTATION_STATES = [
    "NOT_STARTED",
    "IN_PROGRESS",
    "IMPLEMENTED",
    "QUALIFICATION_PENDING",
    "QUALIFIED",
    "FAILED",
    "BLOCKED",
    "DEFERRED",
    "NOT_APPLICABLE",
]

EXPECTED_RESULTS = [
    "PASS",
    "FAIL",
    "UNSUPPORTED",
    "NOT_RUN",
    "INCONCLUSIVE",
    "EXPECTED_REJECTION",
]

EXPECTED_QRR_STATUSES = [
    "ACTIVE",
    "DEFERRED",
    "SUPERSEDED",
    "RETIRED",
]

EXPECTED_VERIFICATION_CLASSES = [
    "INSPECTION",
    "TEST",
    "CONFORMANCE",
    "INTEROPERABILITY",
    "BROWSER",
    "FUZZ",
    "RESOURCE",
    "BENCHMARK",
    "ENDURANCE",
]

MANIFEST_REQUIRED_FIELDS = [
    "qualification_id",
    "AsmWeb_version",
    "requirements_baseline",
    "architecture_baseline",
    "assembly_standard_version",
    "runtime_specification_version",
    "security_specification_version",
    "limits_register_version",
    "protocol_specification_version",
    "qualification_specification_version",
    "capability_profile_version",
    "standards_register_version",
    "source_commit",
    "binary_hash",
    "configuration_identity",
    "effective_limit_manifest",
    "build_manifest",
    "provenance_manifest_ref",
    "host_manifest",
    "suite_versions",
    "instrumentation_state",
    "virtual_time_state",
    "deterministic_entropy_state",
    "implementation_variant_state",
    "requirement_results",
    "assembly_rule_results",
    "runtime_rule_results",
    "security_rule_results",
    "invariant_results",
    "limit_results",
    "protocol_rule_results",
    "qualification_rule_results",
    "correctness_results",
    "conformance_results",
    "interop_results",
    "browser_results",
    "fuzz_results",
    "fault_injection_results",
    "resource_results",
    "RAF_results",
    "performance_results",
    "endurance_results",
    "reclamation_results",
    "milestone_results",
    "known_failures",
    "unsupported_features",
    "waivers",
    "artifact_digests",
    "timestamp",
]

QRR_REQUIRED_FIELDS = [
    "rule_id",
    "title",
    "status",
    "normative_statement",
    "verification_classes",
    "verification_methods",
    "applies_to_profiles",
    "architecture_refs",
    "requirement_refs",
    "assembly_rule_refs",
    "runtime_rule_refs",
    "security_rule_refs",
    "invariant_refs",
    "limit_refs",
    "protocol_rule_refs",
    "procedure_refs",
    "test_refs",
    "tool_refs",
    "evidence_refs",
    "first_required_milestone",
    "qualification_milestone",
    "prerequisite_refs",
    "waiver_refs",
    "supersedes",
    "superseded_by",
    "notes",
]

QRR_ID_RE = re.compile(r"^QUA-[A-Z]{3}-[0-9]{3}$")


class ValidationError(Exception):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValidationError(f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValidationError(
            f"invalid JSON in {path}: line {exc.lineno}: {exc.msg}"
        ) from exc


def dump_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run_text(*argv: str) -> str:
    result = subprocess.run(
        argv,
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def git_commit() -> str:
    return run_text("git", "rev-parse", "HEAD")


def git_clean() -> bool:
    return run_text("git", "status", "--porcelain=v1") == ""


def tool_version(argv: list[str]) -> str:
    result = subprocess.run(
        argv,
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    first = result.stdout.splitlines()
    return first[0].strip() if first else ""


def validate_vocabulary() -> None:
    data = load_json(VOCAB_PATH)

    if data.get("implementation_states") != EXPECTED_IMPLEMENTATION_STATES:
        raise ValidationError("implementation-state vocabulary mismatch")

    if data.get("qualification_results") != EXPECTED_RESULTS:
        raise ValidationError("qualification-result vocabulary mismatch")

    if data.get("qrr_rule_statuses") != EXPECTED_QRR_STATUSES:
        raise ValidationError("QRR rule-status vocabulary mismatch")

    if data.get("verification_classes") != EXPECTED_VERIFICATION_CLASSES:
        raise ValidationError("verification-class vocabulary mismatch")


def canonical_membership_digest(rule_ids: list[str]) -> str:
    payload = "".join(
        f"{rule_id}\n"
        for rule_id in sorted(rule_ids)
    )

    return hashlib.sha256(
        payload.encode("utf-8")
    ).hexdigest()


def validate_qrr_membership_authority() -> set[str]:
    data = load_json(QRR_MEMBERSHIP_PATH)

    if not isinstance(data, dict):
        raise ValidationError(
            "QRR membership authority root must be an object"
        )

    rule_ids = data.get("rule_ids")

    if not isinstance(rule_ids, list):
        raise ValidationError(
            "QRR membership authority rule_ids must be an array"
        )

    if not all(isinstance(item, str) for item in rule_ids):
        raise ValidationError(
            "QRR membership authority identities must be strings"
        )

    invalid = [
        item for item in rule_ids
        if not QRR_ID_RE.fullmatch(item)
    ]

    if invalid:
        raise ValidationError(
            "QRR membership authority contains invalid identities: "
            + ", ".join(invalid)
        )

    if len(rule_ids) != len(set(rule_ids)):
        raise ValidationError(
            "QRR membership authority contains duplicate identities"
        )

    declared_count = data.get("rule_count")

    if declared_count != len(rule_ids):
        raise ValidationError(
            "QRR membership declared rule_count does not match identities"
        )

    expected_digest = data.get(
        "canonical_membership_sha256"
    )

    actual_digest = canonical_membership_digest(rule_ids)

    if expected_digest != actual_digest:
        raise ValidationError(
            "QRR membership canonical digest mismatch: "
            f"expected={expected_digest!r} "
            f"actual={actual_digest!r}"
        )

    return set(rule_ids)


def canonical_rule_text_digest(
    entries: list[dict[str, object]]
) -> str:
    payload = "".join(
        (
            f"{entry['rule_id']}\t"
            f"{entry['normative_statement']}\n"
        )
        for entry in entries
    )

    return hashlib.sha256(
        payload.encode("utf-8")
    ).hexdigest()


def validate_qrr_source_authority() -> dict[str, str]:
    membership_data = load_json(QRR_MEMBERSHIP_PATH)
    membership_ids = membership_data["rule_ids"]

    source = load_json(QRR_SOURCE_PATH)

    if not isinstance(source, dict):
        raise ValidationError(
            "QRR source authority root must be an object"
        )

    entries = source.get("entries")

    if not isinstance(entries, list):
        raise ValidationError(
            "QRR source authority entries must be an array"
        )

    if source.get("rule_count") != len(entries):
        raise ValidationError(
            "QRR source declared count does not match entries"
        )

    if len(entries) != len(membership_ids):
        raise ValidationError(
            "QRR source count does not match membership authority"
        )

    by_id: dict[str, str] = {}

    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ValidationError(
                f"QRR source entry {index} must be an object"
            )

        rule_id = entry.get("rule_id")
        statement = entry.get("normative_statement")

        if not isinstance(rule_id, str):
            raise ValidationError(
                f"QRR source entry {index} has invalid rule_id"
            )

        if not isinstance(statement, str) or not statement.strip():
            raise ValidationError(
                f"{rule_id}: empty normative statement"
            )

        if rule_id in by_id:
            raise ValidationError(
                f"duplicate QRR source identity: {rule_id}"
            )

        by_id[rule_id] = statement

    actual_ids = list(by_id)

    if actual_ids != membership_ids:
        raise ValidationError(
            "QRR source order/membership does not exactly match "
            "membership authority"
        )

    expected_digest = source.get(
        "canonical_rule_text_sha256"
    )

    actual_digest = canonical_rule_text_digest(
        entries
    )

    if expected_digest != actual_digest:
        raise ValidationError(
            "QRR source canonical text digest mismatch: "
            f"expected={expected_digest!r} "
            f"actual={actual_digest!r}"
        )

    frozen_v03_digest = (
        "464b32f9f01f60ef5f145bd393b715cc"
        "bcab46171e53df864796c92fd75429f6"
    )

    if actual_digest != frozen_v03_digest:
        raise ValidationError(
            "QRR source does not match frozen Qualification "
            "Specification v0.3 rule-text authority"
        )

    return by_id


def validate_qrr_exact_membership(path: Path) -> None:
    authority = validate_qrr_membership_authority()

    data = load_json(path)

    if not isinstance(data, dict):
        raise ValidationError("QRR root must be an object")

    entries = data.get("entries")

    if not isinstance(entries, list):
        raise ValidationError("QRR entries must be an array")

    identities: list[str] = []

    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ValidationError(
                f"QRR entry {index} must be an object"
            )

        rule_id = entry.get("rule_id")

        if not isinstance(rule_id, str):
            raise ValidationError(
                f"QRR entry {index} has no string rule_id"
            )

        identities.append(rule_id)

    if len(identities) != len(set(identities)):
        raise ValidationError(
            "QRR exact membership contains duplicate identities"
        )

    actual = set(identities)

    missing = sorted(authority - actual)
    extra = sorted(actual - authority)

    if missing or extra:
        parts: list[str] = []

        if missing:
            parts.append(
                "missing=" + ",".join(missing)
            )

        if extra:
            parts.append(
                "extra=" + ",".join(extra)
            )

        raise ValidationError(
            "QRR exact membership mismatch: "
            + " ".join(parts)
        )


def validate_qrr_structure(path: Path) -> None:
    validate_qrr_membership_authority()

    data = load_json(path)

    if not isinstance(data, dict):
        raise ValidationError("QRR root must be an object")

    entries = data.get("entries")

    if not isinstance(entries, list):
        raise ValidationError("QRR entries must be an array")

    seen: set[str] = set()

    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ValidationError(f"QRR entry {index} must be an object")

        missing = [
            field for field in QRR_REQUIRED_FIELDS
            if field not in entry
        ]
        if missing:
            raise ValidationError(
                f"QRR entry {index} missing fields: {', '.join(missing)}"
            )

        rule_id = entry["rule_id"]

        if not isinstance(rule_id, str) or not QRR_ID_RE.fullmatch(rule_id):
            raise ValidationError(
                f"QRR entry {index} invalid rule_id: {rule_id!r}"
            )

        if rule_id in seen:
            raise ValidationError(f"duplicate QRR rule identity: {rule_id}")

        seen.add(rule_id)

        status = entry["status"]
        if status not in EXPECTED_QRR_STATUSES:
            raise ValidationError(
                f"{rule_id}: invalid QRR status {status!r}"
            )

        for array_field in (
            "verification_classes",
            "verification_methods",
            "applies_to_profiles",
            "architecture_refs",
            "requirement_refs",
            "assembly_rule_refs",
            "runtime_rule_refs",
            "security_rule_refs",
            "invariant_refs",
            "limit_refs",
            "protocol_rule_refs",
            "procedure_refs",
            "test_refs",
            "tool_refs",
            "evidence_refs",
            "prerequisite_refs",
            "waiver_refs",
            "supersedes",
            "superseded_by",
        ):
            if not isinstance(entry[array_field], list):
                raise ValidationError(
                    f"{rule_id}: {array_field} must be an array"
                )

        unknown_classes = sorted(
            set(entry["verification_classes"])
            - set(EXPECTED_VERIFICATION_CLASSES)
        )
        if unknown_classes:
            raise ValidationError(
                f"{rule_id}: unknown verification classes: "
                + ", ".join(unknown_classes)
            )

        if status == "ACTIVE":
            if not entry["verification_classes"]:
                raise ValidationError(
                    f"{rule_id}: ACTIVE rule has no verification class"
                )

            if not entry["verification_methods"]:
                raise ValidationError(
                    f"{rule_id}: ACTIVE rule has no verification method"
                )

    # Deliberate boundary:
    #
    # This routine validates representation, duplicate identity, vocabulary
    # and minimum ACTIVE-rule mechanism presence.
    #
    # It does NOT yet establish QUA-REG-002 or QUA-REG-004 because complete
    # authoritative registries and exact specification membership are not yet
    # populated into this repository.


def validate_m0() -> None:
    data = load_json(M0_PATH)

    required = [
        "milestone_id",
        "first_mandatory_requirement_refs",
        "inherited_regression_refs",
        "prerequisite_refs",
        "new_rule_refs",
        "required_verification_refs",
        "result_refs",
        "known_failures",
        "blocked_items",
        "waivers",
        "deferred_items",
        "closure_status",
        "evidence_refs",
    ]

    missing = [field for field in required if field not in data]
    if missing:
        raise ValidationError(
            "M0 milestone record missing fields: " + ", ".join(missing)
        )

    if data["milestone_id"] != "M0":
        raise ValidationError("milestone record must identify M0")

    if data.get("implementation_state") not in EXPECTED_IMPLEMENTATION_STATES:
        raise ValidationError("invalid M0 implementation_state")

    if data["closure_status"] not in EXPECTED_IMPLEMENTATION_STATES:
        raise ValidationError("invalid M0 closure_status")

    for field in (
        "first_mandatory_requirement_refs",
        "inherited_regression_refs",
        "prerequisite_refs",
        "new_rule_refs",
        "required_verification_refs",
        "result_refs",
        "known_failures",
        "blocked_items",
        "waivers",
        "deferred_items",
        "evidence_refs",
    ):
        if not isinstance(data[field], list):
            raise ValidationError(f"M0 {field} must be an array")

    if data["blocked_items"] and data["closure_status"] == "QUALIFIED":
        raise ValidationError(
            "M0 cannot be QUALIFIED while blocked_items is non-empty"
        )


def validate_manifest(path: Path) -> None:
    data = load_json(path)

    if not isinstance(data, dict):
        raise ValidationError("Qualification Manifest root must be an object")

    missing = [
        field for field in MANIFEST_REQUIRED_FIELDS
        if field not in data
    ]
    if missing:
        raise ValidationError(
            "Qualification Manifest missing fields: " + ", ".join(missing)
        )

    if not data["qualification_id"]:
        raise ValidationError("qualification_id must be non-empty")

    if not data["source_commit"]:
        raise ValidationError("source_commit must be non-empty")

    binary_hash = data["binary_hash"]
    if not isinstance(binary_hash, str) or not re.fullmatch(
        r"[0-9a-f]{64}", binary_hash
    ):
        raise ValidationError("binary_hash must be lowercase SHA-256")

    if not isinstance(data["artifact_digests"], list):
        raise ValidationError("artifact_digests must be an array")

    for item in data["artifact_digests"]:
        if not isinstance(item, dict):
            raise ValidationError("artifact digest entries must be objects")

        for key in ("artifact", "algorithm", "digest"):
            if key not in item:
                raise ValidationError(
                    f"artifact digest missing {key}"
                )

        if item["algorithm"] != "SHA-256":
            raise ValidationError(
                "M0 foundation currently permits SHA-256 artifact identity only"
            )

        if not re.fullmatch(r"[0-9a-f]{64}", item["digest"]):
            raise ValidationError("invalid artifact SHA-256 digest")


def repo_absolute(path: Path) -> Path:
    """
    Return an absolute repository-grounded path.

    Relative qualification paths are interpreted relative to ROOT rather than
    relative to the caller's incidental working-directory representation.
    """
    if path.is_absolute():
        return path.resolve()

    return (ROOT / path).resolve()


def repo_relative(path: Path) -> str:
    """
    Return canonical repository-relative artifact identity.

    Both absolute and relative inputs are accepted, but the resolved path must
    remain within ROOT.
    """
    absolute = repo_absolute(path)

    try:
        relative = absolute.relative_to(ROOT)
    except ValueError as exc:
        raise ValidationError(
            f"artifact path escapes repository root: {path}"
        ) from exc

    return relative.as_posix()


def emit_m0_foundation(out_root: Path) -> Path:
    validate_vocabulary()
    validate_m0()

    if not PRODUCTION_BINARY.is_file():
        raise ValidationError(
            "build/asmweb does not exist; build production artifact first"
        )

    if not git_clean():
        raise ValidationError(
            "formal evidence generation requires a clean source tree"
        )

    commit = git_commit()
    binary_hash = sha256_file(PRODUCTION_BINARY)

    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    timestamp = now.isoformat().replace("+00:00", "Z")
    compact = now.strftime("%Y%m%dT%H%M%SZ")

    qualification_id = (
        f"M0-foundation-{commit[:12]}-{binary_hash[:12]}-{compact}"
    )

    output_root = repo_absolute(out_root)
    final_dir = output_root / qualification_id
    staging_dir = output_root / f".{qualification_id}.tmp"

    if final_dir.exists():
        raise ValidationError(
            f"qualification identity already exists: {qualification_id}"
        )

    if staging_dir.exists():
        raise ValidationError(
            f"staging qualification identity already exists: "
            f"{staging_dir.name}"
        )

    output_root.mkdir(parents=True, exist_ok=True)

    milestone = load_json(M0_PATH)

    binary_rel = repo_relative(PRODUCTION_BINARY)

    artifact_digests = [
        {
            "artifact": binary_rel,
            "algorithm": "SHA-256",
            "digest": binary_hash,
        }
    ]

    manifest = {
        "qualification_id": qualification_id,
        "AsmWeb_version": "M0-development",
        "requirements_baseline":
            "AsmWeb — Requirements & Scope Specification v0.3",
        "architecture_baseline":
            "AsmWeb — Architecture & Engineering Specification v0.4",
        "assembly_standard_version":
            "AsmWeb — Assembly Engineering Standard v0.3",
        "runtime_specification_version":
            "AsmWeb — Runtime & Memory Specification v0.3",
        "security_specification_version":
            "AsmWeb — Security & Threat Model Specification v0.3",
        "limits_register_version":
            "AsmWeb — Invariants & Limits Register v0.3",
        "protocol_specification_version":
            "AsmWeb — Protocol & Semantic Specification v0.3",
        "qualification_specification_version": QUALIFICATION_SPEC,
        "capability_profile_version": None,
        "standards_register_version": None,
        "source_commit": commit,
        "binary_hash": binary_hash,
        "configuration_identity": "M0-current-production-runtime",
        "effective_limit_manifest": None,
        "build_manifest": {
            "binary": binary_rel,
            "binary_kind": "production",
            "source_tree_clean": True,
            "assembler": tool_version(["nasm", "-v"]),
            "linker": tool_version(["ld", "--version"]),
        },
        "provenance_manifest_ref": None,
        "host_manifest": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "platform": platform.platform(),
        },
        "suite_versions": {
            "qualification_foundation": 1
        },
        "instrumentation_state": {
            "production_binary": True,
            "qualification_fault_controller_linked": False
        },
        "virtual_time_state": "NOT_ACTIVE",
        "deterministic_entropy_state": "NOT_ACTIVE",
        "implementation_variant_state": {
            "identity": "production-default",
            "qualification_status": "QUALIFICATION_PENDING"
        },
        "requirement_results": [],
        "assembly_rule_results": [],
        "runtime_rule_results": [],
        "security_rule_results": [],
        "invariant_results": [],
        "limit_results": [],
        "protocol_rule_results": [],
        "qualification_rule_results": [],
        "correctness_results": [],
        "conformance_results": [],
        "interop_results": [],
        "browser_results": [],
        "fuzz_results": [],
        "fault_injection_results": [],
        "resource_results": [],
        "RAF_results": [],
        "performance_results": [],
        "endurance_results": [],
        "reclamation_results": [],
        "milestone_results": [
            {
                "milestone_id": "M0",
                "closure_status": milestone["closure_status"],
                "blocked_items": milestone["blocked_items"]
            }
        ],
        "known_failures": milestone["known_failures"],
        "unsupported_features": [],
        "waivers": milestone["waivers"],
        "artifact_digests": artifact_digests,
        "timestamp": timestamp
    }

    try:
        staging_dir.mkdir()

        manifest_path = staging_dir / "qualification-manifest.json"
        evidence_path = staging_dir / "evidence-manifest.json"
        index_path = staging_dir / "artifact-index.json"

        dump_json(manifest_path, manifest)
        validate_manifest(manifest_path)

        evidence_manifest = {
            "schema_version": 1,
            "qualification_id": qualification_id,
            "source_commit": commit,
            "artifacts": artifact_digests,
            "notes": [
                "This foundation evidence does not establish M0 closure.",
                "The M0 milestone remains BLOCKED.",
                "Re-running evidence generation creates a new "
                "qualification identity."
            ]
        }

        dump_json(evidence_path, evidence_manifest)

        # Artifact names identify their final published locations rather than
        # the temporary staging paths.
        generated = [
            (
                manifest_path,
                final_dir / "qualification-manifest.json"
            ),
            (
                evidence_path,
                final_dir / "evidence-manifest.json"
            ),
        ]

        index = {
            "schema_version": 1,
            "qualification_id": qualification_id,
            "artifacts": [
                {
                    "artifact": repo_relative(published_path),
                    "algorithm": "SHA-256",
                    "digest": sha256_file(staged_path)
                }
                for staged_path, published_path in generated
            ]
        }

        dump_json(index_path, index)

        # Publication occurs only after every required artifact exists and
        # validates. rename() is atomic within this filesystem.
        staging_dir.rename(final_dir)

    except Exception:
        # A failed run SHALL NOT leave a visible half-published evidence run.
        if staging_dir.exists():
            import shutil
            shutil.rmtree(staging_dir)

        raise

    return final_dir


def cmd_validate_foundation(_: argparse.Namespace) -> int:
    validate_vocabulary()
    validate_m0()

    membership = validate_qrr_membership_authority()
    source_rules = validate_qrr_source_authority()

    schema = load_json(QRR_SCHEMA_PATH)

    if schema.get("entry_required_fields") != QRR_REQUIRED_FIELDS:
        raise ValidationError("QRR schema field set mismatch")

    print("qualification_foundation_validation_status=0")
    print(
        "qualification_result_count="
        f"{len(EXPECTED_RESULTS)}"
    )
    print(
        "implementation_state_count="
        f"{len(EXPECTED_IMPLEMENTATION_STATES)}"
    )
    print(
        "verification_class_count="
        f"{len(EXPECTED_VERIFICATION_CLASSES)}"
    )
    print(f"qrr_authoritative_rule_count={len(membership)}")
    print(
        "qrr_membership_digest="
        f"{canonical_membership_digest(sorted(membership))}"
    )
    print(
        "qrr_source_rule_count="
        f"{len(source_rules)}"
    )

    source_data = load_json(QRR_SOURCE_PATH)

    print(
        "qrr_source_rule_text_digest="
        f"{source_data['canonical_rule_text_sha256']}"
    )
    print("m0_closure_status=BLOCKED")
    return 0


def cmd_validate_qrr(args: argparse.Namespace) -> int:
    validate_vocabulary()
    validate_qrr_structure(Path(args.path))
    print("qrr_structural_validation_status=0")
    return 0


def cmd_validate_qrr_membership(
    args: argparse.Namespace
) -> int:
    validate_qrr_structure(Path(args.path))
    validate_qrr_exact_membership(Path(args.path))

    print("qrr_exact_membership_status=0")
    return 0


def cmd_validate_manifest(args: argparse.Namespace) -> int:
    validate_manifest(Path(args.path))
    print("qualification_manifest_validation_status=0")
    return 0


def cmd_emit(args: argparse.Namespace) -> int:
    out_dir = emit_m0_foundation(Path(args.output_root))
    print("qualification_foundation_emit_status=0")
    print(f"qualification_output={out_dir}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()

    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("validate-foundation")
    p.set_defaults(func=cmd_validate_foundation)

    p = sub.add_parser("validate-qrr")
    p.add_argument("path")
    p.set_defaults(func=cmd_validate_qrr)

    p = sub.add_parser("validate-qrr-membership")
    p.add_argument("path")
    p.set_defaults(func=cmd_validate_qrr_membership)

    p = sub.add_parser("validate-manifest")
    p.add_argument("path")
    p.set_defaults(func=cmd_validate_manifest)

    p = sub.add_parser("emit-m0-foundation")
    p.add_argument(
        "--output-root",
        default="build/qualification/evidence"
    )
    p.set_defaults(func=cmd_emit)

    return parser


def main() -> int:
    try:
        args = build_parser().parse_args()
        return args.func(args)
    except ValidationError as exc:
        print(f"qualification_validation_error={exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
