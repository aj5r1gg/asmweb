bits 64

%include "asmweb/registry.inc"
%include "asmweb/resource.inc"

global _start

extern asm_runtime_rules_init
extern asm_runtime_rules_get
extern asm_rrr_validate
extern asm_linux_exit


section .text

_start:
    cld


    ; =======================================================================
    ; CASE 1 — canonical RRR is not published before initialisation
    ; =======================================================================

    call asm_runtime_rules_get

    test rax, rax
    jnz .fail_1

    test rdx, rdx
    jnz .fail_1


    ; =======================================================================
    ; CASE 2 — canonical RRR materialises and validates
    ; =======================================================================

    call asm_runtime_rules_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — published canonical population is exactly 13
    ; =======================================================================

    call asm_runtime_rules_get

    test rax, rax
    jz .fail_3

    cmp rdx, 13
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — published canonical table independently passes RRR validator
    ; =======================================================================

    mov rdi, rax
    mov rsi, rdx

    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — every canonical entry has ACTIVE definition state
    ;          and bounded non-empty normative text
    ; =======================================================================

    call asm_runtime_rules_get

    mov r8, rax
    mov r9, rdx
    xor ecx, ecx

.entry_loop:
    cmp rcx, r9
    jae .entry_done

    mov rax, rcx
    imul rax, ASMWEB_RRR_VALIDATION_ENTRY_size
    jo .fail_5

    lea r10, [r8 + rax]

    cmp qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE
    jne .fail_5

    mov rax, [r10 + ASMWEB_RRR_VALIDATION_ENTRY.normative_statement_ptr]
    test rax, rax
    jz .fail_5

    mov rax, [r10 + ASMWEB_RRR_VALIDATION_ENTRY.normative_statement_length]
    test rax, rax
    jz .fail_5

    cmp rax, ASMWEB_M0_MAX_RULE_STATEMENT_BYTES
    ja .fail_5

    inc rcx
    jmp .entry_loop


.entry_done:

    ; =======================================================================
    ; CASE 6 — initialisation is repeatable and republishes valid authority
    ; =======================================================================

    call asm_runtime_rules_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6

    call asm_runtime_rules_get

    test rax, rax
    jz .fail_6

    cmp rdx, 13
    jne .fail_6


    xor edi, edi
    call asm_linux_exit
    ud2


.fail_1:
    mov edi, 1
    call asm_linux_exit
    ud2

.fail_2:
    mov edi, 2
    call asm_linux_exit
    ud2

.fail_3:
    mov edi, 3
    call asm_linux_exit
    ud2

.fail_4:
    mov edi, 4
    call asm_linux_exit
    ud2

.fail_5:
    mov edi, 5
    call asm_linux_exit
    ud2

.fail_6:
    mov edi, 6
    call asm_linux_exit
    ud2
