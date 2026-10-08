bits 64

%include "asmweb/abi.inc"
%include "asmweb/startup.inc"
%include "asmweb/memory.inc"
%include "asmweb/resource.inc"
%include "asmweb/stack.inc"

global asm_stack_provision
global asm_stack_release

extern asm_memory_map_rw_bounded
extern asm_memory_unmap_bounded
extern asm_memory_protect_none

section .text


; ===========================================================================
; asm_stack_provision
;
; Purpose:
;   Provision one bounded anonymous guarded stack mapping without publishing an
;   execution context or selecting a production stack size.
;
; Input:
;
;   RDI = ASMWEB_STACK_REQUEST *
;   RSI = ASMWEB_MAPPING_CAPACITY *
;   RDX = pristine ASMWEB_STACK *
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_EXHAUSTED
;         ASMWEB_RESOURCE_INTEGRITY
;
; Success:
;
;   - one bounded mapping is owned by stack.mapping;
;   - usable storage is page-rounded and RW;
;   - requested low/high guard ranges are PROT_NONE;
;   - stack_top is the one-past-end usable boundary;
;   - ready is published last.
;
; Validation/configuration contradictions return INTEGRITY.
;
; Mapping-capacity refusal, mmap failure or mprotect failure return EXHAUSTED
; where ownership/accounting remains coherent.
;
; Guard-protection failure triggers bounded unmap rollback. If that rollback
; itself fails, the embedded mapping remains explicitly owned with stack.ready
; still zero so asm_stack_release can perform later recovery. Ownership is
; never silently discarded.
;
; Mutation:
;
;   Success:
;       COMMITTED_MUTATION.
;
;   Ordinary validation/capacity/protection failure with successful rollback:
;       destination remains zero.
;
;   Rollback failure:
;       VALID_PARTIAL_MUTATION limited to the embedded owned mapping record.
;
; ===========================================================================

asm_stack_provision:
    cld

    test rdi, rdi
    jz .integrity_no_frame

    test rsi, rsi
    jz .integrity_no_frame

    test rdx, rdx
    jz .integrity_no_frame

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Six pushes leave ordinary entry at RSP % 16 == 8.
    ; Reserve 40 bytes so nested CALL boundaries see RSP % 16 == 0.
    ;
    ;   [rsp + 0]  rounded usable bytes
    ;   [rsp + 8]  low guard bytes
    ;   [rsp + 16] high guard bytes
    ;   [rsp + 24] total mapping bytes
    ;   [rsp + 32] original failure result during rollback
    sub rsp, 40

    mov rbx, rdi                    ; request
    mov rbp, rsi                    ; mapping capacity
    mov r12, rdx                    ; stack descriptor


    ; -----------------------------------------------------------------------
    ; Destination must be completely pristine.
    ; -----------------------------------------------------------------------

    xor ecx, ecx

.check_pristine:
    cmp rcx, ASMWEB_STACK_size / 8
    jae .request_validate

    cmp qword [r12 + rcx * 8], 0
    jne .integrity

    inc rcx
    jmp .check_pristine


.request_validate:

    mov r15, [rbx + ASMWEB_STACK_REQUEST.owner_id]
    test r15, r15
    jz .integrity

    mov r13, [rbx + ASMWEB_STACK_REQUEST.page_size]

    cmp r13, ASMWEB_M0_MIN_PAGE_SIZE
    jb .integrity

    cmp r13, ASMWEB_M0_MAX_PAGE_SIZE
    ja .integrity

    mov rax, r13
    lea rcx, [rax - 1]
    test rax, rcx
    jnz .integrity


    ; -----------------------------------------------------------------------
    ; Checked usable-size page rounding.
    ; -----------------------------------------------------------------------

    mov rax, [rbx + ASMWEB_STACK_REQUEST.usable_bytes]
    test rax, rax
    jz .integrity

    mov rcx, r13
    dec rcx

    add rax, rcx
    jc .integrity

    not rcx
    and rax, rcx

    test rax, rax
    jz .integrity

    mov [rsp], rax


    ; Expected/qualified maximum use must be explicit and fit usable capacity.

    mov rcx, [rbx + ASMWEB_STACK_REQUEST.expected_max_use_bytes]
    test rcx, rcx
    jz .integrity

    cmp rcx, rax
    ja .integrity


    ; -----------------------------------------------------------------------
    ; Checked low-guard byte derivation.
    ; -----------------------------------------------------------------------

    mov rax, [rbx + ASMWEB_STACK_REQUEST.low_guard_pages]
    mul r13

    test rdx, rdx
    jnz .integrity

    mov [rsp + 8], rax


    ; -----------------------------------------------------------------------
    ; Checked high-guard byte derivation.
    ; -----------------------------------------------------------------------

    mov rax, [rbx + ASMWEB_STACK_REQUEST.high_guard_pages]
    mul r13

    test rdx, rdx
    jnz .integrity

    mov [rsp + 16], rax


    ; -----------------------------------------------------------------------
    ; Checked total reserved mapping size:
    ;
    ;   low guard + usable + high guard
    ; -----------------------------------------------------------------------

    mov rax, [rsp + 8]
    add rax, [rsp]
    jc .integrity

    add rax, [rsp + 16]
    jc .integrity

    test rax, rax
    jz .integrity

    mov [rsp + 24], rax


    ; -----------------------------------------------------------------------
    ; Acquire one bounded RW mapping.
    ;
    ; The embedded mapping record is the ownership authority during
    ; construction. No stack-level semantic state is published yet.
    ; -----------------------------------------------------------------------

    lea r14, [r12 + ASMWEB_STACK.mapping]

    mov rdi, [rsp + 24]
    mov rsi, r13
    mov rdx, rbp
    mov rcx, r14

    call asm_memory_map_rw_bounded

    cmp eax, ASMWEB_RESOURCE_OK
    jne .return


    ; -----------------------------------------------------------------------
    ; Low guard.
    ; -----------------------------------------------------------------------

    mov rsi, [rsp + 8]
    test rsi, rsi
    jz .high_guard

    mov rdi, [r14 + ASMWEB_MEMORY_MAPPING.base]
    mov rdx, r13

    call asm_memory_protect_none

    test eax, eax
    jnz .protection_failure


.high_guard:

    mov rsi, [rsp + 16]
    test rsi, rsi
    jz .publish

    mov rdi, [r14 + ASMWEB_MEMORY_MAPPING.base]

    add rdi, [rsp + 8]
    jc .construction_integrity_failure

    add rdi, [rsp]
    jc .construction_integrity_failure

    mov rdx, r13

    call asm_memory_protect_none

    test eax, eax
    jnz .protection_failure


.publish:

    ; All fallible construction steps have completed.

    mov rax, [r14 + ASMWEB_MEMORY_MAPPING.base]

    add rax, [rsp + 8]
    jc .construction_integrity_failure

    mov [r12 + ASMWEB_STACK.usable_base], rax

    mov rcx, [rsp]
    mov [r12 + ASMWEB_STACK.usable_bytes], rcx

    add rax, rcx
    jc .construction_integrity_failure

    mov [r12 + ASMWEB_STACK.stack_top], rax

    mov [r12 + ASMWEB_STACK.owner_id], r15

    mov rax, [rsp + 8]
    mov [r12 + ASMWEB_STACK.low_guard_bytes], rax

    mov rax, [rsp + 16]
    mov [r12 + ASMWEB_STACK.high_guard_bytes], rax

    mov rax, [rbx + ASMWEB_STACK_REQUEST.expected_max_use_bytes]
    mov [r12 + ASMWEB_STACK.expected_max_use_bytes], rax


    ; Derived guard-policy bitmask.

    xor eax, eax

    cmp qword [rsp + 8], 0
    je .guard_high_bit

    or eax, ASMWEB_STACK_GUARD_LOW

.guard_high_bit:

    cmp qword [rsp + 16], 0
    je .guard_policy_done

    or eax, ASMWEB_STACK_GUARD_HIGH

.guard_policy_done:

    mov [r12 + ASMWEB_STACK.guard_policy], rax

    ; Publication marker last.
    mov qword [r12 + ASMWEB_STACK.ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    jmp .return


.protection_failure:
    mov qword [rsp + 32], ASMWEB_RESOURCE_EXHAUSTED
    jmp .rollback


.construction_integrity_failure:
    mov qword [rsp + 32], ASMWEB_RESOURCE_INTEGRITY


.rollback:

    ; Undo the entire mapping through the same bounded ownership/accounting
    ; authority that acquired it.
    ;
    ; If unmap fails, asm_memory_unmap_bounded deliberately preserves both the
    ; live mapping record and capacity occupancy. stack.ready remains zero,
    ; leaving an explicit recoverable ownership residue.

    mov rdi, rbp
    mov rsi, r14

    call asm_memory_unmap_bounded

    cmp eax, ASMWEB_RESOURCE_OK
    jne .rollback_failed

    mov eax, [rsp + 32]
    jmp .return


.rollback_failed:
    ; Underlying release failure remains ordinary external exhaustion while
    ; ownership is still represented. It is not silently reclassified as
    ; corruption merely because cleanup could not complete.
    mov eax, ASMWEB_RESOURCE_EXHAUSTED
    jmp .return


.integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY


.return:
    add rsp, 40

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ret


.integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_stack_release
;
; Input:
;
;   RDI = ASMWEB_MAPPING_CAPACITY *
;   RSI = ASMWEB_STACK *
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_EXHAUSTED
;         ASMWEB_RESOURCE_INTEGRITY
;
; A normal published stack (ready=1) may be released.
;
; An unpublished recovery residue from failed provisioning may also be
; released when the embedded mapping remains owned and every stack-semantic
; publication field is still zero.
;
; Successful release clears the complete descriptor.
; Double release is an integrity failure.
; ===========================================================================

asm_stack_release:
    cld

    test rdi, rdi
    jz .release_integrity_no_frame

    test rsi, rsi
    jz .release_integrity_no_frame

    push rbx
    push r12
    push r13

    ; Three pushes establish RSP % 16 == 0 before nested calls.
    mov rbx, rdi
    mov r12, rsi

    lea r13, [r12 + ASMWEB_STACK.mapping]

    cmp qword [r13 + ASMWEB_MEMORY_MAPPING.ready], 1
    jne .release_integrity


    ; -----------------------------------------------------------------------
    ; Published stack or explicit unpublished rollback residue.
    ; -----------------------------------------------------------------------

    cmp qword [r12 + ASMWEB_STACK.ready], 1
    je .validate_published

    cmp qword [r12 + ASMWEB_STACK.ready], 0
    jne .release_integrity

    ; Recovery residue must contain no stack-level publication state.

    cmp qword [r12 + ASMWEB_STACK.owner_id], 0
    jne .release_integrity

    cmp qword [r12 + ASMWEB_STACK.usable_base], 0
    jne .release_integrity

    cmp qword [r12 + ASMWEB_STACK.usable_bytes], 0
    jne .release_integrity

    cmp qword [r12 + ASMWEB_STACK.stack_top], 0
    jne .release_integrity

    cmp qword [r12 + ASMWEB_STACK.low_guard_bytes], 0
    jne .release_integrity

    cmp qword [r12 + ASMWEB_STACK.high_guard_bytes], 0
    jne .release_integrity

    cmp qword [r12 + ASMWEB_STACK.expected_max_use_bytes], 0
    jne .release_integrity

    cmp qword [r12 + ASMWEB_STACK.guard_policy], 0
    jne .release_integrity

    jmp .perform_release


.validate_published:

    cmp qword [r12 + ASMWEB_STACK.owner_id], 0
    je .release_integrity

    cmp qword [r12 + ASMWEB_STACK.usable_base], 0
    je .release_integrity

    cmp qword [r12 + ASMWEB_STACK.usable_bytes], 0
    je .release_integrity

    cmp qword [r12 + ASMWEB_STACK.stack_top], 0
    je .release_integrity

    cmp qword [r12 + ASMWEB_STACK.expected_max_use_bytes], 0
    je .release_integrity


.perform_release:

    mov rdi, rbx
    mov rsi, r13

    call asm_memory_unmap_bounded

    cmp eax, ASMWEB_RESOURCE_OK
    jne .release_return


    ; Clear the complete descriptor after kernel/accounting release succeeds.

    xor eax, eax
    xor ecx, ecx

.release_zero_loop:
    cmp rcx, ASMWEB_STACK_size / 8
    jae .release_success

    mov [r12 + rcx * 8], rax

    inc rcx
    jmp .release_zero_loop


.release_success:
    mov eax, ASMWEB_RESOURCE_OK


.release_return:
    pop r13
    pop r12
    pop rbx
    ret


.release_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY

    pop r13
    pop r12
    pop rbx
    ret


.release_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
