# AsmWeb

**A deliberately small, resource-bounded web server written in native x86-64 assembly for Linux.**

> **Do less. Bound everything. Measure the rest.**

AsmWeb explores a simple engineering question: how much useful web-serving infrastructure can be built directly in assembly, with explicit ownership, bounded memory, predictable failure handling, and tests that exercise real Linux kernel behaviour?

The purpose is **not** to claim that assembly is inherently faster, more secure, or a better choice than established web servers. It is to construct a narrowly scoped server whose behaviour can be understood, measured, and challenged at the syscall, runtime, and HTTP levels.

**Current status:** Experimental M1 development. The repository contains a functioning loopback-only HTTP server and substantial low-level and integration qualification. **It is not production-ready, and it is not yet protected against slow clients by an enforced absolute request deadline.**

## Quick start

### Requirements

- Linux on **x86-64** (the assembly and syscalls are Linux-specific)
- **NASM**
- GNU **make** and **ld** (typically supplied by binutils)
- **Python 3** for integration tests
- `timeout` from GNU coreutils for selected qualification targets
- **Git** to clone the repository

The primary build uses NASM and GNU `ld`; it does not require a C compiler to link the server.

```bash
git clone https://github.com/aj5r1gg/asmweb.git
cd asmweb
make -j2 all
./build/asmweb
```

In another terminal:

```bash
curl --http1.1 -i http://127.0.0.1:18080/
```

Run the executable **from the repository root**: the current file-backed response opens `www/index.html` relative to the process working directory. Stop the server with Ctrl+C.

The listener is fixed to **127.0.0.1:18080**; it is not a general network-facing deployment configuration.

## What works today

### HTTP serving

- A persistent, **sequential** TCP listener on IPv4 loopback.
- A constrained `GET / HTTP/1.1` request path.
- A required, single `Host` header with supported localhost values.
- File-backed responses from `www/index.html` with a fixed **4,096-byte maximum page size**.
- Connection-closing responses with explicit `Content-Length`.
- Responses for the implemented success and rejection cases, including **200**, **400**, and **431**; file errors include **404** and **500** handling.
- Bounded request acquisition using a **1,024-byte header buffer**.
- Correct handling of headers split across multiple socket reads.
- Partial-write handling during response transmission.
- Recovery after incomplete requests, client half-closes, and accepted-client receive timeouts.

This is a **restricted HTTP/1.1 implementation**, not a complete HTTP/1.1 server. In particular, arbitrary routes, request bodies, keep-alive, pipelining, TLS, and general-purpose virtual hosting are not currently implemented. The application closes connections after a response.

### Linux networking primitives

The codebase exposes small wrappers for Linux socket operations, including socket creation, bind, listen, accept, `accept4`, receive, send, datagram send/receive, socket options, socket identity queries, and close.

Wrappers follow the project's internal calling convention and expose **raw Linux syscall results** rather than silently retrying operations or translating errors. Newly acquired descriptors are owned by the caller; operations that inspect or use a descriptor borrow it; close consumes it.

The networking test suite exercises actual sockets and syscalls, including TCP and UDP loopback, stream fragmentation, nonblocking short writes, truncation and error paths, descriptor cleanup, and signal-driven `EINTR`.

### Runtime and resource controls

AsmWeb has a substantial runtime foundation alongside the HTTP prototype. The repository includes platform, runtime, memory, process-entry, invariant, registry, and qualification modules.

The existing monotonic-clock routine obtains `CLOCK_MONOTONIC`, validates the sample, and converts it to an overflow-checked unsigned nanosecond representation. A separate **deadline arithmetic** module computes remaining time and a positive Linux `timeval`, with explicit active, expired, and invalid results.

**Important distinction:** Deadline arithmetic has been implemented and locally qualified, but it has **not yet been wired into the HTTP receive loop**. A client sending bytes at intervals shorter than the socket's idle timeout can still occupy the sequential server for more than three seconds.

## Explicit limits and current boundaries

| Area | Current boundary |
| --- | --- |
| Platform | Linux x86-64 |
| Binding | IPv4 loopback, `127.0.0.1:18080` |
| Concurrency | One accepted connection processed at a time |
| Supported request | Restricted HTTP/1.1 `GET /` |
| Request header buffer | 1,024 bytes |
| Served file | `www/index.html` relative to working directory |
| Served file size | Up to 4,096 bytes |
| Socket receive/send idle timeout | 3 seconds per blocking operation |
| Absolute HTTP request-acquisition deadline | **Not yet enforced** |
| TLS | Not implemented |
| General routing / dynamic content | Not implemented |
| HTTP persistent connections / pipelining | Not implemented |
| Deployment status | Experimental; loopback development use |

A 3-second **idle timeout** is **not** a 3-second **total request deadline**. An accepted client that periodically delivers more data can still prevent the sequential server from servicing another request. This limitation has been reproduced in an integration probe and is a current M1 work item.

Likewise, successful local tests are not a substitute for production hardening, comprehensive protocol conformance, fuzzing, external security review, or deployment-specific performance measurement.

## Build and qualification

Build the application:

```bash
make -j2 all
```

Run the existing application integration tests:

```bash
python3 tests/integration/first_http.py
python3 tests/integration/socket_failures.py
python3 tests/integration/http_idle_survival.py
```

Run the targeted assembly and behavioural qualifications:

```bash
make qualify-time
make qualify-deadline
make qualify-udp-loopback
make qualify-tcp-accept4
make qualify-network-error-paths
make qualify-stream-fragments
make qualify-stream-short-write
make qualify-network-eintr
make qualify-http-descriptor-lifecycle
make qualify-http-descriptor-mutations
```

`make qualify-deadline` currently tests **15 arithmetic boundary cases**, including exact expiry, overflow, backward time samples, sub-microsecond positive intervals, register preservation, and buffer guards. The deadline qualification was also repeated successfully across 20 local executions before publication.

`make qualify-network-eintr` installs a real signal handler, uses a kernel timer to interrupt a blocking receive, verifies that `-EINTR` is returned, and checks buffer integrity, socket reuse and descriptor cleanup.

The `http_idle_survival.py` regression verifies that an incomplete, idle client does **not** terminate the persistent listener and that a subsequent valid client receives HTTP 200. Its sensitivity was checked against both an original vulnerable server (expected failure) and the corrected server (expected success).

The HTTP descriptor mutation qualification deliberately changes cleanup behaviour and verifies that the lifecycle tests reject those mutations.

### Continuous integration

GitHub Actions runs the project build and registered qualification targets. See [the CI workflow](.github/workflows/ci.yml) for the authoritative current command list.

The latest locally verified revision for this README update is:

```text
6aab023 feat(time): add qualified deadline arithmetic
```

The deadline arithmetic changes passed local qualification and GitHub Actions on `main` (commit `6aab023`, workflow run `39399296594`). A successful CI run verifies its executed checks; it does not establish production readiness or formal milestone closure.

## Milestone and qualification governance

AsmWeb follows a controlled **M0–M16 milestone baseline**.

The M0 engineering implementation includes process entry, runtime
bootstrap, startup memory accounting, capacity validation and runtime
invariant work. **Formal M0 qualification has not been declared
complete.**

The original engineering record identifies outstanding authoritative
qualification obligations involving the Qualification Rule Register,
Invariant Register, Limit Register, Effective Limit Manifest, common
diagnostics, and effective configuration/provenance identity. Their
current closure status must be established from the relevant
qualification evidence, not inferred from passing tests.

Functional M1 HTTP development can proceed while earlier formal
qualification obligations remain open. **Implemented, locally tested,
CI-passing and formally milestone-qualified are distinct statuses.**

### Historical M1.5 reconciliation

The historical checkpoint called M1.5 is reconciled into the
controlled milestone structure rather than treated as a separate
authoritative milestone.

Existing reconciliation records include:

- `qualification/checkpoints/CP-LEGACY-M1-5-reconciliation-v0.1.json`
- `qualification/checkpoints/CP-LEGACY-M1-5-reconciliation-v0.2.json`

The repository provides these verification commands:

```bash
make qualify-checkpoint-reconciliation
make qualify-checkpoint-reconciliation-adversarial
```

These checks and records do not themselves constitute formal
milestone closure.

## Repository guide

| Path | Purpose |
| --- | --- |
| `src/http/` | Restricted HTTP handler and response path |
| `src/linux/` | Linux syscall boundaries and socket wrappers |
| `src/platform/` | CPU, time, deadline, memory and platform facilities |
| `src/runtime/` | Runtime bootstrap, accounting, registries and invariants |
| `include/` | Internal ABI, constants and shared structures |
| `tests/qualification/` | NASM-level component and invariant qualifications |
| `tests/integration/` | End-to-end tests using the actual server executable |
| `qualification/` | Qualification records, checkpoints and reconciliation tooling |
| `www/index.html` | Current page served by `GET /` |
| `.github/workflows/ci.yml` | CI build and qualification sequence |
| `Makefile` | Build and test targets |

The Makefile discovers `.asm` files under `src/` and produces the native executable at `build/asmweb`.

## Engineering principles

AsmWeb is guided by a few non-negotiable habits:

1. **Bound resources.** Prefer fixed, documented capacities and explicitly checked arithmetic.
2. **Keep ownership visible.** Know which component acquires, borrows, and releases every descriptor and buffer.
3. **Preserve failure semantics.** Expose kernel errors at the wrapper boundary, then handle them at the appropriate ownership level.
4. **Isolate client failures.** An uncooperative accepted client should not needlessly terminate the listener.
5. **Prove behaviour with real systems.** Use actual sockets, signals and Linux syscalls rather than mock-only success paths.
6. **Require negative controls when practical.** A regression is stronger when it demonstrably rejects the earlier defective implementation.
7. **Measure before claiming.** Small binaries, fast startup, memory savings and throughput improvements are hypotheses until supported by repeatable benchmarks.

The implementation is intentionally explicit. That is part of the exercise, not a claim that assembly automatically yields superior software.

## Development status and next work

**Current development phase: M1 — networking and HTTP robustness.**

Completed and locally verified increments include UDP and TCP loopback primitives; `accept4`; endpoint identity wrappers; nonblocking error cases; fragmented streams and partial writes; signal-driven `EINTR`; persistent-listener survival after client I/O failures; and checked deadline arithmetic.

The next important work is to connect the existing monotonic clock and deadline arithmetic to the HTTP receive loop and prove a **non-resettable request-acquisition deadline**. Acceptance must include a slow client being disconnected at the bounded deadline, the waiting legitimate request subsequently being served, ordinary fragmented requests continuing to work, and descriptor cleanup remaining correct.

Further work includes more complete send-side deadline analysis, explicit protocol limitations, stronger adversarial testing, runtime measurements, and milestone qualification against the project specifications.

**Do not treat a completed arithmetic primitive as a completed HTTP deadline feature.**

## Project intent

AsmWeb is simultaneously a real native-software engineering exercise and an experiment in deliberate constraint. Assembly is the chosen medium because making the resource, ABI, and kernel boundaries explicit is interesting and instructive—not because conventional software development is somehow invalid.

A useful end state would be a very small process that does a narrow job predictably, consumes bounded resources, and has evidence for its claims. Whether that becomes competitive with existing servers is something to **measure**, not assert.

## License and contributions

AsmWeb is open-source software licensed under the **Mozilla Public License, Version 2.0 (MPL-2.0)**. See [LICENSE](LICENSE) for the full licence and [LICENSING.md](LICENSING.md) for its scope.

AsmWeb maintains one common engineering foundation. Future commercial offerings may include:

- **Free:** The open-source AsmWeb Core.
- **Pro:** Additional professional tooling and documentation.
- **OEM:** Device integration, qualification and manufacturer-specific services.
- **Enterprise:** Organisational deployment, assurance and support services.

These commercial offerings are planned, not currently released. The existing MPL-2.0 rights remain independent of any additional commercial agreement.

Issues and reproducible bug reports are welcome through the [GitHub repository](https://github.com/aj5r1gg/asmweb).

Contributions are welcome subject to the project engineering requirements and [contribution guidelines](CONTRIBUTING.md). Please include relevant build and qualification evidence and preserve the project's deliberately limited scope.

---

**AsmWeb:** *Do less. Bound everything. Measure the rest.*
