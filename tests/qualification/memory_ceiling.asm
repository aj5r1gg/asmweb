bits 64

%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/registry.inc"
%include "asmweb/memory_ceiling.inc"

global _start

extern asm_memory_fixed_class_capacity
extern asm_memory_direct_capacity_sum
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
