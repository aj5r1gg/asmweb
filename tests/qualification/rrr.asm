bits 64

%include "asmweb/registry.inc"
%include "asmweb/resource.inc"

global _start

extern asm_rrr_validate
extern asm_linux_exit


section .rodata

rule_gov:
    db "MEM-GOV-AUTHORITY"
rule_gov_len equ $ - rule_gov

rule_life:
    db "MEM-LIFE-TERMINAL"
rule_life_len equ $ - rule_life

rule_cap:
    db "MEM-CAP-REGISTERED-ACQUISITION"
rule_cap_len equ $ - rule_cap

rule_duplicate:
    db "MEM-GOV-AUTHORITY"
rule_duplicate_len equ $ - rule_duplicate

rule_bad_prefix:
    db "RAM-GOV-AUTHORITY"
rule_bad_prefix_len equ $ - rule_bad_prefix

rule_bad_namespace:
    db "MEM-CAP-AUTHORITY"
rule_bad_namespace_len equ $ - rule_bad_namespace

rule_bad_character:
    db "MEM-GOV-Bad"
rule_bad_character_len equ $ - rule_bad_character

rule_trailing_hyphen:
    db "MEM-GOV-AUTHORITY-"
rule_trailing_hyphen_len equ $ - rule_trailing_hyphen

rule_double_hyphen:
    db "MEM-GOV--AUTHORITY"
rule_double_hyphen_len equ $ - rule_double_hyphen

rule_too_long:
    db "MEM-GOV-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
rule_too_long_len equ $ - rule_too_long


; Canonical positive fixture for every Runtime & Memory namespace.
ns_gov:
    db "MEM-GOV-X"
ns_gov_len equ $ - ns_gov

ns_obj:
    db "MEM-OBJ-X"
ns_obj_len equ $ - ns_obj

ns_pol:
    db "MEM-POL-X"
ns_pol_len equ $ - ns_pol

ns_cap:
    db "MEM-CAP-X"
ns_cap_len equ $ - ns_cap

ns_own:
    db "MEM-OWN-X"
ns_own_len equ $ - ns_own

ns_life:
    db "MEM-LIFE-X"
ns_life_len equ $ - ns_life

ns_buf:
    db "MEM-BUF-X"
ns_buf_len equ $ - ns_buf

ns_asy:
    db "MEM-ASY-X"
ns_asy_len equ $ - ns_asy

ns_evt:
    db "MEM-EVT-X"
ns_evt_len equ $ - ns_evt

ns_tmr:
    db "MEM-TMR-X"
ns_tmr_len equ $ - ns_tmr

ns_acc:
    db "MEM-ACC-X"
ns_acc_len equ $ - ns_acc

ns_prs:
    db "MEM-PRS-X"
ns_prs_len equ $ - ns_prs

ns_ext:
    db "MEM-EXT-X"
ns_ext_len equ $ - ns_ext

ns_cfg:
    db "MEM-CFG-X"
ns_cfg_len equ $ - ns_cfg

ns_qui:
    db "MEM-QUI-X"
ns_qui_len equ $ - ns_qui

ns_sec:
    db "MEM-SEC-X"
ns_sec_len equ $ - ns_sec

ns_qua:
    db "MEM-QUA-X"
ns_qua_len equ $ - ns_qua

ns_chg:
    db "MEM-CHG-X"
ns_chg_len equ $ - ns_chg


section .bss

align 8

valid_entries:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size * 3

duplicate_entries:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size * 2

bad_prefix_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

bad_namespace_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

bad_status_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

bad_qual_state_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

bad_character_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

trailing_hyphen_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

double_hyphen_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

zero_length_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

too_long_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size

namespace_entries:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size * 18

bad_numeric_namespace_entry:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size


section .text


%macro INIT_RRR_ENTRY 6
    lea r10, [rel %1]
    lea rax, [rel %2]

    mov [r10 + ASMWEB_RRR_VALIDATION_ENTRY.rule_id_ptr], rax
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.rule_id_length], %3
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.namespace], %4
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.status], %5
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.qualification_state], %6
%endmacro


_start:
    cld

    ; -----------------------------------------------------------------------
    ; Build valid three-entry registry.
    ; -----------------------------------------------------------------------

    INIT_RRR_ENTRY \
        valid_entries, \
        rule_gov, \
        rule_gov_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        valid_entries + ASMWEB_RRR_VALIDATION_ENTRY_size, \
        rule_life, \
        rule_life_len, \
        ASMWEB_RRR_NAMESPACE_LIFE, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_QUALIFICATION_PENDING

    INIT_RRR_ENTRY \
        valid_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 2, \
        rule_cap, \
        rule_cap_len, \
        ASMWEB_RRR_NAMESPACE_CAP, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_NOT_STARTED

    ; Duplicate identity registry.
    INIT_RRR_ENTRY \
        duplicate_entries, \
        rule_gov, \
        rule_gov_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        duplicate_entries + ASMWEB_RRR_VALIDATION_ENTRY_size, \
        rule_duplicate, \
        rule_duplicate_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        bad_prefix_entry, \
        rule_bad_prefix, \
        rule_bad_prefix_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        bad_namespace_entry, \
        rule_bad_namespace, \
        rule_bad_namespace_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        bad_status_entry, \
        rule_gov, \
        rule_gov_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        0, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        bad_qual_state_entry, \
        rule_gov, \
        rule_gov_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        0

    INIT_RRR_ENTRY \
        bad_character_entry, \
        rule_bad_character, \
        rule_bad_character_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        trailing_hyphen_entry, \
        rule_trailing_hyphen, \
        rule_trailing_hyphen_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        double_hyphen_entry, \
        rule_double_hyphen, \
        rule_double_hyphen_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    ; Zero-length fixture: pointer is valid but explicit length is invalid.
    lea r10, [rel zero_length_entry]
    lea rax, [rel rule_gov]

    mov [r10 + ASMWEB_RRR_VALIDATION_ENTRY.rule_id_ptr], rax
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.namespace], \
        ASMWEB_RRR_NAMESPACE_GOV
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.qualification_state], \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        too_long_entry, \
        rule_too_long, \
        rule_too_long_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED


    ; -----------------------------------------------------------------------
    ; Complete namespace-dispatch qualification set.
    ; -----------------------------------------------------------------------

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 0, \
        ns_gov, ns_gov_len, \
        ASMWEB_RRR_NAMESPACE_GOV, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 1, \
        ns_obj, ns_obj_len, \
        ASMWEB_RRR_NAMESPACE_OBJ, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 2, \
        ns_pol, ns_pol_len, \
        ASMWEB_RRR_NAMESPACE_POL, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 3, \
        ns_cap, ns_cap_len, \
        ASMWEB_RRR_NAMESPACE_CAP, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 4, \
        ns_own, ns_own_len, \
        ASMWEB_RRR_NAMESPACE_OWN, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 5, \
        ns_life, ns_life_len, \
        ASMWEB_RRR_NAMESPACE_LIFE, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 6, \
        ns_buf, ns_buf_len, \
        ASMWEB_RRR_NAMESPACE_BUF, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 7, \
        ns_asy, ns_asy_len, \
        ASMWEB_RRR_NAMESPACE_ASY, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 8, \
        ns_evt, ns_evt_len, \
        ASMWEB_RRR_NAMESPACE_EVT, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 9, \
        ns_tmr, ns_tmr_len, \
        ASMWEB_RRR_NAMESPACE_TMR, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 10, \
        ns_acc, ns_acc_len, \
        ASMWEB_RRR_NAMESPACE_ACC, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 11, \
        ns_prs, ns_prs_len, \
        ASMWEB_RRR_NAMESPACE_PRS, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 12, \
        ns_ext, ns_ext_len, \
        ASMWEB_RRR_NAMESPACE_EXT, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 13, \
        ns_cfg, ns_cfg_len, \
        ASMWEB_RRR_NAMESPACE_CFG, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 14, \
        ns_qui, ns_qui_len, \
        ASMWEB_RRR_NAMESPACE_QUI, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 15, \
        ns_sec, ns_sec_len, \
        ASMWEB_RRR_NAMESPACE_SEC, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 16, \
        ns_qua, ns_qua_len, \
        ASMWEB_RRR_NAMESPACE_QUA, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    INIT_RRR_ENTRY \
        namespace_entries + ASMWEB_RRR_VALIDATION_ENTRY_size * 17, \
        ns_chg, ns_chg_len, \
        ASMWEB_RRR_NAMESPACE_CHG, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED

    ; Structurally valid textual rule with invalid numeric namespace.
    INIT_RRR_ENTRY \
        bad_numeric_namespace_entry, \
        ns_gov, ns_gov_len, \
        ASMWEB_RRR_NAMESPACE_MAX + 1, \
        ASMWEB_REGISTRY_STATUS_ACTIVE, \
        ASMWEB_QUAL_STATE_IMPLEMENTED


    ; =======================================================================
    ; CASE 1 — coherent mixed-namespace RRR passes
    ; =======================================================================

    lea rdi, [rel valid_entries]
    mov esi, 3
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — canonical empty RRR accepted
    ; =======================================================================

    xor edi, edi
    xor esi, esi
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — non-NULL pointer with zero count rejected
    ; =======================================================================

    lea rdi, [rel valid_entries]
    xor esi, esi
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — NULL pointer with non-zero count rejected
    ; =======================================================================

    xor edi, edi
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — bounded registry count enforced before traversal
    ; =======================================================================

    lea rdi, [rel valid_entries]
    mov esi, ASMWEB_M0_MAX_RRR_ENTRIES + 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — duplicate textual rule identity rejected
    ; =======================================================================

    lea rdi, [rel duplicate_entries]
    mov esi, 2
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — wrong MEM prefix rejected
    ; =======================================================================

    lea rdi, [rel bad_prefix_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_7


    ; =======================================================================
    ; CASE 8 — encoded namespace/text mismatch rejected
    ; =======================================================================

    lea rdi, [rel bad_namespace_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — invalid lifecycle state rejected
    ; =======================================================================

    lea rdi, [rel bad_status_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9


    ; =======================================================================
    ; CASE 10 — invalid qualification state rejected
    ; =======================================================================

    lea rdi, [rel bad_qual_state_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10


    ; =======================================================================
    ; CASE 11 — lowercase/invalid identity character rejected
    ; =======================================================================

    lea rdi, [rel bad_character_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11


    ; =======================================================================
    ; CASE 12 — trailing hyphen rejected
    ; =======================================================================

    lea rdi, [rel trailing_hyphen_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12


    ; =======================================================================
    ; CASE 13 — consecutive hyphens rejected
    ; =======================================================================

    lea rdi, [rel double_hyphen_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13


    ; =======================================================================
    ; CASE 14 — zero-length identity rejected
    ; =======================================================================

    lea rdi, [rel zero_length_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14


    ; =======================================================================
    ; CASE 15 — identity beyond 64-byte M0 bound rejected
    ; =======================================================================

    lea rdi, [rel too_long_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15


    ; =======================================================================
    ; CASE 16 — Internal ABI callee-saved registers and DF preserved
    ; =======================================================================

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    lea rdi, [rel valid_entries]
    mov esi, 3
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_16

    cmp rbx, 0x11111111
    jne .fail_16

    cmp rbp, 0x22222222
    jne .fail_16

    cmp r12, 0x33333333
    jne .fail_16

    cmp r13, 0x44444444
    jne .fail_16

    cmp r14, 0x55555555
    jne .fail_16

    cmp r15, 0x66666666
    jne .fail_16

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_16


    ; =======================================================================
    ; CASE 17 — every declared RRR namespace accepts its canonical textual form
    ; =======================================================================

    lea rdi, [rel namespace_entries]
    mov esi, 18
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17


    ; =======================================================================
    ; CASE 18 — out-of-range numeric namespace rejected
    ; =======================================================================

    lea rdi, [rel bad_numeric_namespace_entry]
    mov esi, 1
    call asm_rrr_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_18


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

.fail_7:
    mov edi, 7
    call asm_linux_exit
    ud2

.fail_8:
    mov edi, 8
    call asm_linux_exit
    ud2

.fail_9:
    mov edi, 9
    call asm_linux_exit
    ud2

.fail_10:
    mov edi, 10
    call asm_linux_exit
    ud2

.fail_11:
    mov edi, 11
    call asm_linux_exit
    ud2

.fail_12:
    mov edi, 12
    call asm_linux_exit
    ud2

.fail_13:
    mov edi, 13
    call asm_linux_exit
    ud2

.fail_14:
    mov edi, 14
    call asm_linux_exit
    ud2

.fail_15:
    mov edi, 15
    call asm_linux_exit
    ud2

.fail_16:
    mov edi, 16
    call asm_linux_exit
    ud2

.fail_17:
    mov edi, 17
    call asm_linux_exit
    ud2

.fail_18:
    mov edi, 18
    call asm_linux_exit
    ud2
