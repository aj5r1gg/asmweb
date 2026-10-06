bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/process_runtime.inc"

global asm_process_runtime_init
global asm_process_runtime_validate


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
