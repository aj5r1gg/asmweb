bits 64
default rel

%include "linux/network.inc"

extern asm_linux_recv
extern asm_linux_send
extern asm_linux_close

global _start

%define SYS_SOCKETPAIR 53
%define SYS_SHUTDOWN   48
%define SYS_EXIT       60
%define AF_UNIX         1
%define SHUT_WR         1

section .data

descriptors:
    dd -1, -1

payload:
    db 'ABCDEFGH'

receive_buffer:
    times 8 db 0

receive_guard:
    dd 0xA5A5A5A5

section .text

_start:
    mov r12, -1              ; Sender
    mov r13, -1              ; Receiver
    xor ebx, ebx             ; Result code

    ; Create connected nonblocking stream sockets.
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

    ; Empty stream must return EAGAIN.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 8
    call asm_linux_recv

    cmp rax, -11
    jne .fail_eagain

    ; Send first fragment: ABC.
    mov rdi, r12
    lea rsi, [payload]
    mov edx, 3
    xor ecx, ecx
    call asm_linux_send

    cmp rax, 3
    jne .fail_first_send

    ; Consume two bytes: AB.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 2
    call asm_linux_recv

    cmp rax, 2
    jne .fail_first_read

    cmp word [receive_buffer], 0x4241
    jne .fail_payload

    ; Consume remaining byte: C.
    mov rdi, r13
    lea rsi, [receive_buffer + 2]
    mov edx, 1
    call asm_linux_recv

    cmp rax, 1
    jne .fail_second_read

    cmp byte [receive_buffer + 2], 'C'
    jne .fail_payload

    ; No more data is currently available.
    mov rdi, r13
    lea rsi, [receive_buffer + 3]
    mov edx, 5
    call asm_linux_recv

    cmp rax, -11
    jne .fail_eagain

    ; Send second fragment: DEFGH.
    mov rdi, r12
    lea rsi, [payload + 3]
    mov edx, 5
    xor ecx, ecx
    call asm_linux_send

    cmp rax, 5
    jne .fail_second_send

    ; Consume two more bytes: DE.
    mov rdi, r13
    lea rsi, [receive_buffer + 3]
    mov edx, 2
    call asm_linux_recv

    cmp rax, 2
    jne .fail_third_read

    ; Consume final three bytes: FGH.
    mov rdi, r13
    lea rsi, [receive_buffer + 5]
    mov edx, 3
    call asm_linux_recv

    cmp rax, 3
    jne .fail_fourth_read

    ; Reconstructed stream must equal ABCDEFGH.
    mov rax, [receive_buffer]
    mov rdx, [payload]

    cmp rax, rdx
    jne .fail_payload

    ; No write beyond the eight-byte buffer.
    cmp dword [receive_guard], 0xA5A5A5A5
    jne .fail_guard

    ; Half-close the sending direction.
    mov rdi, r12
    mov esi, SHUT_WR
    mov eax, SYS_SHUTDOWN
    syscall

    test rax, rax
    js .fail_shutdown

    ; With all data consumed, receiver must observe EOF.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 8
    call asm_linux_recv

    test rax, rax
    jne .fail_eof

    ; Buffer guard remains intact.
    cmp dword [receive_guard], 0xA5A5A5A5
    jne .fail_guard

    jmp .cleanup

.fail_socketpair:
    mov ebx, 11
    jmp .cleanup

.fail_eagain:
    mov ebx, 12
    jmp .cleanup

.fail_first_send:
    mov ebx, 13
    jmp .cleanup

.fail_first_read:
    mov ebx, 14
    jmp .cleanup

.fail_second_read:
    mov ebx, 15
    jmp .cleanup

.fail_payload:
    mov ebx, 16
    jmp .cleanup

.fail_second_send:
    mov ebx, 17
    jmp .cleanup

.fail_third_read:
    mov ebx, 18
    jmp .cleanup

.fail_fourth_read:
    mov ebx, 19
    jmp .cleanup

.fail_guard:
    mov ebx, 20
    jmp .cleanup

.fail_shutdown:
    mov ebx, 21
    jmp .cleanup

.fail_eof:
    mov ebx, 22

.cleanup:
    ; Close each owned descriptor exactly once.
    cmp r13, 0
    jl .close_sender

    mov rdi, r13
    call asm_linux_close

    test rax, rax
    jns .close_sender

    test ebx, ebx
    jnz .close_sender

    mov ebx, 23

.close_sender:
    cmp r12, 0
    jl .finish

    mov rdi, r12
    call asm_linux_close

    test rax, rax
    jns .finish

    test ebx, ebx
    jnz .finish

    mov ebx, 24

.finish:
    mov edi, ebx
    mov eax, SYS_EXIT
    syscall
    ud2
