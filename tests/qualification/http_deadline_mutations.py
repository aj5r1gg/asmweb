#!/usr/bin/env python3
"""Negative-control qualification for the HTTP acquisition deadline.

Builds a temporary mutated copy of production assembly.
Does not modify production source or production objects.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SOURCE = ROOT / "src/http/first_response.asm"
TEST = ROOT / "tests/integration/http_acquisition_deadline.py"

ORIGINAL = ROOT / "build/asmweb"

MUTATION_POINT = (
    "    add r14, r15\n\n"
    "    ; Search bounded received bytes for CRLF CRLF."
)

MUTATED_POINT = (
    "    add r14, r15\n\n"
    "    ; MUTATION: improperly restart the acquisition deadline\n"
    "    ; whenever a fragment is received.\n"
    "    lea rdi, [rsp]\n"
    "    call asm_monotonic_now\n"
    "    test rax, rax\n"
    "    jnz .drop_client\n\n"
    "    ; Search bounded received bytes for CRLF CRLF."
)


def run(args, *, timeout=30, env=None):
    return subprocess.run(
        [str(arg) for arg in args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
        env=env,
    )


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def integration(binary):
    env = os.environ.copy()
    env["ASMWEB_TEST_SERVER"] = str(binary)

    return run(
        [sys.executable, TEST],
        timeout=25,
        env=env,
    )


def main():
    require(SOURCE.is_file(), "Missing production HTTP source")
    require(TEST.is_file(), "Missing deadline integration test")
    require(ORIGINAL.is_file(), "Missing production executable")

    original_result = integration(ORIGINAL)

    require(
        original_result.returncode == 0,
        "Production baseline failed:\n"
        + original_result.stdout
        + original_result.stderr,
    )

    require(
        "HTTP_ACQUISITION_DEADLINE=PASS"
        in original_result.stdout,
        "Production baseline success marker missing",
    )

    print("UNMODIFIED_DEADLINE=PASS", flush=True)

    source = SOURCE.read_text(encoding="utf-8")

    require(
        source.count(MUTATION_POINT) == 1,
        "Production receive topology unexpected",
    )

    mutated = source.replace(
        MUTATION_POINT,
        MUTATED_POINT,
        1,
    )

    with tempfile.TemporaryDirectory(
        prefix="asmweb-deadline-mutation-"
    ) as temporary:

        directory = Path(temporary)

        asm = directory / "deadline_reset.asm"
        obj = directory / "deadline_reset.o"
        binary = directory / "asmweb-deadline-reset"

        asm.write_text(mutated, encoding="utf-8")

        assembly = run([
            "nasm",
            "-f", "elf64",
            "-Wall",
            "-Werror",
            "-Wno-error=reloc-rel-dword",
            "-Iinclude/",
            "-o", obj,
            asm,
        ])

        require(
            assembly.returncode == 0,
            "Mutation assembly failed:\n"
            + assembly.stderr,
        )

        # Reuse actual production objects, replacing only the
        # HTTP handler with the temporary mutated object.
        production_objects = sorted(
            ROOT / "build" / source_file.relative_to(
                ROOT / "src"
            ).with_suffix(".o")
            for source_file in (
                ROOT / "src"
            ).rglob("*.asm")
        )

        require(
            all(p.is_file() for p in production_objects),
            "Missing production object",
        )

        other_objects = [
            p for p in production_objects
            if p != ROOT / "build/http/first_response.o"
        ]

        linkage = run([
            "ld",
            "-z", "noexecstack",
            "-o", binary,
            obj,
            *other_objects,
        ])

        require(
            linkage.returncode == 0,
            "Mutation link failed:\n"
            + linkage.stderr,
        )

        print("MUTATED_EXECUTABLE_BUILD=PASS", flush=True)

        result = integration(binary)

        require(
            result.returncode != 0,
            "Deadline-reset mutation unexpectedly passed:\n"
            + result.stdout
            + result.stderr,
        )

        combined = result.stdout + result.stderr

        require(
            "Slow-client deadline exceeded" in combined,
            "Mutation rejected for an unrelated reason:\n"
            + combined,
        )

        print(
            "RESET_ON_FRAGMENT_MUTATION=REJECTED",
            flush=True,
        )

        print(
            "MUTATION_REJECTION_REASON=DEADLINE_EXCEEDED",
            flush=True,
        )

    print("PRODUCTION_SOURCE=UNCHANGED", flush=True)
    print("DEADLINE_MUTATION_SENSITIVITY=PASS", flush=True)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        AssertionError,
        OSError,
        subprocess.TimeoutExpired,
    ) as exc:
        print(
            f"DEADLINE_MUTATION_SENSITIVITY=FAIL {exc}",
            flush=True,
        )
        raise SystemExit(1)
