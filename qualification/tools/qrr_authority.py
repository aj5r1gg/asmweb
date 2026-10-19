#!/usr/bin/env python3

from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]

QRR_DIR = ROOT / "qualification/qrr"
SLICE_DIR = QRR_DIR / "slices"

SCHEMA_PATH = QRR_DIR / "qrr-schema.json"
MEMBERSHIP_PATH = QRR_DIR / "qrr-membership-v0.3.json"
SOURCE_PATH = QRR_DIR / "qrr-source-v0.3.json"

OUTPUT_PATH = QRR_DIR / "qrr-v0.3.json"

FOUNDATION_TOOL = (
    ROOT
    / "qualification/tools/"
    "qualification_foundation.py"
)

SLICE_TOOL = (
    ROOT
    / "qualification/tools/"
    "qrr_slice.py"
)


class QRRAuthorityError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    with path.open(
        "r",
        encoding="utf-8",
    ) as fh:
        return json.load(fh)


def dump_bytes(data: object) -> bytes:
    return (
        json.dumps(
            data,
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    ).encode("utf-8")


def repo_relative(path: Path) -> str:
    return str(
        path.resolve().relative_to(
            ROOT.resolve()
        )
    )


def display_path(path: Path) -> str:
    resolved = path.resolve()

    try:
        return str(
            resolved.relative_to(
                ROOT.resolve()
            )
        )
    except ValueError:
        return str(resolved)


def load_module(
    module_name: str,
    path: Path,
):
    spec = importlib.util.spec_from_file_location(
        module_name,
        path,
    )

    if spec is None or spec.loader is None:
        raise QRRAuthorityError(
            f"unable to load module: {path}"
        )

    module = importlib.util.module_from_spec(
        spec
    )

    spec.loader.exec_module(module)

    return module


FOUNDATION = load_module(
    "asmweb_qualification_foundation",
    FOUNDATION_TOOL,
)

SLICE_VALIDATOR = load_module(
    "asmweb_qrr_slice_validator",
    SLICE_TOOL,
)


def canonical_slice_paths() -> list[Path]:
    paths = sorted(
        SLICE_DIR.glob(
            "qrr-slice-*.json"
        )
    )

    if len(paths) != 6:
        raise QRRAuthorityError(
            "authoritative QRR construction "
            f"requires exactly 6 canonical slices; "
            f"found {len(paths)}"
        )

    return paths


def validate_slice_inputs(
    paths: list[Path],
) -> None:
    for path in paths:
        try:
            SLICE_VALIDATOR.validate(path)
        except Exception as exc:
            raise QRRAuthorityError(
                f"invalid slice input {path}: {exc}"
            ) from exc


def merge_method_maps(
    paths: list[Path],
) -> dict[str, list[str]]:
    merged: dict[str, list[str]] = {}

    for path in paths:
        data = load_json(path)

        method_map = data.get(
            "verification_method_class_map"
        )

        if not isinstance(method_map, dict):
            raise QRRAuthorityError(
                f"{path}: missing method map"
            )

        for method, classes in method_map.items():
            if method in merged:
                if merged[method] != classes:
                    raise QRRAuthorityError(
                        "verification-method mapping "
                        f"conflict for {method}: "
                        f"{merged[method]!r} "
                        f"vs {classes!r}"
                    )
            else:
                merged[method] = list(classes)

    return {
        method: merged[method]
        for method in sorted(merged)
    }


def collect_entries(
    paths: list[Path],
) -> dict[str, dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}

    for path in paths:
        data = load_json(path)

        entries = data.get("entries")

        if not isinstance(entries, list):
            raise QRRAuthorityError(
                f"{path}: entries must be an array"
            )

        for entry in entries:
            if not isinstance(entry, dict):
                raise QRRAuthorityError(
                    f"{path}: non-object QRR entry"
                )

            rule_id = entry.get("rule_id")

            if not isinstance(rule_id, str):
                raise QRRAuthorityError(
                    f"{path}: entry without rule_id"
                )

            if rule_id in by_id:
                raise QRRAuthorityError(
                    "duplicate QRR rule across slices: "
                    f"{rule_id}"
                )

            by_id[rule_id] = dict(entry)

    return by_id


def build_document() -> dict[str, Any]:
    schema = load_json(SCHEMA_PATH)
    membership = load_json(MEMBERSHIP_PATH)
    source = load_json(SOURCE_PATH)

    paths = canonical_slice_paths()

    validate_slice_inputs(paths)

    membership_ids = membership.get(
        "rule_ids"
    )

    source_entries = source.get(
        "entries"
    )

    if not isinstance(
        membership_ids,
        list,
    ):
        raise QRRAuthorityError(
            "membership rule_ids must be an array"
        )

    if not isinstance(
        source_entries,
        list,
    ):
        raise QRRAuthorityError(
            "source entries must be an array"
        )

    source_ids = [
        entry["rule_id"]
        for entry in source_entries
    ]

    if membership_ids != source_ids:
        raise QRRAuthorityError(
            "membership and source order differ"
        )

    if len(source_ids) != 234:
        raise QRRAuthorityError(
            f"expected 234 frozen rules; "
            f"got {len(source_ids)}"
        )

    source_text = {
        entry["rule_id"]:
            entry["normative_statement"]
        for entry in source_entries
    }

    by_id = collect_entries(paths)

    actual_ids = set(by_id)
    required_ids = set(source_ids)

    missing = sorted(
        required_ids - actual_ids
    )

    extra = sorted(
        actual_ids - required_ids
    )

    if missing or extra:
        pieces: list[str] = []

        if missing:
            pieces.append(
                "missing=" + ",".join(missing)
            )

        if extra:
            pieces.append(
                "extra=" + ",".join(extra)
            )

        raise QRRAuthorityError(
            "slice coverage mismatch: "
            + " ".join(pieces)
        )

    required_fields = schema.get(
        "entry_required_fields"
    )

    if not isinstance(
        required_fields,
        list,
    ):
        raise QRRAuthorityError(
            "schema entry_required_fields "
            "must be an array"
        )

    required_field_set = set(
        required_fields
    )

    ordered_entries: list[
        dict[str, Any]
    ] = []

    for rule_id in source_ids:
        entry = by_id[rule_id]

        actual_fields = set(entry)

        if actual_fields != required_field_set:
            missing_fields = sorted(
                required_field_set
                - actual_fields
            )

            extra_fields = sorted(
                actual_fields
                - required_field_set
            )

            raise QRRAuthorityError(
                f"{rule_id}: entry field shape "
                "does not exactly match QRR schema; "
                f"missing={missing_fields!r} "
                f"extra={extra_fields!r}"
            )

        if (
            entry["normative_statement"]
            != source_text[rule_id]
        ):
            raise QRRAuthorityError(
                f"{rule_id}: normative statement "
                "differs from frozen source"
            )

        ordered_entries.append(entry)

    method_map = merge_method_maps(paths)

    return {
        "schema_version":
            schema["schema_version"],
        "authority":
            schema["authority"],
        "registry_name":
            schema["registry_name"],
        "registry_abbreviation":
            schema["registry_abbreviation"],
        "source_membership_authority":
            repo_relative(
                MEMBERSHIP_PATH
            ),
        "source_text_authority":
            repo_relative(
                SOURCE_PATH
            ),
        "source_slices": [
            repo_relative(path)
            for path in paths
        ],
        "entry_count":
            len(ordered_entries),
        "verification_method_class_map":
            method_map,
        "entries":
            ordered_entries,
    }


def validate_top_level_identity(
    data: dict[str, Any],
) -> None:
    schema = load_json(SCHEMA_PATH)

    expected = {
        "schema_version":
            schema["schema_version"],
        "authority":
            schema["authority"],
        "registry_name":
            schema["registry_name"],
        "registry_abbreviation":
            schema["registry_abbreviation"],
        "source_membership_authority":
            repo_relative(
                MEMBERSHIP_PATH
            ),
        "source_text_authority":
            repo_relative(
                SOURCE_PATH
            ),
        "source_slices": [
            repo_relative(path)
            for path in canonical_slice_paths()
        ],
    }

    for field, value in expected.items():
        if data.get(field) != value:
            raise QRRAuthorityError(
                f"authoritative QRR {field} "
                "does not match construction "
                "authority"
            )


def validate_authoritative(
    path: Path,
) -> None:
    if not path.is_file():
        raise QRRAuthorityError(
            f"QRR does not exist: {path}"
        )

    data = load_json(path)

    if not isinstance(data, dict):
        raise QRRAuthorityError(
            "authoritative QRR root "
            "must be an object"
        )

    validate_top_level_identity(data)

    entries = data.get("entries")

    if not isinstance(entries, list):
        raise QRRAuthorityError(
            "authoritative QRR entries "
            "must be an array"
        )

    if data.get("entry_count") != len(entries):
        raise QRRAuthorityError(
            "authoritative QRR entry_count "
            "does not match entries"
        )

    if len(entries) != 234:
        raise QRRAuthorityError(
            "authoritative QRR must contain "
            f"234 entries; got {len(entries)}"
        )

    schema = load_json(SCHEMA_PATH)

    required_fields = set(
        schema["entry_required_fields"]
    )

    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise QRRAuthorityError(
                f"QRR entry {index} "
                "must be an object"
            )

        actual_fields = set(entry)

        if actual_fields != required_fields:
            raise QRRAuthorityError(
                f"QRR entry {index} has "
                "non-canonical field shape"
            )

    try:
        FOUNDATION.validate_vocabulary()

        FOUNDATION.validate_qrr_structure(
            path
        )

        FOUNDATION.validate_qrr_exact_membership(
            path
        )
    except Exception as exc:
        raise QRRAuthorityError(
            f"foundation QRR validation "
            f"failed: {exc}"
        ) from exc

    source = load_json(SOURCE_PATH)

    source_entries = source["entries"]

    source_ids = [
        entry["rule_id"]
        for entry in source_entries
    ]

    source_text = {
        entry["rule_id"]:
            entry["normative_statement"]
        for entry in source_entries
    }

    actual_ids = [
        entry["rule_id"]
        for entry in entries
    ]

    if actual_ids != source_ids:
        raise QRRAuthorityError(
            "authoritative QRR order does "
            "not exactly match frozen source"
        )

    for entry in entries:
        rule_id = entry["rule_id"]

        if (
            entry["normative_statement"]
            != source_text[rule_id]
        ):
            raise QRRAuthorityError(
                f"{rule_id}: normative statement "
                "differs from frozen source"
            )

    expected_document = build_document()

    expected_map = expected_document[
        "verification_method_class_map"
    ]

    actual_map = data.get(
        "verification_method_class_map"
    )

    if actual_map != expected_map:
        raise QRRAuthorityError(
            "authoritative verification-method "
            "map differs from canonical merged map"
        )

    canonical_classes = set(
        load_json(
            ROOT
            / "qualification/schema/"
            "qualification-vocabulary.json"
        )["verification_classes"]
    )

    for method, classes in actual_map.items():
        if (
            not isinstance(method, str)
            or not method
            or not isinstance(classes, list)
            or not classes
        ):
            raise QRRAuthorityError(
                "invalid authoritative method "
                f"mapping: {method!r}"
            )

        unknown = (
            set(classes)
            - canonical_classes
        )

        if unknown:
            raise QRRAuthorityError(
                f"{method}: unknown mapped "
                f"classes: {sorted(unknown)!r}"
            )

    for entry in entries:
        rule_id = entry["rule_id"]

        classes = set(
            entry[
                "verification_classes"
            ]
        )

        methods = entry[
            "verification_methods"
        ]

        mapped: set[str] = set()

        for method in methods:
            if method not in actual_map:
                raise QRRAuthorityError(
                    f"{rule_id}: unmapped "
                    f"verification method "
                    f"{method!r}"
                )

            mapped.update(
                actual_map[method]
            )

        if not classes.issubset(mapped):
            raise QRRAuthorityError(
                f"{rule_id}: declared "
                "verification classes are not "
                "supported by authoritative "
                "method mappings"
            )

    canonical = dump_bytes(
        expected_document
    )

    actual = path.read_bytes()

    if actual != canonical:
        raise QRRAuthorityError(
            "authoritative QRR is not the "
            "deterministic canonical rendering "
            "of current controlled inputs"
        )


def write_atomic(
    path: Path,
    payload: bytes,
) -> bool:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    if (
        path.exists()
        and path.read_bytes() == payload
    ):
        return False

    temporary = path.with_name(
        "." + path.name + ".tmp"
    )

    try:
        with temporary.open(
            "wb",
        ) as fh:
            fh.write(payload)
            fh.flush()
            os.fsync(fh.fileno())

        os.replace(
            temporary,
            path,
        )
    finally:
        if temporary.exists():
            temporary.unlink()

    return True


def cmd_build(
    args: argparse.Namespace,
) -> int:
    path = Path(args.path)

    document = build_document()

    changed = write_atomic(
        path,
        dump_bytes(document),
    )

    validate_authoritative(path)

    print(
        "qrr_authority_build_status=0"
    )
    print(
        f"qrr_authority_path="
        f"{display_path(path)}"
    )
    print(
        f"qrr_authority_entry_count="
        f"{document['entry_count']}"
    )
    print(
        "qrr_authority_method_count="
        f"{len(document['verification_method_class_map'])}"
    )
    print(
        f"qrr_authority_changed="
        f"{int(changed)}"
    )

    return 0


def cmd_validate(
    args: argparse.Namespace,
) -> int:
    path = Path(args.path)

    validate_authoritative(path)

    data = load_json(path)

    print(
        "qrr_authority_validation_status=0"
    )
    print(
        f"qrr_authority_entry_count="
        f"{data['entry_count']}"
    )
    print(
        "qrr_authority_method_count="
        f"{len(data['verification_method_class_map'])}"
    )

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()

    sub = parser.add_subparsers(
        dest="command",
        required=True,
    )

    p = sub.add_parser("build")

    p.add_argument(
        "path",
        nargs="?",
        default=str(OUTPUT_PATH),
    )

    p.set_defaults(func=cmd_build)

    p = sub.add_parser("validate")

    p.add_argument(
        "path",
        nargs="?",
        default=str(OUTPUT_PATH),
    )

    p.set_defaults(func=cmd_validate)

    return parser


def main() -> int:
    parser = build_parser()

    args = parser.parse_args()

    try:
        return args.func(args)
    except (
        QRRAuthorityError,
        OSError,
        json.JSONDecodeError,
    ) as exc:
        print(
            f"qrr_authority_error={exc}",
            file=sys.stderr,
        )

        return 1


if __name__ == "__main__":
    raise SystemExit(main())
