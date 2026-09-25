bits 64

%include "asmweb/startup.inc"
%include "asmweb/memory.inc"

global _start

extern asm_memory_map_rw
extern asm_memory_unmap
extern asm_linux_exit

section .bss

align 8
guard_before:
    resq 1

mapping:
    resb ASMWEB_MEMORY_MAPPING_size

guard_after:
    resq 1

section .text

; ---------------------------------------------------------------------------
; Controlled memory-mapping qualification
;
; Exit status:
;
;   0  = all checks passed
;   1  = one-byte mapping failed
;   2  = first mapping length/alignment invalid
;   3  = first mapping memory write/read failed
;   4  = first unmap failed
;   5  = released mapping state not cleared
;   6  = page-crossing mapping failed
;   7  = page-crossing length invalid
;   8  = page-crossing memory write/read failed
;   9  = page-crossing unmap failed
;   10 = zero-size rejection failed
;   11 = invalid-page rejection failed
;   12 = overflow rejection failed
;   13 = NULL destination semantics failed
;   14 = NULL unmap semantics failed
;   15 = guard corruption
;   16 = callee-saved register preservation failed
;   17 = non-empty destination ownership rejection failed
; ---------------------------------------------------------------------------

_start:
    cld

    mov qword [rel guard_before], 0x11111111
    mov qword [rel guard_after], 0x22222222

    ; =======================================================================
    ; CASE 1 — one byte rounds to exactly one 4096-byte page.
    ; =======================================================================

    mov rbx, 0x1122334455667788
    mov r12, 0x2233445566778899
    mov r13, 0x33445566778899aa

    mov edi, 1
    mov esi, 4096
    lea rdx, [rel mapping]
    call asm_memory_map_rw

    mov r10, rax

    mov rax, 0x1122334455667788
    cmp rbx, rax
    jne .fail_16

    mov rax, 0x2233445566778899
    cmp r12, rax
    jne .fail_16

    mov rax, 0x33445566778899aa
    cmp r13, rax
    jne .fail_16

    test r10d, r10d
    jnz .fail_1

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.ready], 1
    jne .fail_1

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.length], 4096
    jne .fail_2

    mov rax, [rel mapping + ASMWEB_MEMORY_MAPPING.base]
    test rax, rax
    jz .fail_1

    ; Base must be aligned to the supplied page size.
    mov rcx, rax
    and rcx, 4095
    jnz .fail_2

    ; Write both ends of the owned mapping.
    mov byte [rax], 0x5a
    mov byte [rax + 4095], 0xa5

    cmp byte [rax], 0x5a
    jne .fail_3

    cmp byte [rax + 4095], 0xa5
    jne .fail_3

    mov rbx, 0x2233445566778899

    lea rdi, [rel mapping]
    call asm_memory_unmap

    mov r10, rax

    mov rax, 0x2233445566778899
    cmp rbx, rax
    jne .fail_16

    test r10d, r10d
    jnz .fail_4

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.base], 0
    jne .fail_5

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.length], 0
    jne .fail_5

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.ready], 0
    jne .fail_5

    ; =======================================================================
    ; CASE 2 — 4097 bytes round to two pages.
    ; =======================================================================

    mov edi, 4097
    mov esi, 4096
    lea rdx, [rel mapping]
    call asm_memory_map_rw

    test eax, eax
    jnz .fail_6

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.length], 8192
    jne .fail_7

    mov rax, [rel mapping + ASMWEB_MEMORY_MAPPING.base]

    mov byte [rax], 0x11
    mov byte [rax + 4096], 0x22
    mov byte [rax + 8191], 0x33

    cmp byte [rax], 0x11
    jne .fail_8

    cmp byte [rax + 4096], 0x22
    jne .fail_8

    cmp byte [rax + 8191], 0x33
    jne .fail_8

    lea rdi, [rel mapping]
    call asm_memory_unmap

    test eax, eax
    jnz .fail_9

    ; =======================================================================
    ; CASE 3 — zero request rejected.
    ; =======================================================================

    xor edi, edi
    mov esi, 4096
    lea rdx, [rel mapping]
    call asm_memory_map_rw

    cmp eax, 1
    jne .fail_10

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.ready], 0
    jne .fail_10

    ; =======================================================================
    ; CASE 4 — invalid page size rejected.
    ; =======================================================================

    mov edi, 1
    mov esi, 12288
    lea rdx, [rel mapping]
    call asm_memory_map_rw

    cmp eax, 1
    jne .fail_11

    ; =======================================================================
    ; CASE 5 — checked round-up overflow rejected.
    ; =======================================================================

    mov rdi, -1
    mov esi, 4096
    lea rdx, [rel mapping]
    call asm_memory_map_rw

    cmp eax, 1
    jne .fail_12

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.ready], 0
    jne .fail_12

    ; =======================================================================
    ; CASE 6 — NULL mapping destination rejected.
    ; =======================================================================

    mov edi, 4096
    mov esi, 4096
    xor edx, edx
    call asm_memory_map_rw

    cmp eax, 1
    jne .fail_13

    ; =======================================================================
    ; CASE 7 — NULL unmap state rejected.
    ; =======================================================================

    xor edi, edi
    call asm_memory_unmap

    cmp eax, 1
    jne .fail_14

    ; =======================================================================
    ; CASE 8 — non-empty destination is rejected without modification.
    ;
    ; The values deliberately look like a live record, but no mapping is
    ; actually associated with them. The purpose is to prove that acquisition
    ; performs no destructive overwrite and no mmap when state is non-empty.
    ; =======================================================================

    mov rax, 0x12345000
    mov [rel mapping + ASMWEB_MEMORY_MAPPING.base], rax
    mov qword [rel mapping + ASMWEB_MEMORY_MAPPING.length], 4096
    mov qword [rel mapping + ASMWEB_MEMORY_MAPPING.ready], 1

    mov rbx, 0x445566778899aabb
    mov r12, 0x5566778899aabbcc
    mov r13, 0x66778899aabbccdd

    mov edi, 4096
    mov esi, 4096
    lea rdx, [rel mapping]
    call asm_memory_map_rw

    mov r10, rax

    mov rax, 0x445566778899aabb
    cmp rbx, rax
    jne .fail_16

    mov rax, 0x5566778899aabbcc
    cmp r12, rax
    jne .fail_16

    mov rax, 0x66778899aabbccdd
    cmp r13, rax
    jne .fail_16

    cmp r10d, 1
    jne .fail_17

    mov rax, 0x12345000
    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.base], rax
    jne .fail_17

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.length], 4096
    jne .fail_17

    cmp qword [rel mapping + ASMWEB_MEMORY_MAPPING.ready], 1
    jne .fail_17

    ; Clear the synthetic record without calling unmap: it did not describe
    ; a real kernel mapping.
    mov qword [rel mapping + ASMWEB_MEMORY_MAPPING.base], 0
    mov qword [rel mapping + ASMWEB_MEMORY_MAPPING.length], 0
    mov qword [rel mapping + ASMWEB_MEMORY_MAPPING.ready], 0

    ; Guards must remain intact across the complete suite.
    cmp qword [rel guard_before], 0x11111111
    jne .fail_15

    cmp qword [rel guard_after], 0x22222222
    jne .fail_15

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
