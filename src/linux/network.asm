bits 64

%include "asmweb/abi.inc"
%include "linux/network.inc"

global asm_linux_socket
global asm_linux_bind
global asm_linux_listen
global asm_linux_accept
global asm_linux_accept4
global asm_linux_recv
global asm_linux_send
global asm_linux_recvfrom
global asm_linux_sendto
global asm_linux_recvmmsg
global asm_linux_sendmmsg
global asm_linux_recvmmsg_bounded
global asm_linux_sendmmsg_bounded
global asm_linux_close
global asm_linux_setsockopt
global asm_linux_getsockname
global asm_linux_getpeername

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

; accept4(fd, sockaddr*, socklen_t*, flags)
; RDI=listener, RSI=address or NULL
; RDX=address length pointer or NULL
; RCX=SOCK_NONBLOCK | SOCK_CLOEXEC flags
;
; Returns a newly owned descriptor or negative Linux errno.
; Flags apply to the accepted descriptor, not the listener.
; No implicit retry, allocation or error conversion.
asm_linux_accept4:
    mov r10, rcx
    mov eax, LINUX_SYS_accept4
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

; recvmmsg(fd, mmsghdr*, vlen, flags, timeout*)
; RDI=borrowed descriptor
; RSI=caller-owned mmsghdr array
; RDX=number of entries
; RCX=flags
; R8=timespec pointer or NULL
;
; Raw Linux syscall boundary: no allocation, validation,
; retry, timeout guarantee, or implicit result conversion.
; A positive RAX counts completed datagrams, not bytes.
; A zero result is not a stream EOF indication.
; Each completed entry has its own msg_len and metadata.
; Higher layers SHALL enforce finite batch capacity.
asm_linux_recvmmsg:
    mov r10, rcx
    mov eax, LINUX_SYS_recvmmsg
    syscall
    ret

; sendmmsg(fd, mmsghdr*, vlen, flags)
; RDI=borrowed descriptor
; RSI=caller-owned mmsghdr array
; RDX=number of entries
; RCX=flags
;
; MSG_NOSIGNAL is forced, matching asm_linux_sendto.
; RAX is the number of completed datagrams or negative errno.
; A positive short count does not expose a later errno.
; Successful entries expose their byte counts in msg_len.
; No allocation, validation, or implicit retry.
asm_linux_sendmmsg:
    mov r10, rcx
    or r10d, LINUX_MSG_NOSIGNAL
    mov eax, LINUX_SYS_sendmmsg
    syscall
    ret

; Bounded UDP batch entry points — provisional M1 boundary.
;
; Both functions retain their corresponding raw wrapper ABI.
; RDX must be in [1, ASMWEB_UDP_BATCH_MAX].
; RSI must reference a non-null caller-owned message array.
;
; Rejected arguments return -EINVAL without a syscall.
; Valid arguments delegate directly to the raw wrapper.
; Nested message/iovec memory is not validated here.
; No allocation, retry, socket ownership transfer or
; result conversion occurs.
;
; This is an initial finite-count boundary, NOT complete
; datagram descriptor qualification.

asm_linux_recvmmsg_bounded:
    test rsi, rsi
    jz .invalid
    test rdx, rdx
    jz .invalid
    cmp rdx, ASMWEB_UDP_BATCH_MAX
    ja .invalid
    jmp asm_linux_recvmmsg

.invalid:
    mov rax, -LINUX_EINVAL
    ret

asm_linux_sendmmsg_bounded:
    test rsi, rsi
    jz .invalid
    test rdx, rdx
    jz .invalid
    cmp rdx, ASMWEB_UDP_BATCH_MAX
    ja .invalid
    jmp asm_linux_sendmmsg

.invalid:
    mov rax, -LINUX_EINVAL
    ret

; getsockname(fd, sockaddr*, socklen_t*)
; RDI=descriptor
; RSI=writable address buffer
; RDX=in/out address length pointer
;
; Returns zero or negative Linux errno.
; Descriptor is borrowed; no allocation or implicit retry.
asm_linux_getsockname:
    mov eax, LINUX_SYS_getsockname
    syscall
    ret

; getpeername(fd, sockaddr*, socklen_t*)
; RDI=connected descriptor
; RSI=writable address buffer
; RDX=in/out address length pointer
;
; Returns zero or negative Linux errno.
; Descriptor is borrowed; no allocation or implicit retry.
asm_linux_getpeername:
    mov eax, LINUX_SYS_getpeername
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
