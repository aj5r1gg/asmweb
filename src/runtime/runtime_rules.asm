bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/registry.inc"

global asm_runtime_rules_init
global asm_runtime_rules_get

extern asm_rrr_validate


; ===========================================================================
; Compile-time rule population
; ===========================================================================

%assign ASMWEB_RUNTIME_RULE_COUNT 0

%macro ASMWEB_RUNTIME_RULE 6
    %assign ASMWEB_RUNTIME_RULE_COUNT ASMWEB_RUNTIME_RULE_COUNT + 1
%endmacro

%include "asmweb/runtime_rules.def"

%unmacro ASMWEB_RUNTIME_RULE 6


; Runtime & Memory v0.3 currently defines exactly thirteen explicit MEM-*
; atomic rules. If the authority file changes, this deliberate M0 assertion
; forces the qualification/build contract to be reviewed rather than silently
; changing the baseline.

%if ASMWEB_RUNTIME_RULE_COUNT != 13
    %error "Runtime & Memory v0.3 canonical RRR must contain exactly 13 rules"
%endif


; ===========================================================================
; Canonical immutable rule text
; ===========================================================================

section .rodata

%macro ASMWEB_RUNTIME_RULE 6
asm_runtime_rule_id_%1:
    db %2
asm_runtime_rule_id_%1_len equ $ - asm_runtime_rule_id_%1

asm_runtime_rule_statement_%1:
    db %6
asm_runtime_rule_statement_%1_len equ $ - asm_runtime_rule_statement_%1
%endmacro

%include "asmweb/runtime_rules.def"

%unmacro ASMWEB_RUNTIME_RULE 6


; ===========================================================================
; Materialised validation/registry table
;
; Pointer-bearing entries are populated at initialisation so the linked binary
; does not require runtime relocations or writable static absolute pointers.
; ===========================================================================

section .bss

align 8

asm_runtime_rules:
    resb ASMWEB_RRR_VALIDATION_ENTRY_size * ASMWEB_RUNTIME_RULE_COUNT

asm_runtime_rules_ready:
    resq 1


section .text


; ---------------------------------------------------------------------------
; asm_runtime_rules_init
;
; Materialise the canonical Runtime & Memory v0.3 RRR from the single
; runtime_rules.def authority and validate it before publication.
;
; Result:
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Publication:
;   asm_runtime_rules_ready becomes 1 only after asm_rrr_validate succeeds.
; ---------------------------------------------------------------------------

asm_runtime_rules_init:
    cld

    mov qword [rel asm_runtime_rules_ready], 0

%assign ASMWEB_RUNTIME_RULE_INDEX 0

%macro ASMWEB_RUNTIME_RULE 6
    lea r10, [rel asm_runtime_rules + ASMWEB_RRR_VALIDATION_ENTRY_size * ASMWEB_RUNTIME_RULE_INDEX]

    lea rax, [rel asm_runtime_rule_id_%1]
    mov [r10 + ASMWEB_RRR_VALIDATION_ENTRY.rule_id_ptr], rax
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.rule_id_length], asm_runtime_rule_id_%1_len
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.namespace], %3
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.status], %4
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.qualification_state], %5

    lea rax, [rel asm_runtime_rule_statement_%1]
    mov [r10 + ASMWEB_RRR_VALIDATION_ENTRY.normative_statement_ptr], rax
    mov qword [r10 + ASMWEB_RRR_VALIDATION_ENTRY.normative_statement_length], asm_runtime_rule_statement_%1_len

    %assign ASMWEB_RUNTIME_RULE_INDEX ASMWEB_RUNTIME_RULE_INDEX + 1
%endmacro

%include "asmweb/runtime_rules.def"

%unmacro ASMWEB_RUNTIME_RULE 6


    ; Validate before publication.
    lea rdi, [rel asm_runtime_rules]
    mov esi, ASMWEB_RUNTIME_RULE_COUNT

    ; Internal ABI requires RSP % 16 == 0 immediately before CALL.
    sub rsp, 8
    call asm_rrr_validate
    add rsp, 8

    cmp eax, ASMWEB_RESOURCE_OK
    jne .init_fail

    mov qword [rel asm_runtime_rules_ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret


.init_fail:
    mov qword [rel asm_runtime_rules_ready], 0

    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ---------------------------------------------------------------------------
; asm_runtime_rules_get
;
; Result:
;   On published canonical RRR:
;       RAX = pointer to first ASMWEB_RRR_VALIDATION_ENTRY
;       RDX = number of entries
;
;   Before successful publication:
;       RAX = 0
;       RDX = 0
; ---------------------------------------------------------------------------

asm_runtime_rules_get:
    cld

    cmp qword [rel asm_runtime_rules_ready], 1
    jne .not_ready

    lea rax, [rel asm_runtime_rules]
    mov edx, ASMWEB_RUNTIME_RULE_COUNT
    ret


.not_ready:
    xor eax, eax
    xor edx, edx
    ret
