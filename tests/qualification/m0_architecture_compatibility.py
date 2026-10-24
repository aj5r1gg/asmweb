#!/usr/bin/env python3
"""REQ-M0-002: tested downstream compatibility of the M0 foundation."""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

TARGETS = {
    "TCP_ACCEPT4": "qualify-tcp-accept4",
    "UDP_LOOPBACK": "qualify-udp-loopback",
    "HTTP_DESCRIPTOR": "qualify-http-descriptor-lifecycle",
}


def main():
    for name, target in TARGETS.items():
        result = subprocess.run(
            ["make", "--no-print-directory", target],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )

        if result.returncode != 0:
            print(result.stdout[-4000:])
            print(result.stderr[-4000:], file=sys.stderr)
            raise RuntimeError(
                f"{name} compatibility qualification failed"
            )

        print(f"M0_COMPAT_{name}=PASS")

    print("REQ_M0_002_ENGINEERING_QUALIFICATION=PASS")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        print(
            "REQ_M0_002_ENGINEERING_QUALIFICATION=FAIL:",
            exc,
            file=sys.stderr,
        )
        sys.exit(1)
