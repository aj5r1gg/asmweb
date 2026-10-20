bits 64
default rel

global asm_deadline_remaining

%define NSEC_PER_USEC 1000
%define USEC_PER_SEC 1000000

section .text

; asm_deadline_remaining
;
; RDI = start_ns
; RSI = now_ns
; RDX = budget_ns
; RCX = writable timeval pointer (16 bytes)
;
; RAX:
;   0 = active
;   1 = expired
;   2 = invalid
;
; Output: timeval { seconds, microseconds }.
; Positive remaining nanoseconds are rounded UP to microseconds.
; No allocation, syscall, retry, or callee-saved modification.

asm_deadline_remaining:
    cld

    test rcx, rcx
    jz .invalid_no_output

    ; Failure/expiry leave a deterministic zero timeval.
    mov qword [rcx], 0
    mov qword [rcx + 8], 0

    test rdx, rdx
    jz .invalid

    ; Reject backward clock samples.
    cmp rsi, rdi
    jb .invalid

    ; Checked absolute deadline = start + budget.
    mov r8, rdi
    add r8, rdx
    jc .invalid

    ; Equality is already expired.
    cmp rsi, r8
    jae .expired

    ; remaining_ns is strictly positive.
    sub r8, rsi

    ; Convert nanoseconds to microseconds using division.
    ; Quotient is floor(remaining_ns / 1000).
    ; Increment if there is a remainder, giving ceiling.
    mov rax, r8
    xor edx, edx
    mov r9d, NSEC_PER_USEC
    div r9

    test rdx, rdx
    jz .whole_microseconds

    inc rax
    jz .invalid

.whole_microseconds:
    ; Split total microseconds into timeval sec/usec.
    xor edx, edx
    mov r9d, USEC_PER_SEC
    div r9

    mov [rcx], rax
    mov [rcx + 8], rdx

    xor eax, eax
    ret

.expired:
    mov eax, 1
    ret

.invalid:
    mov eax, 2
    ret

.invalid_no_output:
    mov eax, 2
    ret
