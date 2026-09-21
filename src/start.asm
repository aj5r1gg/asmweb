bits 64

%include "asmweb/abi.inc"

global _start

extern asm_runtime_main
extern asm_linux_exit

section .text

; _start
;
; Linux x86-64 process-entry boundary.
;
; _start is NOT an ordinary AsmWeb Internal ABI function.
;
; Responsibilities at this stage:
;
;   1. establish required ordinary-call invariants;
;   2. enter the AsmWeb runtime through Internal ABI v1;
;   3. terminate through the controlled Linux syscall boundary.
;
; Future M0 work will add bounded argc/argv/environment/auxv handling
; before ordinary runtime entry.

_start:
    ; Linux x86-64 process entry provides RSP aligned to 16 bytes.
    ;
    ; AsmWeb ordinary calls follow the System V AMD64 convention:
    ;
    ;   immediately before CALL: RSP % 16 == 0
    ;   ordinary callee entry:    RSP % 16 == 8
    ;
    ; CALL itself pushes the 8-byte return address.

    cld

    call asm_runtime_main

    ; asm_runtime_main returns the desired process status in RAX.
    ;
    ; asm_linux_exit receives its first Internal ABI argument in RDI.
    mov edi, eax

    call asm_linux_exit

    ; asm_linux_exit is non-returning.
    ud2
