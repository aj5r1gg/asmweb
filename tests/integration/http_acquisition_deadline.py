#!/usr/bin/env python3
"""Live qualification of M1 absolute HTTP request acquisition deadlines."""

import os
import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVER = Path(os.environ.get(
    "ASMWEB_TEST_SERVER",
    str(ROOT / "build/asmweb"),
)).resolve()
ADDRESS = ("127.0.0.1", 18080)

REQUEST = b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"

BUDGET_SECONDS = 3.0
OBSERVATION_TOLERANCE = 1.0


def connect(proc, timeout=2.0):
    deadline = time.monotonic() + timeout

    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise AssertionError(
                f"Server exited unexpectedly: {proc.returncode}"
            )

        try:
            sock = socket.create_connection(
                ADDRESS, timeout=0.2
            )
            sock.settimeout(5.0)
            if proc.poll() is not None:
                sock.close()
                raise AssertionError(
                    "Spawned server exited while connecting; "
                    "possible unrelated listener"
                )
            return sock
        except OSError:
            time.sleep(0.025)

    raise AssertionError("Listener unavailable")


def receive_all(sock):
    data = bytearray()

    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data.extend(chunk)

    return bytes(data)


def verify_followup(proc):
    with connect(proc) as sock:
        sock.sendall(REQUEST)
        response = receive_all(sock)

    assert response.startswith(b"HTTP/1.1 200 OK\r\n"), (
        f"Follow-up request failed: {response[:120]!r}"
    )

    assert proc.poll() is None, (
        "Persistent listener terminated"
    )

    print("DEADLINE_LISTENER_SURVIVAL=PASS", flush=True)


def verify_fragmentation(proc):
    with connect(proc) as sock:
        started = time.monotonic()

        fragments = (
            REQUEST[:5],
            REQUEST[5:16],
            REQUEST[16:25],
            REQUEST[25:],
        )

        for fragment in fragments:
            sock.sendall(fragment)
            time.sleep(0.15)

        response = receive_all(sock)
        elapsed = time.monotonic() - started

    assert response.startswith(b"HTTP/1.1 200 OK\r\n"), (
        f"Fragmented request failed: {response[:120]!r}"
    )

    assert elapsed < BUDGET_SECONDS, (
        f"Fragmented request exceeded budget: {elapsed:.3f}s"
    )

    print(
        f"DEADLINE_VALID_FRAGMENTATION=PASS elapsed={elapsed:.3f}s",
        flush=True,
    )

    verify_followup(proc)


def verify_slow_drip(proc):
    with connect(proc) as sock:
        started = time.monotonic()

        # Bytes arrive well within the old three-second
        # per-receive timeout, but never form a valid request.
        for index in range(5):
            sock.sendall(b"G")

            if index != 4:
                time.sleep(0.55)

        # Begin observing closure before the deadline.
        sock.settimeout(BUDGET_SECONDS + OBSERVATION_TOLERANCE)

        response = receive_all(sock)
        elapsed = time.monotonic() - started

    assert response == b"", (
        f"Unexpected slow-client response: {response[:120]!r}"
    )

    assert elapsed <= (
        BUDGET_SECONDS + OBSERVATION_TOLERANCE
    ), (
        f"Slow-client deadline exceeded: {elapsed:.3f}s"
    )

    print(
        f"DEADLINE_SLOW_DRIP=PASS elapsed={elapsed:.3f}s",
        flush=True,
    )

    verify_followup(proc)


def main():
    if not SERVER.is_file():
        raise AssertionError("Missing build/asmweb")

    # Fail before launching the server if an existing process
    # already owns the test address. SO_REUSEADDR permits normal
    # rapid test reruns without permitting two ordinary listeners
    # to bind the same address concurrently.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(ADDRESS)
        except OSError as exc:
            raise AssertionError(
                f"Test port {ADDRESS!r} unavailable: {exc}"
            ) from exc

    proc = subprocess.Popen(
        [str(SERVER)],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    try:
        verify_fragmentation(proc)
        verify_slow_drip(proc)

        print("HTTP_ACQUISITION_DEADLINE=PASS", flush=True)
        return 0

    finally:
        if proc.poll() is None:
            proc.terminate()

        try:
            _, stderr = proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, stderr = proc.communicate(timeout=3)

        if stderr:
            print(f"SERVER_STDERR={stderr[:1000]!r}")


if __name__ == "__main__":
    raise SystemExit(main())
