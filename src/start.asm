bits 64

global _start
extern asm_linux_exit

section .text

_start:
    xor edi, edi
    call asm_linux_exit

    ; asm_linux_exit is non-returning.
    ud2
