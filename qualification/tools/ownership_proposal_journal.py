#!/usr/bin/env python3
"""Append-only, non-effective ownership proposal journal.

This is NOT an approval journal or effective-publication mechanism.
Records are local filesystem evidence subject to external protection.
"""

import argparse
import fcntl
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

import ownership_decision_preflight as preflight
import ownership_snapshot as snapshot

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_JOURNAL = (
    ROOT / "qualification/requirements/ownership-proposals"
)

FORMAT = "ASMWEB_NON_EFFECTIVE_PROPOSAL_V1"


class JournalError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise JournalError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return snapshot.canonical(value)


def filename(decision_id):
    return digest(decision_id.encode("utf-8")) + ".json"


def envelope(candidate):
    return {
        "format": FORMAT,
        "candidate": candidate,
        "candidate_sha256": digest(canonical(candidate)),
    }


def validate_directory(directory):
    require(
        directory.is_dir() and not directory.is_symlink(),
        "invalid journal directory",
    )


def inspect_records(directory):
    """Validate the journal and return indexed immutable proposals."""
    decisions = {}
    requirements = {}

    for path in sorted(directory.iterdir()):
        if path.name == ".lock":
            continue

        require(
            path.name.endswith(".json"),
            "unexpected journal entry",
        )

        metadata = path.lstat()

        require(
            stat.S_ISREG(metadata.st_mode)
            and metadata.st_nlink == 1,
            "journal entry is not an independent regular file",
        )

        data = path.read_bytes()
        document = preflight.load(data)

        require(
            isinstance(document, dict)
            and set(document) == {
                "format", "candidate", "candidate_sha256"
            },
            "invalid journal envelope",
        )

        require(
            document["format"] == FORMAT,
            "unknown journal record format",
        )

        candidate = document["candidate"]

        require(
            isinstance(candidate, dict),
            "invalid recorded candidate",
        )

        require(
            candidate.get("decision_status") == "PROPOSED",
            "journal contains non-proposal decision",
        )

        require(
            candidate.get("authority_designation_ref") is None
            and candidate.get("approval_evidence_ref") is None,
            "journal contains authority claim",
        )

        require(
            candidate.get("decision_provenance") == {
                "verification_status": "UNVERIFIED"
            },
            "journal contains verified-provenance claim",
        )

        decision_id = candidate.get("decision_id")
        requirement_id = candidate.get("requirement_id")

        require(
            preflight.checked_text(decision_id)
            and preflight.checked_text(requirement_id),
            "invalid recorded identity",
        )

        require(
            path.name == filename(decision_id),
            "journal filename does not match decision ID",
        )

        require(
            document["candidate_sha256"]
            == digest(canonical(candidate)),
            "record digest mismatch",
        )

        require(
            data == canonical(document),
            "noncanonical or altered journal record",
        )

        require(
            decision_id not in decisions,
            "duplicate recorded decision ID",
        )

        require(
            requirement_id not in requirements,
            "multiple proposals for one requirement",
        )

        decisions[decision_id] = document
        requirements[requirement_id] = document

    return decisions, requirements


def append_proposal(candidate, directory=DEFAULT_JOURNAL):
    directory = Path(directory)

    require(
        not directory.is_symlink(),
        "journal directory must not be a symlink",
    )

    directory.mkdir(mode=0o700, exist_ok=True)
    validate_directory(directory)

    lock_path = directory / ".lock"

    flags = os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW
    lock_fd = os.open(lock_path, flags, 0o600)

    try:
        metadata = os.fstat(lock_fd)

        require(
            stat.S_ISREG(metadata.st_mode)
            and metadata.st_nlink == 1,
            "invalid journal lock",
        )

        fcntl.flock(lock_fd, fcntl.LOCK_EX)

        # Revalidate the current baseline while holding the lock.
        baseline = preflight.current_snapshot()
        preflight.validate(candidate, baseline)

        decisions, requirements = inspect_records(directory)

        decision_id = candidate["decision_id"]
        requirement_id = candidate["requirement_id"]

        require(
            decision_id not in decisions,
            "decision ID already recorded",
        )

        require(
            requirement_id not in requirements,
            "requirement already has a recorded proposal",
        )

        record = envelope(candidate)
        payload = canonical(record)

        output = directory / filename(decision_id)

        # O_EXCL prevents replacing even an identically named record.
        fd = os.open(
            output,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
        )

        try:
            with os.fdopen(fd, "wb", closefd=True) as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
        except BaseException:
            # A failed write must not be represented as an accepted
            # journal append. Leave any partial file visible for
            # explicit investigation rather than concealing it.
            raise

        directory_fd = os.open(
            directory,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)

        return {
            "result": "PROPOSAL_RECORDED_NON_EFFECTIVE",
            "decision_id": decision_id,
            "requirement_id": requirement_id,
            "record": str(output),
            "record_sha256": digest(payload),
            "snapshot_sha256": baseline,
            "recorded_proposals": len(decisions) + 1,
            "authority_verified": False,
            "effective_publication": False,
            "milestone_closed": False,
        }
    finally:
        os.close(lock_fd)


def verify_journal(directory=DEFAULT_JOURNAL):
    directory = Path(directory)
    validate_directory(directory)

    lock_fd = os.open(
        directory / ".lock",
        os.O_RDONLY | os.O_NOFOLLOW,
    )

    try:
        fcntl.flock(lock_fd, fcntl.LOCK_SH)
        decisions, requirements = inspect_records(directory)

        return {
            "result": "NON_EFFECTIVE_JOURNAL_VERIFIED",
            "decision_count": len(decisions),
            "requirement_count": len(requirements),
            "authority_verified": False,
            "effective_publication": False,
        }
    finally:
        os.close(lock_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=("submit", "verify"),
    )
    parser.add_argument("candidate", nargs="?")
    parser.add_argument(
        "--journal",
        type=Path,
        default=DEFAULT_JOURNAL,
    )

    args = parser.parse_args()

    try:
        if args.action == "submit":
            require(
                args.candidate is not None,
                "candidate file required",
            )
            candidate = preflight.load(
                Path(args.candidate).read_bytes()
            )
            result = append_proposal(candidate, args.journal)
        else:
            require(
                args.candidate is None,
                "verify does not accept a candidate",
            )
            result = verify_journal(args.journal)

    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        json.JSONDecodeError,
    ) as exc:
        print(f"OWNERSHIP_JOURNAL=REJECT: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
