bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/diagnostic.inc"

global asm_runtime_ready_validate_diagnose

extern asm_runtime_invariant_validate_ready
extern asm_diagnostic_record_invariant

section .text

; ---------------------------------------------------------------------------
; M0-DIAG-002 — READY invariant validation and diagnostic capture.
;
; RDI = borrowed ASMWEB_RUNTIME_INVARIANT_VIEW pointer
; RSI = caller-owned, initialised ASMWEB_DIAGNOSTIC pointer
;
; Returns:
;   RAX/RDX = exact result pair from the original READY validator.
;
; Integrity failures are offered to the first-failure latch.
; Failure of the diagnostic recorder does not replace or mask
; the original validator result.
;
; No ownership transfer, allocation, I/O or global state.
; Caller must ensure single-writer, non-concurrent access.
; ---------------------------------------------------------------------------

asm_runtime_ready_validate_diagnose:
    cld

    ; Preserve the diagnostic pointer across the validator call.
    ; Entry RSP % 16 == 8.
    ; One push and 16 local bytes leave RSP % 16 == 0
    ; before either nested call.

    push rbx
    sub rsp, 16

    mov rbx, rsi

    call asm_runtime_invariant_validate_ready

    ; Preserve the authoritative result before optional reporting.
    mov [rsp], rax
    mov [rsp + 8], rdx

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .restore

    mov rdi, rbx
    mov rsi, rdx
    call asm_diagnostic_record_invariant

.restore:
    mov rax, [rsp]
    mov rdx, [rsp + 8]

    add rsp, 16
    pop rbx

    ret
