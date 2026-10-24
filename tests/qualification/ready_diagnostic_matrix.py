#!/usr/bin/env python3
"""M0-DIAG-003: real READY-validator diagnostic classification matrix.

Derives fixtures from the established runtime-invariant qualification.
The source fixture is not modified. All generated binaries are temporary.

Positive: 20 failure fixtures, 11 classifications, 2 success fixtures.
Negative: bypass adapter; first missing publication must fail case 2.
"""

from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/qualification/runtime_invariant.asm"

OBJECTS = [
    "build/linux/syscall.o",
    "build/runtime/arithmetic.o",
    "build/runtime/memory_ceiling.o",
    "build/runtime/registry.o",
    "build/runtime/process_runtime.o",
    "build/runtime/startup_memory.o",
    "build/runtime/config_dependency.o",
    "build/runtime/runtime_invariant.o",
    "build/runtime/diagnostic.o",
    "build/runtime/ready_diagnostic.o",
]

ADAPTER = "    call asm_runtime_ready_validate_diagnose"
RAW_VALIDATOR = "    call asm_runtime_invariant_validate_ready"


def run(args, timeout=30):
    return subprocess.run(
        [str(value) for value in args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def require(label, condition):
    print(f"{label}={'PASS' if condition else 'FAIL'}", flush=True)
    if not condition:
        raise RuntimeError(label)


def replace_once(source, before, after, label):
    require(label, source.count(before) == 1)
    return source.replace(before, after, 1)


def record_checks(case, expected):
    return f"""
    ; Capture is mandatory for failure fixture {case}.
    lea rdi, [rel diagnostic]
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_{case}

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.domain], \
        ASMWEB_DIAG_DOMAIN_RUNTIME_INVARIANT
    jne .fail_{case}

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.classification], \
        ASMWEB_RESOURCE_INTEGRITY
    jne .fail_{case}

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.origin], \
        ASMWEB_DIAG_ORIGIN_READY_VALIDATOR
    jne .fail_{case}

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.local_code], \
        {expected}
    jne .fail_{case}

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.published], 1
    jne .fail_{case}

    mov rax, 0x1122334455667788
    cmp qword [rel guard_before], rax
    jne .fail_{case}

    mov rax, 0x8877665544332211
    cmp qword [rel guard_after], rax
    jne .fail_{case}
"""


def generate():
    source = FIXTURE.read_text()

    source = replace_once(
        source,
        "extern asm_runtime_invariant_validate_ready\n",
        "extern asm_runtime_ready_validate_diagnose\n"
        "extern asm_runtime_invariant_validate_ready\n"
        "extern asm_diagnostic_init\n"
        "extern asm_diagnostic_validate\n",
        "VALIDATOR_EXTERN_ANCHOR",
    )

    anchor = '%include "asmweb/runtime_invariant.inc"\n'
    source = replace_once(
        source,
        anchor,
        anchor + '%include "asmweb/diagnostic.inc"\n',
        "DIAGNOSTIC_INCLUDE_ANCHOR",
    )

    source = replace_once(
        source,
        "section .text\n",
        """
guard_before: resq 1
diagnostic:   resb ASMWEB_DIAGNOSTIC_size
guard_after:  resq 1

section .text
""",
        "TEXT_ANCHOR",
    )

    source = replace_once(
        source,
        "_start:\n    cld\n",
        """_start:
    cld
    mov rax, 0x1122334455667788
    mov [rel guard_before], rax
    mov rax, 0x8877665544332211
    mov [rel guard_after], rax
""",
        "START_ANCHOR",
    )

    # Restore the fixture's original validator argument and flags.
    # In case 15, STD deliberately sets DF before the adapter call.
    # Resetting the diagnostic record must not remove that condition.
    replacement = """    sub rsp, 32
    mov [rsp], rdi
    pushfq
    pop rax
    mov [rsp + 8], rax

    cld
    lea rdi, [rel diagnostic]
    xor eax, eax
    mov ecx, ASMWEB_DIAGNOSTIC_size / 8
    rep stosq

    lea rdi, [rel diagnostic]
    call asm_diagnostic_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne matrix_initialisation_failed

    mov rdi, [rsp]
    mov rax, [rsp + 8]
    add rsp, 32
    push rax
    popfq

    lea rsi, [rel diagnostic]
    call asm_runtime_ready_validate_diagnose"""

    require(
        "VALIDATOR_CALLS_22",
        source.count(RAW_VALIDATOR) == 22,
    )

    source = source.replace(RAW_VALIDATOR, replacement)

    pattern = re.compile(
        r"(    cmp edx, "
        r"(ASMWEB_RUNTIME_INVARIANT_FAIL_[A-Z_]+)"
        r"\n    jne \.fail_(\d+)\n)"
    )

    matches = list(pattern.finditer(source))

    require("FAILURE_FIXTURES_20", len(matches) == 20)

    require(
        "FAILURE_CASES_2_TO_14_AND_16_TO_22",
        {int(m.group(3)) for m in matches}
        == (set(range(2, 15)) | set(range(16, 23))),
    )

    require(
        "FAILURE_CLASSES_11",
        len({m.group(2) for m in matches}) == 11,
    )

    source = pattern.sub(
        lambda match:
            match.group(1)
            + record_checks(int(match.group(3)), match.group(2)),
        source,
    )

    for case in (1, 15):
        anchor = (
            f"    cmp rdx, 64\n"
            f"    jne .fail_{case}\n"
        )

        extra = f"""
    lea rdi, [rel diagnostic]
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_{case}

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.published], 0
    jne .fail_{case}
"""

        source = replace_once(
            source,
            anchor,
            anchor + extra,
            f"SUCCESS_CASE_{case}",
        )

    # Distinct failure code for an unexpected initializer rejection.
    # Appended as a non-local label so it is reachable from all cases.
    source += """
matrix_initialisation_failed:
    cld
    mov edi, 50
    call asm_linux_exit
    ud2
"""

    require(
        "ADAPTER_CALLS_22",
        source.count(ADAPTER) == 22,
    )

    return source


def execute_variant(directory, name, source, expected_exit):
    asm = directory / f"{name}.asm"
    obj = directory / f"{name}.o"
    binary = directory / f"{name}.bin"

    asm.write_text(source)

    assembly = run([
        "nasm", "-f", "elf64",
        "-Wall", "-Werror",
        "-Wno-error=reloc-rel-dword",
        "-Iinclude/",
        "-o", obj,
        asm,
    ])

    if assembly.returncode:
        print(assembly.stderr, flush=True)

    require(f"{name}_ASSEMBLY", assembly.returncode == 0)

    linking = run([
        "ld", "-z", "noexecstack",
        "-o", binary,
        *(ROOT / path for path in OBJECTS),
        obj,
    ])

    if linking.returncode:
        print(linking.stderr, flush=True)

    require(f"{name}_LINK", linking.returncode == 0)

    result = run([binary], timeout=10)

    print(f"{name}_ACTUAL_EXIT={result.returncode}", flush=True)
    require(
        f"{name}_EXPECTED_EXIT",
        result.returncode == expected_exit,
    )


def main():
    require(
        "SOURCE_EXISTS",
        FIXTURE.is_file(),
    )

    require(
        "PRODUCTION_OBJECTS_PRESENT",
        all((ROOT / path).is_file() for path in OBJECTS),
    )

    positive = generate()

    # Deliberate mutation:
    # bypass the diagnostic adapter while keeping the real validator.
    # The first failure (case 2) must now leave published=0 and
    # produce the original fixture's failure exit code 2.
    negative = positive.replace(ADAPTER, RAW_VALIDATOR)

    require(
        "MUTATION_REPLACEMENTS_22",
        negative.count(ADAPTER) == 0
        and negative.count(RAW_VALIDATOR) == 22,
    )

    with tempfile.TemporaryDirectory(
        prefix="asmweb-ready-matrix-"
    ) as temp:
        directory = Path(temp)

        execute_variant(
            directory,
            "REAL_ADAPTER",
            positive,
            0,
        )

        execute_variant(
            directory,
            "BYPASSED_ADAPTER",
            negative,
            2,
        )

    print("READY_FAILURE_FIXTURES=20")
    print("READY_FAILURE_CLASSES=11")
    print("READY_SUCCESS_FIXTURES=2")
    print("MATRIX_ADAPTER_BYPASS_MUTATION=REJECTED")
    print("M0_DIAG_003_MATRIX=PASS")


if __name__ == "__main__":
    try:
        main()
    except (
        RuntimeError,
        OSError,
        subprocess.TimeoutExpired,
    ) as error:
        print(
            f"M0_DIAG_003_MATRIX=FAIL: {error}",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(1)
