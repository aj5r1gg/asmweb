# AsmWeb — NASM Assembler Profile v0.1

Status: M0 INITIAL BASELINE

Governing ADR: ADR-001 — Assembler and Initial Linker Toolchain

Target: Linux x86-64

Object format: ELF64

Assembler: NASM

## Purpose

This profile defines the initial NASM-specific implementation conventions for AsmWeb.

It translates the assembler-independent requirements of the Assembly Engineering Standard into concrete NASM source and build behaviour.

This profile is intentionally small.

It SHALL expand only when implementation requires additional assembler-specific rules.

## Source Format

AsmWeb assembly source files SHALL use NASM syntax.

Source files SHALL use the `.asm` suffix.

Shared NASM include files SHALL use the `.inc` suffix.

The target object format SHALL be:

elf64

## Architecture

The initial architecture SHALL be x86-64.

Source intended for the normal runtime SHALL declare:

bits 64

where required for clarity or independent assembly.

AsmWeb SHALL NOT rely on assembler behaviour intended for 16-bit or 32-bit execution modes.

## Sections

Executable instructions SHALL normally reside in:

.text

Read-only constants SHALL normally reside in:

.rodata

Mutable initialised data SHALL normally reside in:

.data

Zero-initialised storage SHALL normally reside in:

.bss

Executable and writable state SHALL remain separate.

## Symbols

Externally visible symbols SHALL be declared explicitly using `global`.

External symbols SHALL be declared explicitly using `extern`.

Internal symbols SHALL remain non-global unless visibility is required.

Unexpected external dependencies SHALL fail build or qualification inspection.

## Position Independence

Source SHALL NOT gratuitously depend on fixed load addresses.

RIP-relative addressing SHALL be preferred for static program data where appropriate.

The final executable hardening and PIE policy remains subject to the Build/Toolchain specification and qualification.

## Includes

Project-local includes SHALL reside beneath:

include/

The build SHALL provide the include search path explicitly.

Includes SHALL NOT silently depend upon the current working directory beyond the defined project build invocation.

## Constants

Protocol, syscall, ABI and project constants SHALL use named definitions.

Unexplained numeric constants SHOULD NOT appear repeatedly in source.

Constants derived from authoritative registries or generated sources SHALL preserve provenance.

## Macros

Macros SHALL be used only where they improve clarity, consistency or verifiability.

Macros SHALL NOT hide:

- resource acquisition;
- ownership transfer;
- blocking;
- syscalls;
- significant control flow;
- externally influenced bounds;
- error handling.

A macro SHALL NOT silently introduce behaviour that would be material to function contracts.

## Structure Layout

Runtime structure offsets, sizes and alignments SHALL eventually originate from one authoritative definition or be mechanically cross-validated against it.

Magic structure offsets are prohibited.

NASM compile-time assertions SHOULD verify critical size and offset relationships.

## Diagnostics

Assembly warnings SHALL be treated seriously.

The qualification profile SHALL ultimately define which NASM diagnostics are fatal.

The initial M0 build SHALL enable broad warning reporting.

## Debug Information

Development and qualification builds MAY emit debug information.

Debug information SHALL NOT define runtime semantics.

Release artefacts SHALL remain attributable to their source and build identity even if symbols are separated or stripped.

## Listing Files

NASM listing files MAY be generated for qualification and inspection.

Listing files are generated artefacts and SHALL NOT be treated as authoritative source.

## Build Identity

Qualification and release evidence SHALL identify the exact NASM version used.

The initial M0 baseline is:

NASM 3.02

Tool versions SHALL NOT be assumed stable merely because command names are stable.

## Output Authority

The linked executable is the authoritative representation of executed machine code.

Source review SHALL therefore be supplemented by binary and disassembly inspection where required.

## Deferred Items

This profile does not yet freeze:

- full macro conventions;
- generated-constant mechanism;
- complete structure-definition mechanism;
- debug-information format;
- production warning policy;
- PIE policy;
- linker script policy;
- optimisation-specific NASM features.

These SHALL be introduced through controlled M0 implementation work.
