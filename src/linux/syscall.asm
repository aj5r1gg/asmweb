bits 64

%include "linux/syscall.inc"

global asm_linux_exit
global asm_linux_clock_gettime

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


; asm_linux_clock_gettime
;
; Controlled Linux syscall boundary.
;
; Input:
;   RDI = Linux clock ID
;   RSI = pointer to writable Linux timespec:
;         qword tv_sec
;         qword tv_nsec
;
; Result:
;   RAX = raw Linux syscall result:
;         0 on success
;         negative errno on failure
;
; Linux syscall ABI clobbers RCX and R11.

asm_linux_clock_gettime:
    mov eax, LINUX_SYS_clock_gettime
    syscall
    ret
