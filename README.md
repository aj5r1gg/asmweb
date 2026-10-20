# AsmWeb

**Do less. Bound everything. Measure the rest.**

AsmWeb is an experimental, resource-conscious web server and runtime
built primarily in **NASM x86-64 assembly for Linux**.

The project explores how small, predictable, fast and resource-bounded
a useful native web server can become.

Assembly is the implementation method, not the purpose. The purpose is
to produce useful software with explicit limits, controlled resource
ownership, predictable behaviour and measurable performance.

## Development Status

**Experimental implementation — not production qualified.**

AsmWeb now runs as a native Linux HTTP server and serves an actual HTML
page from disk. The page has been demonstrated in Firefox.

The current implementation:

- Starts a native TCP listener.
- Binds to `127.0.0.1:18080`.
- Accepts successive client connections without restarting.
- Processes client connections sequentially.
- Handles a restricted subset of HTTP/1.1.
- Accepts `GET / HTTP/1.1` with ordinary request headers.
- Requires a Host header and rejects duplicate Host headers.
- Serves `www/index.html` from disk.
- Generates Content-Length from the file's actual byte count.
- Returns basic HTTP error responses.
- Closes each client connection after responding.

The implementation has been demonstrated through direct HTTP requests
and a real Firefox browser session.

This is a functional engineering achievement, not a declaration of
complete HTTP/1.1 compliance, formal milestone closure or production
readiness.

## Quick Start

### Requirements

- Linux on x86-64.
- NASM.
- GNU Make.
- GNU binutils, including the linker.
- A terminal and web browser.

Development has been carried out using Fedora Toolbox.

### Build

From the repository root:

    make all

This produces:

    build/asmweb

### Start the Server

From the repository root:

    ./build/asmweb

The process runs a persistent, sequential HTTP listener.

The current page path is relative to the process working directory.
Start AsmWeb from the repository root so `www/index.html` can be found.

### View the Website

Open a browser on the same machine at:

http://127.0.0.1:18080/

The current demonstration page describes AsmWeb and its engineering
philosophy.

Stop the server using Ctrl+C in its terminal.

### Request From a Terminal

A normal HTTP request can also be made with:

    curl --http1.1 -i http://127.0.0.1:18080/

A successful response for the included page has the structure:

    HTTP/1.1 200 OK
    Content-Type: text/html; charset=utf-8
    Content-Length: 681
    Connection: close

The body contains the HTML document from `www/index.html`.

The byte count shown above is for the currently supplied demonstration
page. Content-Length is constructed from the file contents rather than
being fixed to that example value.

## What AsmWeb Is

AsmWeb is both an experimental web server and the foundation for a
small, resource-conscious native runtime.

It is intended to investigate whether useful server functionality
can be implemented with:

- Explicit memory and request limits.
- Small executable and memory footprints.
- Predictable resource acquisition and cleanup.
- Minimal runtime dependencies.
- Controlled operating-system interfaces.
- Deterministic or bounded failure behaviour wherever established.
- Reproducible performance measurements.

The project does not assume assembly code is automatically faster,
smaller or more efficient. Those are engineering claims to establish
through measurements.

## Current Architecture

AsmWeb uses a native Linux x86-64 executable assembled with NASM and
linked using GNU binutils.

Its implementation includes several cooperating areas.

### Process and Runtime

The runtime includes Linux process entry, bootstrap mechanisms,
registry and capacity validation, startup memory accounting, runtime
invariant checks, and readiness publication.

The existing engineering baseline also includes work on resource
ownership, memory ceilings and runtime invariants.

### Linux Interfaces

The server interfaces with Linux through native syscall boundaries.

Networking is implemented without Apache, Nginx, Node.js or a separate
application-language runtime.

### HTTP Handling

The current HTTP implementation is in:

    src/http/first_response.asm

The production runtime invokes a persistent server entry point.

The older one-shot entry point is retained for existing internal
engineering callers.

The HTTP handling path is intentionally restricted and bounded.
It is not yet a general-purpose HTTP implementation.

### HTML File Serving

The current production server opens:

    www/index.html

It reads the document within its configured size limit, constructs an
HTTP response containing the actual file length, and sends the
response to the connected client.

At present, this is a single-document server, not a general static-file
server.

## Current HTTP Behaviour

The production listener uses:

| Property | Current behaviour |
| --- | --- |
| Network family | IPv4 |
| Bind address | 127.0.0.1 |
| TCP port | 18080 |
| Supported successful request | GET / HTTP/1.1 |
| Request headers | Restricted HTTP/1.1 subset |
| Host header | Required, duplicate rejected |
| Successful content | www/index.html |
| Content type | text/html; charset=utf-8 |
| Connection handling | Sequential |
| Listener lifetime | Persistent |
| Response connection | Closed after response |
| Maximum request buffer | 1,024 bytes |
| Maximum HTML file size | 4,096 bytes |

The file-serving implementation uses fixed-capacity buffers and does
not permit arbitrarily large HTML documents.

Existing responses include successful delivery and basic error
responses. The implementation is not claimed to satisfy every HTTP
protocol error-handling requirement.

## Known Limitations

The current development version has important limitations:

- Only the root document is served.
- HTML files are limited to 4,096 bytes.
- Received request headers are limited to 1,024 bytes.
- Client connections are processed sequentially.
- There is no HTTP connection reuse or pipelining.
- There is no general static-file routing.
- Request bodies and general request framing are not implemented.
- There is no MIME-type selection for multiple file types.
- Full HTTP/1.1 interoperability remains incomplete.
- HTTP/2 and HTTP/3 are not implemented.
- TLS is not implemented.
- The listener is restricted to IPv4 loopback.
- Configuration and deployment interfaces remain experimental.
- A comprehensive total request-processing deadline has not yet been
  established.
- The implementation is not production-ready.

The parser and file-serving code require further hardening before the
server should be exposed to untrusted remote clients.

## Engineering Principles

AsmWeb prioritises:

1. Correctness.
2. Explicit resource boundaries.
3. Controlled ownership and cleanup.
4. Predictable failure behaviour.
5. Required interoperability.
6. Measured performance.

These priorities are deliberate.

An assembly implementation that is smaller or faster but violates
resource limits or behaves unpredictably is not a successful result.

**Do less. Bound everything. Measure the rest.**

## Development Roadmap

The immediate functional direction is:

1. **Working HTTP foundation — demonstrated.**
   Native listening, HTTP responses and sequential persistence.

2. **HTML file serving — demonstrated.**
   Delivery of the root document from disk to Firefox.

3. **General static-file serving — next.**
   Bounded URL routing, multiple files, safe file access and MIME types.

4. **HTTP interoperability.**
   Improve parsing, framing, error handling and connection lifecycle
   without sacrificing bounded resource use.

5. **Configuration and deployment.**
   Move beyond hard-coded development paths and settings.

6. **Performance and memory measurement.**
   Establish actual executable size, resident memory usage, startup
   cost, throughput and latency.

7. **Further protocol capabilities.**
   Progress toward the native HTTP/1.1, HTTP/2 and HTTP/3 architecture
   described in the project specifications.

These are development directions, not claims that all features have
been implemented or formally qualified.

## Build and Verification

The normal production build is:

    make all

The repository also includes engineering regression and qualification
infrastructure.

Selected existing checks include:

    make qualify-production-registry
    make qualify-production-limit-manifest
    make qualify-mot-ceiling-integration
    make qualify-memory-ceiling
    make qualify-runtime-invariant
    make qualify-http-descriptor-lifecycle

Other qualification and adversarial checks are available through the
Makefile and the `tests/` tree.

The GitHub Actions workflow is located at:

    .github/workflows/ci.yml

GitHub Actions runs engineering checks on supported workflow events.

**A green CI run establishes that its executed checks passed. It does
not establish production readiness or formal milestone qualification.**

The HTTP integration checks cover file-backed HTML responses,
persistent sequential connections, request validation and basic error
responses.

GitHub Actions also executes additional runtime, descriptor-lifecycle
and engineering regression checks. The status of each workflow run
must be established from its actual GitHub Actions result.

## Milestone and Qualification Context

AsmWeb uses a controlled M0–M16 milestone baseline.

The M0 engineering implementation includes process entry, runtime
bootstrap, memory accounting, capacity validation and runtime
invariant work.

Formal M0 qualification has not been declared complete.

Outstanding authoritative qualification work has included the
Qualification Rule Register, Invariant Register, Limit Register,
Effective Limit Manifest, common diagnostics, and effective
configuration/provenance identity.

Functional HTTP development can continue while these formal
qualification obligations remain open.

### Historical M1.5 Reconciliation

The historical engineering checkpoint labelled M1.5 is reconciled
against the controlled milestone structure rather than treated as
a separate authoritative milestone.

Existing reconciliation records include:

- `qualification/checkpoints/CP-LEGACY-M1-5-reconciliation-v0.1.json`
- `qualification/checkpoints/CP-LEGACY-M1-5-reconciliation-v0.2.json`

The repository includes reconciliation verification targets:

    make qualify-checkpoint-reconciliation
    make qualify-checkpoint-reconciliation-adversarial

These records and checks do not, by themselves, constitute formal
milestone closure.

## Repository Layout

Important repository paths include:

| Path | Purpose |
| --- | --- |
| `src/` | Native assembly implementation |
| `src/http/` | HTTP server implementation |
| `src/linux/` | Linux syscall and networking interfaces |
| `src/runtime/` | Runtime mechanisms |
| `include/` | NASM includes and interfaces |
| `www/` | Demonstration website |
| `tests/` | Integration and engineering tests |
| `qualification/` | Qualification records and tooling |
| `.github/workflows/` | GitHub Actions CI |
| `build/` | Generated executable and build artifacts |
| `Makefile` | Build and verification targets |

The repository contains substantially more runtime and qualification
work than the small HTML demonstration alone illustrates.

## Intended Direction

AsmWeb is not being developed merely to demonstrate that assembly
can respond to an HTTP request.

The larger objective is a useful native web server with deliberately
small and measurable resource requirements.

The immediate priority is working functionality:

- Serve multiple useful assets.
- Improve interoperability.
- Retain explicit limits.
- Keep the implementation understandable.
- Measure actual performance.
- Harden what has been implemented.

Formal verification and qualification remain important, but should
support implementation rather than replace it.

## License

No licence has been selected for this repository.

**All rights reserved unless and until a licence is explicitly added.**
