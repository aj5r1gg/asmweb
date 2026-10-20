#!/usr/bin/env python3
"""Permanent M0-DIAG-002 positive/negative bootstrap qualification."""

from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/qualification/ready_bootstrap_injection.asm"

WRAPPED = (
    "asm_runtime_invariant_validate_ready",
    "asm_diagnostic_record_invariant",
    "asm_linux_exit",
)

REFERENCES = (
    ("runtime.o", "asm_runtime_ready_validate_diagnose"),
    ("ready_diagnostic.o", "asm_runtime_invariant_validate_ready"),
    ("ready_diagnostic.o", "asm_diagnostic_record_invariant"),
    ("start.o", "asm_linux_exit"),
)


def run(args, timeout=15):
    return subprocess.run(
        [str(arg) for arg in args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def require(ok, label):
    print(f"{label}={'PASS' if ok else 'FAIL'}", flush=True)
    if not ok:
        raise RuntimeError(label)


def main():
    sources = sorted((ROOT / "src").rglob("*.asm"))
    objects = [
        ROOT / "build" / source.relative_to(
            ROOT / "src"
        ).with_suffix(".o")
        for source in sources
    ]

    require(
        bool(objects)
        and len(objects) == len(set(objects))
        and all(obj.is_file() for obj in objects),
        "PRODUCTION_OBJECT_CLOSURE",
    )

    require(
        (ROOT / "build/asmweb").is_file(),
        "PRODUCTION_BINARY",
    )

    names = {obj.name for obj in objects}

    require(
        {
            "runtime.o",
            "ready_diagnostic.o",
            "diagnostic.o",
            "runtime_invariant.o",
            "start.o",
        } <= names,
        "REQUIRED_OBJECTS",
    )

    for obj_name, symbol in REFERENCES:
        obj = next(obj for obj in objects if obj.name == obj_name)
        result = run(["nm", "-u", obj])
        require(
            result.returncode == 0
            and symbol in result.stdout.split(),
            f"UNRESOLVED_{obj_name}_{symbol}",
        )

    results = []

    with tempfile.TemporaryDirectory(
        prefix="asmweb-ready-bootstrap-"
    ) as temporary:
        directory = Path(temporary)

        for variant, negative, expected_exit in (
            ("CAPTURE", False, 0),
            ("SUPPRESSED_CAPTURE", True, 41),
        ):
            obj = directory / f"{variant}.o"
            binary = directory / f"{variant}.bin"

            args = [
                "nasm", "-f", "elf64",
                "-Wall", "-Werror",
                "-Wno-error=reloc-rel-dword",
                "-Iinclude/",
            ]

            if negative:
                args.append("-DNEGATIVE=1")

            args.extend(["-o", obj, SOURCE])

            assembled = run(args)
            if assembled.returncode:
                print(assembled.stderr)

            require(
                assembled.returncode == 0,
                f"{variant}_ASSEMBLY",
            )

            linked = run([
                "ld", "-z", "noexecstack",
                *(f"--wrap={name}" for name in WRAPPED),
                "-o", binary,
                *objects,
                obj,
            ])

            if linked.returncode:
                print(linked.stderr)

            require(linked.returncode == 0, f"{variant}_LINK")

            symbols = run(["nm", "-n", binary])

            require(
                symbols.returncode == 0
                and all(
                    f"__wrap_{name}" in symbols.stdout
                    for name in WRAPPED
                ),
                f"{variant}_WRAPPER_SYMBOLS",
            )

            executed = run([binary], timeout=5)

            print(
                f"{variant}_ACTUAL_EXIT={executed.returncode}",
                flush=True,
            )

            require(
                executed.returncode == expected_exit,
                f"{variant}_EXPECTED_EXIT",
            )

            results.append((variant, executed.returncode))

    require(
        results == [
            ("CAPTURE", 0),
            ("SUPPRESSED_CAPTURE", 41),
        ],
        "NEGATIVE_CONTROL_SENSITIVE",
    )

    print("M0_DIAG_002_BOOTSTRAP_INJECTION=PASS")


if __name__ == "__main__":
    try:
        main()
    except (
        RuntimeError,
        OSError,
        StopIteration,
        subprocess.TimeoutExpired,
    ) as error:
        print(
            f"M0_DIAG_002_BOOTSTRAP_INJECTION=FAIL: {error}",
            file=sys.stderr,
        )
        sys.exit(1)
