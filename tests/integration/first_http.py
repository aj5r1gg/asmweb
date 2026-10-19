#!/usr/bin/env python3
"""M1 experimental single-connection HTTP integration tests."""

import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "build" / "asmweb"
HOST = "127.0.0.1"
PORT = 18080

CASES = [
    (
        "HTTP_200",
        b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
        b"HTTP/1.1 200 OK",
        b"AsmWeb\n",
    ),
    (
        "HTTP_400",
        b"BAD / HTTP/1.1\r\nHost: localhost\r\n\r\n",
        b"HTTP/1.1 400 Bad Request",
        b"Bad Request\n",
    ),
    (
        "HTTP_431",
        b"A" * 1024,
        b"HTTP/1.1 431 Request Header Fields Too Large",
        b"Header Too Large\n",
    ),
    (
        "VALID_LOCALHOST",
        b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
        b"HTTP/1.1 200 OK",
        b"AsmWeb\n",
    ),
    (
        "VALID_LOOPBACK_IP",
        b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
        b"HTTP/1.1 200 OK",
        b"AsmWeb\n",
    ),
    (
        "MISSING_HOST",
        b"GET / HTTP/1.1\r\n\r\n",
        b"HTTP/1.1 400 Bad Request",
        b"Bad Request\n",
    ),
    (
        "DUPLICATE_HOST",
        b"GET / HTTP/1.1\r\nHost: localhost\r\n"
        b"Host: localhost\r\n\r\n",
        b"HTTP/1.1 400 Bad Request",
        b"Bad Request\n",
    ),
    (
        "UNSUPPORTED_METHOD",
        b"POST / HTTP/1.1\r\nHost: localhost\r\n\r\n",
        b"HTTP/1.1 400 Bad Request",
        b"Bad Request\n",
    ),
    (
        "UNSUPPORTED_PATH",
        b"GET /admin HTTP/1.1\r\nHost: localhost\r\n\r\n",
        b"HTTP/1.1 400 Bad Request",
        b"Bad Request\n",
    ),
    (
        "BODY_FRAMING",
        b"GET / HTTP/1.1\r\nHost: localhost\r\n"
        b"Content-Length: 3\r\n\r\nabc",
        b"HTTP/1.1 400 Bad Request",
        b"Bad Request\n",
    ),
    (
        "TRAILING_BYTES",
        b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\nJUNK",
        b"HTTP/1.1 400 Bad Request",
        b"Bad Request\n",
    ),
    (
        "EMBEDDED_NUL",
        b"GET / HTTP/1.1\r\nHost: local\x00host\r\n\r\n",
        b"HTTP/1.1 400 Bad Request",
        b"Bad Request\n",
    ),
]


def run_case(name, request, status, body):
    proc = subprocess.Popen(
        [str(SERVER)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    try:
        conn = None

        for _ in range(60):
            if proc.poll() is not None:
                raise RuntimeError(
                    f"server exited before connection: {proc.returncode}"
                )

            try:
                conn = socket.create_connection(
                    (HOST, PORT), timeout=0.25
                )
                break
            except OSError:
                time.sleep(0.02)

        if conn is None:
            raise RuntimeError("listener unavailable")

        with conn:
            conn.settimeout(5)
            conn.sendall(request)
            response = bytearray()

            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                response.extend(chunk)

        proc.wait(timeout=5)

        expected = (
            status
            + b"\r\nContent-Type: text/plain\r\n"
            + b"Content-Length: "
            + str(len(body)).encode("ascii")
            + b"\r\nConnection: close\r\n\r\n"
            + body
        )

        if bytes(response) != expected:
            raise AssertionError(
                f"response mismatch: got {bytes(response)!r}"
            )

        if proc.returncode != 0:
            raise AssertionError(
                f"unexpected exit status {proc.returncode}"
            )

        print(
            f"{name}=PASS bytes={len(response)} "
            f"exit={proc.returncode}",
            flush=True,
        )

    finally:
        if proc.poll() is None:
            proc.kill()
        proc.communicate(timeout=5)


def main():
    if not SERVER.is_file():
        print("HTTP_INTEGRATION=FAIL missing build/asmweb")
        return 1

    failures = []

    for case in CASES:
        try:
            run_case(*case)
        except Exception as exc:
            failures.append(case[0])
            print(
                f"{case[0]}=FAIL {type(exc).__name__}: {exc}",
                flush=True,
            )

    if failures:
        print(f"HTTP_INTEGRATION=FAIL cases={failures}")
        return 1

    print("HTTP_INTEGRATION=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
