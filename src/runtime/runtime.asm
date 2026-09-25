bits 64

%include "asmweb/abi.inc"
%include "asmweb/startup.inc"
%include "asmweb/entropy.inc"
%include "asmweb/cpu.inc"
%include "asmweb/time.inc"

global asm_runtime_main

extern asm_abi_probe
extern asm_entropy_bootstrap
extern asm_cpu_discover
extern asm_monotonic_now

section .text

; asm_runtime_main
;
; Purpose:
;   Initial ordinary AsmWeb runtime entry point.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Input:
;   RDI = pointer to validated ASMWEB_STARTUP_INFO
;   RSI = pointer to writable ASMWEB_ENTROPY_BOOTSTRAP
;   RDX = pointer to writable ASMWEB_CPU_INFO
;   RCX = pointer to writable ASMWEB_MONOTONIC_TIME
;
; Result:
;   RAX = process status.
;
; Current M0 responsibilities:
;
;   - accept controlled startup state explicitly;
;   - verify required startup fields are present;
;   - qualify the initial Internal ABI contract.
;
; Exit status:
;   0 = runtime bootstrap and ABI probe passed.
;   1 = runtime bootstrap or ABI probe failed.
;
; Callee-saved registers:
;   RBX RBP R12 R13 R14 R15 preserved.
;
; Stack:
;   Ordinary callee entry:
;       RSP % 16 == 8
;
;   Six 8-byte callee-saved pushes:
;       RSP % 16 == 8
;
;   Additional 8-byte alignment adjustment:
;       RSP % 16 == 0 before CALL.

asm_runtime_main:
    cld

    ; -----------------------------------------------------------------------
    ; Validate explicit controlled startup state.
    ; -----------------------------------------------------------------------

    test rdi, rdi
    jz .early_failure

    test rsi, rsi
    jz .early_failure

    test rdx, rdx
    jz .early_failure

    test rcx, rcx
    jz .early_failure

    cmp qword [rdi + ASMWEB_STARTUP_INFO.page_size], 0
    je .early_failure

    cmp qword [rdi + ASMWEB_STARTUP_INFO.at_random], 0
    je .early_failure

    ; -----------------------------------------------------------------------
    ; Preserve the Internal ABI callee-saved register set used by this
    ; qualification routine.
    ; -----------------------------------------------------------------------

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Entry is RSP % 16 == 8.
    ; Six pushes consume 48 bytes and preserve that modulus.
    ; Reserve another 8 bytes so RSP is 16-byte aligned
    ; immediately before ordinary calls below.
    sub rsp, 8

    ; Preserve explicit bootstrap-state pointers in callee-saved registers.
    mov rbx, rdi
    mov rbp, rsi
    mov r12, rdx
    mov r13, rcx

    ; -----------------------------------------------------------------------
    ; Transfer Linux AT_RANDOM material into AsmWeb-owned state.
    ; -----------------------------------------------------------------------

    mov rdi, rbx
    mov rsi, rbp
    call asm_entropy_bootstrap

    test eax, eax
    jnz .failure

    cmp qword [rbp + ASMWEB_ENTROPY_BOOTSTRAP.ready], 1
    jne .failure

    ; The raw borrowed AT_RANDOM pointer must be invalidated after transfer.
    cmp qword [rbx + ASMWEB_STARTUP_INFO.at_random], 0
    jne .failure

    ; -----------------------------------------------------------------------
    ; Discover CPU feature state once into AsmWeb-owned storage.
    ; -----------------------------------------------------------------------

    mov rdi, r12
    call asm_cpu_discover

    test eax, eax
    jnz .failure

    cmp qword [r12 + ASMWEB_CPU_INFO.ready], 1
    jne .failure

    ; M0 x86-64 baseline requires SSE2.
    bt qword [r12 + ASMWEB_CPU_INFO.features], ASMWEB_CPU_FEATURE_SSE2
    jnc .failure

    ; -----------------------------------------------------------------------
    ; Establish one controlled CLOCK_MONOTONIC bootstrap sample.
    ; -----------------------------------------------------------------------

    mov rdi, r13
    call asm_monotonic_now

    test eax, eax
    jnz .failure

    cmp qword [r13 + ASMWEB_MONOTONIC_TIME.ready], 1
    jne .failure

    cmp qword [r13 + ASMWEB_MONOTONIC_TIME.nsec], ASMWEB_NSEC_PER_SEC
    jae .failure

    ; Seed callee-saved registers with known values for the ABI probe.
    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    ; Six Internal ABI arguments.
    mov edi, 0x11
    mov esi, 0x22
    mov edx, 0x33
    mov ecx, 0x44
    mov r8d, 0x55
    mov r9d, 0x66

    call asm_abi_probe

    ; Verify primary result.
    mov r10, 0x123456789abcdef0
    cmp rax, r10
    jne .failure

    ; Verify the called routine preserved callee-saved registers.
    cmp rbx, 0x11111111
    jne .failure

    cmp rbp, 0x22222222
    jne .failure

    cmp r12, 0x33333333
    jne .failure

    cmp r13, 0x44444444
    jne .failure

    cmp r14, 0x55555555
    jne .failure

    cmp r15, 0x66666666
    jne .failure

    ; Verify DF is clear.
    pushfq
    pop r10
    test r10, 1 << 10
    jnz .failure

    xor eax, eax
    jmp .restore

.failure:
    cld
    mov eax, 1

.restore:
    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ret

.early_failure:
    cld
    mov eax, 1
    ret
