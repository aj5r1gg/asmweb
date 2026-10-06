bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"

%include "asmweb/startup.inc"
%include "asmweb/entropy.inc"
%include "asmweb/cpu.inc"
%include "asmweb/time.inc"
%include "asmweb/process_runtime.inc"
%include "asmweb/startup_memory.inc"
%include "asmweb/registry.inc"
%include "asmweb/production_registry.inc"


global asm_production_registry_init
global asm_production_registry_get


extern asm_registry_validate


; ===========================================================================
; Canonical production storage
; ===========================================================================

section .bss

align 8

asm_production_olr:
    resb ASMWEB_OLR_VALIDATION_ENTRY_size * ASMWEB_PRODUCTION_OLR_COUNT

asm_production_mot:
    resb ASMWEB_MOT_VALIDATION_ENTRY_size * ASMWEB_PRODUCTION_MOT_COUNT

asm_production_registry_set:
    resb ASMWEB_REGISTRY_VALIDATION_SET_size

asm_production_registry_ready:
    resq 1


section .text


; ===========================================================================
; OLR materialisation helper
;
; Macro parameters:
;
;   1 index
;   2 object_id
;   3 actual_size
;   4 mot_ref
;
; All current production M0 fixed objects:
;
;   - are ACTIVE;
;   - have qualified assembly-defined layouts;
;   - are not typed-pool elements;
;   - nevertheless resolve to MOT state because they contribute to the fixed
;     direct runtime capacity.
; ===========================================================================

%macro ASMWEB_PRODUCTION_OLR_ENTRY 4
    lea r10, [rel asm_production_olr + ASMWEB_OLR_VALIDATION_ENTRY_size * %1]

    mov qword [r10 + ASMWEB_OLR_VALIDATION_ENTRY.object_id], %2
    mov qword [r10 + ASMWEB_OLR_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE
    mov qword [r10 + ASMWEB_OLR_VALIDATION_ENTRY.layout_status], \
        ASMWEB_LAYOUT_STATUS_QUALIFIED
    mov qword [r10 + ASMWEB_OLR_VALIDATION_ENTRY.actual_size_bytes], %3
    mov qword [r10 + ASMWEB_OLR_VALIDATION_ENTRY.effective_stride_bytes], %3
    mov qword [r10 + ASMWEB_OLR_VALIDATION_ENTRY.pooled], 0
    mov qword [r10 + ASMWEB_OLR_VALIDATION_ENTRY.mot_ref], %4
%endmacro


; ===========================================================================
; MOT materialisation helper
;
; Macro parameters:
;
;   1 index
;   2 limit_id
;   3 object_id
;   4 actual_size
;
; Each current fixed production object has:
;
;   maximum_count       = 1
;   physical_capacity   = 1
;   configured_capacity = 1
;   pool metadata       = 0
;   mapping overhead    = 0
;   RCT owner           = none
;
; This represents fixed process-persistent direct state. It does not imply
; typed-pool semantics or external resource capacity.
; ===========================================================================

%macro ASMWEB_PRODUCTION_MOT_ENTRY 4
    lea r10, [rel asm_production_mot + ASMWEB_MOT_VALIDATION_ENTRY_size * %1]

    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.limit_id], %2
    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.status], \
        ASMWEB_REGISTRY_STATUS_ACTIVE
    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.object_id], %3

    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.actual_size_bytes], %4
    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.effective_stride_bytes], %4

    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.pool_metadata_bytes], 0
    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.mapping_overhead_bytes], 0

    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.maximum_count], 1
    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.physical_capacity], 1
    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.configured_capacity], 1

    mov qword [r10 + ASMWEB_MOT_VALIDATION_ENTRY.owner_resource_id], 0
%endmacro


; ===========================================================================
; asm_production_registry_init
;
; Materialises and validates the canonical production M0 OLR/MOT/RCT
; projection.
;
; The current production RCT is canonically empty because no production
; externally retained resource-capacity object is yet instantiated by the
; ordinary runtime path. Controlled mapping/RCT machinery exists, but it is
; not falsely presented here as live production state before runtime wiring.
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Publication:
;
;   asm_production_registry_ready becomes 1 only after the materialised set
;   passes asm_registry_validate.
;
; Reinitialisation after successful publication is rejected.
; ===========================================================================

asm_production_registry_init:
    cld

    cmp qword [rel asm_production_registry_ready], 0
    jne .already_published


    ; -----------------------------------------------------------------------
    ; OLR
    ; -----------------------------------------------------------------------

    ASMWEB_PRODUCTION_OLR_ENTRY \
        0, \
        ASMWEB_PROD_OBJECT_STARTUP_INFO, \
        ASMWEB_STARTUP_INFO_size, \
        ASMWEB_PROD_LIMIT_STARTUP_INFO

    ASMWEB_PRODUCTION_OLR_ENTRY \
        1, \
        ASMWEB_PROD_OBJECT_ENTROPY_BOOTSTRAP, \
        ASMWEB_ENTROPY_BOOTSTRAP_size, \
        ASMWEB_PROD_LIMIT_ENTROPY_BOOTSTRAP

    ASMWEB_PRODUCTION_OLR_ENTRY \
        2, \
        ASMWEB_PROD_OBJECT_CPU_INFO, \
        ASMWEB_CPU_INFO_size, \
        ASMWEB_PROD_LIMIT_CPU_INFO

    ASMWEB_PRODUCTION_OLR_ENTRY \
        3, \
        ASMWEB_PROD_OBJECT_MONOTONIC_TIME, \
        ASMWEB_MONOTONIC_TIME_size, \
        ASMWEB_PROD_LIMIT_MONOTONIC_TIME

    ASMWEB_PRODUCTION_OLR_ENTRY \
        4, \
        ASMWEB_PROD_OBJECT_PROCESS_RUNTIME, \
        ASMWEB_PROCESS_RUNTIME_size, \
        ASMWEB_PROD_LIMIT_PROCESS_RUNTIME

    ASMWEB_PRODUCTION_OLR_ENTRY \
        5, \
        ASMWEB_PROD_OBJECT_STARTUP_MEMORY_ACCOUNT, \
        ASMWEB_STARTUP_MEMORY_ACCOUNT_size, \
        ASMWEB_PROD_LIMIT_STARTUP_MEMORY_ACCOUNT

    ASMWEB_PRODUCTION_OLR_ENTRY \
        6, \
        ASMWEB_PROD_OBJECT_RUNTIME_RULE_STORAGE, \
        ASMWEB_PRODUCTION_RUNTIME_RULE_STORAGE_BYTES, \
        ASMWEB_PROD_LIMIT_RUNTIME_RULE_STORAGE

    ASMWEB_PRODUCTION_OLR_ENTRY \
        7, \
        ASMWEB_PROD_OBJECT_REGISTRY_STORAGE, \
        ASMWEB_PRODUCTION_REGISTRY_STORAGE_BYTES, \
        ASMWEB_PROD_LIMIT_REGISTRY_STORAGE


    ; -----------------------------------------------------------------------
    ; MOT
    ; -----------------------------------------------------------------------

    ASMWEB_PRODUCTION_MOT_ENTRY \
        0, \
        ASMWEB_PROD_LIMIT_STARTUP_INFO, \
        ASMWEB_PROD_OBJECT_STARTUP_INFO, \
        ASMWEB_STARTUP_INFO_size

    ASMWEB_PRODUCTION_MOT_ENTRY \
        1, \
        ASMWEB_PROD_LIMIT_ENTROPY_BOOTSTRAP, \
        ASMWEB_PROD_OBJECT_ENTROPY_BOOTSTRAP, \
        ASMWEB_ENTROPY_BOOTSTRAP_size

    ASMWEB_PRODUCTION_MOT_ENTRY \
        2, \
        ASMWEB_PROD_LIMIT_CPU_INFO, \
        ASMWEB_PROD_OBJECT_CPU_INFO, \
        ASMWEB_CPU_INFO_size

    ASMWEB_PRODUCTION_MOT_ENTRY \
        3, \
        ASMWEB_PROD_LIMIT_MONOTONIC_TIME, \
        ASMWEB_PROD_OBJECT_MONOTONIC_TIME, \
        ASMWEB_MONOTONIC_TIME_size

    ASMWEB_PRODUCTION_MOT_ENTRY \
        4, \
        ASMWEB_PROD_LIMIT_PROCESS_RUNTIME, \
        ASMWEB_PROD_OBJECT_PROCESS_RUNTIME, \
        ASMWEB_PROCESS_RUNTIME_size

    ASMWEB_PRODUCTION_MOT_ENTRY \
        5, \
        ASMWEB_PROD_LIMIT_STARTUP_MEMORY_ACCOUNT, \
        ASMWEB_PROD_OBJECT_STARTUP_MEMORY_ACCOUNT, \
        ASMWEB_STARTUP_MEMORY_ACCOUNT_size

    ASMWEB_PRODUCTION_MOT_ENTRY \
        6, \
        ASMWEB_PROD_LIMIT_RUNTIME_RULE_STORAGE, \
        ASMWEB_PROD_OBJECT_RUNTIME_RULE_STORAGE, \
        ASMWEB_PRODUCTION_RUNTIME_RULE_STORAGE_BYTES

    ASMWEB_PRODUCTION_MOT_ENTRY \
        7, \
        ASMWEB_PROD_LIMIT_REGISTRY_STORAGE, \
        ASMWEB_PROD_OBJECT_REGISTRY_STORAGE, \
        ASMWEB_PRODUCTION_REGISTRY_STORAGE_BYTES


    ; -----------------------------------------------------------------------
    ; Registry-set descriptor.
    ; -----------------------------------------------------------------------

    lea rax, [rel asm_production_olr]
    mov [rel asm_production_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_ptr], rax

    mov qword [rel asm_production_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.olr_count], ASMWEB_PRODUCTION_OLR_COUNT


    lea rax, [rel asm_production_mot]
    mov [rel asm_production_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr], rax

    mov qword [rel asm_production_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.mot_count], ASMWEB_PRODUCTION_MOT_COUNT


    ; Canonically empty production RCT for the current runtime slice.
    mov qword [rel asm_production_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_ptr], 0

    mov qword [rel asm_production_registry_set + ASMWEB_REGISTRY_VALIDATION_SET.rct_count], 0


    ; -----------------------------------------------------------------------
    ; Validate before publication.
    ;
    ; Ordinary function entry has RSP % 16 == 8, therefore reserve 8 bytes
    ; before the nested call.
    ; -----------------------------------------------------------------------

    lea rdi, [rel asm_production_registry_set]

    sub rsp, 8
    call asm_registry_validate
    add rsp, 8

    cmp eax, ASMWEB_RESOURCE_OK
    jne .init_fail

    mov qword [rel asm_production_registry_ready], 1

    mov eax, ASMWEB_RESOURCE_OK
    ret


.init_fail:
    ; Initial publication failed. Keep the unpublished state canonical.
    mov qword [rel asm_production_registry_ready], 0

    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


.already_published:
    ; Reinitialisation is an integrity error, but rejection must not destroy
    ; an already validated and published canonical registry.
    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret


; ===========================================================================
; asm_production_registry_get
;
; Result:
;
;   Published:
;       RAX = ASMWEB_REGISTRY_VALIDATION_SET *
;
;   Not published:
;       RAX = 0
; ===========================================================================

asm_production_registry_get:
    cld

    cmp qword [rel asm_production_registry_ready], 1
    jne .get_not_ready

    lea rax, [rel asm_production_registry_set]
    ret


.get_not_ready:
    xor eax, eax
    ret


%unmacro ASMWEB_PRODUCTION_OLR_ENTRY 4
%unmacro ASMWEB_PRODUCTION_MOT_ENTRY 4
