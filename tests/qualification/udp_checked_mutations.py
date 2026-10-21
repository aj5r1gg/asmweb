#!/usr/bin/env python3
"""NET-005 checked UDP descriptor adversarial mutation qualification.

Compile mutations in temporary directories. Never alter production source
or the production object. An expected nonzero exit is required for each
specific mutant; crashes and timeouts do not qualify as successful detection.
"""

from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
NETWORK = ROOT / "src/linux/network.asm"
HARNESS = ROOT / "tests/qualification/udp_checked_descriptors.asm"
ORIGINAL_OBJECT = ROOT / "build/linux/network.o"

FUNCTIONS = (
    "asm_linux_recvmmsg_checked",
    "asm_linux_sendmmsg_checked",
)

# name, original fragment, replacement fragment, expected harness exit
MUTATIONS = (
    (
        "name_pointer_guard_removed",
        "cmp qword [r11], 0\n    jne .invalid",
        "cmp qword [r11], 0\n    nop\n    nop",
        15,
    ),
    (
        "name_length_guard_removed",
        "cmp dword [r11 + 8], 0\n    jne .invalid",
        "cmp dword [r11 + 8], 0\n    nop\n    nop",
        21,
    ),
    (
        "iov_count_guard_removed",
        "cmp qword [r11 + ASMWEB_LINUX_MSG_IOVLEN_OFFSET],         "
        "ASMWEB_UDP_CHECKED_IOV_MAX\n    jne .invalid",
        "cmp qword [r11 + ASMWEB_LINUX_MSG_IOVLEN_OFFSET],         "
        "ASMWEB_UDP_CHECKED_IOV_MAX\n    nop\n    nop",
        13,
    ),
    (
        "iov_pointer_guard_inverted",
        "test rax, rax\n    jz .invalid",
        "test rax, rax\n    jnz .invalid",
        11,
    ),
    (
        "control_length_guard_removed",
        "cmp qword [r11 + ASMWEB_LINUX_MSG_CONTROLLEN_OFFSET], 0\n"
        "    jne .invalid",
        "cmp qword [r11 + ASMWEB_LINUX_MSG_CONTROLLEN_OFFSET], 0\n"
        "    nop\n    nop",
        16,
    ),
    (
        "payload_base_guard_removed",
        "cmp qword [rax], 0\n    je .invalid",
        "cmp qword [rax], 0\n    nop\n    nop",
        14,
    ),
    (
        "payload_maximum_weakened",
        "cmp qword [rax + 8], ASMWEB_UDP_CHECKED_PAYLOAD_MAX",
        "cmp qword [rax + 8], ASMWEB_UDP_CHECKED_PAYLOAD_MAX + 1",
        14,
    ),
    (
        "batch_traversal_skipped",
        "dec r9\n    jnz .validate",
        "dec r9\n    nop\n    nop",
        18,
    ),
)


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def command(argv):
    result = subprocess.run(
        argv,
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    require(
        result.returncode == 0,
        f"COMMAND_FAILED={argv}\n"
        f"EXIT={result.returncode}\n"
        f"{result.stdout}\n{result.stderr}",
    )


def assemble(source, output):
    command([
        "nasm", "-f", "elf64",
        "-Wall", "-Werror",
        "-Wno-error=reloc-rel-dword",
        "-Iinclude/",
        "-o", str(output),
        str(source),
    ])


def link(output, network_obj, harness_obj):
    command([
        "ld", "-z", "noexecstack",
        "-o", str(output),
        str(harness_obj),
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


def mutate_function(source, function, old, new):
    beginning = function + ":\n"
    require(
        source.count(beginning) == 1,
        f"FUNCTION_NOT_UNIQUE={function}",
    )

    start = source.index(beginning)
    end = source.index("\n.invalid:\n", start)

    segment = source[start:end]
    require(
        segment.count(old) == 1,
        f"MUTATION_ANCHOR_INVALID={function}:{old}",
    )

    return (
        source[:start]
        + segment.replace(old, new, 1)
        + source[end:]
    )


def main():
    require(NETWORK.is_file(), "NETWORK_SOURCE_MISSING")
    require(HARNESS.is_file(), "HARNESS_MISSING")
    require(ORIGINAL_OBJECT.is_file(), "PRODUCTION_OBJECT_MISSING")

    source = NETWORK.read_text(encoding="utf-8")
    require(len(MUTATIONS) == 8, "MUTATION_CATALOGUE_INVALID")

    with TemporaryDirectory(prefix="asmweb-net005-mutations-") as tmp:
        work = Path(tmp)

        harness_obj = work / "harness.o"
        assemble(HARNESS, harness_obj)

        baseline = work / "baseline"
        link(baseline, ORIGINAL_OBJECT, harness_obj)

        require(
            execute(baseline) == 0,
            "UNMODIFIED_PRODUCTION_FAILED",
        )
        print("UNMODIFIED_PRODUCTION=PASS", flush=True)

        detected = 0

        for function in FUNCTIONS:
            for name, old, new, expected in MUTATIONS:
                mutated = mutate_function(source, function, old, new)

                folder = work / f"{function}-{name}"
                folder.mkdir()

                asm = folder / "network.asm"
                obj = folder / "network.o"
                executable = folder / "qualification"

                asm.write_text(mutated, encoding="utf-8")

                assemble(asm, obj)
                link(executable, obj, harness_obj)

                actual = execute(executable)

                require(
                    actual == expected,
                    "MUTATION_NOT_CORRECTLY_DETECTED="
                    f"{function}:{name}:"
                    f"expected={expected}:actual={actual}",
                )

                print(
                    f"{function}:{name}=REJECTED_EXIT_{actual}",
                    flush=True,
                )
                detected += 1

        require(
            detected == 16,
            f"UNEXPECTED_MUTATION_COUNT={detected}",
        )

        print(
            f"CHECKED_DESCRIPTOR_MUTATIONS_REJECTED={detected}/16",
            flush=True,
        )
        print(
            "NET005_CHECKED_MUTATION_QUALIFICATION=PASS",
            flush=True,
        )


if __name__ == "__main__":
    try:
        main()
    except (
        RuntimeError,
        OSError,
        subprocess.TimeoutExpired,
    ) as exc:
        print(
            f"NET005_CHECKED_MUTATION_QUALIFICATION=FAIL: {exc}",
            file=sys.stderr,
        )
        sys.exit(1)
