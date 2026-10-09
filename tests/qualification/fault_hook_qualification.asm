bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/pool.inc"
%include "fault_hook.inc"

global _start

extern asm_typed_pool_init
extern asm_typed_pool_validate
extern asm_typed_pool_acquire
extern asm_typed_pool_release

extern asm_qual_fault_init
extern asm_qual_fault_validate
extern asm_qual_fault_arm
extern asm_qual_fault_check
extern asm_qual_fault_disarm

extern asm_linux_exit


; ===========================================================================
; Qualification-only two-resource composition.
;
; The fault controller is consulted only at explicit seams.
;
; Simulated resource failure is represented to this fixture as
; ASMWEB_RESOURCE_EXHAUSTED.
; ===========================================================================

struc QUAL_FAULT_TRANSACTION
    .resource_a: resq 1
    .resource_b: resq 1
    .ready:      resq 1
endstruc


section .bss

alignb 64

controller_a:
    resb ASMWEB_QUAL_FAULT_CONTROLLER_size

controller_b:
    resb ASMWEB_QUAL_FAULT_CONTROLLER_size

controller_budget:
    resb ASMWEB_QUAL_FAULT_CONTROLLER_size

controller_invalid:
    resb ASMWEB_QUAL_FAULT_CONTROLLER_size


pool_a_request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool_a:
    resb ASMWEB_TYPED_POOL_size

alignb 64
pool_a_backing:
    resb 64 * 2

alignb 8
pool_a_slot_state:
    resb 2


pool_b_request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool_b:
    resb ASMWEB_TYPED_POOL_size

alignb 64
pool_b_backing:
    resb 64 * 2

alignb 8
pool_b_slot_state:
    resb 2


transaction:
    resb QUAL_FAULT_TRANSACTION_size

saved_trigger_count:
    resq 1


section .text


; ===========================================================================
; qual_transaction_clear
; ===========================================================================

qual_transaction_clear:
    cld

    mov qword [rel transaction + QUAL_FAULT_TRANSACTION.resource_a], 0
    mov qword [rel transaction + QUAL_FAULT_TRANSACTION.resource_b], 0
    mov qword [rel transaction + QUAL_FAULT_TRANSACTION.ready], 0

    ret


; ===========================================================================
; qual_transaction_acquire
;
; RDI = fault controller
; RSI = pool A
; RDX = pool B
; RCX = pristine transaction
;
; Returns:
;
;   OK
;   EXHAUSTED
;   INTEGRITY
;
; All-or-nothing publication.
; Reverse-order rollback.
; ===========================================================================

qual_transaction_acquire:
    cld

    test rdi, rdi
    jz .txn_integrity_no_frame

    test rsi, rsi
    jz .txn_integrity_no_frame

    test rdx, rdx
    jz .txn_integrity_no_frame

    test rcx, rcx
    jz .txn_integrity_no_frame


    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Six pushes leave RSP % 16 == 8.
    ; Reserve 8 bytes for nested-call alignment.
    sub rsp, 8


    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx

    xor ebp, ebp
    xor r15d, r15d


    ; Transaction destination must be pristine.

    cmp qword [r14 + QUAL_FAULT_TRANSACTION.resource_a], 0
    jne .txn_integrity

    cmp qword [r14 + QUAL_FAULT_TRANSACTION.resource_b], 0
    jne .txn_integrity

    cmp qword [r14 + QUAL_FAULT_TRANSACTION.ready], 0
    jne .txn_integrity


    ; -----------------------------------------------------------------------
    ; Acquire A.
    ; -----------------------------------------------------------------------

    mov rdi, r12
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_return

    mov r15, rdx


    ; Explicit qualification seam: after A.

    mov rdi, rbx
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_A

    call asm_qual_fault_check

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_rollback_a_integrity

    test rdx, rdx
    jnz .txn_rollback_a_exhausted


    ; -----------------------------------------------------------------------
    ; Acquire B.
    ; -----------------------------------------------------------------------

    mov rdi, r13
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_rollback_a_preserve_result

    mov rbp, rdx


    ; Explicit qualification seam: after B.

    mov rdi, rbx
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_B

    call asm_qual_fault_check

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_rollback_ba_integrity

    test rdx, rdx
    jnz .txn_rollback_ba_exhausted


    ; -----------------------------------------------------------------------
    ; Publish only complete ownership.
    ; -----------------------------------------------------------------------

    mov [r14 + QUAL_FAULT_TRANSACTION.resource_a], r15
    mov [r14 + QUAL_FAULT_TRANSACTION.resource_b], rbp

    mov qword [r14 + QUAL_FAULT_TRANSACTION.ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    jmp .txn_return


.txn_rollback_ba_exhausted:
    mov qword [rsp], ASMWEB_RESOURCE_EXHAUSTED
    jmp .txn_rollback_ba


.txn_rollback_ba_integrity:
    mov qword [rsp], ASMWEB_RESOURCE_INTEGRITY


.txn_rollback_ba:
    ; Intended transaction result is already preserved in stack-local state
    ; before the nested release call. No caller-saved register carries it.
    mov rdi, r13
    mov rsi, rbp

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_integrity

    jmp .txn_rollback_a_with_saved_result


.txn_rollback_a_exhausted:
    mov qword [rsp], ASMWEB_RESOURCE_EXHAUSTED
    jmp .txn_rollback_a_with_saved_result


.txn_rollback_a_integrity:
    mov qword [rsp], ASMWEB_RESOURCE_INTEGRITY
    jmp .txn_rollback_a_with_saved_result


.txn_rollback_a_preserve_result:
    mov [rsp], rax


.txn_rollback_a_with_saved_result:
    mov rdi, r12
    mov rsi, r15

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .txn_integrity

    mov eax, [rsp]
    jmp .txn_return


.txn_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY


.txn_return:
    add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ret


.txn_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; qual_transaction_release
; ===========================================================================

qual_transaction_release:
    cld

    test rdi, rdi
    jz .release_integrity

    test rsi, rsi
    jz .release_integrity

    test rdx, rdx
    jz .release_integrity


    push rbx
    push r12
    push r13

    ; Three pushes establish RSP % 16 == 0.
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx


    cmp qword [r13 + QUAL_FAULT_TRANSACTION.ready], 1
    jne .release_integrity_frame


    ; B then A.

    mov rdi, r12
    mov rsi, [r13 + QUAL_FAULT_TRANSACTION.resource_b]

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .release_integrity_frame


    mov rdi, rbx
    mov rsi, [r13 + QUAL_FAULT_TRANSACTION.resource_a]

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .release_integrity_frame


    xor eax, eax

    mov [r13 + QUAL_FAULT_TRANSACTION.resource_a], rax
    mov [r13 + QUAL_FAULT_TRANSACTION.resource_b], rax
    mov [r13 + QUAL_FAULT_TRANSACTION.ready], rax


    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.release_integrity_frame:
    pop r13
    pop r12
    pop rbx


.release_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; Exit codes
;
;   0  PASS
;   1  pool/controller initialisation failed
;   2  invalid arm semantics failed
;   3  unrelated point altered campaign
;   4  AFTER_A fault did not trigger
;   5  AFTER_A containment/reclamation failed
;   6  AFTER_B fault did not trigger
;   7  AFTER_B containment/reclamation failed
;   8  bounded trigger budget failed
;   9  post-budget ordinary success failed
;   10 successful transaction release failed
;   11 disarm semantics failed
;   12 controller validation failed
;   13 hit-counter overflow accepted/mutated
;   14 re-arm accepted
;   15 ABI/DF preservation failed
;   16 final pool accounting/quiescence failed
;   17 pool B initialisation failed
;   18 controller A initialisation failed
;   19 controller B initialisation failed
;   20 controller budget initialisation failed
;   21 controller invalid-test initialisation failed
; ===========================================================================

_start:
    cld


    ; =======================================================================
    ; Initialise pools.
    ; =======================================================================

    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x910001

    lea rax, [rel pool_a_backing]
    mov [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax

    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 128

    lea rax, [rel pool_a_slot_state]
    mov [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax

    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 2
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 32
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 64
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 2
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 2
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 0
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], \
        0x920001
    mov qword [rel pool_a_request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL

    lea rdi, [rel pool_a_request]
    lea rsi, [rel pool_a]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x910002

    lea rax, [rel pool_b_backing]
    mov [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax

    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 128

    lea rax, [rel pool_b_slot_state]
    mov [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax

    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 2
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 32
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 64
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 2
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 2
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 0
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], \
        0x920002
    mov qword [rel pool_b_request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL

    lea rdi, [rel pool_b_request]
    lea rsi, [rel pool_b]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17


    ; =======================================================================
    ; Initialise four independent campaigns.
    ; =======================================================================

    lea rdi, [rel controller_a]
    call asm_qual_fault_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18

    lea rdi, [rel controller_b]
    call asm_qual_fault_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    lea rdi, [rel controller_budget]
    call asm_qual_fault_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_20

    lea rdi, [rel controller_invalid]
    call asm_qual_fault_init
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21


    ; =======================================================================
    ; CASE 1 — invalid arm rejected atomically.
    ; =======================================================================

    lea rdi, [rel controller_invalid]
    xor esi, esi
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_A
    mov ecx, 1

    call asm_qual_fault_arm

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_2

    cmp qword [rel controller_invalid + ASMWEB_QUAL_FAULT_CONTROLLER.fault_id], 0
    jne .fail_2

    cmp qword [rel controller_invalid + ASMWEB_QUAL_FAULT_CONTROLLER.active], 0
    jne .fail_2


    ; =======================================================================
    ; CASE 2 — unrelated hook cannot alter configured campaign.
    ; =======================================================================

    lea rdi, [rel controller_a]
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_A
    mov ecx, 1

    call asm_qual_fault_arm

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    lea rdi, [rel controller_a]
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_B

    call asm_qual_fault_check

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3

    test rdx, rdx
    jnz .fail_3

    cmp qword [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 0
    jne .fail_3

    cmp qword [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], 0
    jne .fail_3


    ; =======================================================================
    ; CASE 3 — AFTER_A injected failure.
    ; =======================================================================

    call qual_transaction_clear

    lea rdi, [rel controller_a]
    lea rsi, [rel pool_a]
    lea rdx, [rel pool_b]
    lea rcx, [rel transaction]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_4


    cmp qword [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 1
    jne .fail_4

    cmp qword [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], 1
    jne .fail_4


    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_5

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_5

    cmp qword [rel transaction + QUAL_FAULT_TRANSACTION.ready], 0
    jne .fail_5


    ; =======================================================================
    ; CASE 4 — AFTER_B injected failure.
    ; =======================================================================

    lea rdi, [rel controller_b]
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_B
    mov ecx, 1

    call asm_qual_fault_arm

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6


    call qual_transaction_clear

    lea rdi, [rel controller_b]
    lea rsi, [rel pool_a]
    lea rdx, [rel pool_b]
    lea rcx, [rel transaction]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_6

    cmp qword [rel controller_b + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 1
    jne .fail_6

    cmp qword [rel controller_b + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], 1
    jne .fail_6


    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_7

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_7

    cmp qword [rel transaction + QUAL_FAULT_TRANSACTION.ready], 0
    jne .fail_7


    ; =======================================================================
    ; CASE 5 — exact bounded trigger budget.
    ;
    ; Budget = 2 at AFTER_A.
    ;
    ; Attempts:
    ;
    ;   1 -> injected failure
    ;   2 -> injected failure
    ;   3 -> no injection; transaction succeeds
    ; =======================================================================

    lea rdi, [rel controller_budget]
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_A
    mov ecx, 2

    call asm_qual_fault_arm

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8


    mov r12d, 2


.budget_failure_loop:

    call qual_transaction_clear

    lea rdi, [rel controller_budget]
    lea rsi, [rel pool_a]
    lea rdx, [rel pool_b]
    lea rcx, [rel transaction]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_8

    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_8

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_8

    dec r12
    jnz .budget_failure_loop


    ; Third encounter exceeds trigger budget and proceeds normally.

    call qual_transaction_clear

    lea rdi, [rel controller_budget]
    lea rsi, [rel pool_a]
    lea rdx, [rel pool_b]
    lea rcx, [rel transaction]

    call qual_transaction_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_9

    cmp qword [rel controller_budget + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 3
    jne .fail_8

    cmp qword [rel controller_budget + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], 2
    jne .fail_8

    cmp qword [rel transaction + QUAL_FAULT_TRANSACTION.ready], 1
    jne .fail_9


    lea rdi, [rel pool_a]
    lea rsi, [rel pool_b]
    lea rdx, [rel transaction]

    call qual_transaction_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_10


    ; =======================================================================
    ; CASE 6 — explicit disarm retains campaign evidence and suppresses hook.
    ; =======================================================================

    lea rdi, [rel controller_budget]
    call asm_qual_fault_disarm

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_11

    cmp qword [rel controller_budget + ASMWEB_QUAL_FAULT_CONTROLLER.active], 0
    jne .fail_11

    cmp qword [rel controller_budget + ASMWEB_QUAL_FAULT_CONTROLLER.fault_id], \
        ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    jne .fail_11

    cmp qword [rel controller_budget + ASMWEB_QUAL_FAULT_CONTROLLER.point_id], \
        ASMWEB_QUAL_POINT_AFTER_ACQUIRE_A
    jne .fail_11

    cmp qword [rel controller_budget + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 3
    jne .fail_11

    cmp qword [rel controller_budget + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], 2
    jne .fail_11


    lea rdi, [rel controller_budget]
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_A

    call asm_qual_fault_check

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_11

    test rdx, rdx
    jnz .fail_11

    cmp qword [rel controller_budget + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 3
    jne .fail_11


    ; =======================================================================
    ; CASE 7 — all controller representations validate.
    ; =======================================================================

    lea rdi, [rel controller_a]
    call asm_qual_fault_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    lea rdi, [rel controller_b]
    call asm_qual_fault_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    lea rdi, [rel controller_budget]
    call asm_qual_fault_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    lea rdi, [rel controller_invalid]
    call asm_qual_fault_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12


    ; =======================================================================
    ; CASE 8 — hit counter wrap is rejected atomically.
    ; =======================================================================

    mov rax, -1
    mov [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], rax

    mov rax, [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count]
    mov [rel saved_trigger_count], rax

    lea rdi, [rel controller_a]
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_A

    call asm_qual_fault_check

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13

    cmp qword [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], -1
    jne .fail_13

    ; Trigger count must not have changed.
    mov rax, [rel saved_trigger_count]

    cmp [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.trigger_count], rax
    jne .fail_13


    ; Restore coherent historical value.
    mov qword [rel controller_a + ASMWEB_QUAL_FAULT_CONTROLLER.hit_count], 1


    ; =======================================================================
    ; CASE 9 — a campaign controller cannot be silently repurposed.
    ; =======================================================================

    lea rdi, [rel controller_a]
    mov esi, ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION
    mov edx, ASMWEB_QUAL_POINT_AFTER_ACQUIRE_B
    mov ecx, 1

    call asm_qual_fault_arm

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14


    ; =======================================================================
    ; CASE 10 — Internal ABI / DF.
    ; =======================================================================

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std

    lea rdi, [rel controller_b]
    call asm_qual_fault_validate

    cmp eax, ASMWEB_RESOURCE_OK
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


    ; =======================================================================
    ; CASE 11 — pools finish quiescent and historically coherent.
    ; =======================================================================

    lea rdi, [rel pool_a]
    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_16

    lea rdi, [rel pool_b]
    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_16


    cmp qword [rel pool_a + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_16

    cmp qword [rel pool_b + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_16


    mov rax, [rel pool_a + ASMWEB_TYPED_POOL.acquisition_count]

    cmp rax, [rel pool_a + ASMWEB_TYPED_POOL.release_count]
    jne .fail_16


    mov rax, [rel pool_b + ASMWEB_TYPED_POOL.acquisition_count]

    cmp rax, [rel pool_b + ASMWEB_TYPED_POOL.release_count]
    jne .fail_16


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
