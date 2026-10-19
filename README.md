# AsmWeb

**Do less. Bound everything. Measure the rest.**

AsmWeb is an experimental, resource-conscious web server and runtime built primarily in **x86-64 assembly** for Linux. Its engineering focus is explicit resource bounds, small executable and memory footprints, predictable failure behaviour, and reproducible measurement—not assembly language for its own sake.

> **Development status — M0 engineering baseline; M1 HTTP implementation in progress.** The executable currently contains an assembly runtime and bootstrap machinery. It **does not yet serve HTTP traffic**. Do not deploy it as a production web server.

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

**Important:** Until M1 HTTP networking is implemented and verified, executing `build/asmweb` does not start an HTTP listener.

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

## Next milestone: first HTTP response

M1 will add the controlled Linux TCP syscall boundary, then a loopback-only, single-connection HTTP/1.1 path with fixed bounded storage and an initial `GET /` route. Acceptance requires a real TCP connection, an exact HTTP response, complete writes, descriptor cleanup, explicit bounded error handling, and preservation of M0 regressions.

## Design principles

Correctness, memory boundedness, computational boundedness, and required interoperability take precedence over speed. Implementation and performance claims require evidence. Unsupported capabilities must not be presented as implemented.

## License

No licence has been selected for this repository. **All rights reserved unless and until a licence is explicitly added.**
