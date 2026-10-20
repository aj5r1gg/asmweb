bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/diagnostic.inc"
%include "asmweb/runtime_invariant.inc"

global _start

extern asm_diagnostic_init
extern asm_diagnostic_validate
extern asm_runtime_ready_validate_diagnose
extern asm_linux_exit

section .bss

alignb 16
guard_before:
    resq 1

diagnostic:
    resb ASMWEB_DIAGNOSTIC_size

guard_after:
    resq 1

section .text

_start:
    cld

    mov rax, 0x1122334455667788
    mov [rel guard_before], rax

    mov rax, 0x8877665544332211
    mov [rel guard_after], rax

    ; CASE 1:
    ; Real validator returns INPUT failure for null view.
    ; An uninitialised diagnostic must not be published.

    xor edi, edi
    lea rsi, [rel diagnostic]

    call asm_runtime_ready_validate_diagnose

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_1

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    jne .fail_1

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.published], 0
    jne .fail_1

    ; CASE 2: initialise the caller-owned record.

    lea rdi, [rel diagnostic]
    call asm_diagnostic_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    ; CASE 3:
    ; Exercise the actual invariant validator's INPUT failure
    ; through the adapter and capture its code.

    xor edi, edi
    lea rsi, [rel diagnostic]

    call asm_runtime_ready_validate_diagnose

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_3

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    jne .fail_3

    ; CASE 4: published classification, domain, origin and code.

    lea rdi, [rel diagnostic]
    call asm_diagnostic_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.domain], \
        ASMWEB_DIAG_DOMAIN_RUNTIME_INVARIANT
    jne .fail_4

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.classification], \
        ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.origin], \
        ASMWEB_DIAG_ORIGIN_READY_VALIDATOR
    jne .fail_4

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.local_code], \
        ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    jne .fail_4

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.published], 1
    jne .fail_4

    ; CASE 5:
    ; Repeated validation cannot replace the first failure.
    ; The original validator RAX/RDX must still propagate.

    xor edi, edi
    lea rsi, [rel diagnostic]

    call asm_runtime_ready_validate_diagnose

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    jne .fail_5

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.local_code], \
        ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    jne .fail_5

    ; CASE 6:
    ; A null diagnostic pointer must not mask the validator's
    ; original integrity classification and failure code.

    xor edi, edi
    xor esi, esi

    call asm_runtime_ready_validate_diagnose

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_6

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    jne .fail_6

    ; CASE 7: adjacent storage remains intact.

    mov rax, 0x1122334455667788
    cmp [rel guard_before], rax
    jne .fail_7

    mov rax, 0x8877665544332211
    cmp [rel guard_after], rax
    jne .fail_7

    ; CASE 8: callee-saved preservation through the adapter.

    mov rbx, 0x1111222233334444
    mov rbp, 0x2222333344445555
    mov r12, 0x3333444455556666
    mov r13, 0x4444555566667777
    mov r14, 0x5555666677778888
    mov r15, 0x6666777788889999

    xor edi, edi
    lea rsi, [rel diagnostic]

    call asm_runtime_ready_validate_diagnose

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_8

    mov rax, 0x1111222233334444
    cmp rbx, rax
    jne .fail_8

    mov rax, 0x2222333344445555
    cmp rbp, rax
    jne .fail_8

    mov rax, 0x3333444455556666
    cmp r12, rax
    jne .fail_8

    mov rax, 0x4444555566667777
    cmp r13, rax
    jne .fail_8

    mov rax, 0x5555666677778888
    cmp r14, rax
    jne .fail_8

    mov rax, 0x6666777788889999
    cmp r15, rax
    jne .fail_8

    xor edi, edi
    call asm_linux_exit
    ud2

%macro FAIL_CASE 1
.fail_%1:
    cld
    mov edi, %1
    call asm_linux_exit
    ud2
%endmacro

%assign i 1
%rep 8
FAIL_CASE i
%assign i i+1
%endrep
