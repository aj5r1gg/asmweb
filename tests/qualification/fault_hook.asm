bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "fault_hook.inc"

global asm_qual_fault_init
global asm_qual_fault_validate
global asm_qual_fault_arm
global asm_qual_fault_check
global asm_qual_fault_disarm


section .text


; ===========================================================================
; asm_qual_fault_init
;
; RDI = pristine ASMWEB_QUAL_FAULT_CONTROLLER *
;
; Publishes ready=1 last.
; ===========================================================================

asm_qual_fault_init:
    cld

    test rdi, rdi
    jz .init_integrity

    xor eax, eax
    xor ecx, ecx


.init_pristine_loop:
    cmp rcx, ASMWEB_QUAL_FAULT_CONTROLLER_size / 8
    jae .init_commit

    cmp [rdi + rcx * 8], rax
    jne .init_integrity

    inc rcx
    jmp .init_pristine_loop


.init_commit:
    mov qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret


.init_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_qual_fault_validate
;
; RDI = ASMWEB_QUAL_FAULT_CONTROLLER *
;
; Valid states:
;
;   initialised but never armed:
;
;       fault_id        = 0
;       point_id        = 0
;       trigger_budget  = 0
;       hit_count       = 0
;       trigger_count   = 0
;       active          = 0
;       ready           = 1
;
;   armed or historically completed/disarmed campaign:
;
;       fault_id        != 0
;       point_id        != 0
;       trigger_budget  != 0
;       trigger_count   <= trigger_budget
;       trigger_count   <= hit_count
;       active          in {0,1}
;       ready           = 1
; ===========================================================================

asm_qual_fault_validate:
    cld

    test rdi, rdi
    jz .validate_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.ready], 1
    jne .validate_integrity

    mov rax, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.active]

    cmp rax, 1
    ja .validate_integrity


    mov rax, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.fault_id]

    test rax, rax
    jnz .validate_campaign


    ; Never-armed canonical state.

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.point_id], 0
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_budget], 0
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 0
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], 0
    jne .validate_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.active], 0
    jne .validate_integrity

    mov eax, ASMWEB_RESOURCE_OK
    ret


.validate_campaign:

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.point_id], 0
    je .validate_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_budget], 0
    je .validate_integrity


    mov rax, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count]

    cmp rax, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_budget]
    ja .validate_integrity

    cmp rax, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count]
    ja .validate_integrity


    mov eax, ASMWEB_RESOURCE_OK
    ret


.validate_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_qual_fault_arm
;
; RDI = initialised, never-armed controller
; RSI = non-zero fault_id
; RDX = non-zero point_id
; RCX = non-zero trigger_budget
;
; One controller represents one campaign and therefore cannot be re-armed.
;
; Failure is atomic.
; ===========================================================================

asm_qual_fault_arm:
    cld

    test rdi, rdi
    jz .arm_integrity

    test rsi, rsi
    jz .arm_integrity

    test rdx, rdx
    jz .arm_integrity

    test rcx, rcx
    jz .arm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.ready], 1
    jne .arm_integrity


    ; Require canonical never-armed state.

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.fault_id], 0
    jne .arm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.point_id], 0
    jne .arm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_budget], 0
    jne .arm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 0
    jne .arm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], 0
    jne .arm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.active], 0
    jne .arm_integrity


    ; Commit campaign identity before active publication.

    mov [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.fault_id], rsi
    mov [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.point_id], rdx
    mov [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_budget], rcx

    mov qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.active], 1


    mov eax, ASMWEB_RESOURCE_OK
    ret


.arm_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_qual_fault_check
;
; RDI = ASMWEB_QUAL_FAULT_CONTROLLER *
; RSI = fault_id of this hook
; RDX = injection-point identity of this hook
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   on OK:
;
;       RDX = 1  inject the configured fault now
;       RDX = 0  continue normally
;
; Semantics:
;
;   - unrelated fault IDs or injection points do nothing;
;   - an inactive controller does nothing;
;   - exact configured hook encounters increment hit_count;
;   - actual injection occurs while trigger_count < trigger_budget;
;   - trigger_count never exceeds trigger_budget;
;   - counters never wrap;
;   - failure is atomic.
; ===========================================================================

asm_qual_fault_check:
    cld

    mov r8, rdx

    test rdi, rdi
    jz .check_integrity

    test rsi, rsi
    jz .check_integrity

    test r8, r8
    jz .check_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.ready], 1
    jne .check_integrity


    mov rax, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.active]

    cmp rax, 1
    ja .check_integrity

    test rax, rax
    jz .check_no_trigger


    cmp rsi, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.fault_id]
    jne .check_no_trigger

    cmp r8, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.point_id]
    jne .check_no_trigger


    ; Exact configured hook reached.
    ;
    ; Pre-calculate complete next state before mutation.

    mov r9, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count]

    cmp r9, -1
    je .check_integrity

    inc r9


    mov r10, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count]
    mov r11, [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_budget]

    cmp r10, r11
    ja .check_integrity


    ; Budget already consumed: record the hit but do not inject.

    je .check_commit_hit_only


    ; One more trigger is permitted.

    cmp r10, -1
    je .check_integrity

    inc r10


    mov [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], r9
    mov [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], r10

    mov edx, 1
    mov eax, ASMWEB_RESOURCE_OK
    ret


.check_commit_hit_only:
    mov [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], r9


.check_no_trigger:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_OK
    ret


.check_integrity:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_qual_fault_disarm
;
; RDI = armed campaign controller
;
; Campaign identity and history remain intact.
; ===========================================================================

asm_qual_fault_disarm:
    cld

    test rdi, rdi
    jz .disarm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.ready], 1
    jne .disarm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.fault_id], 0
    je .disarm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.point_id], 0
    je .disarm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_budget], 0
    je .disarm_integrity

    cmp qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.active], 1
    jne .disarm_integrity

    mov qword [rdi + ASMWEB_QUAL_FAULT_CONTROLLER.active], 0

    mov eax, ASMWEB_RESOURCE_OK
    ret


.disarm_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
