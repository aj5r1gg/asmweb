bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/pool.inc"

global _start

extern asm_typed_pool_init
extern asm_typed_pool_validate
extern asm_typed_pool_acquire
extern asm_typed_pool_release
extern asm_typed_pool_quiescent

extern asm_linux_exit


; ===========================================================================
; Qualification-only transactional acquisition fixture
;
; This file deliberately contains the fault injection and transaction fixture.
; No qualification-only fault machinery is linked into the production runtime.
;
; The fixture composes TWO real ASMWEB_TYPED_POOL resources.
;
; Transaction:
;
;   acquire A privately
;       ->
;   acquire B privately
;       ->
;   publish {A,B,ready=1}
;
; Any failure before publication rolls provisional ownership back in reverse
; dependency order:
;
;   B -> A
;
; The fixture qualifies MEM-LIFE-ACQUIRE-ROLLBACK at an M0 composition
; boundary. It does NOT establish a generic production transaction framework.
; ===========================================================================


; Qualification fault points.
;
; NONE:
;   no injected failure.
;
; AFTER_A:
;   resource A has been acquired but resource B has not.
;
; AFTER_B:
;   resources A and B have both been acquired but publication has not occurred.

%define QUAL_FAULT_NONE     0
%define QUAL_FAULT_AFTER_A  1
%define QUAL_FAULT_AFTER_B  2
%define QUAL_FAULT_MAX      QUAL_FAULT_AFTER_B


; Rollback/release event identities.
;
; The event log is qualification evidence for dependency-safe reverse order.

%define QUAL_EVENT_RELEASE_A  1
%define QUAL_EVENT_RELEASE_B  2


struc QUAL_TRANSACTION
    .resource_a: resq 1
    .resource_b: resq 1
    .ready:      resq 1
endstruc


struc QUAL_EVENT_LOG
    .count:   resq 1
    .event_0: resq 1
    .event_1: resq 1
endstruc


section .bss

; ---------------------------------------------------------------------------
; Pool A
; ---------------------------------------------------------------------------

alignb 64
pool_a_backing:
    resb 64

pool_a_slot_state:
    resb 2

alignb 8
pool_a_request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool_a:
    resb ASMWEB_TYPED_POOL_size


; ---------------------------------------------------------------------------
; Pool B
; ---------------------------------------------------------------------------

alignb 64
pool_b_backing:
    resb 64

pool_b_slot_state:
    resb 2

alignb 8
pool_b_request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool_b:
    resb ASMWEB_TYPED_POOL_size


; ---------------------------------------------------------------------------
; Transaction publications / logs
; ---------------------------------------------------------------------------

alignb 8
transaction:
    resb QUAL_TRANSACTION_size

transaction_bad:
    resb QUAL_TRANSACTION_size

event_log:
    resb QUAL_EVENT_LOG_size

event_log_bad:
    resb QUAL_EVENT_LOG_size


section .text


; ===========================================================================
; qual_event_reset
;
; RDI = QUAL_EVENT_LOG *
;
; Qualification-only helper.
; ===========================================================================

qual_event_reset:
    cld

    test rdi, rdi
    jz .event_reset_integrity

    mov qword [rdi + QUAL_EVENT_LOG.count], 0
    mov qword [rdi + QUAL_EVENT_LOG.event_0], 0
    mov qword [rdi + QUAL_EVENT_LOG.event_1], 0

    mov eax, ASMWEB_RESOURCE_OK
    ret


.event_reset_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; qual_event_append
;
; RDI = QUAL_EVENT_LOG *
; RSI = event identity
;
; Bounded to two events because the qualified transaction owns at most two
; provisional resources.
; ===========================================================================

qual_event_append:
    cld

    test rdi, rdi
    jz .event_append_integrity

    test rsi, rsi
    jz .event_append_integrity

    mov rax, [rdi + QUAL_EVENT_LOG.count]

    cmp rax, 0
    je .event_append_first

    cmp rax, 1
    je .event_append_second

    jmp .event_append_integrity


.event_append_first:
    mov [rdi + QUAL_EVENT_LOG.event_0], rsi
    mov qword [rdi + QUAL_EVENT_LOG.count], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret


.event_append_second:
    mov [rdi + QUAL_EVENT_LOG.event_1], rsi
    mov qword [rdi + QUAL_EVENT_LOG.count], 2

    mov eax, ASMWEB_RESOURCE_OK
    ret


.event_append_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; qual_transaction_acquire
;
; RDI = pool A
; RSI = pool B
; RDX = pristine QUAL_TRANSACTION publication
; RCX = injected fault point
; R8  = QUAL_EVENT_LOG
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_EXHAUSTED
;         ASMWEB_RESOURCE_INTEGRITY
;
; Success:
;
;   - A owned;
;   - B owned;
;   - publication contains both exact pointers;
;   - ready written last;
;   - event log remains empty.
;
; Failure before publication:
;
;   - publication remains pristine;
;   - every provisional resource is rolled back;
;   - rollback occurs B then A where both were acquired;
;   - ordinary injected/acquisition refusal returns EXHAUSTED;
;   - rollback contradiction returns INTEGRITY.
;
; Fault injection is qualification-only.
; ===========================================================================

qual_transaction_acquire:
    cld

    test rdi, rdi
    jz .txn_integrity_no_frame

    test rsi, rsi
    jz .txn_integrity_no_frame

    test rdx, rdx
    jz .txn_integrity_no_frame

    test r8, r8
    jz .txn_integrity_no_frame


    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Six pushes leave ordinary entry RSP % 16 == 8.
    ; Reserve 8 bytes so nested calls see RSP % 16 == 0.
    ;
    ; [rsp] = original failure result
    sub rsp, 8

    mov rbx, rdi                    ; pool A
    mov rbp, rsi                    ; pool B
    mov r12, rdx                    ; publication
    mov r13, rcx                    ; fault point
    mov r14, r8                     ; event log

    xor r15d, r15d                  ; acquired A pointer
    xor r11d, r11d                  ; acquired B pointer


    ; -----------------------------------------------------------------------
    ; Validate fault-point vocabulary before acquisition.
    ; -----------------------------------------------------------------------

    cmp r13, QUAL_FAULT_MAX
    ja .txn_integrity


    ; -----------------------------------------------------------------------
    ; Publication must be pristine.
    ; -----------------------------------------------------------------------

    cmp qword [r12 + QUAL_TRANSACTION.resource_a], 0
    jne .txn_integrity

    cmp qword [r12 + QUAL_TRANSACTION.resource_b], 0
    jne .txn_integrity

    cmp qword [r12 + QUAL_TRANSACTION.ready], 0
    jne .txn_integrity


    ; Event log must begin pristine/empty.

    cmp qword [r14 + QUAL_EVENT_LOG.count], 0
    jne .txn_integrity

    cmp qword [r14 + QUAL_EVENT_LOG.event_0], 0
    jne .txn_integrity

    cmp qword [r14 + QUAL_EVENT_LOG.event_1], 0
    jne .txn_integrity


    ; -----------------------------------------------------------------------
    ; Validate both underlying bounded resources before mutation.
    ; -----------------------------------------------------------------------

    mov rdi, rbx
    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_integrity


    mov rdi, rbp
    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_integrity


    ; -----------------------------------------------------------------------
    ; Acquire A privately.
    ; -----------------------------------------------------------------------

    mov rdi, rbx
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    je .txn_a_acquired

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    je .txn_exhausted_no_ownership

    jmp .txn_integrity


.txn_a_acquired:
    mov r15, rdx


    ; Qualification fault point: after A only.

    cmp r13, QUAL_FAULT_AFTER_A
    jne .txn_acquire_b

    mov qword [rsp], ASMWEB_RESOURCE_EXHAUSTED
    jmp .txn_rollback_a


    ; -----------------------------------------------------------------------
    ; Acquire B privately.
    ; -----------------------------------------------------------------------

.txn_acquire_b:

    mov rdi, rbp
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    je .txn_b_acquired

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    je .txn_b_exhausted

    ; Contradictory B state is an integrity failure, but A still has to be
    ; reclaimed before returning.
    mov qword [rsp], ASMWEB_RESOURCE_INTEGRITY
    jmp .txn_rollback_a


.txn_b_exhausted:
    mov qword [rsp], ASMWEB_RESOURCE_EXHAUSTED
    jmp .txn_rollback_a


.txn_b_acquired:
    mov r11, rdx


    ; Qualification fault point: both acquired, publication not yet performed.

    cmp r13, QUAL_FAULT_AFTER_B
    jne .txn_publish

    mov qword [rsp], ASMWEB_RESOURCE_EXHAUSTED
    jmp .txn_rollback_b_then_a


    ; -----------------------------------------------------------------------
    ; Publish only after complete acquisition.
    ;
    ; No fallible work remains below this point.
    ; -----------------------------------------------------------------------

.txn_publish:

    mov [r12 + QUAL_TRANSACTION.resource_a], r15
    mov [r12 + QUAL_TRANSACTION.resource_b], r11

    ; Publication marker LAST.
    mov qword [r12 + QUAL_TRANSACTION.ready], 1

    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


    ; -----------------------------------------------------------------------
    ; Rollback both resources in reverse dependency order.
    ; -----------------------------------------------------------------------

.txn_rollback_b_then_a:

    mov rdi, rbp
    mov rsi, r11
    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_rollback_integrity

    mov rdi, r14
    mov esi, QUAL_EVENT_RELEASE_B
    call qual_event_append

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_rollback_integrity


.txn_rollback_a:

    mov rdi, rbx
    mov rsi, r15
    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_rollback_integrity

    mov rdi, r14
    mov esi, QUAL_EVENT_RELEASE_A
    call qual_event_append

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_rollback_integrity


    mov eax, [rsp]

    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ret


.txn_rollback_integrity:

    ; A rollback contradiction must never be disguised as ordinary exhaustion.
    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


.txn_exhausted_no_ownership:

    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_EXHAUSTED
    ret


.txn_integrity:

    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx


.txn_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; qual_transaction_release
;
; RDI = pool A
; RSI = pool B
; RDX = published QUAL_TRANSACTION
; RCX = QUAL_EVENT_LOG
;
; Release order is B -> A.
;
; Publication is cleared only after both releases succeed.
;
; This qualification fixture intentionally has no injected release failure:
; release-failure/residue behaviour is already separately exercised by the
; stack/mapping qualification paths.
; ===========================================================================

qual_transaction_release:
    cld

    test rdi, rdi
    jz .txn_release_integrity_no_frame

    test rsi, rsi
    jz .txn_release_integrity_no_frame

    test rdx, rdx
    jz .txn_release_integrity_no_frame

    test rcx, rcx
    jz .txn_release_integrity_no_frame


    push rbx
    push rbp
    push r12
    push r13
    push r14

    ; Five pushes establish call alignment.
    mov rbx, rdi                    ; pool A
    mov rbp, rsi                    ; pool B
    mov r12, rdx                    ; publication
    mov r13, rcx                    ; event log


    cmp qword [r12 + QUAL_TRANSACTION.ready], 1
    jne .txn_release_integrity

    mov r14, [r12 + QUAL_TRANSACTION.resource_a]
    test r14, r14
    jz .txn_release_integrity

    mov rax, [r12 + QUAL_TRANSACTION.resource_b]
    test rax, rax
    jz .txn_release_integrity


    ; Event log must be pristine for this release interval.

    cmp qword [r13 + QUAL_EVENT_LOG.count], 0
    jne .txn_release_integrity

    cmp qword [r13 + QUAL_EVENT_LOG.event_0], 0
    jne .txn_release_integrity

    cmp qword [r13 + QUAL_EVENT_LOG.event_1], 0
    jne .txn_release_integrity


    ; Release B first.

    mov rdi, rbp
    mov rsi, rax
    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_release_integrity

    mov rdi, r13
    mov esi, QUAL_EVENT_RELEASE_B
    call qual_event_append

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_release_integrity


    ; Release A second.

    mov rdi, rbx
    mov rsi, r14
    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_release_integrity

    mov rdi, r13
    mov esi, QUAL_EVENT_RELEASE_A
    call qual_event_append

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_release_integrity


    ; Complete publication retirement only after both resources are gone.

    mov qword [r12 + QUAL_TRANSACTION.resource_a], 0
    mov qword [r12 + QUAL_TRANSACTION.resource_b], 0
    mov qword [r12 + QUAL_TRANSACTION.ready], 0


    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.txn_release_integrity:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx


.txn_release_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; Test program
;
; Exit codes:
;
;   0  PASS
;   1  pool A init failed
;   2  pool B init failed
;   3  invalid fault point mutated state
;   4  AFTER_A injection failed rollback
;   5  AFTER_A publication/order incorrect
;   6  AFTER_B injection failed rollback
;   7  AFTER_B reverse order incorrect
;   8  real B exhaustion did not rollback A
;   9  real B exhaustion accounting invalid
;   10 success transaction failed
;   11 success published partial/incorrect state
;   12 success release failed
;   13 successful release order incorrect
;   14 repeated rollback failed
;   15 repeated rollback leaked occupancy
;   16 historical accounting inconsistent
;   17 non-pristine publication accepted
;   18 NULL semantics failed
;   19 ABI/DF preservation failed
;   20 final quiescence failed
;   21 dirty resource A publication accepted or mutated state
;   22 dirty resource B publication accepted or mutated state
;   23 dirty event count accepted or mutated state
;   24 dirty event payload accepted or mutated state
;   25 NULL publication accepted or mutated state
;   26 NULL event log accepted or mutated state
; ===========================================================================

_start:
    cld


    ; =======================================================================
    ; Build pool A
    ; =======================================================================

    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x31000001

    lea rax, [rel pool_a_backing]
    mov [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax

    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 64

    lea rax, [rel pool_a_slot_state]
    mov [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax

    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 2
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 24
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 32
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 2
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 1
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 0
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], \
        0x41000001

    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL

    lea rdi, [rel pool_a_request]
    lea rsi, [rel pool_a]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    ; =======================================================================
    ; Build pool B
    ; =======================================================================

    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x31000002

    lea rax, [rel pool_b_backing]
    mov [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax

    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 64

    lea rax, [rel pool_b_slot_state]
    mov [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax

    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 2
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 24
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 32
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 2
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 1
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 0
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], \
        0x41000002

    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL

    lea rdi, [rel pool_b_request]
    lea rsi, [rel pool_b]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    ; =======================================================================
    ; CASE 1 — invalid injection point rejected before acquisition
    ; =======================================================================

    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_MAX + 1
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_3

    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_3

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_3

    cmp qword [rel transaction + QUAL_TRANSACTION.ready], 0
    jne .fail_3


    ; =======================================================================
    ; CASE 2 — injected failure after A rolls A back
    ; =======================================================================

    lea rdi, [rel event_log]
    call qual_event_reset

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4


    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_AFTER_A
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_4

    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_4

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_4


    ; Publication remained invisible/pristine.

    cmp qword [rel transaction + QUAL_TRANSACTION.resource_a], 0
    jne .fail_5

    cmp qword [rel transaction + QUAL_TRANSACTION.resource_b], 0
    jne .fail_5

    cmp qword [rel transaction + QUAL_TRANSACTION.ready], 0
    jne .fail_5


    ; Only A required rollback.

    cmp qword [rel event_log + QUAL_EVENT_LOG.count], 1
    jne .fail_5

    cmp qword [rel event_log + QUAL_EVENT_LOG.event_0], QUAL_EVENT_RELEASE_A
    jne .fail_5


    ; =======================================================================
    ; CASE 3 — injected failure after B rolls B then A
    ; =======================================================================

    lea rdi, [rel event_log]
    call qual_event_reset

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6


    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_AFTER_B
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_6

    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_6

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_6

    cmp qword [rel transaction + QUAL_TRANSACTION.ready], 0
    jne .fail_6


    cmp qword [rel event_log + QUAL_EVENT_LOG.count], 2
    jne .fail_7

    cmp qword [rel event_log + QUAL_EVENT_LOG.event_0], QUAL_EVENT_RELEASE_B
    jne .fail_7

    cmp qword [rel event_log + QUAL_EVENT_LOG.event_1], QUAL_EVENT_RELEASE_A
    jne .fail_7


    ; =======================================================================
    ; CASE 4 — REAL downstream exhaustion rolls back A
    ;
    ; Occupy B outside the transaction, then attempt the two-resource
    ; transaction. A can be provisionally acquired, B cannot.
    ; =======================================================================

    lea rdi, [rel pool_b]
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8

    mov r12, rdx                    ; externally held B


    lea rdi, [rel event_log]
    call qual_event_reset

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8


    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_8


    ; A was rolled back. Only the deliberately external B remains.

    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_8

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 1
    jne .fail_8

    cmp qword [rel transaction + QUAL_TRANSACTION.ready], 0
    jne .fail_8


    cmp qword [rel event_log + QUAL_EVENT_LOG.count], 1
    jne .fail_9

    cmp qword [rel event_log + QUAL_EVENT_LOG.event_0], QUAL_EVENT_RELEASE_A
    jne .fail_9


    ; Release deliberate external B occupation.

    lea rdi, [rel pool_b]
    mov rsi, r12
    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_9


    ; =======================================================================
    ; CASE 5 — successful acquisition publishes only complete ownership
    ; =======================================================================

    lea rdi, [rel event_log]
    call qual_event_reset

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_10


    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_10


    cmp qword [rel transaction + QUAL_TRANSACTION.ready], 1
    jne .fail_11

    cmp qword [rel transaction + QUAL_TRANSACTION.resource_a], 0
    je .fail_11

    cmp qword [rel transaction + QUAL_TRANSACTION.resource_b], 0
    je .fail_11

    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 1
    jne .fail_11

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 1
    jne .fail_11

    ; Successful acquisition performed no rollback.
    cmp qword [rel event_log + QUAL_EVENT_LOG.count], 0
    jne .fail_11


    ; =======================================================================
    ; CASE 6 — release successful transaction in reverse order
    ; =======================================================================

    lea rdi, [rel event_log]
    call qual_event_reset

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12


    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    lea rcx, [rel event_log]

    call qual_transaction_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12


    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_12

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_12

    cmp qword [rel transaction + QUAL_TRANSACTION.ready], 0
    jne .fail_12


    cmp qword [rel event_log + QUAL_EVENT_LOG.count], 2
    jne .fail_13

    cmp qword [rel event_log + QUAL_EVENT_LOG.event_0], QUAL_EVENT_RELEASE_B
    jne .fail_13

    cmp qword [rel event_log + QUAL_EVENT_LOG.event_1], QUAL_EVENT_RELEASE_A
    jne .fail_13


    ; =======================================================================
    ; CASE 7 — repeated partial acquisition cannot accumulate retained state
    ;
    ; 128 injected AFTER_B failures.
    ; Each attempt acquires both real pool resources then rolls them back.
    ; =======================================================================

    mov r13d, 128


.repeat_failure_loop:

    lea rdi, [rel event_log]
    call qual_event_reset

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_14


    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_AFTER_B
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_14

    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_15

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_15

    cmp qword [rel transaction + QUAL_TRANSACTION.ready], 0
    jne .fail_15

    dec r13
    jnz .repeat_failure_loop


    ; =======================================================================
    ; CASE 8 — historical accounting remains truthful after churn
    ;
    ; For a quiescent pool:
    ;
    ; acquisition_count - release_count == current_occupancy == 0
    ; =======================================================================

    lea rdi, [rel pool_a]
    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_16

    lea rdi, [rel pool_b]
    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_16


    mov rax, [rel pool_a + ASMWEB_TYPED_POOL.acquisition_count]
    cmp rax, [rel pool_a + ASMWEB_TYPED_POOL.release_count]
    jne .fail_16

    mov rax, [rel pool_b + ASMWEB_TYPED_POOL.acquisition_count]
    cmp rax, [rel pool_b + ASMWEB_TYPED_POOL.release_count]
    jne .fail_16


    ; =======================================================================
    ; CASE 9 — non-pristine publication rejected before acquisition
    ; =======================================================================

    mov qword [rel transaction_bad + QUAL_TRANSACTION.ready], 1

    lea rdi, [rel event_log_bad]
    call qual_event_reset

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17


    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction_bad]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log_bad]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17

    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_17

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_17

    ; Original publication marker preserved.
    cmp qword [rel transaction_bad + QUAL_TRANSACTION.ready], 1
    jne .fail_17


    ; =======================================================================
    ; CASE 9A — dirty resource A publication rejected without acquisition
    ; =======================================================================

    mov qword [rel transaction_bad + QUAL_TRANSACTION.ready], 0
    mov qword [rel transaction_bad + QUAL_TRANSACTION.resource_a], 0x1234

    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction_bad]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log_bad]
    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21
    cmp qword [rel transaction_bad + QUAL_TRANSACTION.resource_a], 0x1234
    jne .fail_21
    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_21
    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_21
    mov qword [rel transaction_bad + QUAL_TRANSACTION.resource_a], 0

    ; =======================================================================
    ; CASE 9B — dirty resource B publication rejected without acquisition
    ; =======================================================================

    mov qword [rel transaction_bad + QUAL_TRANSACTION.resource_b], 0x5678

    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction_bad]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log_bad]
    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_22
    cmp qword [rel transaction_bad + QUAL_TRANSACTION.resource_b], 0x5678
    jne .fail_22
    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_22
    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_22
    mov qword [rel transaction_bad + QUAL_TRANSACTION.resource_b], 0

    ; =======================================================================
    ; CASE 9C — dirty event count rejected without acquisition
    ; =======================================================================

    mov qword [rel event_log_bad + QUAL_EVENT_LOG.count], 1

    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction_bad]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log_bad]
    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_23
    cmp qword [rel event_log_bad + QUAL_EVENT_LOG.count], 1
    jne .fail_23
    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_23
    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_23
    mov qword [rel event_log_bad + QUAL_EVENT_LOG.count], 0

    ; =======================================================================
    ; CASE 9D — dirty event payload rejected without acquisition
    ; =======================================================================

    mov qword [rel event_log_bad + QUAL_EVENT_LOG.event_0], QUAL_EVENT_RELEASE_B

    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction_bad]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log_bad]
    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_24
    cmp qword [rel event_log_bad + QUAL_EVENT_LOG.event_0], QUAL_EVENT_RELEASE_B
    jne .fail_24
    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_24
    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_24
    mov qword [rel event_log_bad + QUAL_EVENT_LOG.event_0], 0

    ; =======================================================================
    ; CASE 9E — NULL publication rejected without acquisition
    ; =======================================================================

    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    xor edx, edx
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log_bad]
    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_25
    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_25
    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_25

    ; =======================================================================
    ; CASE 9F — NULL event log rejected without acquisition
    ; =======================================================================

    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction_bad]
    mov ecx, QUAL_FAULT_NONE
    xor r8d, r8d
    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_26
    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_26
    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_26

    ; =======================================================================
    ; CASE 10 — NULL semantics
    ; =======================================================================

    xor edi, edi
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_18


    lea rdi, [rel pool_a]
    xor esi, esi
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_NONE
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_18


    ; =======================================================================
    ; CASE 11 — transaction fixture preserves ABI callee-saved state + DF
    ; =======================================================================

    lea rdi, [rel event_log]
    call qual_event_reset

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std

    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]
    mov ecx, QUAL_FAULT_AFTER_B
    lea r8, [rel event_log]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_19


    cmp rbx, 0x11111111
    jne .fail_19

    cmp rbp, 0x22222222
    jne .fail_19

    cmp r12, 0x33333333
    jne .fail_19

    cmp r13, 0x44444444
    jne .fail_19

    mov rax, 0x55555555
    cmp r14, rax
    jne .fail_19

    mov rax, 0x66666666
    cmp r15, rax
    jne .fail_19

    pushfq
    pop rax

    test rax, 1 << 10
    jnz .fail_19


    ; =======================================================================
    ; CASE 12 — final quiescence
    ; =======================================================================

    lea rdi, [rel pool_a]
    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_20


    lea rdi, [rel pool_b]
    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_20


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

.fail_19:
    mov edi, 19
    call asm_linux_exit
    ud2

.fail_20:
    mov edi, 20
    call asm_linux_exit
    ud2

.fail_21:
    mov edi, 21
    call asm_linux_exit
    ud2

.fail_22:
    mov edi, 22
    call asm_linux_exit
    ud2

.fail_23:
    mov edi, 23
    call asm_linux_exit
    ud2

.fail_24:
    mov edi, 24
    call asm_linux_exit
    ud2

.fail_25:
    mov edi, 25
    call asm_linux_exit
    ud2

.fail_26:
    mov edi, 26
    call asm_linux_exit
    ud2
