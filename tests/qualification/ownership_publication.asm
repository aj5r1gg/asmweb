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
; M0 ownership / publication qualification
;
; Governing semantic contract:
;
;   acquire privately
;       ->
;   initialise
;       ->
;   validate
;       ->
;   establish accounting
;       ->
;   publish
;       ->
;   transfer ownership
;
; The fixture uses one real ASMWEB_TYPED_POOL slot as the underlying bounded
; resource.
;
; While the object is private:
;
;   - the producer owns it;
;   - the consumer publication descriptor is pristine;
;   - consumer lookup returns no object.
;
; Publication:
;
;   - validates all required object state first;
;   - has no fallible work after the first publication store;
;   - establishes the consumer owner identity;
;   - writes ready last.
;
; After publication:
;
;   - consumer lookup resolves the exact object;
;   - producer-only mutation is rejected;
;   - repeat publication is rejected;
;   - ownership remains defined.
;
; This qualifies the M0 logical ownership/publication contract in the current
; single-threaded model.
;
; It does NOT establish:
;
;   - concurrent memory-ordering semantics;
;   - lock-free publication;
;   - inter-worker handoff;
;   - queue ownership;
;   - asynchronous/kernel-held borrows;
;   - final protocol-object ownership state machines.
; ===========================================================================


%define QUAL_OWNER_PRODUCER  0x510001
%define QUAL_OWNER_CONSUMER  0x510002

%define QUAL_PAYLOAD_A       0x12345678
%define QUAL_PAYLOAD_B       0x23456789


struc QUAL_OWNED_OBJECT
    .owner_id:       resq 1
    .initialised:    resq 1
    .accounted:      resq 1
    .payload_a:      resq 1
    .payload_b:      resq 1
endstruc


struc QUAL_PUBLICATION
    .object_ptr:     resq 1
    .owner_id:       resq 1
    .ready:          resq 1
endstruc


section .bss

alignb 64
pool_backing:
    resb 64

pool_slot_state:
    resb 1

alignb 8
pool_request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool:
    resb ASMWEB_TYPED_POOL_size


alignb 8
publication:
    resb QUAL_PUBLICATION_size

publication_bad:
    resb QUAL_PUBLICATION_size


section .text


; ===========================================================================
; qual_consumer_get
;
; RDI = QUAL_PUBLICATION *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_EXHAUSTED
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = published object pointer on OK
;         zero otherwise
;
; EXHAUSTED here means logically "not published / not externally reachable".
;
; Consumer visibility exists only through a complete ready publication.
; ===========================================================================

qual_consumer_get:
    cld

    test rdi, rdi
    jz .consumer_integrity

    cmp qword [rdi + QUAL_PUBLICATION.ready], 0
    je .consumer_not_published

    cmp qword [rdi + QUAL_PUBLICATION.ready], 1
    jne .consumer_integrity

    mov rdx, [rdi + QUAL_PUBLICATION.object_ptr]
    test rdx, rdx
    jz .consumer_integrity

    cmp qword [rdi + QUAL_PUBLICATION.owner_id], QUAL_OWNER_CONSUMER
    jne .consumer_integrity

    cmp qword [rdx + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_CONSUMER
    jne .consumer_integrity

    cmp qword [rdx + QUAL_OWNED_OBJECT.initialised], 1
    jne .consumer_integrity

    cmp qword [rdx + QUAL_OWNED_OBJECT.accounted], 1
    jne .consumer_integrity

    cmp qword [rdx + QUAL_OWNED_OBJECT.payload_a], QUAL_PAYLOAD_A
    jne .consumer_integrity

    cmp qword [rdx + QUAL_OWNED_OBJECT.payload_b], QUAL_PAYLOAD_B
    jne .consumer_integrity

    mov eax, ASMWEB_RESOURCE_OK
    ret


.consumer_not_published:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_EXHAUSTED
    ret


.consumer_integrity:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; qual_producer_write
;
; RDI = QUAL_OWNED_OBJECT *
; RSI = new payload_a
;
; Producer-only mutation helper.
;
; The operation is legal only while producer ownership remains explicit.
; Once publication transfers ownership, this operation MUST reject without
; modifying the object.
; ===========================================================================

qual_producer_write:
    cld

    test rdi, rdi
    jz .producer_write_integrity

    cmp qword [rdi + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_PRODUCER
    jne .producer_write_integrity

    mov [rdi + QUAL_OWNED_OBJECT.payload_a], rsi

    mov eax, ASMWEB_RESOURCE_OK
    ret


.producer_write_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; qual_publish
;
; RDI = QUAL_OWNED_OBJECT *
; RSI = pristine QUAL_PUBLICATION *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Publication preconditions:
;
;   object:
;       producer-owned;
;       initialised;
;       accounted;
;       complete qualified payload.
;
;   publication:
;       entirely pristine.
;
; Commit:
;
;   object_ptr
;   publication owner
;   object owner transfer
;   ready = 1 LAST
;
; No fallible work exists after the first commit store.
; ===========================================================================

qual_publish:
    cld

    test rdi, rdi
    jz .publish_integrity

    test rsi, rsi
    jz .publish_integrity


    ; Publication destination must be pristine.

    cmp qword [rsi + QUAL_PUBLICATION.object_ptr], 0
    jne .publish_integrity

    cmp qword [rsi + QUAL_PUBLICATION.owner_id], 0
    jne .publish_integrity

    cmp qword [rsi + QUAL_PUBLICATION.ready], 0
    jne .publish_integrity


    ; Producer must still own the object.

    cmp qword [rdi + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_PRODUCER
    jne .publish_integrity


    ; Complete construction state is mandatory.

    cmp qword [rdi + QUAL_OWNED_OBJECT.initialised], 1
    jne .publish_integrity

    cmp qword [rdi + QUAL_OWNED_OBJECT.accounted], 1
    jne .publish_integrity

    cmp qword [rdi + QUAL_OWNED_OBJECT.payload_a], QUAL_PAYLOAD_A
    jne .publish_integrity

    cmp qword [rdi + QUAL_OWNED_OBJECT.payload_b], QUAL_PAYLOAD_B
    jne .publish_integrity


    ; -----------------------------------------------------------------------
    ; Logical publication commit.
    ;
    ; No fallible work remains.
    ;
    ; The descriptor is not externally consumable until ready == 1.
    ; Ownership transfer is therefore complete before the final ready store.
    ; -----------------------------------------------------------------------

    mov [rsi + QUAL_PUBLICATION.object_ptr], rdi

    mov qword [rsi + QUAL_PUBLICATION.owner_id], QUAL_OWNER_CONSUMER

    mov qword [rdi + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_CONSUMER

    ; Publication marker LAST.
    mov qword [rsi + QUAL_PUBLICATION.ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret


.publish_integrity:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; qual_consumer_retire
;
; RDI = ASMWEB_TYPED_POOL *
; RSI = QUAL_PUBLICATION *
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Current M0 single-threaded retirement fixture:
;
;   validate published ownership
;       ->
;   make publication unreachable
;       ->
;   release consumer-owned slot
;       ->
;   clear publication descriptor
;
; If the underlying release unexpectedly fails, publication remains
; unpublished but still contains the pointer/consumer ownership identity,
; leaving ownership represented rather than silently lost.
;
; That recovery-residue pattern mirrors the stack rollback principle but this
; fixture does not inject release failure.
; ===========================================================================

qual_consumer_retire:
    cld

    test rdi, rdi
    jz .retire_integrity_no_frame

    test rsi, rsi
    jz .retire_integrity_no_frame

    push rbx
    push r12
    push r13

    ; Three pushes establish RSP % 16 == 0 before nested calls.
    mov rbx, rdi
    mov r12, rsi


    mov rdi, r12
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_OK
    jne .retire_integrity

    mov r13, rdx


    ; Withdraw external reachability first.
    ;
    ; Pointer + owner remain represented until release succeeds.
    mov qword [r12 + QUAL_PUBLICATION.ready], 0


    mov rdi, rbx
    mov rsi, r13
    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .retire_integrity


    ; Complete retirement after successful resource release.

    mov qword [r12 + QUAL_PUBLICATION.object_ptr], 0
    mov qword [r12 + QUAL_PUBLICATION.owner_id], 0

    ; ready is already zero.

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.retire_integrity:
    pop r13
    pop r12
    pop rbx


.retire_integrity_no_frame:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; Qualification program
;
; Exit codes:
;
;   0  PASS
;   1  pool initialisation failed
;   2  consumer observed unpublished empty state
;   3  private acquisition failed
;   4  consumer observed acquired but uninitialised object
;   5  producer mutation while private failed
;   6  consumer observed initialised but unaccounted object
;   7  incomplete object publication accepted
;   8  failed publication mutated publication/ownership
;   9  valid publication failed
;   10 published state incorrect
;   11 consumer could not resolve published object
;   12 old producer mutated transferred object
;   13 repeat publication accepted
;   14 publication corruption not detected
;   15 consumer retirement failed
;   16 retired object remained externally reachable
;   17 pool failed to return to quiescence
;   18 recycled private object became externally reachable accidentally
;   19 non-pristine publication accepted
;   20 NULL semantics failed
;   21 ABI/DF behaviour failed
;   22 final cleanup failed
; ===========================================================================

_start:
    cld


    ; =======================================================================
    ; Establish one-slot bounded typed pool
    ; =======================================================================

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x32000001

    lea rax, [rel pool_backing]
    mov [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 64

    lea rax, [rel pool_slot_state]
    mov [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 1

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.actual_size], \
        QUAL_OWNED_OBJECT_size

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 64

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.alignment], 64

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 1
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 1
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 0

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], \
        0x42000001

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL


    lea rdi, [rel pool_request]
    lea rsi, [rel pool]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    ; =======================================================================
    ; CASE 1 — pristine/unpublished state is not consumer-visible
    ; =======================================================================

    lea rdi, [rel publication]
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_2

    test rdx, rdx
    jne .fail_2


    ; =======================================================================
    ; CASE 2 — acquire privately
    ; =======================================================================

    lea rdi, [rel pool]
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3

    mov r12, rdx

    lea rax, [rel pool_backing]
    cmp r12, rax
    jne .fail_3


    ; Establish producer ownership only.
    mov qword [r12 + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_PRODUCER


    ; Underlying storage exists and is owned, but the consumer MUST NOT see it.

    lea rdi, [rel publication]
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_4

    test rdx, rdx
    jne .fail_4


    ; =======================================================================
    ; CASE 3 — producer can mutate while ownership is private
    ; =======================================================================

    mov rdi, r12
    mov esi, QUAL_PAYLOAD_A

    call qual_producer_write

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5

    cmp qword [r12 + QUAL_OWNED_OBJECT.payload_a], QUAL_PAYLOAD_A
    jne .fail_5


    ; Complete semantic initialisation, but deliberately do not account yet.

    mov qword [r12 + QUAL_OWNED_OBJECT.payload_b], QUAL_PAYLOAD_B
    mov qword [r12 + QUAL_OWNED_OBJECT.initialised], 1


    ; Still private.

    lea rdi, [rel publication]
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_6


    ; =======================================================================
    ; CASE 4 — initialised but unaccounted object cannot publish
    ; =======================================================================

    mov rdi, r12
    lea rsi, [rel publication]

    call qual_publish

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_7


    ; Failed publication must not transfer ownership or expose partial state.

    cmp qword [r12 + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_PRODUCER
    jne .fail_8

    cmp qword [rel publication + QUAL_PUBLICATION.object_ptr], 0
    jne .fail_8

    cmp qword [rel publication + QUAL_PUBLICATION.owner_id], 0
    jne .fail_8

    cmp qword [rel publication + QUAL_PUBLICATION.ready], 0
    jne .fail_8


    ; =======================================================================
    ; CASE 5 — establish accounting, then publish
    ; =======================================================================

    mov qword [r12 + QUAL_OWNED_OBJECT.accounted], 1


    mov rdi, r12
    lea rsi, [rel publication]

    call qual_publish

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_9


    cmp qword [rel publication + QUAL_PUBLICATION.ready], 1
    jne .fail_10

    cmp qword [rel publication + QUAL_PUBLICATION.object_ptr], r12
    jne .fail_10

    cmp qword [rel publication + QUAL_PUBLICATION.owner_id], QUAL_OWNER_CONSUMER
    jne .fail_10

    cmp qword [r12 + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_CONSUMER
    jne .fail_10


    ; =======================================================================
    ; CASE 6 — consumer now resolves exact published object
    ; =======================================================================

    lea rdi, [rel publication]

    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_11

    cmp rdx, r12
    jne .fail_11


    ; =======================================================================
    ; CASE 7 — old producer may no longer mutate transferred state
    ; =======================================================================

    mov rdi, r12
    mov esi, 0x33333333

    call qual_producer_write

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12

    cmp qword [r12 + QUAL_OWNED_OBJECT.payload_a], QUAL_PAYLOAD_A
    jne .fail_12


    ; =======================================================================
    ; CASE 8 — repeat publication is rejected without disturbing ownership
    ; =======================================================================

    mov rdi, r12
    lea rsi, [rel publication]

    call qual_publish

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13


    lea rdi, [rel publication]
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_13

    cmp rdx, r12
    jne .fail_13


    ; =======================================================================
    ; CASE 9 — contradictory published owner identity is detected
    ; =======================================================================

    mov qword [rel publication + QUAL_PUBLICATION.owner_id], QUAL_OWNER_PRODUCER

    lea rdi, [rel publication]
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14


    ; Restore legitimate published state.
    mov qword [rel publication + QUAL_PUBLICATION.owner_id], QUAL_OWNER_CONSUMER

    lea rdi, [rel publication]
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_14


    ; =======================================================================
    ; CASE 10 — consumer retires its owned object
    ; =======================================================================

    lea rdi, [rel pool]
    lea rsi, [rel publication]

    call qual_consumer_retire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_15


    ; Publication is no longer externally reachable.

    lea rdi, [rel publication]
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_16

    test rdx, rdx
    jne .fail_16


    ; Underlying resource returned to quiescent baseline.

    lea rdi, [rel pool]
    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17


    ; =======================================================================
    ; CASE 11 — recycling storage does not itself publish it
    ; =======================================================================

    lea rdi, [rel pool]
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18

    mov r13, rdx

    cmp r13, r12
    jne .fail_18


    ; Recycled memory still contains old payload bytes. That must not make it
    ; externally reachable because publication authority is separate.

    mov qword [r13 + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_PRODUCER

    lea rdi, [rel publication]
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_18


    ; Clean recycled fixture directly through current producer lifetime.

    lea rdi, [rel pool]
    mov rsi, r13

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18


    ; =======================================================================
    ; CASE 12 — non-pristine publication is rejected
    ; =======================================================================

    mov qword [rel publication_bad + QUAL_PUBLICATION.owner_id], \
        QUAL_OWNER_CONSUMER


    ; Acquire a fresh private object for this rejection test.

    lea rdi, [rel pool]
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    mov r14, rdx


    mov qword [r14 + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_PRODUCER
    mov qword [r14 + QUAL_OWNED_OBJECT.initialised], 1
    mov qword [r14 + QUAL_OWNED_OBJECT.accounted], 1
    mov qword [r14 + QUAL_OWNED_OBJECT.payload_a], QUAL_PAYLOAD_A
    mov qword [r14 + QUAL_OWNED_OBJECT.payload_b], QUAL_PAYLOAD_B


    mov rdi, r14
    lea rsi, [rel publication_bad]

    call qual_publish

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_19


    ; Producer ownership must survive rejection.
    cmp qword [r14 + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_PRODUCER
    jne .fail_19


    lea rdi, [rel pool]
    mov rsi, r14

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    ; =======================================================================
    ; CASE 13 — NULL semantics
    ; =======================================================================

    xor edi, edi
    call qual_consumer_get

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20


    xor edi, edi
    mov esi, QUAL_PAYLOAD_A
    call qual_producer_write

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20


    xor edi, edi
    lea rsi, [rel publication]

    call qual_publish

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20


    lea rdi, [rel pool]
    xor esi, esi

    call qual_consumer_retire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20


    ; =======================================================================
    ; CASE 14 — publication helper preserves ABI callee-saved state + DF
    ;
    ; Build one complete private object first.
    ; =======================================================================

    lea rdi, [rel pool]
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21

    mov r10, rdx


    ; publication is pristine after the earlier retirement.
    mov qword [r10 + QUAL_OWNED_OBJECT.owner_id], QUAL_OWNER_PRODUCER
    mov qword [r10 + QUAL_OWNED_OBJECT.initialised], 1
    mov qword [r10 + QUAL_OWNED_OBJECT.accounted], 1
    mov qword [r10 + QUAL_OWNED_OBJECT.payload_a], QUAL_PAYLOAD_A
    mov qword [r10 + QUAL_OWNED_OBJECT.payload_b], QUAL_PAYLOAD_B


    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std


    mov rdi, r10
    lea rsi, [rel publication]

    call qual_publish

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21


    cmp rbx, 0x11111111
    jne .fail_21

    cmp rbp, 0x22222222
    jne .fail_21

    cmp r12, 0x33333333
    jne .fail_21

    cmp r13, 0x44444444
    jne .fail_21

    mov rax, 0x55555555
    cmp r14, rax
    jne .fail_21

    mov rax, 0x66666666
    cmp r15, rax
    jne .fail_21


    pushfq
    pop rax

    test rax, 1 << 10
    jnz .fail_21


    ; =======================================================================
    ; CASE 15 — final cleanup
    ; =======================================================================

    lea rdi, [rel pool]
    lea rsi, [rel publication]

    call qual_consumer_retire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22


    lea rdi, [rel pool]
    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22


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
