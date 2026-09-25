bits 64

%include "asmweb/abi.inc"
%include "asmweb/time.inc"
%include "linux/syscall.inc"

global asm_monotonic_now

extern asm_linux_clock_gettime

section .text

; asm_monotonic_now
;
; Purpose:
;   Obtain one normalized CLOCK_MONOTONIC sample and convert it to an
;   overflow-checked unsigned nanosecond representation.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Input:
;   RDI = pointer to writable ASMWEB_MONOTONIC_TIME
;
; Result:
;   RAX = 0 on success
;   RAX = 1 on failure
;
; Success invariants:
;
;   sec >= 0
;   0 <= nsec < 1,000,000,000
;   total_ns = sec * 1,000,000,000 + nsec without unsigned overflow
;   ready = 1
;
; Failure semantics:
;   Destination is deterministically zeroed when non-NULL.
;
; Clock semantics:
;   CLOCK_MONOTONIC is used directly through the Linux syscall boundary.
;
; Resource acquisition:
;   None.
;
; Blocking:
;   Kernel clock read only.
;
; Callee-saved registers:
;   RBX preserved.
;
; Direction flag:
;   Clear on return.

asm_monotonic_now:
    cld

    test rdi, rdi
    jz .failure_no_destination

    ; RBX is callee-saved under Internal ABI v1.
    push rbx

    ; Reserve:
    ;
    ;   16 bytes Linux timespec
    ;    8 bytes destination pointer
    ;    8 bytes reserved/padding
    ;
    ; RSP remains 16-byte aligned for the nested CALL.
    sub rsp, 32

    mov [rsp + 16], rdi

    ; Deterministically zero the destination before attempting acquisition.
    mov rbx, rdi
    xor eax, eax

    mov [rbx + ASMWEB_MONOTONIC_TIME.sec], rax
    mov [rbx + ASMWEB_MONOTONIC_TIME.nsec], rax
    mov [rbx + ASMWEB_MONOTONIC_TIME.total_ns], rax
    mov [rbx + ASMWEB_MONOTONIC_TIME.ready], rax

    mov edi, LINUX_CLOCK_MONOTONIC
    mov rsi, rsp
    call asm_linux_clock_gettime

    test rax, rax
    jnz .failure

    ; Kernel result.
    mov r8, [rsp]
    mov r9, [rsp + 8]

    ; Recover destination while the frame is still live.
    mov rbx, [rsp + 16]

    ; CLOCK_MONOTONIC seconds must be non-negative for this representation.
    test r8, r8
    js .failure

    ; tv_nsec must already be normalized.
    cmp r9, ASMWEB_NSEC_PER_SEC
    jae .failure

    ; Checked:
    ;
    ;   sec * 1,000,000,000 + nsec
    ;
    ; MUL produces RDX:RAX.
    mov rax, r8
    mov rcx, ASMWEB_NSEC_PER_SEC
    mul rcx

    test rdx, rdx
    jnz .failure

    add rax, r9
    jc .failure

    mov [rbx + ASMWEB_MONOTONIC_TIME.sec], r8
    mov [rbx + ASMWEB_MONOTONIC_TIME.nsec], r9
    mov [rbx + ASMWEB_MONOTONIC_TIME.total_ns], rax
    mov qword [rbx + ASMWEB_MONOTONIC_TIME.ready], 1

    add rsp, 32
    pop rbx

    xor eax, eax
    ret

.failure:
    ; Recover the destination pointer from the live frame. This remains
    ; valid regardless of which checked operation led here.
    mov rbx, [rsp + 16]

    xor eax, eax

    mov [rbx + ASMWEB_MONOTONIC_TIME.sec], rax
    mov [rbx + ASMWEB_MONOTONIC_TIME.nsec], rax
    mov [rbx + ASMWEB_MONOTONIC_TIME.total_ns], rax
    mov [rbx + ASMWEB_MONOTONIC_TIME.ready], rax

    add rsp, 32
    pop rbx

    mov eax, 1
    ret

.failure_no_destination:
    mov eax, 1
    ret
