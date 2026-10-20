bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/diagnostic.inc"

global _start

extern asm_diagnostic_init
extern asm_diagnostic_validate
extern asm_diagnostic_record_invariant
extern asm_linux_exit

section .bss

alignb 16
diagnostic:
    resb ASMWEB_DIAGNOSTIC_size

section .text

_start:
    cld

    ; CASE 1: null initialisation rejected.
    xor edi, edi
    call asm_diagnostic_init
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_1

    ; CASE 2: pristine initialisation succeeds.
    lea rdi, [rel diagnostic]
    call asm_diagnostic_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    ; CASE 3: empty initialised representation valid.
    lea rdi, [rel diagnostic]
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3

    ; CASE 4: repeated initialisation rejected.
    lea rdi, [rel diagnostic]
    call asm_diagnostic_init
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4

    ; CASE 5: zero failure code rejected atomically.
    lea rdi, [rel diagnostic]
    xor esi, esi
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.published], 0
    jne .fail_5

    ; CASE 6: code above defined range rejected.
    lea rdi, [rel diagnostic]
    mov esi, 12
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_6

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.domain], 0
    jne .fail_6

    ; CASE 7: supported failure recorded.
    lea rdi, [rel diagnostic]
    mov esi, 11
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7

    ; CASE 8: published structure validates.
    lea rdi, [rel diagnostic]
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.local_code], 11
    jne .fail_8

    ; CASE 9: second publication rejected, first preserved.
    lea rdi, [rel diagnostic]
    mov esi, 1
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.local_code], 11
    jne .fail_9

    ; CASE 10: corruption detected.
    mov qword [rel diagnostic + ASMWEB_DIAGNOSTIC.domain], 99

    lea rdi, [rel diagnostic]
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10

    ; CASE 11: corrupt publication cannot be overwritten.
    lea rdi, [rel diagnostic]
    mov esi, 2
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11

    cmp qword [rel diagnostic + ASMWEB_DIAGNOSTIC.domain], 99
    jne .fail_11

    ; CASE 12: null validation rejected.
    xor edi, edi
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12

    ; CASE 13: null recording rejected.
    xor edi, edi
    mov esi, 1
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13

    xor edi, edi
    call asm_linux_exit
    ud2

%macro FAIL_CASE 1
.fail_%1:
    mov edi, %1
    call asm_linux_exit
    ud2
%endmacro

FAIL_CASE 1
FAIL_CASE 2
FAIL_CASE 3
FAIL_CASE 4
FAIL_CASE 5
FAIL_CASE 6
FAIL_CASE 7
FAIL_CASE 8
FAIL_CASE 9
FAIL_CASE 10
FAIL_CASE 11
FAIL_CASE 12
FAIL_CASE 13
