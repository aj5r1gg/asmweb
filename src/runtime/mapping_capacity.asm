bits 64

%include "asmweb/abi.inc"
%include "asmweb/startup.inc"
%include "asmweb/memory.inc"
%include "asmweb/resource.inc"

global asm_mapping_capacity_init
global asm_mapping_capacity_validate
global asm_memory_map_rw_bounded
global asm_memory_unmap_bounded

extern asm_memory_map_rw
extern asm_memory_unmap

section .text

; ---------------------------------------------------------------------------
; asm_mapping_capacity_init
;
; Input:
;
;   RDI = configured maximum live mapping count
;   RSI = configured maximum live mapped bytes
;   RDX = validated runtime page size
;   RCX = writable ASMWEB_MAPPING_CAPACITY
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; The destination must be completely zero before initialisation.
;
; configured_bytes must be page aligned.
;
; Capacity-affecting hot reconfiguration is deliberately not introduced here.

asm_mapping_capacity_init:
    cld

    test rcx, rcx
    jz .init_integrity

    ; Require pristine state. Reinitialising live accounting state would
    ; destroy ownership/accounting history.
    xor eax, eax

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.configured_count], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.configured_bytes], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.current_count], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.current_bytes], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.high_water_count], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.high_water_bytes], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.acquisition_count], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.release_count], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.rejection_count], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.page_size], rax
    jne .init_integrity

    cmp [rcx + ASMWEB_MAPPING_CAPACITY.ready], rax
    jne .init_integrity

    ; Configured capacities must be meaningful.
    test rdi, rdi
    jz .init_integrity

    test rsi, rsi
    jz .init_integrity

    ; Revalidate page-size policy.
    cmp rdx, ASMWEB_M0_MIN_PAGE_SIZE
    jb .init_integrity

    cmp rdx, ASMWEB_M0_MAX_PAGE_SIZE
    ja .init_integrity

    mov rax, rdx
    lea r8, [rax - 1]
    test rax, r8
    jnz .init_integrity

    ; Configured byte capacity must be exactly page aligned.
    mov rax, rsi
    dec rdx
    test rax, rdx
    jnz .init_integrity

    mov [rcx + ASMWEB_MAPPING_CAPACITY.configured_count], rdi
    mov [rcx + ASMWEB_MAPPING_CAPACITY.configured_bytes], rsi

    xor eax, eax
    mov [rcx + ASMWEB_MAPPING_CAPACITY.current_count], rax
    mov [rcx + ASMWEB_MAPPING_CAPACITY.current_bytes], rax
    mov [rcx + ASMWEB_MAPPING_CAPACITY.high_water_count], rax
    mov [rcx + ASMWEB_MAPPING_CAPACITY.high_water_bytes], rax
    mov [rcx + ASMWEB_MAPPING_CAPACITY.acquisition_count], rax
    mov [rcx + ASMWEB_MAPPING_CAPACITY.release_count], rax
    mov [rcx + ASMWEB_MAPPING_CAPACITY.rejection_count], rax

    inc rdx
    mov [rcx + ASMWEB_MAPPING_CAPACITY.page_size], rdx
    mov qword [rcx + ASMWEB_MAPPING_CAPACITY.ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret

.init_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ---------------------------------------------------------------------------
; asm_mapping_capacity_validate
;
; RDI = ASMWEB_MAPPING_CAPACITY *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Validates the complete M0 logical accounting representation without
; acquiring or releasing any kernel resource.
;
; Invariants:
;
;   ready == 1
;
;   configured_count > 0
;   configured_bytes > 0
;
;   page_size obeys M0 page-size policy
;   configured_bytes is page aligned
;
;   current_count <= high_water_count <= configured_count
;   current_bytes <= high_water_bytes <= configured_bytes
;
;   acquisition_count >= release_count
;   acquisition_count - release_count == current_count
;
; rejection_count is historical refusal/failure state and is not derivable
; from occupancy.
; ---------------------------------------------------------------------------

asm_mapping_capacity_validate:
    cld

    test rdi, rdi
    jz .validate_integrity

    cmp qword [rdi + ASMWEB_MAPPING_CAPACITY.ready], 1
    jne .validate_integrity

    mov r8, [rdi + ASMWEB_MAPPING_CAPACITY.configured_count]
    test r8, r8
    jz .validate_integrity

    mov r9, [rdi + ASMWEB_MAPPING_CAPACITY.configured_bytes]
    test r9, r9
    jz .validate_integrity

    mov r10, [rdi + ASMWEB_MAPPING_CAPACITY.page_size]

    cmp r10, ASMWEB_M0_MIN_PAGE_SIZE
    jb .validate_integrity

    cmp r10, ASMWEB_M0_MAX_PAGE_SIZE
    ja .validate_integrity

    lea rax, [r10 - 1]
    test r10, rax
    jnz .validate_integrity

    ; configured_bytes must be page aligned.
    test r9, rax
    jnz .validate_integrity


    ; Count occupancy / high-water.

    mov rax, [rdi + ASMWEB_MAPPING_CAPACITY.current_count]
    mov rcx, [rdi + ASMWEB_MAPPING_CAPACITY.high_water_count]

    cmp rax, rcx
    ja .validate_integrity

    cmp rcx, r8
    ja .validate_integrity


    ; Byte occupancy / high-water.

    mov rax, [rdi + ASMWEB_MAPPING_CAPACITY.current_bytes]
    mov rcx, [rdi + ASMWEB_MAPPING_CAPACITY.high_water_bytes]

    cmp rax, rcx
    ja .validate_integrity

    cmp rcx, r9
    ja .validate_integrity


    ; Historical acquisition/release reconciliation.

    mov rax, [rdi + ASMWEB_MAPPING_CAPACITY.acquisition_count]
    mov rcx, [rdi + ASMWEB_MAPPING_CAPACITY.release_count]

    cmp rax, rcx
    jb .validate_integrity

    sub rax, rcx

    cmp rax, [rdi + ASMWEB_MAPPING_CAPACITY.current_count]
    jne .validate_integrity


    mov eax, ASMWEB_RESOURCE_OK
    ret


.validate_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ---------------------------------------------------------------------------
; asm_memory_map_rw_bounded
;
; Purpose:
;   Acquire one controlled mapping subject to configured mapping-count and
;   mapped-byte capacity.
;
; Input:
;
;   RDI = requested byte count
;   RSI = runtime page size
;   RDX = ASMWEB_MAPPING_CAPACITY
;   RCX = empty ASMWEB_MEMORY_MAPPING
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_EXHAUSTED
;         ASMWEB_RESOURCE_INTEGRITY
;
; Transaction rule:
;
;   Capacity occupancy is committed only AFTER mmap succeeds.
;
; Therefore a failed mmap cannot leak logical capacity.
;
; Callee-saved:
;   RBX, R12, R13, R14, R15 preserved.

asm_memory_map_rw_bounded:
    cld

    test rdx, rdx
    jz .map_integrity_no_frame

    test rcx, rcx
    jz .map_integrity_no_frame

    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Five pushes establish call alignment.
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx

    cmp qword [r13 + ASMWEB_MAPPING_CAPACITY.ready], 1
    jne .map_integrity

    ; Caller page size must match the capacity authority.
    cmp r12, [r13 + ASMWEB_MAPPING_CAPACITY.page_size]
    jne .map_integrity

    ; Mapping destination must be empty.
    cmp qword [r14 + ASMWEB_MEMORY_MAPPING.base], 0
    jne .map_integrity

    cmp qword [r14 + ASMWEB_MEMORY_MAPPING.length], 0
    jne .map_integrity

    cmp qword [r14 + ASMWEB_MEMORY_MAPPING.ready], 0
    jne .map_integrity

    test rbx, rbx
    jz .map_reject

    ; -----------------------------------------------------------------------
    ; Checked page round-up.
    ; -----------------------------------------------------------------------

    mov rax, r12
    dec rax

    mov r15, rbx
    add r15, rax
    jc .map_reject

    not rax
    and r15, rax

    test r15, r15
    jz .map_reject

    ; -----------------------------------------------------------------------
    ; Validate current accounting before using it.
    ; -----------------------------------------------------------------------

    mov rax, [r13 + ASMWEB_MAPPING_CAPACITY.current_count]
    cmp rax, [r13 + ASMWEB_MAPPING_CAPACITY.configured_count]
    ja .map_integrity

    mov rax, [r13 + ASMWEB_MAPPING_CAPACITY.current_bytes]
    cmp rax, [r13 + ASMWEB_MAPPING_CAPACITY.configured_bytes]
    ja .map_integrity

    ; -----------------------------------------------------------------------
    ; Mapping-count admission and next-state calculation.
    ; -----------------------------------------------------------------------

    mov r8, [r13 + ASMWEB_MAPPING_CAPACITY.current_count]
    add r8, 1
    jc .map_integrity

    cmp r8, [r13 + ASMWEB_MAPPING_CAPACITY.configured_count]
    ja .map_reject

    ; -----------------------------------------------------------------------
    ; Byte-capacity admission and next-state calculation.
    ; -----------------------------------------------------------------------

    mov r9, [r13 + ASMWEB_MAPPING_CAPACITY.current_bytes]
    add r9, r15
    jc .map_integrity

    cmp r9, [r13 + ASMWEB_MAPPING_CAPACITY.configured_bytes]
    ja .map_reject

    ; Historical acquisition accounting must never silently wrap.
    ;
    ; Check this BEFORE mmap so a live kernel resource is never created when
    ; its successful acquisition cannot be represented historically.
    mov r10, [r13 + ASMWEB_MAPPING_CAPACITY.acquisition_count]
    cmp r10, -1
    je .map_integrity
    inc r10

    ; -----------------------------------------------------------------------
    ; Preserve the complete logical commit tuple over asm_memory_map_rw.
    ;
    ; Five callee-saved pushes above leave RSP 16-byte aligned. Reserving
    ; another 32 bytes preserves call alignment.
    ;
    ;   [rsp + 0]  next current_count
    ;   [rsp + 8]  next current_bytes
    ;   [rsp + 16] next acquisition_count
    ;   [rsp + 24] reserved
    ; -----------------------------------------------------------------------

    sub rsp, 32

    mov [rsp], r8
    mov [rsp + 8], r9
    mov [rsp + 16], r10

    ; -----------------------------------------------------------------------
    ; Acquire the kernel mapping.
    ;
    ; Logical occupancy has NOT yet changed.
    ; -----------------------------------------------------------------------

    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call asm_memory_map_rw

    test eax, eax
    jnz .map_acquire_failed

    ; -----------------------------------------------------------------------
    ; Kernel acquisition succeeded.
    ;
    ; Every fallible accounting calculation completed before mmap.
    ; Commit is now assignment-only.
    ; -----------------------------------------------------------------------

    mov r8, [rsp]
    mov r9, [rsp + 8]
    mov r10, [rsp + 16]

    add rsp, 32

    mov [r13 + ASMWEB_MAPPING_CAPACITY.current_count], r8
    mov [r13 + ASMWEB_MAPPING_CAPACITY.current_bytes], r9
    mov [r13 + ASMWEB_MAPPING_CAPACITY.acquisition_count], r10

    ; High-water count.
    cmp r8, [r13 + ASMWEB_MAPPING_CAPACITY.high_water_count]
    jbe .map_high_bytes

    mov [r13 + ASMWEB_MAPPING_CAPACITY.high_water_count], r8

.map_high_bytes:
    cmp r9, [r13 + ASMWEB_MAPPING_CAPACITY.high_water_bytes]
    jbe .map_success

    mov [r13 + ASMWEB_MAPPING_CAPACITY.high_water_bytes], r9

.map_success:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret

.map_acquire_failed:
    ; Underlying mmap failed. No logical state was committed.
    ; Discard the precomputed commit tuple before ordinary rejection handling.
    add rsp, 32

.map_reject:
    ; Saturating historical rejection accounting.
    ;
    ; Historical accounting must not silently wrap.
    cmp qword [r13 + ASMWEB_MAPPING_CAPACITY.rejection_count], -1
    je .map_integrity

    inc qword [r13 + ASMWEB_MAPPING_CAPACITY.rejection_count]

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_EXHAUSTED
    ret

.map_integrity:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

.map_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ---------------------------------------------------------------------------
; asm_memory_unmap_bounded
;
; Purpose:
;   Release one live mapping while keeping mapping-capacity accounting
;   transactionally consistent.
;
; Input:
;
;   RDI = ASMWEB_MAPPING_CAPACITY
;   RSI = live ASMWEB_MEMORY_MAPPING
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_EXHAUSTED
;         ASMWEB_RESOURCE_INTEGRITY
;
; Transaction rule:
;
;   Logical occupancy is decremented only AFTER munmap succeeds.
;
; Double release is an integrity failure.

asm_memory_unmap_bounded:
    cld

    test rdi, rdi
    jz .unmap_integrity_no_frame

    test rsi, rsi
    jz .unmap_integrity_no_frame

    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    cmp qword [rbx + ASMWEB_MAPPING_CAPACITY.ready], 1
    jne .unmap_integrity

    cmp qword [r12 + ASMWEB_MEMORY_MAPPING.ready], 1
    jne .unmap_integrity

    mov r13, [r12 + ASMWEB_MEMORY_MAPPING.length]
    test r13, r13
    jz .unmap_integrity

    ; -----------------------------------------------------------------------
    ; Calculate complete post-release accounting BEFORE munmap.
    ;
    ; Once kernel release succeeds, no fallible accounting arithmetic remains.
    ; -----------------------------------------------------------------------

    mov r8, [rbx + ASMWEB_MAPPING_CAPACITY.current_count]
    cmp r8, 1
    jb .unmap_integrity
    dec r8

    mov r9, [rbx + ASMWEB_MAPPING_CAPACITY.current_bytes]
    cmp r9, r13
    jb .unmap_integrity
    sub r9, r13

    ; Historical release accounting must never silently wrap.
    ;
    ; Check before munmap so a kernel resource cannot disappear when its
    ; successful release cannot be represented historically.
    mov r10, [rbx + ASMWEB_MAPPING_CAPACITY.release_count]
    cmp r10, -1
    je .unmap_integrity
    inc r10

    ; -----------------------------------------------------------------------
    ; Preserve complete post-release tuple over asm_memory_unmap.
    ;
    ; Three callee-saved pushes above leave RSP 16-byte aligned.
    ;
    ;   [rsp + 0]  next current_count
    ;   [rsp + 8]  next current_bytes
    ;   [rsp + 16] next release_count
    ;   [rsp + 24] reserved
    ; -----------------------------------------------------------------------

    sub rsp, 32

    mov [rsp], r8
    mov [rsp + 8], r9
    mov [rsp + 16], r10

    ; Release kernel resource.
    mov rdi, r12
    call asm_memory_unmap

    test eax, eax
    jnz .unmap_platform_failure_with_frame

    ; -----------------------------------------------------------------------
    ; Kernel release succeeded.
    ;
    ; All fallible arithmetic completed before munmap.
    ; Logical release is now assignment-only.
    ; -----------------------------------------------------------------------

    mov r8, [rsp]
    mov r9, [rsp + 8]
    mov r10, [rsp + 16]

    add rsp, 32

    mov [rbx + ASMWEB_MAPPING_CAPACITY.current_count], r8
    mov [rbx + ASMWEB_MAPPING_CAPACITY.current_bytes], r9
    mov [rbx + ASMWEB_MAPPING_CAPACITY.release_count], r10

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret

.unmap_platform_failure_with_frame:
    ; Kernel release failed. No logical release occurred.
    ; Discard the precomputed tuple.
    add rsp, 32

.unmap_platform_failure:
    ; Mapping remains live and occupancy remains unchanged.
    cmp qword [rbx + ASMWEB_MAPPING_CAPACITY.rejection_count], -1
    je .unmap_integrity

    inc qword [rbx + ASMWEB_MAPPING_CAPACITY.rejection_count]

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_EXHAUSTED
    ret

.unmap_integrity:
    pop r13
    pop r12
    pop rbx

.unmap_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
