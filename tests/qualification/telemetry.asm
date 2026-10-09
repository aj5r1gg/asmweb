bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/startup.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/process_runtime.inc"
%include "asmweb/startup_memory.inc"
%include "asmweb/registry.inc"
%include "asmweb/pool.inc"
%include "asmweb/quiescence.inc"
%include "asmweb/telemetry.inc"

global _start

extern asm_mapping_capacity_init
extern asm_mapping_capacity_validate

extern asm_typed_pool_init
extern asm_typed_pool_acquire
extern asm_typed_pool_release

extern asm_quiescence_init
extern asm_quiescence_observe

extern asm_runtime_telemetry_init
extern asm_runtime_telemetry_validate
extern asm_runtime_telemetry_capture
extern asm_runtime_telemetry_record_rss

extern asm_linux_exit


%define QUAL_OBJECT_ID  0x810001
%define QUAL_LIMIT_ID   0x820001


section .bss

alignb 64

telemetry:
    resb ASMWEB_RUNTIME_TELEMETRY_size

view:
    resb ASMWEB_TELEMETRY_VIEW_size

process_runtime:
    resb ASMWEB_PROCESS_RUNTIME_size

startup_memory:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size

olr:
    resb ASMWEB_OLR_VALIDATION_ENTRY_size

mot:
    resb ASMWEB_MOT_VALIDATION_ENTRY_size

registry_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size


alignb 64
mapping_capacity:
    resb ASMWEB_MAPPING_CAPACITY_size


alignb 64
pool_request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool:
    resb ASMWEB_TYPED_POOL_size

pool_payload:
    resb 64 * 4

pool_slot_state:
    resb 4


alignb 64
quiescence:
    resb ASMWEB_QUIESCENCE_STATE_size

saved_snapshot_count:
    resq 1


section .text


; ===========================================================================
; Build mandatory valid source authorities.
;
; Registry direct capacity = 64 bytes.
; ===========================================================================

qual_build_base_sources:
    cld


    ; Process READY state.

    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY

    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STEADY_STATE

    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.ready], 1
    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.initialised], 1
    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.generation], 1
    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.transition_count], 1


    ; Startup memory.

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 64
    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 96
    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 1


    ; OLR.

    mov qword [rel olr + ASMWEB_OLR_VALIDATION_ENTRY.object_id], \
        QUAL_OBJECT_ID

    mov qword [rel olr + ASMWEB_OLR_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE

    mov qword [rel olr + ASMWEB_OLR_VALIDATION_ENTRY.layout_status], \
        ASMWEB_LAYOUT_STATUS_QUALIFIED

    mov qword [rel olr + ASMWEB_OLR_VALIDATION_ENTRY.actual_size_bytes], 64
    mov qword [rel olr + ASMWEB_OLR_VALIDATION_ENTRY.effective_stride_bytes], 64
    mov qword [rel olr + ASMWEB_OLR_VALIDATION_ENTRY.pooled], 0

    mov qword [rel olr + ASMWEB_OLR_VALIDATION_ENTRY.mot_ref], \
        QUAL_LIMIT_ID


    ; MOT.

    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.limit_id], \
        QUAL_LIMIT_ID

    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE

    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.object_id], \
        QUAL_OBJECT_ID

    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.actual_size_bytes], 64
    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.effective_stride_bytes], 64
    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.pool_metadata_bytes], 0
    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.mapping_overhead_bytes], 0
    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.maximum_count], 1
    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.physical_capacity], 1
    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.configured_capacity], 1
    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.owner_resource_id], 0


    ; Registry set.

    lea rax, [rel olr]
    mov [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    lea rax, [rel mot]
    mov [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1

    mov qword [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], 0
    mov qword [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 0


    ; View mandatory sources only.

    lea rax, [rel registry_set]
    mov [rel view + ASMWEB_TELEMETRY_VIEW.registry_ptr], rax

    lea rax, [rel startup_memory]
    mov [rel view + ASMWEB_TELEMETRY_VIEW.startup_memory_ptr], rax

    lea rax, [rel process_runtime]
    mov [rel view + ASMWEB_TELEMETRY_VIEW.process_runtime_ptr], rax

    mov qword [rel view + ASMWEB_TELEMETRY_VIEW.mapping_capacity_ptr], 0
    mov qword [rel view + ASMWEB_TELEMETRY_VIEW.pool_ptr], 0
    mov qword [rel view + ASMWEB_TELEMETRY_VIEW.quiescence_ptr], 0

    ret


; ===========================================================================
; Exit codes
;
;   0  PASS
;   1  telemetry init failed
;   2  mandatory snapshot failed
;   3  mandatory snapshot values wrong
;   4  mapping validation/snapshot failed
;   5  pool snapshot failed
;   6  quiescence snapshot failed
;   7  unexplained-retained telemetry failed
;   8  source corruption accepted / capture mutated
;   9  snapshot counter wrap accepted
;   10 RSS initial observation failed
;   11 RSS maximum semantics failed
;   12 RSS lower sample reduced maximum
;   13 RSS final observation failed
;   14 duplicate RSS endpoint accepted
;   15 RSS observation counter wrap accepted
;   16 telemetry self-validation failed
;   17 mapping standalone validator failed
;   18 ABI / DF preservation failed
; ===========================================================================

_start:
    cld


    ; =======================================================================
    ; CASE 1 — telemetry initialisation
    ; =======================================================================

    lea rdi, [rel telemetry]
    call asm_runtime_telemetry_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.ready], 1
    jne .fail_1


    ; =======================================================================
    ; CASE 2/3 — mandatory source snapshot
    ; =======================================================================

    call qual_build_base_sources

    lea rdi, [rel view]
    lea rsi, [rel telemetry]

    call asm_runtime_telemetry_capture

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.snapshot_count], 1
    jne .fail_3

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.source_present], 0
    jne .fail_3

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.direct_capacity_max], 64
    jne .fail_3

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.startup_current_bytes], 64
    jne .fail_3

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.startup_peak_bytes], 96
    jne .fail_3

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY
    jne .fail_3

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.transition_count], 1
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — mapping source
    ; =======================================================================

    mov edi, 4
    mov esi, 16384
    mov edx, 4096
    lea rcx, [rel mapping_capacity]

    call asm_mapping_capacity_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4


    ; Qualification injection: coherent history representing:
    ;
    ;   acquired 3
    ;   released 1
    ;   current 2
    ;   high-water 3

    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.current_count], 2
    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 8192

    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.high_water_count], 3
    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.high_water_bytes], 12288

    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.acquisition_count], 3
    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.release_count], 1
    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.rejection_count], 2


    lea rax, [rel mapping_capacity]
    mov [rel view + ASMWEB_TELEMETRY_VIEW.mapping_capacity_ptr], rax

    lea rdi, [rel view]
    lea rsi, [rel telemetry]

    call asm_runtime_telemetry_capture

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4

    test qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_MAPPING
    jz .fail_4

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.mapping_current_count], 2
    jne .fail_4

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.mapping_high_water_count], 3
    jne .fail_4

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.mapping_rejection_count], 2
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — typed-pool source
    ; =======================================================================

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x830001

    lea rax, [rel pool_payload]
    mov [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 256

    lea rax, [rel pool_slot_state]
    mov [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 4

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 32
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 64
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 4
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 4
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 1

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], 1
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL


    lea rdi, [rel pool_request]
    lea rsi, [rel pool]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5


    lea rdi, [rel pool]
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5

    mov r12, rdx


    lea rax, [rel pool]
    mov [rel view + ASMWEB_TELEMETRY_VIEW.pool_ptr], rax

    lea rdi, [rel view]
    lea rsi, [rel telemetry]

    call asm_runtime_telemetry_capture

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5

    test qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_POOL
    jz .fail_5

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.pool_current_occupancy], 1
    jne .fail_5

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.pool_high_water], 1
    jne .fail_5

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.pool_acquisition_count], 1
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — quiescence baseline snapshot
    ; =======================================================================

    mov edi, 64
    lea rsi, [rel quiescence]

    call asm_quiescence_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6


    lea rax, [rel quiescence]
    mov [rel view + ASMWEB_TELEMETRY_VIEW.quiescence_ptr], rax

    lea rdi, [rel view]
    lea rsi, [rel telemetry]

    call asm_runtime_telemetry_capture

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6

    test qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.source_present], \
        ASMWEB_TELEMETRY_SOURCE_QUIESCENCE
    jz .fail_6

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.quiescence_baseline], 64
    jne .fail_6

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.quiescence_outcome], \
        ASMWEB_QUIESCENCE_OUTCOME_BASELINE
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — unexplained retained state is visible, not hidden
    ; =======================================================================

    lea rdi, [rel quiescence]
    mov esi, 80
    xor edx, edx
    xor ecx, ecx
    mov r8d, 16
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7


    lea rdi, [rel view]
    lea rsi, [rel telemetry]

    call asm_runtime_telemetry_capture

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.quiescence_unexplained], 16
    jne .fail_7

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.quiescence_outcome], \
        ASMWEB_QUIESCENCE_OUTCOME_FAIL
    jne .fail_7

    test qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.quiescence_class_mask], \
        ASMWEB_QUIESCENCE_CLASS_UNEXPLAINED_RETAINED
    jz .fail_7


    ; =======================================================================
    ; CASE 8 — invalid source rejects capture without incrementing snapshot
    ; =======================================================================

    mov rax, [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.snapshot_count]
    mov [rel saved_snapshot_count], rax

    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.current_count], 5

    lea rdi, [rel view]
    lea rsi, [rel telemetry]

    call asm_runtime_telemetry_capture

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_8

    mov rax, [rel saved_snapshot_count]

    cmp [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.snapshot_count], rax
    jne .fail_8

    ; Restore coherent mapping state.
    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.current_count], 2


    ; =======================================================================
    ; CASE 9 — snapshot count cannot wrap
    ; =======================================================================

    mov rax, ASMWEB_U64_MAX
    mov [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.snapshot_count], rax

    lea rdi, [rel view]
    lea rsi, [rel telemetry]

    call asm_runtime_telemetry_capture

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9

    mov qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.snapshot_count], 5


    ; =======================================================================
    ; CASE 10 — RSS initial sample
    ; =======================================================================

    lea rdi, [rel telemetry]
    mov esi, ASMWEB_TELEMETRY_RSS_PHASE_INITIAL
    mov edx, 1000

    call asm_runtime_telemetry_record_rss

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_10

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_initial_bytes], 1000
    jne .fail_10

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes], 1000
    jne .fail_10


    ; =======================================================================
    ; CASE 11 — intermediate sample raises max
    ; =======================================================================

    lea rdi, [rel telemetry]
    mov esi, ASMWEB_TELEMETRY_RSS_PHASE_SAMPLE
    mov edx, 1500

    call asm_runtime_telemetry_record_rss

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_11

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes], 1500
    jne .fail_11


    ; =======================================================================
    ; CASE 12 — lower sample does not reduce max
    ; =======================================================================

    lea rdi, [rel telemetry]
    mov esi, ASMWEB_TELEMETRY_RSS_PHASE_SAMPLE
    mov edx, 1200

    call asm_runtime_telemetry_record_rss

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes], 1500
    jne .fail_12


    ; =======================================================================
    ; CASE 13 — final sample retained, historical max preserved
    ; =======================================================================

    lea rdi, [rel telemetry]
    mov esi, ASMWEB_TELEMETRY_RSS_PHASE_FINAL
    mov edx, 1100

    call asm_runtime_telemetry_record_rss

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_13

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_final_bytes], 1100
    jne .fail_13

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes], 1500
    jne .fail_13

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_observation_count], 4
    jne .fail_13


    ; =======================================================================
    ; CASE 14 — duplicate final endpoint rejected atomically
    ; =======================================================================

    lea rdi, [rel telemetry]
    mov esi, ASMWEB_TELEMETRY_RSS_PHASE_FINAL
    mov edx, 2000

    call asm_runtime_telemetry_record_rss

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_final_bytes], 1100
    jne .fail_14

    cmp qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_max_bytes], 1500
    jne .fail_14


    ; =======================================================================
    ; CASE 15 — RSS observation count cannot wrap
    ; =======================================================================

    mov rax, ASMWEB_U64_MAX
    mov [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_observation_count], rax

    lea rdi, [rel telemetry]
    mov esi, ASMWEB_TELEMETRY_RSS_PHASE_SAMPLE
    mov edx, 2000

    call asm_runtime_telemetry_record_rss

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15

    mov qword [rel telemetry + ASMWEB_RUNTIME_TELEMETRY.rss_observation_count], 4


    ; =======================================================================
    ; CASE 16 — telemetry representation validates
    ; =======================================================================

    lea rdi, [rel telemetry]
    call asm_runtime_telemetry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_16


    ; =======================================================================
    ; CASE 17 — standalone mapping validator rejects contradiction
    ; =======================================================================

    lea rdi, [rel mapping_capacity]
    call asm_mapping_capacity_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17

    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.high_water_count], 1

    lea rdi, [rel mapping_capacity]
    call asm_mapping_capacity_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17

    mov qword [rel mapping_capacity + ASMWEB_MAPPING_CAPACITY.high_water_count], 3


    ; =======================================================================
    ; Release pool object before ABI case.
    ; =======================================================================

    lea rdi, [rel pool]
    mov rsi, r12

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5


    ; =======================================================================
    ; CASE 18 — ABI / DF
    ; =======================================================================

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std

    lea rdi, [rel telemetry]
    call asm_runtime_telemetry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18

    cmp rbx, 0x11111111
    jne .fail_18

    cmp rbp, 0x22222222
    jne .fail_18

    cmp r12, 0x33333333
    jne .fail_18

    cmp r13, 0x44444444
    jne .fail_18

    mov rax, 0x55555555
    cmp r14, rax
    jne .fail_18

    mov rax, 0x66666666
    cmp r15, rax
    jne .fail_18

    pushfq
    pop rax

    test rax, 1 << 10
    jnz .fail_18


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
