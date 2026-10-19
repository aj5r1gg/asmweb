#!/usr/bin/env python3
"""Socket acquisition and bind-failure integration tests.

Exercises the real production executable. No test-only assembly
implementation or production instrumentation is used.
"""

import resource
import socket
import subprocess
import sys

SERVER = "./build/asmweb"
ADDRESS = ("127.0.0.1", 18080)


def run_server(name, preexec_fn=None):
    proc = subprocess.Popen(
        [SERVER],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        preexec_fn=preexec_fn,
    )

    try:
        _, stderr = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise AssertionError(f"{name}: server timed out")

    if proc.returncode != 1:
        raise AssertionError(
            f"{name}: expected exit 1, got {proc.returncode}; "
            f"stderr={stderr[:200]!r}"
        )

    print(f"{name}=PASS exit=1")


def exhaust_descriptors():
    # stdin/stdout/stderr occupy descriptors 0, 1 and 2.
    # No additional descriptor can be acquired.
    resource.setrlimit(resource.RLIMIT_NOFILE, (3, 3))


def test_socket_refusal():
    run_server(
        "SOCKET_ACQUISITION_REFUSED",
        preexec_fn=exhaust_descriptors,
    )


def test_bind_refusal():
    with socket.socket(
        socket.AF_INET, socket.SOCK_STREAM
    ) as blocker:
        # Match the production listener's address-reuse policy.
        # Previous HTTP tests may have left TCP sockets in TIME_WAIT.
        blocker.setsockopt(
            socket.SOL_SOCKET,
            socket.SO_REUSEADDR,
            1,
        )
        blocker.bind(ADDRESS)
        blocker.listen(1)
        run_server("BIND_ADDRESS_IN_USE")


def main():
    failures = []

    for name, test in (
        ("SOCKET_ACQUISITION_REFUSED", test_socket_refusal),
        ("BIND_ADDRESS_IN_USE", test_bind_refusal),
    ):
        try:
            test()
        except Exception as exc:
            failures.append(name)
            print(
                f"{name}=FAIL "
                f"{type(exc).__name__}: {exc}"
            )

    print(
        "SOCKET_FAILURE_INTEGRATION="
        + ("FAIL" if failures else "PASS")
    )

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
