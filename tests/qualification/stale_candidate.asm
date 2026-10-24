bits 64

%include "asmweb/arithmetic.inc"
%include "asmweb/resource.inc"
%include "asmweb/pool.inc"
%include "asmweb/stale_candidate.inc"

global _start

extern asm_typed_pool_init
extern asm_typed_pool_validate
extern asm_typed_pool_quiescent

extern asm_stale_candidate_init
extern asm_stale_candidate_validate
extern asm_stale_candidate_acquire
extern asm_stale_candidate_lookup
extern asm_stale_candidate_release

extern asm_linux_exit


section .bss

alignb 64
backing:
    resb 128

slot_state:
    resb 4

alignb 8
pool_request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool:
    resb ASMWEB_TYPED_POOL_size


; Candidate generation metadata.
alignb 8
generations:
    resq 2

generations_alt:
    resq 2


candidate:
    resb ASMWEB_STALE_CANDIDATE_size

candidate_bad_1:
    resb ASMWEB_STALE_CANDIDATE_size

candidate_bad_2:
    resb ASMWEB_STALE_CANDIDATE_size


handle_a:
    resb ASMWEB_STALE_HANDLE_size

handle_b:
    resb ASMWEB_STALE_HANDLE_size

handle_bad:
    resb ASMWEB_STALE_HANDLE_size

handle_abi:
    resb ASMWEB_STALE_HANDLE_size


section .text

; ===========================================================================
; M0 candidate stale-reference qualification
;
; Pool fixture:
;
;   object class        = 0x30001001
;   actual size         = 24
;   effective stride    = 32
;   alignment           = 16
;   physical capacity   = 2
;   configured capacity = 2
;   reserve             = 0
;   ordinary capacity   = 2
;
; Candidate:
;
;   two uint64 generation entries
;   initial generation for every slot = 1
;
; This suite qualifies:
;
;   - candidate metadata accounting;
;   - class validation;
;   - index validation;
;   - non-zero/current generation validation;
;   - ownership validation;
;   - stale rejection after release;
;   - same-address reuse without stale-handle resurrection;
;   - bounded non-wrapping generation exhaustion;
;   - candidate validation/corruption detection;
;   - init structural rejection;
;   - ABI/DF preservation.
;
; It does NOT qualify:
;
;   - concurrency;
;   - ABA-safe reclamation;
;   - asynchronous publication;
;   - final generation width;
;   - final production handle architecture.
;
; Exit:
;
;   0  PASS
;   1  pool init failed
;   2  candidate init failed
;   3  candidate metadata/accounting invalid
;   4  first candidate acquisition failed
;   5  first handle contents incorrect
;   6  current handle lookup failed
;   7  wrong class accepted
;   8  out-of-range index accepted
;   9  zero generation accepted
;   10 wrong generation accepted
;   11 release failed
;   12 released handle remained live
;   13 same slot/address was not reused
;   14 new lifetime generation incorrect
;   15 old handle resurrected after reuse
;   16 new handle failed after reuse
;   17 stale release accepted/mutated occupancy
;   18 generation-exhaustion boundary failed
;   19 final cleanup/quiescence failed
;   20 dirty generation metadata accepted
;   21 non-pristine candidate accepted/destructively overwritten
;   22 generation count mismatch accepted
;   23 insufficient generation storage accepted
;   24 candidate/generation overlap accepted
;   25 occupied-pool attachment accepted
;   26 NULL semantics failed
;   27 candidate corruption not detected
;   28 ABI/DF preservation failed
;   29 publication corruption accepted
;   30 generation count corruption accepted
;   31 generation storage byte corruption accepted
;   32 management accounting corruption accepted
;   33 zero generation corruption accepted or recovery failed
; ===========================================================================

_start:
    cld


    ; -----------------------------------------------------------------------
    ; Canonical typed pool.
    ; -----------------------------------------------------------------------

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x30001001

    lea rax, [rel backing]
    mov [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 128

    lea rax, [rel slot_state]
    mov [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 4

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 24
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 32
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 2
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 2
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 0

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], \
        0x40001001

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL


    lea rdi, [rel pool_request]
    lea rsi, [rel pool]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    ; =======================================================================
    ; CASE 1 — initialize stale-reference candidate
    ; =======================================================================

    lea rdi, [rel pool]
    lea rsi, [rel generations]
    mov edx, 2
    mov ecx, 16
    lea r8, [rel candidate]

    call asm_stale_candidate_init

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_2


    lea rdi, [rel candidate]

    call asm_stale_candidate_validate

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_3


    ; Exact candidate metadata accounting.

    cmp qword [rel candidate + ASMWEB_STALE_CANDIDATE.generation_count], 2
    jne .fail_3

    cmp qword [rel candidate + ASMWEB_STALE_CANDIDATE.generation_bytes], 16
    jne .fail_3

    cmp qword [rel candidate + ASMWEB_STALE_CANDIDATE.management_bytes_total], \
        ASMWEB_STALE_CANDIDATE_size + 16
    jne .fail_3

    cmp qword [rel generations + 0], 1
    jne .fail_3

    cmp qword [rel generations + 8], 1
    jne .fail_3


    ; =======================================================================
    ; CASE 2 — first candidate acquisition
    ; =======================================================================

    lea rdi, [rel candidate]
    lea rsi, [rel handle_a]

    call asm_stale_candidate_acquire

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_4

    lea rax, [rel backing]

    cmp rdx, rax
    jne .fail_4

    mov r12, rdx


    cmp qword [rel handle_a + ASMWEB_STALE_HANDLE.object_class_id], \
        0x30001001
    jne .fail_5

    cmp qword [rel handle_a + ASMWEB_STALE_HANDLE.slot_index], 0
    jne .fail_5

    cmp qword [rel handle_a + ASMWEB_STALE_HANDLE.generation], 1
    jne .fail_5


    ; =======================================================================
    ; CASE 3 — current handle resolves
    ; =======================================================================

    lea rdi, [rel candidate]
    lea rsi, [rel handle_a]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_6

    cmp rdx, r12
    jne .fail_6


    ; =======================================================================
    ; CASE 4 — wrong object class rejected
    ; =======================================================================

    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.object_class_id], \
        0x30001002

    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.slot_index], 0
    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.generation], 1

    lea rdi, [rel candidate]
    lea rsi, [rel handle_bad]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    jne .fail_7

    test rdx, rdx
    jne .fail_7


    ; =======================================================================
    ; CASE 5 — out-of-range slot index rejected
    ; =======================================================================

    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.object_class_id], \
        0x30001001

    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.slot_index], 2
    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.generation], 1

    lea rdi, [rel candidate]
    lea rsi, [rel handle_bad]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    jne .fail_8


    ; =======================================================================
    ; CASE 6 — zero generation rejected
    ; =======================================================================

    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.slot_index], 0
    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.generation], 0

    lea rdi, [rel candidate]
    lea rsi, [rel handle_bad]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    jne .fail_9


    ; =======================================================================
    ; CASE 7 — wrong non-zero generation rejected
    ; =======================================================================

    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.generation], 2

    lea rdi, [rel candidate]
    lea rsi, [rel handle_bad]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    jne .fail_10


    ; =======================================================================
    ; CASE 8 — release lifetime 1
    ; =======================================================================

    lea rdi, [rel candidate]
    lea rsi, [rel handle_a]

    call asm_stale_candidate_release

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_11

    cmp qword [rel generations + 0], 2
    jne .fail_11

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_11


    ; Old handle must immediately be stale.

    lea rdi, [rel candidate]
    lea rsi, [rel handle_a]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    jne .fail_12

    test rdx, rdx
    jne .fail_12


    ; =======================================================================
    ; CASE 9 — reacquire the same physical slot/address
    ; =======================================================================

    lea rdi, [rel candidate]
    lea rsi, [rel handle_b]

    call asm_stale_candidate_acquire

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_13

    cmp rdx, r12
    jne .fail_13

    cmp qword [rel handle_b + ASMWEB_STALE_HANDLE.slot_index], 0
    jne .fail_13


    ; New lifetime has advanced generation.

    cmp qword [rel handle_b + ASMWEB_STALE_HANDLE.generation], 2
    jne .fail_14


    ; =======================================================================
    ; CASE 10 — old handle stays stale despite identical raw address
    ; =======================================================================

    lea rdi, [rel candidate]
    lea rsi, [rel handle_a]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    jne .fail_15


    ; New handle resolves.

    lea rdi, [rel candidate]
    lea rsi, [rel handle_b]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_16

    cmp rdx, r12
    jne .fail_16


    ; =======================================================================
    ; CASE 11 — stale handle cannot release the new lifetime
    ; =======================================================================

    lea rdi, [rel candidate]
    lea rsi, [rel handle_a]

    call asm_stale_candidate_release

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    jne .fail_17

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 1
    jne .fail_17

    cmp qword [rel generations + 0], 2
    jne .fail_17


    ; =======================================================================
    ; CASE 12 — finite generation boundary refuses wrap without mutation
    ;
    ; This is a controlled candidate-boundary fixture. It does NOT claim that
    ; 64 bits is the final justified generation width.
    ; =======================================================================

    mov rax, ASMWEB_U64_MAX
    mov [rel generations + 0], rax
    mov [rel handle_b + ASMWEB_STALE_HANDLE.generation], rax


    ; Handle with the current maximum generation still resolves.

    lea rdi, [rel candidate]
    lea rsi, [rel handle_b]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_18


    ; Release must refuse rather than wrap.

    lea rdi, [rel candidate]
    lea rsi, [rel handle_b]

    call asm_stale_candidate_release

    cmp eax, ASMWEB_STALE_RESULT_REJECTED
    jne .fail_18

    mov rax, ASMWEB_U64_MAX
    cmp [rel generations + 0], rax
    jne .fail_18

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 1
    jne .fail_18


    ; Restore the controlled fixture to its real lifetime identity and cleanly
    ; release it.

    mov qword [rel generations + 0], 2
    mov qword [rel handle_b + ASMWEB_STALE_HANDLE.generation], 2

    lea rdi, [rel candidate]
    lea rsi, [rel handle_b]

    call asm_stale_candidate_release

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_19

    cmp qword [rel generations + 0], 3
    jne .fail_19

    lea rdi, [rel pool]

    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    ; =======================================================================
    ; CASE 13 — dirty generation metadata rejected
    ; =======================================================================

    mov qword [rel generations_alt + 0], 7

    lea rdi, [rel pool]
    lea rsi, [rel generations_alt]
    mov edx, 2
    mov ecx, 16
    lea r8, [rel candidate_bad_1]

    call asm_stale_candidate_init

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_20

    ; Rejection must not publish candidate.
    cmp qword [rel candidate_bad_1 + ASMWEB_STALE_CANDIDATE.ready], 0
    jne .fail_20

    ; Rejection must not rewrite caller metadata.
    cmp qword [rel generations_alt + 0], 7
    jne .fail_20

    mov qword [rel generations_alt + 0], 0


    ; =======================================================================
    ; CASE 14 — non-pristine candidate rejected non-destructively
    ; =======================================================================

    mov eax, 0x12345678
    mov [rel candidate_bad_1 + ASMWEB_STALE_CANDIDATE.object_class_id], rax

    lea rdi, [rel pool]
    lea rsi, [rel generations_alt]
    mov edx, 2
    mov ecx, 16
    lea r8, [rel candidate_bad_1]

    call asm_stale_candidate_init

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_21

    mov eax, 0x12345678
    cmp [rel candidate_bad_1 + ASMWEB_STALE_CANDIDATE.object_class_id], rax
    jne .fail_21

    ; Restore test fixture.
    mov qword [rel candidate_bad_1 + ASMWEB_STALE_CANDIDATE.object_class_id], 0


    ; =======================================================================
    ; CASE 15 — generation count must equal physical slot count
    ; =======================================================================

    lea rdi, [rel pool]
    lea rsi, [rel generations_alt]
    mov edx, 1
    mov ecx, 16
    lea r8, [rel candidate_bad_1]

    call asm_stale_candidate_init

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_22


    ; =======================================================================
    ; CASE 16 — generation storage must represent the complete array
    ; =======================================================================

    lea rdi, [rel pool]
    lea rsi, [rel generations_alt]
    mov edx, 2
    mov ecx, 15
    lea r8, [rel candidate_bad_1]

    call asm_stale_candidate_init

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_23


    ; =======================================================================
    ; CASE 17 — generation metadata cannot overlap candidate descriptor
    ; =======================================================================

    lea rdi, [rel pool]
    lea rsi, [rel candidate_bad_2]
    mov edx, 2
    mov ecx, 16
    lea r8, [rel candidate_bad_2]

    call asm_stale_candidate_init

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_24


    ; =======================================================================
    ; CASE 18 — candidate cannot attach to an occupied pool
    ; =======================================================================

    ; Acquire through the established candidate.
    lea rdi, [rel candidate]
    lea rsi, [rel handle_bad]

    ; handle_bad currently contains old test values; clear it first.
    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.object_class_id], 0
    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.slot_index], 0
    mov qword [rel handle_bad + ASMWEB_STALE_HANDLE.generation], 0

    call asm_stale_candidate_acquire

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_25

    mov r15, rdx


    lea rdi, [rel pool]
    lea rsi, [rel generations_alt]
    mov edx, 2
    mov ecx, 16
    lea r8, [rel candidate_bad_1]

    call asm_stale_candidate_init

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_25


    ; Clean up occupied slot.
    lea rdi, [rel candidate]
    lea rsi, [rel handle_bad]

    call asm_stale_candidate_release

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_25


    ; =======================================================================
    ; CASE 19 — NULL semantics
    ; =======================================================================

    xor edi, edi
    lea rsi, [rel generations_alt]
    mov edx, 2
    mov ecx, 16
    lea r8, [rel candidate_bad_1]

    call asm_stale_candidate_init

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_26


    xor edi, edi

    call asm_stale_candidate_validate

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_26


    xor edi, edi
    lea rsi, [rel handle_a]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_26

    test rdx, rdx
    jne .fail_26


    lea rdi, [rel candidate]
    xor esi, esi

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_26


    xor edi, edi
    lea rsi, [rel handle_a]

    call asm_stale_candidate_acquire

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_26


    xor edi, edi
    lea rsi, [rel handle_a]

    call asm_stale_candidate_release

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_26


    ; =======================================================================
    ; CASE 20 — candidate validator detects cached-class corruption
    ; =======================================================================

    mov rax, [rel candidate + ASMWEB_STALE_CANDIDATE.object_class_id]
    mov r14, rax

    inc rax
    mov [rel candidate + ASMWEB_STALE_CANDIDATE.object_class_id], rax

    lea rdi, [rel candidate]

    call asm_stale_candidate_validate

    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_27

    mov [rel candidate + ASMWEB_STALE_CANDIDATE.object_class_id], r14

    lea rdi, [rel candidate]

    call asm_stale_candidate_validate

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_27


    ; =======================================================================
    ; CASE 21 — lookup preserves Internal ABI callee-saved state and clears DF
    ; =======================================================================

    ; Obtain one live candidate identity.
    lea rdi, [rel candidate]
    lea rsi, [rel handle_abi]

    call asm_stale_candidate_acquire

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_28


    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std

    lea rdi, [rel candidate]
    lea rsi, [rel handle_abi]

    call asm_stale_candidate_lookup

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_28

    ; The pool is quiescent before this acquisition, and the M0 pool uses
    ; deterministic first-free ordinary-slot acquisition. The live ABI test
    ; identity therefore belongs to slot zero, whose raw address is backing.
    ;
    ; Do NOT preserve the expected pointer in R10: R10 is caller-saved under
    ; the AsmWeb Internal ABI and lookup is entitled to clobber it.
    lea rax, [rel backing]
    cmp rdx, rax
    jne .fail_28

    cmp rbx, 0x11111111
    jne .fail_28

    cmp rbp, 0x22222222
    jne .fail_28

    cmp r12, 0x33333333
    jne .fail_28

    cmp r13, 0x44444444
    jne .fail_28

    mov rax, 0x55555555
    cmp r14, rax
    jne .fail_28

    mov rax, 0x66666666
    cmp r15, rax
    jne .fail_28

    pushfq
    pop rax

    test rax, 1 << 10
    jnz .fail_28


    ; Clean final live identity.

    lea rdi, [rel candidate]
    lea rsi, [rel handle_abi]

    call asm_stale_candidate_release

    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_28

    lea rdi, [rel pool]

    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_28


    ; =======================================================================
    ; CASE 22 — publication marker corruption must fail validation
    ; =======================================================================

    mov qword [rel candidate + ASMWEB_STALE_CANDIDATE.ready], 0
    lea rdi, [rel candidate]
    call asm_stale_candidate_validate
    mov qword [rel candidate + ASMWEB_STALE_CANDIDATE.ready], 1
    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_29

    ; =======================================================================
    ; CASE 23 — generation count corruption must fail validation
    ; =======================================================================

    inc qword [rel candidate + ASMWEB_STALE_CANDIDATE.generation_count]
    lea rdi, [rel candidate]
    call asm_stale_candidate_validate
    dec qword [rel candidate + ASMWEB_STALE_CANDIDATE.generation_count]
    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_30

    ; =======================================================================
    ; CASE 24 — generation byte count corruption must fail validation
    ; =======================================================================

    add qword [rel candidate + ASMWEB_STALE_CANDIDATE.generation_bytes], 8
    lea rdi, [rel candidate]
    call asm_stale_candidate_validate
    sub qword [rel candidate + ASMWEB_STALE_CANDIDATE.generation_bytes], 8
    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_31

    ; =======================================================================
    ; CASE 25 — management accounting corruption must fail validation
    ; =======================================================================

    inc qword [rel candidate + ASMWEB_STALE_CANDIDATE.management_bytes_total]
    lea rdi, [rel candidate]
    call asm_stale_candidate_validate
    dec qword [rel candidate + ASMWEB_STALE_CANDIDATE.management_bytes_total]
    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_32

    ; =======================================================================
    ; CASE 26 — zero generation must fail validation, then recover
    ; =======================================================================

    mov r14, [rel generations]
    mov qword [rel generations], 0
    lea rdi, [rel candidate]
    call asm_stale_candidate_validate
    mov [rel generations], r14
    cmp eax, ASMWEB_STALE_RESULT_INTEGRITY
    jne .fail_33

    lea rdi, [rel candidate]
    call asm_stale_candidate_validate
    cmp eax, ASMWEB_STALE_RESULT_OK
    jne .fail_33

    lea rdi, [rel pool]
    call asm_typed_pool_quiescent
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_33

    ; =======================================================================
    ; PASS
    ; =======================================================================

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

.fail_27:
    mov edi, 27
    call asm_linux_exit
    ud2

.fail_28:
    mov edi, 28
    call asm_linux_exit
    ud2

.fail_29:
    mov edi, 29
    call asm_linux_exit
    ud2

.fail_30:
    mov edi, 30
    call asm_linux_exit
    ud2

.fail_31:
    mov edi, 31
    call asm_linux_exit
    ud2

.fail_32:
    mov edi, 32
    call asm_linux_exit
    ud2

.fail_33:
    mov edi, 33
    call asm_linux_exit
    ud2
