bits 64

%include "asmweb/abi.inc"
%include "linux/network.inc"

global asm_linux_socket
global asm_linux_bind
global asm_linux_listen
global asm_linux_accept
global asm_linux_recv
global asm_linux_send
global asm_linux_recvfrom
global asm_linux_sendto
global asm_linux_close
global asm_linux_setsockopt

section .text

; AsmWeb Internal ABI v1.
;
; All functions return the raw Linux syscall result in RAX:
;   nonnegative: success
;   negative:    negative Linux errno
;
; All wrappers preserve RBX, RBP and R12-R15.
; RAX, RCX and R11 may be clobbered by SYSCALL.
;
; Descriptor ownership:
;   socket/accept return newly owned descriptors on success.
;   bind/listen/recv/send borrow the supplied descriptor.
;   close consumes the supplied descriptor.
;
; No wrapper allocates user-space memory.
; No wrapper retries or converts errors implicitly.

; socket(domain, type, protocol)
; RDI=domain, RSI=type, RDX=protocol
asm_linux_socket:
    mov eax, LINUX_SYS_socket
    syscall
    ret

; bind(fd, sockaddr*, sockaddr_length)
; RDI=fd, RSI=address, RDX=length
asm_linux_bind:
    mov eax, LINUX_SYS_bind
    syscall
    ret

; listen(fd, backlog)
; RDI=fd, RSI=backlog
asm_linux_listen:
    mov eax, LINUX_SYS_listen
    syscall
    ret

; accept(fd, sockaddr*, socklen_t*)
; RDI=fd, RSI=address or NULL, RDX=length pointer or NULL
asm_linux_accept:
    mov eax, LINUX_SYS_accept
    syscall
    ret

; recv(fd, buffer, length)
; RDI=fd, RSI=buffer, RDX=length
;
; Uses read(2) on the connected stream socket.
; Returns zero on peer EOF.
asm_linux_recv:
    mov eax, LINUX_SYS_read
    syscall
    ret

; send(fd, buffer, length, flags)
; RDI=fd, RSI=buffer, RDX=length, RCX=flags
;
; Uses sendto(2) with no destination address.
; MSG_NOSIGNAL is always enabled to prevent SIGPIPE.
; The caller must handle partial sends.
asm_linux_send:
    mov r10, rcx
    or r10d, LINUX_MSG_NOSIGNAL
    xor r8d, r8d
    xor r9d, r9d
    mov eax, LINUX_SYS_sendto
    syscall
    ret

; recvfrom(fd, buffer, length, flags, address, address_length*)
; RDI=fd, RSI=buffer, RDX=length, RCX=flags
; R8=source sockaddr buffer or NULL
; R9=source sockaddr length pointer or NULL
;
; Returns datagram length or negative Linux errno.
; The caller owns and bounds all buffers.
; The descriptor is borrowed.
asm_linux_recvfrom:
    mov r10, rcx
    mov eax, LINUX_SYS_recvfrom
    syscall
    ret

; sendto(fd, buffer, length, flags, address, address_length)
; RDI=fd, RSI=buffer, RDX=length, RCX=flags
; R8=destination sockaddr pointer
; R9=destination sockaddr length
;
; Returns bytes sent or negative Linux errno.
; MSG_NOSIGNAL is always enabled.
; The descriptor is borrowed.
asm_linux_sendto:
    mov r10, rcx
    or r10d, LINUX_MSG_NOSIGNAL
    mov eax, LINUX_SYS_sendto
    syscall
    ret

; close(fd)
; RDI=fd
;
; A negative return does not authorise blind retry:
; Linux close error handling must respect descriptor
; ownership and possible descriptor-number reuse.
asm_linux_close:
    mov eax, LINUX_SYS_close
    syscall
    ret

; setsockopt(fd, level, option, value*, value_length)
; RDI, RSI, RDX, RCX, R8 respectively.
asm_linux_setsockopt:
    mov r10, rcx
    mov eax, LINUX_SYS_setsockopt
    syscall
    ret
