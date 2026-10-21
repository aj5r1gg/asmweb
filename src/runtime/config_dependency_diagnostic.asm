bits 64

%include "asmweb/resource.inc"
%include "asmweb/diagnostic.inc"

global asm_capacity_dependency_validate_diagnose

extern asm_capacity_dependency_validate
extern asm_diagnostic_record_dependency

section .text

; Shared diagnostic adapter for an already-resolved capacity graph.
;
; RDI = nodes
; RSI = node count
; RDX = edges
; RCX = edge count
; R8  = caller-owned, initialised diagnostic pointer
;
; Returns the original validator RAX result.
; First integrity failure is offered to the shared diagnostic latch.
; Diagnostic refusal never masks the validator result.
;
; Caller ensures exclusive access to diagnostic storage.

asm_capacity_dependency_validate_diagnose:
    cld

    push rbx
    sub rsp, 16

    mov rbx, r8

    call asm_capacity_dependency_validate

    mov [rsp], rax

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .restore

    mov rdi, rbx
    call asm_diagnostic_record_dependency

.restore:
    mov rax, [rsp]

    add rsp, 16
    pop rbx
    ret
