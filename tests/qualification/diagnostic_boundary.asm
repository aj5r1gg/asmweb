bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/diagnostic.inc"

global _start

extern asm_diagnostic_init
extern asm_diagnostic_validate
extern asm_diagnostic_record_invariant
extern asm_linux_exit

section .rodata

invalid_codes:
    dq 0
    dq 12
    dq 0xffffffffffffffff
    dq 0x100000001

section .bss

alignb 16
guard_before: resq 1
record:       resb ASMWEB_DIAGNOSTIC_size
guard_after:  resq 1

section .text

%macro ASSERT_GUARDS 1
    mov rax, 0x1122334455667788
    cmp [rel guard_before], rax
    jne .fail_%1

    mov rax, 0x8877665544332211
    cmp [rel guard_after], rax
    jne .fail_%1
%endmacro

%macro RESET_RECORD 0
    lea rdi, [rel record]
    mov ecx, ASMWEB_DIAGNOSTIC_size / 8
    xor eax, eax
    cld
    rep stosq
%endmacro

%macro CHECK_EMPTY 1
    lea rdi, [rel record]
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_%1

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.published], 0
    jne .fail_%1

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.domain], 0
    jne .fail_%1

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.local_code], 0
    jne .fail_%1
%endmacro

_start:
    cld

    mov rax, 0x1122334455667788
    mov [rel guard_before], rax

    mov rax, 0x8877665544332211
    mov [rel guard_after], rax

    ; CASES 1-5: every valid failure code, 1..11.
    mov r12, 1

.valid_loop:
    RESET_RECORD

    lea rdi, [rel record]
    call asm_diagnostic_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1

    lea rdi, [rel record]
    mov rsi, r12
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    lea rdi, [rel record]
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3

    cmp [rel record + ASMWEB_DIAGNOSTIC.local_code], r12
    jne .fail_4

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.published], 1
    jne .fail_4

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.classification], \
        ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4

    ASSERT_GUARDS 5

    inc r12
    cmp r12, 12
    jb .valid_loop

    ; CASES 6-9: invalid full-width codes and canaries.
    xor r12d, r12d
    lea r13, [rel invalid_codes]

.invalid_loop:
    RESET_RECORD

    lea rdi, [rel record]
    call asm_diagnostic_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6

    lea rdi, [rel record]
    mov rsi, [r13 + r12 * 8]
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_7

    CHECK_EMPTY 8
    ASSERT_GUARDS 9

    inc r12
    cmp r12, 4
    jb .invalid_loop

    ; CASE 10: premature publication refused.
    RESET_RECORD

    lea rdi, [rel record]
    mov esi, 1
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.ready], 0
    jne .fail_10

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.published], 0
    jne .fail_10

    ; CASE 11: malformed empty record left unchanged.
    RESET_RECORD

    lea rdi, [rel record]
    call asm_diagnostic_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_11

    mov qword [rel record + ASMWEB_DIAGNOSTIC.origin], 99

    lea rdi, [rel record]
    mov esi, 3
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.origin], 99
    jne .fail_11

    cmp qword [rel record + ASMWEB_DIAGNOSTIC.published], 0
    jne .fail_11

    ; CASES 12-14: ABI callee-saved registers, DF, canaries.
    RESET_RECORD

    mov rbx, 0x1111222233334444
    mov rbp, 0x2222333344445555
    mov r12, 0x3333444455556666
    mov r13, 0x4444555566667777
    mov r14, 0x5555666677778888
    mov r15, 0x6666777788889999

    std
    lea rdi, [rel record]
    call asm_diagnostic_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_12

    std
    lea rdi, [rel record]
    mov esi, 11
    call asm_diagnostic_record_invariant
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_12

    std
    lea rdi, [rel record]
    call asm_diagnostic_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_12

    mov rax, 0x1111222233334444
    cmp rbx, rax
    jne .fail_13

    mov rax, 0x2222333344445555
    cmp rbp, rax
    jne .fail_13

    mov rax, 0x3333444455556666
    cmp r12, rax
    jne .fail_13

    mov rax, 0x4444555566667777
    cmp r13, rax
    jne .fail_13

    mov rax, 0x5555666677778888
    cmp r14, rax
    jne .fail_13

    mov rax, 0x6666777788889999
    cmp r15, rax
    jne .fail_13

    ASSERT_GUARDS 14

    xor edi, edi
    call asm_linux_exit
    ud2

%macro FAILURE 1
.fail_%1:
    cld
    mov edi, %1
    call asm_linux_exit
    ud2
%endmacro

%assign i 1
%rep 14
FAILURE i
%assign i i+1
%endrep
