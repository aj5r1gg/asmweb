bits 64
default rel

%include "linux/network.inc"

extern asm_linux_recvmmsg_bounded
extern asm_linux_sendmmsg_bounded

global _start

%if ASMWEB_UDP_BATCH_MAX != 16
    %error "Unexpected provisional batch capacity"
%endif

%define SYS_EXIT 60
%define EBADF 9

section .data
guard_before dq 0x1122334455667788
messages: times (16 * 64) db 0
guard_after dq 0x8877665544332211

section .text

_start:
    ; Test receive boundary.
    lea r12, [rel asm_linux_recvmmsg_bounded]
    call test_boundary
    test eax, eax
    jnz .exit

    ; Test send boundary.
    lea r12, [rel asm_linux_sendmmsg_bounded]
    call test_boundary
    test eax, eax
    jnz .exit

    ; Rejected calls must leave caller memory untouched.
    mov rax, 0x1122334455667788
    cmp qword [rel guard_before], rax
    jne .fail_guard

    mov rax, 0x8877665544332211
    cmp qword [rel guard_after], rax
    jne .fail_guard

    xor edi, edi
    jmp .finish

.fail_guard:
    mov eax, 30

.exit:
    mov edi, eax

.finish:
    mov eax, SYS_EXIT
    syscall
    ud2

test_boundary:
    ; R12 = bounded function under test.
    ; Invalid descriptor is intentional.
    ; It distinguishes local validation from syscall dispatch
    ; when the kernel would otherwise return EBADF.

    ; Zero count.
    mov edi, -1
    lea rsi, [rel messages]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -LINUX_EINVAL
    jne .fail_zero

    ; First count above maximum.
    mov edi, -1
    lea rsi, [rel messages]
    mov edx, ASMWEB_UDP_BATCH_MAX + 1
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -LINUX_EINVAL
    jne .fail_over

    ; Negative count: unsigned representation must reject it.
    mov edi, -1
    lea rsi, [rel messages]
    mov rdx, -1
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -LINUX_EINVAL
    jne .fail_negative

    ; High-bit count.
    mov edi, -1
    lea rsi, [rel messages]
    mov rdx, 0x8000000000000000
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -LINUX_EINVAL
    jne .fail_highbit

    ; Null message pointer with an otherwise valid count.
    mov edi, -1
    xor esi, esi
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -LINUX_EINVAL
    jne .fail_null

    ; Valid lower bound must delegate to kernel.
    mov edi, -1
    lea rsi, [rel messages]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -EBADF
    jne .fail_one

    ; Valid intermediate count.
    mov edi, -1
    lea rsi, [rel messages]
    mov edx, 2
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -EBADF
    jne .fail_two

    ; Valid upper bound must delegate to kernel.
    mov edi, -1
    lea rsi, [rel messages]
    mov edx, ASMWEB_UDP_BATCH_MAX
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -EBADF
    jne .fail_max

    xor eax, eax
    ret

.fail_zero:
    mov eax, 11
    ret
.fail_over:
    mov eax, 12
    ret
.fail_negative:
    mov eax, 13
    ret
.fail_highbit:
    mov eax, 14
    ret
.fail_null:
    mov eax, 15
    ret
.fail_one:
    mov eax, 16
    ret
.fail_two:
    mov eax, 17
    ret
.fail_max:
    mov eax, 18
    ret
