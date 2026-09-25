bits 64

%include "asmweb/abi.inc"
%include "asmweb/startup.inc"
%include "asmweb/entropy.inc"
%include "asmweb/cpu.inc"

global _start

extern asm_linux_parse_process_entry
extern asm_runtime_main
extern asm_linux_exit

section .bss

align 8
startup_info:
    resb ASMWEB_STARTUP_INFO_size

align 8
entropy_bootstrap:
    resb ASMWEB_ENTROPY_BOOTSTRAP_size

align 8
cpu_info:
    resb ASMWEB_CPU_INFO_size

section .text

; _start
;
; Linux x86-64 process-entry boundary.
;
; _start is NOT an ordinary AsmWeb Internal ABI function.
;
; Responsibilities:
;
;   1. preserve the original Linux process-entry stack pointer;
;   2. establish ordinary-call invariants;
;   3. parse Linux process-entry state through the controlled boundary;
;   4. enter the AsmWeb runtime through Internal ABI v1;
;   5. terminate through the controlled Linux syscall boundary.

_start:
    ; Linux provides the initial stack pointer here.
    mov r12, rsp

    cld

    ; -----------------------------------------------------------------------
    ; Parse controlled startup state.
    ;
    ; RDI = original process-entry stack
    ; RSI = startup_info
    ; -----------------------------------------------------------------------

    mov rdi, r12
    lea rsi, [rel startup_info]

    call asm_linux_parse_process_entry

    test eax, eax
    jnz .startup_failure

    ; -----------------------------------------------------------------------
    ; Enter ordinary AsmWeb runtime.
    ;
    ; RDI = pointer to validated controlled startup state.
    ; RSI = pointer to AsmWeb-owned entropy bootstrap state.
    ; RDX = pointer to AsmWeb-owned CPU discovery state.
    ; -----------------------------------------------------------------------

    lea rdi, [rel startup_info]
    lea rsi, [rel entropy_bootstrap]
    lea rdx, [rel cpu_info]
    call asm_runtime_main

    mov edi, eax
    call asm_linux_exit

    ud2

.startup_failure:
    mov edi, 2
    call asm_linux_exit

    ud2
