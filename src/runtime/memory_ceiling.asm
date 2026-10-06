bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/memory_ceiling.inc"

global asm_memory_fixed_class_capacity

extern asm_u64_mul_checked
extern asm_u64_add_checked


; ===========================================================================
; asm_memory_fixed_class_capacity
;
; Inputs:
;
;   RDI = effective_stride_bytes
;   RSI = maximum_count
;   RDX = pool_metadata_bytes
;   RCX = mapping_overhead_bytes
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = complete class direct-memory contribution on success
;         zero on failure
;
; Formula:
;
;   payload_max = stride * count
;
;   class_max =
;       payload_max
;     + pool_metadata
;     + mapping_overhead
;
; The routine intentionally composes the canonical checked arithmetic
; primitives rather than reproducing independent overflow logic.
; ===========================================================================

asm_memory_fixed_class_capacity:
    cld

    ; Function entry sees RSP % 16 == 8.
    ;
    ; Reserve 24 bytes:
    ;   [rsp + 0]  pool_metadata
    ;   [rsp + 8]  mapping_overhead
    ;   [rsp + 16] reserved/alignment
    ;
    ; This leaves RSP % 16 == 0 before each CALL.
    sub rsp, 24

    mov [rsp + 0], rdx
    mov [rsp + 8], rcx


    ; -----------------------------------------------------------------------
    ; payload_max = stride * count
    ; -----------------------------------------------------------------------

    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail


    ; -----------------------------------------------------------------------
    ; payload_plus_metadata = payload_max + pool_metadata
    ; -----------------------------------------------------------------------

    mov rdi, rdx
    mov rsi, [rsp + 0]

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail


    ; -----------------------------------------------------------------------
    ; class_max = payload_plus_metadata + mapping_overhead
    ; -----------------------------------------------------------------------

    mov rdi, rdx
    mov rsi, [rsp + 8]

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail


    add rsp, 24

    mov eax, ASMWEB_RESOURCE_OK
    ret


.fail:
    add rsp, 24

    xor edx, edx
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
