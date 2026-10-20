bits 64

%include "asmweb/abi.inc"
%include "asmweb/http_first.inc"
%include "linux/network.inc"

global asm_http_serve_once
global asm_http_serve_forever

extern asm_linux_socket
extern asm_linux_bind
extern asm_linux_listen
extern asm_linux_accept
extern asm_linux_recv
extern asm_linux_send
extern asm_linux_close
extern asm_linux_setsockopt

section .rodata

; sockaddr_in: AF_INET, port 18080 in network byte order,
; 127.0.0.1, and zero padding.
align 8
listen_address:
    dw LINUX_AF_INET
    db 0x46, 0xA0
    db 127, 0, 0, 1
    dq 0

; Linux timeval: 3 seconds, 0 microseconds.
align 8
socket_timeout:
    dq 3, 0

align 4
reuse_address:
    dd 1

; Supported request line.
request_line:
    db 'GET / HTTP/1.1', 13, 10
request_line_end:


response_ok:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/plain', 13, 10
    db 'Content-Length: 7', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
    db 'AsmWeb', 10
response_ok_end:

response_bad:
    db 'HTTP/1.1 400 Bad Request', 13, 10
    db 'Content-Type: text/plain', 13, 10
    db 'Content-Length: 12', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
    db 'Bad Request', 10
response_bad_end:

response_large:
    db 'HTTP/1.1 431 Request Header Fields Too Large', 13, 10
    db 'Content-Type: text/plain', 13, 10
    db 'Content-Length: 17', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
    db 'Header Too Large', 10
response_large_end:

section .bss

align 16
request_buffer:
    resb ASMWEB_M1_REQUEST_CAPACITY

serve_forever_mode:
    resb 1

section .text

; asm_http_serve_once
;
; Internal ABI v1:
;   Inputs: none
;   RAX: 0 on successful handling, 1 on local failure.
;   Preserves RBX, RBP, R12-R15 and clears DF.
;
; M1 experimental constraints:
;   IPv4 loopback only.
;   One listener, one connection, then exit.
;   Maximum 1024 received header bytes.
;   Exactly one supported request line: GET / HTTP/1.1.
;   Fixed responses and Connection: close.
;
; This is not a general HTTP/1.1 parser.
; A full HTTP header grammar, Host validation, request bodies,
; persistence and pipelining are NOT implemented here.
;
; Descriptor ownership:
;   R12 = listener, R13 = accepted connection.
;   Both start as invalid and are closed during cleanup.
;
; The temporary fixed request buffer must be included in
; subsequent canonical memory/resource registry integration.

asm_http_serve_forever:
    mov byte [rel serve_forever_mode], 1
    jmp asm_http_serve_common

asm_http_serve_once:
    mov byte [rel serve_forever_mode], 0

asm_http_serve_common:
    cld

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov r12, -1
    mov r13, -1
    mov ebp, 1

    ; socket(AF_INET, SOCK_STREAM|CLOEXEC, IPPROTO_TCP)
    mov edi, LINUX_AF_INET
    mov esi, LINUX_SOCK_STREAM | LINUX_SOCK_CLOEXEC
    mov edx, LINUX_IPPROTO_TCP
    call asm_linux_socket

    test rax, rax
    js .cleanup

    mov r12, rax

    ; Permit immediate listener restart after previous connections.
    ; SO_REUSEADDR must be configured before bind().
    mov rdi, r12
    mov esi, LINUX_SOL_SOCKET
    mov edx, LINUX_SO_REUSEADDR
    lea rcx, [rel reuse_address]
    mov r8d, 4
    call asm_linux_setsockopt

    test rax, rax
    js .cleanup

    ; bind(listener, 127.0.0.1:18080)
    mov rdi, r12
    lea rsi, [rel listen_address]
    mov edx, 16
    call asm_linux_bind

    test rax, rax
    js .cleanup

    ; Listen for one queued connection.
    mov rdi, r12
    mov esi, 1
    call asm_linux_listen

    test rax, rax
    js .cleanup

.accept:
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    call asm_linux_accept

    cmp rax, -4             ; EINTR
    je .accept

    test rax, rax
    js .cleanup

    mov r13, rax

    ; Bound idle receive/send blocking on the accepted socket.
    mov rdi, r13
    mov esi, LINUX_SOL_SOCKET
    mov edx, LINUX_SO_RCVTIMEO
    lea rcx, [rel socket_timeout]
    mov r8d, 16
    call asm_linux_setsockopt

    test rax, rax
    js .cleanup

    mov rdi, r13
    mov esi, LINUX_SOL_SOCKET
    mov edx, LINUX_SO_SNDTIMEO
    lea rcx, [rel socket_timeout]
    mov r8d, 16
    call asm_linux_setsockopt

    test rax, rax
    js .cleanup

    xor r14d, r14d

.read:
    cmp r14, ASMWEB_M1_REQUEST_CAPACITY
    jae .too_large

    mov rdi, r13
    lea rsi, [rel request_buffer]
    add rsi, r14
    mov edx, ASMWEB_M1_REQUEST_CAPACITY
    sub rdx, r14
    call asm_linux_recv

    cmp rax, -4             ; EINTR
    je .read

    test rax, rax
    js .cleanup

    test rax, rax
    jz .bad_request

    add r14, rax

    ; Search bounded received bytes for CRLF CRLF.
    cmp r14, 4
    jb .read

    lea rsi, [rel request_buffer]
    mov ecx, 4

.scan:
    mov eax, [rsi + rcx - 4]
    cmp eax, 0x0a0d0a0d
    je .complete

    inc rcx
    cmp rcx, r14
    jbe .scan

    jmp .read

.complete:
    ; Check supported request line.
    cmp r14, request_line_end - request_line + 2
    jb .bad_request

    lea rsi, [rel request_buffer]
    lea rdi, [rel request_line]
    mov ecx, request_line_end - request_line
    repe cmpsb
    jne .bad_request

    lea rsi, [rel request_buffer]
    mov r9d, request_line_end - request_line
    xor r8d, r8d

.header_next:
    cmp r9, r14
    jae .bad_request

    cmp byte [rsi+r9], 13
    jne .header_name

    lea r10, [r9+2]
    cmp r10, r14
    jne .bad_request
    cmp byte [rsi+r9+1], 10
    jne .bad_request
    test r8d, r8d
    jz .bad_request
    jmp .accepted

.header_name:
    mov r10, r9

.name_char:
    cmp r10, r14
    jae .bad_request

    movzx eax, byte [rsi+r10]
    cmp al, ':'
    je .colon

    cmp al, 'A'
    jb .digit
    cmp al, 'Z'
    jbe .name_valid

    cmp al, 'a'
    jb .digit
    cmp al, 'z'
    jbe .name_valid

.digit:
    cmp al, '0'
    jb .hyphen
    cmp al, '9'
    jbe .name_valid

.hyphen:
    cmp al, '-'
    jne .bad_request

.name_valid:
    inc r10
    jmp .name_char

.colon:
    cmp r10, r9
    je .bad_request

    mov r11, r10
    sub r11, r9
    cmp r11, 4
    jne .header_value

    mov eax, [rsi+r9]
    or eax, 0x20202020
    cmp eax, 0x74736f68
    jne .header_value

    ; Exactly one Host header.
    test r8d, r8d
    jnz .bad_request
    mov r8d, 1

    lea r11, [r10+1]

.host_value:
    cmp r11, r14
    jae .bad_request

    mov al, [rsi+r11]
    cmp al, ' '
    je .host_space
    cmp al, 9
    je .host_space
    cmp al, 13
    je .bad_request
    jmp .header_value

.host_space:
    inc r11
    jmp .host_value

.header_value:
    inc r10

.value_char:
    cmp r10, r14
    jae .bad_request

    movzx eax, byte [rsi+r10]
    cmp al, 13
    je .line_end

    cmp al, 9
    je .value_valid
    cmp al, 32
    jb .bad_request
    cmp al, 126
    ja .bad_request

.value_valid:
    inc r10
    jmp .value_char

.line_end:
    lea r11, [r10+1]
    cmp r11, r14
    jae .bad_request

    cmp byte [rsi+r11], 10
    jne .bad_request

    lea r9, [r10+2]
    jmp .header_next

.accepted:
    lea r15, [rel response_ok]
    mov ebx, response_ok_end - response_ok
    jmp .send

.bad_request:
    lea r15, [rel response_bad]
    mov ebx, response_bad_end - response_bad
    jmp .send

.too_large:
    lea r15, [rel response_large]
    mov ebx, response_large_end - response_large

.send:
    test rbx, rbx
    jz .served

    mov rdi, r13
    mov rsi, r15
    mov rdx, rbx
    xor ecx, ecx
    call asm_linux_send

    cmp rax, -4             ; EINTR
    je .send

    test rax, rax
    jle .cleanup

    add r15, rax
    sub rbx, rax
    jmp .send

.served:
    xor ebp, ebp

.cleanup:
    cmp r13, 0
    jl .close_listener

    mov rdi, r13
    call asm_linux_close
    mov r13, -1

    test rax, rax
    js .client_close_failure

    test ebp, ebp
    jnz .close_listener

    cmp byte [rel serve_forever_mode], 0
    jne .accept

    jmp .close_listener

.client_close_failure:
    mov ebp, 1

.close_listener:
    cmp r12, 0
    jl .return

    mov rdi, r12
    call asm_linux_close

    test rax, rax
    jns .return
    mov ebp, 1

.return:
    mov eax, ebp
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    cld
    ret
