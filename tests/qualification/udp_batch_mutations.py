#!/usr/bin/env python3
"""M1 UDP batch boundary mutation qualification.

Mutations are assembled and linked in a temporary directory.
The source tree and production objects are never modified.
"""

from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]

NETWORK_SOURCE = ROOT / "src/linux/network.asm"
BOUNDS_SOURCE = ROOT / "tests/qualification/udp_batch_bounds.asm"

NETWORK_OBJECT = ROOT / "build/linux/network.o"
BOUNDS_OBJECT = ROOT / "build/tests/qualification/udp_batch_bounds.o"

FUNCTIONS = (
    "asm_linux_recvmmsg_bounded",
    "asm_linux_sendmmsg_bounded",
)

# Mutation name, exact production replacement, expected test exit.
MUTATIONS = (
    (
        "null_check_removed",
        "test rsi, rsi\n    jz .invalid",
        "test rsi, rsi\n    nop\n    nop",
        15,
    ),
    (
        "zero_check_removed",
        "test rdx, rdx\n    jz .invalid",
        "test rdx, rdx\n    nop\n    nop",
        11,
    ),
    (
        "upper_bound_weakened",
        "cmp rdx, ASMWEB_UDP_BATCH_MAX\n    ja .invalid",
        "cmp rdx, ASMWEB_UDP_BATCH_MAX + 1\n    ja .invalid",
        12,
    ),
    (
        "upper_bound_tightened",
        "cmp rdx, ASMWEB_UDP_BATCH_MAX\n    ja .invalid",
        "cmp rdx, ASMWEB_UDP_BATCH_MAX - 1\n    ja .invalid",
        18,
    ),
    (
        "unsigned_comparison_broken",
        "cmp rdx, ASMWEB_UDP_BATCH_MAX\n    ja .invalid",
        "cmp rdx, ASMWEB_UDP_BATCH_MAX\n    jg .invalid",
        13,
    ),
)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run_checked(argv):
    result = subprocess.run(
        argv,
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"COMMAND_FAILED={argv}\n"
            f"EXIT={result.returncode}\n"
            f"{result.stdout}\n{result.stderr}"
        )


def assemble(source, obj):
    run_checked([
        "nasm",
        "-f", "elf64",
        "-Wall",
        "-Werror",
        "-Wno-error=reloc-rel-dword",
        "-Iinclude/",
        "-o", str(obj),
        str(source),
    ])


def link(executable, test_obj, network_obj):
    run_checked([
        "ld",
        "-z", "noexecstack",
        "-o", str(executable),
        str(test_obj),
        str(network_obj),
    ])


def execute(executable):
    result = subprocess.run(
        ["timeout", "5s", str(executable)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    return result.returncode


def mutate_function(source, function, before, after):
    beginning = function + ":\n"
    require(
        source.count(beginning) == 1,
        f"FUNCTION_ANCHOR_INVALID={function}",
    )

    start = source.index(beginning)
    end = source.index("\n.invalid:\n", start)

    segment = source[start:end]

    require(
        segment.count(before) == 1,
        f"MUTATION_ANCHOR_INVALID={function}",
    )

    return (
        source[:start]
        + segment.replace(before, after, 1)
        + source[end:]
    )


def main():
    require(NETWORK_OBJECT.is_file(), "NETWORK_OBJECT_MISSING")
    require(BOUNDS_OBJECT.is_file(), "BOUNDS_OBJECT_MISSING")

    network_text = NETWORK_SOURCE.read_text(encoding="utf-8")
    bounds_text = BOUNDS_SOURCE.read_text(encoding="utf-8")

    with TemporaryDirectory(prefix="asmweb-udp-b8-") as temp:
        work = Path(temp)

        baseline = work / "baseline"
        link(baseline, BOUNDS_OBJECT, NETWORK_OBJECT)

        require(
            execute(baseline) == 0,
            "UNMODIFIED_PRODUCTION_FAILED",
        )
        print("UNMODIFIED_PRODUCTION=PASS", flush=True)

        # Confirm the guard check itself reports failure.
        guard_old = "guard_before dq 0x1122334455667788"
        guard_new = "guard_before dq 0x1122334455667789"

        require(
            bounds_text.count(guard_old) == 1,
            "GUARD_MUTATION_ANCHOR_INVALID",
        )

        guard_asm = work / "guard.asm"
        guard_obj = work / "guard.o"
        guard_exe = work / "guard"

        guard_asm.write_text(
            bounds_text.replace(guard_old, guard_new, 1),
            encoding="utf-8",
        )

        assemble(guard_asm, guard_obj)
        link(guard_exe, guard_obj, NETWORK_OBJECT)

        result = execute(guard_exe)
        require(
            result == 30,
            f"GUARD_MUTATION_NOT_DETECTED=EXIT_{result}",
        )
        print("GUARD_MUTATION=REJECTED_EXIT_30", flush=True)

        detected = 0

        for function in FUNCTIONS:
            for name, before, after, expected_exit in MUTATIONS:
                mutated = mutate_function(
                    network_text, function, before, after
                )

                case = work / f"{function}_{name}"
                case.mkdir()

                asm = case / "network.asm"
                obj = case / "network.o"
                exe = case / "qualification"

                asm.write_text(mutated, encoding="utf-8")

                assemble(asm, obj)
                link(exe, BOUNDS_OBJECT, obj)

                actual = execute(exe)

                require(
                    actual == expected_exit,
                    f"MUTATION_RESULT_MISMATCH="
                    f"{function}:{name}:"
                    f"expected={expected_exit}:actual={actual}",
                )

                print(
                    f"{function}:{name}="
                    f"REJECTED_EXIT_{actual}",
                    flush=True,
                )
                detected += 1

        require(
            detected == 10,
            f"UNEXPECTED_MUTATION_COUNT={detected}",
        )

        print(
            f"PRODUCTION_MUTATIONS_REJECTED={detected}/10",
            flush=True,
        )
        print("UDP_BATCH_MUTATION_QUALIFICATION=PASS", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        print(f"UDP_BATCH_MUTATION_QUALIFICATION=FAIL: {exc}",
              file=sys.stderr)
        sys.exit(1)
