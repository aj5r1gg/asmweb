bits 64

%include "asmweb/memory.inc"
%include "asmweb/resource.inc"

global _start

extern asm_mapping_capacity_init
extern asm_memory_map_rw_bounded
extern asm_memory_unmap_bounded
extern asm_linux_exit

section .bss

align 8
capacity:
    resb ASMWEB_MAPPING_CAPACITY_size

mapping_a:
    resb ASMWEB_MEMORY_MAPPING_size

mapping_b:
    resb ASMWEB_MEMORY_MAPPING_size

mapping_c:
    resb ASMWEB_MEMORY_MAPPING_size

section .text

; ---------------------------------------------------------------------------
; Mapping-capacity qualification
;
; Configured capacity:
;
;   2 mappings
;   8192 mapped bytes
;
; This directly exercises N-1, N and N+1 count capacity.
;
; Exit status:
;
;   0  = PASS
;   1  = capacity init failed
;   2  = first acquisition failed
;   3  = first accounting state invalid
;   4  = second acquisition failed
;   5  = capacity boundary state invalid
;   6  = N+1 acquisition not rejected
;   7  = rejection mutated empty destination
;   8  = first release failed
;   9  = release accounting invalid
;   10 = reacquisition failed
;   11 = high-water accounting invalid
;   12 = byte-capacity refusal failed
;   13 = final release failed
;   14 = final quiescent state invalid
;   15 = double release not classified as integrity failure
; ---------------------------------------------------------------------------

_start:
    cld

    ; =======================================================================
    ; INITIALISE
    ; =======================================================================

    mov edi, 2
    mov esi, 8192
    mov edx, 4096
    lea rcx, [rel capacity]
    call asm_mapping_capacity_init

    test eax, eax
    jnz .fail_1

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.ready], 1
    jne .fail_1

    ; =======================================================================
    ; N-1 — first mapping
    ; =======================================================================

    mov edi, 1
    mov esi, 4096
    lea rdx, [rel capacity]
    lea rcx, [rel mapping_a]
    call asm_memory_map_rw_bounded

    test eax, eax
    jnz .fail_2

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 1
    jne .fail_3

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 4096
    jne .fail_3

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.acquisition_count], 1
    jne .fail_3

    ; =======================================================================
    ; N — second mapping
    ; =======================================================================

    mov edi, 4096
    mov esi, 4096
    lea rdx, [rel capacity]
    lea rcx, [rel mapping_b]
    call asm_memory_map_rw_bounded

    test eax, eax
    jnz .fail_4

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 2
    jne .fail_5

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 8192
    jne .fail_5

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.high_water_count], 2
    jne .fail_5

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.high_water_bytes], 8192
    jne .fail_5

    ; =======================================================================
    ; N+1 — bounded rejection
    ; =======================================================================

    mov edi, 1
    mov esi, 4096
    lea rdx, [rel capacity]
    lea rcx, [rel mapping_c]
    call asm_memory_map_rw_bounded

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_6

    cmp qword [rel mapping_c + ASMWEB_MEMORY_MAPPING.base], 0
    jne .fail_7

    cmp qword [rel mapping_c + ASMWEB_MEMORY_MAPPING.length], 0
    jne .fail_7

    cmp qword [rel mapping_c + ASMWEB_MEMORY_MAPPING.ready], 0
    jne .fail_7

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 2
    jne .fail_6

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 8192
    jne .fail_6

    ; =======================================================================
    ; RELEASE A
    ; =======================================================================

    lea rdi, [rel capacity]
    lea rsi, [rel mapping_a]
    call asm_memory_unmap_bounded

    test eax, eax
    jnz .fail_8

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 1
    jne .fail_9

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 4096
    jne .fail_9

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.release_count], 1
    jne .fail_9

    ; =======================================================================
    ; BYTE-CAPACITY REJECTION
    ;
    ; One count slot remains available here:
    ;
    ;   current_count     = 1
    ;   configured_count  = 2
    ;
    ; Therefore count admission succeeds.
    ;
    ; Request 8193 rounds to 12288 bytes:
    ;
    ;   current mapped bytes = 4096
    ;   candidate mapping    = 12288
    ;   resulting bytes      = 16384
    ;   configured bytes     = 8192
    ;
    ; The refusal therefore proves byte-capacity admission independently.
    ; =======================================================================

    mov edi, 8193
    mov esi, 4096
    lea rdx, [rel capacity]
    lea rcx, [rel mapping_c]
    call asm_memory_map_rw_bounded

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_12

    ; Occupancy must remain unchanged.
    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 1
    jne .fail_12

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 4096
    jne .fail_12

    ; No mapping may have been published.
    cmp qword [rel mapping_c + ASMWEB_MEMORY_MAPPING.base], 0
    jne .fail_12

    cmp qword [rel mapping_c + ASMWEB_MEMORY_MAPPING.length], 0
    jne .fail_12

    cmp qword [rel mapping_c + ASMWEB_MEMORY_MAPPING.ready], 0
    jne .fail_12

    ; =======================================================================
    ; REACQUIRE AFTER RELEASE
    ; =======================================================================

    mov edi, 1
    mov esi, 4096
    lea rdx, [rel capacity]
    lea rcx, [rel mapping_a]
    call asm_memory_map_rw_bounded

    test eax, eax
    jnz .fail_10

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 2
    jne .fail_10

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.acquisition_count], 3
    jne .fail_10

    ; Historical high-water must remain at the capacity boundary.
    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.high_water_count], 2
    jne .fail_11

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.high_water_bytes], 8192
    jne .fail_11

    ; =======================================================================
    ; RELEASE BOTH LIVE MAPPINGS
    ; =======================================================================

    lea rdi, [rel capacity]
    lea rsi, [rel mapping_a]
    call asm_memory_unmap_bounded

    test eax, eax
    jnz .fail_13

    lea rdi, [rel capacity]
    lea rsi, [rel mapping_b]
    call asm_memory_unmap_bounded

    test eax, eax
    jnz .fail_13

    ; =======================================================================
    ; QUIESCENT BASELINE
    ; =======================================================================

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 0
    jne .fail_14

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 0
    jne .fail_14

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.acquisition_count], 3
    jne .fail_14

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.release_count], 3
    jne .fail_14

    ; Two bounded rejected acquisition attempts occurred.
    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.rejection_count], 2
    jne .fail_14

    ; =======================================================================
    ; DOUBLE RELEASE = INTEGRITY FAILURE
    ; =======================================================================

    lea rdi, [rel capacity]
    lea rsi, [rel mapping_a]
    call asm_memory_unmap_bounded

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15

    ; Accounting must remain quiescent.
    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 0
    jne .fail_15

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 0
    jne .fail_15

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
