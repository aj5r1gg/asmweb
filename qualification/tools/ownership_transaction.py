#!/usr/bin/env python3
"""Verify complete signed proposal coverage; never publish approvals."""

import argparse
import fcntl
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

import ownership_authority as authority
import ownership_decision_preflight as preflight
import ownership_proposal_journal as journal
import ownership_signed_decision as signed
import ownership_snapshot as snapshot

FORMAT = "ASMWEB_SIGNED_TRANSACTION_PREFLIGHT_V1"
FIELDS = {
    "decision_id",
    "designation",
    "designation_signature",
    "binding",
    "binding_signature",
    "decision_signature",
}


class TransactionError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise TransactionError(message)


def read_file(path):
    info = path.lstat()
    require(
        stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
        "unsafe evidence file",
    )
    data = path.read_bytes()
    require(len(data) <= 1048576, "oversized evidence file")
    return data


def resolve(base, name):
    require(
        type(name) is str
        and name
        and not Path(name).is_absolute()
        and not any(
            part in ("", ".", "..")
            for part in name.split("/")
        )
        and "\\" not in name,
        "unsafe evidence reference",
    )

    path = base / name
    require(
        path.resolve().is_relative_to(base.resolve()),
        "evidence escapes trusted directory",
    )

    cursor = base
    require(
        base.is_dir() and not base.is_symlink(),
        "unsafe evidence root",
    )

    for component in Path(name).parts:
        cursor = cursor / component
        require(not cursor.is_symlink(), "symlink evidence")
    read_file(path)
    return path


def verify(
    manifest_path, journal_dir,
    evidence_dir, trusted_root, revocations,
):
    manifest = read_file(Path(manifest_path))
    document = preflight.load(manifest)

    require(
        manifest == snapshot.canonical(document),
        "noncanonical manifest",
    )
    require(
        type(document) is dict
        and set(document) == {
            "schema_version", "format",
            "baseline_snapshot_id", "decisions",
        },
        "invalid transaction fields",
    )
    require(
        type(document["schema_version"]) is int
        and document["schema_version"] == 1
        and document["format"] == FORMAT,
        "invalid transaction version",
    )

    baseline = preflight.current_snapshot()
    require(
        document["baseline_snapshot_id"] == baseline,
        "stale transaction baseline",
    )

    evidence_dir = Path(evidence_dir)

    # Authority and revocation bytes are part of the transaction
    # identity, even if their substantive verification succeeds.
    trusted_bytes = read_file(Path(trusted_root))
    revocation_bytes = read_file(Path(revocations))

    journal_dir = Path(journal_dir)
    journal.validate_directory(journal_dir)

    lock_path = journal_dir / ".lock"
    lock_fd = os.open(
        lock_path,
        os.O_RDONLY | os.O_NOFOLLOW,
    )

    try:
        info = os.fstat(lock_fd)
        require(
            stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
            "invalid journal lock",
        )
        fcntl.flock(lock_fd, fcntl.LOCK_SH)

        records, _ = journal.inspect_records(journal_dir)
        original_records = {
            identity: snapshot.canonical(record)
            for identity, record in records.items()
        }

        entries = document["decisions"]
        require(type(entries) is list, "decisions must be array")

        ids = []
        candidate_hashes = []
        evidence_hashes = []

        for entry in entries:
            require(
                type(entry) is dict and set(entry) == FIELDS,
                "invalid signed-decision entry",
            )

            identity = entry["decision_id"]
            require(
                authority.valid_identifier(identity),
                "invalid decision ID",
            )
            ids.append(identity)

            require(identity in records, "unknown decision")

            candidate = records[identity]["candidate"]
            preflight.validate(candidate, baseline)

            paths = {
                field: resolve(evidence_dir, entry[field])
                for field in FIELDS - {"decision_id"}
            }

            # Read every signing input before verification, not
            # merely its pathname. Reject a change during verification.
            evidence_before = {
                field: read_file(path)
                for field, path in paths.items()
            }

            outcome = signed.verify(
                journal_dir,
                identity,
                paths["designation"],
                paths["designation_signature"],
                paths["binding"],
                paths["binding_signature"],
                trusted_root,
                revocations,
                paths["decision_signature"],
            )

            require(
                outcome["decision_signature_verified"] is True
                and outcome["ownership_approved"] is False,
                "invalid decision verification outcome",
            )

            require(
                all(
                    read_file(paths[field]) == data
                    for field, data in evidence_before.items()
                ),
                "signing evidence changed during verification",
            )

            candidate_hashes.append({
                "decision_id": identity,
                "candidate_sha256": records[identity][
                    "candidate_sha256"
                ],
            })

            evidence_hashes.append({
                "decision_id": identity,
                "sha256": {
                    field: hashlib.sha256(data).hexdigest()
                    for field, data in sorted(
                        evidence_before.items()
                    )
                },
            })

        require(
            len(ids) == len(set(ids)),
            "duplicate decision in transaction",
        )
        require(
            set(ids) == set(records),
            "incomplete signed-decision coverage",
        )
        require(
            ids == sorted(ids),
            "noncanonical decision ordering",
        )

        # Shared-lock protection covers cooperative journal writers.
        # Independently compare recorded bytes to detect mutation by
        # a noncooperating writer during the transaction.
        final_records, _ = journal.inspect_records(journal_dir)
        require(
            {
                identity: snapshot.canonical(record)
                for identity, record in final_records.items()
            } == original_records,
            "journal changed during verification",
        )

        require(
            read_file(Path(trusted_root)) == trusted_bytes,
            "trusted root changed during verification",
        )
        require(
            read_file(Path(revocations)) == revocation_bytes,
            "revocation state changed during verification",
        )
        require(
            preflight.current_snapshot() == baseline,
            "baseline changed during verification",
        )

        receipt = {
            "schema_version": 1,
            "result": "VERIFIED_NON_EFFECTIVE_TRANSACTION",
            "baseline_snapshot_id": baseline,
            "manifest_sha256": hashlib.sha256(
                manifest
            ).hexdigest(),
            "decisions": candidate_hashes,
            "evidence": evidence_hashes,
            "trusted_root_sha256": hashlib.sha256(
                trusted_bytes
            ).hexdigest(),
            "revocations_sha256": hashlib.sha256(
                revocation_bytes
            ).hexdigest(),
            "journal_sha256": hashlib.sha256(
                snapshot.canonical({
                    identity: original_records[identity].decode(
                        "utf-8"
                    )
                    for identity in sorted(original_records)
                })
            ).hexdigest(),
            "decision_count": len(ids),
            "effective_approvals": 0,
            "publication_enabled": False,
            "milestones_closed": False,
        }

        receipt["receipt_sha256"] = hashlib.sha256(
            snapshot.canonical(receipt)
        ).hexdigest()

        return receipt

    finally:
        os.close(lock_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in (
        "manifest", "journal", "evidence",
        "trusted-root", "revocations",
    ):
        parser.add_argument("--" + name, required=True, type=Path)

    args = parser.parse_args()
    try:
        result = verify(
            args.manifest,
            args.journal,
            args.evidence,
            args.trusted_root,
            args.revocations,
        )
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(
            f"OWNERSHIP_TRANSACTION=REJECT: {exc}",
            file=sys.stderr,
        )
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
