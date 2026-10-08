bits 64

%include "asmweb/abi.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/resource.inc"
%include "asmweb/quiescence.inc"

global asm_quiescence_init
global asm_quiescence_validate
global asm_quiescence_observe
global asm_quiescence_evaluate


section .text


; ===========================================================================
; asm_quiescence_init
;
; RDI = configuration-derived expected persistent baseline
; RSI = pristine ASMWEB_QUIESCENCE_STATE *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Initial observation is exactly the baseline:
;
;   baseline            = input
;   current             = baseline
;   expected_persistent = baseline
;   all other classes   = 0
;   observation_count   = 0
;   ready               = 1, written last
;
; Zero is a valid baseline.
; ===========================================================================

asm_quiescence_init:
    cld

    test rsi, rsi
    jz .init_integrity

    ; Destination must be completely pristine.
    xor ecx, ecx

.init_pristine_loop:
    cmp rcx, ASMWEB_QUIESCENCE_STATE_size / 8
    jae .init_commit

    cmp qword [rsi + rcx * 8], 0
    jne .init_integrity

    inc rcx
    jmp .init_pristine_loop


.init_commit:

    ; No fallible operation remains.

    mov [rsi + ASMWEB_QUIESCENCE_STATE.baseline], rdi
    mov [rsi + ASMWEB_QUIESCENCE_STATE.current], rdi
    mov [rsi + ASMWEB_QUIESCENCE_STATE.expected_persistent], rdi

    mov qword [rsi + ASMWEB_QUIESCENCE_STATE.grace_transient], 0
    mov qword [rsi + ASMWEB_QUIESCENCE_STATE.external_completion_pending], 0
    mov qword [rsi + ASMWEB_QUIESCENCE_STATE.unexplained_retained], 0
    mov qword [rsi + ASMWEB_QUIESCENCE_STATE.confirmed_leak], 0

    mov qword [rsi + ASMWEB_QUIESCENCE_STATE.observation_count], 0

    ; Publication marker last.
    mov qword [rsi + ASMWEB_QUIESCENCE_STATE.ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret


.init_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_quiescence_validate
;
; RDI = ASMWEB_QUIESCENCE_STATE *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Validates exact retained-state decomposition using checked arithmetic.
; ===========================================================================

asm_quiescence_validate:
    cld

    test rdi, rdi
    jz .validate_integrity

    cmp qword [rdi + ASMWEB_QUIESCENCE_STATE.ready], 1
    jne .validate_integrity


    ; M0 expected persistent state is exactly the configured baseline.

    mov rax, [rdi + ASMWEB_QUIESCENCE_STATE.baseline]

    cmp [rdi + ASMWEB_QUIESCENCE_STATE.expected_persistent], rax
    jne .validate_integrity


    ; Current cannot be less than the expected persistent baseline.

    cmp [rdi + ASMWEB_QUIESCENCE_STATE.current], rax
    jb .validate_integrity


    ; checked:
    ;
    ;   baseline
    ; + grace
    ; + external
    ; + unexplained
    ; + leak
    ;
    ; must equal current.

    add rax, [rdi + ASMWEB_QUIESCENCE_STATE.grace_transient]
    jc .validate_integrity

    add rax, [rdi + ASMWEB_QUIESCENCE_STATE.external_completion_pending]
    jc .validate_integrity

    add rax, [rdi + ASMWEB_QUIESCENCE_STATE.unexplained_retained]
    jc .validate_integrity

    add rax, [rdi + ASMWEB_QUIESCENCE_STATE.confirmed_leak]
    jc .validate_integrity

    cmp rax, [rdi + ASMWEB_QUIESCENCE_STATE.current]
    jne .validate_integrity


    mov eax, ASMWEB_RESOURCE_OK
    ret


.validate_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_quiescence_observe
;
; RDI = ASMWEB_QUIESCENCE_STATE *
; RSI = current total retained quantity
; RDX = GRACE_TRANSIENT quantity
; RCX = EXTERNAL_COMPLETION_PENDING quantity
; R8  = UNEXPLAINED_RETAINED quantity
; R9  = CONFIRMED_LEAK quantity
;
; EXPECTED_PERSISTENT remains the configuration-derived baseline.
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Observation is accepted only when:
;
;   current >= baseline
;
; and:
;
;   current =
;       baseline
;     + grace
;     + external
;     + unexplained
;     + leak
;
; All arithmetic and historical-count checks complete before mutation.
; Failure leaves the previous observation unchanged.
; ===========================================================================

asm_quiescence_observe:
    cld

    test rdi, rdi
    jz .observe_integrity_no_frame

    ; Preserve complete input tuple across validation.
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Five pushes establish call alignment.
    ; Reserve 16 bytes without changing alignment.
    ;
    ; [rsp + 0] = confirmed_leak
    ; [rsp + 8] = next observation_count
    sub rsp, 16

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8

    mov [rsp], r9


    ; Existing state must itself be coherent.

    mov rdi, rbx
    call asm_quiescence_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .observe_integrity


    ; Current cannot fall below the persistent baseline.

    mov rax, [rbx + ASMWEB_QUIESCENCE_STATE.baseline]

    cmp r12, rax
    jb .observe_integrity


    ; Exact checked decomposition.

    add rax, r13
    jc .observe_integrity

    add rax, r14
    jc .observe_integrity

    add rax, r15
    jc .observe_integrity

    add rax, [rsp]
    jc .observe_integrity

    cmp rax, r12
    jne .observe_integrity


    ; Historical observation count must never silently wrap.

    mov rax, [rbx + ASMWEB_QUIESCENCE_STATE.observation_count]

    cmp rax, ASMWEB_U64_MAX
    je .observe_integrity

    inc rax
    mov [rsp + 8], rax


    ; -----------------------------------------------------------------------
    ; Commit.
    ;
    ; No fallible operation remains.
    ; -----------------------------------------------------------------------

    mov [rbx + ASMWEB_QUIESCENCE_STATE.current], r12
    mov [rbx + ASMWEB_QUIESCENCE_STATE.grace_transient], r13
    mov [rbx + ASMWEB_QUIESCENCE_STATE.external_completion_pending], r14
    mov [rbx + ASMWEB_QUIESCENCE_STATE.unexplained_retained], r15

    mov rax, [rsp]
    mov [rbx + ASMWEB_QUIESCENCE_STATE.confirmed_leak], rax

    mov rax, [rsp + 8]
    mov [rbx + ASMWEB_QUIESCENCE_STATE.observation_count], rax


    add rsp, 16

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.observe_integrity:
    add rsp, 16

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx


.observe_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_quiescence_evaluate
;
; RDI = ASMWEB_QUIESCENCE_STATE *
;
; Returns:
;
;   RAX = ASMWEB_QUIESCENCE_OUTCOME_*
;
;   RDX = ASMWEB_QUIESCENCE_CLASS_* presence bitmask
;         zero on INTEGRITY
;
; Precedence:
;
;   representation contradiction
;       -> INTEGRITY
;
;   unexplained or confirmed leak
;       -> FAIL
;
;   grace transient or external completion pending
;       -> PENDING
;
;   exact persistent baseline only
;       -> BASELINE
;
; CONFIRMED_LEAK is an explicit classification supplied by the subsystem or
; qualification authority. This primitive never infers a leak from time alone.
; ===========================================================================

asm_quiescence_evaluate:
    cld

    test rdi, rdi
    jz .evaluate_integrity_no_frame

    push rbx
    mov rbx, rdi

    call asm_quiescence_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .evaluate_integrity


    xor edx, edx


    ; EXPECTED_PERSISTENT presence.

    cmp qword [rbx + ASMWEB_QUIESCENCE_STATE.expected_persistent], 0
    je .evaluate_grace

    or edx, ASMWEB_QUIESCENCE_CLASS_EXPECTED_PERSISTENT


.evaluate_grace:

    cmp qword [rbx + ASMWEB_QUIESCENCE_STATE.grace_transient], 0
    je .evaluate_external

    or edx, ASMWEB_QUIESCENCE_CLASS_GRACE_TRANSIENT


.evaluate_external:

    cmp qword [rbx + ASMWEB_QUIESCENCE_STATE.external_completion_pending], 0
    je .evaluate_unexplained

    or edx, ASMWEB_QUIESCENCE_CLASS_EXTERNAL_COMPLETION_PENDING


.evaluate_unexplained:

    cmp qword [rbx + ASMWEB_QUIESCENCE_STATE.unexplained_retained], 0
    je .evaluate_leak

    or edx, ASMWEB_QUIESCENCE_CLASS_UNEXPLAINED_RETAINED


.evaluate_leak:

    cmp qword [rbx + ASMWEB_QUIESCENCE_STATE.confirmed_leak], 0
    je .evaluate_outcome

    or edx, ASMWEB_QUIESCENCE_CLASS_CONFIRMED_LEAK


.evaluate_outcome:

    ; Qualification-failing retained classes take precedence.

    test edx, \
        ASMWEB_QUIESCENCE_CLASS_UNEXPLAINED_RETAINED | \
        ASMWEB_QUIESCENCE_CLASS_CONFIRMED_LEAK
    jnz .evaluate_fail


    ; Recognised temporary/pending retained classes are not baseline yet.

    test edx, \
        ASMWEB_QUIESCENCE_CLASS_GRACE_TRANSIENT | \
        ASMWEB_QUIESCENCE_CLASS_EXTERNAL_COMPLETION_PENDING
    jnz .evaluate_pending


    pop rbx
    mov eax, ASMWEB_QUIESCENCE_OUTCOME_BASELINE
    ret


.evaluate_pending:
    pop rbx
    mov eax, ASMWEB_QUIESCENCE_OUTCOME_PENDING
    ret


.evaluate_fail:
    pop rbx
    mov eax, ASMWEB_QUIESCENCE_OUTCOME_FAIL
    ret


.evaluate_integrity:
    pop rbx


.evaluate_integrity_no_frame:
    xor edx, edx
    mov eax, ASMWEB_QUIESCENCE_OUTCOME_INTEGRITY
    ret
