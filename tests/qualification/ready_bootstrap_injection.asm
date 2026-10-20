bits 64

%include "asmweb/resource.inc"
%include "asmweb/diagnostic.inc"
%include "asmweb/runtime_invariant.inc"

global __wrap_asm_runtime_invariant_validate_ready
global __wrap_asm_diagnostic_record_invariant
global __wrap_asm_linux_exit

extern __real_asm_diagnostic_record_invariant
extern asm_diagnostic_validate

section .bss

alignb 8
observed: resq 1
captured: resq 1

section .text

; M0-DIAG-002:
; Qualification-only READY failure injection.
; Production source and object files remain unmodified.

__wrap_asm_runtime_invariant_validate_ready:
    cld
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_ENTROPY
    ret

__wrap_asm_diagnostic_record_invariant:
    cld

    push rbx
    push r12
    sub rsp, 8

    mov rbx, rdi
    mov r12, rsi

    mov qword [rel observed], 1

    test rbx, rbx
    jz diagnostic_observer_failure

    cmp r12, ASMWEB_RUNTIME_INVARIANT_FAIL_ENTROPY
    jne diagnostic_observer_failure

    cmp qword [rbx + ASMWEB_DIAGNOSTIC.ready], 1
    jne diagnostic_observer_failure

    cmp qword [rbx + ASMWEB_DIAGNOSTIC.published], 0
    jne diagnostic_observer_failure

%ifdef NEGATIVE
    ; Deliberately suppress publication.
    xor eax, eax
%else
    mov rdi, rbx
    mov rsi, r12
    call __real_asm_diagnostic_record_invariant

    cmp eax, ASMWEB_RESOURCE_OK
    jne diagnostic_observer_failure

    mov rdi, rbx
    call asm_diagnostic_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne diagnostic_observer_failure

    cmp qword [rbx + ASMWEB_DIAGNOSTIC.domain], \
        ASMWEB_DIAG_DOMAIN_RUNTIME_INVARIANT
    jne diagnostic_observer_failure

    cmp qword [rbx + ASMWEB_DIAGNOSTIC.classification], \
        ASMWEB_RESOURCE_INTEGRITY
    jne diagnostic_observer_failure

    cmp qword [rbx + ASMWEB_DIAGNOSTIC.origin], \
        ASMWEB_DIAG_ORIGIN_READY_VALIDATOR
    jne diagnostic_observer_failure

    cmp qword [rbx + ASMWEB_DIAGNOSTIC.local_code], \
        ASMWEB_RUNTIME_INVARIANT_FAIL_ENTROPY
    jne diagnostic_observer_failure

    cmp qword [rbx + ASMWEB_DIAGNOSTIC.published], 1
    jne diagnostic_observer_failure

    mov qword [rel captured], 1
    xor eax, eax
%endif

    add rsp, 8
    pop r12
    pop rbx
    ret

diagnostic_observer_failure:
    mov edi, 43
    jmp test_terminate

__wrap_asm_linux_exit:
    cld

    ; The actual production runtime must request failure exit 1.
    cmp edi, 1
    jne test_wrong_runtime_exit

    cmp qword [rel observed], 1
    jne test_no_record_call

    cmp qword [rel captured], 1
    jne test_missing_capture

    ; Exit 0 is the observer's PASS, not runtime success.
    xor edi, edi
    jmp test_terminate

test_wrong_runtime_exit:
    mov edi, 44
    jmp test_terminate

test_no_record_call:
    mov edi, 42
    jmp test_terminate

test_missing_capture:
    mov edi, 41

test_terminate:
    mov eax, 60
    syscall
    ud2
