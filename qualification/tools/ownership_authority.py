#!/usr/bin/env python3
"""Verify independently signed AsmWeb ownership authority designations.

NON-EFFECTIVE: Verification does not publish authority, approve any
ownership decision, alter a registry or close a milestone.

Trusted signers and revocations must come from independently controlled
inputs, not from the designation or proposed ownership decision.
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT / "qualification/requirements/"
    "requirements-source-v0.3.json"
)

NAMESPACE = "asmweb-ownership-authority-v1"
TRUST_PRINCIPAL = "asmweb-root"

FIELDS = {
    "schema_version",
    "designation_id",
    "principal",
    "granted_requirement_ids",
    "granted_milestones",
    "valid_from",
    "valid_until",
}

MILESTONES = {f"M{i}" for i in range(17)}
IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$")


class AuthorityError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise AuthorityError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def reject_constant(value):
    raise AuthorityError("nonfinite JSON value")


def load(payload):
    require(
        type(payload) is bytes and len(payload) <= 1048576,
        "invalid JSON payload size",
    )
    return json.loads(
        payload.decode("utf-8"),
        object_pairs_hook=unique_object,
        parse_constant=reject_constant,
    )


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


def independent_file(path):
    path = Path(path)
    require(
        path.is_file() and not path.is_symlink(),
        f"invalid file: {path}",
    )
    return path


def valid_identifier(value):
    return (
        type(value) is str
        and IDENTIFIER.fullmatch(value) is not None
    )


def unique_ids(values):
    require(
        type(values) is list
        and bool(values)
        and all(valid_identifier(x) for x in values)
        and len(set(values)) == len(values),
        "invalid or duplicate scope identifiers",
    )


def utc_timestamp(value):
    require(
        type(value) is str
        and re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",
            value,
        ) is not None,
        "invalid UTC timestamp format",
    )
    try:
        return datetime.strptime(
            value, "%Y-%m-%dT%H:%M:%SZ"
        ).replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise AuthorityError("invalid timestamp") from exc


def verify(
    designation_path,
    signature_path,
    trusted_signers_path,
    revocations_path,
    requirement_id,
    milestone,
    now=None,
):
    require(valid_identifier(requirement_id), "invalid requirement ID")
    require(milestone in MILESTONES, "invalid milestone")

    designation_path = independent_file(designation_path)
    signature_path = independent_file(signature_path)
    trusted_signers_path = independent_file(trusted_signers_path)
    revocations_path = independent_file(revocations_path)

    payload = designation_path.read_bytes()
    require(len(payload) <= 65536, "designation too large")

    document = load(payload)

    require(
        type(document) is dict and set(document) == FIELDS,
        "invalid designation fields",
    )
    require(
        type(document["schema_version"]) is int
        and document["schema_version"] == 1,
        "invalid designation schema",
    )
    require(
        payload == canonical(document),
        "designation must be canonical JSON",
    )

    for field in ("designation_id", "principal"):
        require(
            valid_identifier(document[field]),
            f"invalid {field}",
        )

    requirements = document["granted_requirement_ids"]
    milestones = document["granted_milestones"]

    unique_ids(requirements)
    unique_ids(milestones)

    require(
        set(milestones) <= MILESTONES,
        "unknown milestone in grant",
    )

    source = load(independent_file(SOURCE).read_bytes())
    require(
        type(source) is dict
        and type(source.get("entries")) is list,
        "invalid frozen requirements source",
    )
    known_ids = {
        item["requirement_id"]
        for item in source["entries"]
    }

    require(
        len(known_ids) == len(source["entries"]) == 1001,
        "requirements membership mismatch",
    )
    require(
        set(requirements) <= known_ids,
        "unknown requirement in authority scope",
    )
    require(
        requirement_id in known_ids,
        "unknown requested requirement",
    )

    start = utc_timestamp(document["valid_from"])
    end = utc_timestamp(document["valid_until"])
    current = now or datetime.now(timezone.utc)

    require(
        start < end and start <= current < end,
        "authority designation outside validity interval",
    )

    revocations = load(revocations_path.read_bytes())

    require(
        type(revocations) is dict
        and set(revocations) == {
            "schema_version", "revoked_designation_ids"
        },
        "invalid revocation register",
    )
    require(
        type(revocations["schema_version"]) is int
        and revocations["schema_version"] == 1,
        "invalid revocation schema",
    )

    revoked = revocations["revoked_designation_ids"]
    require(
        type(revoked) is list
        and all(valid_identifier(x) for x in revoked)
        and len(set(revoked)) == len(revoked),
        "invalid revocation identifiers",
    )
    require(
        document["designation_id"] not in revoked,
        "authority designation revoked",
    )

    # Fixed trust principal. The signed document does not select
    # which trusted signer is permitted to designate authority.
    try:
        completed = subprocess.run(
            [
                "ssh-keygen",
                "-Y", "verify",
                "-f", str(trusted_signers_path),
                "-I", TRUST_PRINCIPAL,
                "-n", NAMESPACE,
                "-s", str(signature_path),
            ],
            input=payload,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise AuthorityError("signature verifier unavailable") from exc

    require(
        completed.returncode == 0,
        "signature or trusted signer verification failed",
    )

    require(
        requirement_id in requirements
        and milestone in milestones,
        "authority scope does not include requested assignment",
    )

    return {
        "result": "SIGNED_DESIGNATION_VERIFIED_NON_EFFECTIVE",
        "designation_id": document["designation_id"],
        "principal": document["principal"],
        "requirement_id": requirement_id,
        "milestone": milestone,
        "signature_verified": True,
        "revocation_checked": True,
        "scope_verified": True,
        "effective_authority_published": False,
        "ownership_approved": False,
        "milestone_closed": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument("--designation", required=True, type=Path)
    parser.add_argument("--signature", required=True, type=Path)
    parser.add_argument("--trusted-signers", required=True, type=Path)
    parser.add_argument("--revocations", required=True, type=Path)
    parser.add_argument("--requirement", required=True)
    parser.add_argument("--milestone", required=True)

    args = parser.parse_args()

    try:
        result = verify(
            args.designation,
            args.signature,
            args.trusted_signers,
            args.revocations,
            args.requirement,
            args.milestone,
        )
    except (
        AuthorityError,
        OSError,
        ValueError,
        TypeError,
        KeyError,
        UnicodeError,
    ) as exc:
        print(
            f"OWNERSHIP_AUTHORITY=REJECT: {exc}",
            file=sys.stderr,
        )
        return 1

    print(json.dumps(result, indent=2))
    print("OWNERSHIP_AUTHORITY_VERIFICATION=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
