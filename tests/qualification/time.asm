bits 64

%include "asmweb/time.inc"

global _start

extern asm_monotonic_now
extern asm_linux_exit

section .bss

align 8
guard_before:
    resq 1

time_a:
    resb ASMWEB_MONOTONIC_TIME_size

time_b:
    resb ASMWEB_MONOTONIC_TIME_size

guard_after:
    resq 1

section .text

; ---------------------------------------------------------------------------
; Monotonic-time qualification
;
; Exit status:
;
;   0 = all checks passed
;   1 = first monotonic read failed
;   2 = normalized representation invalid
;   3 = guard corruption
;   4 = second monotonic read failed
;   5 = monotonic order violated
;   6 = total_ns reconstruction mismatch
;   7 = NULL destination semantics failed
;   8 = callee-saved RBX preservation failed
; ---------------------------------------------------------------------------

_start:
    cld

    mov qword [rel guard_before], 0x11111111
    mov qword [rel guard_after], 0x22222222

    ; =======================================================================
    ; CASE 1 — first valid read
    ; =======================================================================

    mov rbx, 0x1122334455667788

    lea rdi, [rel time_a]
    call asm_monotonic_now

    mov r10, rax

    mov rax, 0x1122334455667788
    cmp rbx, rax
    jne .fail_8

    test r10d, r10d
    jnz .fail_1

    cmp qword [rel time_a + ASMWEB_MONOTONIC_TIME.ready], 1
    jne .fail_1

    ; sec must be non-negative.
    mov rax, [rel time_a + ASMWEB_MONOTONIC_TIME.sec]
    test rax, rax
    js .fail_2

    ; nsec must be normalized.
    cmp qword [rel time_a + ASMWEB_MONOTONIC_TIME.nsec], ASMWEB_NSEC_PER_SEC
    jae .fail_2

    ; Guards prove the write stayed within the state structure.
    cmp qword [rel guard_before], 0x11111111
    jne .fail_3

    cmp qword [rel guard_after], 0x22222222
    jne .fail_3

    ; =======================================================================
    ; CASE 2 — second valid read
    ; =======================================================================

    mov rbx, 0x8877665544332211

    lea rdi, [rel time_b]
    call asm_monotonic_now

    mov r10, rax

    mov rax, 0x8877665544332211
    cmp rbx, rax
    jne .fail_8

    test r10d, r10d
    jnz .fail_4

    cmp qword [rel time_b + ASMWEB_MONOTONIC_TIME.ready], 1
    jne .fail_4

    cmp qword [rel time_b + ASMWEB_MONOTONIC_TIME.nsec], ASMWEB_NSEC_PER_SEC
    jae .fail_4

    ; =======================================================================
    ; CASE 3 — monotonic non-decrease
    ;
    ; Compare normalized (sec,nsec) lexicographically.
    ; =======================================================================

    mov rax, [rel time_b + ASMWEB_MONOTONIC_TIME.sec]
    mov rdx, [rel time_a + ASMWEB_MONOTONIC_TIME.sec]

    cmp rax, rdx
    jb .fail_5
    ja .check_totals

    mov rax, [rel time_b + ASMWEB_MONOTONIC_TIME.nsec]
    cmp rax, [rel time_a + ASMWEB_MONOTONIC_TIME.nsec]
    jb .fail_5

.check_totals:

    ; =======================================================================
    ; CASE 4 — independently reconstruct total_ns for both samples.
    ; =======================================================================

    mov rax, [rel time_a + ASMWEB_MONOTONIC_TIME.sec]
    mov rcx, ASMWEB_NSEC_PER_SEC
    mul rcx

    test rdx, rdx
    jnz .fail_6

    add rax, [rel time_a + ASMWEB_MONOTONIC_TIME.nsec]
    jc .fail_6

    cmp rax, [rel time_a + ASMWEB_MONOTONIC_TIME.total_ns]
    jne .fail_6

    mov rax, [rel time_b + ASMWEB_MONOTONIC_TIME.sec]
    mov rcx, ASMWEB_NSEC_PER_SEC
    mul rcx

    test rdx, rdx
    jnz .fail_6

    add rax, [rel time_b + ASMWEB_MONOTONIC_TIME.nsec]
    jc .fail_6

    cmp rax, [rel time_b + ASMWEB_MONOTONIC_TIME.total_ns]
    jne .fail_6

    ; Numeric nanoseconds must also be non-decreasing.
    mov rax, [rel time_b + ASMWEB_MONOTONIC_TIME.total_ns]
    cmp rax, [rel time_a + ASMWEB_MONOTONIC_TIME.total_ns]
    jb .fail_5

    ; =======================================================================
    ; CASE 5 — NULL destination
    ; =======================================================================

    mov rbx, 0xaabbccddeeff0011

    xor edi, edi
    call asm_monotonic_now

    mov r10, rax

    mov rax, 0xaabbccddeeff0011
    cmp rbx, rax
    jne .fail_8

    cmp r10d, 1
    jne .fail_7

    ; =======================================================================
    ; PASS
    ; =======================================================================

    xor edi, edi
    call asm_linux_exit
    ud2

.fail_1:
    mov edi, 1
    call asm_linux_exit
    ud2

.fail_2:
    mov edi, 2
    call asm_linux_exit
    ud2

.fail_3:
    mov edi, 3
    call asm_linux_exit
    ud2

.fail_4:
    mov edi, 4
    call asm_linux_exit
    ud2

.fail_5:
    mov edi, 5
    call asm_linux_exit
    ud2

.fail_6:
    mov edi, 6
    call asm_linux_exit
    ud2

.fail_7:
    mov edi, 7
    call asm_linux_exit
    ud2

.fail_8:
    mov edi, 8
    call asm_linux_exit
    ud2
