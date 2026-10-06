bits 64

%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/memory_ceiling.inc"

global _start

extern asm_memory_fixed_class_capacity
extern asm_linux_exit


section .text

_start:
    cld


    ; =======================================================================
    ; CASE 1 — all-zero resolved quantities produce zero
    ; =======================================================================

    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1

    test rdx, rdx
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — ordinary fixed-stride class calculation
    ;
    ; payload:
    ;   64 * 10 = 640
    ;
    ; class:
    ;   640 + 32 + 4096 = 4768
    ; =======================================================================

    mov edi, 64
    mov esi, 10
    mov edx, 32
    mov ecx, 4096

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    cmp rdx, 4768
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — zero count retains only metadata and mapping overhead
    ;
    ; 128 * 0 + 256 + 4096 = 4352
    ; =======================================================================

    mov edi, 128
    xor esi, esi
    mov edx, 256
    mov ecx, 4096

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3

    cmp rdx, 4352
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — exact UINT64_MAX payload succeeds
    ;
    ; UINT64_MAX * 1 + 0 + 0 = UINT64_MAX
    ; =======================================================================

    mov rdi, ASMWEB_U64_MAX
    mov esi, 1
    xor edx, edx
    xor ecx, ecx

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_4

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — multiplication overflow rejected
    ;
    ; 2 * 2^63 cannot fit in uint64.
    ; =======================================================================

    mov edi, 2
    mov rsi, 0x8000000000000000
    xor edx, edx
    xor ecx, ecx

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5

    test rdx, rdx
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — metadata addition overflow rejected
    ;
    ; UINT64_MAX * 1 + 1
    ; =======================================================================

    mov rdi, ASMWEB_U64_MAX
    mov esi, 1
    mov edx, 1
    xor ecx, ecx

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_6

    test rdx, rdx
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — mapping-overhead addition overflow rejected
    ;
    ; payload      = UINT64_MAX - 2
    ; metadata     = 1
    ; intermediate = UINT64_MAX - 1
    ; overhead     = 2
    ; final result would overflow.
    ; =======================================================================

    mov rdi, 0xFFFFFFFFFFFFFFFD
    mov esi, 1
    mov edx, 1
    mov ecx, 2

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_7

    test rdx, rdx
    jne .fail_7


    ; =======================================================================
    ; CASE 8 — exact final UINT64_MAX succeeds
    ;
    ; payload      = UINT64_MAX - 2
    ; metadata     = 1
    ; overhead     = 1
    ; final        = UINT64_MAX
    ; =======================================================================

    mov rdi, 0xFFFFFFFFFFFFFFFD
    mov esi, 1
    mov edx, 1
    mov ecx, 1

    call asm_memory_fixed_class_capacity

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — large legitimate multiplication
    ;
    ; 4096 * 1048576 = 4294967296
    ; + 65536
    ; + 4096
    ; = 4295036928
    ; =======================================================================

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


    ; =======================================================================
    ; CASE 10 — caller-visible failure result is deterministically zero
    ; =======================================================================

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
    ; CASE 11 — Internal ABI callee-saved registers and DF preserved
    ; =======================================================================

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
    jne .fail_11

    cmp rdx, 4768
    jne .fail_11

    cmp rbx, 0x11111111
    jne .fail_11

    cmp rbp, 0x22222222
    jne .fail_11

    cmp r12, 0x33333333
    jne .fail_11

    cmp r13, 0x44444444
    jne .fail_11

    cmp r14, 0x55555555
    jne .fail_11

    cmp r15, 0x66666666
    jne .fail_11

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_11


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
