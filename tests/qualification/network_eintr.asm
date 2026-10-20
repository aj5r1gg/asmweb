bits 64
default rel

%include "linux/network.inc"

extern asm_linux_recv
extern asm_linux_send
extern asm_linux_close

global _start

%define SYS_WRITE        1
%define SYS_RT_SIGACTION 13
%define SYS_RT_SIGRETURN 15
%define SYS_SETITIMER    38
%define SYS_SOCKETPAIR   53
%define SYS_EXIT         60

%define AF_UNIX          1
%define SIGALRM          14
%define SA_RESTORER      0x04000000

section .data

descriptors:
    dd -1, -1

; Linux x86-64 kernel sigaction layout:
; handler, flags, restorer, 8-byte signal mask.
signal_action:
    dq 0                    ; Handler address set at runtime
    dq SA_RESTORER
    dq 0                    ; Restorer address set at runtime
    dq 0

signal_count:
    dq 0

ready:
    db 'R'

payload:
    db 'X'

receive_buffer:
    db 0xA5

receive_guard:
    dd 0xA5A5A5A5

; Linux x86-64 struct itimerval:
; interval (seconds, microseconds), then initial value.
; Repeat every 100 milliseconds until explicitly disarmed.
interrupt_timer:
    dq 0, 100000
    dq 0, 100000

disabled_timer:
    dq 0, 0
    dq 0, 0

section .text

_start:
    mov r12, -1
    mov r13, -1
    xor ebx, ebx

    ; Create a blocking stream socket pair.
    mov edi, AF_UNIX
    mov esi, LINUX_SOCK_STREAM | LINUX_SOCK_CLOEXEC
    xor edx, edx
    lea r10, [descriptors]
    mov eax, SYS_SOCKETPAIR
    syscall

    test rax, rax
    js .fail_socketpair

    mov r12d, [descriptors]
    mov r13d, [descriptors + 4]

    ; Populate function pointers with RIP-relative addresses.
    lea rax, [signal_handler]
    mov [signal_action], rax

    lea rax, [signal_restorer]
    mov [signal_action + 16], rax

    ; Install SIGALRM handler without SA_RESTART.
    mov edi, SIGALRM
    lea rsi, [signal_action]
    xor edx, edx
    mov r10d, 8
    mov eax, SYS_RT_SIGACTION
    syscall

    test rax, rax
    js .fail_sigaction

    ; Arm recurring kernel-generated SIGALRM signals.
    mov edi, 0                 ; ITIMER_REAL
    lea rsi, [interrupt_timer]
    xor edx, edx
    mov eax, SYS_SETITIMER
    syscall

    test rax, rax
    js .fail_ready

    ; No peer data exists. A timer signal must interrupt recv.
    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 1
    call asm_linux_recv

    ; Preserve the raw receive result while disabling the timer.
    mov r14, rax

    mov edi, 0                 ; ITIMER_REAL
    lea rsi, [disabled_timer]
    xor edx, edx
    mov eax, SYS_SETITIMER
    syscall

    test rax, rax
    js .fail_ready

    cmp r14, -4
    jne .fail_eintr

    ; At least one genuine signal handler invocation.
    cmp qword [signal_count], 1
    jb .fail_signal_count

    ; No data was delivered before interruption.
    cmp byte [receive_buffer], 0xA5
    jne .fail_buffer

    cmp dword [receive_guard], 0xA5A5A5A5
    jne .fail_buffer

    ; Verify the same socket still works after EINTR.
    mov rdi, r12
    lea rsi, [payload]
    mov edx, 1
    xor ecx, ecx
    call asm_linux_send

    cmp rax, 1
    jne .fail_recovery_send

    mov rdi, r13
    lea rsi, [receive_buffer]
    mov edx, 1
    call asm_linux_recv

    cmp rax, 1
    jne .fail_recovery_recv

    cmp byte [receive_buffer], 'X'
    jne .fail_buffer

    cmp dword [receive_guard], 0xA5A5A5A5
    jne .fail_buffer

    jmp .cleanup

.fail_socketpair:
    mov ebx, 11
    jmp .cleanup

.fail_sigaction:
    mov ebx, 12
    jmp .cleanup

.fail_ready:
    mov ebx, 13
    jmp .cleanup

.fail_eintr:
    mov ebx, 14
    jmp .cleanup

.fail_signal_count:
    mov ebx, 15
    jmp .cleanup

.fail_buffer:
    mov ebx, 16
    jmp .cleanup

.fail_recovery_send:
    mov ebx, 17
    jmp .cleanup

.fail_recovery_recv:
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
    jl .finish

    mov rdi, r12
    call asm_linux_close

    test rax, rax
    jns .finish

    test ebx, ebx
    jnz .finish
    mov ebx, 20

.finish:
    mov edi, ebx
    mov eax, SYS_EXIT
    syscall
    ud2

; Minimal signal handler.
signal_handler:
    inc qword [signal_count]
    ret

; Required Linux x86-64 signal-restoration trampoline.
signal_restorer:
    mov eax, SYS_RT_SIGRETURN
    syscall
    ud2
