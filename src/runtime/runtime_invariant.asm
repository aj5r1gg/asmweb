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
%include "asmweb/memory_ceiling.inc"
%include "asmweb/config_dependency.inc"
%include "asmweb/runtime_invariant.inc"

global asm_runtime_invariant_validate_ready

extern asm_process_runtime_validate
extern asm_registry_validate
extern asm_startup_memory_account_validate
extern asm_capacity_dependency_validate
extern asm_memory_direct_capacity_from_mot
extern asm_u64_mul_checked
extern asm_u64_add_checked


section .text


; ===========================================================================
; asm_runtime_invariant_validate_ready
;
; RDI = ASMWEB_RUNTIME_INVARIANT_VIEW *
;
; Returns:
;
;   success:
;
;       RAX = ASMWEB_RESOURCE_OK
;       RDX = derived M_direct_capacity_max
;
;   failure:
;
;       RAX = ASMWEB_RESOURCE_INTEGRITY
;       RDX = ASMWEB_RUNTIME_INVARIANT_FAIL_*
;
; This routine is deliberately a READY-state composition check.
;
; It does not define:
;
;   - future PRESSURED/DRAINING/STOPPING invariant sets;
;   - protocol-specific invariants;
;   - pool/stack invariants for production objects not yet instantiated;
;   - a general invariant-expression engine.
;
; Local subsystem invariants remain owned by their existing validators.
; ===========================================================================

asm_runtime_invariant_validate_ready:
    cld

    test rdi, rdi
    jz .fail_input_no_frame

    ; Preserve callee-saved state.
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Six pushes retain ordinary entry RSP % 16 == 8.
    ; Reserve 8 bytes to align nested CALL boundaries.
    ;
    ; [rsp] = derived M_direct_capacity_max
    sub rsp, 8

    mov rbx, rdi


    ; -----------------------------------------------------------------------
    ; Mandatory authorities.
    ; -----------------------------------------------------------------------

    mov r12, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.startup_info_ptr]
    test r12, r12
    jz .fail_input

    mov r13, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.entropy_ptr]
    test r13, r13
    jz .fail_input

    mov r14, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.cpu_ptr]
    test r14, r14
    jz .fail_input

    mov r15, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.time_ptr]
    test r15, r15
    jz .fail_input

    mov rbp, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.process_runtime_ptr]
    test rbp, rbp
    jz .fail_input

    mov rax, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.startup_memory_ptr]
    test rax, rax
    jz .fail_input

    mov rax, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.registry_ptr]
    test rax, rax
    jz .fail_input


    ; =======================================================================
    ; PROCESS RUNTIME
    ; =======================================================================

    mov rdi, rbp
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_process


    ; M0 global READY invariant is narrower than generic process validation.

    cmp qword [rbp + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY
    jne .fail_ready

    cmp qword [rbp + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STEADY_STATE
    jne .fail_ready

    cmp qword [rbp + ASMWEB_PROCESS_RUNTIME.ready], 1
    jne .fail_ready

    ; Current M0 has exactly one publication transition:
    ;
    ;   STARTING -> READY
    ;
    ; A future transition engine may replace this invariant with a broader
    ; path-aware rule. Do not silently relax it before then.
    cmp qword [rbp + ASMWEB_PROCESS_RUNTIME.transition_count], 1
    jne .fail_ready


    ; =======================================================================
    ; REGISTRY
    ; =======================================================================

    mov rdi, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.registry_ptr]
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_registry


    ; =======================================================================
    ; STARTUP MEMORY
    ; =======================================================================

    mov rdi, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.startup_memory_ptr]
    call asm_startup_memory_account_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_startup_memory


    ; =======================================================================
    ; CAPACITY DEPENDENCY GRAPH
    ; =======================================================================

    mov rdi, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_nodes_ptr]
    mov rsi, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_node_count]
    mov rdx, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_edges_ptr]
    mov rcx, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_edge_count]

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_dependency


    ; =======================================================================
    ; CONTROLLED STARTUP STATE
    ;
    ; At READY:
    ;
    ;   - page size remains structurally valid;
    ;   - the borrowed AT_RANDOM pointer has been invalidated.
    ; =======================================================================

    mov rax, [r12 + ASMWEB_STARTUP_INFO.page_size]

    cmp rax, ASMWEB_M0_MIN_PAGE_SIZE
    jb .fail_startup_state

    cmp rax, ASMWEB_M0_MAX_PAGE_SIZE
    ja .fail_startup_state

    lea rcx, [rax - 1]
    test rax, rcx
    jnz .fail_startup_state

    cmp qword [r12 + ASMWEB_STARTUP_INFO.at_random], 0
    jne .fail_startup_state


    ; =======================================================================
    ; ENTROPY BOOTSTRAP
    ;
    ; The seed bytes themselves may legally contain any 128-bit value.
    ; M0 therefore checks publication, not invented entropy-quality semantics.
    ; =======================================================================

    cmp qword [r13 + ASMWEB_ENTROPY_BOOTSTRAP.ready], 1
    jne .fail_entropy


    ; =======================================================================
    ; CPU BOOTSTRAP
    ; =======================================================================

    cmp qword [r14 + ASMWEB_CPU_INFO.ready], 1
    jne .fail_cpu

    bt qword [r14 + ASMWEB_CPU_INFO.features], ASMWEB_CPU_FEATURE_SSE2
    jnc .fail_cpu


    ; =======================================================================
    ; MONOTONIC TIME
    ;
    ; Validate normalized nsec and exact checked total_ns derivation:
    ;
    ;   total_ns = sec * 1,000,000,000 + nsec
    ; =======================================================================

    cmp qword [r15 + ASMWEB_MONOTONIC_TIME.ready], 1
    jne .fail_time

    mov rax, [r15 + ASMWEB_MONOTONIC_TIME.nsec]

    cmp rax, ASMWEB_NSEC_PER_SEC
    jae .fail_time


    mov rdi, [r15 + ASMWEB_MONOTONIC_TIME.sec]
    mov esi, ASMWEB_NSEC_PER_SEC

    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_time


    mov rdi, rdx
    mov rsi, [r15 + ASMWEB_MONOTONIC_TIME.nsec]

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_time

    cmp rdx, [r15 + ASMWEB_MONOTONIC_TIME.total_ns]
    jne .fail_time


    ; =======================================================================
    ; GLOBAL MEMORY RECONCILIATION
    ;
    ; Derive registered direct capacity from the authoritative MOT.
    ;
    ; At current M0 READY:
    ;
    ;   startup_memory.current_bytes == M_direct_capacity_max
    ;   startup_memory.peak_bytes   >= M_direct_capacity_max
    ;
    ; This is the cross-object relationship that no local validator owns.
    ; =======================================================================

    mov rax, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.registry_ptr]

    mov rdi, [rax + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr]
    mov rsi, [rax + ASMWEB_REGISTRY_VALIDATION_SET.mot_count]

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_memory_reconciliation

    test rdx, rdx
    jz .fail_memory_reconciliation

    mov [rsp], rdx


    mov rax, [rbx + ASMWEB_RUNTIME_INVARIANT_VIEW.startup_memory_ptr]

    mov rcx, [rsp]

    cmp [rax + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], rcx
    jne .fail_memory_reconciliation

    mov rdx, [rax + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes]

    cmp rdx, rcx
    jb .fail_memory_reconciliation


    ; -----------------------------------------------------------------------
    ; Success.
    ; -----------------------------------------------------------------------

    mov rdx, [rsp]

    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.fail_input:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    jmp .fail


.fail_process:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_PROCESS
    jmp .fail


.fail_registry:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_REGISTRY
    jmp .fail


.fail_startup_memory:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_STARTUP_MEMORY
    jmp .fail


.fail_dependency:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_DEPENDENCY
    jmp .fail


.fail_startup_state:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_STARTUP_STATE
    jmp .fail


.fail_entropy:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_ENTROPY
    jmp .fail


.fail_cpu:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_CPU
    jmp .fail


.fail_time:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_TIME
    jmp .fail


.fail_memory_reconciliation:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_MEMORY_RECONCILIATION
    jmp .fail


.fail_ready:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_READY_STATE


.fail:
    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


.fail_input_no_frame:
    mov edx, ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
