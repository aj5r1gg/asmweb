bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/registry.inc"

global asm_registry_validate

section .text


; ---------------------------------------------------------------------------
; asm_registry_validate
;
; Purpose:
;   Validate the initial machine-relevant OLR/MOT/RCT consistency contract.
;
; Input:
;   RDI = ASMWEB_REGISTRY_VALIDATION_SET
;
; Result:
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; M0 validation includes:
;
;   - bounded registry counts;
;   - pointer/count structural consistency;
;   - non-zero stable identifiers;
;   - valid registry lifecycle states;
;   - valid OLR layout states;
;   - duplicate OLR object_id rejection;
;   - duplicate MOT limit_id rejection;
;   - duplicate RCT resource_id rejection;
;   - active pooled OLR -> MOT resolution;
;   - active MOT -> OLR resolution;
;   - OLR/MOT size and stride agreement;
;   - stride >= actual object size;
;   - MOT configured <= physical <= maximum count;
;   - MOT owning resource -> RCT resolution;
;   - RCT configured <= physical;
;   - RCT reserved <= configured;
;   - memory-bearing RCT -> MOT linkage or explicit justification;
;   - all non-zero RCT MOT references resolve.
;
; Complexity:
;   O(n^2) duplicate/reference qualification.
;
;   Registry entry counts are explicitly bounded and small in M0. This
;   validator is startup/qualification machinery, not request-path work.
;
; Callee-saved:
;   RBX RBP R12 R13 R14 R15 preserved.
; ---------------------------------------------------------------------------

asm_registry_validate:
    cld

    test rdi, rdi
    jz .integrity_no_frame

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi

    ; -----------------------------------------------------------------------
    ; Registry-set structural validation.
    ; -----------------------------------------------------------------------

    mov r12, [rbx + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr]
    mov r13, [rbx + ASMWEB_REGISTRY_VALIDATION_SET.olr_count]

    cmp r13, ASMWEB_M0_MAX_OLR_ENTRIES
    ja .integrity

    test r13, r13
    jz .olr_empty_pointer_check

    test r12, r12
    jz .integrity
    jmp .mot_set

.olr_empty_pointer_check:
    ; Canonical empty representation is NULL + zero count.
    test r12, r12
    jnz .integrity

.mot_set:
    mov r14, [rbx + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr]
    mov r15, [rbx + ASMWEB_REGISTRY_VALIDATION_SET.mot_count]

    cmp r15, ASMWEB_M0_MAX_MOT_ENTRIES
    ja .integrity

    test r15, r15
    jz .mot_empty_pointer_check

    test r14, r14
    jz .integrity
    jmp .rct_set

.mot_empty_pointer_check:
    test r14, r14
    jnz .integrity

.rct_set:
    mov rbp, [rbx + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr]
    mov r11, [rbx + ASMWEB_REGISTRY_VALIDATION_SET.rct_count]

    cmp r11, ASMWEB_M0_MAX_RCT_ENTRIES
    ja .integrity

    test r11, r11
    jz .rct_empty_pointer_check

    test rbp, rbp
    jz .integrity
    jmp .validate_olr

.rct_empty_pointer_check:
    test rbp, rbp
    jnz .integrity


    ; =======================================================================
    ; OLR
    ; =======================================================================

.validate_olr:
    xor r8d, r8d

.olr_outer:
    cmp r8, r13
    jae .validate_mot

    ; current = olr + index * entry_size
    mov rax, r8
    imul rax, ASMWEB_OLR_VALIDATION_ENTRY_size
    jo .integrity

    lea r9, [r12 + rax]

    ; Stable object identifier must be non-zero.
    mov rax, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.object_id]
    test rax, rax
    jz .integrity

    ; Lifecycle status range.
    mov rcx, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.status]
    cmp rcx, ASMWEB_REGISTRY_STATUS_ACTIVE
    jb .integrity
    cmp rcx, ASMWEB_REGISTRY_STATUS_RETIRED
    ja .integrity

    ; Layout status range.
    mov rcx, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.layout_status]
    cmp rcx, ASMWEB_LAYOUT_STATUS_CONCEPTUAL
    jb .integrity
    cmp rcx, ASMWEB_LAYOUT_STATUS_FROZEN_FOR_MILESTONE
    ja .integrity

    ; pooled is a strict boolean.
    mov rcx, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.pooled]
    cmp rcx, 1
    ja .integrity

    ; Active memory-bearing layout state must be coherent.
    cmp qword [r9 + ASMWEB_OLR_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE
    jne .olr_duplicate_scan

    mov rdx, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.actual_size_bytes]
    mov rcx, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.effective_stride_bytes]

    test rdx, rdx
    jz .integrity

    test rcx, rcx
    jz .integrity

    cmp rcx, rdx
    jb .integrity

    ; Active pooled objects require applicable MOT linkage.
    cmp qword [r9 + ASMWEB_OLR_VALIDATION_ENTRY.pooled], 1
    jne .olr_optional_mot_check

    cmp qword [r9 + ASMWEB_OLR_VALIDATION_ENTRY.mot_ref], 0
    je .integrity

.olr_optional_mot_check:
    ; Any non-zero MOT reference must resolve and agree.
    mov r10, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.mot_ref]
    test r10, r10
    jz .olr_duplicate_scan

    xor ecx, ecx

.olr_find_mot:
    cmp rcx, r15
    jae .integrity

    mov rax, rcx
    imul rax, ASMWEB_MOT_VALIDATION_ENTRY_size
    jo .integrity

    lea rdx, [r14 + rax]

    cmp [rdx + ASMWEB_MOT_VALIDATION_ENTRY.limit_id], r10
    je .olr_mot_found

    inc rcx
    jmp .olr_find_mot

.olr_mot_found:
    mov rax, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.object_id]
    cmp [rdx + ASMWEB_MOT_VALIDATION_ENTRY.object_id], rax
    jne .integrity

    mov rax, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.actual_size_bytes]
    cmp [rdx + ASMWEB_MOT_VALIDATION_ENTRY.actual_size_bytes], rax
    jne .integrity

    mov rax, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.effective_stride_bytes]
    cmp [rdx + ASMWEB_MOT_VALIDATION_ENTRY.effective_stride_bytes], rax
    jne .integrity

.olr_duplicate_scan:
    mov r10, r8
    inc r10

.olr_duplicate_loop:
    cmp r10, r13
    jae .olr_next

    mov rax, r10
    imul rax, ASMWEB_OLR_VALIDATION_ENTRY_size
    jo .integrity

    lea rdx, [r12 + rax]

    mov rax, [r9 + ASMWEB_OLR_VALIDATION_ENTRY.object_id]
    cmp [rdx + ASMWEB_OLR_VALIDATION_ENTRY.object_id], rax
    je .integrity

    inc r10
    jmp .olr_duplicate_loop

.olr_next:
    inc r8
    jmp .olr_outer


    ; =======================================================================
    ; MOT
    ; =======================================================================

.validate_mot:
    xor r8d, r8d

.mot_outer:
    cmp r8, r15
    jae .validate_rct

    mov rax, r8
    imul rax, ASMWEB_MOT_VALIDATION_ENTRY_size
    jo .integrity

    lea r9, [r14 + rax]

    ; Stable limit ID.
    mov rax, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.limit_id]
    test rax, rax
    jz .integrity

    ; Valid lifecycle status.
    mov rcx, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.status]
    cmp rcx, ASMWEB_REGISTRY_STATUS_ACTIVE
    jb .integrity
    cmp rcx, ASMWEB_REGISTRY_STATUS_RETIRED
    ja .integrity

    cmp qword [r9 + ASMWEB_MOT_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE
    jne .mot_duplicate_scan

    ; Active MOT entries require an OLR object.
    mov r10, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.object_id]
    test r10, r10
    jz .integrity

    xor ecx, ecx

.mot_find_olr:
    cmp rcx, r13
    jae .integrity

    mov rax, rcx
    imul rax, ASMWEB_OLR_VALIDATION_ENTRY_size
    jo .integrity

    lea rdx, [r12 + rax]

    cmp [rdx + ASMWEB_OLR_VALIDATION_ENTRY.object_id], r10
    je .mot_olr_found

    inc rcx
    jmp .mot_find_olr

.mot_olr_found:
    mov rax, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.actual_size_bytes]
    test rax, rax
    jz .integrity

    cmp [rdx + ASMWEB_OLR_VALIDATION_ENTRY.actual_size_bytes], rax
    jne .integrity

    mov rax, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.effective_stride_bytes]
    test rax, rax
    jz .integrity

    cmp [rdx + ASMWEB_OLR_VALIDATION_ENTRY.effective_stride_bytes], rax
    jne .integrity

    cmp rax, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.actual_size_bytes]
    jb .integrity

    ; configured <= physical <= maximum_count
    mov rax, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.configured_capacity]
    mov rcx, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.physical_capacity]
    mov rdx, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.maximum_count]

    cmp rax, rcx
    ja .integrity

    cmp rcx, rdx
    ja .integrity

    ; Optional owning resource must resolve.
    mov r10, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.owner_resource_id]
    test r10, r10
    jz .mot_duplicate_scan

    xor ecx, ecx

.mot_find_rct:
    cmp rcx, r11
    jae .integrity

    mov rax, rcx
    imul rax, ASMWEB_RCT_VALIDATION_ENTRY_size
    jo .integrity

    lea rdx, [rbp + rax]

    cmp [rdx + ASMWEB_RCT_VALIDATION_ENTRY.resource_id], r10
    je .mot_duplicate_scan

    inc rcx
    jmp .mot_find_rct

.mot_duplicate_scan:
    mov r10, r8
    inc r10

.mot_duplicate_loop:
    cmp r10, r15
    jae .mot_next

    mov rax, r10
    imul rax, ASMWEB_MOT_VALIDATION_ENTRY_size
    jo .integrity

    lea rdx, [r14 + rax]

    mov rax, [r9 + ASMWEB_MOT_VALIDATION_ENTRY.limit_id]
    cmp [rdx + ASMWEB_MOT_VALIDATION_ENTRY.limit_id], rax
    je .integrity

    inc r10
    jmp .mot_duplicate_loop

.mot_next:
    inc r8
    jmp .mot_outer


    ; =======================================================================
    ; RCT
    ; =======================================================================

.validate_rct:
    xor r8d, r8d

.rct_outer:
    cmp r8, r11
    jae .success

    mov rax, r8
    imul rax, ASMWEB_RCT_VALIDATION_ENTRY_size
    jo .integrity

    lea r9, [rbp + rax]

    ; Stable resource ID.
    mov rax, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.resource_id]
    test rax, rax
    jz .integrity

    ; Valid lifecycle status.
    mov rcx, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.status]
    cmp rcx, ASMWEB_REGISTRY_STATUS_ACTIVE
    jb .integrity
    cmp rcx, ASMWEB_REGISTRY_STATUS_RETIRED
    ja .integrity

    ; Explicit-justification marker is a strict boolean.
    mov rcx, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.direct_memory_justified]
    cmp rcx, 1
    ja .integrity

    cmp qword [r9 + ASMWEB_RCT_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE
    jne .rct_duplicate_scan

    ; configured <= physical
    mov rax, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.configured_capacity]
    mov rcx, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.physical_capacity]

    cmp rax, rcx
    ja .integrity

    ; reserved <= configured
    mov rdx, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.reserved_capacity]
    cmp rdx, rax
    ja .integrity

    ; Memory-bearing RCT entries require MOT linkage or explicit justification.
    mov rax, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.direct_bytes]
    test rax, rax
    jz .rct_optional_mot

    cmp qword [r9 + ASMWEB_RCT_VALIDATION_ENTRY.mot_ref], 0
    jne .rct_optional_mot

    cmp qword [r9 + ASMWEB_RCT_VALIDATION_ENTRY.direct_memory_justified], 1
    jne .integrity

.rct_optional_mot:
    ; Any non-zero MOT reference must resolve.
    mov r10, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.mot_ref]
    test r10, r10
    jz .rct_duplicate_scan

    xor ecx, ecx

.rct_find_mot:
    cmp rcx, r15
    jae .integrity

    mov rax, rcx
    imul rax, ASMWEB_MOT_VALIDATION_ENTRY_size
    jo .integrity

    lea rdx, [r14 + rax]

    cmp [rdx + ASMWEB_MOT_VALIDATION_ENTRY.limit_id], r10
    je .rct_duplicate_scan

    inc rcx
    jmp .rct_find_mot

.rct_duplicate_scan:
    mov r10, r8
    inc r10

.rct_duplicate_loop:
    cmp r10, r11
    jae .rct_next

    mov rax, r10
    imul rax, ASMWEB_RCT_VALIDATION_ENTRY_size
    jo .integrity

    lea rdx, [rbp + rax]

    mov rax, [r9 + ASMWEB_RCT_VALIDATION_ENTRY.resource_id]
    cmp [rdx + ASMWEB_RCT_VALIDATION_ENTRY.resource_id], rax
    je .integrity

    inc r10
    jmp .rct_duplicate_loop

.rct_next:
    inc r8
    jmp .rct_outer


.success:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.integrity:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

.integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
