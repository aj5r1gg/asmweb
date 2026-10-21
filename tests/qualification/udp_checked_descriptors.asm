bits 64
default rel

%include "linux/network.inc"

extern asm_linux_recvmmsg_checked
extern asm_linux_sendmmsg_checked

global _start

%define SYS_EXIT 60
%define EBADF 9

section .data
align 8

guard_before: dq 0x1122334455667788
message: times 64 db 0
vector: times 16 db 0
payload: db 0x5a
guard_after: dq 0x8877665544332211

section .text

_start:
    lea rax, [payload]
    mov [vector], rax
    mov qword [vector + 8], 1

    lea rax, [vector]
    mov [message + ASMWEB_LINUX_MSG_IOV_OFFSET], rax
    mov qword [message + ASMWEB_LINUX_MSG_IOVLEN_OFFSET], 1

    lea r12, [asm_linux_recvmmsg_checked]
    call validate_cases
    test eax, eax
    jnz .exit

    lea r12, [asm_linux_sendmmsg_checked]
    call validate_cases
    test eax, eax
    jnz .exit

    mov rax, 0x1122334455667788
    cmp [guard_before], rax
    jne .guard_failure

    mov rax, 0x8877665544332211
    cmp [guard_after], rax
    jne .guard_failure

    xor edi, edi
    jmp .finish

.guard_failure:
    mov edi, 30
    jmp .finish

.exit:
    mov edi, eax

.finish:
    mov eax, SYS_EXIT
    syscall
    ud2

validate_cases:
    ; R12 holds the entry point under examination.
    ; Invalid fd differentiates validation from syscall dispatch.

    ; Valid metadata must reach the kernel and return EBADF.
    call .invoke
    cmp rax, -EBADF
    jne .fail_valid

    ; Zero batch count.
    mov edi, -1
    lea rsi, [message]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -LINUX_EINVAL
    jne .fail_count

    ; Batch count exceeds the provisional maximum.
    mov edi, -1
    lea rsi, [message]
    mov edx, ASMWEB_UDP_BATCH_MAX + 1
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -LINUX_EINVAL
    jne .fail_count

    ; Null descriptor array.
    mov edi, -1
    xor esi, esi
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call r12
    cmp rax, -LINUX_EINVAL
    jne .fail_count

    ; Zero iovecs.
    mov qword [message + ASMWEB_LINUX_MSG_IOVLEN_OFFSET], 0
    call .invoke
    cmp rax, -LINUX_EINVAL
    jne .fail_iov
    mov qword [message + ASMWEB_LINUX_MSG_IOVLEN_OFFSET], 1

    ; Multiple iovecs.
    mov qword [message + ASMWEB_LINUX_MSG_IOVLEN_OFFSET], 2
    call .invoke
    cmp rax, -LINUX_EINVAL
    jne .fail_iov
    mov qword [message + ASMWEB_LINUX_MSG_IOVLEN_OFFSET], 1

    ; Null iovec pointer.
    mov r14, [message + ASMWEB_LINUX_MSG_IOV_OFFSET]
    mov qword [message + ASMWEB_LINUX_MSG_IOV_OFFSET], 0
    call .invoke
    cmp rax, -LINUX_EINVAL
    jne .fail_iov
    mov [message + ASMWEB_LINUX_MSG_IOV_OFFSET], r14

    ; Payload length above the provisional limit.
    mov qword [vector + 8], ASMWEB_UDP_CHECKED_PAYLOAD_MAX + 1
    call .invoke
    cmp rax, -LINUX_EINVAL
    jne .fail_payload
    mov qword [vector + 8], 1

    ; Null payload base.
    mov r14, [vector]
    mov qword [vector], 0
    call .invoke
    cmp rax, -LINUX_EINVAL
    jne .fail_payload
    mov [vector], r14

    ; Connected-only profile: no per-message address.
    mov qword [message], 1
    call .invoke
    cmp rax, -LINUX_EINVAL
    jne .fail_name
    mov qword [message], 0

    ; No ancillary data.
    mov qword [message + ASMWEB_LINUX_MSG_CONTROLLEN_OFFSET], 1
    call .invoke
    cmp rax, -LINUX_EINVAL
    jne .fail_control
    mov qword [message + ASMWEB_LINUX_MSG_CONTROLLEN_OFFSET], 0

    ; Valid shape must still dispatch after all rejections.
    call .invoke
    cmp rax, -EBADF
    jne .fail_valid

    xor eax, eax
    ret

.invoke:
    mov edi, -1
    lea rsi, [message]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call r12
    ret

.fail_valid:
    mov eax, 11
    ret

.fail_count:
    mov eax, 12
    ret

.fail_iov:
    mov eax, 13
    ret

.fail_payload:
    mov eax, 14
    ret

.fail_name:
    mov eax, 15
    ret

.fail_control:
    mov eax, 16
    ret
