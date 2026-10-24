bits 64

%include "asmweb/resource.inc"
%include "asmweb/pool.inc"

global _start

extern asm_typed_pool_init
extern asm_typed_pool_validate
extern asm_typed_pool_acquire
extern asm_typed_pool_release
extern asm_typed_pool_quiescent
extern asm_linux_exit


section .bss

align 64
backing:
    resb 256

slot_state:
    resb 8

align 8
request:
    resb ASMWEB_TYPED_POOL_REQUEST_size

pool:
    resb ASMWEB_TYPED_POOL_size

bad_pool_1:
    resb ASMWEB_TYPED_POOL_size

bad_pool_2:
    resb ASMWEB_TYPED_POOL_size

bad_pool_3:
    resb ASMWEB_TYPED_POOL_size

bad_pool_4:
    resb ASMWEB_TYPED_POOL_size

bad_pool_5:
    resb ASMWEB_TYPED_POOL_size


section .text

; ===========================================================================
; M0 typed-pool qualification
;
; Main fixture:
;
;   actual object size     = 24
;   effective stride       = 32
;   alignment              = 16
;   physical capacity      = 4
;   configured capacity    = 3
;   protected reserve      = 1
;   ordinary capacity      = 2
;
; Thus:
;
;   payload bytes          = 128
;   slot metadata bytes    = 4
;   ordinary acquisition may own at most two slots
;
; Exit:
;
;   0  PASS
;   1  valid init failed
;   2  descriptor/accounting invalid after init
;   3  first acquisition failed
;   4  second acquisition failed
;   5  acquisition pointers/occupancy invalid
;   6  protected reserve was borrowed
;   7  quiescence incorrectly reported while occupied
;   8  interior release accepted
;   9  valid release failed
;   10 double release accepted
;   11 reacquisition failed
;   12 final release/quiescence failed
;   13 stride smaller than actual accepted
;   14 invalid alignment accepted
;   15 configured > physical accepted
;   16 reserve > configured accepted
;   17 insufficient backing accepted
;   18 insufficient slot metadata accepted
;   19 dirty slot metadata accepted
;   20 non-pristine destination accepted/destructively overwritten
;   21 NULL API semantics failed
;   22 validator failed to detect corruption
;   23 ABI/DF preservation failed
;   24 invalid ownership scope mutated destination
;   25 invalid partitioning model mutated destination
;   26–36 corrupted accounting, authority, and slot-state accepted
; ===========================================================================

_start:
    cld


    ; -----------------------------------------------------------------------
    ; Build canonical valid request.
    ; -----------------------------------------------------------------------

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.object_class_id], \
        0x30000001

    lea rax, [rel backing]
    mov [rel request + ASMWEB_TYPED_POOL_REQUEST.backing_base], rax
    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 256

    lea rax, [rel slot_state]
    mov [rel request + ASMWEB_TYPED_POOL_REQUEST.slot_state_base], rax
    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 8

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 24
    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 32
    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.physical_capacity], 4
    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 3
    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 1

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], \
        0x40000001

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], \
        ASMWEB_POOL_PARTITION_GLOBAL


    ; =======================================================================
    ; CASE 1 — valid initialisation
    ; =======================================================================

    lea rdi, [rel request]
    lea rsi, [rel pool]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1

    lea rdi, [rel pool]

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    ; Exact derived accounting.

    cmp qword [rel pool + ASMWEB_TYPED_POOL.payload_bytes], 128
    jne .fail_2

    cmp qword [rel pool + ASMWEB_TYPED_POOL.slot_metadata_bytes], 4
    jne .fail_2

    cmp qword [rel pool + ASMWEB_TYPED_POOL.management_bytes_total], \
        ASMWEB_TYPED_POOL_size + 4
    jne .fail_2

    cmp qword [rel pool + ASMWEB_TYPED_POOL.physical_capacity], 4
    jne .fail_2

    cmp qword [rel pool + ASMWEB_TYPED_POOL.configured_capacity], 3
    jne .fail_2

    cmp qword [rel pool + ASMWEB_TYPED_POOL.reserved_capacity], 1
    jne .fail_2

    cmp qword [rel pool + ASMWEB_TYPED_POOL.ordinary_capacity], 2
    jne .fail_2

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_2

    cmp qword [rel pool + ASMWEB_TYPED_POOL.high_water], 0
    jne .fail_2


    ; =======================================================================
    ; CASE 2 — first ordinary acquisition
    ; =======================================================================

    lea rdi, [rel pool]

    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3

    lea rcx, [rel backing]

    cmp rdx, rcx
    jne .fail_5

    mov r12, rdx


    ; =======================================================================
    ; CASE 3 — second ordinary acquisition
    ; =======================================================================

    lea rdi, [rel pool]

    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4

    lea rcx, [rel backing + 32]

    cmp rdx, rcx
    jne .fail_5

    mov r13, rdx


    ; Occupancy/high-water/history.

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 2
    jne .fail_5

    cmp qword [rel pool + ASMWEB_TYPED_POOL.high_water], 2
    jne .fail_5

    cmp qword [rel pool + ASMWEB_TYPED_POOL.acquisition_count], 2
    jne .fail_5

    cmp byte [rel slot_state + 0], ASMWEB_POOL_SLOT_OWNED
    jne .fail_5

    cmp byte [rel slot_state + 1], ASMWEB_POOL_SLOT_OWNED
    jne .fail_5

    ; Reserve and unconfigured physical slot remain FREE.

    cmp byte [rel slot_state + 2], ASMWEB_POOL_SLOT_FREE
    jne .fail_6

    cmp byte [rel slot_state + 3], ASMWEB_POOL_SLOT_FREE
    jne .fail_6


    ; =======================================================================
    ; CASE 4 — ordinary acquisition cannot borrow protected reserve
    ; =======================================================================

    lea rdi, [rel pool]

    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_6

    test rdx, rdx
    jne .fail_6

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 2
    jne .fail_6

    cmp qword [rel pool + ASMWEB_TYPED_POOL.rejection_count], 1
    jne .fail_6

    cmp byte [rel slot_state + 2], ASMWEB_POOL_SLOT_FREE
    jne .fail_6


    ; =======================================================================
    ; CASE 5 — occupied pool is not quiescent
    ; =======================================================================

    lea rdi, [rel pool]

    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_7


    ; =======================================================================
    ; CASE 6 — interior pointer release rejected
    ; =======================================================================

    lea rdi, [rel pool]
    lea rsi, [r12 + 1]

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_8

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 2
    jne .fail_8


    ; =======================================================================
    ; CASE 7 — valid release
    ; =======================================================================

    lea rdi, [rel pool]
    mov rsi, r12

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_9

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 1
    jne .fail_9

    cmp qword [rel pool + ASMWEB_TYPED_POOL.release_count], 1
    jne .fail_9

    cmp byte [rel slot_state + 0], ASMWEB_POOL_SLOT_FREE
    jne .fail_9


    ; =======================================================================
    ; CASE 8 — double release rejected
    ; =======================================================================

    lea rdi, [rel pool]
    mov rsi, r12

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10


    ; =======================================================================
    ; CASE 9 — released slot can be reacquired
    ; =======================================================================

    lea rdi, [rel pool]

    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_11

    cmp rdx, r12
    jne .fail_11

    mov r14, rdx

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 2
    jne .fail_11

    cmp qword [rel pool + ASMWEB_TYPED_POOL.acquisition_count], 3
    jne .fail_11

    ; Historical high-water remains the ordinary-capacity boundary.
    cmp qword [rel pool + ASMWEB_TYPED_POOL.high_water], 2
    jne .fail_11


    ; =======================================================================
    ; CASE 10 — release all and return to quiescence
    ; =======================================================================

    lea rdi, [rel pool]
    mov rsi, r13

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    lea rdi, [rel pool]
    mov rsi, r14

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    cmp qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 0
    jne .fail_12

    cmp qword [rel pool + ASMWEB_TYPED_POOL.acquisition_count], 3
    jne .fail_12

    cmp qword [rel pool + ASMWEB_TYPED_POOL.release_count], 3
    jne .fail_12

    cmp qword [rel pool + ASMWEB_TYPED_POOL.high_water], 2
    jne .fail_12

    lea rdi, [rel pool]

    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    lea rdi, [rel pool]

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12


    ; =======================================================================
    ; CASE 11 — stride smaller than actual object rejected
    ; =======================================================================

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 40
    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.effective_stride], 32

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_1]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.actual_size], 24


    ; =======================================================================
    ; CASE 12 — non-power-of-two alignment rejected
    ; =======================================================================

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.alignment], 24

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_1]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.alignment], 16


    ; =======================================================================
    ; CASE 13 — configured capacity cannot exceed physical capacity
    ; =======================================================================

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 5

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_1]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.configured_capacity], 3


    ; =======================================================================
    ; CASE 14 — reserve cannot exceed configured capacity
    ; =======================================================================

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 4

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_1]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.reserved_capacity], 1


    ; =======================================================================
    ; CASE 15 — insufficient backing storage rejected
    ; =======================================================================

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 127

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_1]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.backing_bytes], 256


    ; =======================================================================
    ; CASE 16 — insufficient slot-state storage rejected
    ; =======================================================================

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 3

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_1]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_18

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.slot_state_bytes], 8


    ; =======================================================================
    ; CASE 17 — dirty initial slot metadata rejected
    ; =======================================================================

    mov byte [rel slot_state + 3], ASMWEB_POOL_SLOT_OWNED

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_1]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_19

    mov byte [rel slot_state + 3], ASMWEB_POOL_SLOT_FREE


    ; =======================================================================
    ; CASE 18 — destination must be pristine and rejection is non-destructive
    ; =======================================================================

    mov eax, 0xdeadbeef
    mov [rel bad_pool_2 + ASMWEB_TYPED_POOL.object_class_id], rax

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_2]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20

    mov eax, 0xdeadbeef
    cmp [rel bad_pool_2 + ASMWEB_TYPED_POOL.object_class_id], rax
    jne .fail_20


    ; =======================================================================
    ; CASE 19 — NULL API semantics
    ; =======================================================================

    xor edi, edi
    lea rsi, [rel bad_pool_3]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21

    xor edi, edi

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21

    xor edi, edi

    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21

    test rdx, rdx
    jne .fail_21

    xor edi, edi
    lea rsi, [rel backing]

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21

    xor edi, edi

    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21


    ; =======================================================================
    ; CASE 20 — validator detects accounting corruption
    ; =======================================================================

    ; Copying the descriptor is unnecessary: corrupt one field temporarily,
    ; validate rejection, then restore it.

    mov qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 1

    lea rdi, [rel pool]

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_22

    mov qword [rel pool + ASMWEB_TYPED_POOL.current_occupancy], 0

    lea rdi, [rel pool]

    call asm_typed_pool_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22


    ; =======================================================================
    ; CASE 20A — corrupt accounting and authority must be rejected.
    ;
    ; Each mutation is applied to a quiescent, valid pool, checked through
    ; the production validator, restored, and checked again. No invalid
    ; descriptor reaches acquire/release or escapes this test.
    ; =======================================================================

    ; Mutation 26: release count greater than acquisition count.
    mov qword [rel pool + ASMWEB_TYPED_POOL.release_count], 4
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_26
    mov qword [rel pool + ASMWEB_TYPED_POOL.release_count], 3
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_26

    ; Mutation 27: high-water above ordinary capacity.
    mov qword [rel pool + ASMWEB_TYPED_POOL.high_water], 3
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_27
    mov qword [rel pool + ASMWEB_TYPED_POOL.high_water], 2
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_27

    ; Mutation 28: historical acquisition mismatch.
    mov qword [rel pool + ASMWEB_TYPED_POOL.acquisition_count], 4
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_28
    mov qword [rel pool + ASMWEB_TYPED_POOL.acquisition_count], 3
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_28

    ; Mutation 29: reserved capacity greater than configured.
    mov qword [rel pool + ASMWEB_TYPED_POOL.reserved_capacity], 4
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_29
    mov qword [rel pool + ASMWEB_TYPED_POOL.reserved_capacity], 1
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_29

    ; Mutation 30: ordinary capacity contradicts configured minus reserve.
    mov qword [rel pool + ASMWEB_TYPED_POOL.ordinary_capacity], 3
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_30
    mov qword [rel pool + ASMWEB_TYPED_POOL.ordinary_capacity], 2
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_30

    ; Mutation 31: zero object-class identity.
    mov qword [rel pool + ASMWEB_TYPED_POOL.object_class_id], 0
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_31
    mov qword [rel pool + ASMWEB_TYPED_POOL.object_class_id], 0x30000001
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_31

    ; Mutation 32: zero ownership scope.
    mov qword [rel pool + ASMWEB_TYPED_POOL.ownership_scope], 0
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_32
    mov qword [rel pool + ASMWEB_TYPED_POOL.ownership_scope], 0x40000001
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_32

    ; Mutation 33: unsupported partitioning model.
    mov qword [rel pool + ASMWEB_TYPED_POOL.partitioning_model], 99
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_33
    mov qword [rel pool + ASMWEB_TYPED_POOL.partitioning_model], ASMWEB_POOL_PARTITION_GLOBAL
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_33

    ; Mutation 34: reserve slot must never become owned.
    mov byte [rel slot_state + 2], ASMWEB_POOL_SLOT_OWNED
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_34
    mov byte [rel slot_state + 2], ASMWEB_POOL_SLOT_FREE
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_34

    ; Mutation 35: unconfigured slot must never become owned.
    mov byte [rel slot_state + 3], ASMWEB_POOL_SLOT_OWNED
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_35
    mov byte [rel slot_state + 3], ASMWEB_POOL_SLOT_FREE
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_35

    ; Mutation 36: invalid slot-state value must be rejected.
    mov byte [rel slot_state + 0], 2
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_36
    mov byte [rel slot_state + 0], ASMWEB_POOL_SLOT_FREE
    lea rdi, [rel pool]
    call asm_typed_pool_validate
    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_36

    ; =======================================================================
    ; CASE 21 — acquire preserves Internal ABI callee-saved state and clears DF
    ; =======================================================================

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std

    lea rdi, [rel pool]

    call asm_typed_pool_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_23

    mov r10, rdx

    cmp rbx, 0x11111111
    jne .fail_23

    cmp rbp, 0x22222222
    jne .fail_23

    cmp r12, 0x33333333
    jne .fail_23

    cmp r13, 0x44444444
    jne .fail_23

    mov rax, 0x55555555
    cmp r14, rax
    jne .fail_23

    mov rax, 0x66666666
    cmp r15, rax
    jne .fail_23

    pushfq
    pop rax

    test rax, 1 << 10
    jnz .fail_23

    ; Restore final quiescence after ABI qualification.

    lea rdi, [rel pool]
    mov rsi, r10

    call asm_typed_pool_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_23

    lea rdi, [rel pool]

    call asm_typed_pool_quiescent

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_23


    ; =======================================================================
    ; CASE 22 — late ownership-scope rejection is failure-atomic
    ; =======================================================================

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope], 0

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_4]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_24

    lea rax, [rel bad_pool_4]
    xor ecx, ecx

.check_bad_pool_4_zero:
    cmp rcx, ASMWEB_TYPED_POOL_size / 8
    jae .bad_pool_4_zero

    cmp qword [rax + rcx * 8], 0
    jne .fail_24

    inc rcx
    jmp .check_bad_pool_4_zero


.bad_pool_4_zero:

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.ownership_scope],         0x40000001


    ; =======================================================================
    ; CASE 23 — late partitioning rejection is failure-atomic
    ; =======================================================================

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model], 99

    lea rdi, [rel request]
    lea rsi, [rel bad_pool_5]

    call asm_typed_pool_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_25

    lea rax, [rel bad_pool_5]
    xor ecx, ecx

.check_bad_pool_5_zero:
    cmp rcx, ASMWEB_TYPED_POOL_size / 8
    jae .bad_pool_5_zero

    cmp qword [rax + rcx * 8], 0
    jne .fail_25

    inc rcx
    jmp .check_bad_pool_5_zero


.bad_pool_5_zero:

    mov qword [rel request + ASMWEB_TYPED_POOL_REQUEST.partitioning_model],         ASMWEB_POOL_PARTITION_GLOBAL


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

.fail_34:
    mov edi, 34
    call asm_linux_exit
    ud2

.fail_35:
    mov edi, 35
    call asm_linux_exit
    ud2

.fail_36:
    mov edi, 36
    call asm_linux_exit
    ud2
