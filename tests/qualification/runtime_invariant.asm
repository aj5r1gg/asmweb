bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/startup.inc"
%include "asmweb/entropy.inc"
%include "asmweb/cpu.inc"
%include "asmweb/time.inc"
%include "asmweb/process_runtime.inc"
%include "asmweb/startup_memory.inc"
%include "asmweb/registry.inc"
%include "asmweb/config_dependency.inc"
%include "asmweb/runtime_invariant.inc"

global _start

extern asm_runtime_invariant_validate_ready
extern asm_linux_exit


%define QUAL_OBJECT_ID  0x710001
%define QUAL_LIMIT_ID   0x720001


section .bss

alignb 8
startup_info:
    resb ASMWEB_STARTUP_INFO_size

entropy:
    resb ASMWEB_ENTROPY_BOOTSTRAP_size

cpu_info:
    resb ASMWEB_CPU_INFO_size

mono_time:
    resb ASMWEB_MONOTONIC_TIME_size

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


view:
    resb ASMWEB_RUNTIME_INVARIANT_VIEW_size


dep_node:
    resb ASMWEB_CAPACITY_DEPENDENCY_NODE_size


section .text


; ===========================================================================
; qual_build_valid_fixture
;
; Rebuild one complete valid READY-state invariant fixture.
;
; Registry:
;
;   one active fixed 64-byte object
;   maximum/physical/configured count = 1
;
; Therefore:
;
;   M_direct_capacity_max = 64
;
; Startup memory:
;
;   current = 64
;   peak    = 64
; ===========================================================================

qual_build_valid_fixture:
    cld


    ; -----------------------------------------------------------------------
    ; Startup state.
    ; -----------------------------------------------------------------------

    mov qword [rel startup_info + ASMWEB_STARTUP_INFO.page_size], 4096
    mov qword [rel startup_info + ASMWEB_STARTUP_INFO.at_random], 0


    ; -----------------------------------------------------------------------
    ; Entropy.
    ; -----------------------------------------------------------------------

    mov qword [rel entropy + ASMWEB_ENTROPY_BOOTSTRAP.seed_lo], 0x11111111
    mov qword [rel entropy + ASMWEB_ENTROPY_BOOTSTRAP.seed_hi], 0x22222222
    mov qword [rel entropy + ASMWEB_ENTROPY_BOOTSTRAP.ready], 1


    ; -----------------------------------------------------------------------
    ; CPU.
    ; -----------------------------------------------------------------------

    mov qword [rel cpu_info + ASMWEB_CPU_INFO.features], \
        1 << ASMWEB_CPU_FEATURE_SSE2

    mov qword [rel cpu_info + ASMWEB_CPU_INFO.ready], 1


    ; -----------------------------------------------------------------------
    ; Monotonic time.
    ;
    ; 1 second + 2 ns = 1,000,000,002 ns.
    ; -----------------------------------------------------------------------

    mov qword [rel mono_time + ASMWEB_MONOTONIC_TIME.sec], 1
    mov qword [rel mono_time + ASMWEB_MONOTONIC_TIME.nsec], 2
    mov qword [rel mono_time + ASMWEB_MONOTONIC_TIME.total_ns], \
        1000000002
    mov qword [rel mono_time + ASMWEB_MONOTONIC_TIME.ready], 1


    ; -----------------------------------------------------------------------
    ; Process READY state.
    ; -----------------------------------------------------------------------

    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY

    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STEADY_STATE

    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.ready], 1
    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.initialised], 1
    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.generation], 1
    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.transition_count], 1


    ; -----------------------------------------------------------------------
    ; Startup memory.
    ; -----------------------------------------------------------------------

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], \
        64

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], \
        64

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], \
        1


    ; -----------------------------------------------------------------------
    ; OLR.
    ; -----------------------------------------------------------------------

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


    ; -----------------------------------------------------------------------
    ; MOT.
    ; -----------------------------------------------------------------------

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


    ; -----------------------------------------------------------------------
    ; Registry set.
    ; -----------------------------------------------------------------------

    lea rax, [rel olr]
    mov [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    lea rax, [rel mot]
    mov [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1

    mov qword [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], 0
    mov qword [rel registry_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 0


    ; -----------------------------------------------------------------------
    ; Canonically empty dependency graph.
    ; -----------------------------------------------------------------------

    mov qword [rel dep_node + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id], 0
    mov qword [rel dep_node + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], 0
    mov qword [rel dep_node + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], 0
    mov qword [rel dep_node + ASMWEB_CAPACITY_DEPENDENCY_NODE.dependency_rank], 0


    ; -----------------------------------------------------------------------
    ; View.
    ; -----------------------------------------------------------------------

    lea rax, [rel startup_info]
    mov [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.startup_info_ptr], rax

    lea rax, [rel entropy]
    mov [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.entropy_ptr], rax

    lea rax, [rel cpu_info]
    mov [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.cpu_ptr], rax

    lea rax, [rel mono_time]
    mov [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.time_ptr], rax

    lea rax, [rel process_runtime]
    mov [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.process_runtime_ptr], rax

    lea rax, [rel startup_memory]
    mov [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.startup_memory_ptr], rax

    lea rax, [rel registry_set]
    mov [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.registry_ptr], rax

    mov qword [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_nodes_ptr], 0
    mov qword [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_node_count], 0
    mov qword [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_edges_ptr], 0
    mov qword [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_edge_count], 0

    ret


; ===========================================================================
; Exit cases:
;
;   0  PASS
;   1  valid READY invariant set rejected
;   2  NULL view classification failed
;   3  process corruption classification failed
;   4  READY-state contradiction classification failed
;   5  registry corruption classification failed
;   6  startup-memory corruption classification failed
;   7  dependency corruption classification failed
;   8  startup-state corruption classification failed
;   9  entropy corruption classification failed
;   10 CPU corruption classification failed
;   11 monotonic nsec corruption classification failed
;   12 monotonic total derivation corruption classification failed
;   13 memory reconciliation corruption classification failed
;   14 startup peak relationship corruption classification failed
;   15 ABI/DF preservation failed
; ===========================================================================

_start:
    cld


    ; =======================================================================
    ; CASE 1 — complete valid READY invariant set
    ; =======================================================================

    call qual_build_valid_fixture

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1

    cmp rdx, 64
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — NULL input
    ; =======================================================================

    xor edi, edi
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_2

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — generic process structure corruption
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.generation], 0

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_3

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_PROCESS
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — structurally valid process state but not the M0 READY invariant
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel process_runtime + ASMWEB_PROCESS_RUNTIME.transition_count], 2

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_READY_STATE
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — registry contradiction
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel mot + ASMWEB_MOT_VALIDATION_ENTRY.configured_capacity], 2

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_REGISTRY
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — startup-memory local contradiction
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], \
        65

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], \
        64

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_6

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_STARTUP_MEMORY
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — dependency graph canonicality contradiction
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_node_count], 1
    mov qword [rel view + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_nodes_ptr], 0

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_7

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_DEPENDENCY
    jne .fail_7


    ; =======================================================================
    ; CASE 8 — borrowed startup entropy pointer survived READY
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel startup_info + ASMWEB_STARTUP_INFO.at_random], 0x1000

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_8

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_STARTUP_STATE
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — entropy not published
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel entropy + ASMWEB_ENTROPY_BOOTSTRAP.ready], 0

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_ENTROPY
    jne .fail_9


    ; =======================================================================
    ; CASE 10 — required x86-64 CPU baseline missing
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel cpu_info + ASMWEB_CPU_INFO.features], 0

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_CPU
    jne .fail_10


    ; =======================================================================
    ; CASE 11 — non-normalized monotonic nsec
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel mono_time + ASMWEB_MONOTONIC_TIME.nsec], \
        ASMWEB_NSEC_PER_SEC

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_TIME
    jne .fail_11


    ; =======================================================================
    ; CASE 12 — total_ns does not equal checked sec/nsec derivation
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel mono_time + ASMWEB_MONOTONIC_TIME.total_ns], \
        1000000003

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_TIME
    jne .fail_12


    ; =======================================================================
    ; CASE 13 — locally valid startup memory contradicts MOT capacity
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], \
        63

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], \
        64

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_MEMORY_RECONCILIATION
    jne .fail_13


    ; =======================================================================
    ; CASE 14 — peak cannot fall below reconciled persistent capacity
    ;
    ; Keep local startup-memory structure valid by setting both to 63.
    ; Global reconciliation must reject it.
    ; =======================================================================

    call qual_build_valid_fixture

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], \
        63

    mov qword [rel startup_memory + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], \
        63

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14

    cmp edx, ASMWEB_RUNTIME_INVARIANT_FAIL_MEMORY_RECONCILIATION
    jne .fail_14


    ; =======================================================================
    ; CASE 15 — ABI callee-saved state + DF clear
    ; =======================================================================

    call qual_build_valid_fixture


    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std

    lea rdi, [rel view]
    call asm_runtime_invariant_validate_ready

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_15

    cmp rdx, 64
    jne .fail_15


    cmp rbx, 0x11111111
    jne .fail_15

    cmp rbp, 0x22222222
    jne .fail_15

    cmp r12, 0x33333333
    jne .fail_15

    cmp r13, 0x44444444
    jne .fail_15

    mov rax, 0x55555555
    cmp r14, rax
    jne .fail_15

    mov rax, 0x66666666
    cmp r15, rax
    jne .fail_15


    pushfq
    pop rax

    test rax, 1 << 10
    jnz .fail_15


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
