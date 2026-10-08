bits 64

%include "asmweb/abi.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/resource.inc"
%include "asmweb/pool.inc"
%include "asmweb/stale_candidate.inc"

global asm_stale_candidate_init
global asm_stale_candidate_validate
global asm_stale_candidate_acquire
global asm_stale_candidate_lookup
global asm_stale_candidate_release

extern asm_typed_pool_validate
extern asm_typed_pool_acquire
extern asm_typed_pool_release


section .text


; ===========================================================================
; asm_stale_candidate_init
;
; RDI = ASMWEB_TYPED_POOL *
; RSI = caller-provided uint64 generation array
; RDX = generation entry count
; RCX = generation storage bytes supplied by caller
; R8  = pristine ASMWEB_STALE_CANDIDATE *
;
; Returns:
;
;   RAX = ASMWEB_STALE_RESULT_OK
;         ASMWEB_STALE_RESULT_INTEGRITY
;
; Preconditions:
;
;   - underlying pool is valid and quiescent;
;   - generation count exactly equals physical pool capacity;
;   - generation storage is large enough and 8-byte aligned;
;   - every candidate generation entry is initially zero;
;   - candidate descriptor is pristine;
;   - candidate/generation storage does not overlap the pool descriptor,
;     payload, slot-state metadata or each other.
;
; On success every candidate generation begins at 1.
;
; All fallible validation occurs before generation metadata or candidate
; descriptor mutation.
; ===========================================================================

asm_stale_candidate_init:
    cld

    test rdi, rdi
    jz .init_integrity_no_frame

    test rsi, rsi
    jz .init_integrity_no_frame

    test r8, r8
    jz .init_integrity_no_frame

    ; Six saved registers leave entry alignment unchanged (RSP % 16 == 8).
    ; Additional 8 bytes establish the Internal ABI CALL boundary.
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov rbx, rdi                    ; pool
    mov r12, rsi                    ; generation_base
    mov r13, rdx                    ; generation_count
    mov r15, rcx                    ; supplied generation bytes
    mov rbp, r8                     ; candidate


    ; -----------------------------------------------------------------------
    ; Destination descriptor must be pristine.
    ; -----------------------------------------------------------------------

    xor ecx, ecx

.init_candidate_pristine:
    cmp rcx, ASMWEB_STALE_CANDIDATE_size / 8
    jae .init_pool_validate

    cmp qword [rbp + rcx * 8], 0
    jne .init_integrity

    inc rcx
    jmp .init_candidate_pristine


.init_pool_validate:

    mov rdi, rbx
    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .init_integrity


    ; Candidate attachment begins only from a quiescent pool.
    cmp qword [rbx + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .init_integrity


    ; Stable object class must exist.
    cmp qword [rbx + ASMWEB_TYPED_POOL.object_class_id], 0
    je .init_integrity


    ; -----------------------------------------------------------------------
    ; Generation geometry.
    ; -----------------------------------------------------------------------

    test r13, r13
    jz .init_integrity

    cmp r13, [rbx + ASMWEB_TYPED_POOL.physical_capacity]
    jne .init_integrity

    ; uint64 generation array requires 8-byte alignment.
    test r12, 7
    jnz .init_integrity


    ; required_generation_bytes = generation_count * 8

    mov rax, r13
    mov ecx, 8
    mul rcx

    test rdx, rdx
    jnz .init_integrity

    mov r14, rax

    cmp r15, r14
    jb .init_integrity


    ; Complete management representation:
    ;
    ;     candidate descriptor + represented generation bytes

    mov rax, r14
    add rax, ASMWEB_STALE_CANDIDATE_size
    jc .init_integrity

    mov [rsp], rax                  ; management_bytes_total candidate


    ; -----------------------------------------------------------------------
    ; Calculate represented ranges.
    ; -----------------------------------------------------------------------

    ; generation_end
    mov r9, r12
    add r9, r14
    jc .init_integrity

    ; candidate_end
    mov r10, rbp
    add r10, ASMWEB_STALE_CANDIDATE_size
    jc .init_integrity

    ; pool_end
    mov r11, rbx
    add r11, ASMWEB_TYPED_POOL_size
    jc .init_integrity


    ; -----------------------------------------------------------------------
    ; Candidate descriptor must not overlap generation metadata.
    ; -----------------------------------------------------------------------

    cmp r10, r12
    jbe .init_candidate_generation_separate

    cmp r9, rbp
    ja .init_integrity


.init_candidate_generation_separate:

    ; -----------------------------------------------------------------------
    ; Candidate descriptor must not overlap pool descriptor.
    ; -----------------------------------------------------------------------

    cmp r10, rbx
    jbe .init_candidate_pool_separate

    cmp r11, rbp
    ja .init_integrity


.init_candidate_pool_separate:

    ; -----------------------------------------------------------------------
    ; Generation metadata must not overlap pool descriptor.
    ; -----------------------------------------------------------------------

    cmp r9, rbx
    jbe .init_generation_pool_separate

    cmp r11, r12
    ja .init_integrity


.init_generation_pool_separate:

    ; -----------------------------------------------------------------------
    ; Pool payload range.
    ; -----------------------------------------------------------------------

    mov rdx, [rbx + ASMWEB_TYPED_POOL.backing_base]
    mov rcx, rdx
    add rcx, [rbx + ASMWEB_TYPED_POOL.payload_bytes]
    jc .init_integrity


    ; candidate / payload
    cmp r10, rdx
    jbe .init_candidate_payload_separate

    cmp rcx, rbp
    ja .init_integrity


.init_candidate_payload_separate:

    ; generation / payload
    cmp r9, rdx
    jbe .init_generation_payload_separate

    cmp rcx, r12
    ja .init_integrity


.init_generation_payload_separate:

    ; -----------------------------------------------------------------------
    ; Pool slot-state metadata range.
    ; -----------------------------------------------------------------------

    mov rdx, [rbx + ASMWEB_TYPED_POOL.slot_state_base]
    mov rcx, rdx
    add rcx, [rbx + ASMWEB_TYPED_POOL.slot_metadata_bytes]
    jc .init_integrity


    ; candidate / slot-state
    cmp r10, rdx
    jbe .init_candidate_slot_state_separate

    cmp rcx, rbp
    ja .init_integrity


.init_candidate_slot_state_separate:

    ; generation / slot-state
    cmp r9, rdx
    jbe .init_regions_valid

    cmp rcx, r12
    ja .init_integrity


.init_regions_valid:

    ; -----------------------------------------------------------------------
    ; Generation metadata must begin pristine.
    ; -----------------------------------------------------------------------

    xor ecx, ecx

.init_generation_zero_scan:
    cmp rcx, r13
    jae .init_commit

    cmp qword [r12 + rcx * 8], 0
    jne .init_integrity

    inc rcx
    jmp .init_generation_zero_scan


.init_commit:

    ; -----------------------------------------------------------------------
    ; No fallible operation remains.
    ;
    ; Initialize candidate generation metadata first.
    ; -----------------------------------------------------------------------

    xor ecx, ecx

.init_generation_one_loop:
    cmp rcx, r13
    jae .init_publish

    mov qword [r12 + rcx * 8], 1

    inc rcx
    jmp .init_generation_one_loop


.init_publish:

    mov [rbp + ASMWEB_STALE_CANDIDATE.pool_ptr], rbx

    mov rax, [rbx + ASMWEB_TYPED_POOL.object_class_id]
    mov [rbp + ASMWEB_STALE_CANDIDATE.object_class_id], rax

    mov [rbp + ASMWEB_STALE_CANDIDATE.generation_base], r12
    mov [rbp + ASMWEB_STALE_CANDIDATE.generation_count], r13
    mov [rbp + ASMWEB_STALE_CANDIDATE.generation_bytes], r14

    mov rax, [rsp]
    mov [rbp + ASMWEB_STALE_CANDIDATE.management_bytes_total], rax

    ; Publish last.
    mov qword [rbp + ASMWEB_STALE_CANDIDATE.ready], 1

    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_STALE_RESULT_OK
    ret


.init_integrity:
    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx


.init_integrity_no_frame:
    mov eax, ASMWEB_STALE_RESULT_INTEGRITY
    ret


; ===========================================================================
; asm_stale_candidate_validate
;
; RDI = ASMWEB_STALE_CANDIDATE *
;
; Returns:
;
;   RAX = ASMWEB_STALE_RESULT_OK
;         ASMWEB_STALE_RESULT_INTEGRITY
;
; This validates the candidate representation and its relationship to the
; underlying typed pool.
;
; It does not prove concurrent reclamation safety.
; ===========================================================================

asm_stale_candidate_validate:
    cld

    test rdi, rdi
    jz .validate_integrity_no_frame

    push rbx
    mov rbx, rdi

    cmp qword [rbx + ASMWEB_STALE_CANDIDATE.ready], 1
    jne .validate_integrity

    mov rdi, [rbx + ASMWEB_STALE_CANDIDATE.pool_ptr]
    test rdi, rdi
    jz .validate_integrity

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .validate_integrity


    ; Cached object class must match current pool authority.

    mov rax, [rbx + ASMWEB_STALE_CANDIDATE.object_class_id]
    test rax, rax
    jz .validate_integrity

    mov rdx, [rbx + ASMWEB_STALE_CANDIDATE.pool_ptr]

    cmp rax, [rdx + ASMWEB_TYPED_POOL.object_class_id]
    jne .validate_integrity


    ; Generation metadata.

    mov r8, [rbx + ASMWEB_STALE_CANDIDATE.generation_base]
    test r8, r8
    jz .validate_integrity

    test r8, 7
    jnz .validate_integrity

    mov r9, [rbx + ASMWEB_STALE_CANDIDATE.generation_count]
    test r9, r9
    jz .validate_integrity

    cmp r9, [rdx + ASMWEB_TYPED_POOL.physical_capacity]
    jne .validate_integrity


    ; generation_bytes = count * 8

    mov rax, r9
    mov ecx, 8
    mul rcx

    test rdx, rdx
    jnz .validate_integrity

    cmp rax, [rbx + ASMWEB_STALE_CANDIDATE.generation_bytes]
    jne .validate_integrity

    mov r10, rax


    ; management total must remain exact.

    add rax, ASMWEB_STALE_CANDIDATE_size
    jc .validate_integrity

    cmp rax, [rbx + ASMWEB_STALE_CANDIDATE.management_bytes_total]
    jne .validate_integrity


    ; Generation range must not wrap.

    mov rax, r8
    add rax, r10
    jc .validate_integrity


    ; Every represented generation must remain non-zero.

    xor ecx, ecx

.validate_generation_scan:
    cmp rcx, r9
    jae .validate_success

    cmp qword [r8 + rcx * 8], 0
    je .validate_integrity

    inc rcx
    jmp .validate_generation_scan


.validate_success:
    pop rbx

    mov eax, ASMWEB_STALE_RESULT_OK
    ret


.validate_integrity:
    pop rbx


.validate_integrity_no_frame:
    mov eax, ASMWEB_STALE_RESULT_INTEGRITY
    ret


; ===========================================================================
; asm_stale_candidate_lookup
;
; RDI = ASMWEB_STALE_CANDIDATE *
; RSI = ASMWEB_STALE_HANDLE *
;
; Returns:
;
;   RAX = ASMWEB_STALE_RESULT_OK
;         ASMWEB_STALE_RESULT_REJECTED
;         ASMWEB_STALE_RESULT_INTEGRITY
;
;   RDX = current raw object pointer on success
;         zero otherwise
;
; REJECTED means the presented durable candidate identity is not the current
; lifetime identity for an owned ordinary pool slot.
;
; Validation order deliberately checks:
;
;   class;
;   index;
;   non-zero generation;
;   current generation;
;   slot ownership;
;   pointer arithmetic.
; ===========================================================================

asm_stale_candidate_lookup:
    cld

    test rdi, rdi
    jz .lookup_integrity_no_frame

    test rsi, rsi
    jz .lookup_integrity_no_frame

    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    call asm_stale_candidate_validate

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .lookup_integrity


    ; Class identity.

    mov rax, [r12 + ASMWEB_STALE_HANDLE.object_class_id]

    cmp rax, [rbx + ASMWEB_STALE_CANDIDATE.object_class_id]
    jne .lookup_rejected


    ; Index must identify an ordinary-acquirable pool slot.

    mov r13, [r12 + ASMWEB_STALE_HANDLE.slot_index]

    mov r8, [rbx + ASMWEB_STALE_CANDIDATE.pool_ptr]

    cmp r13, [r8 + ASMWEB_TYPED_POOL.ordinary_capacity]
    jae .lookup_rejected


    ; Generation identity.

    mov rax, [r12 + ASMWEB_STALE_HANDLE.generation]
    test rax, rax
    jz .lookup_rejected

    mov r9, [rbx + ASMWEB_STALE_CANDIDATE.generation_base]

    cmp rax, [r9 + r13 * 8]
    jne .lookup_rejected


    ; Slot must currently be owned.

    mov r10, [r8 + ASMWEB_TYPED_POOL.slot_state_base]

    cmp byte [r10 + r13], ASMWEB_POOL_SLOT_OWNED
    jne .lookup_rejected


    ; Calculate exact raw slot pointer.

    mov rax, r13
    mul qword [r8 + ASMWEB_TYPED_POOL.effective_stride]

    test rdx, rdx
    jnz .lookup_integrity

    add rax, [r8 + ASMWEB_TYPED_POOL.backing_base]
    jc .lookup_integrity

    mov rdx, rax

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_STALE_RESULT_OK
    ret


.lookup_rejected:
    xor edx, edx

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_STALE_RESULT_REJECTED
    ret


.lookup_integrity:
    xor edx, edx

    pop r13
    pop r12
    pop rbx


.lookup_integrity_no_frame:
    xor edx, edx
    mov eax, ASMWEB_STALE_RESULT_INTEGRITY
    ret


; ===========================================================================
; asm_stale_candidate_acquire
;
; RDI = ASMWEB_STALE_CANDIDATE *
; RSI = pristine ASMWEB_STALE_HANDLE *
;
; Returns:
;
;   RAX = ASMWEB_STALE_RESULT_OK
;         ASMWEB_STALE_RESULT_REJECTED
;         ASMWEB_STALE_RESULT_INTEGRITY
;
;   RDX = acquired raw object pointer on success
;         zero otherwise
;
; The underlying pool acquisition occurs first. The candidate then derives the
; slot index and publishes the corresponding current generation.
;
; If post-acquisition candidate construction detects an internal contradiction,
; the routine attempts to roll the pool acquisition back before returning.
;
; The handle is written only after candidate construction has succeeded.
; ===========================================================================

asm_stale_candidate_acquire:
    cld

    test rdi, rdi
    jz .acquire_integrity_no_frame

    test rsi, rsi
    jz .acquire_integrity_no_frame

    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r13, rsi                    ; output handle


    call asm_stale_candidate_validate

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .acquire_integrity


    ; Output handle must be pristine.

    cmp qword [r13 + ASMWEB_STALE_HANDLE.object_class_id], 0
    jne .acquire_integrity

    cmp qword [r13 + ASMWEB_STALE_HANDLE.slot_index], 0
    jne .acquire_integrity

    cmp qword [r13 + ASMWEB_STALE_HANDLE.generation], 0
    jne .acquire_integrity


    ; Acquire from the already-qualified pool.

    mov rdi, [rbx + ASMWEB_STALE_CANDIDATE.pool_ptr]

    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    je .acquire_pool_success

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    je .acquire_rejected

    jmp .acquire_integrity


.acquire_pool_success:
    mov r12, rdx                    ; acquired raw pointer


    ; -----------------------------------------------------------------------
    ; Derive slot index mechanically.
    ; -----------------------------------------------------------------------

    mov r8, [rbx + ASMWEB_STALE_CANDIDATE.pool_ptr]
    mov r9, [r8 + ASMWEB_TYPED_POOL.backing_base]

    cmp r12, r9
    jb .acquire_rollback

    mov rax, r12
    sub rax, r9

    xor edx, edx
    div qword [r8 + ASMWEB_TYPED_POOL.effective_stride]

    test rdx, rdx
    jnz .acquire_rollback

    ; RAX = index
    cmp rax, [r8 + ASMWEB_TYPED_POOL.ordinary_capacity]
    jae .acquire_rollback

    mov r10, rax                    ; index


    ; Generation for a legitimately initialized candidate is always non-zero.

    mov r11, [rbx + ASMWEB_STALE_CANDIDATE.generation_base]
    mov rcx, [r11 + r10 * 8]

    test rcx, rcx
    jz .acquire_rollback


    ; -----------------------------------------------------------------------
    ; Publish candidate handle only after all checks have succeeded.
    ; -----------------------------------------------------------------------

    mov rax, [rbx + ASMWEB_STALE_CANDIDATE.object_class_id]
    mov [r13 + ASMWEB_STALE_HANDLE.object_class_id], rax

    mov [r13 + ASMWEB_STALE_HANDLE.slot_index], r10
    mov [r13 + ASMWEB_STALE_HANDLE.generation], rcx

    mov rdx, r12

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_STALE_RESULT_OK
    ret


.acquire_rollback:

    ; Candidate publication did not occur. Reclaim the acquired pool slot.
    mov rdi, [rbx + ASMWEB_STALE_CANDIDATE.pool_ptr]
    mov rsi, r12

    call asm_typed_pool_release

    ; Rollback failure is an integrity failure and cannot be disguised as
    ; ordinary candidate rejection.
    cmp eax, ASMWEB_RESOURCE_OK
    jne .acquire_integrity

    jmp .acquire_integrity


.acquire_rejected:
    xor edx, edx

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_STALE_RESULT_REJECTED
    ret


.acquire_integrity:
    xor edx, edx

    pop r13
    pop r12
    pop rbx


.acquire_integrity_no_frame:
    xor edx, edx
    mov eax, ASMWEB_STALE_RESULT_INTEGRITY
    ret


; ===========================================================================
; asm_stale_candidate_release
;
; RDI = ASMWEB_STALE_CANDIDATE *
; RSI = ASMWEB_STALE_HANDLE *
;
; Returns:
;
;   RAX = ASMWEB_STALE_RESULT_OK
;         ASMWEB_STALE_RESULT_REJECTED
;         ASMWEB_STALE_RESULT_INTEGRITY
;
; Successful release:
;
;   1. validates the presented lifetime identity;
;   2. verifies generation can advance without wrap;
;   3. releases the underlying pool object;
;   4. advances that slot generation exactly once.
;
; The caller's old handle is intentionally NOT modified. It becomes stale and
; must subsequently fail lookup.
;
; Candidate generation exhaustion:
;
;   generation == UINT64_MAX
;
; causes bounded REJECTED with no state mutation. This exposes rather than
; hides the finite-width limitation. Final generation width/policy remains a
; deferred architectural decision.
;
; This single-threaded candidate ordering does NOT establish concurrent
; reclamation or ABA safety.
; ===========================================================================

asm_stale_candidate_release:
    cld

    test rdi, rdi
    jz .release_integrity_no_frame

    test rsi, rsi
    jz .release_integrity_no_frame

    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; candidate
    mov r13, rsi                    ; handle


    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_OK
    je .release_lookup_ok

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    je .release_rejected

    jmp .release_integrity


.release_lookup_ok:
    mov r12, rdx                    ; raw object pointer

    mov r14, [r13 + ASMWEB_STALE_HANDLE.slot_index]

    mov r8, [rbx + ASMWEB_STALE_CANDIDATE.generation_base]
    mov r15, [r8 + r14 * 8]


    ; Never wrap generation identity.

    mov rax, ASMWEB_U64_MAX
    cmp r15, rax
    je .release_rejected


    ; Precompute next generation before releasing ownership.

    mov rax, r15
    inc rax

    test rax, rax
    jz .release_integrity

    mov r15, rax


    ; Release pool ownership.

    mov rdi, [rbx + ASMWEB_STALE_CANDIDATE.pool_ptr]
    mov rsi, r12

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .release_integrity


    ; No fallible operation remains after successful pool release.
    ; Advance lifetime identity exactly once.

    mov r8, [rbx + ASMWEB_STALE_CANDIDATE.generation_base]
    mov [r8 + r14 * 8], r15

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_STALE_RESULT_OK
    ret


.release_rejected:
    xor edx, edx

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_STALE_RESULT_REJECTED
    ret


.release_integrity:
    xor edx, edx

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx


.release_integrity_no_frame:
    xor edx, edx
    mov eax, ASMWEB_STALE_RESULT_INTEGRITY
    ret
