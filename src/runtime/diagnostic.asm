bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/diagnostic.inc"

global asm_diagnostic_init
global asm_diagnostic_validate
global asm_diagnostic_record_invariant

section .text

; Initialise only an entirely zeroed object.
asm_diagnostic_init:
    cld

    test rdi, rdi
    jz .fail

    xor ecx, ecx

.check_pristine:
    cmp rcx, ASMWEB_DIAGNOSTIC_size / 8
    jae .publish

    cmp qword [rdi + rcx * 8], 0
    jne .fail

    inc rcx
    jmp .check_pristine

.publish:
    mov qword [rdi + ASMWEB_DIAGNOSTIC.ready], 1
    mov eax, ASMWEB_RESOURCE_OK
    ret

.fail:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; Validate both empty and published representations.
asm_diagnostic_validate:
    cld

    test rdi, rdi
    jz .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.ready], 1
    jne .fail

    mov rax, [rdi + ASMWEB_DIAGNOSTIC.published]

    test rax, rax
    jz .check_empty

    cmp rax, 1
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.domain], \
        ASMWEB_DIAG_DOMAIN_RUNTIME_INVARIANT
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.classification], \
        ASMWEB_RESOURCE_INTEGRITY
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.origin], \
        ASMWEB_DIAG_ORIGIN_READY_VALIDATOR
    jne .fail

    mov rax, [rdi + ASMWEB_DIAGNOSTIC.local_code]

    cmp rax, ASMWEB_DIAG_MIN_INVARIANT_CODE
    jb .fail

    cmp rax, ASMWEB_DIAG_MAX_INVARIANT_CODE
    ja .fail

    mov eax, ASMWEB_RESOURCE_OK
    ret

.check_empty:
    cmp qword [rdi + ASMWEB_DIAGNOSTIC.domain], 0
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.classification], 0
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.origin], 0
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.local_code], 0
    jne .fail

    mov eax, ASMWEB_RESOURCE_OK
    ret

.fail:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; Capture exactly one READY-state invariant integrity failure.
;
; All checks complete before any data field is written.
; published=1 is written last.
asm_diagnostic_record_invariant:
    cld

    test rdi, rdi
    jz .fail

    cmp rsi, ASMWEB_DIAG_MIN_INVARIANT_CODE
    jb .fail

    cmp rsi, ASMWEB_DIAG_MAX_INVARIANT_CODE
    ja .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.ready], 1
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.published], 0
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.domain], 0
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.classification], 0
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.origin], 0
    jne .fail

    cmp qword [rdi + ASMWEB_DIAGNOSTIC.local_code], 0
    jne .fail

    mov qword [rdi + ASMWEB_DIAGNOSTIC.domain], \
        ASMWEB_DIAG_DOMAIN_RUNTIME_INVARIANT

    mov qword [rdi + ASMWEB_DIAGNOSTIC.classification], \
        ASMWEB_RESOURCE_INTEGRITY

    mov qword [rdi + ASMWEB_DIAGNOSTIC.origin], \
        ASMWEB_DIAG_ORIGIN_READY_VALIDATOR

    mov [rdi + ASMWEB_DIAGNOSTIC.local_code], rsi

    mov qword [rdi + ASMWEB_DIAGNOSTIC.published], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret

.fail:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
