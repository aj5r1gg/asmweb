# AsmWeb

**Do less. Bound everything. Measure the rest.**

AsmWeb is an experimental, resource-conscious web server and runtime built primarily in **x86-64 assembly** for Linux. Its engineering focus is explicit resource bounds, small executable and memory footprints, predictable failure behaviour, and reproducible measurement—not assembly language for its own sake.

> **Development status — experimental engineering implementation, not production qualified.** AsmWeb currently serves a restricted HTTP/1.1 response on `127.0.0.1:18080`, accepting one connection per process. Only two exact `GET / HTTP/1.1` request representations are accepted, with `Host: localhost` or `Host: 127.0.0.1`. General HTTP parsing, persistence, TLS, HTTP/2 and HTTP/3 are not implemented. No M0–M16 milestone is formally closed by this experimental HTTP implementation. Do not deploy it as a production web server.

## Project goals

- Keep memory, connection, request, and other resource consumption explicitly bounded.
- Establish ownership, lifetime, cleanup, and failure contracts.
- Minimise dependencies and startup overhead while preserving correctness.
- Measure performance rather than infer it from the implementation language.
- Develop native HTTP/1.1, HTTP/2, and HTTP/3 support progressively, with a shared semantic HTTP core, as specified by the project architecture. **These protocols are targets, not current capabilities.**
- Qualify claims through reproducible tests and adversarial evidence.

## Current state

The M0 engineering baseline includes Linux x86-64 process entry, runtime bootstrap, registry and capacity validation, startup memory accounting, runtime invariant checks, and readiness publication. NASM include dependency tracking has been added to the build.

The last verified M0 baseline commit reported in the development handover is `93ada42625683f1a9b6d475dce968bf90d56a443` (19 October 2026). That baseline is **not a declaration of formal M0 qualification**.

Formal M0 qualification remains blocked on completion of the authoritative Qualification Rule Register, Invariant Register, Limit Register, Effective Limit Manifest, common diagnostics, and effective configuration/provenance identity. These obligations remain open while M1 functional implementation proceeds.

## Build

Development environment: Linux x86-64, NASM, GNU Make, and GNU binutils. The project has been developed in a Fedora Toolbox environment.

```sh
make all
```

The resulting executable is expected at `build/asmweb`.

**Important:** Running `build/asmweb` starts the experimental loopback-only HTTP listener on TCP port `18080`. The process accepts one connection and then exits. It is not a general-purpose or production-qualified HTTP server.

## Verification

Run the existing M0 engineering regression targets:

```sh
make qualify-production-registry
make qualify-production-limit-manifest
make qualify-mot-ceiling-integration
make qualify-memory-ceiling
make qualify-runtime-invariant
make all
```

GitHub Actions runs these same engineering checks on pushes and pull requests. A green CI workflow indicates that its **listed tests passed on that runner**; it does **not** mean formal M0 qualification, complete specification compliance, or production readiness.

## Milestone reconciliation

The historical engineering checkpoint labelled `M1.5` is being reconciled with the controlled M0–M16 baseline defined by ASM-MIL-001 v0.3.

The draft reconciliation records are:

- `qualification/checkpoints/CP-LEGACY-M1-5-reconciliation-v0.1.json`
- `qualification/checkpoints/CP-LEGACY-M1-5-reconciliation-v0.2.json`

They map the existing network, resource and restricted HTTP engineering contributions to proposed M0, M1, M2 and M4 allocations. These allocations are not formal qualification determinations or milestone closures.

The production listener is restricted to IPv4 loopback, and the current implementation has no established total request-processing deadline. Successful CI establishes only the listed engineering test results.

Verify the reconciliation with:

```sh
make qualify-checkpoint-reconciliation
make qualify-checkpoint-reconciliation-adversarial
```

Further engineering work will follow the governed milestone allocations and product boundaries rather than treating the historical M1.5 label as a new baseline milestone.

## Design principles

Correctness, memory boundedness, computational boundedness, and required interoperability take precedence over speed. Implementation and performance claims require evidence. Unsupported capabilities must not be presented as implemented.

## License

No licence has been selected for this repository. **All rights reserved unless and until a licence is explicitly added.**

<!-- ASMWEB-WEBSITE-START -->

## Working HTTP Server

AsmWeb is an experimental native x86-64 Linux web server
written in NASM assembly.

The current implementation supports:

- IPv4 loopback listening at `127.0.0.1:18080`.
- Persistent sequential client acceptance.
- `GET / HTTP/1.1` requests with ordinary HTTP headers.
- Required and nonduplicate Host headers.
- Serving `www/index.html` directly from disk.
- Dynamic Content-Length calculation.
- Connection closure after each response.
- Basic HTTP error responses.

### Build and Run

From the repository root:

    make all
    ./build/asmweb

Open a browser at:

http://127.0.0.1:18080/

Press Ctrl+C to stop the server.

The document path is currently relative to the working directory.

### Current Limitations

- Only `www/index.html` is served.
- Maximum HTML file size: 4,096 bytes.
- Maximum received request headers: 1,024 bytes.
- Sequential connections only.
- No HTTP keep-alive or pipelining.
- No request-body support.
- No general static-file routing.
- IPv4 loopback only.
- Not yet production-ready.

### Design Philosophy

**Do less. Bound everything. Measure the rest.**

<!-- ASMWEB-WEBSITE-END -->
