# AsmWeb

**A deliberately small, resource-bounded web server written in native x86-64 assembly for Linux.**

> **Do less. Bound everything. Measure the rest.**

AsmWeb explores a simple engineering question: how much useful web-serving infrastructure can be built directly in assembly, with explicit ownership, bounded memory, predictable failure handling, and tests that exercise real Linux kernel behaviour?

The purpose is **not** to claim that assembly is inherently faster, more secure, or a better choice than established web servers. It is to construct a narrowly scoped server whose behaviour can be understood, measured, and challenged at the syscall, runtime, and HTTP levels.

**Current status:** Experimental M1 development. AsmWeb is a
working Linux x86-64 assembly web server with a persistent,
loopback-only HTTP listener, a small multi-page static website,
bounded request acquisition, and TCP/UDP networking primitives.

AsmWeb is **not yet production-ready** or formally
milestone-qualified.

## Quick start

### Requirements

- Linux on x86-64
- NASM
- GNU make and GNU ld (binutils)
- Git
- Python 3 and GNU `timeout` for selected development checks

AsmWeb builds without requiring a C compiler.

```bash
git clone https://github.com/aj5r1gg/asmweb.git
cd asmweb
make -j2 all
./build/asmweb
```

Leave the server running. Open Firefox at:

**http://127.0.0.1:18080/**

Or use another terminal:

```bash
curl --noproxy '*' -i http://127.0.0.1:18080/
curl --noproxy '*' -i http://127.0.0.1:18080/about.html
```

Stop AsmWeb with **Ctrl+C**.

The server currently listens on **127.0.0.1:18080**.
Run it from the repository root because the website files
are resolved relative to the working directory.

## What works today

### HTTP serving

AsmWeb currently implements:

- A persistent, sequential TCP listener on IPv4 loopback.
- Restricted HTTP/1.1 `GET` request processing.
- Bounded request headers, with a 1,024-byte buffer.
- A three-second absolute request-acquisition deadline.
- Request-header handling across multiple socket reads.
- A required single `Host` header.
- Explicit `Content-Length` responses.
- Partial-write handling and connection cleanup.
- Static-file responses with a 4,096-byte per-file capacity.
- Fixed-path routing and URL query-string handling.
- HTTP responses including 200, 400, 404, 431 and 500.

The current website contains:

| URL | File | Content type |
| --- | --- | --- |
| `/` | `www/index.html` | HTML |
| `/about.html` | `www/about.html` | HTML |
| `/style.css` | `www/style.css` | CSS |
| `/favicon.ico` | `www/favicon.ico` | Icon |

Query parameters are separated from the resource path.
For example, `/?utm_source=chatgpt.com` resolves to the
home-page resource.

**Current limitations:** This is not a complete HTTP/1.1
implementation. Arbitrary filesystem routing, dynamic content,
request bodies, keep-alive, pipelining, TLS and virtual hosting
are not implemented.

The route table is deliberately fixed. Unknown paths return 404.

### Linux networking primitives

The codebase exposes small wrappers for Linux socket operations, including socket creation, bind, listen, accept, `accept4`, receive, send, datagram send/receive, socket options, socket identity queries, and close.

Wrappers follow the project's internal calling convention and expose **raw Linux syscall results** rather than silently retrying operations or translating errors. Newly acquired descriptors are owned by the caller; operations that inspect or use a descriptor borrow it; close consumes it.

The networking layer also provides native `recvmmsg`
and `sendmmsg` wrappers, together with bounded entry points
using a provisional maximum of **16 datagrams per batch**.

These are networking primitives, not yet a complete
application-level UDP transport.

The networking test suite exercises actual sockets and syscalls, including TCP and UDP loopback, stream fragmentation, nonblocking short writes, truncation and error paths, descriptor cleanup, and signal-driven `EINTR`.

### Runtime and resource controls

AsmWeb has a substantial runtime foundation alongside the HTTP prototype. The repository includes platform, runtime, memory, process-entry, invariant, registry, and qualification modules.

The existing monotonic-clock routine obtains `CLOCK_MONOTONIC`, validates the sample, and converts it to an overflow-checked unsigned nanosecond representation. A separate **deadline arithmetic** module computes remaining time and a positive Linux `timeval`, with explicit active, expired, and invalid results.

The HTTP receive loop now uses monotonic-clock sampling
and deadline arithmetic to enforce a non-resetting
three-second request-acquisition budget.

This is implemented functionality. It does not imply
complete HTTP protocol conformance or production readiness.

## Explicit limits and current boundaries

| Area | Current boundary |
| --- | --- |
| Platform | Linux x86-64 |
| Listener | 127.0.0.1:18080 |
| Concurrency | One accepted client at a time |
| HTTP method | Restricted GET |
| Routes | Four explicitly recognised resources |
| Request-header capacity | 1,024 bytes |
| Static-file capacity | 4,096 bytes per resource |
| Request-acquisition deadline | 3 seconds |
| Socket send timeout | 3 seconds |
| UDP batch size | Provisional maximum of 16 |
| TLS | Not implemented |
| Dynamic content | Not implemented |
| Keep-alive and pipelining | Not implemented |
| Deployment status | Experimental, local development |

These are implementation boundaries, not a declaration
of production readiness or formal milestone closure.

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
make qualify-udp-batch-transfer
make qualify-udp-batch-bounds
make qualify-udp-batch-mutations
make qualify-http-descriptor-lifecycle
make qualify-http-descriptor-mutations
```

`make qualify-deadline` currently tests **15 arithmetic boundary cases**, including exact expiry, overflow, backward time samples, sub-microsecond positive intervals, register preservation, and buffer guards. The deadline qualification was also repeated successfully across 20 local executions before publication.

`make qualify-network-eintr` installs a real signal handler, uses a kernel timer to interrupt a blocking receive, verifies that `-EINTR` is returned, and checks buffer integrity, socket reuse and descriptor cleanup.

The `http_idle_survival.py` regression verifies that an incomplete, idle client does **not** terminate the persistent listener and that a subsequent valid client receives HTTP 200. Its sensitivity was checked against both an original vulnerable server (expected failure) and the corrected server (expected success).

The HTTP descriptor mutation qualification deliberately changes cleanup behaviour and verifies that the lifecycle tests reject those mutations.

### Continuous integration

GitHub Actions runs the project build and registered qualification targets. See [the CI workflow](.github/workflows/ci.yml) for the authoritative current command list.


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
| `www/` | HTML pages, CSS and favicon served by AsmWeb |
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

**Current phase: M1 — networking and HTTP development.**

Implemented engineering checkpoints include:

- Linux TCP/UDP networking primitives.
- Bounded UDP batch send and receive operations.
- A persistent HTTP listener.
- An absolute HTTP request-acquisition deadline.
- Multi-page static website serving.
- Query-string handling for recognised paths.

The application has been demonstrated in Firefox and through
real HTTP requests.

The next application-oriented objective is **general-purpose,
bounded static-file serving**, avoiding the need to hardcode
each website resource into the assembly source.

Development follows a practical cycle:

**Implement → demonstrate → verify sufficiently → commit → advance.**

Tests and specifications support application delivery.
They are not substitutes for it.

Formal milestone qualification remains separate from
engineering commits and feature completion.

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
