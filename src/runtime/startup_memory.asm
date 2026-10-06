bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/startup_memory.inc"


global asm_startup_memory_account_init
global asm_startup_memory_account_baseline
global asm_startup_memory_account_validate
global asm_startup_memory_account_acquire
global asm_startup_memory_account_release


extern asm_u64_add_checked
extern asm_u64_sub_checked


; ===========================================================================
; asm_startup_memory_account_init
;
; RDI = ASMWEB_STARTUP_MEMORY_ACCOUNT *
;
; Requires a pristine all-zero account.
;
; Returns:
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; On success:
;   current_bytes = 0
;   peak_bytes    = 0
;   initialised   = 1
; ===========================================================================

asm_startup_memory_account_init:
    cld

    test rdi, rdi
    jz .init_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 0
    jne .init_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 0
    jne .init_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 0
    jne .init_fail

    mov qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret


.init_fail:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_startup_memory_account_baseline
;
; RDI = ASMWEB_STARTUP_MEMORY_ACCOUNT *
; RSI = direct registered bytes already retained when startup accounting
;       becomes authoritative
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = established current_bytes on success
;         zero on failure
;
; Preconditions:
;
;   account != NULL
;   initialised   == 1
;   current_bytes == 0
;   peak_bytes    == 0
;
; Semantics:
;
;   current_bytes = baseline_bytes
;   peak_bytes    = baseline_bytes
;
; This is reconciliation of already-retained registered state. It is not an
; acquisition event.
;
; Re-baselining after accounting has begun is rejected. Failure leaves the
; account unchanged.
; ===========================================================================

asm_startup_memory_account_baseline:
    cld

    test rdi, rdi
    jz .baseline_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 1
    jne .baseline_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], 0
    jne .baseline_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], 0
    jne .baseline_fail

    ; Every fallible prerequisite has succeeded. These stores cannot fail.
    mov [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], rsi
    mov [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], rsi

    mov rdx, rsi
    mov eax, ASMWEB_RESOURCE_OK
    ret


.baseline_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_startup_memory_account_validate
;
; RDI = ASMWEB_STARTUP_MEMORY_ACCOUNT *
;
; Structural invariants:
;
;   initialised == 1
;   current_bytes <= peak_bytes
;
; Returns:
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
; ===========================================================================

asm_startup_memory_account_validate:
    cld

    test rdi, rdi
    jz .validate_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 1
    jne .validate_fail

    mov rax, [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]

    cmp rax, [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes]
    ja .validate_fail

    mov eax, ASMWEB_RESOURCE_OK
    ret


.validate_fail:
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_startup_memory_account_acquire
;
; RDI = ASMWEB_STARTUP_MEMORY_ACCOUNT *
; RSI = newly retained direct registered bytes
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = resulting current_bytes on success
;         zero on failure
;
; Semantics:
;
;   new_current = checked(current_bytes + acquired_bytes)
;
;   peak_bytes = max(peak_bytes, new_current)
;
; The account is not mutated unless checked arithmetic succeeds.
; ===========================================================================

asm_startup_memory_account_acquire:
    cld

    test rdi, rdi
    jz .acquire_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 1
    jne .acquire_fail

    mov rax, [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]

    cmp rax, [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes]
    ja .acquire_fail


    ; Entry RSP % 16 == 8.
    ; Three pushes -> RSP % 16 == 0 for nested CALL.
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    mov rdi, [rbx + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]
    mov rsi, r12

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .acquire_fail_preserved

    mov r13, rdx

    ; Commit only after successful checked arithmetic.
    mov [rbx + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], r13

    cmp r13, [rbx + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes]
    jbe .acquire_peak_done

    mov [rbx + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes], r13


.acquire_peak_done:
    mov rdx, r13

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.acquire_fail_preserved:
    pop r13
    pop r12
    pop rbx


.acquire_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_startup_memory_account_release
;
; RDI = ASMWEB_STARTUP_MEMORY_ACCOUNT *
; RSI = direct registered bytes no longer retained
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = resulting current_bytes on success
;         zero on failure
;
; Semantics:
;
;   new_current = checked(current_bytes - released_bytes)
;
; peak_bytes is historical high-water state and is never reduced by release.
;
; The account is not mutated unless checked arithmetic succeeds.
; ===========================================================================

asm_startup_memory_account_release:
    cld

    test rdi, rdi
    jz .release_fail

    cmp qword [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.initialised], 1
    jne .release_fail

    mov rax, [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]

    cmp rax, [rdi + ASMWEB_STARTUP_MEMORY_ACCOUNT.peak_bytes]
    ja .release_fail


    ; Entry RSP % 16 == 8.
    ; Three pushes -> RSP % 16 == 0 for nested CALL.
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    mov rdi, [rbx + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes]
    mov rsi, r12

    call asm_u64_sub_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .release_fail_preserved

    mov r13, rdx

    ; Commit only after successful checked arithmetic.
    mov [rbx + ASMWEB_STARTUP_MEMORY_ACCOUNT.current_bytes], r13

    mov rdx, r13

    pop r13
    pop r12
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.release_fail_preserved:
    pop r13
    pop r12
    pop rbx


.release_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
