bits 64

%include "asmweb/abi.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/resource.inc"
%include "asmweb/pool.inc"

global asm_typed_pool_init
global asm_typed_pool_validate
global asm_typed_pool_acquire
global asm_typed_pool_release
global asm_typed_pool_quiescent

section .text


; ===========================================================================
; asm_typed_pool_init
;
; RDI = ASMWEB_TYPED_POOL_REQUEST *
; RSI = pristine ASMWEB_TYPED_POOL *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; The caller supplies storage; this routine performs no mapping/allocation.
;
; The request, destination descriptor, payload region and slot-state region
; must be structurally non-overlapping.
;
; The slot-state region must be zero for all represented physical slots.
;
; ready is published last.
; ===========================================================================

asm_typed_pool_init:
    cld

    test rdi, rdi
    jz .init_integrity_no_frame

    test rsi, rsi
    jz .init_integrity_no_frame

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; request
    mov rbp, rsi                    ; pool


    ; -----------------------------------------------------------------------
    ; Destination descriptor must be pristine.
    ; -----------------------------------------------------------------------

    xor ecx, ecx

.init_pristine_loop:
    cmp rcx, ASMWEB_TYPED_POOL_size / 8
    jae .init_request

    cmp qword [rbp + rcx * 8], 0
    jne .init_integrity

    inc rcx
    jmp .init_pristine_loop


.init_request:

    ; Stable object-class identity.

    mov rax, [rbx + ASMWEB_TYPED_POOL_REQUEST.object_class_id]
    test rax, rax
    jz .init_integrity


    ; Backing and slot-state pointers/capacities.

    mov r12, [rbx + ASMWEB_TYPED_POOL_REQUEST.backing_base]
    test r12, r12
    jz .init_integrity

    mov r13, [rbx + ASMWEB_TYPED_POOL_REQUEST.slot_state_base]
    test r13, r13
    jz .init_integrity


    ; Layout quantities.

    mov rax, [rbx + ASMWEB_TYPED_POOL_REQUEST.actual_size]
    test rax, rax
    jz .init_integrity

    mov r14, [rbx + ASMWEB_TYPED_POOL_REQUEST.effective_stride]
    test r14, r14
    jz .init_integrity

    cmp r14, rax
    jb .init_integrity


    ; Alignment must be a non-zero power of two.

    mov r15, [rbx + ASMWEB_TYPED_POOL_REQUEST.alignment]
    test r15, r15
    jz .init_integrity

    mov rax, r15
    dec rax
    test r15, rax
    jnz .init_integrity


    ; Stride must satisfy the declared alignment.

    test r14, rax
    jnz .init_integrity


    ; Backing base must satisfy the declared alignment.

    test r12, rax
    jnz .init_integrity


    ; -----------------------------------------------------------------------
    ; Capacity relationships.
    ; -----------------------------------------------------------------------

    mov r15, [rbx + ASMWEB_TYPED_POOL_REQUEST.physical_capacity]
    test r15, r15
    jz .init_integrity

    mov r10, [rbx + ASMWEB_TYPED_POOL_REQUEST.configured_capacity]

    cmp r10, r15
    ja .init_integrity

    mov r11, [rbx + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity]

    cmp r11, r10
    ja .init_integrity

    ; ordinary = configured - reserved
    mov r9, r10
    sub r9, r11


    ; -----------------------------------------------------------------------
    ; Checked payload bytes:
    ;
    ;     stride * physical_capacity
    ; -----------------------------------------------------------------------

    mov rax, r14
    mul r15

    test rdx, rdx
    jnz .init_integrity

    mov r8, rax                     ; required payload bytes

    cmp [rbx + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], r8
    jb .init_integrity


    ; M0 slot metadata is exactly one byte per physical slot.

    cmp [rbx + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], r15
    jb .init_integrity


    ; -----------------------------------------------------------------------
    ; Pointer-range arithmetic.
    ;
    ; payload_end = backing_base + required_payload
    ; metadata_end = slot_state_base + physical_capacity
    ; pool_end = pool + sizeof(pool)
    ; request_end = request + sizeof(request)
    ;
    ; Pointer wrap is an integrity/configuration error.
    ; -----------------------------------------------------------------------

    mov rax, r12
    add rax, r8
    jc .init_integrity
    mov rdx, rax                    ; payload_end

    mov rax, r13
    add rax, r15
    jc .init_integrity
    mov rcx, rax                    ; metadata_end

    mov rax, rbp
    add rax, ASMWEB_TYPED_POOL_size
    jc .init_integrity
    mov rsi, rax                    ; pool_end

    mov rax, rbx
    add rax, ASMWEB_TYPED_POOL_REQUEST_size
    jc .init_integrity
    mov rdi, rax                    ; request_end


    ; payload and slot metadata must not overlap.

    cmp rdx, r13
    jbe .init_payload_metadata_separate

    cmp rcx, r12
    ja .init_integrity


.init_payload_metadata_separate:

    ; pool descriptor and payload must not overlap.

    cmp rsi, r12
    jbe .init_pool_payload_separate

    cmp rdx, rbp
    ja .init_integrity


.init_pool_payload_separate:

    ; pool descriptor and slot metadata must not overlap.

    cmp rsi, r13
    jbe .init_pool_metadata_separate

    cmp rcx, rbp
    ja .init_integrity


.init_pool_metadata_separate:

    ; request and pool descriptor must not overlap.

    cmp rdi, rbp
    jbe .init_request_pool_separate

    cmp rsi, rbx
    ja .init_integrity


.init_request_pool_separate:

    ; request and payload must not overlap.

    cmp rdi, r12
    jbe .init_request_payload_separate

    cmp rdx, rbx
    ja .init_integrity


.init_request_payload_separate:

    ; request and slot metadata must not overlap.

    cmp rdi, r13
    jbe .init_regions_valid

    cmp rcx, rbx
    ja .init_integrity


.init_regions_valid:

    ; -----------------------------------------------------------------------
    ; Slot metadata must begin entirely FREE.
    ; -----------------------------------------------------------------------

    xor ecx, ecx

.init_slot_zero_loop:
    cmp rcx, r15
    jae .init_publish

    cmp byte [r13 + rcx], ASMWEB_POOL_SLOT_FREE
    jne .init_integrity

    inc rcx
    jmp .init_slot_zero_loop


.init_publish:

    ; -----------------------------------------------------------------------
    ; Complete every remaining fallible validation/calculation BEFORE the
    ; first descriptor store.
    ;
    ; This preserves failure atomicity: any rejected initialisation leaves the
    ; pristine destination descriptor untouched.
    ; -----------------------------------------------------------------------

    mov rdx, r15
    add rdx, ASMWEB_TYPED_POOL_size
    jc .init_integrity

    mov rsi, [rbx + ASMWEB_TYPED_POOL_REQUEST.ownership_scope]
    test rsi, rsi
    jz .init_integrity

    mov rcx, [rbx + ASMWEB_TYPED_POOL_REQUEST.partitioning_model]
    cmp rcx, ASMWEB_POOL_PARTITION_GLOBAL
    jne .init_integrity


    ; -----------------------------------------------------------------------
    ; Commit descriptor state.
    ;
    ; No fallible operation remains below this point.
    ; -----------------------------------------------------------------------

    mov rax, [rbx + ASMWEB_TYPED_POOL_REQUEST.object_class_id]
    mov [rbp + ASMWEB_TYPED_POOL.object_class_id], rax

    mov [rbp + ASMWEB_TYPED_POOL.backing_base], r12
    mov [rbp + ASMWEB_TYPED_POOL.payload_bytes], r8

    mov [rbp + ASMWEB_TYPED_POOL.slot_state_base], r13
    mov [rbp + ASMWEB_TYPED_POOL.slot_metadata_bytes], r15
    mov [rbp + ASMWEB_TYPED_POOL.management_bytes_total], rdx

    mov rax, [rbx + ASMWEB_TYPED_POOL_REQUEST.actual_size]
    mov [rbp + ASMWEB_TYPED_POOL.actual_size], rax

    mov [rbp + ASMWEB_TYPED_POOL.effective_stride], r14

    mov rax, [rbx + ASMWEB_TYPED_POOL_REQUEST.alignment]
    mov [rbp + ASMWEB_TYPED_POOL.alignment], rax

    mov [rbp + ASMWEB_TYPED_POOL.physical_capacity], r15
    mov [rbp + ASMWEB_TYPED_POOL.configured_capacity], r10
    mov [rbp + ASMWEB_TYPED_POOL.reserved_capacity], r11
    mov [rbp + ASMWEB_TYPED_POOL.ordinary_capacity], r9

    ; Current, high-water and historical counters remain zero from pristine
    ; descriptor state.

    mov [rbp + ASMWEB_TYPED_POOL.ownership_scope], rsi
    mov [rbp + ASMWEB_TYPED_POOL.partitioning_model], rcx

    ; Publication marker last.
    mov qword [rbp + ASMWEB_TYPED_POOL.ready], 1

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.init_integrity:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx


.init_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_typed_pool_validate
;
; RDI = ASMWEB_TYPED_POOL *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Validation includes:
;
;   - layout/capacity relationships;
;   - management-byte arithmetic;
;   - represented pointer ranges;
;   - slot-state vocabulary;
;   - no owned reserve/unconfigured slots;
;   - exact current occupancy;
;   - high-water relationship;
;   - acquisition/release/current historical consistency.
; ===========================================================================

asm_typed_pool_validate:
    cld

    test rdi, rdi
    jz .validate_integrity

    mov r8, rdi

    cmp qword [r8 + ASMWEB_TYPED_POOL.ready], 1
    jne .validate_integrity

    cmp qword [r8 + ASMWEB_TYPED_POOL.object_class_id], 0
    je .validate_integrity

    mov r9, [r8 + ASMWEB_TYPED_POOL.backing_base]
    test r9, r9
    jz .validate_integrity

    mov r10, [r8 + ASMWEB_TYPED_POOL.slot_state_base]
    test r10, r10
    jz .validate_integrity


    ; Layout.

    mov rax, [r8 + ASMWEB_TYPED_POOL.actual_size]
    test rax, rax
    jz .validate_integrity

    mov rcx, [r8 + ASMWEB_TYPED_POOL.effective_stride]
    test rcx, rcx
    jz .validate_integrity

    cmp rcx, rax
    jb .validate_integrity

    mov r11, [r8 + ASMWEB_TYPED_POOL.alignment]
    test r11, r11
    jz .validate_integrity

    mov rax, r11
    dec rax
    test r11, rax
    jnz .validate_integrity

    test rcx, rax
    jnz .validate_integrity

    test r9, rax
    jnz .validate_integrity


    ; Capacity relationships.

    mov rsi, [r8 + ASMWEB_TYPED_POOL.physical_capacity]
    test rsi, rsi
    jz .validate_integrity

    mov rdi, [r8 + ASMWEB_TYPED_POOL.configured_capacity]
    cmp rdi, rsi
    ja .validate_integrity

    mov rdx, [r8 + ASMWEB_TYPED_POOL.reserved_capacity]
    cmp rdx, rdi
    ja .validate_integrity

    mov rax, rdi
    sub rax, rdx

    cmp [r8 + ASMWEB_TYPED_POOL.ordinary_capacity], rax
    jne .validate_integrity


    ; Payload arithmetic.

    mov rax, [r8 + ASMWEB_TYPED_POOL.effective_stride]
    mul rsi

    test rdx, rdx
    jnz .validate_integrity

    cmp [r8 + ASMWEB_TYPED_POOL.payload_bytes], rax
    jne .validate_integrity

    mov rcx, rax                    ; payload_bytes


    ; Slot metadata and total management representation.

    cmp [r8 + ASMWEB_TYPED_POOL.slot_metadata_bytes], rsi
    jne .validate_integrity

    mov rax, rsi
    add rax, ASMWEB_TYPED_POOL_size
    jc .validate_integrity

    cmp [r8 + ASMWEB_TYPED_POOL.management_bytes_total], rax
    jne .validate_integrity


    ; Represented pointer ranges must not wrap.

    mov rax, r9
    add rax, rcx
    jc .validate_integrity
    mov rdx, rax                    ; payload_end

    mov rax, r10
    add rax, rsi
    jc .validate_integrity
    mov rdi, rax                    ; metadata_end

    mov rax, r8
    add rax, ASMWEB_TYPED_POOL_size
    jc .validate_integrity
    mov r11, rax                    ; pool_end


    ; payload / metadata overlap.

    cmp rdx, r10
    jbe .validate_payload_metadata_ok

    cmp rdi, r9
    ja .validate_integrity


.validate_payload_metadata_ok:

    ; pool / payload overlap.

    cmp r11, r9
    jbe .validate_pool_payload_ok

    cmp rdx, r8
    ja .validate_integrity


.validate_pool_payload_ok:

    ; pool / metadata overlap.

    cmp r11, r10
    jbe .validate_ranges_ok

    cmp rdi, r8
    ja .validate_integrity


.validate_ranges_ok:

    ; Occupancy/high-water relationships.

    mov rax, [r8 + ASMWEB_TYPED_POOL.current_occupancy]
    mov rcx, [r8 + ASMWEB_TYPED_POOL.ordinary_capacity]

    cmp rax, rcx
    ja .validate_integrity

    mov rdx, [r8 + ASMWEB_TYPED_POOL.high_water]

    cmp rdx, rax
    jb .validate_integrity

    cmp rdx, rcx
    ja .validate_integrity


    ; Historical accounting:
    ;
    ;     acquisition_count - release_count == current_occupancy

    mov rax, [r8 + ASMWEB_TYPED_POOL.acquisition_count]
    mov rdx, [r8 + ASMWEB_TYPED_POOL.release_count]

    cmp rax, rdx
    jb .validate_integrity

    sub rax, rdx

    cmp rax, [r8 + ASMWEB_TYPED_POOL.current_occupancy]
    jne .validate_integrity


    ; Ownership / partitioning authority.

    cmp qword [r8 + ASMWEB_TYPED_POOL.ownership_scope], 0
    je .validate_integrity

    cmp qword [r8 + ASMWEB_TYPED_POOL.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL
    jne .validate_integrity


    ; -----------------------------------------------------------------------
    ; Slot-state scan.
    ;
    ; Only ordinary slots may be OWNED.
    ; Protected reserve and physically provisioned-but-unconfigured slots
    ; remain FREE under this M0 ordinary acquisition API.
    ; -----------------------------------------------------------------------

    xor ecx, ecx                    ; index
    xor edx, edx                    ; counted ordinary owned slots

.validate_slot_loop:
    cmp rcx, rsi
    jae .validate_slot_done

    movzx eax, byte [r10 + rcx]

    cmp eax, ASMWEB_POOL_SLOT_OWNED
    ja .validate_integrity

    cmp rcx, [r8 + ASMWEB_TYPED_POOL.ordinary_capacity]
    jae .validate_nonordinary_slot

    cmp eax, ASMWEB_POOL_SLOT_OWNED
    jne .validate_slot_next

    inc rdx
    jmp .validate_slot_next


.validate_nonordinary_slot:
    cmp eax, ASMWEB_POOL_SLOT_FREE
    jne .validate_integrity


.validate_slot_next:
    inc rcx
    jmp .validate_slot_loop


.validate_slot_done:
    cmp rdx, [r8 + ASMWEB_TYPED_POOL.current_occupancy]
    jne .validate_integrity

    mov eax, ASMWEB_RESOURCE_OK
    ret


.validate_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_typed_pool_acquire
;
; RDI = ASMWEB_TYPED_POOL *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_EXHAUSTED
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = exact object-slot pointer on success
;         zero on failure
;
; Ordinary acquisition never consumes protected reserve.
;
; All fallible arithmetic/accounting checks occur before ownership publication.
; ===========================================================================

asm_typed_pool_acquire:
    cld

    test rdi, rdi
    jz .acquire_integrity_no_frame

    push rbx
    mov rbx, rdi

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .acquire_integrity


    xor ecx, ecx

.acquire_scan:
    cmp rcx, [rbx + ASMWEB_TYPED_POOL.ordinary_capacity]
    jae .acquire_exhausted

    mov r8, [rbx + ASMWEB_TYPED_POOL.slot_state_base]

    cmp byte [r8 + rcx], ASMWEB_POOL_SLOT_FREE
    je .acquire_candidate

    inc rcx
    jmp .acquire_scan


.acquire_candidate:

    ; Checked current occupancy increment.

    mov r9, [rbx + ASMWEB_TYPED_POOL.current_occupancy]

    cmp r9, ASMWEB_U64_MAX
    je .acquire_integrity

    lea r10, [r9 + 1]

    cmp r10, [rbx + ASMWEB_TYPED_POOL.ordinary_capacity]
    ja .acquire_integrity


    ; Checked historical acquisition increment.

    mov r11, [rbx + ASMWEB_TYPED_POOL.acquisition_count]

    cmp r11, ASMWEB_U64_MAX
    je .acquire_integrity

    inc r11


    ; Calculate candidate pointer before ownership publication.

    mov rax, rcx
    mul qword [rbx + ASMWEB_TYPED_POOL.effective_stride]

    test rdx, rdx
    jnz .acquire_integrity

    add rax, [rbx + ASMWEB_TYPED_POOL.backing_base]
    jc .acquire_integrity

    mov rdx, rax


    ; -----------------------------------------------------------------------
    ; Commit.
    ; -----------------------------------------------------------------------

    mov byte [r8 + rcx], ASMWEB_POOL_SLOT_OWNED

    mov [rbx + ASMWEB_TYPED_POOL.current_occupancy], r10
    mov [rbx + ASMWEB_TYPED_POOL.acquisition_count], r11

    cmp r10, [rbx + ASMWEB_TYPED_POOL.high_water]
    jbe .acquire_success

    mov [rbx + ASMWEB_TYPED_POOL.high_water], r10


.acquire_success:
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.acquire_exhausted:

    mov rax, [rbx + ASMWEB_TYPED_POOL.rejection_count]

    cmp rax, ASMWEB_U64_MAX
    je .acquire_integrity

    inc rax
    mov [rbx + ASMWEB_TYPED_POOL.rejection_count], rax

    xor edx, edx

    pop rbx

    mov eax, ASMWEB_RESOURCE_EXHAUSTED
    ret


.acquire_integrity:
    xor edx, edx
    pop rbx


.acquire_integrity_no_frame:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_typed_pool_release
;
; RDI = ASMWEB_TYPED_POOL *
; RSI = exact pointer returned by asm_typed_pool_acquire
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Release rejects:
;
;   - NULL pointer;
;   - pointer below backing;
;   - interior/non-stride pointer;
;   - reserve/unconfigured slot;
;   - already-free slot;
;   - contradictory accounting.
;
; Successful release terminates the raw-pointer ownership lifetime.
; ===========================================================================

asm_typed_pool_release:
    cld

    test rdi, rdi
    jz .release_integrity_no_frame

    test rsi, rsi
    jz .release_integrity_no_frame

    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .release_integrity


    mov r13, [rbx + ASMWEB_TYPED_POOL.backing_base]

    cmp r12, r13
    jb .release_integrity

    mov rax, r12
    sub rax, r13


    ; Exact stride-start requirement.

    xor edx, edx
    div qword [rbx + ASMWEB_TYPED_POOL.effective_stride]

    test rdx, rdx
    jnz .release_integrity


    ; Quotient is slot index.

    cmp rax, [rbx + ASMWEB_TYPED_POOL.ordinary_capacity]
    jae .release_integrity

    mov r8, [rbx + ASMWEB_TYPED_POOL.slot_state_base]

    cmp byte [r8 + rax], ASMWEB_POOL_SLOT_OWNED
    jne .release_integrity


    ; Accounting must permit release before mutation.

    mov rcx, [rbx + ASMWEB_TYPED_POOL.current_occupancy]
    test rcx, rcx
    jz .release_integrity

    mov rdx, [rbx + ASMWEB_TYPED_POOL.release_count]
    cmp rdx, ASMWEB_U64_MAX
    je .release_integrity


    ; -----------------------------------------------------------------------
    ; Commit.
    ; -----------------------------------------------------------------------

    mov byte [r8 + rax], ASMWEB_POOL_SLOT_FREE

    dec rcx
    inc rdx

    mov [rbx + ASMWEB_TYPED_POOL.current_occupancy], rcx
    mov [rbx + ASMWEB_TYPED_POOL.release_count], rdx

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.release_integrity:
    pop r13
    pop r12
    pop rbx


.release_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_typed_pool_quiescent
;
; RDI = ASMWEB_TYPED_POOL *
;
; Returns:
;
;   ASMWEB_RESOURCE_OK
;       valid pool at its defined quiescent baseline;
;
;   ASMWEB_RESOURCE_EXHAUSTED
;       valid pool still owns one or more ordinary slots;
;
;   ASMWEB_RESOURCE_INTEGRITY
;       invalid pool state.
; ===========================================================================

asm_typed_pool_quiescent:
    cld

    test rdi, rdi
    jz .quiescent_integrity_no_frame

    push rbx
    mov rbx, rdi

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .quiescent_integrity

    cmp qword [rbx + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .quiescent_busy

    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.quiescent_busy:
    pop rbx

    mov eax, ASMWEB_RESOURCE_EXHAUSTED
    ret


.quiescent_integrity:
    pop rbx


.quiescent_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
