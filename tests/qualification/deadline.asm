bits 64
default rel

global _start

extern asm_deadline_remaining

%define SYS_EXIT 60

section .data

guard_before:
    dq 0x1122334455667788

timeval_output:
    dq 0, 0

guard_after:
    dq 0x8877665544332211

section .text

; CHECK start_ns, now_ns, budget_ns, status, sec, usec
;
; The failing case number is returned as process exit status.

%macro CHECK 6
    inc r15d

    mov qword [timeval_output], -1
    mov qword [timeval_output + 8], -1

    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    lea rcx, [timeval_output]

    ; Test preservation of callee-saved registers.
    mov rbx, 0x1020304050607080
    mov r12, 0x1111222233334444
    mov r13, 0x5555666677778888
    mov r14, 0x123456789abcdef0

    call asm_deadline_remaining

    cmp rax, %4
    jne .failure

    cmp qword [timeval_output], %5
    jne .failure

    cmp qword [timeval_output + 8], %6
    jne .failure

    mov rax, 0x1122334455667788
    cmp [guard_before], rax
    jne .failure

    mov rax, 0x8877665544332211
    cmp [guard_after], rax
    jne .failure

    mov rax, 0x1020304050607080
    cmp rbx, rax
    jne .failure

    mov rax, 0x1111222233334444
    cmp r12, rax
    jne .failure

    mov rax, 0x5555666677778888
    cmp r13, rax
    jne .failure

    mov rax, 0x123456789abcdef0
    cmp r14, rax
    jne .failure
%endmacro

_start:
    cld
    xor r15d, r15d

    ; 1. Full three-second budget.
    CHECK 1000000000, 1000000000, 3000000000, 0, 3, 0

    ; 2. One second elapsed.
    CHECK 1000000000, 2000000000, 3000000000, 0, 2, 0

    ; 3. One nanosecond remains: rounds UP to 1 us.
    CHECK 0, 2999999999, 3000000000, 0, 0, 1

    ; 4. Exactly at expiry.
    CHECK 0, 3000000000, 3000000000, 1, 0, 0

    ; 5. Beyond expiry.
    CHECK 0, 4000000000, 3000000000, 1, 0, 0

    ; 6. A backward monotonic sample is invalid.
    CHECK 2000000000, 1999999999, 3000000000, 2, 0, 0

    ; 7. Zero budget is invalid.
    CHECK 100, 100, 0, 2, 0, 0

    ; 8. Unsigned addition overflow is invalid.
    CHECK 0xfffffffffffffff0, 0xfffffffffffffff0, 100, 2, 0, 0

    ; 9. Exactly one microsecond remaining.
    CHECK 0, 0, 1000, 0, 0, 1

    ; 10. 1001 ns rounds UP to two microseconds.
    CHECK 0, 0, 1001, 0, 0, 2

    ; 11. One second plus one nanosecond.
    CHECK 0, 0, 1000000001, 0, 1, 1

    ; 12. Largest representable budget, near expiry.
    CHECK 0, 0xfffffffffffffffe, 0xffffffffffffffff, 0, 0, 1

    ; 13. Maximum clock value exactly at expiry.
    CHECK 0xfffffffffffffffe, 0xffffffffffffffff, 1, 1, 0, 0

    ; 14. Fractional microseconds across a second boundary.
    CHECK 0, 0, 999999999, 0, 1, 0

    ; 15. 1 ns at the start of the budget.
    CHECK 0, 0, 1, 0, 0, 1

    ; Success.
    xor edi, edi
    mov eax, SYS_EXIT
    syscall
    ud2

.failure:
    mov edi, r15d
    mov eax, SYS_EXIT
    syscall
    ud2
