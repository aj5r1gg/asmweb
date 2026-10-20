bits 64
default rel

%include "linux/network.inc"

extern asm_linux_socket
extern asm_linux_bind
extern asm_linux_sendto
extern asm_linux_recvfrom
extern asm_linux_close

global _start

section .data
receiver_fd dq -1
sender_fd   dq -1

; sockaddr_in: IPv4 loopback, ephemeral port.
bind_address:
    dw LINUX_AF_INET
    dw 0
    dd 0x0100007f
    dq 0

payload db "ASMUDP01"
payload_len equ $ - payload

address_length dd 16
source_length  dd 16

section .bss
receiver_address resb 16
source_address   resb 16
receive_buffer   resb 64

section .text

_start:
    ; Create a nonblocking, close-on-exec UDP receiver.
    mov edi, LINUX_AF_INET
    mov esi, LINUX_SOCK_DGRAM | LINUX_SOCK_NONBLOCK | LINUX_SOCK_CLOEXEC
    mov edx, LINUX_IPPROTO_UDP
    call asm_linux_socket
    test rax, rax
    js .fail_socket
    mov [receiver_fd], rax

    ; Bind receiver to 127.0.0.1 with kernel-selected port.
    mov rdi, rax
    lea rsi, [bind_address]
    mov edx, 16
    call asm_linux_bind
    test rax, rax
    js .fail_bind

    ; Obtain the receiver's actual endpoint.
    mov rdi, [receiver_fd]
    lea rsi, [receiver_address]
    lea rdx, [address_length]
    mov eax, 51                    ; getsockname
    syscall
    test rax, rax
    js .fail_endpoint

    cmp dword [address_length], 16
    jne .fail_endpoint

    cmp word [receiver_address + 2], 0
    je .fail_endpoint

    ; Before sending, nonblocking recvfrom must report EAGAIN.
    mov rdi, [receiver_fd]
    lea rsi, [receive_buffer]
    mov edx, 64
    xor ecx, ecx
    lea r8, [source_address]
    lea r9, [source_length]
    call asm_linux_recvfrom

    cmp rax, -11                   ; EAGAIN
    jne .fail_nonblocking

    ; Create a separate UDP sender.
    mov edi, LINUX_AF_INET
    mov esi, LINUX_SOCK_DGRAM | LINUX_SOCK_CLOEXEC
    mov edx, LINUX_IPPROTO_UDP
    call asm_linux_socket
    test rax, rax
    js .fail_socket
    mov [sender_fd], rax

    ; Send eight bytes through AsmWeb's sendto wrapper.
    mov rdi, rax
    lea rsi, [payload]
    mov edx, payload_len
    xor ecx, ecx
    lea r8, [receiver_address]
    mov r9d, 16
    call asm_linux_sendto

    cmp rax, payload_len
    jne .fail_send

    ; Receive using AsmWeb's recvfrom wrapper.
    mov rdi, [receiver_fd]
    lea rsi, [receive_buffer]
    mov edx, 64
    xor ecx, ecx
    lea r8, [source_address]
    lea r9, [source_length]
    call asm_linux_recvfrom

    cmp rax, payload_len
    jne .fail_receive

    cmp dword [source_length], 16
    jne .fail_receive

    ; Verify all eight payload bytes.
    lea rsi, [payload]
    lea rdi, [receive_buffer]
    mov ecx, payload_len
    cld
    repe cmpsb
    jne .fail_payload

    ; UDP permits zero-length datagrams.
    mov rdi, [sender_fd]
    lea rsi, [payload]
    xor edx, edx
    xor ecx, ecx
    lea r8, [receiver_address]
    mov r9d, 16
    call asm_linux_sendto
    test rax, rax
    jne .fail_zero_length

    mov rdi, [receiver_fd]
    lea rsi, [receive_buffer]
    mov edx, 64
    xor ecx, ecx
    lea r8, [source_address]
    lea r9, [source_length]
    call asm_linux_recvfrom
    test rax, rax
    jne .fail_zero_length

    ; Success.
    xor ebx, ebx
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

.fail_nonblocking:
    mov ebx, 14
    jmp .cleanup

.fail_send:
    mov ebx, 15
    jmp .cleanup

.fail_receive:
    mov ebx, 16
    jmp .cleanup

.fail_payload:
    mov ebx, 17
    jmp .cleanup

.fail_zero_length:
    mov ebx, 18

.cleanup:
    mov rdi, [sender_fd]
    test rdi, rdi
    js .close_receiver
    call asm_linux_close
    test rax, rax
    jns .close_receiver
    test ebx, ebx
    jnz .close_receiver
    mov ebx, 19

.close_receiver:
    mov rdi, [receiver_fd]
    test rdi, rdi
    js .finish
    call asm_linux_close
    test rax, rax
    jns .finish
    test ebx, ebx
    jnz .finish
    mov ebx, 20

.finish:
    mov edi, ebx
    mov eax, 60                    ; exit
    syscall
    ud2
