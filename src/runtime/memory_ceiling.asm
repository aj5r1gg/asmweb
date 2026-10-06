bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/registry.inc"
%include "asmweb/memory_ceiling.inc"

global asm_memory_fixed_class_capacity

extern asm_u64_mul_checked
extern asm_u64_add_checked


; ===========================================================================
; asm_memory_fixed_class_capacity
;
; Inputs:
;
;   RDI = effective_stride_bytes
;   RSI = maximum_count
;   RDX = pool_metadata_bytes
;   RCX = mapping_overhead_bytes
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = complete class direct-memory contribution on success
;         zero on failure
;
; Formula:
;
;   payload_max = stride * count
;
;   class_max =
;       payload_max
;     + pool_metadata
;     + mapping_overhead
;
; The routine intentionally composes the canonical checked arithmetic
; primitives rather than reproducing independent overflow logic.
; ===========================================================================

asm_memory_fixed_class_capacity:
    cld

    ; Function entry sees RSP % 16 == 8.
    ;
    ; Reserve 24 bytes:
    ;   [rsp + 0]  pool_metadata
    ;   [rsp + 8]  mapping_overhead
    ;   [rsp + 16] reserved/alignment
    ;
    ; This leaves RSP % 16 == 0 before each CALL.
    sub rsp, 24

    mov [rsp + 0], rdx
    mov [rsp + 8], rcx


    ; -----------------------------------------------------------------------
    ; payload_max = stride * count
    ; -----------------------------------------------------------------------

    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail


    ; -----------------------------------------------------------------------
    ; payload_plus_metadata = payload_max + pool_metadata
    ; -----------------------------------------------------------------------

    mov rdi, rdx
    mov rsi, [rsp + 0]

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail


    ; -----------------------------------------------------------------------
    ; class_max = payload_plus_metadata + mapping_overhead
    ; -----------------------------------------------------------------------

    mov rdi, rdx
    mov rsi, [rsp + 8]

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail


    add rsp, 24

    mov eax, ASMWEB_RESOURCE_OK
    ret


.fail:
    add rsp, 24

    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_memory_direct_capacity_sum
;
; Inputs:
;
;   RDI = pointer to contiguous uint64 class contributions
;   RSI = contribution count
;
; Canonical empty input:
;
;   RDI = NULL
;   RSI = 0
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = checked sum on success
;         zero on failure
;
; Constraints:
;
;   - count SHALL NOT exceed ASMWEB_M0_MAX_MOT_ENTRIES;
;   - NULL + non-zero count is invalid;
;   - non-NULL + zero count is non-canonical and invalid;
;   - every addition is performed by asm_u64_add_checked;
;   - arithmetic overflow fails deterministically.
;
; This routine does not decide which MOT entries are active or applicable.
; It sums an already-selected bounded contribution vector.
; ===========================================================================

global asm_memory_direct_capacity_sum


asm_memory_direct_capacity_sum:
    cld

    ; Canonical empty vector.
    test rsi, rsi
    jnz .sum_nonempty

    test rdi, rdi
    jnz .sum_fail

    xor edx, edx
    mov eax, ASMWEB_RESOURCE_OK
    ret


.sum_nonempty:
    test rdi, rdi
    jz .sum_fail

    cmp rsi, ASMWEB_M0_MAX_MOT_ENTRIES
    ja .sum_fail


    ; Function entry:
    ;   RSP % 16 == 8
    ;
    ; Preserve three callee-saved registers. After three pushes:
    ;   RSP % 16 == 0
    ;
    ; so nested CALL sites satisfy Internal ABI v1.
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d


.sum_loop:
    mov rdi, r13
    mov rsi, [rbx]

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .sum_fail_preserved

    mov r13, rdx

    add rbx, 8
    dec r12
    jnz .sum_loop


    mov rdx, r13

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.sum_fail_preserved:
    pop r13
    pop r12
    pop rbx


.sum_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_memory_direct_capacity_from_mot
;
; Inputs:
;
;   RDI = pointer to contiguous ASMWEB_MOT_VALIDATION_ENTRY records
;   RSI = MOT entry count
;
; Canonical empty input:
;
;   RDI = NULL
;   RSI = 0
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = M_direct_capacity_max arithmetic result on success
;         zero on failure
;
; Derivation:
;
;   for each MOT entry:
;
;       validate lifecycle-state representation
;
;       if status != ACTIVE:
;           skip
;
;       M_class =
;           checked(
;               effective_stride_bytes * maximum_count
;               + pool_metadata_bytes
;               + mapping_overhead_bytes
;           )
;
;       M_direct_capacity_max =
;           checked(M_direct_capacity_max + M_class)
;
; The routine does not perform OLR/RCT cross-reference validation. That remains
; the responsibility of asm_registry_validate. It does, however, refuse an
; invalid lifecycle value rather than silently treating malformed state as
; inactive.
; ===========================================================================

global asm_memory_direct_capacity_from_mot


asm_memory_direct_capacity_from_mot:
    cld

    ; Canonical empty MOT.
    test rsi, rsi
    jnz .mot_nonempty

    test rdi, rdi
    jnz .mot_fail

    xor edx, edx
    mov eax, ASMWEB_RESOURCE_OK
    ret


.mot_nonempty:
    test rdi, rdi
    jz .mot_fail

    cmp rsi, ASMWEB_M0_MAX_MOT_ENTRIES
    ja .mot_fail


    ; Function entry sees RSP % 16 == 8.
    ;
    ; Five callee-saved pushes consume 40 bytes, leaving RSP % 16 == 0 before
    ; nested CALL sites.
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d


.mot_loop:
    mov rax, [rbx + ASMWEB_MOT_VALIDATION_ENTRY.status]

    cmp rax, ASMWEB_REGISTRY_STATUS_ACTIVE
    jb .mot_fail_preserved

    cmp rax, ASMWEB_REGISTRY_STATUS_RETIRED
    ja .mot_fail_preserved

    cmp rax, ASMWEB_REGISTRY_STATUS_ACTIVE
    jne .mot_next


    ; Calculate the complete fixed-class contribution directly from the MOT.
    mov rdi, [rbx + ASMWEB_MOT_VALIDATION_ENTRY.effective_stride_bytes]
    mov rsi, [rbx + ASMWEB_MOT_VALIDATION_ENTRY.maximum_count]
    mov rdx, [rbx + ASMWEB_MOT_VALIDATION_ENTRY.pool_metadata_bytes]
    mov rcx, [rbx + ASMWEB_MOT_VALIDATION_ENTRY.mapping_overhead_bytes]

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .mot_fail_preserved

    mov r14, rdx


    ; Accumulate the class contribution without wraparound.
    mov rdi, r13
    mov rsi, r14

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .mot_fail_preserved

    mov r13, rdx


.mot_next:
    add rbx, ASMWEB_MOT_VALIDATION_ENTRY_size

    dec r12
    jnz .mot_loop


    mov rdx, r13

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.mot_fail_preserved:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx


.mot_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
