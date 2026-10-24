#!/usr/bin/env python3
"""Produce a deterministic, read-only ownership baseline identity.

This is a baseline inspection primitive, NOT an effective approval
snapshot, an authority designation, or a milestone closure decision.
"""

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

MEMBERS = (
    (
        "requirements_source",
        "qualification/requirements/requirements-source-v0.3.json",
    ),
    (
        "requirements_membership",
        "qualification/requirements/requirements-membership-v0.3.json",
    ),
    (
        "requirements_registry",
        "qualification/requirements/requirements-registry-v0.3.json",
    ),
    (
        "ownership_registry",
        "qualification/requirements/requirements-milestone-ownership-v0.3.json",
    ),
    (
        "ownership_contract",
        "qualification/requirements/ownership-decision-contract-v0.2.json",
    ),
    (
        "m0_milestone",
        "qualification/milestones/M0.json",
    ),
    (
        "m1_milestone",
        "qualification/milestones/M1.json",
    ),
)


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f"nonfinite JSON value: {value}")


def canonical(value):
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ) + "\n"
    ).encode("utf-8")


def read_member(role, relative):
    path = ROOT / relative

    if path.is_symlink() or not path.is_file():
        raise ValueError(f"invalid snapshot member: {relative}")

    data = path.read_bytes()

    document = json.loads(
        data.decode("utf-8"),
        object_pairs_hook=strict_object,
        parse_constant=reject_constant,
    )

    if not isinstance(document, dict):
        raise ValueError(f"member is not a JSON object: {relative}")

    schema = document.get("schema_version")

    if type(schema) is not int or schema < 1:
        raise ValueError(f"invalid schema version: {relative}")

    return {
        "role": role,
        "path": relative,
        "schema_version": schema,
        "sha256": hashlib.sha256(data).hexdigest(),
    }, document


def validate_contract_state(contract):
    """Validate observable contract state without granting authority.

    This snapshot remains read-only and non-effective. Recognition
    of enabled approval flags does not authenticate an individual
    ownership decision or publish an approval.
    """
    approval = contract.get("approval_enabled")
    publication = contract.get("effective_publication_enabled")
    authority = contract.get("authority_status")

    if type(approval) is not bool:
        raise ValueError("invalid approval enablement type")

    if type(publication) is not bool:
        raise ValueError("invalid publication enablement type")

    if publication and not approval:
        raise ValueError("publication enabled without approval")

    if approval and authority != "ESTABLISHED":
        raise ValueError("approval enabled without established authority")

    if publication and authority != "ESTABLISHED":
        raise ValueError("publication enabled without established authority")

    if approval and contract.get("status") != (
        "M0_LOCAL_AUTHORITY_ESTABLISHED"
    ):
        raise ValueError("inconsistent established authority status")


def main():
    members = []
    documents = {}

    for role, relative in MEMBERS:
        member, document = read_member(role, relative)
        members.append(member)
        documents[role] = document

    source = documents["requirements_source"]
    membership = documents["requirements_membership"]
    registry = documents["requirements_registry"]
    ownership = documents["ownership_registry"]

    source_ids = [
        entry["requirement_id"]
        for entry in source["entries"]
    ]
    membership_ids = membership["requirement_ids"]
    registry_ids = [
        entry["id"]
        for entry in registry["entries"]
    ]
    ownership_ids = [
        entry["requirement_id"]
        for entry in ownership["entries"]
    ]

    if not (
        len(source_ids) == 1001
        and len(set(source_ids)) == 1001
        and source_ids == membership_ids
        and source_ids == registry_ids
        and source_ids == ownership_ids
    ):
        raise ValueError("requirements membership mismatch")

    if documents["m0_milestone"].get("milestone_id") != "M0":
        raise ValueError("M0 milestone identity mismatch")

    if documents["m1_milestone"].get("milestone_id") != "M1":
        raise ValueError("M1 milestone identity mismatch")

    contract = documents["ownership_contract"]

    if contract.get("contract_version") != "0.2":
        raise ValueError("unexpected ownership contract version")

    validate_contract_state(contract)

    manifest = {
        "format": "ASMWEB_OWNERSHIP_BASELINE_SNAPSHOT_V1",
        "purpose": "READ_ONLY_NON_EFFECTIVE_BASELINE",
        "requirement_count": 1001,
        "members": members,
    }

    identity = hashlib.sha256(canonical(manifest)).hexdigest()

    result = {
        "manifest": manifest,
        "snapshot_sha256": identity,
        "effective_approval": False,
        "formal_milestone_closure": False,
    }

    sys.stdout.buffer.write(canonical(result))


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError, KeyError, TypeError) as exc:
        print(f"OWNERSHIP_SNAPSHOT=FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
