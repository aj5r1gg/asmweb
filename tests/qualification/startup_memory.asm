bits 64

%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/startup_memory.inc"

global _start

extern asm_startup_memory_account_init
extern asm_startup_memory_account_baseline
extern asm_startup_memory_account_validate
extern asm_startup_memory_account_acquire
extern asm_startup_memory_account_release
extern asm_linux_exit


section .data

align 8

; Deliberately non-pristine object.
nonpristine_account:
    dq 1
    dq 1
    dq 0


; Valid initialised account at UINT64_MAX.
max_account:
    dq 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF
    dq 1


; Invalid account: current exceeds peak.
corrupt_account:
    dq 101
    dq 100
    dq 1


section .bss

align 8

account:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size

exact_max_account:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size

uninitialised_account:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size

baseline_account:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size

baseline_uninitialised_account:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size

baseline_abi_account:
    resb ASMWEB_STARTUP_MEMORY_ACCOUNT_size


section .text

_start:
    cld


    ; =======================================================================
    ; CASE 1 — NULL init rejected
    ; =======================================================================

    xor edi, edi

    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — pristine account initialises deterministically
    ; =======================================================================

    lea rdi, [rel account]

    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 0
    jne .fail_2

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 0
    jne .fail_2

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 1
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — initialised account validates
    ; =======================================================================

    lea rdi, [rel account]

    call asm_startup_memory_account_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — reinitialisation rejected
    ; =======================================================================

    lea rdi, [rel account]

    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — non-pristine account rejected
    ; =======================================================================

    lea rdi, [rel nonpristine_account]

    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — first acquisition establishes current and peak
    ; =======================================================================

    lea rdi, [rel account]
    mov esi, 100

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_6

    cmp rdx, 100
    jne .fail_6

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 100
    jne .fail_6

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 100
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — overlapping acquisition raises peak
    ; =======================================================================

    lea rdi, [rel account]
    mov esi, 50

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7

    cmp rdx, 150
    jne .fail_7

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 150
    jne .fail_7

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 150
    jne .fail_7


    ; =======================================================================
    ; CASE 8 — release reduces current but preserves peak
    ; =======================================================================

    lea rdi, [rel account]
    mov esi, 70

    call asm_startup_memory_account_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_8

    cmp rdx, 80
    jne .fail_8

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 80
    jne .fail_8

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 150
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — later acquisition below peak does not lower/change peak
    ; =======================================================================

    lea rdi, [rel account]
    mov esi, 20

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_9

    cmp rdx, 100
    jne .fail_9

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 100
    jne .fail_9

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 150
    jne .fail_9


    ; =======================================================================
    ; CASE 10 — release underflow rejected without mutation
    ; =======================================================================

    lea rdi, [rel account]
    mov esi, 101

    call asm_startup_memory_account_release

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10

    test rdx, rdx
    jne .fail_10

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 100
    jne .fail_10

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 150
    jne .fail_10


    ; =======================================================================
    ; CASE 11 — acquisition overflow rejected without mutation
    ; =======================================================================

    lea rdi, [rel max_account]
    mov esi, 1

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11

    test rdx, rdx
    jne .fail_11

    cmp qword [rel max_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], \
        ASMWEB_U64_MAX
    jne .fail_11

    cmp qword [rel max_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], \
        ASMWEB_U64_MAX
    jne .fail_11


    ; =======================================================================
    ; CASE 12 — exact UINT64_MAX acquisition succeeds
    ; =======================================================================

    lea rdi, [rel exact_max_account]

    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    lea rdi, [rel exact_max_account]
    mov rsi, ASMWEB_U64_MAX

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_12

    cmp rdx, ASMWEB_U64_MAX
    jne .fail_12

    cmp qword [rel exact_max_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], \
        ASMWEB_U64_MAX
    jne .fail_12


    ; =======================================================================
    ; CASE 13 — exact full release returns current to zero, peak retained
    ; =======================================================================

    lea rdi, [rel exact_max_account]
    mov rsi, ASMWEB_U64_MAX

    call asm_startup_memory_account_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_13

    test rdx, rdx
    jne .fail_13

    cmp qword [rel exact_max_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 0
    jne .fail_13

    cmp qword [rel exact_max_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], \
        ASMWEB_U64_MAX
    jne .fail_13


    ; =======================================================================
    ; CASE 14 — zero-byte acquisition/release are valid numerical operations
    ; =======================================================================

    lea rdi, [rel account]
    xor esi, esi

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_14

    cmp rdx, 100
    jne .fail_14

    lea rdi, [rel account]
    xor esi, esi

    call asm_startup_memory_account_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_14

    cmp rdx, 100
    jne .fail_14

    cmp qword [rel account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 150
    jne .fail_14


    ; =======================================================================
    ; CASE 15 — NULL validation rejected
    ; =======================================================================

    xor edi, edi

    call asm_startup_memory_account_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15


    ; =======================================================================
    ; CASE 16 — corrupt current > peak state rejected
    ; =======================================================================

    lea rdi, [rel corrupt_account]

    call asm_startup_memory_account_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    ; =======================================================================
    ; CASE 17 — uninitialised acquisition rejected
    ; =======================================================================

    lea rdi, [rel uninitialised_account]
    mov esi, 1

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17

    test rdx, rdx
    jne .fail_17


    ; =======================================================================
    ; CASE 18 — uninitialised release rejected
    ; =======================================================================

    lea rdi, [rel uninitialised_account]
    mov esi, 1

    call asm_startup_memory_account_release

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_18

    test rdx, rdx
    jne .fail_18


    ; =======================================================================
    ; CASE 19 — public startup-account routines preserve Internal ABI + DF
    ; =======================================================================

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    lea rdi, [rel account]

    call asm_startup_memory_account_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    lea rdi, [rel account]
    mov esi, 1

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    lea rdi, [rel account]
    mov esi, 1

    call asm_startup_memory_account_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19

    cmp rbx, 0x11111111
    jne .fail_19

    cmp rbp, 0x22222222
    jne .fail_19

    cmp r12, 0x33333333
    jne .fail_19

    cmp r13, 0x44444444
    jne .fail_19

    cmp r14, 0x55555555
    jne .fail_19

    cmp r15, 0x66666666
    jne .fail_19

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_19


    ; =======================================================================
    ; CASE 20 — NULL baseline rejected
    ; =======================================================================

    xor edi, edi
    mov esi, 4096

    call asm_startup_memory_account_baseline

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_20

    test rdx, rdx
    jne .fail_20


    ; =======================================================================
    ; CASE 21 — uninitialised baseline rejected without mutation
    ; =======================================================================

    lea rdi, [rel baseline_uninitialised_account]
    mov esi, 4096

    call asm_startup_memory_account_baseline

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_21

    test rdx, rdx
    jne .fail_21

    cmp qword [rel baseline_uninitialised_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 0
    jne .fail_21

    cmp qword [rel baseline_uninitialised_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 0
    jne .fail_21

    cmp qword [rel baseline_uninitialised_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 0
    jne .fail_21


    ; =======================================================================
    ; CASE 22 — baseline establishes already-retained registered bytes
    ; =======================================================================

    lea rdi, [rel baseline_account]
    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22

    lea rdi, [rel baseline_account]
    mov esi, 4096

    call asm_startup_memory_account_baseline

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22

    cmp rdx, 4096
    jne .fail_22

    cmp qword [rel baseline_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 4096
    jne .fail_22

    cmp qword [rel baseline_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 4096
    jne .fail_22

    lea rdi, [rel baseline_account]
    call asm_startup_memory_account_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_22


    ; =======================================================================
    ; CASE 23 — re-baselining is rejected without rewriting history
    ; =======================================================================

    lea rdi, [rel baseline_account]
    mov esi, 1

    call asm_startup_memory_account_baseline

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_23

    test rdx, rdx
    jne .fail_23

    cmp qword [rel baseline_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 4096
    jne .fail_23

    cmp qword [rel baseline_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 4096
    jne .fail_23


    ; =======================================================================
    ; CASE 24 — acquisition/release operate above an established baseline
    ; =======================================================================

    lea rdi, [rel baseline_account]
    mov esi, 512

    call asm_startup_memory_account_acquire

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_24

    cmp rdx, 4608
    jne .fail_24

    cmp qword [rel baseline_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 4608
    jne .fail_24

    cmp qword [rel baseline_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 4608
    jne .fail_24

    lea rdi, [rel baseline_account]
    mov esi, 512

    call asm_startup_memory_account_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_24

    cmp rdx, 4096
    jne .fail_24

    cmp qword [rel baseline_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 4096
    jne .fail_24

    cmp qword [rel baseline_account + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 4608
    jne .fail_24


    ; =======================================================================
    ; CASE 25 — baseline preserves Internal ABI callee-saved state and DF
    ; =======================================================================

    lea rdi, [rel baseline_abi_account]
    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_25

    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    lea rdi, [rel baseline_abi_account]
    mov esi, 2048

    call asm_startup_memory_account_baseline

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_25

    cmp rdx, 2048
    jne .fail_25

    cmp rbx, 0x11111111
    jne .fail_25

    cmp rbp, 0x22222222
    jne .fail_25

    cmp r12, 0x33333333
    jne .fail_25

    cmp r13, 0x44444444
    jne .fail_25

    cmp r14, 0x55555555
    jne .fail_25

    cmp r15, 0x66666666
    jne .fail_25

    pushfq
    pop rax
    test rax, 1 << 10
    jnz .fail_25


    xor edi, edi
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
