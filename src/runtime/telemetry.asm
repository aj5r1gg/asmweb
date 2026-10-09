bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/process_runtime.inc"
%include "asmweb/startup_memory.inc"
%include "asmweb/registry.inc"
%include "asmweb/memory_ceiling.inc"
%include "asmweb/pool.inc"
%include "asmweb/quiescence.inc"
%include "asmweb/telemetry.inc"

global asm_runtime_telemetry_init
global asm_runtime_telemetry_validate
global asm_runtime_telemetry_capture
global asm_runtime_telemetry_record_rss

extern asm_process_runtime_validate
extern asm_startup_memory_account_validate
extern asm_registry_validate
extern asm_memory_direct_capacity_from_mot
extern asm_mapping_capacity_validate
extern asm_typed_pool_validate
extern asm_quiescence_validate
extern asm_quiescence_evaluate


section .text


; ===========================================================================
; asm_runtime_telemetry_init
;
; RDI = pristine ASMWEB_RUNTIME_TELEMETRY *
;
; Requires the complete destination to be zero.
;
; Publishes ready=1 last.
; ===========================================================================

asm_runtime_telemetry_init:
    cld

    test rdi, rdi
    jz .init_integrity

    xor ecx, ecx


.init_pristine_loop:
    cmp rcx, ASMWEB_RUNTIME_TELEMETRY_size / 8
    jae .init_commit

    cmp qword [rdi + rcx * 8], 0
    jne .init_integrity

    inc rcx
    jmp .init_pristine_loop


.init_commit:
    mov qword [rdi + ASMWEB_RUNTIME_TELEMETRY.ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret


.init_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_runtime_telemetry_validate
;
; RDI = ASMWEB_RUNTIME_TELEMETRY *
;
; This validates the telemetry representation itself.
;
; It does NOT revalidate the live source authorities from which the last
; snapshot was captured.
; ===========================================================================

asm_runtime_telemetry_validate:
    cld

    test rdi, rdi
    jz .validate_integrity

    cmp qword [rdi + ASMWEB_RUNTIME_TELEMETRY.ready], 1
    jne .validate_integrity


    ; Only defined source bits may be present.

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.source_present]
    mov rcx, ASMWEB_TELEMETRY_SOURCE_MASK_ALL
    not rcx
    test rax, rcx
    jnz .validate_integrity


    ; Startup current <= startup peak.

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.startup_current_bytes]

    cmp rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.startup_peak_bytes]
    ja .validate_integrity


    ; If mapping snapshot is absent, every mapping field must be zero.

    test qword [rdi + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_MAPPING
    jnz .validate_mapping_present

    xor eax, eax

    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_configured_count], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_configured_bytes], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_current_count], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_current_bytes], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_count], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_bytes], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_acquisition_count], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_release_count], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_rejection_count], rax
    jne .validate_integrity

    jmp .validate_pool_presence


.validate_mapping_present:
    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_current_count]
    mov rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_count]

    cmp rax, rcx
    ja .validate_integrity

    cmp rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_configured_count]
    ja .validate_integrity

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_current_bytes]
    mov rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_bytes]

    cmp rax, rcx
    ja .validate_integrity

    cmp rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_configured_bytes]
    ja .validate_integrity

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_acquisition_count]
    mov rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_release_count]

    cmp rax, rcx
    jb .validate_integrity

    sub rax, rcx

    cmp rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.mapping_current_count]
    jne .validate_integrity


.validate_pool_presence:

    ; If pool snapshot is absent, every pool field must be zero.

    test qword [rdi + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_POOL
    jnz .validate_pool_present

    xor eax, eax

    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_configured_capacity], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_reserved_capacity], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_ordinary_capacity], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_current_occupancy], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_high_water], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_acquisition_count], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_release_count], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_rejection_count], rax
    jne .validate_integrity

    jmp .validate_quiescence_presence


.validate_pool_present:
    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_reserved_capacity]
    mov rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_configured_capacity]

    cmp rax, rcx
    ja .validate_integrity

    sub rcx, rax

    cmp rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_ordinary_capacity]
    jne .validate_integrity

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_current_occupancy]
    mov rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_high_water]

    cmp rax, rcx
    ja .validate_integrity

    cmp rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_ordinary_capacity]
    ja .validate_integrity

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_acquisition_count]
    mov rcx, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_release_count]

    cmp rax, rcx
    jb .validate_integrity

    sub rax, rcx

    cmp rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.pool_current_occupancy]
    jne .validate_integrity


.validate_quiescence_presence:

    ; If quiescence snapshot is absent, every quiescence field must be zero.

    test qword [rdi + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_QUIESCENCE
    jnz .validate_quiescence_present

    xor eax, eax

    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_baseline], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_current], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_grace], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_external], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_unexplained], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_confirmed_leak], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_observation_count], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_outcome], rax
    jne .validate_integrity
    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_class_mask], rax
    jne .validate_integrity

    jmp .validate_rss


.validate_quiescence_present:
    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_baseline]

    cmp [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_current], rax
    jb .validate_integrity

    add rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_grace]
    jc .validate_integrity

    add rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_external]
    jc .validate_integrity

    add rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_unexplained]
    jc .validate_integrity

    add rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_confirmed_leak]
    jc .validate_integrity

    cmp rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_current]
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_RUNTIME_TELEMETRY.quiescence_outcome], \
        ASMWEB_QUIESCENCE_OUTCOME_INTEGRITY
    jae .validate_integrity


.validate_rss:

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_seen_mask]

    mov rcx, ASMWEB_TELEMETRY_RSS_SEEN_MASK_ALL
    not rcx
    test rax, rcx
    jnz .validate_integrity


    ; No observations means all RSS quantities remain zero.

    cmp qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_observation_count], 0
    jne .validate_rss_observed

    cmp qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_seen_mask], 0
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_initial_bytes], 0
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes], 0
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_final_bytes], 0
    jne .validate_integrity

    jmp .validate_success


.validate_rss_observed:

    ; Historical maximum must dominate any explicitly retained endpoint sample.

    test qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_seen_mask], \
        ASMWEB_TELEMETRY_RSS_SEEN_INITIAL
    jz .validate_rss_final

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_initial_bytes]

    cmp rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes]
    ja .validate_integrity


.validate_rss_final:
    test qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_seen_mask], \
        ASMWEB_TELEMETRY_RSS_SEEN_FINAL
    jz .validate_success

    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_final_bytes]

    cmp rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes]
    ja .validate_integrity


.validate_success:
    mov eax, ASMWEB_RESOURCE_OK
    ret


.validate_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_runtime_telemetry_capture
;
; RDI = ASMWEB_TELEMETRY_VIEW *
; RSI = ASMWEB_RUNTIME_TELEMETRY *
;
; Mandatory authorities:
;
;   registry
;   startup memory
;   process runtime
;
; Optional sources:
;
;   mapping capacity
;   typed pool
;   quiescence
;
; All source validation and snapshot-count arithmetic complete before any
; snapshot field is mutated.
;
; RSS state is not changed by capture.
; ===========================================================================

asm_runtime_telemetry_capture:
    cld

    test rdi, rdi
    jz .capture_integrity_no_frame

    test rsi, rsi
    jz .capture_integrity_no_frame

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Six pushes leave RSP % 16 == 8.
    ;
    ; Reserve 24 bytes:
    ;
    ;   [rsp + 0]  next snapshot_count
    ;   [rsp + 8]  quiescence outcome
    ;   [rsp + 16] quiescence class mask
    ;
    ; RSP % 16 == 0 before nested calls.
    sub rsp, 24

    mov rbx, rdi
    mov rbp, rsi


    ; Existing telemetry state must itself be coherent.

    mov rdi, rbp
    call asm_runtime_telemetry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .capture_integrity


    ; Historical snapshot count must never wrap.

    mov rax, [rbp + ASMWEB_RUNTIME_TELEMETRY.snapshot_count]

    cmp rax, ASMWEB_U64_MAX
    je .capture_integrity

    inc rax
    mov [rsp], rax


    ; Mandatory source pointers.

    mov r12, [rbx + ASMWEB_TELEMETRY_VIEW.registry_ptr]
    test r12, r12
    jz .capture_integrity

    mov r13, [rbx + ASMWEB_TELEMETRY_VIEW.startup_memory_ptr]
    test r13, r13
    jz .capture_integrity

    mov r14, [rbx + ASMWEB_TELEMETRY_VIEW.process_runtime_ptr]
    test r14, r14
    jz .capture_integrity


    ; Registry.

    mov rdi, r12
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .capture_integrity


    ; M_direct_capacity_max.

    mov rdi, [r12 + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr]
    mov rsi, [r12 + ASMWEB_REGISTRY_VALIDATION_SET.mot_count]

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .capture_integrity

    mov r15, rdx


    ; Startup-memory source.

    mov rdi, r13
    call asm_startup_memory_account_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .capture_integrity


    ; Process source.

    mov rdi, r14
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .capture_integrity


    ; Optional mapping source.

    mov rax, [rbx + ASMWEB_TELEMETRY_VIEW.mapping_capacity_ptr]
    test rax, rax
    jz .capture_pool

    mov rdi, rax
    call asm_mapping_capacity_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .capture_integrity


.capture_pool:

    ; Optional pool source.

    mov rax, [rbx + ASMWEB_TELEMETRY_VIEW.pool_ptr]
    test rax, rax
    jz .capture_quiescence

    mov rdi, rax
    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .capture_integrity


.capture_quiescence:

    ; Optional quiescence source.

    mov rax, [rbx + ASMWEB_TELEMETRY_VIEW.quiescence_ptr]
    test rax, rax
    jz .capture_commit

    mov rdi, rax
    call asm_quiescence_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .capture_integrity

    mov rdi, [rbx + ASMWEB_TELEMETRY_VIEW.quiescence_ptr]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_INTEGRITY
    je .capture_integrity

    mov [rsp + 8], rax
    mov [rsp + 16], rdx


    ; =======================================================================
    ; COMMIT
    ;
    ; No fallible operation remains.
    ; =======================================================================

.capture_commit:

    mov rax, [rsp]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.snapshot_count], rax

    xor eax, eax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.source_present], rax


    ; Mandatory snapshot.

    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.direct_capacity_max], r15

    mov rax, [r13 + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.startup_current_bytes], rax

    mov rax, [r13 + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.startup_peak_bytes], rax

    mov rax, [r14 + ASMWEB_PROCESS_RUNTIME.lifecycle_state]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.lifecycle_state], rax

    mov rax, [r14 + ASMWEB_PROCESS_RUNTIME.memory_epoch]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.memory_epoch], rax

    mov rax, [r14 + ASMWEB_PROCESS_RUNTIME.transition_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.transition_count], rax


    ; -----------------------------------------------------------------------
    ; Mapping snapshot or canonical zero absence.
    ; -----------------------------------------------------------------------

    mov r10, [rbx + ASMWEB_TELEMETRY_VIEW.mapping_capacity_ptr]
    test r10, r10
    jz .commit_mapping_absent

    or qword [rbp + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_MAPPING

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.configured_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_configured_count], rax

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.configured_bytes]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_configured_bytes], rax

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.current_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_current_count], rax

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.current_bytes]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_current_bytes], rax

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.high_water_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_count], rax

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.high_water_bytes]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_bytes], rax

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.acquisition_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_acquisition_count], rax

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.release_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_release_count], rax

    mov rax, [r10 + ASMWEB_MAPPING_CAPACITY.rejection_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_rejection_count], rax

    jmp .commit_pool


.commit_mapping_absent:
    xor eax, eax

    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_configured_count], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_configured_bytes], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_current_count], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_current_bytes], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_count], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_bytes], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_acquisition_count], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_release_count], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.mapping_rejection_count], rax


    ; -----------------------------------------------------------------------
    ; Pool snapshot or canonical zero absence.
    ; -----------------------------------------------------------------------

.commit_pool:
    mov r10, [rbx + ASMWEB_TELEMETRY_VIEW.pool_ptr]
    test r10, r10
    jz .commit_pool_absent

    or qword [rbp + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_POOL

    mov rax, [r10 + ASMWEB_TYPED_POOL.configured_capacity]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_configured_capacity], rax

    mov rax, [r10 + ASMWEB_TYPED_POOL.reserved_capacity]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_reserved_capacity], rax

    mov rax, [r10 + ASMWEB_TYPED_POOL.ordinary_capacity]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_ordinary_capacity], rax

    mov rax, [r10 + ASMWEB_TYPED_POOL.current_occupancy]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_current_occupancy], rax

    mov rax, [r10 + ASMWEB_TYPED_POOL.high_water]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_high_water], rax

    mov rax, [r10 + ASMWEB_TYPED_POOL.acquisition_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_acquisition_count], rax

    mov rax, [r10 + ASMWEB_TYPED_POOL.release_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_release_count], rax

    mov rax, [r10 + ASMWEB_TYPED_POOL.rejection_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_rejection_count], rax

    jmp .commit_quiescence


.commit_pool_absent:
    xor eax, eax

    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_configured_capacity], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_reserved_capacity], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_ordinary_capacity], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_current_occupancy], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_high_water], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_acquisition_count], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_release_count], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.pool_rejection_count], rax


    ; -----------------------------------------------------------------------
    ; Quiescence snapshot or canonical zero absence.
    ; -----------------------------------------------------------------------

.commit_quiescence:
    mov r10, [rbx + ASMWEB_TELEMETRY_VIEW.quiescence_ptr]
    test r10, r10
    jz .commit_quiescence_absent

    or qword [rbp + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_QUIESCENCE

    mov rax, [r10 + ASMWEB_QUIESCENCE_STATE.baseline]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_baseline], rax

    mov rax, [r10 + ASMWEB_QUIESCENCE_STATE.current]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_current], rax

    mov rax, [r10 + ASMWEB_QUIESCENCE_STATE.grace_transient]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_grace], rax

    mov rax, [r10 + ASMWEB_QUIESCENCE_STATE.external_completion_pending]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_external], rax

    mov rax, [r10 + ASMWEB_QUIESCENCE_STATE.unexplained_retained]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_unexplained], rax

    mov rax, [r10 + ASMWEB_QUIESCENCE_STATE.confirmed_leak]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_confirmed_leak], rax

    mov rax, [r10 + ASMWEB_QUIESCENCE_STATE.observation_count]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_observation_count], rax

    mov rax, [rsp + 8]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_outcome], rax

    mov rax, [rsp + 16]
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_class_mask], rax

    jmp .capture_success


.commit_quiescence_absent:
    xor eax, eax

    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_baseline], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_current], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_grace], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_external], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_unexplained], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_confirmed_leak], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_observation_count], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_outcome], rax
    mov [rbp + ASMWEB_RUNTIME_TELEMETRY.quiescence_class_mask], rax


.capture_success:
    add rsp, 24

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.capture_integrity:
    add rsp, 24

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx


.capture_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_runtime_telemetry_record_rss
;
; RDI = ASMWEB_RUNTIME_TELEMETRY *
; RSI = ASMWEB_TELEMETRY_RSS_PHASE_*
; RDX = observed RSS bytes
;
; The measurement itself is supplied by a future trusted provider.
;
; Semantics:
;
;   INITIAL:
;       may be recorded once;
;
;   SAMPLE:
;       may be recorded any number of times;
;
;   FINAL:
;       may be recorded once;
;
; every successful observation:
;
;   rss_observation_count += 1
;   rss_max_bytes = max(rss_max_bytes, observed)
;
; Historical counters never wrap.
;
; Failure is atomic.
; ===========================================================================

asm_runtime_telemetry_record_rss:
    cld

    test rdi, rdi
    jz .rss_integrity

    cmp qword [rdi + ASMWEB_RUNTIME_TELEMETRY.ready], 1
    jne .rss_integrity

    cmp rsi, ASMWEB_TELEMETRY_RSS_PHASE_INITIAL
    jb .rss_integrity

    cmp rsi, ASMWEB_TELEMETRY_RSS_PHASE_FINAL
    ja .rss_integrity


    mov rax, [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_observation_count]

    cmp rax, ASMWEB_U64_MAX
    je .rss_integrity

    lea r8, [rax + 1]


    ; Pre-calculate next max.

    mov r9, [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes]

    cmp rdx, r9
    jbe .rss_max_ready

    mov r9, rdx


.rss_max_ready:

    cmp rsi, ASMWEB_TELEMETRY_RSS_PHASE_INITIAL
    je .rss_initial

    cmp rsi, ASMWEB_TELEMETRY_RSS_PHASE_FINAL
    je .rss_final

    jmp .rss_commit_common


.rss_initial:
    test qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_seen_mask], \
        ASMWEB_TELEMETRY_RSS_SEEN_INITIAL
    jnz .rss_integrity

    ; Commit INITIAL endpoint.
    mov [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_initial_bytes], rdx

    or qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_seen_mask], \
        ASMWEB_TELEMETRY_RSS_SEEN_INITIAL

    jmp .rss_commit_common


.rss_final:
    test qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_seen_mask], \
        ASMWEB_TELEMETRY_RSS_SEEN_FINAL
    jnz .rss_integrity

    ; Commit FINAL endpoint.
    mov [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_final_bytes], rdx

    or qword [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_seen_mask], \
        ASMWEB_TELEMETRY_RSS_SEEN_FINAL


.rss_commit_common:
    mov [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes], r9
    mov [rdi + ASMWEB_RUNTIME_TELEMETRY.rss_observation_count], r8

    mov eax, ASMWEB_RESOURCE_OK
    ret


.rss_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
