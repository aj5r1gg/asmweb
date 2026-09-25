bits 64

%include "asmweb/startup.inc"
%include "asmweb/entropy.inc"

global _start

extern asm_entropy_bootstrap
extern asm_linux_exit

section .rodata

align 8
entropy_source_pattern:
    dq 0x0123456789abcdef
    dq 0xfedcba9876543210

section .bss

align 8
test_startup_info:
    resb ASMWEB_STARTUP_INFO_size

align 8
guard_before:
    resq 1

test_entropy_state:
    resb ASMWEB_ENTROPY_BOOTSTRAP_size

guard_after:
    resq 1

section .text

; ---------------------------------------------------------------------------
; Entropy bootstrap qualification
;
; Exit status:
;
;   0 = all cases passed
;   1 = valid transfer failed
;   2 = missing AT_RANDOM failure semantics failed
;   3 = NULL startup failure semantics failed
;   4 = NULL destination failure semantics failed
; ---------------------------------------------------------------------------

_start:
    cld

    ; =======================================================================
    ; CASE 1 — exact successful transfer
    ; =======================================================================

    mov qword [rel guard_before], 0x11111111
    mov qword [rel guard_after], 0x22222222

    lea rax, [rel entropy_source_pattern]
    mov [rel test_startup_info + ASMWEB_STARTUP_INFO.at_random], rax

    lea rdi, [rel test_startup_info]
    lea rsi, [rel test_entropy_state]
    call asm_entropy_bootstrap

    test eax, eax
    jnz .fail_1

    mov rax, 0x0123456789abcdef
    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_lo], rax
    jne .fail_1

    mov rax, 0xfedcba9876543210
    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_hi], rax
    jne .fail_1

    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.ready], 1
    jne .fail_1

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.at_random], 0
    jne .fail_1

    cmp qword [rel guard_before], 0x11111111
    jne .fail_1

    cmp qword [rel guard_after], 0x22222222
    jne .fail_1

    ; =======================================================================
    ; CASE 2 — missing AT_RANDOM
    ;
    ; Destination must be deterministically zeroed.
    ; =======================================================================

    mov qword [rel test_startup_info + ASMWEB_STARTUP_INFO.at_random], 0

    mov qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_lo], 1
    mov qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_hi], 1
    mov qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.ready], 1

    lea rdi, [rel test_startup_info]
    lea rsi, [rel test_entropy_state]
    call asm_entropy_bootstrap

    cmp eax, 1
    jne .fail_2

    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_lo], 0
    jne .fail_2

    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_hi], 0
    jne .fail_2

    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.ready], 0
    jne .fail_2

    ; =======================================================================
    ; CASE 3 — NULL startup pointer
    ;
    ; Valid destination must still be deterministically zeroed.
    ; =======================================================================

    mov qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_lo], 1
    mov qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_hi], 1
    mov qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.ready], 1

    xor edi, edi
    lea rsi, [rel test_entropy_state]
    call asm_entropy_bootstrap

    cmp eax, 1
    jne .fail_3

    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_lo], 0
    jne .fail_3

    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.seed_hi], 0
    jne .fail_3

    cmp qword [rel test_entropy_state + ASMWEB_ENTROPY_BOOTSTRAP.ready], 0
    jne .fail_3

    ; =======================================================================
    ; CASE 4 — NULL destination
    ;
    ; Source pointer must not be consumed.
    ; =======================================================================

    lea rax, [rel entropy_source_pattern]
    mov [rel test_startup_info + ASMWEB_STARTUP_INFO.at_random], rax

    lea rdi, [rel test_startup_info]
    xor esi, esi
    call asm_entropy_bootstrap

    cmp eax, 1
    jne .fail_4

    lea rax, [rel entropy_source_pattern]
    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.at_random], rax
    jne .fail_4

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
