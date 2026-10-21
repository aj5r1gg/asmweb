#!/usr/bin/env python3
"""Integration checks for file-backed persistent HTTP serving."""

import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "build" / "asmweb"
HOST = "127.0.0.1"
PORT = 18080
HTML_BODY = (ROOT / "www" / "index.html").read_bytes()

CASES = [
    (
        "HTTP_200",
        b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
        b"HTTP/1.1 200 OK",
        HTML_BODY,
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
        HTML_BODY,
    ),
    (
        "VALID_LOOPBACK_IP",
        b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
        b"HTTP/1.1 200 OK",
        HTML_BODY,
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
        b"HTTP/1.1 404 Not Found",
        b"",
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

    def exchange(payload):
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
            conn.sendall(payload)

            response = bytearray()
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                response.extend(chunk)

        return bytes(response)

    try:
        content_type = (
            b"text/html; charset=utf-8"
            if status == b"HTTP/1.1 200 OK"
            else b"text/plain"
        )

        expected = (
            status
            + (
                b""
                if status == b"HTTP/1.1 404 Not Found"
                else b"\r\nContent-Type: " + content_type
            )
            + b"\r\nContent-Length: "
            + str(len(body)).encode("ascii")
            + b"\r\nConnection: close\r\n\r\n"
            + body
        )

        actual = exchange(request)

        if actual != expected:
            raise AssertionError(
                f"response mismatch: got {actual!r}"
            )

        if proc.poll() is not None:
            raise AssertionError(
                f"server unexpectedly exited: {proc.returncode}"
            )

        # Exercise persistence with a second connection for
        # each successful HTTP request.
        if status == b"HTTP/1.1 200 OK":
            second = exchange(request)

            if second != expected:
                raise AssertionError(
                    f"second response mismatch: got {second!r}"
                )

            if proc.poll() is not None:
                raise AssertionError(
                    "server exited after second connection"
                )

        print(
            f"{name}=PASS bytes={len(actual)} "
            f"persistent={proc.poll() is None}",
            flush=True,
        )

    finally:
        if proc.poll() is None:
            proc.terminate()

        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
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
