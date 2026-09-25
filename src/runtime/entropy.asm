bits 64

%include "asmweb/abi.inc"
%include "asmweb/startup.inc"
%include "asmweb/entropy.inc"

global asm_entropy_bootstrap

section .text

; asm_entropy_bootstrap
;
; Purpose:
;   Transfer Linux AT_RANDOM startup material into AsmWeb-owned state.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Input:
;   RDI = pointer to validated ASMWEB_STARTUP_INFO
;   RSI = pointer to writable ASMWEB_ENTROPY_BOOTSTRAP
;
; Result:
;   RAX = 0 on success
;   RAX = 1 on failure
;
; Success semantics:
;
;   - exactly 16 source bytes are copied;
;   - destination ready field becomes 1;
;   - startup_info.at_random becomes 0;
;   - the raw borrowed pointer is no longer authoritative.
;
; Failure semantics:
;
;   - if destination is non-NULL, the complete destination structure
;     is deterministically zeroed;
;   - startup_info.at_random is not consumed;
;   - RAX = 1.
;
; Ownership:
;   startup info       = MUTABLE_BORROW
;   AT_RANDOM bytes    = BORROWED
;   entropy bootstrap  = MUTABLE_BORROW
;
; Resource acquisition:
;   None.
;
; Blocking:
;   No.
;
; Callee-saved registers:
;   None modified.
;
; Direction flag:
;   Clear on return.

asm_entropy_bootstrap:
    cld

    ; Destination must exist before we can establish deterministic
    ; failure state.
    test rsi, rsi
    jz .failure_no_destination

    xor eax, eax

    mov [rsi + ASMWEB_ENTROPY_BOOTSTRAP.seed_lo], rax
    mov [rsi + ASMWEB_ENTROPY_BOOTSTRAP.seed_hi], rax
    mov [rsi + ASMWEB_ENTROPY_BOOTSTRAP.ready], rax

    test rdi, rdi
    jz .failure

    mov rdx, [rdi + ASMWEB_STARTUP_INFO.at_random]
    test rdx, rdx
    jz .failure

    ; Copy exactly the 16 bytes supplied by Linux AT_RANDOM.
    mov r8, [rdx]
    mov r9, [rdx + 8]

    mov [rsi + ASMWEB_ENTROPY_BOOTSTRAP.seed_lo], r8
    mov [rsi + ASMWEB_ENTROPY_BOOTSTRAP.seed_hi], r9

    mov qword [rsi + ASMWEB_ENTROPY_BOOTSTRAP.ready], 1

    ; Consume the borrowed startup pointer.
    mov qword [rdi + ASMWEB_STARTUP_INFO.at_random], 0

    xor eax, eax
    ret

.failure:
    mov eax, 1
    ret

.failure_no_destination:
    mov eax, 1
    ret
