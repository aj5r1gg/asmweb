bits 64
default rel

%include "linux/network.inc"

extern asm_linux_socket
extern asm_linux_bind
extern asm_linux_getsockname
extern asm_linux_getpeername
extern asm_linux_listen
extern asm_linux_accept4
extern asm_linux_close

global _start

%define SYS_CONNECT      42
%define SYS_FCNTL        72
%define F_GETFD           1
%define F_GETFL           3
%define FD_CLOEXEC        1
%define O_NONBLOCK        0x800

section .data

endpoint:
    dw LINUX_AF_INET
    dw 0
    dd 0x0100007f
    dq 0

endpoint_length dd 16
peer_length dd 16
peer_endpoint: times 16 db 0

section .text

_start:
    mov r12, -1              ; Listener
    mov r13, -1              ; Client
    mov r14, -1              ; Accepted descriptor
    xor ebx, ebx             ; Failure status

    ; Create nonblocking TCP listener.
    mov edi, LINUX_AF_INET
    mov esi, LINUX_SOCK_STREAM | LINUX_SOCK_NONBLOCK | LINUX_SOCK_CLOEXEC
    mov edx, LINUX_IPPROTO_TCP
    call asm_linux_socket

    test rax, rax
    js .fail_socket
    mov r12, rax

    ; Bind loopback with an ephemeral port.
    mov rdi, r12
    lea rsi, [endpoint]
    mov edx, 16
    call asm_linux_bind

    test rax, rax
    js .fail_bind

    ; Discover assigned port.
    mov rdi, r12
    lea rsi, [endpoint]
    lea rdx, [endpoint_length]
    call asm_linux_getsockname

    test rax, rax
    js .fail_endpoint

    cmp dword [endpoint_length], 16
    jne .fail_endpoint

    cmp word [endpoint + 2], 0
    je .fail_endpoint

    ; Start listening.
    mov rdi, r12
    mov esi, 1
    call asm_linux_listen

    test rax, rax
    js .fail_listen

    ; Empty queue must return EAGAIN.
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    mov ecx, LINUX_SOCK_NONBLOCK | LINUX_SOCK_CLOEXEC
    call asm_linux_accept4

    cmp rax, -11
    jne .fail_eagain

    ; Create blocking client.
    mov edi, LINUX_AF_INET
    mov esi, LINUX_SOCK_STREAM | LINUX_SOCK_CLOEXEC
    mov edx, LINUX_IPPROTO_TCP
    call asm_linux_socket

    test rax, rax
    js .fail_socket
    mov r13, rax

    ; Connect client to listener.
    mov rdi, r13
    lea rsi, [endpoint]
    mov edx, 16
    mov eax, SYS_CONNECT
    syscall

    test rax, rax
    js .fail_connect

    ; Accept connection with nonblocking and CLOEXEC flags.
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    mov ecx, LINUX_SOCK_NONBLOCK | LINUX_SOCK_CLOEXEC
    call asm_linux_accept4

    test rax, rax
    js .fail_accept

    mov r14, rax

    ; Obtain peer endpoint through the AsmWeb wrapper.
    mov rdi, r14
    lea rsi, [peer_endpoint]
    lea rdx, [peer_length]
    call asm_linux_getpeername

    test rax, rax
    jne .fail_peer

    cmp dword [peer_length], 16
    jne .fail_peer

    cmp word [peer_endpoint], LINUX_AF_INET
    jne .fail_peer

    cmp dword [peer_endpoint + 4], 0x0100007f
    jne .fail_peer

    cmp word [peer_endpoint + 2], 0
    je .fail_peer

    ; Verify O_NONBLOCK on accepted descriptor.
    mov rdi, r14
    mov esi, F_GETFL
    xor edx, edx
    mov eax, SYS_FCNTL
    syscall

    test rax, rax
    js .fail_nonblock

    test eax, O_NONBLOCK
    jz .fail_nonblock

    ; Verify FD_CLOEXEC on accepted descriptor.
    mov rdi, r14
    mov esi, F_GETFD
    xor edx, edx
    mov eax, SYS_FCNTL
    syscall

    test rax, rax
    js .fail_cloexec

    test eax, FD_CLOEXEC
    jz .fail_cloexec

    ; Listener must remain nonblocking.
    mov rdi, r12
    mov esi, F_GETFL
    xor edx, edx
    mov eax, SYS_FCNTL
    syscall

    test rax, rax
    js .fail_listener_flags

    test eax, O_NONBLOCK
    jz .fail_listener_flags

    jmp .cleanup

.fail_peer:
    mov ebx, 24
    jmp .cleanup

.fail_socket:
    mov ebx, 11
    jmp .cleanup

.fail_bind:
    mov ebx, 12
    jmp .cleanup

.fail_endpoint:
    mov ebx, 13
    jmp .cleanup

.fail_listen:
    mov ebx, 14
    jmp .cleanup

.fail_eagain:
    mov ebx, 15
    jmp .cleanup

.fail_connect:
    mov ebx, 16
    jmp .cleanup

.fail_accept:
    mov ebx, 17
    jmp .cleanup

.fail_nonblock:
    mov ebx, 18
    jmp .cleanup

.fail_cloexec:
    mov ebx, 19
    jmp .cleanup

.fail_listener_flags:
    mov ebx, 20

.cleanup:
    ; Close accepted socket.
    cmp r14, 0
    jl .close_client

    mov rdi, r14
    call asm_linux_close

    test rax, rax
    jns .close_client
    test ebx, ebx
    jnz .close_client
    mov ebx, 21

.close_client:
    cmp r13, 0
    jl .close_listener

    mov rdi, r13
    call asm_linux_close

    test rax, rax
    jns .close_listener
    test ebx, ebx
    jnz .close_listener
    mov ebx, 22

.close_listener:
    cmp r12, 0
    jl .finish

    mov rdi, r12
    call asm_linux_close

    test rax, rax
    jns .finish
    test ebx, ebx
    jnz .finish
    mov ebx, 23

.finish:
    mov edi, ebx
    mov eax, 60
    syscall
    ud2
