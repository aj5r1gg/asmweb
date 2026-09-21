bits 64

%include "linux/syscall.inc"

global asm_linux_exit

section .text

; asm_linux_exit
;
; Purpose:
;   Terminate the process through the Linux x86-64 syscall ABI.
;
; AsmWeb Internal ABI input:
;   RDI = process exit status
;
; Result:
;   Does not return.
;
; Linux syscall ABI:
;   RAX = syscall number
;   RDI = first argument
;
; Clobbers:
;   RAX
;   RCX
;   R11
;
; Ownership:
;   None.
;
; Resource effects:
;   Terminates the process.
;
; Failure:
;   No normal return path exists.

asm_linux_exit:
    mov eax, LINUX_SYS_exit
    syscall

    ; exit(2) should not return.
    ; If execution reaches this point, terminate deliberately
    ; rather than falling through into unrelated memory.
    ud2
