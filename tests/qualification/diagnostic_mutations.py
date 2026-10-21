#!/usr/bin/env python3
"""M0-DIAG-001: isolated, fail-closed diagnostic mutation checks."""

from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "src/runtime/diagnostic.asm"
ORIGINAL = ROOT / "build/qualification/diagnostic"

MUTATIONS = [
    (
        "REPEATED_INITIALISATION",
        "    cmp qword [rdi + rcx * 8], 0\n    jne .fail\n",
        "    cmp qword [rdi + rcx * 8], 0\n    nop\n",
        4,
    ),
    (
        "CORRUPTED_DOMAIN",
        '    jmp .fail\n\n.check_invariant:',
        '    jmp .check_invariant\n\n.check_invariant:',
        10,
    ),
    (
        "ZERO_FAILURE_CODE",
        "    cmp rsi, ASMWEB_DIAG_MIN_INVARIANT_CODE\n    jb .fail\n",
        "    cmp rsi, ASMWEB_DIAG_MIN_INVARIANT_CODE\n    nop\n",
        5,
    ),
    (
        "OUT_OF_RANGE_FAILURE_CODE",
        "    cmp rsi, ASMWEB_DIAG_MAX_INVARIANT_CODE\n    ja .fail\n",
        "    cmp rsi, ASMWEB_DIAG_MAX_INVARIANT_CODE\n    nop\n",
        6,
    ),
]


def execute(arguments):
    return subprocess.run(
        [str(arg) for arg in arguments],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    source = SOURCE.read_text()

    for name, old, _, _ in MUTATIONS:
        require(
            source.count(old) == 1,
            f"{name}: non-unique or missing mutation anchor",
        )

    result = execute([ORIGINAL])
    require(result.returncode == 0, "Original diagnostic harness failed")
    print("UNMODIFIED_DIAGNOSTIC=PASS")

    rejected_count = 0

    with tempfile.TemporaryDirectory(
        prefix="asmweb-diagnostic-mutations-"
    ) as temporary:
        directory = Path(temporary)

        for number, (name, old, new, expected_exit) in enumerate(
            MUTATIONS, start=1
        ):
            asm = directory / f"mutation-{number}.asm"
            obj = directory / f"mutation-{number}.o"
            binary = directory / f"mutation-{number}"

            asm.write_text(source.replace(old, new, 1))

            assembled = execute([
                "nasm", "-f", "elf64", "-Wall", "-Werror",
                "-Wno-error=reloc-rel-dword",
                "-Iinclude/", "-o", obj, asm,
            ])
            require(
                assembled.returncode == 0,
                f"{name}: assembly failed: {assembled.stderr}",
            )

            linked = execute([
                "ld", "-z", "noexecstack",
                "-o", binary,
                ROOT / "build/linux/syscall.o",
                obj,
                ROOT / "build/tests/qualification/diagnostic.o",
            ])
            require(
                linked.returncode == 0,
                f"{name}: link failed: {linked.stderr}",
            )

            result = execute([binary])
            require(
                result.returncode == expected_exit,
                (
                    f"{name}: expected rejection exit {expected_exit}, "
                    f"got {result.returncode}; "
                    f"stderr={result.stderr}"
                ),
            )

            rejected_count += 1
            print(f"{name}=REJECTED case={expected_exit}")

    print(f"MUTATIONS_TESTED={len(MUTATIONS)}")
    print(f"MUTATIONS_REJECTED={rejected_count}")
    print("M0_DIAG_ADVERSARIAL=PASS")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"M0_DIAG_ADVERSARIAL=FAIL: {error}", file=sys.stderr)
        sys.exit(1)
