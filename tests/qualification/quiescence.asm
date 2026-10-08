bits 64

%include "asmweb/abi.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/resource.inc"
%include "asmweb/pool.inc"
%include "asmweb/startup_memory.inc"
%include "asmweb/quiescence.inc"

global _start

extern asm_quiescence_init
extern asm_quiescence_validate
extern asm_quiescence_observe
extern asm_quiescence_evaluate

extern asm_typed_pool_init
extern asm_typed_pool_acquire
extern asm_typed_pool_release
extern asm_typed_pool_quiescent

extern asm_startup_memory_account_init
extern asm_startup_memory_account_baseline
extern asm_startup_memory_account_acquire
extern asm_startup_memory_account_release

extern asm_linux_exit


; ===========================================================================
; M0 quiescence qualification
;
; Qualifies:
;
;   - zero and non-zero configuration-derived baselines;
;   - exact retained-state decomposition;
;   - EXPECTED_PERSISTENT;
;   - GRACE_TRANSIENT;
;   - EXTERNAL_COMPLETION_PENDING;
;   - UNEXPLAINED_RETAINED;
;   - CONFIRMED_LEAK;
;   - deterministic outcome precedence;
;   - failure-atomic observations;
;   - observation-count history;
;   - real typed-pool integration;
;   - real startup-memory non-zero-baseline integration;
;   - ABI / DF behaviour.
;
; This does not infer when a grace interval expires or when unexplained state
; becomes a confirmed leak. Those are subsystem/qualification-policy decisions.
; ===========================================================================


section .bss

alignb 8
q_zero:
    resb ASMWEB_QUIESCENCE_STATE_size

q_persistent:
    resb ASMWEB_QUIESCENCE_STATE_size

q_bad:
    resb ASMWEB_QUIESCENCE_STATE_size

q_abi:
    resb ASMWEB_QUIESCENCE_STATE_size


; ---------------------------------------------------------------------------
; Pool integration fixture
; ---------------------------------------------------------------------------

alignb 64
pool_backing:
    resb 64

pool_slot_state:
    resb 2

alignb 8
pool_request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool:
    resb ASMWEB_TYPED_POOL_size

q_pool:
    resb ASMWEB_QUIESCENCE_STATE_size


; ---------------------------------------------------------------------------
; Startup-memory non-zero baseline fixture
; ---------------------------------------------------------------------------

startup_account:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size

q_startup:
    resb ASMWEB_QUIESCENCE_STATE_size


section .text


; ===========================================================================
; Exit codes
;
;   0  PASS
;   1  zero-baseline init/evaluation failed
;   2  non-zero baseline failed
;   3  grace classification failed
;   4  external-pending classification failed
;   5  mixed pending classification failed
;   6  unexplained classification failed
;   7  confirmed-leak classification failed
;   8  fail precedence failed
;   9  incomplete decomposition accepted
;   10 below-baseline observation accepted
;   11 arithmetic overflow accepted
;   12 failed observation mutated state
;   13 observation-count overflow accepted
;   14 corruption not detected
;   15 reinitialisation/non-pristine state accepted
;   16 NULL semantics failed
;   17 pool integration failed
;   18 pool did not return to baseline
;   19 startup-memory baseline integration failed
;   20 startup transient integration failed
;   21 startup baseline restoration failed
;   22 ABI/DF behaviour failed
; ===========================================================================

_start:
    cld


    ; =======================================================================
    ; CASE 1 — zero baseline is legitimate and immediately quiescent
    ; =======================================================================

    xor edi, edi
    lea rsi, [rel q_zero]

    call asm_quiescence_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    lea rdi, [rel q_zero]
    call asm_quiescence_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    lea rdi, [rel q_zero]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_BASELINE
    jne .fail_1

    test rdx, rdx
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — non-zero expected persistent baseline
    ; =======================================================================

    mov edi, 4096
    lea rsi, [rel q_persistent]

    call asm_quiescence_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    cmp qword [rel q_persistent + ASMWEB_QUIESCENCE_STATE.baseline], 4096
    jne .fail_2

    cmp qword [rel q_persistent + ASMWEB_QUIESCENCE_STATE.current], 4096
    jne .fail_2

    cmp qword [rel q_persistent + ASMWEB_QUIESCENCE_STATE.expected_persistent], \
        4096
    jne .fail_2


    lea rdi, [rel q_persistent]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_BASELINE
    jne .fail_2

    cmp edx, ASMWEB_QUIESCENCE_CLASS_EXPECTED_PERSISTENT
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — grace transient
    ; =======================================================================

    lea rdi, [rel q_persistent]
    mov esi, 4608
    mov edx, 512
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3


    lea rdi, [rel q_persistent]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_PENDING
    jne .fail_3

    mov ecx, \
        ASMWEB_QUIESCENCE_CLASS_EXPECTED_PERSISTENT | \
        ASMWEB_QUIESCENCE_CLASS_GRACE_TRANSIENT

    cmp edx, ecx
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — external completion pending
    ; =======================================================================

    lea rdi, [rel q_persistent]
    mov esi, 4352
    xor edx, edx
    mov ecx, 256
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4


    lea rdi, [rel q_persistent]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_PENDING
    jne .fail_4

    mov ecx, \
        ASMWEB_QUIESCENCE_CLASS_EXPECTED_PERSISTENT | \
        ASMWEB_QUIESCENCE_CLASS_EXTERNAL_COMPLETION_PENDING

    cmp edx, ecx
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — grace + external may coexist
    ; =======================================================================

    lea rdi, [rel q_persistent]
    mov esi, 4864
    mov edx, 512
    mov ecx, 256
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5


    lea rdi, [rel q_persistent]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_PENDING
    jne .fail_5

    mov ecx, \
        ASMWEB_QUIESCENCE_CLASS_EXPECTED_PERSISTENT | \
        ASMWEB_QUIESCENCE_CLASS_GRACE_TRANSIENT | \
        ASMWEB_QUIESCENCE_CLASS_EXTERNAL_COMPLETION_PENDING

    cmp edx, ecx
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — unexplained retained state fails quiescence qualification
    ; =======================================================================

    lea rdi, [rel q_persistent]
    mov esi, 4224
    xor edx, edx
    xor ecx, ecx
    mov r8d, 128
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6


    lea rdi, [rel q_persistent]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_FAIL
    jne .fail_6

    test edx, ASMWEB_QUIESCENCE_CLASS_UNEXPLAINED_RETAINED
    jz .fail_6


    ; =======================================================================
    ; CASE 7 — confirmed leak fails
    ; =======================================================================

    lea rdi, [rel q_persistent]
    mov esi, 4160
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    mov r9d, 64

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7


    lea rdi, [rel q_persistent]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_FAIL
    jne .fail_7

    test edx, ASMWEB_QUIESCENCE_CLASS_CONFIRMED_LEAK
    jz .fail_7


    ; =======================================================================
    ; CASE 8 — failure classes take precedence over pending classes
    ; =======================================================================

    lea rdi, [rel q_persistent]
    mov esi, 4224
    mov edx, 32
    mov ecx, 32
    mov r8d, 32
    mov r9d, 32

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8


    lea rdi, [rel q_persistent]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_FAIL
    jne .fail_8

    mov ecx, \
        ASMWEB_QUIESCENCE_CLASS_EXPECTED_PERSISTENT | \
        ASMWEB_QUIESCENCE_CLASS_GRACE_TRANSIENT | \
        ASMWEB_QUIESCENCE_CLASS_EXTERNAL_COMPLETION_PENDING | \
        ASMWEB_QUIESCENCE_CLASS_UNEXPLAINED_RETAINED | \
        ASMWEB_QUIESCENCE_CLASS_CONFIRMED_LEAK

    cmp edx, ecx
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — incomplete classification decomposition rejected
    ; =======================================================================

    mov r12, [rel q_persistent + ASMWEB_QUIESCENCE_STATE.observation_count]
    mov r13, [rel q_persistent + ASMWEB_QUIESCENCE_STATE.current]

    lea rdi, [rel q_persistent]
    mov esi, 4200
    mov edx, 1
    mov ecx, 1
    mov r8d, 1
    mov r9d, 1

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9


    ; Failure atomicity.
    cmp [rel q_persistent + ASMWEB_QUIESCENCE_STATE.observation_count], r12
    jne .fail_12

    cmp [rel q_persistent + ASMWEB_QUIESCENCE_STATE.current], r13
    jne .fail_12


    ; =======================================================================
    ; CASE 10 — current below persistent baseline rejected
    ; =======================================================================

    lea rdi, [rel q_persistent]
    mov esi, 4095
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10


    ; =======================================================================
    ; CASE 11 — arithmetic overflow rejected
    ; =======================================================================

    lea rdi, [rel q_persistent]
    mov rsi, ASMWEB_U64_MAX
    mov rdx, ASMWEB_U64_MAX
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11


    ; =======================================================================
    ; CASE 12 — observation counter cannot wrap
    ; =======================================================================

    ; Restore exact baseline first.
    lea rdi, [rel q_persistent]
    mov esi, 4096
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_13


    mov rax, ASMWEB_U64_MAX
    mov [rel q_persistent + ASMWEB_QUIESCENCE_STATE.observation_count], rax


    lea rdi, [rel q_persistent]
    mov esi, 4096
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13


    mov rax, ASMWEB_U64_MAX
    cmp [rel q_persistent + ASMWEB_QUIESCENCE_STATE.observation_count], rax
    jne .fail_13


    ; Restore fixture history to a valid finite value for remaining cases.
    mov qword [rel q_persistent + ASMWEB_QUIESCENCE_STATE.observation_count], 6


    ; =======================================================================
    ; CASE 13 — validator detects contradictory decomposition
    ; =======================================================================

    mov qword [rel q_persistent + ASMWEB_QUIESCENCE_STATE.current], 4097

    lea rdi, [rel q_persistent]
    call asm_quiescence_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14


    lea rdi, [rel q_persistent]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_INTEGRITY
    jne .fail_14

    test rdx, rdx
    jne .fail_14


    ; Restore.
    mov qword [rel q_persistent + ASMWEB_QUIESCENCE_STATE.current], 4096


    ; =======================================================================
    ; CASE 14 — reinitialisation/non-pristine state rejected
    ; =======================================================================

    mov edi, 4096
    lea rsi, [rel q_persistent]

    call asm_quiescence_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15


    ; =======================================================================
    ; CASE 15 — NULL semantics
    ; =======================================================================

    xor esi, esi
    xor edi, edi

    call asm_quiescence_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    xor edi, edi

    call asm_quiescence_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    xor edi, edi

    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_INTEGRITY
    jne .fail_16


    ; =======================================================================
    ; CASE 16 — integrate real typed-pool zero baseline
    ; =======================================================================

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x33000001

    lea rax, [rel pool_backing]
    mov [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 64

    lea rax, [rel pool_slot_state]
    mov [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 2

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 24
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 32
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 2
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 2
    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 0

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], \
        0x43000001

    mov qword [rel pool_request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL


    lea rdi, [rel pool_request]
    lea rsi, [rel pool]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17


    ; Derive pool baseline from actual authoritative current occupancy.
    mov rdi, [rel pool + ASMWEB_TYPED_POOL.current_occupancy]
    lea rsi, [rel q_pool]

    call asm_quiescence_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17


    lea rdi, [rel pool]
    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17

    mov r12, rdx


    ; One retained pool object classified as grace-transient.
    lea rdi, [rel q_pool]
    mov rsi, [rel pool + ASMWEB_TYPED_POOL.current_occupancy]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17


    lea rdi, [rel q_pool]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_PENDING
    jne .fail_17


    ; Release and derive current from authoritative pool state again.
    lea rdi, [rel pool]
    mov rsi, r12

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18


    lea rdi, [rel pool]
    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18


    lea rdi, [rel q_pool]
    mov rsi, [rel pool + ASMWEB_TYPED_POOL.current_occupancy]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18


    lea rdi, [rel q_pool]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_BASELINE
    jne .fail_18


    ; =======================================================================
    ; CASE 17 — integrate real startup-memory NON-ZERO baseline
    ; =======================================================================

    lea rdi, [rel startup_account]
    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    lea rdi, [rel startup_account]
    mov esi, 4096

    call asm_startup_memory_account_baseline

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    ; Derive quiescent baseline from authoritative startup account.
    mov rdi, [rel startup_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]
    lea rsi, [rel q_startup]

    call asm_quiescence_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    lea rdi, [rel q_startup]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_BASELINE
    jne .fail_19

    test edx, ASMWEB_QUIESCENCE_CLASS_EXPECTED_PERSISTENT
    jz .fail_19


    ; Add temporary retained startup state.
    lea rdi, [rel startup_account]
    mov esi, 512

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_20


    lea rdi, [rel q_startup]
    mov rsi, [rel startup_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]
    mov edx, 512
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_20


    lea rdi, [rel q_startup]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_PENDING
    jne .fail_20


    ; Release temporary state and return exactly to persistent baseline.
    lea rdi, [rel startup_account]
    mov esi, 512

    call asm_startup_memory_account_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21


    lea rdi, [rel q_startup]
    mov rsi, [rel startup_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21


    lea rdi, [rel q_startup]
    call asm_quiescence_evaluate

    cmp eax, ASMWEB_QUIESCENCE_OUTCOME_BASELINE
    jne .fail_21

    cmp qword [rel q_startup + ASMWEB_QUIESCENCE_STATE.current], 4096
    jne .fail_21


    ; =======================================================================
    ; CASE 18 — ABI / DF qualification
    ; =======================================================================

    mov edi, 7
    lea rsi, [rel q_abi]

    call asm_quiescence_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22


    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std


    lea rdi, [rel q_abi]
    mov esi, 10
    mov edx, 1
    mov ecx, 1
    mov r8d, 1
    xor r9d, r9d

    call asm_quiescence_observe

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22


    cmp rbx, 0x11111111
    jne .fail_22

    cmp rbp, 0x22222222
    jne .fail_22

    cmp r12, 0x33333333
    jne .fail_22

    cmp r13, 0x44444444
    jne .fail_22

    mov rax, 0x55555555
    cmp r14, rax
    jne .fail_22

    mov rax, 0x66666666
    cmp r15, rax
    jne .fail_22


    pushfq
    pop rax

    test rax, 1 << 10
    jnz .fail_22


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
