bits 64
default rel

%include "linux/network.inc"

extern asm_linux_socket
extern asm_linux_bind
extern asm_linux_listen
extern asm_linux_accept
extern asm_linux_accept4
extern asm_linux_recv
extern asm_linux_send
extern asm_linux_recvfrom
extern asm_linux_sendto
extern asm_linux_recvmmsg
extern asm_linux_sendmmsg
extern asm_linux_recvmmsg_bounded
extern asm_linux_sendmmsg_bounded
extern asm_linux_recvmmsg_checked
extern asm_linux_sendmmsg_checked
extern asm_linux_close
extern asm_linux_setsockopt
extern asm_linux_getsockname
extern asm_linux_getpeername

global _start

%define RBX_VALUE 0x1122334455667788
%define RBP_VALUE 0x2233445566778899
%define R12_VALUE 0x33445566778899aa
%define R13_VALUE 0x445566778899aabb
%define R14_VALUE 0x5566778899aabbcc
%define R15_VALUE 0x66778899aabbccdd

%macro CHECK_FAILURE_PATH 1
    mov rbx, RBX_VALUE
    mov rbp, RBP_VALUE
    mov r12, R12_VALUE
    mov r13, R13_VALUE
    mov r14, R14_VALUE
    mov r15, R15_VALUE
    mov rdi, -1
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call %1
    test rax, rax
    jns .fail
    mov rax, RBX_VALUE
    cmp rbx, rax
    jne .fail
    mov rax, RBP_VALUE
    cmp rbp, rax
    jne .fail
    mov rax, R12_VALUE
    cmp r12, rax
    jne .fail
    mov rax, R13_VALUE
    cmp r13, rax
    jne .fail
    mov rax, R14_VALUE
    cmp r14, rax
    jne .fail
    mov rax, R15_VALUE
    cmp r15, rax
    jne .fail
%endmacro

section .text
_start:
    CHECK_FAILURE_PATH asm_linux_socket
    CHECK_FAILURE_PATH asm_linux_bind
    CHECK_FAILURE_PATH asm_linux_listen
    CHECK_FAILURE_PATH asm_linux_accept
    CHECK_FAILURE_PATH asm_linux_accept4
    CHECK_FAILURE_PATH asm_linux_recv
    CHECK_FAILURE_PATH asm_linux_send
    CHECK_FAILURE_PATH asm_linux_recvfrom
    CHECK_FAILURE_PATH asm_linux_sendto
    CHECK_FAILURE_PATH asm_linux_recvmmsg
    CHECK_FAILURE_PATH asm_linux_sendmmsg
    CHECK_FAILURE_PATH asm_linux_recvmmsg_bounded
    CHECK_FAILURE_PATH asm_linux_sendmmsg_bounded
    CHECK_FAILURE_PATH asm_linux_recvmmsg_checked
    CHECK_FAILURE_PATH asm_linux_sendmmsg_checked
    CHECK_FAILURE_PATH asm_linux_close
    CHECK_FAILURE_PATH asm_linux_setsockopt
    CHECK_FAILURE_PATH asm_linux_getsockname
    CHECK_FAILURE_PATH asm_linux_getpeername
    xor edi, edi
    mov eax, 60
    syscall
.fail:
    mov edi, 1
    mov eax, 60
    syscall
