#!/usr/bin/env python3
"""Non-effective, content-addressed ownership baseline publication.

Immutable generation + atomic root-pointer replacement. This does NOT
publish approvals, grant authority or close a milestone.
"""

import argparse
import fcntl
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import ownership_decision_preflight as preflight
import ownership_snapshot as snapshot

FORMAT = "ASMWEB_NON_EFFECTIVE_GENERATION_V1"
ROOT_FORMAT = "ASMWEB_NON_EFFECTIVE_ROOT_V1"


class PublicationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise PublicationError(message)


def canonical(value):
    return snapshot.canonical(value)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def regular(path):
    path = Path(path)
    info = path.lstat()
    require(
        stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
        f"invalid regular file: {path}",
    )
    return path.read_bytes()


def directory(path):
    path = Path(path)
    require(
        path.is_dir() and not path.is_symlink(),
        f"invalid directory: {path}",
    )


def parse(data):
    document = preflight.load(data)
    require(
        isinstance(document, dict)
        and data == canonical(document),
        "noncanonical document",
    )
    return document


def current_baseline():
    result = subprocess.run(
        [
            sys.executable, "-B",
            str(
                preflight.ROOT
                / "qualification/tools/ownership_snapshot.py"
            ),
        ],
        cwd=preflight.ROOT,
        capture_output=True,
        check=True,
        timeout=30,
    )

    document = parse(result.stdout)

    require(
        document.get("effective_approval") is False
        and document.get("formal_milestone_closure") is False,
        "effective snapshot prohibited",
    )

    require(
        document.get("manifest", {}).get("purpose")
        == "READ_ONLY_NON_EFFECTIVE_BASELINE",
        "unsupported snapshot purpose",
    )

    identity = document.get("snapshot_sha256")
    require(
        type(identity) is str
        and len(identity) == 64
        and all(c in "0123456789abcdef" for c in identity),
        "invalid snapshot identity",
    )

    return document


def lock(base, exclusive):
    directory(base)
    path = base / ".lock"
    flags = os.O_RDWR | os.O_NOFOLLOW
    if exclusive:
        flags |= os.O_CREAT

    fd = os.open(path, flags, 0o600)
    info = os.fstat(fd)

    require(
        stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
        "unsafe publication lock",
    )

    fcntl.flock(
        fd, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
    )
    return fd


def fsync_directory(path):
    fd = os.open(
        path,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def read_generation(base, root):
    require(
        type(root) is dict
        and set(root) == {
            "schema_version", "format",
            "generation_sha256", "snapshot_sha256",
        },
        "invalid publication root",
    )

    require(
        type(root["schema_version"]) is int
        and root["schema_version"] == 1
        and root["format"] == ROOT_FORMAT,
        "unsupported root format",
    )

    identity = root["generation_sha256"]
    require(
        type(identity) is str
        and len(identity) == 64
        and all(c in "0123456789abcdef" for c in identity),
        "invalid generation identity",
    )

    data = regular(base / "generations" / (identity + ".json"))

    require(sha(data) == identity, "generation digest mismatch")

    generation = parse(data)

    require(
        set(generation) == {
            "schema_version", "format",
            "snapshot_sha256", "snapshot",
        },
        "invalid generation structure",
    )

    require(
        type(generation["schema_version"]) is int
        and generation["schema_version"] == 1
        and generation["format"] == FORMAT,
        "unsupported generation format",
    )

    embedded = generation["snapshot"]
    require(
        type(embedded) is dict
        and generation["snapshot_sha256"]
        == root["snapshot_sha256"]
        == embedded.get("snapshot_sha256"),
        "snapshot identity mismatch",
    )

    require(
        embedded.get("effective_approval") is False
        and embedded.get("formal_milestone_closure") is False,
        "effective generation prohibited",
    )

    return generation


def verify_locked(base, require_current=True):
    directory(base)
    directory(base / "generations")

    root = parse(regular(base / "effective-root.json"))
    generation = read_generation(base, root)

    if require_current:
        require(
            generation["snapshot"] == current_baseline(),
            "published baseline is stale",
        )

    return {
        "result": "NON_EFFECTIVE_GENERATION_VERIFIED",
        "generation_sha256": root["generation_sha256"],
        "snapshot_sha256": root["snapshot_sha256"],
        "effective_approval": False,
        "milestone_closed": False,
    }


def verify(base, require_current=True):
    base = Path(base)
    fd = lock(base, False)

    try:
        return verify_locked(base, require_current)
    finally:
        os.close(fd)


def publish(base):
    base = Path(base)

    require(
        not base.is_symlink(),
        "unsafe publication directory",
    )

    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory(base)

    generations = base / "generations"
    generations.mkdir(mode=0o700, exist_ok=True)
    directory(generations)

    fd = lock(base, True)

    try:
        root_path = base / "effective-root.json"

        if root_path.exists() or root_path.is_symlink():
            # Never replace a root that cannot be fully verified.
            verify_locked(base, False)

        baseline = current_baseline()

        generation = {
            "schema_version": 1,
            "format": FORMAT,
            "snapshot_sha256": baseline["snapshot_sha256"],
            "snapshot": baseline,
        }

        data = canonical(generation)
        identity = sha(data)

        generation_path = generations / (identity + ".json")

        if generation_path.exists() or generation_path.is_symlink():
            require(
                regular(generation_path) == data,
                "existing generation differs",
            )
        else:
            new_fd = os.open(
                generation_path,
                os.O_WRONLY | os.O_CREAT
                | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
            )
            with os.fdopen(new_fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())

            fsync_directory(generations)

        new_root = {
            "schema_version": 1,
            "format": ROOT_FORMAT,
            "generation_sha256": identity,
            "snapshot_sha256": baseline["snapshot_sha256"],
        }

        root_data = canonical(new_root)

        if root_path.exists():
            if regular(root_path) == root_data:
                result = verify_locked(base)
                result["publication"] = "ALREADY_CURRENT"
                return result

        # Prepare a complete root in the same filesystem, then
        # atomically replace the single visible publication pointer.
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="wb",
                dir=base,
                prefix=".root-",
                delete=False,
            ) as stream:
                temporary = Path(stream.name)
                stream.write(root_data)
                stream.flush()
                os.fsync(stream.fileno())

            os.replace(temporary, root_path)
            fsync_directory(base)

        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)

        result = verify_locked(base)
        result["publication"] = "ATOMIC_ROOT_REPLACEMENT"
        return result

    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("publish", "verify"))
    parser.add_argument("--store", type=Path, required=True)
    args = parser.parse_args()

    try:
        if args.action == "publish":
            result = publish(args.store)
        else:
            result = verify(args.store)

    except (
        OSError, ValueError, KeyError, TypeError,
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
    ) as exc:
        print(
            f"OWNERSHIP_GENERATION=REJECT: {exc}",
            file=sys.stderr,
        )
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
