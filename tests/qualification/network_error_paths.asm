bits 64
default rel

%include "linux/network.inc"

extern asm_linux_recv
extern asm_linux_send
extern asm_linux_recvfrom
extern asm_linux_sendto
extern asm_linux_getsockname
extern asm_linux_getpeername
extern asm_linux_close

global _start

%define SYS_SOCKETPAIR 53
%define SYS_EXIT       60
%define AF_UNIX         1
%define MSG_TRUNC    0x20

section .data

descriptors:
    dd -1, -1

payload:
    db 'ASMUDP01'

receive_buffer:
    times 4 db 0
receive_guard:
    dd 0xA5A5A5A5

address_buffer:
    times 128 db 0

address_length:
    dd 128

section .text

_start:
    mov r12, -1
    mov r13, -1
    xor ebx, ebx

    ; Create connected, nonblocking datagram sockets.
    mov edi, AF_UNIX
    mov esi, LINUX_SOCK_DGRAM | LINUX_SOCK_NONBLOCK | LINUX_SOCK_CLOEXEC
    xor edx, edx
    lea r10, [descriptors]
    mov eax, SYS_SOCKETPAIR
    syscall

    test rax, rax
    js .fail_socketpair

    mov r12d, [descriptors]
    mov r13d, [descriptors + 4]

    ; Empty nonblocking receive: EAGAIN.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 4
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call asm_linux_recvfrom

    cmp rax, -11
    jne .fail_eagain

    ; Send an eight-byte datagram.
    mov rdi, r12
    lea rsi, [payload]
    mov edx, 8
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call asm_linux_sendto

    cmp rax, 8
    jne .fail_send

    ; Receive into a deliberately smaller buffer.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 4
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call asm_linux_recvfrom

    cmp rax, 4
    jne .fail_truncation

    cmp dword [receive_buffer], 0x554D5341
    jne .fail_payload

    ; The four-byte guard must be untouched.
    cmp dword [receive_guard], 0xA5A5A5A5
    jne .fail_guard

    ; The discarded remainder must not become another datagram.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 4
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call asm_linux_recvfrom

    cmp rax, -11
    jne .fail_discard

    ; Send another eight-byte datagram.
    mov rdi, r12
    lea rsi, [payload]
    mov edx, 8
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call asm_linux_sendto

    cmp rax, 8
    jne .fail_send

    ; MSG_TRUNC reports full datagram length on Linux.
    ; Only four bytes may be copied to our receive buffer.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 4
    mov ecx, MSG_TRUNC
    xor r8d, r8d
    xor r9d, r9d
    call asm_linux_recvfrom

    cmp rax, 8
    jne .fail_msg_trunc

    cmp dword [receive_guard], 0xA5A5A5A5
    jne .fail_guard

    ; Zero-length datagrams are valid and distinct from EAGAIN.
    mov rdi, r12
    lea rsi, [payload]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call asm_linux_sendto

    test rax, rax
    jne .fail_zero

    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 4
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call asm_linux_recvfrom

    test rax, rax
    jne .fail_zero

    ; Invalid descriptor: getsockname -> EBADF.
    mov rdi, -1
    lea rsi, [address_buffer]
    lea rdx, [address_length]
    call asm_linux_getsockname

    cmp rax, -9
    jne .fail_badfd

    ; Invalid descriptor: getpeername -> EBADF.
    mov rdi, -1
    lea rsi, [address_buffer]
    lea rdx, [address_length]
    call asm_linux_getpeername

    cmp rax, -9
    jne .fail_badfd

    ; Invalid descriptor: recv -> EBADF.
    mov rdi, -1
    lea rsi, [receive_buffer]
    mov edx, 4
    call asm_linux_recv

    cmp rax, -9
    jne .fail_badfd

    ; Invalid descriptor: send -> EBADF.
    mov rdi, -1
    lea rsi, [payload]
    mov edx, 8
    xor ecx, ecx
    call asm_linux_send

    cmp rax, -9
    jne .fail_badfd

    jmp .cleanup

.fail_socketpair:
    mov ebx, 11
    jmp .cleanup

.fail_eagain:
    mov ebx, 12
    jmp .cleanup

.fail_send:
    mov ebx, 13
    jmp .cleanup

.fail_truncation:
    mov ebx, 14
    jmp .cleanup

.fail_payload:
    mov ebx, 15
    jmp .cleanup

.fail_guard:
    mov ebx, 16
    jmp .cleanup

.fail_discard:
    mov ebx, 17
    jmp .cleanup

.fail_msg_trunc:
    mov ebx, 18
    jmp .cleanup

.fail_zero:
    mov ebx, 19
    jmp .cleanup

.fail_badfd:
    mov ebx, 20

.cleanup:
    ; Close both owned descriptors exactly once.
    cmp r13, 0
    jl .close_first

    mov rdi, r13
    call asm_linux_close

    test rax, rax
    jns .close_first
    test ebx, ebx
    jnz .close_first
    mov ebx, 21

.close_first:
    cmp r12, 0
    jl .finish

    mov rdi, r12
    call asm_linux_close

    test rax, rax
    jns .finish
    test ebx, ebx
    jnz .finish
    mov ebx, 22

.finish:
    mov edi, ebx
    mov eax, SYS_EXIT
    syscall
    ud2
