# ADR-001 — Assembler and Initial Linker Toolchain

Status: ACCEPTED

Date: 2026-09-21

Milestone: M0 — Toolchain & Assembly Runtime Foundation

## Context

AsmWeb is primarily implemented in x86-64 assembly on Linux.

The Architecture & Engineering Specification deliberately deferred final selection among NASM, GAS and FASM until implementation work could establish an explicit toolchain decision.

The Assembly Engineering Standard requires the selected assembler to receive an AsmWeb-specific profile and prohibits incidental tool availability from silently resolving the assembler decision.

AsmWeb also requires direct and inspectable ELF construction without unnecessary compiler-runtime or C-runtime machinery.

The initial development environment is Fedora 44 Toolbox on x86-64.

The verified available M0 toolchain is:

- NASM 3.02
- GNU binutils 2.46.1
- GNU Make 4.4.1
- GDB 17.2
- strace 7.2
- perf 7.2.5
- Python 3.14.4

## Decision

AsmWeb SHALL use NASM as the primary assembler for the M0 implementation.

AsmWeb SHALL use GNU ld from binutils as the initial direct linker.

GNU Make SHALL provide the initial build orchestration.

GNU binutils tools including readelf, objdump, objcopy, nm, size, strings and strip SHALL provide initial ELF and binary inspection.

GDB, strace and perf SHALL provide initial debugging, syscall inspection and performance instrumentation.

The initial assembly source syntax SHALL therefore be NASM Intel syntax.

The initial object format SHALL be ELF64.

The initial target SHALL be Linux x86-64.

The normal AsmWeb executable SHALL be linked directly rather than through GCC or another compiler driver unless a later controlled decision requires otherwise.

The initial runtime SHALL NOT depend upon libc, a C runtime, compiler startup objects or a language runtime.

## Rationale

NASM provides a direct x86-oriented assembly environment with explicit Intel syntax and mature ELF64 support.

Its source model is sufficiently low-level for AsmWeb while retaining useful preprocessing, constants, macros and compile-time facilities.

GNU binutils provides mature and widely available ELF linking and inspection tooling.

Using GNU ld directly makes the link boundary explicit and reduces the likelihood that compiler-driver defaults, startup objects or runtime dependencies are introduced accidentally.

This combination supports the AsmWeb objective of making generated machine behaviour and binary structure inspectable.

## Alternatives Considered

### GNU assembler — GAS

GAS is mature and tightly integrated with GNU/Linux tooling.

It remains available for experiments and comparative work.

It was not selected as the primary M0 assembler because AsmWeb does not require compiler-driver integration and NASM provides a more direct assembly-oriented source environment for this project.

### FASM

FASM provides a compact and highly assembly-centric environment.

It was not selected for M0 because NASM combined with GNU binutils provides stronger integration with the initial ELF inspection, debugging and qualification workflow.

## Consequences

AsmWeb SHALL define a NASM-specific Assembler Profile.

Source files SHALL use NASM-compatible syntax unless explicitly classified otherwise.

Build and qualification evidence SHALL record the actual NASM and linker versions used.

The linked executable, rather than source appearance, remains authoritative evidence of executed machine code.

GNU as being installed SHALL NOT make GAS-generated source part of the supported implementation without explicit classification.

The decision does not prevent later measurement or reconsideration of another assembler.

A future change of primary assembler SHALL require a superseding ADR and qualification-impact analysis.

## Initial Toolchain Identity

Development environment:

Fedora Linux 44 Toolbox
Linux x86-64

Assembler:

NASM 3.02

Linker and ELF tools:

GNU binutils 2.46.1

Build orchestration:

GNU Make 4.4.1

Debugging and inspection:

GDB 17.2
strace 7.2
perf 7.2.5

## Qualification Impact

ADR-001 resolves the M0 assembler-selection dependency.

The following remain to be established before M0 closure:

- NASM Assembler Profile
- reproducible build procedure
- linker profile
- ELF hardening profile
- build identity mechanism
- binary dependency inspection
- instruction-baseline inspection
- disassembly qualification mechanism

## Supersession

This ADR remains authoritative until explicitly superseded.

A different assembler or linker SHALL NOT become the production toolchain merely through experimental use.
