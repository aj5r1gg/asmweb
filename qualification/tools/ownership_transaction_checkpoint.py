#!/usr/bin/env python3
"""Atomic non-effective checkpoints of independently verified transactions.

A checkpoint is not an ownership approval or effective publication.
Readers MUST reverify its underlying evidence before accepting it.
"""

import argparse
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

import ownership_generation as storage
import ownership_snapshot as snapshot
import ownership_transaction as transaction

FORMAT = "ASMWEB_NON_EFFECTIVE_TRANSACTION_CHECKPOINT_V1"
ROOT_FORMAT = "ASMWEB_NON_EFFECTIVE_CHECKPOINT_ROOT_V1"


class CheckpointError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CheckpointError(message)


def canonical(value):
    return snapshot.canonical(value)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def evidence_receipt(inputs):
    receipt = transaction.verify(*inputs)
    require(
        receipt.get("effective_approvals") == 0
        and receipt.get("publication_enabled") is False
        and receipt.get("milestones_closed") is False
        and receipt.get("result")
        == "VERIFIED_NON_EFFECTIVE_TRANSACTION",
        "effective or invalid transaction prohibited",
    )
    return receipt


def validate_root(base):
    storage.directory(base)
    storage.directory(base / "generations")

    root = storage.parse(
        storage.regular(base / "checkpoint-root.json")
    )

    require(
        type(root) is dict
        and set(root) == {
            "schema_version", "format", "generation_sha256"
        }
        and type(root["schema_version"]) is int
        and root["schema_version"] == 1
        and root["format"] == ROOT_FORMAT,
        "invalid checkpoint root",
    )

    identity = root["generation_sha256"]
    require(
        type(identity) is str
        and len(identity) == 64
        and all(c in "0123456789abcdef" for c in identity),
        "invalid checkpoint identity",
    )

    raw = storage.regular(
        base / "generations" / (identity + ".json")
    )

    require(digest(raw) == identity, "checkpoint digest mismatch")

    record = storage.parse(raw)
    require(
        type(record) is dict
        and set(record) == {
            "schema_version", "format",
            "receipt_sha256", "receipt",
        }
        and type(record["schema_version"]) is int
        and record["schema_version"] == 1
        and record["format"] == FORMAT,
        "invalid checkpoint generation",
    )

    receipt = record["receipt"]
    require(type(receipt) is dict, "invalid receipt")

    claimed_digest = receipt.get("receipt_sha256")
    require(
        type(claimed_digest) is str
        and len(claimed_digest) == 64
        and all(c in "0123456789abcdef"
                for c in claimed_digest),
        "invalid receipt identity",
    )

    unsigned = dict(receipt)
    del unsigned["receipt_sha256"]

    require(
        claimed_digest == digest(canonical(unsigned))
        and record["receipt_sha256"] == claimed_digest,
        "receipt digest mismatch",
    )

    return identity, receipt


def verify_locked(base, inputs):
    identity, stored = validate_root(base)
    current = evidence_receipt(inputs)

    require(
        stored == current,
        "checkpoint evidence is missing, stale or altered",
    )

    return {
        "result": "VERIFIED_NON_EFFECTIVE_CHECKPOINT",
        "generation_sha256": identity,
        "receipt_sha256": stored["receipt_sha256"],
        "decision_count": stored["decision_count"],
        "effective_approvals": 0,
        "publication_enabled": False,
        "milestones_closed": False,
    }


def verify(base, *inputs):
    base = Path(base)
    lock_fd = storage.lock(base, False)
    try:
        return verify_locked(base, inputs)
    finally:
        os.close(lock_fd)


def publish(base, *inputs):
    base = Path(base)

    require(
        not base.is_symlink(),
        "symlink checkpoint directory",
    )

    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    storage.directory(base)

    generations = base / "generations"
    generations.mkdir(mode=0o700, exist_ok=True)
    storage.directory(generations)

    lock_fd = storage.lock(base, True)

    try:
        root_path = base / "checkpoint-root.json"

        previous_exists = (
            root_path.exists() or root_path.is_symlink()
        )

        if previous_exists:
            # No silent repair or replacement of a stale root.
            verify_locked(base, inputs)

        receipt = evidence_receipt(inputs)
        record = {
            "schema_version": 1,
            "format": FORMAT,
            "receipt_sha256": receipt["receipt_sha256"],
            "receipt": receipt,
        }

        record_bytes = canonical(record)
        identity = digest(record_bytes)
        target = generations / (identity + ".json")

        if target.exists() or target.is_symlink():
            require(
                storage.regular(target) == record_bytes,
                "existing checkpoint altered",
            )
        else:
            fd = os.open(
                target,
                os.O_WRONLY | os.O_CREAT
                | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
            )
            with os.fdopen(fd, "wb") as stream:
                stream.write(record_bytes)
                stream.flush()
                os.fsync(stream.fileno())

            storage.fsync_directory(generations)

        root_bytes = canonical({
            "schema_version": 1,
            "format": ROOT_FORMAT,
            "generation_sha256": identity,
        })

        # Reverify before changing the visible root.
        require(
            evidence_receipt(inputs) == receipt,
            "transaction changed during checkpoint preparation",
        )

        if previous_exists:
            if storage.regular(root_path) == root_bytes:
                result = verify_locked(base, inputs)
                result["publication"] = "ALREADY_CURRENT"
                return result

        temporary = None

        try:
            with tempfile.NamedTemporaryFile(
                mode="wb",
                prefix=".checkpoint-",
                dir=base,
                delete=False,
            ) as stream:
                temporary = Path(stream.name)
                stream.write(root_bytes)
                stream.flush()
                os.fsync(stream.fileno())

            os.replace(temporary, root_path)
            storage.fsync_directory(base)

        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)

        result = verify_locked(base, inputs)
        result["publication"] = "ATOMIC_ROOT_REPLACEMENT"
        return result

    finally:
        os.close(lock_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action", choices=("publish", "verify")
    )

    for name in (
        "store", "manifest", "journal", "evidence",
        "trusted-root", "revocations",
    ):
        parser.add_argument(
            "--" + name, required=True, type=Path
        )

    args = parser.parse_args()

    inputs = (
        args.manifest, args.journal, args.evidence,
        args.trusted_root, args.revocations,
    )

    try:
        if args.action == "publish":
            result = publish(args.store, *inputs)
        else:
            result = verify(args.store, *inputs)

    except (
        OSError, ValueError, KeyError, TypeError,
    ) as exc:
        print(
            f"TRANSACTION_CHECKPOINT=REJECT: {exc}",
            file=sys.stderr,
        )
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
