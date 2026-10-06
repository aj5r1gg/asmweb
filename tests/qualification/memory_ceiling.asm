bits 64

%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/registry.inc"
%include "asmweb/memory_ceiling.inc"

global _start

extern asm_memory_fixed_class_capacity
extern asm_memory_direct_capacity_sum
extern asm_memory_direct_capacity_from_mot
extern asm_linux_exit


section .rodata

align 8

sum_one:
    dq 1234

sum_three:
    dq 100
    dq 200
    dq 300

sum_with_zero:
    dq 100
    dq 0
    dq 200

sum_exact_max:
    dq 0xFFFFFFFFFFFFFFFD
    dq 1
    dq 1

sum_overflow:
    dq 0xFFFFFFFFFFFFFFFF
    dq 1

sum_late_overflow:
    dq 100
    dq 200
    dq 0xFFFFFFFFFFFFFED4





; ===========================================================================
; MOT-derived capacity fixtures
; ===========================================================================

align 8

; One ACTIVE class:
;
;   64 * 10 + 32 + 4096 = 4768
mot_one_active:
    dq 0x5001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x6001
    dq 64
    dq 64
    dq 32
    dq 4096
    dq 10
    dq 10
    dq 10
    dq 0


; Three entries:
;
;   ACTIVE   = 64 * 10 + 32 + 4096 = 4768
;   DEFERRED = ignored
;   ACTIVE   = 128 * 2 + 16 + 4096 = 4368
;
; total = 9136
mot_mixed:
    dq 0x5101
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x6101
    dq 64
    dq 64
    dq 32
    dq 4096
    dq 10
    dq 10
    dq 10
    dq 0

    dq 0x5102
    dq ASMWEB_REGISTRY_STATUS_DEFERRED
    dq 0x6102
    dq 1
    dq 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF
    dq 0
    dq 0
    dq 0

    dq 0x5103
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x6103
    dq 128
    dq 128
    dq 16
    dq 4096
    dq 2
    dq 2
    dq 2
    dq 0


; Valid lifecycle state but no ACTIVE entries.
mot_all_inactive:
    dq 0x5201
    dq ASMWEB_REGISTRY_STATUS_DEFERRED
    dq 0x6201
    dq 1
    dq 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF
    dq 0
    dq 0
    dq 0


; Exact aggregate UINT64_MAX.
mot_exact_max:
    dq 0x5301
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x6301
    dq 1
    dq 0xFFFFFFFFFFFFFFFF
    dq 0
    dq 0
    dq 1
    dq 1
    dq 1
    dq 0


; Per-class multiplication overflow:
;
;   2 * 2^63 = 2^64
mot_class_overflow:
    dq 0x5401
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x6401
    dq 2
    dq 2
    dq 0
    dq 0
    dq 0x8000000000000000
    dq 1
    dq 1
    dq 0


; Aggregate overflow:
;
;   first class  = UINT64_MAX
;   second class = 1
mot_aggregate_overflow:
    dq 0x5501
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x6501
    dq 1
    dq 0xFFFFFFFFFFFFFFFF
    dq 0
    dq 0
    dq 1
    dq 1
    dq 1
    dq 0

    dq 0x5502
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x6502
    dq 1
    dq 1
    dq 0
    dq 0
    dq 1
    dq 1
    dq 1
    dq 0


; Invalid lifecycle representation.
mot_invalid_status:
    dq 0x5601
    dq 0
    dq 0x6601
    dq 1
    dq 1
    dq 0
    dq 0
    dq 1
    dq 1
    dq 1
    dq 0


section .text

_start:
    cld


    ; =======================================================================
    ; FIXED-CLASS CONTRIBUTION
    ; =======================================================================


    ; CASE 1 — all-zero resolved quantities produce zero
    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1

    test rdx, rdx
    jne .fail_1


    ; CASE 2 — ordinary fixed-stride class calculation
    ;
    ; 64 * 10 + 32 + 4096 = 4768
    mov edi, 64
    mov esi, 10
    mov edx, 32
    mov ecx, 4096

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    cmp rdx, 4768
    jne .fail_2


    ; CASE 3 — zero count retains metadata and mapping overhead
    ;
    ; 128 * 0 + 256 + 4096 = 4352
    mov edi, 128
    xor esi, esi
    mov edx, 256
    mov ecx, 4096

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3

    cmp rdx, 4352
    jne .fail_3


    ; CASE 4 — exact UINT64_MAX payload succeeds
    mov rdi, ASMWEB_U64_MAX
    mov esi, 1
    xor edx, edx
    xor ecx, ecx

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_4


    ; CASE 5 — multiplication overflow rejected
    mov edi, 2
    mov rsi, 0x8000000000000000
    xor edx, edx
    xor ecx, ecx

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5

    test rdx, rdx
    jne .fail_5


    ; CASE 6 — metadata addition overflow rejected
    mov rdi, ASMWEB_U64_MAX
    mov esi, 1
    mov edx, 1
    xor ecx, ecx

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_6

    test rdx, rdx
    jne .fail_6


    ; CASE 7 — mapping-overhead addition overflow rejected
    mov rdi, 0xFFFFFFFFFFFFFFFD
    mov esi, 1
    mov edx, 1
    mov ecx, 2

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_7

    test rdx, rdx
    jne .fail_7


    ; CASE 8 — exact final UINT64_MAX succeeds
    mov rdi, 0xFFFFFFFFFFFFFFFD
    mov esi, 1
    mov edx, 1
    mov ecx, 1

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_8


    ; CASE 9 — large legitimate multiplication
    ;
    ; 4096 * 1048576 + 65536 + 4096 = 4295036928
    mov edi, 4096
    mov esi, 1048576
    mov edx, 65536
    mov ecx, 4096

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_9

    mov rax, 4295036928
    cmp rdx, rax
    jne .fail_9


    ; CASE 10 — fixed-class failure result is deterministically zero
    mov rdi, ASMWEB_U64_MAX
    mov rsi, ASMWEB_U64_MAX
    mov rdx, ASMWEB_U64_MAX
    mov rcx, ASMWEB_U64_MAX

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10

    test rdx, rdx
    jne .fail_10


    ; =======================================================================
    ; DIRECT CAPACITY ACCUMULATION
    ; =======================================================================


    ; CASE 11 — canonical empty vector succeeds with zero
    xor edi, edi
    xor esi, esi

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_11

    test rdx, rdx
    jne .fail_11


    ; CASE 12 — non-NULL + zero count rejected as non-canonical
    lea rdi, [rel sum_one]
    xor esi, esi

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12

    test rdx, rdx
    jne .fail_12


    ; CASE 13 — NULL + non-zero count rejected
    xor edi, edi
    mov esi, 1

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13

    test rdx, rdx
    jne .fail_13


    ; CASE 14 — one contribution
    lea rdi, [rel sum_one]
    mov esi, 1

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_14

    cmp rdx, 1234
    jne .fail_14


    ; CASE 15 — ordinary three-class accumulation
    lea rdi, [rel sum_three]
    mov esi, 3

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_15

    cmp rdx, 600
    jne .fail_15


    ; CASE 16 — zero-valued contribution is a valid resolved value
    lea rdi, [rel sum_with_zero]
    mov esi, 3

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_16

    cmp rdx, 300
    jne .fail_16


    ; CASE 17 — exact aggregate UINT64_MAX succeeds
    lea rdi, [rel sum_exact_max]
    mov esi, 3

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_17


    ; CASE 18 — immediate aggregate overflow rejected
    lea rdi, [rel sum_overflow]
    mov esi, 2

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_18

    test rdx, rdx
    jne .fail_18


    ; CASE 19 — late aggregate overflow rejected
    ;
    ; 100 + 200 = 300.
    ; Third contribution = UINT64_MAX - 299.
    ; Final addition therefore exceeds UINT64_MAX by exactly 1.
    lea rdi, [rel sum_late_overflow]
    mov esi, 3

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_19

    test rdx, rdx
    jne .fail_19


    ; CASE 20 — count above M0 MOT safety bound rejected before traversal
    lea rdi, [rel sum_one]
    mov esi, ASMWEB_M0_MAX_MOT_ENTRIES + 1

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20

    test rdx, rdx
    jne .fail_20


    ; =======================================================================
    ; ABI
    ; =======================================================================


    ; CASE 21 — both public memory-ceiling routines preserve Internal ABI state
    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    mov edi, 64
    mov esi, 10
    mov edx, 32
    mov ecx, 4096

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21

    cmp rdx, 4768
    jne .fail_21

    lea rdi, [rel sum_three]
    mov esi, 3

    call asm_memory_direct_capacity_sum

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21

    cmp rdx, 600
    jne .fail_21

    cmp rbx, 0x11111111
    jne .fail_21

    cmp rbp, 0x22222222
    jne .fail_21

    cmp r12, 0x33333333
    jne .fail_21

    cmp r13, 0x44444444
    jne .fail_21

    cmp r14, 0x55555555
    jne .fail_21

    cmp r15, 0x66666666
    jne .fail_21

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_21


    ; =======================================================================
    ; MOT-DERIVED DIRECT CAPACITY
    ; =======================================================================


    ; CASE 22 — canonical empty MOT produces zero
    xor edi, edi
    xor esi, esi

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22

    test rdx, rdx
    jne .fail_22


    ; CASE 23 — non-NULL + zero count rejected
    lea rdi, [rel mot_one_active]
    xor esi, esi

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_23

    test rdx, rdx
    jne .fail_23


    ; CASE 24 — NULL + non-zero count rejected
    xor edi, edi
    mov esi, 1

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_24

    test rdx, rdx
    jne .fail_24


    ; CASE 25 — one ACTIVE MOT class derives correctly
    lea rdi, [rel mot_one_active]
    mov esi, 1

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_25

    cmp rdx, 4768
    jne .fail_25


    ; CASE 26 — only ACTIVE entries contribute
    lea rdi, [rel mot_mixed]
    mov esi, 3

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_26

    cmp rdx, 9136
    jne .fail_26


    ; CASE 27 — valid all-inactive MOT produces zero
    lea rdi, [rel mot_all_inactive]
    mov esi, 1

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_27

    test rdx, rdx
    jne .fail_27


    ; CASE 28 — exact UINT64_MAX aggregate succeeds
    lea rdi, [rel mot_exact_max]
    mov esi, 1

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_28

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_28


    ; CASE 29 — per-class arithmetic overflow rejected
    lea rdi, [rel mot_class_overflow]
    mov esi, 1

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_29

    test rdx, rdx
    jne .fail_29


    ; CASE 30 — aggregate overflow across ACTIVE classes rejected
    lea rdi, [rel mot_aggregate_overflow]
    mov esi, 2

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_30

    test rdx, rdx
    jne .fail_30


    ; CASE 31 — MOT count above M0 bound rejected before traversal
    lea rdi, [rel mot_one_active]
    mov esi, ASMWEB_M0_MAX_MOT_ENTRIES + 1

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_31

    test rdx, rdx
    jne .fail_31


    ; CASE 32 — invalid lifecycle representation rejected
    lea rdi, [rel mot_invalid_status]
    mov esi, 1

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_32

    test rdx, rdx
    jne .fail_32


    ; CASE 33 — MOT-derived routine preserves Internal ABI state
    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    lea rdi, [rel mot_mixed]
    mov esi, 3

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_33

    cmp rdx, 9136
    jne .fail_33

    cmp rbx, 0x11111111
    jne .fail_33

    cmp rbp, 0x22222222
    jne .fail_33

    cmp r12, 0x33333333
    jne .fail_33

    cmp r13, 0x44444444
    jne .fail_33

    cmp r14, 0x55555555
    jne .fail_33

    cmp r15, 0x66666666
    jne .fail_33

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_33


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
