bits 64
default rel

%include "linux/network.inc"

extern asm_linux_send
extern asm_linux_recv
extern asm_linux_setsockopt
extern asm_linux_close

global _start

%define SYS_SOCKETPAIR 53
%define SYS_EXIT       60
%define AF_UNIX         1
%define SO_SNDBUF       7
%define PAYLOAD_SIZE    65536
%define MAX_ATTEMPTS    128

section .data

descriptors:
    dd -1, -1

send_buffer_size:
    dd 4096

payload:
    times PAYLOAD_SIZE db 'Q'

receive_buffer:
    times 4096 db 0

receive_guard:
    dd 0xA5A5A5A5

section .text

_start:
    mov r12, -1
    mov r13, -1
    xor ebx, ebx

    ; Nonblocking connected stream socket pair.
    mov edi, AF_UNIX
    mov esi, LINUX_SOCK_STREAM | LINUX_SOCK_NONBLOCK | LINUX_SOCK_CLOEXEC
    xor edx, edx
    lea r10, [descriptors]
    mov eax, SYS_SOCKETPAIR
    syscall

    test rax, rax
    js .fail_socketpair

    mov r12d, [descriptors]
    mov r13d, [descriptors + 4]

    ; Request a deliberately small sender buffer.
    mov rdi, r12
    mov esi, LINUX_SOL_SOCKET
    mov edx, SO_SNDBUF
    lea rcx, [send_buffer_size]
    mov r8d, 4
    call asm_linux_setsockopt

    test rax, rax
    js .fail_sockopt

    ; Request much more data than the configured buffer.
    mov rdi, r12
    lea rsi, [payload]
    mov edx, PAYLOAD_SIZE
    xor ecx, ecx
    call asm_linux_send

    ; A positive return smaller than requested proves
    ; partial progress was reported to the caller.
    cmp rax, 0
    jle .fail_short_write

    cmp rax, PAYLOAD_SIZE
    jae .fail_short_write

    ; Save the actual accepted byte count.
    mov r14, rax

    ; The receiver does not consume yet. Continue sending
    ; until the kernel reports EAGAIN. Bound attempts.
    mov r15d, MAX_ATTEMPTS

.fill:
    test r15, r15
    jz .fail_exhaustion

    dec r15

    mov rdi, r12
    lea rsi, [payload]
    mov edx, 4096
    xor ecx, ecx
    call asm_linux_send

    cmp rax, -11
    je .exhausted

    test rax, rax
    jle .fail_exhaustion

    cmp rax, 4096
    ja .fail_exhaustion

    jmp .fill

.exhausted:
    ; Receiving from the peer must recover actual data.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 4096
    call asm_linux_recv

    test rax, rax
    jle .fail_receive

    cmp rax, 4096
    ja .fail_receive

    ; Confirm payload data and the buffer boundary.
    cmp byte [receive_buffer], 'Q'
    jne .fail_payload

    cmp dword [receive_guard], 0xA5A5A5A5
    jne .fail_guard

    ; Original send must have made positive partial progress.
    test r14, r14
    jle .fail_short_write

    cmp r14, PAYLOAD_SIZE
    jae .fail_short_write

    jmp .cleanup

.fail_socketpair:
    mov ebx, 11
    jmp .cleanup

.fail_sockopt:
    mov ebx, 12
    jmp .cleanup

.fail_short_write:
    mov ebx, 13
    jmp .cleanup

.fail_exhaustion:
    mov ebx, 14
    jmp .cleanup

.fail_receive:
    mov ebx, 15
    jmp .cleanup

.fail_payload:
    mov ebx, 16
    jmp .cleanup

.fail_guard:
    mov ebx, 17

.cleanup:
    cmp r13, 0
    jl .close_sender

    mov rdi, r13
    call asm_linux_close

    test rax, rax
    jns .close_sender

    test ebx, ebx
    jnz .close_sender

    mov ebx, 18

.close_sender:
    cmp r12, 0
    jl .finish

    mov rdi, r12
    call asm_linux_close

    test rax, rax
    jns .finish

    test ebx, ebx
    jnz .finish

    mov ebx, 19

.finish:
    mov edi, ebx
    mov eax, SYS_EXIT
    syscall
    ud2
