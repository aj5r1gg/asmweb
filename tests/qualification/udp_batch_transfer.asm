bits 64
default rel

%include "linux/network.inc"

extern asm_linux_sendmmsg_bounded
extern asm_linux_recvmmsg_bounded
extern asm_linux_close

global _start

%define SYS_SOCKETPAIR 53
%define SYS_EXIT       60
%define AF_UNIX         1
%define MSG_DONTWAIT 0x40

%define IOV_SIZE   16
%define MMSG_SIZE  64
%define MSG_IOV    16
%define MSG_IOVLEN 24
%define MMSG_LEN   56

section .data

fds: dd -1, -1

payload_a: db 'ABCD'
payload_b: db 'XYZ'

send_iov: times (2 * IOV_SIZE) db 0
recv_iov: times (2 * IOV_SIZE) db 0

send_msgs: times (2 * MMSG_SIZE) db 0
recv_msgs: times (2 * MMSG_SIZE) db 0

receive_a: times 8 db 0xA5
receive_b: times 8 db 0xA5

section .text

_start:
    mov r12, -1
    mov r13, -1
    xor ebx, ebx

    ; Nonblocking connected datagram sockets.
    mov edi, AF_UNIX
    mov esi, LINUX_SOCK_DGRAM | LINUX_SOCK_NONBLOCK | LINUX_SOCK_CLOEXEC
    xor edx, edx
    lea r10, [fds]
    mov eax, SYS_SOCKETPAIR
    syscall
    test rax, rax
    js .fail_socket

    mov r12d, [fds]
    mov r13d, [fds + 4]

    ; Empty receive must report EAGAIN.
    mov rdi, r13
    lea rsi, [recv_msgs]
    mov edx, 1
    mov ecx, MSG_DONTWAIT
    xor r8d, r8d
    call asm_linux_recvmmsg_bounded
    cmp rax, -11
    jne .fail_eagain

    ; Two independent send iovecs.
    lea rax, [payload_a]
    mov [send_iov], rax
    mov qword [send_iov + 8], 4

    lea rax, [payload_b]
    mov [send_iov + IOV_SIZE], rax
    mov qword [send_iov + IOV_SIZE + 8], 3

    lea rax, [send_iov]
    mov [send_msgs + MSG_IOV], rax
    mov qword [send_msgs + MSG_IOVLEN], 1

    lea rax, [send_iov + IOV_SIZE]
    mov [send_msgs + MMSG_SIZE + MSG_IOV], rax
    mov qword [send_msgs + MMSG_SIZE + MSG_IOVLEN], 1

    mov rdi, r12
    lea rsi, [send_msgs]
    mov edx, 2
    xor ecx, ecx
    call asm_linux_sendmmsg_bounded
    cmp rax, 2
    jne .fail_send

    cmp dword [send_msgs + MMSG_LEN], 4
    jne .fail_send_len
    cmp dword [send_msgs + MMSG_SIZE + MMSG_LEN], 3
    jne .fail_send_len

    ; Two receive buffers with untouched guard bytes.
    lea rax, [receive_a]
    mov [recv_iov], rax
    mov qword [recv_iov + 8], 4

    lea rax, [receive_b]
    mov [recv_iov + IOV_SIZE], rax
    mov qword [recv_iov + IOV_SIZE + 8], 3

    lea rax, [recv_iov]
    mov [recv_msgs + MSG_IOV], rax
    mov qword [recv_msgs + MSG_IOVLEN], 1

    lea rax, [recv_iov + IOV_SIZE]
    mov [recv_msgs + MMSG_SIZE + MSG_IOV], rax
    mov qword [recv_msgs + MMSG_SIZE + MSG_IOVLEN], 1

    mov rdi, r13
    lea rsi, [recv_msgs]
    mov edx, 2
    mov ecx, MSG_DONTWAIT
    xor r8d, r8d
    call asm_linux_recvmmsg_bounded
    cmp rax, 2
    jne .fail_recv

    cmp dword [recv_msgs + MMSG_LEN], 4
    jne .fail_recv_len
    cmp dword [recv_msgs + MMSG_SIZE + MMSG_LEN], 3
    jne .fail_recv_len

    cmp dword [receive_a], 0x44434241
    jne .fail_payload
    cmp dword [receive_a + 4], 0xA5A5A5A5
    jne .fail_guard

    cmp word [receive_b], 0x5958
    jne .fail_payload
    cmp byte [receive_b + 2], 'Z'
    jne .fail_payload
    cmp dword [receive_b + 3], 0xA5A5A5A5
    jne .fail_guard

    ; Batch receive consumed both datagrams.
    mov rdi, r13
    lea rsi, [recv_msgs]
    mov edx, 1
    mov ecx, MSG_DONTWAIT
    xor r8d, r8d
    call asm_linux_recvmmsg_bounded
    cmp rax, -11
    jne .fail_eagain

    jmp .cleanup

.fail_socket:
    mov ebx, 11
    jmp .cleanup
.fail_eagain:
    mov ebx, 12
    jmp .cleanup
.fail_send:
    mov ebx, 13
    jmp .cleanup
.fail_send_len:
    mov ebx, 14
    jmp .cleanup
.fail_recv:
    mov ebx, 15
    jmp .cleanup
.fail_recv_len:
    mov ebx, 16
    jmp .cleanup
.fail_payload:
    mov ebx, 17
    jmp .cleanup
.fail_guard:
    mov ebx, 18

.cleanup:
    cmp r13, 0
    jl .close_sender
    mov rdi, r13
    call asm_linux_close
    test rax, rax
    jns .close_sender
    test ebx, ebx
    jnz .close_sender
    mov ebx, 19

.close_sender:
    cmp r12, 0
    jl .exit
    mov rdi, r12
    call asm_linux_close
    test rax, rax
    jns .exit
    test ebx, ebx
    jnz .exit
    mov ebx, 20

.exit:
    mov edi, ebx
    mov eax, SYS_EXIT
    syscall
    ud2
