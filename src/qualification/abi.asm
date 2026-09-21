bits 64

%include "asmweb/abi.inc"

global asm_abi_probe

section .text

; asm_abi_probe
;
; Purpose:
;   Exercise observable AsmWeb Internal ABI v1 behaviour.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Input:
;   RDI = 0x11
;   RSI = 0x22
;   RDX = 0x33
;   RCX = 0x44
;   R8  = 0x55
;   R9  = 0x66
;
; Result:
;   RAX = 0x123456789abcdef0 on success.
;   RAX = 0 on failure.
;
; Callee-saved:
;   Preserved.
;
; Direction flag:
;   Cleared before return.

asm_abi_probe:
    ; Ordinary callee entry shall observe:
    ;
    ;   RSP % 16 == 8
    ;
    mov rax, rsp
    and eax, 15
    cmp eax, 8
    jne .failure

    cmp rdi, 0x11
    jne .failure

    cmp rsi, 0x22
    jne .failure

    cmp rdx, 0x33
    jne .failure

    cmp rcx, 0x44
    jne .failure

    cmp r8, 0x55
    jne .failure

    cmp r9, 0x66
    jne .failure

    cld

    mov rax, 0x123456789abcdef0
    ret

.failure:
    cld
    xor eax, eax
    ret
