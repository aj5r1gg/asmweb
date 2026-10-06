bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/process_runtime.inc"
%include "asmweb/registry.inc"
%include "asmweb/startup_memory.inc"

global asm_process_runtime_init
global asm_process_runtime_validate
global asm_process_runtime_publish_ready


extern asm_registry_validate
extern asm_memory_direct_capacity_from_mot
extern asm_startup_memory_account_validate
extern asm_u64_add_checked


; ===========================================================================
; asm_process_runtime_init
;
; Input:
;   RDI = ASMWEB_PROCESS_RUNTIME *
;
; Result:
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Establishes the only M0 process-runtime initial condition currently defined:
;
;   lifecycle_state  = STARTING
;   memory_epoch     = INITIALISATION
;   ready            = 0
;   initialised      = 1
;   generation       = 1
;   transition_count = 0
;
; This routine does NOT publish READY and does NOT define the complete process
; lifecycle transition graph.
; ===========================================================================

asm_process_runtime_init:
    cld

    test rdi, rdi
    jz .init_integrity

    ; Require pristine storage so accidental re-initialisation cannot silently
    ; reset an already published process-runtime object.
    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.lifecycle_state], 0
    jne .init_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.memory_epoch], 0
    jne .init_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.ready], 0
    jne .init_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.initialised], 0
    jne .init_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.generation], 0
    jne .init_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.transition_count], 0
    jne .init_integrity

    mov qword [rdi + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STARTING

    mov qword [rdi + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION

    mov qword [rdi + ASMWEB_PROCESS_RUNTIME.ready], 0
    mov qword [rdi + ASMWEB_PROCESS_RUNTIME.initialised], 1
    mov qword [rdi + ASMWEB_PROCESS_RUNTIME.generation], 1
    mov qword [rdi + ASMWEB_PROCESS_RUNTIME.transition_count], 0

    mov eax, ASMWEB_RESOURCE_OK
    ret


.init_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_process_runtime_validate
;
; Input:
;   RDI = ASMWEB_PROCESS_RUNTIME *
;
; Result:
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Validates:
;   - non-NULL object;
;   - initialised == 1;
;   - generation != 0;
;   - lifecycle state belongs to requirements vocabulary;
;   - memory epoch belongs to Runtime & Memory vocabulary;
;   - ready is Boolean;
;   - lifecycle/epoch combinations implied by the specifications;
;   - READY lifecycle requires ready == 1;
;   - STARTING lifecycle requires ready == 0;
;
; PRESSURED remains a process-lifecycle state over STEADY_STATE. This routine
; does not yet validate detailed pressure reason/state machinery.
;
; DRAINING and STOPPING retain the previous READY-publication fact: ready may
; be either 0 or 1 because startup failure may proceed toward STOPPING without
; ever reaching READY, while an ordinary shutdown proceeds from a published
; runtime. A later transition engine will tighten path-dependent semantics.
; ===========================================================================

asm_process_runtime_validate:
    cld

    test rdi, rdi
    jz .validate_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.initialised], 1
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.generation], 0
    je .validate_integrity

    mov rax, [rdi + ASMWEB_PROCESS_RUNTIME.ready]
    cmp rax, 1
    ja .validate_integrity

    mov rax, [rdi + ASMWEB_PROCESS_RUNTIME.lifecycle_state]

    cmp rax, ASMWEB_PROCESS_STATE_MIN
    jb .validate_integrity

    cmp rax, ASMWEB_PROCESS_STATE_MAX
    ja .validate_integrity

    mov rdx, [rdi + ASMWEB_PROCESS_RUNTIME.memory_epoch]

    cmp rdx, ASMWEB_MEMORY_EPOCH_MIN
    jb .validate_integrity

    cmp rdx, ASMWEB_MEMORY_EPOCH_MAX
    ja .validate_integrity


    ; -----------------------------------------------------------------------
    ; Cross-state consistency
    ; -----------------------------------------------------------------------

    cmp rax, ASMWEB_PROCESS_STATE_STARTING
    je .validate_starting

    cmp rax, ASMWEB_PROCESS_STATE_READY
    je .validate_ready

    cmp rax, ASMWEB_PROCESS_STATE_PRESSURED
    je .validate_pressured

    cmp rax, ASMWEB_PROCESS_STATE_DRAINING
    je .validate_draining

    cmp rax, ASMWEB_PROCESS_STATE_STOPPING
    je .validate_stopping

    jmp .validate_integrity


.validate_starting:
    cmp rdx, ASMWEB_MEMORY_EPOCH_INITIALISATION
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.ready], 0
    jne .validate_integrity

    jmp .validate_success


.validate_ready:
    cmp rdx, ASMWEB_MEMORY_EPOCH_STEADY_STATE
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.ready], 1
    jne .validate_integrity

    jmp .validate_success


.validate_pressured:
    cmp rdx, ASMWEB_MEMORY_EPOCH_STEADY_STATE
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_PROCESS_RUNTIME.ready], 1
    jne .validate_integrity

    jmp .validate_success


.validate_draining:
    cmp rdx, ASMWEB_MEMORY_EPOCH_DRAINING
    jne .validate_integrity

    jmp .validate_success


.validate_stopping:
    cmp rdx, ASMWEB_MEMORY_EPOCH_STOPPING
    jne .validate_integrity


.validate_success:
    mov eax, ASMWEB_RESOURCE_OK
    ret


.validate_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret



; ===========================================================================
; asm_process_runtime_publish_ready
;
; Inputs:
;
;   RDI = ASMWEB_PROCESS_RUNTIME *
;   RSI = ASMWEB_REGISTRY_VALIDATION_SET *
;   RDX = ASMWEB_STARTUP_MEMORY_ACCOUNT *
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = derived M_direct_capacity_max on success
;         zero on failure
;
; Controlled publication sequence:
;
;   1. validate current process-runtime state;
;   2. require canonical STARTING / INITIALISATION / unpublished pre-state;
;   3. validate the authoritative registry set;
;   4. derive M_direct_capacity_max from its MOT projection;
;   5. validate startup-memory accounting state;
;   6. checked-increment transition_count;
;   7. publish STEADY_STATE / READY / ready=1.
;
; Failure atomicity:
;
;   No ASMWEB_PROCESS_RUNTIME field is modified until all validation,
;   derivation and transition-count arithmetic have succeeded.
;
; This M0 gate does not enforce startup-temporary reclamation because the
; current startup-memory account does not distinguish temporary retained bytes
; from legitimate persistent state created during startup.
; ===========================================================================

asm_process_runtime_publish_ready:
    cld

    test rdi, rdi
    jz .publish_fail

    test rsi, rsi
    jz .publish_fail

    test rdx, rdx
    jz .publish_fail


    ; Entry RSP % 16 == 8.
    ; Five pushes consume 40 bytes -> RSP % 16 == 0 before nested calls.
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx


    ; -----------------------------------------------------------------------
    ; Validate the existing process-runtime object before using its fields.
    ; -----------------------------------------------------------------------

    mov rdi, rbx
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .publish_fail_preserved


    ; The only M0 READY-publication source state.
    cmp qword [rbx + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STARTING
    jne .publish_fail_preserved

    cmp qword [rbx + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION
    jne .publish_fail_preserved

    cmp qword [rbx + ASMWEB_PROCESS_RUNTIME.ready], 0
    jne .publish_fail_preserved


    ; -----------------------------------------------------------------------
    ; Validate authoritative OLR / MOT / RCT state.
    ; -----------------------------------------------------------------------

    mov rdi, r12
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .publish_fail_preserved


    ; -----------------------------------------------------------------------
    ; Derive the process direct-memory capacity from authoritative MOT state.
    ; -----------------------------------------------------------------------

    mov rdi, [r12 + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr]
    mov rsi, [r12 + ASMWEB_REGISTRY_VALIDATION_SET.mot_count]

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .publish_fail_preserved

    mov r14, rdx


    ; -----------------------------------------------------------------------
    ; Validate startup high-water accounting.
    ;
    ; current_bytes need not be zero: persistent state created during startup
    ; may legitimately survive publication.
    ; -----------------------------------------------------------------------

    mov rdi, r13
    call asm_startup_memory_account_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .publish_fail_preserved


    ; -----------------------------------------------------------------------
    ; Prepare the historical transition count without mutating runtime state.
    ; -----------------------------------------------------------------------

    mov rdi, [rbx + ASMWEB_PROCESS_RUNTIME.transition_count]
    mov esi, 1

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .publish_fail_preserved

    mov r15, rdx


    ; -----------------------------------------------------------------------
    ; Logical publication commit point.
    ;
    ; Every fallible prerequisite has completed. These stores cannot fail.
    ; The ready marker is written last.
    ; -----------------------------------------------------------------------

    mov qword [rbx + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STEADY_STATE

    mov qword [rbx + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY

    mov [rbx + ASMWEB_PROCESS_RUNTIME.transition_count], r15

    mov qword [rbx + ASMWEB_PROCESS_RUNTIME.ready], 1


    mov rdx, r14

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.publish_fail_preserved:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx


.publish_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
