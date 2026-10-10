from __future__ import annotations

from pathlib import Path
import argparse
import importlib.util
import json
import sys


ROOT = Path(__file__).resolve().parents[2]

FOUNDATION_TOOL = (
    ROOT / "qualification/tools/qualification_foundation.py"
)

SOURCE_PATH = (
    ROOT / "qualification/qrr/qrr-source-v0.3.json"
)

SCHEMA_PATH = (
    ROOT / "qualification/qrr/qrr-schema.json"
)

VOCAB_PATH = (
    ROOT / "qualification/schema/qualification-vocabulary.json"
)

SLICE_01 = (
    ROOT
    / "qualification/qrr/slices/qrr-slice-01-governance.json"
)


class SliceValidationError(Exception):
    pass


def load(path: Path) -> object:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def load_foundation():
    spec = importlib.util.spec_from_file_location(
        "qualification_foundation_module",
        FOUNDATION_TOOL,
    )

    if spec is None or spec.loader is None:
        raise SliceValidationError(
            "unable to load qualification foundation tool"
        )

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    return module


FOUNDATION = load_foundation()
FOUNDATION_VALIDATION_ERROR = FOUNDATION.ValidationError


def validate(path: Path) -> None:
    source_rules = FOUNDATION.validate_qrr_source_authority()

    schema = load(SCHEMA_PATH)
    vocabulary = load(VOCAB_PATH)
    data = load(path)

    if not isinstance(data, dict):
        raise SliceValidationError(
            "slice root must be an object"
        )

    if data.get("authoring_status") != "DRAFT_PARTIAL":
        raise SliceValidationError(
            "slice must remain explicitly DRAFT_PARTIAL"
        )

    entries = data.get("entries")

    if not isinstance(entries, list):
        raise SliceValidationError(
            "slice entries must be an array"
        )

    if data.get("entry_count") != len(entries):
        raise SliceValidationError(
            "slice entry_count mismatch"
        )

    required_fields = schema["entry_required_fields"]

    canonical_classes = set(
        vocabulary["verification_classes"]
    )

    canonical_statuses = set(
        vocabulary["qrr_rule_statuses"]
    )

    method_map = data.get(
        "verification_method_class_map"
    )

    if not isinstance(method_map, dict):
        raise SliceValidationError(
            "verification_method_class_map must be an object"
        )

    for method, classes in method_map.items():
        if (
            not isinstance(method, str)
            or not method
            or not isinstance(classes, list)
            or not classes
        ):
            raise SliceValidationError(
                f"invalid verification method mapping: {method!r}"
            )

        unknown = set(classes) - canonical_classes

        if unknown:
            raise SliceValidationError(
                f"{method}: unknown mapped classes: "
                f"{sorted(unknown)!r}"
            )

    seen: set[str] = set()

    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise SliceValidationError(
                f"entry {index} must be an object"
            )

        missing = [
            field
            for field in required_fields
            if field not in entry
        ]

        if missing:
            raise SliceValidationError(
                f"entry {index} missing fields: "
                + ", ".join(missing)
            )

        rule_id = entry["rule_id"]

        if rule_id in seen:
            raise SliceValidationError(
                f"duplicate slice rule: {rule_id}"
            )

        seen.add(rule_id)

        if rule_id not in source_rules:
            raise SliceValidationError(
                f"unknown source rule: {rule_id}"
            )

        if (
            entry["normative_statement"]
            != source_rules[rule_id]
        ):
            raise SliceValidationError(
                f"{rule_id}: normative statement differs "
                "from frozen source authority"
            )

        if entry["status"] not in canonical_statuses:
            raise SliceValidationError(
                f"{rule_id}: invalid status"
            )

        classes = entry["verification_classes"]
        methods = entry["verification_methods"]

        if (
            not isinstance(classes, list)
            or not classes
        ):
            raise SliceValidationError(
                f"{rule_id}: no verification classes"
            )

        if (
            not isinstance(methods, list)
            or not methods
        ):
            raise SliceValidationError(
                f"{rule_id}: no credible verification method"
            )

        unknown_classes = set(classes) - canonical_classes

        if unknown_classes:
            raise SliceValidationError(
                f"{rule_id}: unknown verification classes "
                f"{sorted(unknown_classes)!r}"
            )

        mapped_classes: set[str] = set()

        for method in methods:
            if method not in method_map:
                raise SliceValidationError(
                    f"{rule_id}: unmapped verification method "
                    f"{method!r}"
                )

            mapped_classes.update(
                method_map[method]
            )

        if not set(classes).issubset(mapped_classes):
            raise SliceValidationError(
                f"{rule_id}: verification classes are not "
                "supported by declared method mappings"
            )

        for field in (
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
            if not isinstance(entry[field], list):
                raise SliceValidationError(
                    f"{rule_id}: {field} must be an array"
                )

        for field in (
            "rule_id",
            "title",
            "normative_statement",
            "first_required_milestone",
            "qualification_milestone",
            "notes",
        ):
            if not isinstance(entry[field], str):
                raise SliceValidationError(
                    f"{rule_id}: {field} must be a string"
                )

    namespaces = data.get("included_namespaces")

    if (
        not isinstance(namespaces, list)
        or not namespaces
        or not all(
            isinstance(namespace, str) and namespace
            for namespace in namespaces
        )
    ):
        raise SliceValidationError(
            "included_namespaces must be a non-empty string array"
        )

    if len(namespaces) != len(set(namespaces)):
        raise SliceValidationError(
            "included_namespaces contains duplicates"
        )

    expected = {
        rule_id
        for rule_id in source_rules
        if rule_id.split("-")[1] in set(namespaces)
    }

    if seen != expected:
        missing = sorted(expected - seen)
        extra = sorted(seen - expected)

        if missing:
            print(
                "slice_missing="
                + ",".join(missing)
            )

        if extra:
            print(
                "slice_extra="
                + ",".join(extra)
            )

        raise SliceValidationError(
            "slice membership does not match declared namespaces"
        )

    expected_count = data.get("entry_count")

    if len(seen) != expected_count:
        raise SliceValidationError(
            f"slice expected {expected_count} rules, got {len(seen)}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "path",
        nargs="?",
        default=str(SLICE_01),
    )

    args = parser.parse_args()

    try:
        validate(Path(args.path))
    except (
        SliceValidationError,
        FOUNDATION_VALIDATION_ERROR,
        OSError,
        json.JSONDecodeError,
    ) as exc:
        print(
            f"qrr_slice_validation_error={exc}",
            file=sys.stderr,
        )
        return 1

    data = load(Path(args.path))

    print("qrr_slice_validation_status=0")
    print(f"qrr_slice_id={data['slice_id']}")
    print(f"qrr_slice_rule_count={data['entry_count']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
