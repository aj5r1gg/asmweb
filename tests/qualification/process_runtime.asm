bits 64

%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/process_runtime.inc"
%include "asmweb/registry.inc"
%include "asmweb/startup_memory.inc"

global _start

extern asm_process_runtime_init
extern asm_process_runtime_validate
extern asm_process_runtime_publish_ready
extern asm_linux_exit


section .data

align 8


; ===========================================================================
; Coherent registry set
;
; One active fixed-stride class:
;
;   64 * 8 + 32 + 4096 = 4640 bytes
; ===========================================================================

valid_olr:
    dq 0x1001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 64
    dq 64
    dq 1
    dq 0x2001

valid_mot:
    dq 0x2001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1001
    dq 64
    dq 64
    dq 32
    dq 4096
    dq 8
    dq 8
    dq 4
    dq 0x3001

valid_rct:
    dq 0x3001
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 8
    dq 4
    dq 1
    dq 4640
    dq 0x2001
    dq 0


; Registry fixture whose active MOT arithmetic overflows.
overflow_olr:
    dq 0x1101
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq ASMWEB_LAYOUT_STATUS_QUALIFIED
    dq 2
    dq 2
    dq 1
    dq 0x2101

overflow_mot:
    dq 0x2101
    dq ASMWEB_REGISTRY_STATUS_ACTIVE
    dq 0x1101
    dq 2
    dq 2
    dq 0
    dq 0
    dq 0x8000000000000000
    dq 1
    dq 1
    dq 0


; Structurally corrupt startup account.
corrupt_startup_account:
    dq 2
    dq 1
    dq 1


section .bss

align 8

runtime_a:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_b:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_c:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_d:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_e:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_f:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_g:
    resb ASMWEB_PROCESS_RUNTIME_size

runtime_h:
    resb ASMWEB_PROCESS_RUNTIME_size


valid_registry_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

overflow_registry_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

startup_account:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size

startup_account_nonzero:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size


section .text

_start:
    cld


    ; -----------------------------------------------------------------------
    ; Construct registry-set fixtures.
    ; -----------------------------------------------------------------------

    lea rax, [rel valid_olr]
    mov [rel valid_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel valid_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    lea rax, [rel valid_mot]
    mov [rel valid_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel valid_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1

    lea rax, [rel valid_rct]
    mov [rel valid_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], rax
    mov qword [rel valid_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 1


    lea rax, [rel overflow_olr]
    mov [rel overflow_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax
    mov qword [rel overflow_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], 1

    lea rax, [rel overflow_mot]
    mov [rel overflow_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax
    mov qword [rel overflow_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], 1


    ; -----------------------------------------------------------------------
    ; Initialise canonical startup accounts.
    ; -----------------------------------------------------------------------

    lea rdi, [rel startup_account]
    extern asm_startup_memory_account_init
    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    lea rdi, [rel startup_account_nonzero]
    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    lea rdi, [rel startup_account_nonzero]
    mov esi, 128

    extern asm_startup_memory_account_acquire
    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


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
    ; CASE 18 — base validator ABI callee-saved registers and DF preserved
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


    ; =======================================================================
    ; CASE 19 — valid prerequisites publish READY and return direct ceiling
    ; =======================================================================

    lea rdi, [rel runtime_d]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    lea rdi, [rel runtime_d]
    lea rsi, [rel valid_registry_set]
    lea rdx, [rel startup_account]

    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    cmp rdx, 4640
    jne .fail_19

    cmp qword [rel runtime_d + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY
    jne .fail_19

    cmp qword [rel runtime_d + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STEADY_STATE
    jne .fail_19

    cmp qword [rel runtime_d + ASMWEB_PROCESS_RUNTIME.ready], 1
    jne .fail_19

    cmp qword [rel runtime_d + ASMWEB_PROCESS_RUNTIME.transition_count], 1
    jne .fail_19

    lea rdi, [rel runtime_d]
    call asm_process_runtime_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    ; =======================================================================
    ; CASE 20 — nonzero startup current is permitted when account is valid
    ; =======================================================================

    lea rdi, [rel runtime_e]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_20

    lea rdi, [rel runtime_e]
    lea rsi, [rel valid_registry_set]
    lea rdx, [rel startup_account_nonzero]

    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_20

    cmp rdx, 4640
    jne .fail_20

    cmp qword [rel runtime_e + ASMWEB_PROCESS_RUNTIME.ready], 1
    jne .fail_20


    ; =======================================================================
    ; CASE 21 — invalid registry fails without partial publication
    ; =======================================================================

    lea rdi, [rel runtime_f]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_21

    lea rdi, [rel runtime_f]
    lea rsi, [rel overflow_registry_set]
    lea rdx, [rel startup_account]

    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21

    test rdx, rdx
    jne .fail_21

    cmp qword [rel runtime_f + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STARTING
    jne .fail_21

    cmp qword [rel runtime_f + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION
    jne .fail_21

    cmp qword [rel runtime_f + ASMWEB_PROCESS_RUNTIME.ready], 0
    jne .fail_21

    cmp qword [rel runtime_f + ASMWEB_PROCESS_RUNTIME.transition_count], 0
    jne .fail_21


    ; =======================================================================
    ; CASE 22 — corrupt startup account fails without partial publication
    ; =======================================================================

    lea rdi, [rel runtime_g]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22

    lea rdi, [rel runtime_g]
    lea rsi, [rel valid_registry_set]
    lea rdx, [rel corrupt_startup_account]

    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_22

    test rdx, rdx
    jne .fail_22

    cmp qword [rel runtime_g + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STARTING
    jne .fail_22

    cmp qword [rel runtime_g + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION
    jne .fail_22

    cmp qword [rel runtime_g + ASMWEB_PROCESS_RUNTIME.ready], 0
    jne .fail_22

    cmp qword [rel runtime_g + ASMWEB_PROCESS_RUNTIME.transition_count], 0
    jne .fail_22


    ; =======================================================================
    ; CASE 23 — transition-count overflow fails without publication
    ; =======================================================================

    lea rdi, [rel runtime_h]
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_23

    mov qword [rel runtime_h + ASMWEB_PROCESS_RUNTIME.transition_count], \
        ASMWEB_U64_MAX

    lea rdi, [rel runtime_h]
    lea rsi, [rel valid_registry_set]
    lea rdx, [rel startup_account]

    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_23

    test rdx, rdx
    jne .fail_23

    cmp qword [rel runtime_h + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_STARTING
    jne .fail_23

    cmp qword [rel runtime_h + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_INITIALISATION
    jne .fail_23

    cmp qword [rel runtime_h + ASMWEB_PROCESS_RUNTIME.ready], 0
    jne .fail_23

    cmp qword [rel runtime_h + ASMWEB_PROCESS_RUNTIME.transition_count], \
        ASMWEB_U64_MAX
    jne .fail_23


    ; =======================================================================
    ; CASE 24 — already READY cannot be published again
    ; =======================================================================

    lea rdi, [rel runtime_d]
    lea rsi, [rel valid_registry_set]
    lea rdx, [rel startup_account]

    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_24

    test rdx, rdx
    jne .fail_24

    cmp qword [rel runtime_d + ASMWEB_PROCESS_RUNTIME.lifecycle_state], \
        ASMWEB_PROCESS_STATE_READY
    jne .fail_24

    cmp qword [rel runtime_d + ASMWEB_PROCESS_RUNTIME.memory_epoch], \
        ASMWEB_MEMORY_EPOCH_STEADY_STATE
    jne .fail_24

    cmp qword [rel runtime_d + ASMWEB_PROCESS_RUNTIME.ready], 1
    jne .fail_24

    cmp qword [rel runtime_d + ASMWEB_PROCESS_RUNTIME.transition_count], 1
    jne .fail_24


    ; =======================================================================
    ; CASE 25 — NULL arguments rejected
    ; =======================================================================

    xor edi, edi
    lea rsi, [rel valid_registry_set]
    lea rdx, [rel startup_account]
    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_25

    test rdx, rdx
    jne .fail_25

    lea rdi, [rel runtime_a]
    xor esi, esi
    lea rdx, [rel startup_account]
    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_25

    test rdx, rdx
    jne .fail_25

    lea rdi, [rel runtime_a]
    lea rsi, [rel valid_registry_set]
    xor edx, edx
    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_25

    test rdx, rdx
    jne .fail_25


    ; =======================================================================
    ; CASE 26 — publication gate preserves Internal ABI + clears DF
    ; =======================================================================

    ; runtime_a is still canonical STARTING / INITIALISATION.
    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    lea rdi, [rel runtime_a]
    lea rsi, [rel valid_registry_set]
    lea rdx, [rel startup_account]

    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_26

    cmp rdx, 4640
    jne .fail_26

    cmp rbx, 0x11111111
    jne .fail_26

    cmp rbp, 0x22222222
    jne .fail_26

    cmp r12, 0x33333333
    jne .fail_26

    cmp r13, 0x44444444
    jne .fail_26

    cmp r14, 0x55555555
    jne .fail_26

    cmp r15, 0x66666666
    jne .fail_26

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_26


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
