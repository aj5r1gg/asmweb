bits 64

%include "asmweb/memory.inc"
%include "asmweb/resource.inc"
%include "asmweb/stack.inc"

global _start

extern asm_mapping_capacity_init
extern asm_stack_provision
extern asm_stack_release
extern asm_linux_exit

section .bss

align 8
capacity:
    resb ASMWEB_MAPPING_CAPACITY_size

request:
    resb ASMWEB_STACK_REQUEST_size

stack_a:
    resb ASMWEB_STACK_size

stack_b:
    resb ASMWEB_STACK_size


section .text

; ===========================================================================
; Guarded-stack provisioning qualification
;
; Configuration authority used only by this qualification:
;
;   mapping count capacity = 2
;   mapped byte capacity   = 32768
;   page size              = 4096
;
; No production stack-size policy is established here.
;
; Exit status:
;
;   0  PASS
;   1  mapping-capacity init failed
;   2  two-sided guarded stack provision failed
;   3  two-sided descriptor geometry invalid
;   4  usable stack memory inaccessible/corrupt
;   5  release failed
;   6  release did not restore quiescence
;   7  one-sided guard provision failed
;   8  one-sided descriptor geometry invalid
;   9  invalid owner accepted
;   10 invalid usable size accepted
;   11 invalid expected maximum accepted
;   12 invalid page size accepted
;   13 arithmetic overflow accepted
;   14 capacity exhaustion classification/state invalid
;   15 non-pristine destination accepted or mutated
;   16 NULL request semantics failed
;   17 NULL capacity semantics failed
;   18 NULL destination semantics failed
;   19 double release not classified as integrity failure
; ===========================================================================

_start:
    cld


    ; -----------------------------------------------------------------------
    ; Initialise mapping authority.
    ; -----------------------------------------------------------------------

    mov edi, 2
    mov esi, 32768
    mov edx, 4096
    lea rcx, [rel capacity]

    call asm_mapping_capacity_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    ; =======================================================================
    ; CASE 1 — two-sided guards, 8192 usable bytes
    ; =======================================================================

    mov qword [rel request + ASMWEB_STACK_REQUEST.owner_id], 0x1001
    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], 8192
    mov qword [rel request + ASMWEB_STACK_REQUEST.low_guard_pages], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.high_guard_pages], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.expected_max_use_bytes], 4096
    mov qword [rel request + ASMWEB_STACK_REQUEST.page_size], 4096

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    cmp qword [rel stack_a + ASMWEB_STACK.ready], 1
    jne .fail_3

    cmp qword [rel stack_a + ASMWEB_STACK.owner_id], 0x1001
    jne .fail_3

    cmp qword [rel stack_a + ASMWEB_STACK.mapping + ASMWEB_MEMORY_MAPPING.ready], 1
    jne .fail_3

    cmp qword [rel stack_a + ASMWEB_STACK.mapping + ASMWEB_MEMORY_MAPPING.length], 16384
    jne .fail_3

    cmp qword [rel stack_a + ASMWEB_STACK.usable_bytes], 8192
    jne .fail_3

    cmp qword [rel stack_a + ASMWEB_STACK.low_guard_bytes], 4096
    jne .fail_3

    cmp qword [rel stack_a + ASMWEB_STACK.high_guard_bytes], 4096
    jne .fail_3

    cmp qword [rel stack_a + ASMWEB_STACK.expected_max_use_bytes], 4096
    jne .fail_3

    cmp qword [rel stack_a + ASMWEB_STACK.guard_policy], \
        ASMWEB_STACK_GUARD_LOW | ASMWEB_STACK_GUARD_HIGH
    jne .fail_3

    mov rax, [rel stack_a + ASMWEB_STACK.mapping + ASMWEB_MEMORY_MAPPING.base]
    add rax, 4096

    cmp rax, [rel stack_a + ASMWEB_STACK.usable_base]
    jne .fail_3

    add rax, 8192

    cmp rax, [rel stack_a + ASMWEB_STACK.stack_top]
    jne .fail_3

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 1
    jne .fail_3

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 16384
    jne .fail_3


    ; Usable stack range must remain writable.

    mov rax, [rel stack_a + ASMWEB_STACK.usable_base]

    mov byte [rax], 0x5a
    mov byte [rax + 8191], 0xa5

    cmp byte [rax], 0x5a
    jne .fail_4

    cmp byte [rax + 8191], 0xa5
    jne .fail_4


    ; =======================================================================
    ; CASE 2 — release returns mapping authority to quiescence
    ; =======================================================================

    lea rdi, [rel capacity]
    lea rsi, [rel stack_a]

    call asm_stack_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 0
    jne .fail_6

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 0
    jne .fail_6

    lea rax, [rel stack_a]
    xor ecx, ecx

.check_stack_a_zero:
    cmp rcx, ASMWEB_STACK_size / 8
    jae .case_3

    cmp qword [rax + rcx * 8], 0
    jne .fail_6

    inc rcx
    jmp .check_stack_a_zero


    ; =======================================================================
    ; CASE 3 — one low guard, 1 requested byte -> 4096 usable
    ; =======================================================================

.case_3:

    mov qword [rel request + ASMWEB_STACK_REQUEST.owner_id], 0x1002
    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.low_guard_pages], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.high_guard_pages], 0
    mov qword [rel request + ASMWEB_STACK_REQUEST.expected_max_use_bytes], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.page_size], 4096

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_7

    cmp qword [rel stack_a + ASMWEB_STACK.usable_bytes], 4096
    jne .fail_8

    cmp qword [rel stack_a + ASMWEB_STACK.low_guard_bytes], 4096
    jne .fail_8

    cmp qword [rel stack_a + ASMWEB_STACK.high_guard_bytes], 0
    jne .fail_8

    cmp qword [rel stack_a + ASMWEB_STACK.guard_policy], \
        ASMWEB_STACK_GUARD_LOW
    jne .fail_8

    cmp qword [rel stack_a + ASMWEB_STACK.mapping + ASMWEB_MEMORY_MAPPING.length], 8192
    jne .fail_8

    lea rdi, [rel capacity]
    lea rsi, [rel stack_a]

    call asm_stack_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5


    ; =======================================================================
    ; CASE 4 — zero owner rejected
    ; =======================================================================

    mov qword [rel request + ASMWEB_STACK_REQUEST.owner_id], 0
    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], 4096
    mov qword [rel request + ASMWEB_STACK_REQUEST.low_guard_pages], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.high_guard_pages], 0
    mov qword [rel request + ASMWEB_STACK_REQUEST.expected_max_use_bytes], 1024
    mov qword [rel request + ASMWEB_STACK_REQUEST.page_size], 4096

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9


    ; =======================================================================
    ; CASE 5 — zero usable size rejected
    ; =======================================================================

    mov qword [rel request + ASMWEB_STACK_REQUEST.owner_id], 0x1003
    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], 0

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10


    ; =======================================================================
    ; CASE 6 — expected maximum cannot exceed rounded usable capacity
    ; =======================================================================

    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], 4096
    mov qword [rel request + ASMWEB_STACK_REQUEST.expected_max_use_bytes], 4097

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11


    ; =======================================================================
    ; CASE 7 — invalid page size rejected
    ; =======================================================================

    mov qword [rel request + ASMWEB_STACK_REQUEST.expected_max_use_bytes], 1024
    mov qword [rel request + ASMWEB_STACK_REQUEST.page_size], 12288

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12


    ; =======================================================================
    ; CASE 8 — usable-size round-up overflow rejected
    ; =======================================================================

    mov qword [rel request + ASMWEB_STACK_REQUEST.page_size], 4096
    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], -1
    mov qword [rel request + ASMWEB_STACK_REQUEST.expected_max_use_bytes], 1

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13


    ; =======================================================================
    ; CASE 9 — valid request exceeding configured mapped-byte capacity
    ; =======================================================================

    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], 32768
    mov qword [rel request + ASMWEB_STACK_REQUEST.low_guard_pages], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.high_guard_pages], 0
    mov qword [rel request + ASMWEB_STACK_REQUEST.expected_max_use_bytes], 4096

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_EXHAUSTED
    jne .fail_14

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_count], 0
    jne .fail_14

    cmp qword [rel capacity + ASMWEB_MAPPING_CAPACITY.current_bytes], 0
    jne .fail_14

    cmp qword [rel stack_a + ASMWEB_STACK.mapping + ASMWEB_MEMORY_MAPPING.ready], 0
    jne .fail_14


    ; =======================================================================
    ; CASE 10 — non-pristine destination rejected without overwrite
    ; =======================================================================

    mov qword [rel stack_a + ASMWEB_STACK.owner_id], 0xabcdef

    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], 4096

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15

    cmp qword [rel stack_a + ASMWEB_STACK.owner_id], 0xabcdef
    jne .fail_15

    mov qword [rel stack_a + ASMWEB_STACK.owner_id], 0


    ; =======================================================================
    ; CASE 11 — NULL request
    ; =======================================================================

    xor edi, edi
    lea rsi, [rel capacity]
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    ; =======================================================================
    ; CASE 12 — NULL capacity
    ; =======================================================================

    lea rdi, [rel request]
    xor esi, esi
    lea rdx, [rel stack_a]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17


    ; =======================================================================
    ; CASE 13 — NULL destination
    ; =======================================================================

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    xor edx, edx

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_18


    ; =======================================================================
    ; CASE 14 — double release is integrity failure
    ; =======================================================================

    mov qword [rel request + ASMWEB_STACK_REQUEST.owner_id], 0x1004
    mov qword [rel request + ASMWEB_STACK_REQUEST.usable_bytes], 4096
    mov qword [rel request + ASMWEB_STACK_REQUEST.low_guard_pages], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.high_guard_pages], 1
    mov qword [rel request + ASMWEB_STACK_REQUEST.expected_max_use_bytes], 1024
    mov qword [rel request + ASMWEB_STACK_REQUEST.page_size], 4096

    lea rdi, [rel request]
    lea rsi, [rel capacity]
    lea rdx, [rel stack_b]

    call asm_stack_provision

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2

    lea rdi, [rel capacity]
    lea rsi, [rel stack_b]

    call asm_stack_release

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_5

    lea rdi, [rel capacity]
    lea rsi, [rel stack_b]

    call asm_stack_release

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_19


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

.fail_18:
    mov edi, 18
    call asm_linux_exit
    ud2

.fail_19:
    mov edi, 19
    call asm_linux_exit
    ud2
