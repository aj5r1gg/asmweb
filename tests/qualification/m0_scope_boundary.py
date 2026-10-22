#!/usr/bin/env python3
"""REQ-M0-001: M0 foundation must not depend on later HTTP implementation.

Evaluate the existing foundation qualification build graph rather than
asserting a claim about the architecture in an approval document.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOUNDATION = (
    "qualify-process-entry",
    "qualify-cpu",
    "qualify-time",
    "qualify-entropy",
    "qualify-memory",
    "qualify-stack",
    "qualify-config-dependency",
)
HTTP_INPUTS = ("src/http/", "build/http/", "first_response.asm")


def main():
    result = subprocess.run(
        ["make", "--no-print-directory", "-n", "-B", *FOUNDATION],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=45,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("foundation graph failed: " + result.stderr[-1500:])
    if not result.stdout.strip():
        raise RuntimeError("empty foundation graph")
    for http_path in HTTP_INPUTS:
        if http_path in result.stdout:
            raise RuntimeError("M0 foundation requires HTTP: " + http_path)
    print("M0_FOUNDATION_HTTP_DEPENDENCY=NONE")
    print("REQ_M0_001_ENGINEERING_QUALIFICATION=PASS")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as exc:
        print("REQ_M0_001_ENGINEERING_QUALIFICATION=FAIL: " + str(exc),
              file=sys.stderr)
        raise SystemExit(1)
