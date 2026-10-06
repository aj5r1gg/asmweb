bits 64

%include "asmweb/resource.inc"

%include "asmweb/startup.inc"
%include "asmweb/entropy.inc"
%include "asmweb/cpu.inc"
%include "asmweb/time.inc"
%include "asmweb/process_runtime.inc"
%include "asmweb/startup_memory.inc"
%include "asmweb/registry.inc"
%include "asmweb/production_registry.inc"

global _start


extern asm_production_registry_init
extern asm_production_registry_get
extern asm_registry_validate
extern asm_memory_direct_capacity_from_mot
extern asm_linux_exit


; Expected direct fixed production bytes represented by the current canonical
; production MOT. This is independently expressed from the actual structure
; sizes used by the registry materialiser.

ASMWEB_EXPECTED_PRODUCTION_DIRECT_BYTES equ \
    ASMWEB_STARTUP_INFO_size + \
    ASMWEB_ENTROPY_BOOTSTRAP_size + \
    ASMWEB_CPU_INFO_size + \
    ASMWEB_MONOTONIC_TIME_size + \
    ASMWEB_PROCESS_RUNTIME_size + \
    ASMWEB_STARTUP_MEMORY_ACCOUNT_size + \
    ASMWEB_PRODUCTION_RUNTIME_RULE_STORAGE_BYTES + \
    ASMWEB_PRODUCTION_REGISTRY_STORAGE_BYTES


section .text

_start:
    cld


    ; =======================================================================
    ; CASE 1 — registry is unavailable before publication
    ; =======================================================================

    call asm_production_registry_get

    test rax, rax
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — canonical production registry initialises
    ; =======================================================================

    call asm_production_registry_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — published registry becomes retrievable
    ; =======================================================================

    call asm_production_registry_get

    test rax, rax
    jz .fail_3

    mov rbx, rax


    ; =======================================================================
    ; CASE 4 — production OLR count is exact
    ; =======================================================================

    cmp qword [rbx + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], ASMWEB_PRODUCTION_OLR_COUNT
    jne .fail_4

    cmp qword [rbx + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], 0
    je .fail_4


    ; =======================================================================
    ; CASE 5 — production MOT count is exact
    ; =======================================================================

    cmp qword [rbx + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], ASMWEB_PRODUCTION_MOT_COUNT
    jne .fail_5

    cmp qword [rbx + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], 0
    je .fail_5


    ; =======================================================================
    ; CASE 6 — current production RCT is canonical empty
    ; =======================================================================

    cmp qword [rbx + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 0
    jne .fail_6

    cmp qword [rbx + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], 0
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — canonical production set independently validates
    ; =======================================================================

    mov rdi, rbx
    call asm_registry_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7


    ; =======================================================================
    ; CASE 8 — canonical production MOT derives the expected fixed ceiling
    ; =======================================================================

    mov rdi, [rbx + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr]

    mov rsi, [rbx + ASMWEB_REGISTRY_VALIDATION_SET.mot_count]

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8

    mov rax, ASMWEB_EXPECTED_PRODUCTION_DIRECT_BYTES
    cmp rdx, rax
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — reinitialisation after publication is rejected
    ; =======================================================================

    call asm_production_registry_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9

    call asm_production_registry_get

    test rax, rax
    jz .fail_9


    ; =======================================================================
    ; CASE 10 — getter preserves Internal ABI callee-saved state and DF
    ; =======================================================================

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    call asm_production_registry_get

    test rax, rax
    jz .fail_10

    cmp rbx, 0x11111111
    jne .fail_10

    cmp rbp, 0x22222222
    jne .fail_10

    cmp r12, 0x33333333
    jne .fail_10

    cmp r13, 0x44444444
    jne .fail_10

    cmp r14, 0x55555555
    jne .fail_10

    cmp r15, 0x66666666
    jne .fail_10

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_10


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
