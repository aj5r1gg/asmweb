#!/usr/bin/env python3

import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "build/asmweb"
ADDRESS = ("127.0.0.1", 18080)
REQUEST = b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"

def connect(proc, seconds=2.0):
    deadline = time.monotonic() + seconds

    while time.monotonic() < deadline:
        if proc.poll() is not None:
            return None

        try:
            sock = socket.create_connection(ADDRESS, timeout=0.2)
            sock.settimeout(1)
            return sock
        except OSError:
            time.sleep(0.025)

    return None

def main():
    if not SERVER.is_file():
        print("SERVER_BINARY=MISSING")
        return 1

    proc = subprocess.Popen(
        [str(SERVER)],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    try:
        idle = connect(proc)

        if idle is None:
            print("LISTENER_START=FAIL")
            return 1

        with idle:
            idle.sendall(b"GET / HTTP/1.1\r\nHost: loc")
            print("INCOMPLETE_REQUEST_SENT=PASS", flush=True)

            # Exceed the server's three-second receive timeout.
            time.sleep(3.6)

            code = proc.poll()

            if code is None:
                print("SERVER_AFTER_IDLE_TIMEOUT=RUNNING")
            else:
                print(f"SERVER_AFTER_IDLE_TIMEOUT=EXITED code={code}")

            try:
                result = idle.recv(4096)
                print(f"IDLE_CLIENT_RESPONSE={result[:120]!r}")
            except OSError as exc:
                print(
                    "IDLE_CLIENT_SOCKET_ERROR="
                    f"{type(exc).__name__}: {exc}"
                )

        if proc.poll() is not None:
            print("POST_TIMEOUT_SERVICE=UNAVAILABLE_SERVER_EXITED")
            print("IDLE_CLIENT_SURVIVAL=FAIL")
            return 1

        followup = connect(proc, seconds=1.0)

        if followup is None:
            print("POST_TIMEOUT_SERVICE=CONNECT_FAILED")
            print("IDLE_CLIENT_SURVIVAL=FAIL")
            return 1

        with followup:
            followup.sendall(REQUEST)
            followup.settimeout(1.5)

            response = bytearray()
            try:
                while len(response) < 8192:
                    chunk = followup.recv(4096)
                    if not chunk:
                        break
                    response.extend(chunk)
            except OSError as exc:
                print(f"FOLLOWUP_READ_ERROR={exc}")

        if response.startswith(b"HTTP/1.1 200 OK\r\n"):
            print("POST_TIMEOUT_SERVICE=PASS")
            print("IDLE_CLIENT_SURVIVAL=PASS")
        else:
            print(f"FOLLOWUP_RESPONSE={bytes(response[:120])!r}")
            print("POST_TIMEOUT_SERVICE=FAIL")
            print("IDLE_CLIENT_SURVIVAL=FAIL")

        return (
            0
            if response.startswith(b"HTTP/1.1 200 OK\r\n")
            else 1
        )

    finally:
        if proc.poll() is None:
            proc.terminate()

        try:
            proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate(timeout=2)

if __name__ == "__main__":
    raise SystemExit(main())
