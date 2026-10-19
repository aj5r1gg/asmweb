bits 64

%include "asmweb/registry.inc"
%include "asmweb/production_registry.inc"

; These identities and capacities come from the canonical
; production resource registry definitions, not from this test.
%if ASMWEB_PRODUCTION_RCT_COUNT != 2
    %error Unexpected production RCT population
%endif

%if ASMWEB_PROD_RESOURCE_HTTP_LISTENER != 0x30000001
    %error Unexpected HTTP listener resource identity
%endif

%if ASMWEB_PROD_RESOURCE_HTTP_ACCEPTED != 0x30000002
    %error Unexpected HTTP accepted resource identity
%endif

%if ASMWEB_M1_LISTENER_FD_CAPACITY != 1
    %error Unexpected listener descriptor capacity
%endif

%if ASMWEB_M1_ACCEPTED_FD_CAPACITY != 1
    %error Unexpected accepted descriptor capacity
%endif

%define QUAL_HTTP_FD_TOTAL_CAPACITY \
    (ASMWEB_M1_LISTENER_FD_CAPACITY + ASMWEB_M1_ACCEPTED_FD_CAPACITY)

; Qualification-only syscall substitution for the real HTTP handler.
; No production syscall implementation or HTTP handler is modified.
;
; Each successful socket/accept call grants a synthetic descriptor:
;   listener = 40
;   accepted = 41
;
; close() consumes ownership even when the simulated close result
; is negative. It must never be retried.
;
; Scenarios:
;   0: EOF -> HTTP 400 successfully sent, both descriptors closed
;   1: socket fails, no descriptors owned
;   2: bind fails, listener closed
;   3: accept fails, listener closed
;   4: receive fails, both descriptors closed
;   5: listener close reports error, no retry
;   6: accepted close reports error, no retry
;   7: listener setsockopt fails, listener closed
;   8: listen fails, listener closed
;   9: accepted setsockopt fails, both closed
;  10: send fails, both closed
;  11: accept EINTR once, then success
;  12: recv EINTR once, then EOF
;  13: send EINTR once, then success

global _start

global asm_linux_socket
global asm_linux_bind
global asm_linux_listen
global asm_linux_accept
global asm_linux_recv
global asm_linux_send
global asm_linux_close
global asm_linux_setsockopt

extern asm_http_serve_once

%define FD_LISTENER 40
%define FD_ACCEPTED 41
%define SCENARIO_COUNT 14

section .rodata

; Expected: return code, acquired, close attempts, high water,
;           close sequence (accepted=2, listener=1).
; A two-descriptor cleanup must produce sequence 21.
expected:
    dq 0, 2, 2, 2, 21
    dq 1, 0, 0, 0, 0
    dq 1, 1, 1, 1, 1
    dq 1, 1, 1, 1, 1
    dq 1, 2, 2, 2, 21
    dq 1, 2, 2, 2, 21
    dq 1, 2, 2, 2, 21
    dq 1, 1, 1, 1, 1
    dq 1, 1, 1, 1, 1
    dq 1, 2, 2, 2, 21
    dq 1, 2, 2, 2, 21
    dq 0, 2, 2, 2, 21
    dq 0, 2, 2, 2, 21
    dq 0, 2, 2, 2, 21

section .bss
align 8

; All mutable state belongs exclusively to this test binary.
state_begin:
scenario:       resq 1
listener_owned: resq 1
accepted_owned: resq 1
occupancy:      resq 1
high_water:     resq 1
acquisitions:   resq 1
close_attempts: resq 1
close_sequence: resq 1
violations:     resq 1
handler_return: resq 1
accept_interrupts: resq 1
recv_interrupts:   resq 1
send_interrupts:   resq 1
state_end:

section .text

_start:
    cld
    xor r15d, r15d

.case_loop:
    ; Reset the complete qualification state between scenarios.
    lea rdi, [rel state_begin]
    mov ecx, (state_end - state_begin) / 8
    xor eax, eax
    rep stosq

    mov [rel scenario], r15

    ; Real production handler, but qualification syscall wrappers.
    call asm_http_serve_once
    mov [rel handler_return], rax

    ; Determine expected row.
    mov rax, r15
    imul rax, 40
    lea rbx, [rel expected]
    add rbx, rax

    mov rax, [rel handler_return]
    cmp rax, [rbx]
    jne .fail

    mov rax, [rel acquisitions]
    cmp rax, [rbx + 8]
    jne .fail

    mov rax, [rel close_attempts]
    cmp rax, [rbx + 16]
    jne .fail

    mov rax, [rel high_water]
    cmp rax, [rbx + 24]
    jne .fail

    mov rax, [rel close_sequence]
    cmp rax, [rbx + 32]
    jne .fail

    cmp qword [rel listener_owned], 0
    jne .fail

    cmp qword [rel accepted_owned], 0
    jne .fail

    cmp qword [rel occupancy], 0
    jne .fail

    cmp qword [rel violations], 0
    jne .fail

    ; Independent bound, derived from production RCT definitions.
    cmp qword [rel high_water], QUAL_HTTP_FD_TOTAL_CAPACITY
    ja .fail

    ; Every original scenario must remain interruption-free.
    ; Each new scenario must exercise exactly its intended EINTR.
    xor eax, eax

    cmp r15, 11
    jne .check_recv_interrupts
    mov eax, 1

.check_recv_interrupts:
    cmp [rel accept_interrupts], rax
    jne .fail

    xor eax, eax
    cmp r15, 12
    jne .check_send_interrupts
    mov eax, 1

.check_send_interrupts:
    cmp [rel recv_interrupts], rax
    jne .fail

    xor eax, eax
    cmp r15, 13
    jne .interrupt_checks_done
    mov eax, 1

.interrupt_checks_done:
    cmp [rel send_interrupts], rax
    jne .fail

    inc r15
    cmp r15, SCENARIO_COUNT
    jb .case_loop

    xor edi, edi
    jmp .exit

.fail:
    ; Exit status identifies the failing scenario (1 through 7).
    lea rdi, [r15 + 1]

.exit:
    mov eax, 60
    syscall

; ------------------------------------------------------------------
; Simulated Linux network interface
; ------------------------------------------------------------------

asm_linux_socket:
    cmp qword [rel scenario], 1
    je .refuse

    cmp qword [rel listener_owned], 0
    jne .invalid

    mov qword [rel listener_owned], 1
    inc qword [rel acquisitions]
    inc qword [rel occupancy]

    cmp qword [rel listener_owned], ASMWEB_M1_LISTENER_FD_CAPACITY
    ja .invalid
    cmp qword [rel occupancy], QUAL_HTTP_FD_TOTAL_CAPACITY
    ja .invalid

    mov rax, [rel occupancy]
    cmp rax, [rel high_water]
    jbe .success
    mov [rel high_water], rax

.success:
    mov eax, FD_LISTENER
    ret

.invalid:
    inc qword [rel violations]
.refuse:
    mov rax, -24
    ret

asm_linux_bind:
    cmp rdi, FD_LISTENER
    jne .invalid
    cmp qword [rel listener_owned], 1
    jne .invalid
    cmp qword [rel scenario], 2
    je .refuse
    xor eax, eax
    ret

.invalid:
    inc qword [rel violations]
.refuse:
    mov rax, -98
    ret

asm_linux_listen:
    cmp rdi, FD_LISTENER
    jne .invalid
    cmp qword [rel listener_owned], 1
    jne .invalid

    cmp qword [rel scenario], 8
    je .refuse

    xor eax, eax
    ret

.refuse:
    mov rax, -5
    ret

.invalid:
    inc qword [rel violations]
    mov rax, -9
    ret

asm_linux_accept:
    cmp rdi, FD_LISTENER
    jne .invalid
    cmp qword [rel listener_owned], 1
    jne .invalid

    cmp qword [rel scenario], 3
    je .refuse

    cmp qword [rel scenario], 11
    jne .accept_normal

    cmp qword [rel accept_interrupts], 0
    jne .accept_normal

    inc qword [rel accept_interrupts]
    mov rax, -4                 ; EINTR
    ret

.accept_normal:
    cmp qword [rel accepted_owned], 0
    jne .invalid

    mov qword [rel accepted_owned], 1
    inc qword [rel acquisitions]
    inc qword [rel occupancy]

    cmp qword [rel accepted_owned], ASMWEB_M1_ACCEPTED_FD_CAPACITY
    ja .invalid
    cmp qword [rel occupancy], QUAL_HTTP_FD_TOTAL_CAPACITY
    ja .invalid

    mov rax, [rel occupancy]
    cmp rax, [rel high_water]
    jbe .success
    mov [rel high_water], rax

.success:
    mov eax, FD_ACCEPTED
    ret

.invalid:
    inc qword [rel violations]
.refuse:
    mov rax, -11
    ret

asm_linux_recv:
    cmp rdi, FD_ACCEPTED
    jne .invalid
    cmp qword [rel accepted_owned], 1
    jne .invalid

    cmp qword [rel scenario], 4
    je .refuse

    cmp qword [rel scenario], 12
    jne .recv_normal

    cmp qword [rel recv_interrupts], 0
    jne .recv_normal

    inc qword [rel recv_interrupts]
    mov rax, -4                 ; EINTR
    ret

.recv_normal:
    ; EOF: production handler generates its 400 response.
    xor eax, eax
    ret

.invalid:
    inc qword [rel violations]
.refuse:
    mov rax, -5
    ret

asm_linux_send:
    cmp rdi, FD_ACCEPTED
    jne .invalid
    cmp qword [rel accepted_owned], 1
    jne .invalid

    cmp qword [rel scenario], 10
    je .refuse

    cmp qword [rel scenario], 13
    jne .send_normal

    cmp qword [rel send_interrupts], 0
    jne .send_normal

    inc qword [rel send_interrupts]
    mov rax, -4                 ; EINTR
    ret

.send_normal:
    ; Simulate complete successful write of requested length.
    mov rax, rdx
    ret

.refuse:
    mov rax, -5
    ret

.invalid:
    inc qword [rel violations]
    mov rax, -9
    ret

asm_linux_setsockopt:
    cmp rdi, FD_LISTENER
    je .listener
    cmp rdi, FD_ACCEPTED
    je .accepted
    jmp .invalid

.listener:
    cmp qword [rel listener_owned], 1
    jne .invalid

    cmp qword [rel scenario], 7
    je .refuse

    xor eax, eax
    ret

.accepted:
    cmp qword [rel accepted_owned], 1
    jne .invalid

    cmp qword [rel scenario], 9
    je .refuse

    xor eax, eax
    ret

.refuse:
    mov rax, -5
    ret

.invalid:
    inc qword [rel violations]
    mov rax, -9
    ret

asm_linux_close:
    cmp rdi, FD_ACCEPTED
    je .close_accepted
    cmp rdi, FD_LISTENER
    je .close_listener
    jmp .invalid

.close_accepted:
    cmp qword [rel accepted_owned], 1
    jne .invalid

    mov qword [rel accepted_owned], 0
    mov r8d, 2
    jmp .record_close

.close_listener:
    cmp qword [rel listener_owned], 1
    jne .invalid

    mov qword [rel listener_owned], 0
    mov r8d, 1

.record_close:
    inc qword [rel close_attempts]
    dec qword [rel occupancy]

    mov rax, [rel close_sequence]
    imul rax, 10
    add rax, r8
    mov [rel close_sequence], rax

    cmp r8d, 1
    jne .check_accepted_close_error
    cmp qword [rel scenario], 5
    je .close_error
    jmp .close_success

.check_accepted_close_error:
    cmp qword [rel scenario], 6
    je .close_error

.close_success:
    xor eax, eax
    ret

.close_error:
    mov rax, -5
    ret

.invalid:
    inc qword [rel violations]
    mov rax, -9
    ret
