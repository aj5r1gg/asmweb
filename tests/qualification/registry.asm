bits 64

%include "asmweb/registry.inc"
%include "asmweb/resource.inc"

global _start

extern asm_registry_validate
extern asm_linux_exit


; ---------------------------------------------------------------------------
; Qualification fixtures
; ---------------------------------------------------------------------------

section .data

align 8

; Valid OLR/MOT/RCT relationship.
valid_olr:
    dq 0x1001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 64
    dq 64
    dq 1
    dq 0x2001

valid_mot:
    dq 0x2001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1001
    dq 64
    dq 64
    dq 8
    dq 8
    dq 4
    dq 0x3001

valid_rct:
    dq 0x3001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 1
    dq 256
    dq 0x2001
    dq 0



; Duplicate OLR object IDs.
duplicate_olr:
    dq 0x1101
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 64
    dq 64
    dq 0
    dq 0

    dq 0x1101
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 64
    dq 64
    dq 0
    dq 0



; Active pooled OLR references unknown MOT.
unknown_mot_olr:
    dq 0x1201
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 32
    dq 32
    dq 1
    dq 0xDEAD



; OLR/MOT stale size relationship.
stale_olr:
    dq 0x1301
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 64
    dq 64
    dq 1
    dq 0x2301

stale_mot:
    dq 0x2301
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1301
    dq 72
    dq 72
    dq 4
    dq 4
    dq 4
    dq 0



; MOT configured capacity exceeds physical capacity.
capacity_olr:
    dq 0x1401
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 32
    dq 32
    dq 1
    dq 0x2401

capacity_mot:
    dq 0x2401
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1401
    dq 32
    dq 32
    dq 8
    dq 4
    dq 5
    dq 0



; Memory-bearing RCT with neither MOT linkage nor justification.
unlinked_rct:
    dq 0x3501
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 0
    dq 4096
    dq 0
    dq 0



; Memory-bearing RCT with explicit non-MOT justification.
justified_rct:
    dq 0x3601
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 0
    dq 4096
    dq 0
    dq 1



; MOT owner resource reference does not resolve.
owner_olr:
    dq 0x1701
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 16
    dq 16
    dq 1
    dq 0x2701

owner_mot:
    dq 0x2701
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1701
    dq 16
    dq 16
    dq 4
    dq 4
    dq 4
    dq 0xDEAD



; Active MOT object does not resolve to an OLR.
orphan_mot:
    dq 0x2801
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1801
    dq 16
    dq 16
    dq 4
    dq 4
    dq 4
    dq 0



; RCT configured capacity exceeds physical capacity.
bad_rct_capacity:
    dq 0x3901
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 4
    dq 5
    dq 0
    dq 0
    dq 0
    dq 0



; Registry count beyond M0 validator bound.


; Duplicate MOT limit IDs.
duplicate_mot_olr_a:
    dq 0x1A01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 16
    dq 16
    dq 0
    dq 0

duplicate_mot_olr_b:
    dq 0x1A02
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 16
    dq 16
    dq 0
    dq 0

duplicate_mot:
    dq 0x2A01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1A01
    dq 16
    dq 16
    dq 4
    dq 4
    dq 4
    dq 0

    dq 0x2A01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1A02
    dq 16
    dq 16
    dq 4
    dq 4
    dq 4
    dq 0


; Duplicate RCT resource IDs.
duplicate_rct:
    dq 0x3A01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 0
    dq 0
    dq 0
    dq 0

    dq 0x3A01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 0
    dq 0
    dq 0
    dq 0


; RCT protected reserve exceeds configured capacity.
bad_rct_reserve:
    dq 0x3B01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 5
    dq 0
    dq 0
    dq 0


; RCT carries unknown non-zero MOT reference.
unknown_rct_mot:
    dq 0x3C01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 0
    dq 0
    dq 0xDEAD
    dq 0


; Active pooled OLR has no MOT reference at all.
missing_mot_ref_olr:
    dq 0x1D01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 32
    dq 32
    dq 1
    dq 0


; Invalid lifecycle status.
invalid_status_olr:
    dq 0x1E01
    dq 0
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 32
    dq 32
    dq 0
    dq 0


; Invalid layout status.
invalid_layout_olr:
    dq 0x1F01
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0
    dq 32
    dq 32
    dq 0
    dq 0


; Invalid boolean fields.
invalid_pooled_olr:
    dq 0x2001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 32
    dq 32
    dq 2
    dq 0

invalid_justification_rct:
    dq 0x4001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 0
    dq 0
    dq 0
    dq 2


section .bss

align 8

valid_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

duplicate_olr_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

unknown_mot_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

stale_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

capacity_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

unlinked_rct_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

justified_rct_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

owner_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

orphan_mot_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

bad_rct_capacity_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

count_overflow_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

duplicate_mot_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

duplicate_rct_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

bad_rct_reserve_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

unknown_rct_mot_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

missing_mot_ref_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

invalid_status_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

invalid_layout_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

invalid_pooled_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

invalid_justification_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

pointer_count_mismatch_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

canonical_empty_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size


section .text

_start:
    cld

    ; -----------------------------------------------------------------------
    ; Construct validation-set descriptors without absolute pointer
    ; relocations.
    ;
    ; BSS provides canonical zero state for absent registry components.
    ; -----------------------------------------------------------------------

    ; valid_set
    lea rax, [rel valid_olr]
    mov [rel valid_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel valid_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    lea rax, [rel valid_mot]
    mov [rel valid_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel valid_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1

    lea rax, [rel valid_rct]
    mov [rel valid_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel valid_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 1

    ; duplicate_olr_set
    lea rax, [rel duplicate_olr]
    mov [rel duplicate_olr_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel duplicate_olr_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 2

    ; unknown_mot_set
    lea rax, [rel unknown_mot_olr]
    mov [rel unknown_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel unknown_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    ; stale_set
    lea rax, [rel stale_olr]
    mov [rel stale_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel stale_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    lea rax, [rel stale_mot]
    mov [rel stale_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel stale_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1

    ; capacity_set
    lea rax, [rel capacity_olr]
    mov [rel capacity_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel capacity_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    lea rax, [rel capacity_mot]
    mov [rel capacity_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel capacity_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1

    ; unlinked_rct_set
    lea rax, [rel unlinked_rct]
    mov [rel unlinked_rct_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel unlinked_rct_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 1

    ; justified_rct_set
    lea rax, [rel justified_rct]
    mov [rel justified_rct_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel justified_rct_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 1

    ; owner_set
    lea rax, [rel owner_olr]
    mov [rel owner_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel owner_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    lea rax, [rel owner_mot]
    mov [rel owner_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel owner_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1

    ; orphan_mot_set
    lea rax, [rel orphan_mot]
    mov [rel orphan_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel orphan_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1

    ; bad_rct_capacity_set
    lea rax, [rel bad_rct_capacity]
    mov [rel bad_rct_capacity_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel bad_rct_capacity_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 1

    ; count_overflow_set
    lea rax, [rel valid_olr]
    mov [rel count_overflow_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel count_overflow_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count],         ASMWEB_M0_MAX_OLR_ENTRIES + 1

    ; duplicate_mot_set
    lea rax, [rel duplicate_mot_olr_a]
    mov [rel duplicate_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel duplicate_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 2

    lea rax, [rel duplicate_mot]
    mov [rel duplicate_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel duplicate_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 2

    ; duplicate_rct_set
    lea rax, [rel duplicate_rct]
    mov [rel duplicate_rct_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel duplicate_rct_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 2

    ; bad_rct_reserve_set
    lea rax, [rel bad_rct_reserve]
    mov [rel bad_rct_reserve_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel bad_rct_reserve_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 1

    ; unknown_rct_mot_set
    lea rax, [rel unknown_rct_mot]
    mov [rel unknown_rct_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel unknown_rct_mot_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 1

    ; missing_mot_ref_set
    lea rax, [rel missing_mot_ref_olr]
    mov [rel missing_mot_ref_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel missing_mot_ref_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    ; invalid_status_set
    lea rax, [rel invalid_status_olr]
    mov [rel invalid_status_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel invalid_status_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    ; invalid_layout_set
    lea rax, [rel invalid_layout_olr]
    mov [rel invalid_layout_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel invalid_layout_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    ; invalid_pooled_set
    lea rax, [rel invalid_pooled_olr]
    mov [rel invalid_pooled_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel invalid_pooled_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    ; invalid_justification_set
    lea rax, [rel invalid_justification_rct]
    mov [rel invalid_justification_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel invalid_justification_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 1

    ; pointer_count_mismatch_set
    ;
    ; Non-zero pointer with zero count violates canonical empty representation.
    lea rax, [rel valid_olr]
    mov [rel pointer_count_mismatch_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax

    ; =======================================================================
    ; CASE 1 — coherent dummy registry set passes
    ; =======================================================================

    lea rdi, [rel valid_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — duplicate OLR identifier rejected
    ; =======================================================================

    lea rdi, [rel duplicate_olr_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — unknown OLR -> MOT cross-reference rejected
    ; =======================================================================

    lea rdi, [rel unknown_mot_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — stale OLR/MOT layout relationship rejected
    ; =======================================================================

    lea rdi, [rel stale_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — MOT configured > physical rejected
    ; =======================================================================

    lea rdi, [rel capacity_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — memory-bearing RCT without linkage/justification rejected
    ; =======================================================================

    lea rdi, [rel unlinked_rct_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — explicit non-MOT direct-memory justification accepted
    ; =======================================================================

    lea rdi, [rel justified_rct_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7


    ; =======================================================================
    ; CASE 8 — unknown MOT owning resource rejected
    ; =======================================================================

    lea rdi, [rel owner_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — active MOT without OLR object rejected
    ; =======================================================================

    lea rdi, [rel orphan_mot_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9


    ; =======================================================================
    ; CASE 10 — RCT configured > physical rejected
    ; =======================================================================

    lea rdi, [rel bad_rct_capacity_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10


    ; =======================================================================
    ; CASE 11 — bounded registry count enforced before traversal
    ; =======================================================================

    lea rdi, [rel count_overflow_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11


    ; =======================================================================
    ; CASE 12 — NULL validation set rejected
    ; =======================================================================

    xor edi, edi
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12


    ; =======================================================================
    ; CASE 13 — duplicate MOT identifier rejected
    ; =======================================================================

    lea rdi, [rel duplicate_mot_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13


    ; =======================================================================
    ; CASE 14 — duplicate RCT identifier rejected
    ; =======================================================================

    lea rdi, [rel duplicate_rct_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14


    ; =======================================================================
    ; CASE 15 — RCT reserved > configured rejected
    ; =======================================================================

    lea rdi, [rel bad_rct_reserve_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15


    ; =======================================================================
    ; CASE 16 — unknown non-zero RCT -> MOT reference rejected
    ; =======================================================================

    lea rdi, [rel unknown_rct_mot_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    ; =======================================================================
    ; CASE 17 — active pooled OLR without MOT reference rejected
    ; =======================================================================

    lea rdi, [rel missing_mot_ref_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17


    ; =======================================================================
    ; CASE 18 — invalid registry lifecycle status rejected
    ; =======================================================================

    lea rdi, [rel invalid_status_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_18


    ; =======================================================================
    ; CASE 19 — invalid layout status rejected
    ; =======================================================================

    lea rdi, [rel invalid_layout_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_19


    ; =======================================================================
    ; CASE 20 — invalid pooled boolean rejected
    ; =======================================================================

    lea rdi, [rel invalid_pooled_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20


    ; =======================================================================
    ; CASE 21 — invalid direct-memory justification boolean rejected
    ; =======================================================================

    lea rdi, [rel invalid_justification_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21


    ; =======================================================================
    ; CASE 22 — non-NULL pointer with zero count rejected
    ; =======================================================================

    lea rdi, [rel pointer_count_mismatch_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_22


    ; =======================================================================
    ; CASE 23 — zero-count canonical empty registry set accepted
    ; =======================================================================

    lea rdi, [rel canonical_empty_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_23


    ; =======================================================================
    ; CASE 24 — validator preserves Internal ABI callee-saved registers
    ; =======================================================================

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    lea rdi, [rel valid_set]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_24

    cmp rbx, 0x11111111
    jne .fail_24

    cmp rbp, 0x22222222
    jne .fail_24

    cmp r12, 0x33333333
    jne .fail_24

    cmp r13, 0x44444444
    jne .fail_24

    cmp r14, 0x55555555
    jne .fail_24

    cmp r15, 0x66666666
    jne .fail_24

    ; Validator contract also requires DF clear on ordinary return.
    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_24


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

.fail_19:
    mov edi, 19
    call asm_linux_exit
    ud2

.fail_20:
    mov edi, 20
    call asm_linux_exit
    ud2

.fail_21:
    mov edi, 21
    call asm_linux_exit
    ud2

.fail_22:
    mov edi, 22
    call asm_linux_exit
    ud2

.fail_23:
    mov edi, 23
    call asm_linux_exit
    ud2

.fail_24:
    mov edi, 24
    call asm_linux_exit
    ud2
