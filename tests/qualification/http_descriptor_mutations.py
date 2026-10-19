#!/usr/bin/env python3
"""Adversarial mutation qualification for HTTP descriptor ownership.

Mutate temporary copies of the real production HTTP assembly source.
Never modify production source files or production build objects.
"""

from pathlib import Path
import subprocess
import sys
import tempfile

HANDLER = Path("src/http/first_response.asm")
HARNESS_OBJECT = Path(
    "build/tests/qualification/http_descriptor_lifecycle.o"
)
BASELINE = Path(
    "build/qualification/http-descriptor-lifecycle"
)

CLOSE = "    call asm_linux_close"
MAX_SCENARIO = 14


def run(arguments, *, timeout=10):
    return subprocess.run(
        [str(arg) for arg in arguments],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def require(condition, explanation):
    if not condition:
        raise AssertionError(explanation)


def run_executable(executable):
    result = run([executable], timeout=5)
    require(
        result.returncode >= 0,
        f"Terminated by signal: {result.returncode}",
    )
    return result.returncode


def mutate_cleanup(source, resource, replacement):
    start_label = (
        ".cleanup:\n"
        if resource == "accepted"
        else ".close_listener:\n"
    )
    end_label = (
        ".close_listener:\n"
        if resource == "accepted"
        else ".return:\n"
    )

    require(source.count(start_label) == 1, "Start label mismatch")
    require(source.count(end_label) == 1, "End label mismatch")

    before, tail = source.split(start_label, 1)
    region, after = tail.split(end_label, 1)

    require(
        region.count(CLOSE) == 1,
        f"Unexpected {resource} close topology",
    )

    region = region.replace(CLOSE, replacement, 1)

    return (
        before + start_label + region + end_label + after
    )


def main():
    require(HANDLER.is_file(), "Missing HTTP handler")
    require(HARNESS_OBJECT.is_file(), "Missing lifecycle object")
    require(BASELINE.is_file(), "Missing baseline executable")

    baseline_status = run_executable(BASELINE.resolve())
    require(baseline_status == 0, "Unmodified handler failed")

    print("UNMODIFIED_HANDLER=PASS")

    source = HANDLER.read_text()

    require(
        source.count(CLOSE) == 2,
        "Unexpected total close topology",
    )

    mutations = {
        "SKIPPED_ACCEPTED_CLOSE": mutate_cleanup(
            source,
            "accepted",
            "    xor eax, eax ; MUTATION: omitted accepted close",
        ),
        "DUPLICATE_ACCEPTED_CLOSE": mutate_cleanup(
            source,
            "accepted",
            CLOSE + "\n" + CLOSE
            + " ; MUTATION: duplicate accepted close",
        ),
        "SKIPPED_LISTENER_CLOSE": mutate_cleanup(
            source,
            "listener",
            "    xor eax, eax ; MUTATION: omitted listener close",
        ),
        "DUPLICATE_LISTENER_CLOSE": mutate_cleanup(
            source,
            "listener",
            CLOSE + "\n" + CLOSE
            + " ; MUTATION: duplicate listener close",
        ),
    }

    with tempfile.TemporaryDirectory(
        prefix="asmweb-http-mutation-"
    ) as temporary:
        directory = Path(temporary)

        for name, mutated_source in mutations.items():
            asm = directory / (name + ".asm")
            obj = directory / (name + ".o")
            binary = directory / name

            asm.write_text(mutated_source)

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
                f"{name}: assembly failed:\n{assembly.stderr}",
            )

            linkage = run([
                "ld",
                "-z", "noexecstack",
                "-o", binary,
                obj,
                HARNESS_OBJECT,
            ])

            require(
                linkage.returncode == 0,
                f"{name}: link failed:\n{linkage.stderr}",
            )

            status = run_executable(binary)

            require(
                1 <= status <= MAX_SCENARIO,
                f"{name}: mutation survived, status={status}",
            )

            print(
                f"{name}=REJECTED scenario={status - 1}"
            )

    print("MUTATION_SENSITIVITY=PASS")
    print("MUTATIONS_REJECTED=4")
    print("PRODUCTION_SOURCE=UNCHANGED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (
        AssertionError,
        OSError,
        subprocess.TimeoutExpired,
    ) as exc:
        print(f"MUTATION_SENSITIVITY=FAIL {exc}")
        sys.exit(1)
