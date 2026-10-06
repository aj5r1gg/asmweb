bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"

global asm_u64_add_checked
global asm_u64_sub_checked
global asm_u64_mul_checked

global asm_u64_floor_div
global asm_u64_ceil_div
global asm_u64_exact_div


; ===========================================================================
; asm_u64_add_checked
;
; Calculates:
;   RDI + RSI
;
; Rejects unsigned overflow.
; ===========================================================================

asm_u64_add_checked:
    cld

    mov rdx, rdi
    add rdx, rsi
    jc .add_fail

    mov eax, ASMWEB_RESOURCE_OK
    ret


.add_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_u64_sub_checked
;
; Calculates:
;   RDI - RSI
;
; Rejects unsigned underflow.
; ===========================================================================

asm_u64_sub_checked:
    cld

    cmp rdi, rsi
    jb .sub_fail

    mov rdx, rdi
    sub rdx, rsi

    mov eax, ASMWEB_RESOURCE_OK
    ret


.sub_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_u64_mul_checked
;
; Calculates:
;   RDI * RSI
;
; Uses the full 128-bit unsigned MUL result.
; Any non-zero high half is overflow.
; ===========================================================================

asm_u64_mul_checked:
    cld

    mov rax, rdi
    mul rsi

    test rdx, rdx
    jnz .mul_fail

    mov rcx, rax
    mov rdx, rcx
    mov eax, ASMWEB_RESOURCE_OK
    ret


.mul_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_u64_floor_div
;
; Calculates:
;   floor_div(RDI, RSI)
;
; The defined capacity domain is non-negative, so ordinary unsigned quotient
; is floor division.
;
; Division by zero is invalid.
; ===========================================================================

asm_u64_floor_div:
    cld

    test rsi, rsi
    jz .floor_fail

    mov rax, rdi
    xor edx, edx
    div rsi

    mov rcx, rax
    mov rdx, rcx
    mov eax, ASMWEB_RESOURCE_OK
    ret


.floor_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_u64_ceil_div
;
; Calculates:
;   ceil_div(RDI, RSI)
;
; For the non-negative uint64 capacity domain:
;
;   quotient  = A / B
;   remainder = A % B
;
;   result = quotient + (remainder != 0)
;
; Division by zero is invalid.
;
; No overflow is possible in the final increment:
;   if remainder != 0 then divisor > 1 or quotient < UINT64_MAX.
; ===========================================================================

asm_u64_ceil_div:
    cld

    test rsi, rsi
    jz .ceil_fail

    mov rax, rdi
    xor edx, edx
    div rsi

    mov rcx, rax

    test rdx, rdx
    jz .ceil_done

    inc rcx


.ceil_done:
    mov rdx, rcx
    mov eax, ASMWEB_RESOURCE_OK
    ret


.ceil_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_u64_exact_div
;
; Calculates:
;   exact_div(RDI, RSI)
;
; Requires:
;   RSI != 0
;   RDI % RSI == 0
;
; Non-exact division is an integrity/configuration failure.
; ===========================================================================

asm_u64_exact_div:
    cld

    test rsi, rsi
    jz .exact_fail

    mov rax, rdi
    xor edx, edx
    div rsi

    test rdx, rdx
    jnz .exact_fail

    mov rcx, rax
    mov rdx, rcx
    mov eax, ASMWEB_RESOURCE_OK
    ret


.exact_fail:
    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
