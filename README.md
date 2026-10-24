# AsmWeb

**A deliberately small, resource-bounded web server written in native x86-64 assembly for Linux.**

> **Do less. Bound everything. Measure the rest.**

AsmWeb explores a simple engineering question: how much useful web-serving infrastructure can be built directly in assembly, with explicit ownership, bounded memory, predictable failure handling, and tests that exercise real Linux kernel behaviour?

The purpose is **not** to claim that assembly is inherently faster, more secure, or a better choice than established web servers. It is to construct a narrowly scoped server whose behaviour can be understood, measured, and challenged at the syscall, runtime, and HTTP levels.

**Current status (24 October 2026): M0 foundation owner-approved; M1 development under way.**

M0 has passed its closure eligibility audit with **zero outstanding blockers**. Its 36 mandatory invariant records have verified owner-signed normative adoption; six additional foundation candidates are deferred under signed scope decisions. The five explicitly identified M0 requirements have owner-signed ownership adoption. The project owner has explicitly approved moving beyond M0. The last observed repository `close` command reported `ELIGIBLE_PENDING_OWNER_APPROVAL`; this README records the subsequent owner decision, **not** an independently verified final publication flag.

AsmWeb is already a functioning **experimental**, loopback-only HTTP/1.1 server, with a small multi-page static website and tested TCP/UDP primitives. **M0 completion does not make M1 or the server production-ready.**

### Milestone status

| Milestone | Status | Interpretation |
| --- | --- | --- |
| **M0 — Foundation** | **Owner-approved (24 October 2026)** | Zero closure blockers; all 36 M0-required invariants adopted. See closure-publication distinction below. |
| **M1 — Networking and I/O** | **In progress** | Networking qualifications pass; full M1 acceptance and closure are not asserted. |
| **Later milestones** | **Planned / not qualified here** | Their scope and acceptance are governed by the milestone specifications, not this README. |

**Closure-publication distinction:** On 24 October 2026 the owner explicitly approved M0 after the gate returned `M0_BLOCKING_CATEGORIES=0` and `M0_CLOSURE_ELIGIBLE=True`. The most recently observed repository `close` output was `M0_CLOSURE_GATE=ELIGIBLE_PENDING_OWNER_APPROVAL`, recorded *before* that explicit owner decision. This README documents the decision but does **not** assert that a subsequent machine-readable final-closure publication was executed or committed. When it is, cite the exact closure commit here; do not infer it from the README.


## Quick start

### Requirements

- Linux on x86-64
- NASM
- GNU make and GNU ld (binutils)
- Git
- Python 3 and GNU `timeout` for selected development checks

**Supported development platform:** Linux **x86-64** only. The code depends on the Linux syscall ABI and NASM x86-64 assembly. Windows, macOS, ARM/AArch64, other operating systems and other CPU architectures are **not supported or qualified** by the current implementation.

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

Run the current time, deadline and **complete 14-target M1 networking qualification sequence**:

```bash
make qualify-time qualify-deadline
make \
  qualify-udp-loopback \
  qualify-tcp-accept4 \
  qualify-network-error-paths \
  qualify-stream-fragments \
  qualify-stream-short-write \
  qualify-network-eintr \
  qualify-udp-batch-transfer \
  qualify-udp-batch-bounds \
  qualify-udp-batch-mutations \
  qualify-udp-checked-descriptors \
  qualify-udp-checked-transfer \
  qualify-udp-checked-mutations \
  qualify-http-descriptor-lifecycle \
  qualify-http-descriptor-mutations
```

The 14 M1 targets above passed in the recorded local run on 24 October 2026. A passing development run does not imply formal M1 closure.

`make qualify-deadline` currently tests **15 arithmetic boundary cases**, including exact expiry, overflow, backward time samples, sub-microsecond positive intervals, register preservation, and buffer guards. The deadline qualification was also repeated successfully across 20 local executions before publication.

`make qualify-network-eintr` installs a real signal handler, uses a kernel timer to interrupt a blocking receive, verifies that `-EINTR` is returned, and checks buffer integrity, socket reuse and descriptor cleanup.

The `http_idle_survival.py` regression verifies that an incomplete, idle client does **not** terminate the persistent listener and that a subsequent valid client receives HTTP 200. Its sensitivity was checked against both an original vulnerable server (expected failure) and the corrected server (expected success).

The HTTP descriptor mutation qualification deliberately changes cleanup behaviour and verifies that the lifecycle tests reject those mutations.

### Continuous integration

GitHub Actions runs the project build and registered qualification targets. See [the CI workflow](.github/workflows/ci.yml) for the authoritative current command list.


## M0 foundation — completed owner decision

**M0 scope:** the native Linux x86-64 entry and runtime foundation, resource-accounting and capacity machinery, bounded memory classes, canonical production limits and configuration, diagnostic and invariant enforcement, and their controlled qualification evidence. M0 is *not* a claim of full HTTP protocol implementation, operational hardening, or benchmark superiority.

### Verified M0 results

| Obligation | Result |
| --- | --- |
| M0 closure eligibility | `M0_BLOCKING_CATEGORIES=0`, `M0_CLOSURE_ELIGIBLE=True` |
| Closure-gate command | `M0_CLOSURE_GATE=ELIGIBLE_PENDING_OWNER_APPROVAL` before final owner decision |
| Owner decision | **Approved**, 24 October 2026 |
| M0 normative invariants | **36/36** owner-signed, signature-verified and mapped to executable qualification targets |
| Scope decisions | 42 assessed candidates: 36 mandatory, six deferred under signed decisions |
| Normative register inventory | 144 controlled invariant identities; 102 outside the assessed M0 candidate set |
| M0 explicit requirement ownership | Five `REQ-M0-001`–`REQ-M0-005` owner-signed assignments |
| Approval authority and publication | Verified by the final zero-blocker closure audit |
| Production limit configuration | Nine canonical M0 production memory/capacity entries and effective configuration evidence |

**Important scope qualification:** `AUTHORITATIVE_IR_COMPLETE=False` refers to the complete 144-invariant cross-milestone register, not the signed set of 36 M0-required invariants. It must not be presented as a claim that all 144 statements are approved. The M0 closure gate nevertheless reported zero M0 blockers.

The final M0 engineering commits include:

- `1615f03` — 36/36 executable invariant evidence links.
- `e7dd3a5` — owner-signed normative adoption of all 36 M0-required invariants.
- `62ae1b2` — retirement of the resolved M0 IR blocker.
- `9e25329` — signed M0 requirement ownership, authority and approval; zero blocker audit.

Those identities describe a recorded engineering checkpoint, not an assertion that later source changes automatically inherit the same qualification. Re-run the relevant qualifications after changes to foundation code or its controlled evidence.

Verify the M0 foundation on a development host:

```bash
make -j2 all
make qualify-m0-invariant-scope
python3 -B qualification/tools/m0_normative_ir.py verify
python3 -B qualification/tools/m0_closure_gate.py audit
python3 -B qualification/tools/m0_closure_gate.py close
```

The final `close` command may report an owner-approval publication state separately from its zero-blocker eligibility calculation. The owner decision is documented here; the underlying signed records and gate output remain the authority for machine-readable status.

### What M0 does *not* imply

M0 owner approval does not establish full production security assurance, an externally audited release, full HTTP/1.1 compliance, HTTP/2, HTTP/3, TLS, concurrent connection handling or general-purpose hosting. Those capabilities require separate implementation and qualification.

## M1 — current development milestone

M1 work concentrates on TCP/UDP and stream-I/O foundations alongside the experimental HTTP serving path. Verified local qualifications include loopback TCP/UDP, `accept4`, network error propagation, stream fragmentation and short writes, signal interruption, bounded and checked UDP batch operations, and HTTP descriptor lifecycle and mutation checks. These passing tests are **engineering evidence**, not a declaration that M1 is closed.

The full 14-target M1 command is maintained once under [Build and qualification](#build-and-qualification), avoiding divergent test lists.

These targets passed in the recorded local run. NASM emitted nonfatal relative-relocation warnings for some fixtures; those warnings should not be mistaken for compilation failures or ignored as an unconditional portability guarantee.

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

**Current phase: M1 — networking and HTTP development. M0 owner-approved.**

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

M1 milestone qualification remains separate from
engineering commits and feature completion.

## Performance benchmarking — baseline not yet established

AsmWeb's performance against established servers, including Nginx, is an **open measurement question**. There is currently **no verified comparative benchmark baseline** in this README and no claim that AsmWeb is faster, smaller in total deployed footprint, or more efficient under equivalent production workloads.

Future comparisons should publish the tested AsmWeb and comparator versions, hardware, operating system, toolchain, network topology, request/response sizes, connection concurrency, measurement commands, raw samples and repeatability conditions. At minimum measure:

| Metric | Required reporting |
| --- | --- |
| Throughput | Requests/second and bytes/second at matched workloads |
| Latency | Median, p95 and p99 response latency, including under concurrency |
| Memory | Idle and peak resident set size (RSS), with workload and observation method |
| Executable size | On-disk binary bytes, separate from RSS and total deployment size |
| CPU usage | CPU time and utilisation at matched delivered throughput |

Do not compare AsmWeb's current loopback-only, sequential, fixed-route HTTP prototype with a differently configured, feature-complete server as if the results represented equivalent products. Report any disabled features, workload limitations and measurement uncertainty.

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
