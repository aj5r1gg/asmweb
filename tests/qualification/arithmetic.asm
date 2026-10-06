bits 64

%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"

global _start

extern asm_u64_add_checked
extern asm_u64_sub_checked
extern asm_u64_mul_checked
extern asm_u64_floor_div
extern asm_u64_ceil_div
extern asm_u64_exact_div
extern asm_linux_exit


section .text

_start:
    cld


    ; =======================================================================
    ; CHECKED ADDITION
    ; =======================================================================


    ; CASE 1 — 0 + 0 = 0
    xor edi, edi
    xor esi, esi
    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1

    test rdx, rdx
    jne .fail_1


    ; CASE 2 — ordinary addition
    mov edi, 123
    mov esi, 456
    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    cmp rdx, 579
    jne .fail_2


    ; CASE 3 — UINT64_MAX + 0 succeeds
    mov rdi, ASMWEB_U64_MAX
    xor esi, esi
    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_3


    ; CASE 4 — UINT64_MAX + 1 rejects overflow
    mov rdi, ASMWEB_U64_MAX
    mov esi, 1
    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4

    test rdx, rdx
    jne .fail_4


    ; CASE 5 — high-bound addition succeeds exactly
    mov rdi, 0xFFFFFFFFFFFFFFFE
    mov esi, 1
    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_5


    ; =======================================================================
    ; CHECKED SUBTRACTION
    ; =======================================================================


    ; CASE 6 — 0 - 0 = 0
    xor edi, edi
    xor esi, esi
    call asm_u64_sub_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6

    test rdx, rdx
    jne .fail_6


    ; CASE 7 — ordinary subtraction
    mov edi, 1000
    mov esi, 999
    call asm_u64_sub_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7

    cmp rdx, 1
    jne .fail_7


    ; CASE 8 — equal operands produce zero
    mov edi, 77
    mov esi, 77
    call asm_u64_sub_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8

    test rdx, rdx
    jne .fail_8


    ; CASE 9 — 0 - 1 rejects underflow
    xor edi, edi
    mov esi, 1
    call asm_u64_sub_checked

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9

    test rdx, rdx
    jne .fail_9


    ; CASE 10 — UINT64_MAX - UINT64_MAX = 0
    mov rdi, ASMWEB_U64_MAX
    mov rsi, ASMWEB_U64_MAX
    call asm_u64_sub_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_10

    test rdx, rdx
    jne .fail_10


    ; =======================================================================
    ; CHECKED MULTIPLICATION
    ; =======================================================================


    ; CASE 11 — 0 * UINT64_MAX = 0
    xor edi, edi
    mov rsi, ASMWEB_U64_MAX
    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_11

    test rdx, rdx
    jne .fail_11


    ; CASE 12 — 1 * UINT64_MAX = UINT64_MAX
    mov edi, 1
    mov rsi, ASMWEB_U64_MAX
    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_12


    ; CASE 13 — ordinary multiplication
    mov edi, 4096
    mov esi, 1024
    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_13

    cmp rdx, 4194304
    jne .fail_13


    ; CASE 14 — exact maximum product succeeds
    mov rdi, 0xFFFFFFFF
    mov rsi, 0x100000001
    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_14

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_14


    ; CASE 15 — 2 * 2^63 rejects overflow
    mov edi, 2
    mov rsi, 0x8000000000000000
    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15

    test rdx, rdx
    jne .fail_15


    ; CASE 16 — UINT64_MAX * UINT64_MAX rejects overflow
    mov rdi, ASMWEB_U64_MAX
    mov rsi, ASMWEB_U64_MAX
    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16

    test rdx, rdx
    jne .fail_16


    ; =======================================================================
    ; FLOOR DIVISION
    ; =======================================================================


    ; CASE 17 — floor_div(0,1) = 0
    xor edi, edi
    mov esi, 1
    call asm_u64_floor_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17

    test rdx, rdx
    jne .fail_17


    ; CASE 18 — floor_div(10,3) = 3
    mov edi, 10
    mov esi, 3
    call asm_u64_floor_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18

    cmp rdx, 3
    jne .fail_18


    ; CASE 19 — floor_div(UINT64_MAX,1) = UINT64_MAX
    mov rdi, ASMWEB_U64_MAX
    mov esi, 1
    call asm_u64_floor_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_19


    ; CASE 20 — floor division by zero rejected
    mov edi, 10
    xor esi, esi
    call asm_u64_floor_div

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20

    test rdx, rdx
    jne .fail_20


    ; =======================================================================
    ; CEILING DIVISION
    ; =======================================================================


    ; CASE 21 — ceil_div(0,1) = 0
    xor edi, edi
    mov esi, 1
    call asm_u64_ceil_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21

    test rdx, rdx
    jne .fail_21


    ; CASE 22 — ceil_div(9,3) = 3
    mov edi, 9
    mov esi, 3
    call asm_u64_ceil_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22

    cmp rdx, 3
    jne .fail_22


    ; CASE 23 — ceil_div(10,3) = 4
    mov edi, 10
    mov esi, 3
    call asm_u64_ceil_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_23

    cmp rdx, 4
    jne .fail_23


    ; CASE 24 — ceil_div(UINT64_MAX,2) = 2^63
    mov rdi, ASMWEB_U64_MAX
    mov esi, 2
    call asm_u64_ceil_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_24

    mov rcx, 0x8000000000000000
    cmp rdx, rcx
    jne .fail_24


    ; CASE 25 — ceil_div(UINT64_MAX,UINT64_MAX) = 1
    mov rdi, ASMWEB_U64_MAX
    mov rsi, ASMWEB_U64_MAX
    call asm_u64_ceil_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_25

    cmp rdx, 1
    jne .fail_25


    ; CASE 26 — ceiling division by zero rejected
    mov edi, 10
    xor esi, esi
    call asm_u64_ceil_div

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_26

    test rdx, rdx
    jne .fail_26


    ; =======================================================================
    ; EXACT DIVISION
    ; =======================================================================


    ; CASE 27 — exact_div(0,1) = 0
    xor edi, edi
    mov esi, 1
    call asm_u64_exact_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_27

    test rdx, rdx
    jne .fail_27


    ; CASE 28 — exact_div(12,3) = 4
    mov edi, 12
    mov esi, 3
    call asm_u64_exact_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_28

    cmp rdx, 4
    jne .fail_28


    ; CASE 29 — exact_div(10,3) rejected
    mov edi, 10
    mov esi, 3
    call asm_u64_exact_div

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_29

    test rdx, rdx
    jne .fail_29


    ; CASE 30 — exact division by zero rejected
    mov edi, 10
    xor esi, esi
    call asm_u64_exact_div

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_30

    test rdx, rdx
    jne .fail_30


    ; CASE 31 — exact_div(UINT64_MAX,UINT64_MAX) = 1
    mov rdi, ASMWEB_U64_MAX
    mov rsi, ASMWEB_U64_MAX
    call asm_u64_exact_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_31

    cmp rdx, 1
    jne .fail_31


    ; =======================================================================
    ; ABI / FAILURE DETERMINISM
    ; =======================================================================


    ; CASE 32 — all public arithmetic primitives preserve Internal ABI state
    ;
    ; Keep one sentinel set live across every public arithmetic routine. Any
    ; callee-saved register corruption by any routine is therefore detected.
    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    ; checked addition
    mov edi, 123
    mov esi, 456
    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_32

    cmp rdx, 579
    jne .fail_32

    ; checked subtraction
    mov edi, 1000
    mov esi, 1
    call asm_u64_sub_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_32

    cmp rdx, 999
    jne .fail_32

    ; checked multiplication
    mov edi, 64
    mov esi, 64
    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_32

    cmp rdx, 4096
    jne .fail_32

    ; floor division
    mov edi, 10
    mov esi, 3
    call asm_u64_floor_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_32

    cmp rdx, 3
    jne .fail_32

    ; ceiling division
    mov edi, 10
    mov esi, 3
    call asm_u64_ceil_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_32

    cmp rdx, 4
    jne .fail_32

    ; exact division
    mov edi, 12
    mov esi, 3
    call asm_u64_exact_div

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_32

    cmp rdx, 4
    jne .fail_32

    ; Internal ABI callee-saved register contract.
    cmp rbx, 0x11111111
    jne .fail_32

    cmp rbp, 0x22222222
    jne .fail_32

    cmp r12, 0x33333333
    jne .fail_32

    cmp r13, 0x44444444
    jne .fail_32

    cmp r14, 0x55555555
    jne .fail_32

    cmp r15, 0x66666666
    jne .fail_32

    ; Ordinary arithmetic calls must return with DF clear.
    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_32


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
