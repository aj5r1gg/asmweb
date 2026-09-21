bits 64

%include "asmweb/abi.inc"

global asm_runtime_main

extern asm_abi_probe

section .text

; asm_runtime_main
;
; Purpose:
;   Initial ordinary AsmWeb runtime entry point.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Result:
;   RAX = process status.
;
; Current M0 responsibility:
;   Qualify the initial Internal ABI contract.
;
; Exit status:
;   0 = ABI probe passed.
;   1 = ABI probe failed.
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

    ; Preserve the Internal ABI callee-saved register set used
    ; by this qualification routine.
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Entry is RSP % 16 == 8.
    ; Six pushes consume 48 bytes and preserve that modulus.
    ; Reserve another 8 bytes so RSP is 16-byte aligned
    ; immediately before the ordinary call below.
    sub rsp, 8

    ; Seed callee-saved registers with known values.
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
    ; Release call-alignment reservation.
    add rsp, 8

    ; Restore this function's caller-visible callee-saved state.
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ret
