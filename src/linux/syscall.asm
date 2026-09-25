bits 64

%include "linux/syscall.inc"

global asm_linux_exit
global asm_linux_clock_gettime
global asm_linux_mmap
global asm_linux_munmap

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


; ---------------------------------------------------------------------------
; asm_linux_mmap
;
; Controlled Linux x86-64 mmap syscall boundary.
;
; Internal ABI input:
;
;   RDI = address hint
;   RSI = length
;   RDX = protection flags
;   RCX = mapping flags
;   R8  = file descriptor
;   R9  = offset
;
; Linux syscall ABI requires argument four in R10 rather than RCX.
;
; Result:
;
;   RAX = mapped address on success
;   RAX = negative errno on failure
;
; Clobbers:
;
;   RAX
;   RCX
;   R10
;   R11
;
; All are caller-saved under Internal ABI v1.

asm_linux_mmap:
    mov r10, rcx
    mov eax, LINUX_SYS_mmap
    syscall
    ret


; ---------------------------------------------------------------------------
; asm_linux_munmap
;
; Controlled Linux x86-64 munmap syscall boundary.
;
; Internal ABI input:
;
;   RDI = mapping base
;   RSI = mapping length
;
; Result:
;
;   RAX = 0 on success
;   RAX = negative errno on failure

asm_linux_munmap:
    mov eax, LINUX_SYS_munmap
    syscall
    ret
