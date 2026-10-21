bits 64

%include "asmweb/abi.inc"
%include "asmweb/http_first.inc"
%include "asmweb/registry.inc"
%include "asmweb/production_registry.inc"
%include "asmweb/time.inc"
%include "linux/network.inc"

global asm_http_serve_once
global asm_http_serve_forever

%define ASMWEB_PAGE_MAX 4096
%define ASMWEB_PAGE_READ_CAP 4097
%define ASMWEB_HTTP_ACQUISITION_BUDGET_NS 3000000000
%define ASMWEB_HTTP_RESPONSE_BUDGET_NS 3000000000

extern asm_linux_socket
extern asm_linux_bind
extern asm_linux_listen
extern asm_linux_accept4
extern asm_production_registry_get
extern asm_linux_recv
extern asm_linux_send
extern asm_linux_close
extern asm_linux_setsockopt
extern asm_monotonic_now
extern asm_deadline_remaining

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

route_about:
    db '/about.html'
route_about_end:

route_style:
    db '/style.css'
route_style_end:

route_icon:
    db '/favicon.ico'
route_icon_end:

request_version:
    db ' HTTP/1.1', 13, 10
request_version_end:


; Local development document root.
; Launch AsmWeb from the repository directory.

web_root_path:
    db 'www', 0
page_path:
    db 'index.html', 0
page_path_about:
    db 'about.html', 0
page_path_style:
    db 'style.css', 0
page_path_icon:
    db 'favicon.ico', 0

page_prefix:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/html; charset=utf-8', 13, 10
    db 'Content-Length: '
page_prefix_end:

page_prefix_style:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/css; charset=utf-8', 13, 10
    db 'Content-Length: '
page_prefix_style_end:

page_prefix_icon:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: image/x-icon', 13, 10
    db 'Content-Length: '
page_prefix_icon_end:

page_suffix:
    db 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
page_suffix_end:

response_missing:
    db 'HTTP/1.1 404 Not Found', 13, 10
    db 'Content-Length: 0', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
response_missing_end:

response_file_error:
    db 'HTTP/1.1 500 Internal Server Error', 13, 10
    db 'Content-Length: 0', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
response_file_error_end:

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


align 16



align 16

align 16

section .bss
align 16
request_buffer:
    resb ASMWEB_M1_REQUEST_CAPACITY
serve_forever_mode:
    resb 1
selected_route:
    resb 1
alignb 8
selected_path_end:
    resq 1
page_buffer:
    resb ASMWEB_PAGE_READ_CAP
page_response:
    resb 4608
decimal_digits:
    resb 16

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
    ; Fixed 120-byte frame, preserving CALL alignment.
    ; [rsp+0]  = immutable request start (32 bytes)
    ; [rsp+32] = current time sample (32 bytes)
    ; [rsp+64] = remaining timeval (16 bytes)
    ; [rsp+80] = borrowed accepted-resource RCT entry (8 bytes)
    ; [rsp+88] = immutable response start (32 bytes)
    ; [rsp+120] = Linux x86-64 struct stat (144 bytes)
    ; [rsp+264] = owned document-root descriptor
    ; Total 280 bytes preserves CALL alignment.
    sub rsp, 280

    mov r12, -1
    mov r13, -1
    mov ebp, 1
    mov qword [rsp + 80], 0
    mov qword [rsp + 264], -1

    ; The currently implemented HTTP engine owns exactly one
    ; listener and processes exactly one accepted client at a
    ; time. Refuse to run with a conflicting published RCT.
    call asm_production_registry_get
    test rax, rax
    jz .cleanup

    cmp qword [rax + ASMWEB_REGISTRY_VALIDATION_SET.rct_count],         ASMWEB_PRODUCTION_RCT_COUNT
    jne .cleanup

    mov r10, [rax + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr]
    test r10, r10
    jz .cleanup

    cmp qword [r10 + ASMWEB_RCT_VALIDATION_ENTRY.resource_id],         ASMWEB_PROD_RESOURCE_HTTP_LISTENER
    jne .cleanup

    cmp qword [r10 + ASMWEB_RCT_VALIDATION_ENTRY.configured_capacity], 1
    jne .cleanup

    cmp qword [r10 + ASMWEB_RCT_VALIDATION_ENTRY.physical_capacity], 1
    jne .cleanup

    lea r11, [r10 + ASMWEB_RCT_VALIDATION_ENTRY_size]

    cmp qword [r11 + ASMWEB_RCT_VALIDATION_ENTRY.resource_id],         ASMWEB_PROD_RESOURCE_HTTP_ACCEPTED
    jne .cleanup

    cmp qword [r11 + ASMWEB_RCT_VALIDATION_ENTRY.configured_capacity], 1
    jne .cleanup

    cmp qword [r11 + ASMWEB_RCT_VALIDATION_ENTRY.physical_capacity], 1
    jne .cleanup

    ; Borrow the existing resource entry. No allocation.
    mov [rsp + 80], r11

    ; Open the document root once, as a real directory.
    ; O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY = 0xB0000.
    ; No symlink may substitute for the document root.
    mov eax, 257
    mov edi, -100
    lea rsi, [rel web_root_path]
    mov edx, 0xB0000
    xor r10d, r10d
    syscall

    test rax, rax
    js .cleanup

    mov [rsp + 264], rax

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

    ; The kernel backlog is derived from the admitted
    ; single-listener capacity, not an unrelated constant.
    mov rdi, r12
    mov esi, ASMWEB_M1_ACCEPTED_FD_CAPACITY
    call asm_linux_listen

    test rax, rax
    js .cleanup

.accept:
    ; R13 is the live-slot ownership marker:
    ; -1 = free; nonnegative = exactly one owned descriptor.
    ; Never acquire a second client while the slot is occupied.
    cmp r13, -1
    jne .cleanup

    mov r10, [rsp + 80]
    test r10, r10
    jz .cleanup

    cmp qword [r10 + ASMWEB_RCT_VALIDATION_ENTRY.configured_capacity], 1
    jne .cleanup

    cmp qword [r10 + ASMWEB_RCT_VALIDATION_ENTRY.physical_capacity], 1
    jne .cleanup

    mov rdi, r12
    xor esi, esi
    xor edx, edx
    mov ecx, LINUX_SOCK_CLOEXEC
    call asm_linux_accept4

    cmp rax, -4             ; EINTR
    je .accept

    test rax, rax
    js .cleanup

    mov r13, rax

    ; Capture the acquisition start exactly once per accepted client.
    ; This timestamp MUST NOT be refreshed by subsequent fragments.
    lea rdi, [rsp]
    call asm_monotonic_now
    test rax, rax
    jnz .drop_client

    mov rdi, r13
    mov esi, LINUX_SOL_SOCKET
    mov edx, LINUX_SO_SNDTIMEO
    lea rcx, [rel socket_timeout]
    mov r8d, 16
    call asm_linux_setsockopt

    test rax, rax
    js .drop_client

    xor r14d, r14d

.read:
    cmp r14, ASMWEB_M1_REQUEST_CAPACITY
    jae .too_large

    ; Recalculate against the immutable acceptance timestamp.
    ; EINTR and incomplete fragments both return through here.
    lea rdi, [rsp + 32]
    call asm_monotonic_now
    test rax, rax
    jnz .drop_client

    mov rdi, [rsp + ASMWEB_MONOTONIC_TIME.total_ns]
    mov rsi, [rsp + 32 + ASMWEB_MONOTONIC_TIME.total_ns]
    mov rdx, ASMWEB_HTTP_ACQUISITION_BUDGET_NS
    lea rcx, [rsp + 64]
    call asm_deadline_remaining
    test eax, eax
    jnz .drop_client

    ; SO_RCVTIMEO now represents the remaining absolute budget,
    ; rounded upwards by the qualified deadline arithmetic.
    mov rdi, r13
    mov esi, LINUX_SOL_SOCKET
    mov edx, LINUX_SO_RCVTIMEO
    lea rcx, [rsp + 64]
    mov r8d, 16
    call asm_linux_setsockopt
    test rax, rax
    js .drop_client

    mov rdi, r13
    lea rsi, [rel request_buffer]
    add rsi, r14
    mov edx, ASMWEB_M1_REQUEST_CAPACITY
    sub rdx, r14
    call asm_linux_recv

    cmp rax, -4             ; EINTR
    je .read

    test rax, rax
    js .drop_client

    test rax, rax
    jz .bad_request

    ; A successful recv is insufficient: it may have returned
    ; at or after the absolute deadline.
    mov r15, rax

    lea rdi, [rsp + 32]
    call asm_monotonic_now
    test rax, rax
    jnz .drop_client

    mov rdi, [rsp + ASMWEB_MONOTONIC_TIME.total_ns]
    mov rsi, [rsp + 32 + ASMWEB_MONOTONIC_TIME.total_ns]
    mov rdx, ASMWEB_HTTP_ACQUISITION_BUDGET_NS
    lea rcx, [rsp + 64]
    call asm_deadline_remaining
    test eax, eax
    jnz .drop_client

    add r14, r15

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
    ; Validate GET and the beginning of an origin-form target.
    cmp r14, 18
    jb .bad_request

    lea rsi, [rel request_buffer]
    cmp dword [rsi], 0x20544547       ; "GET "
    jne .bad_request
    cmp byte [rsi+4], '/'
    jne .bad_request

    ; Scan the request path within the received byte count.
    ; RBX records the end of the path, excluding any query.
    mov r10d, 4

.path_scan:
    cmp r10, r14
    jae .bad_request
    mov al, [rsi+r10]
    cmp al, ' '
    je .path_complete
    cmp al, '?'
    je .query_begin
    cmp al, 33
    jb .bad_request
    cmp al, 126
    ja .bad_request
    inc r10
    jmp .path_scan

.query_begin:
    mov rbx, r10
    inc r10

.query_scan:
    cmp r10, r14
    jae .bad_request
    mov al, [rsi+r10]
    cmp al, ' '
    je .target_complete
    cmp al, 33
    jb .bad_request
    cmp al, 126
    ja .bad_request
    inc r10
    jmp .query_scan

.path_complete:
    mov rbx, r10

.target_complete:
    ; Require precisely " HTTP/1.1" and CRLF after the target.
    lea rax, [r10 + request_version_end - request_version]
    cmp rax, r14
    ja .bad_request

    lea rsi, [rel request_buffer]
    lea rsi, [rsi+r10]
    lea rdi, [rel request_version]
    mov ecx, request_version_end - request_version
    repe cmpsb
    jne .bad_request

    ; RSI now points immediately after the validated request line.
    ; Derive the next-header offset from that position rather than
    ; retaining the request-target scan index.
    lea rax, [rel request_buffer]
    mov r9, rsi
    sub r9, rax

    mov [rel selected_path_end], rbx
    lea rsi, [rel request_buffer]
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
    ; Accept HTTP field-name tchar characters.
    cmp al, '-'
    je .name_valid
    cmp al, '_'
    je .name_valid
    cmp al, '!'
    je .name_valid
    cmp al, '#'
    je .name_valid
    cmp al, '$'
    je .name_valid
    cmp al, '%'
    je .name_valid
    cmp al, '&'
    je .name_valid
    cmp al, 39
    je .name_valid
    cmp al, '*'
    je .name_valid
    cmp al, '+'
    je .name_valid
    cmp al, '^'
    je .name_valid
    cmp al, '`'
    je .name_valid
    cmp al, '|'
    je .name_valid
    cmp al, '~'
    je .name_valid

    jmp .bad_request

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
    mov rbx, [rel selected_path_end]
    ; Dispatch against a fixed, traversal-free route table.
    ; 0=index, 1=about, 2=CSS, 3=icon, 4=missing.
    mov byte [rel selected_route], 4

    cmp rbx, 5
    jne .route_about_check
    mov byte [rel selected_route], 0
    jmp .route_complete

.route_about_check:
    cmp rbx, 4 + route_about_end - route_about
    jne .route_style_check
    lea rsi, [rel request_buffer+4]
    lea rdi, [rel route_about]
    mov ecx, route_about_end - route_about
    repe cmpsb
    jne .route_style_check
    mov byte [rel selected_route], 1
    jmp .route_complete

.route_style_check:
    cmp rbx, 4 + route_style_end - route_style
    jne .route_icon_check
    lea rsi, [rel request_buffer+4]
    lea rdi, [rel route_style]
    mov ecx, route_style_end - route_style
    repe cmpsb
    jne .route_icon_check
    mov byte [rel selected_route], 2
    jmp .route_complete

.route_icon_check:
    cmp rbx, 4 + route_icon_end - route_icon
    jne .route_complete
    lea rsi, [rel request_buffer+4]
    lea rdi, [rel route_icon]
    mov ecx, route_icon_end - route_icon
    repe cmpsb
    jne .route_complete
    mov byte [rel selected_route], 3

.route_complete:
    ; Preserve the existing one-shot response for internal callers.
    cmp byte [rel serve_forever_mode], 0
    je .accepted_legacy

    ; Select a fixed document-root resource.
    movzx eax, byte [rel selected_route]
    cmp eax, 4
    je .page_missing

    lea r14, [rel page_path]
    cmp eax, 0
    je .page_open
    lea r14, [rel page_path_about]
    cmp eax, 1
    je .page_open
    lea r14, [rel page_path_style]
    cmp eax, 2
    je .page_open
    lea r14, [rel page_path_icon]

    ; Open only relative to the already validated,
    ; permanently held document-root directory descriptor.
    ; Final symlinks are refused; nonregular files are
    ; rejected by the subsequent fstat check.
.page_open:
    mov eax, 257
    mov rdi, [rsp + 264]
    mov rsi, r14
    mov edx, 0xA0800
    xor r10d, r10d
    syscall

    cmp rax, -4                 ; EINTR
    je .page_open
    cmp rax, -2                 ; ENOENT
    je .page_missing
    test rax, rax
    js .page_error

    mov r15, rax                ; Owned file descriptor

    ; Verify the opened object, not merely its pathname.
    ; Linux x86-64 struct stat: st_mode is at offset 24.
    ; S_IFMT=0xF000 and S_IFREG=0x8000.
    ;
    ; This excludes directories, FIFOs, devices and sockets.
    ; A failed check consumes the descriptor through the
    ; existing .page_read_error cleanup path.
    mov eax, 5                 ; fstat
    mov rdi, r15
    lea rsi, [rsp + 120]
    syscall

    test rax, rax
    js .page_read_error

    mov eax, [rsp + 120 + 24]
    and eax, 0xF000
    cmp eax, 0x8000
    jne .page_read_error

    xor ebx, ebx               ; Accumulated file bytes

.page_read:
    cmp rbx, ASMWEB_PAGE_READ_CAP
    jae .page_read_finished

    xor eax, eax               ; read(2)
    mov rdi, r15
    lea rsi, [rel page_buffer]
    add rsi, rbx
    mov edx, ASMWEB_PAGE_READ_CAP
    sub rdx, rbx
    syscall

    cmp rax, -4
    je .page_read

    test rax, rax
    js .page_read_error
    jz .page_read_finished

    add rbx, rax
    jmp .page_read

.page_read_error:
    mov rdi, r15
    call asm_linux_close
    jmp .page_error

.page_read_finished:
    mov rdi, r15
    call asm_linux_close
    test rax, rax
    js .page_error

    ; Reject files that exceed the fixed page capacity.
    cmp rbx, ASMWEB_PAGE_MAX
    ja .page_error

    ; Construct the entire response in a bounded buffer.
    lea rdi, [rel page_response]
    cmp byte [rel selected_route], 2
    je .prefix_style
    cmp byte [rel selected_route], 3
    je .prefix_icon

    lea rsi, [rel page_prefix]
    mov ecx, page_prefix_end - page_prefix
    jmp .copy_prefix

.prefix_style:
    lea rsi, [rel page_prefix_style]
    mov ecx, page_prefix_style_end - page_prefix_style
    jmp .copy_prefix

.prefix_icon:
    lea rsi, [rel page_prefix_icon]
    mov ecx, page_prefix_icon_end - page_prefix_icon

.copy_prefix:
    rep movsb

    ; Convert the actual file length to decimal.
    mov rax, rbx
    lea r10, [rel decimal_digits + 16]

.page_decimal:
    xor edx, edx
    mov ecx, 10
    div rcx
    dec r10
    add dl, '0'
    mov [r10], dl
    test rax, rax
    jnz .page_decimal

    mov rsi, r10
    lea rcx, [rel decimal_digits + 16]
    sub rcx, r10
    rep movsb

    lea rsi, [rel page_suffix]
    mov ecx, page_suffix_end - page_suffix
    rep movsb

    lea rsi, [rel page_buffer]
    mov rcx, rbx
    rep movsb

    ; R15 = response pointer, RBX = response byte count.
    mov rbx, rdi
    lea r15, [rel page_response]
    sub rbx, r15
    jmp .send_begin

.page_missing:
    lea r15, [rel response_missing]
    mov ebx, response_missing_end - response_missing
    jmp .send_begin

.page_error:
    lea r15, [rel response_file_error]
    mov ebx, response_file_error_end - response_file_error
    jmp .send_begin

.accepted_legacy:
    lea r15, [rel response_ok]
    mov ebx, response_ok_end - response_ok
    jmp .send_begin

.bad_request:
    lea r15, [rel response_bad]
    mov ebx, response_bad_end - response_bad
    jmp .send_begin

.too_large:
    lea r15, [rel response_large]
    mov ebx, response_large_end - response_large

.send_begin:
    ; A response has ONE transmission deadline. It is not
    ; extended by successful partial sends or EINTR.
    lea rdi, [rsp + 88]
    call asm_monotonic_now
    test eax, eax
    jnz .drop_client

.send:
    test rbx, rbx
    jz .served

    ; Calculate the time remaining from the immutable
    ; response-start sample, not the previous send attempt.
    lea rdi, [rsp + 32]
    call asm_monotonic_now
    test eax, eax
    jnz .drop_client

    mov rdi, [rsp + 88 + ASMWEB_MONOTONIC_TIME.total_ns]
    mov rsi, [rsp + 32 + ASMWEB_MONOTONIC_TIME.total_ns]
    mov rdx, ASMWEB_HTTP_RESPONSE_BUDGET_NS
    lea rcx, [rsp + 64]
    call asm_deadline_remaining
    test eax, eax
    jnz .drop_client

    ; Bound this blocking syscall by the remaining total
    ; response budget. Reapply after every partial write.
    mov rdi, r13
    mov esi, LINUX_SOL_SOCKET
    mov edx, LINUX_SO_SNDTIMEO
    lea rcx, [rsp + 64]
    mov r8d, 16
    call asm_linux_setsockopt
    test rax, rax
    js .drop_client

    mov rdi, r13
    mov rsi, r15
    mov rdx, rbx
    xor ecx, ecx
    call asm_linux_send

    cmp rax, -4             ; EINTR
    je .send

    test rax, rax
    jle .drop_client

    ; Even a successful blocking send may have completed
    ; after expiry. Check before accepting its progress.
    mov r14, rax

    lea rdi, [rsp + 32]
    call asm_monotonic_now
    test eax, eax
    jnz .drop_client

    mov rdi, [rsp + 88 + ASMWEB_MONOTONIC_TIME.total_ns]
    mov rsi, [rsp + 32 + ASMWEB_MONOTONIC_TIME.total_ns]
    mov rdx, ASMWEB_HTTP_RESPONSE_BUDGET_NS
    lea rcx, [rsp + 64]
    call asm_deadline_remaining
    test eax, eax
    jnz .drop_client

    add r15, r14
    sub rbx, r14
    jmp .send

; A failed client must not terminate the persistent listener.
; In one-shot mode, retain the existing failure status.
.drop_client:
    cmp byte [rel serve_forever_mode], 0
    je .cleanup

    xor ebp, ebp
    jmp .cleanup

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
    ; Consume the owned document-root descriptor on every
    ; return path, including startup failure.
    mov rdi, [rsp + 264]
    cmp rdi, 0
    jl .return_complete

    call asm_linux_close
    mov qword [rsp + 264], -1
    test rax, rax
    jns .return_complete
    mov ebp, 1

.return_complete:
    mov eax, ebp
    add rsp, 280
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    cld
    ret
