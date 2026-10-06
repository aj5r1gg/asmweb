bits 64

%include "asmweb/resource.inc"
%include "asmweb/process_runtime.inc"

global _start

extern asm_process_runtime_init
extern asm_process_runtime_validate
extern asm_linux_exit


section .bss

align 8

runtime_a:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_b:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_c:
    resb ASMWEB_PROCESS_RUNTIME_size


section .text

_start:
    cld


    ; =======================================================================
    ; CASE 1 — NULL initialisation rejected
    ; =======================================================================

    xor edi, edi
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — pristine runtime initialises deterministically
    ; =======================================================================

    lea rdi, [rel runtime_a]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    cmp qword [rel runtime_a + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STARTING
    jne .fail_2

    cmp qword [rel runtime_a + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION
    jne .fail_2

    cmp qword [rel runtime_a + ASMWEB_PROCESS_RUNTIME.ready], 0
    jne .fail_2

    cmp qword [rel runtime_a + ASMWEB_PROCESS_RUNTIME.initialised], 1
    jne .fail_2

    cmp qword [rel runtime_a + ASMWEB_PROCESS_RUNTIME.generation], 1
    jne .fail_2

    cmp qword [rel runtime_a + ASMWEB_PROCESS_RUNTIME.transition_count], 0
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — initial STARTING / INITIALISATION state validates
    ; =======================================================================

    lea rdi, [rel runtime_a]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — re-initialisation rejected
    ; =======================================================================

    lea rdi, [rel runtime_a]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — NULL validation rejected
    ; =======================================================================

    xor edi, edi
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — READY / STEADY_STATE / published validates
    ; =======================================================================

    lea rdi, [rel runtime_b]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STEADY_STATE

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.ready], 1

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — PRESSURED remains a STEADY_STATE runtime
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_PRESSURED

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7


    ; =======================================================================
    ; CASE 8 — DRAINING / DRAINING validates
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_DRAINING

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_DRAINING

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — STOPPING / STOPPING validates
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STOPPING

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STOPPING

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_9


    ; =======================================================================
    ; CASE 10 — READY with INITIALISATION epoch rejected
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10


    ; =======================================================================
    ; CASE 11 — READY without publication rejected
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STEADY_STATE

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.ready], 0

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11


    ; =======================================================================
    ; CASE 12 — STARTING marked ready rejected
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STARTING

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.ready], 1

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12


    ; =======================================================================
    ; CASE 13 — invalid lifecycle state rejected
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.lifecycle_state], 0
    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.ready], 0

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13


    ; =======================================================================
    ; CASE 14 — invalid memory epoch rejected
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STARTING

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.memory_epoch], 0

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14


    ; =======================================================================
    ; CASE 15 — non-Boolean ready rejected
    ; =======================================================================

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION

    mov qword [rel runtime_b + ASMWEB_PROCESS_RUNTIME.ready], 2

    lea rdi, [rel runtime_b]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15


    ; =======================================================================
    ; CASE 16 — uninitialised runtime rejected
    ; =======================================================================

    lea rdi, [rel runtime_c]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    ; =======================================================================
    ; CASE 17 — zero generation rejected
    ; =======================================================================

    lea rdi, [rel runtime_c]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_17

    mov qword [rel runtime_c + ASMWEB_PROCESS_RUNTIME.generation], 0

    lea rdi, [rel runtime_c]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17


    ; =======================================================================
    ; CASE 18 — ABI callee-saved registers and DF preserved
    ; =======================================================================

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    lea rdi, [rel runtime_a]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18

    cmp rbx, 0x11111111
    jne .fail_18

    cmp rbp, 0x22222222
    jne .fail_18

    cmp r12, 0x33333333
    jne .fail_18

    cmp r13, 0x44444444
    jne .fail_18

    cmp r14, 0x55555555
    jne .fail_18

    cmp r15, 0x66666666
    jne .fail_18

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_18


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
