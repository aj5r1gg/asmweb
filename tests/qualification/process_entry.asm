bits 64

%include "asmweb/startup.inc"
%include "linux/auxv.inc"

global _start

extern asm_linux_parse_process_entry
extern asm_linux_exit

section .bss

align 8
test_startup_info:
    resb ASMWEB_STARTUP_INFO_size

section .rodata

; ---------------------------------------------------------------------------
; Case 1
;
; Minimal valid process-entry stack:
;
;   argc = 1
;   argv[0]
;   argv terminator
;   empty environment
;   AT_PAGESZ
;   AT_RANDOM
;   AT_NULL
; ---------------------------------------------------------------------------

align 8
case_1_valid_minimal:
    dq 1
    dq 0x11111111
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x123456789abcdef0
    dq LINUX_AT_NULL, 0

; ---------------------------------------------------------------------------
; Case 2
;
; Valid process-entry stack with:
;
;   argc = 3
;   three argv entries
;   two environment entries
;   AT_RANDOM before AT_PAGESZ
; ---------------------------------------------------------------------------

align 8
case_2_valid_args_env:
    dq 3
    dq 0x11111111
    dq 0x22222222
    dq 0x33333333
    dq 0
    dq 0x44444444
    dq 0x55555555
    dq 0
    dq LINUX_AT_RANDOM, 0x0fedcba987654321
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_NULL, 0

; ---------------------------------------------------------------------------
; Case 3
;
; Invalid argv termination.
;
; argc says one argv element, but argv[1] is not NULL.
; ---------------------------------------------------------------------------

align 8
case_3_missing_argv_null:
    dq 1
    dq 0x11111111
    dq 0x22222222
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

; ---------------------------------------------------------------------------
; Case 4
;
; Missing AT_PAGESZ.
; ---------------------------------------------------------------------------

align 8
case_4_missing_pagesz:
    dq 1
    dq 0x11111111
    dq 0
    dq 0
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

; ---------------------------------------------------------------------------
; Case 5
;
; Missing AT_RANDOM.
; ---------------------------------------------------------------------------

align 8
case_5_missing_random:
    dq 1
    dq 0x11111111
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_NULL, 0

; ---------------------------------------------------------------------------
; Case 6
;
; argc * 8 would overflow because the upper three bits are non-zero.
; The parser must reject this before using the calculated address.
; ---------------------------------------------------------------------------

align 8
case_6_argc_scale_overflow:
    dq 0x2000000000000000

; ---------------------------------------------------------------------------
; Case 7
;
; argc itself can be shifted left by three without losing bits, but adding
; the resulting offset to the real argv base address must overflow.
; ---------------------------------------------------------------------------

align 8
case_7_argv_pointer_overflow:
    dq 0x1fffffffffffffff

; ---------------------------------------------------------------------------
; Cases 8-10 — environment traversal boundary
;
; Contract:
;
;   MAX-1 entries = valid
;   MAX   entries = valid
;   MAX+1 entries = rejected
;
; argc = 0 gives:
;
;   argc
;   argv terminator
;   environment entries
;   environment terminator
;   valid auxv
; ---------------------------------------------------------------------------

align 8
case_8_env_max_minus_one:
    dq 0
    dq 0
    times (ASMWEB_M0_MAX_ENVP_ENTRIES - 1) dq 0x11111111
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_9_env_max:
    dq 0
    dq 0
    times ASMWEB_M0_MAX_ENVP_ENTRIES dq 0x11111111
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_10_env_max_plus_one:
    dq 0
    dq 0
    times (ASMWEB_M0_MAX_ENVP_ENTRIES + 1) dq 0x11111111
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

; ---------------------------------------------------------------------------
; Cases 11-13 — auxiliary-vector traversal boundary
;
; Contract:
;
;   MAX-1 non-NULL entries = valid
;   MAX   non-NULL entries = valid
;   MAX+1 non-NULL entries = rejected
;
; Dummy auxv type 1 entries are structurally valid but ignored by AsmWeb.
; AT_PAGESZ and AT_RANDOM are included as the final two required non-NULL
; entries in each valid fixture.
; ---------------------------------------------------------------------------

align 8
case_11_auxv_max_minus_one:
    dq 0
    dq 0
    dq 0
    times (ASMWEB_M0_MAX_AUXV_ENTRIES - 3) dq 1, 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_12_auxv_max:
    dq 0
    dq 0
    dq 0
    times (ASMWEB_M0_MAX_AUXV_ENTRIES - 2) dq 1, 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_13_auxv_max_plus_one:
    dq 0
    dq 0
    dq 0
    times (ASMWEB_M0_MAX_AUXV_ENTRIES - 1) dq 1, 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

; ---------------------------------------------------------------------------
; Cases 14-18 — page-size startup invariant
;
; Contract:
;
;   below minimum       = rejected
;   minimum             = accepted
;   non-power-of-two    = rejected
;   maximum             = accepted
;   above maximum       = rejected
; ---------------------------------------------------------------------------

align 8
case_14_pagesz_below_min:
    dq 0
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, 2048
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_15_pagesz_min:
    dq 0
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, ASMWEB_M0_MIN_PAGE_SIZE
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_16_pagesz_not_power_of_two:
    dq 0
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, 12288
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_17_pagesz_max:
    dq 0
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, ASMWEB_M0_MAX_PAGE_SIZE
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_18_pagesz_above_max:
    dq 0
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, 131072
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

; ---------------------------------------------------------------------------
; Cases 19-21 — argv traversal boundary
;
; Contract:
;
;   MAX-1 entries = valid
;   MAX   entries = valid
;   MAX+1 entries = rejected
;
; These fixtures contain real backing storage for all declared argv slots.
; This keeps qualification deterministic while proving the parser applies the
; explicit policy bound before accepting the vector.
; ---------------------------------------------------------------------------

align 8
case_19_argv_max_minus_one:
    dq ASMWEB_M0_MAX_ARGV_ENTRIES - 1
    times (ASMWEB_M0_MAX_ARGV_ENTRIES - 1) dq 0x11111111
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_20_argv_max:
    dq ASMWEB_M0_MAX_ARGV_ENTRIES
    times ASMWEB_M0_MAX_ARGV_ENTRIES dq 0x11111111
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

align 8
case_21_argv_max_plus_one:
    dq ASMWEB_M0_MAX_ARGV_ENTRIES + 1
    times (ASMWEB_M0_MAX_ARGV_ENTRIES + 1) dq 0x11111111
    dq 0
    dq 0
    dq LINUX_AT_PAGESZ, 4096
    dq LINUX_AT_RANDOM, 0x12345678
    dq LINUX_AT_NULL, 0

section .text

; ---------------------------------------------------------------------------
; Qualification entry
;
; Exit status:
;
;   0 = every qualification case passed
;   N = qualification case N failed
;
; The test executable deliberately uses the production process-entry parser
; and production Linux exit boundary.
; ---------------------------------------------------------------------------

_start:
    cld

    ; =======================================================================
    ; CASE 1 — minimal valid stack
    ; =======================================================================

    lea rdi, [rel case_1_valid_minimal]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_1

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.argc], 1
    jne .fail_1

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.env_count], 0
    jne .fail_1

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.auxv_count], 2
    jne .fail_1

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.page_size], 4096
    jne .fail_1

    mov rax, 0x123456789abcdef0
    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.at_random], rax
    jne .fail_1

    ; =======================================================================
    ; CASE 2 — valid argv/environment and reversed auxv order
    ; =======================================================================

    lea rdi, [rel case_2_valid_args_env]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_2

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.argc], 3
    jne .fail_2

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.env_count], 2
    jne .fail_2

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.auxv_count], 2
    jne .fail_2

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.page_size], 4096
    jne .fail_2

    mov rax, 0x0fedcba987654321
    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.at_random], rax
    jne .fail_2

    ; =======================================================================
    ; CASE 3 — missing argv terminator
    ; =======================================================================

    lea rdi, [rel case_3_missing_argv_null]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_3

    ; =======================================================================
    ; CASE 4 — missing AT_PAGESZ
    ; =======================================================================

    lea rdi, [rel case_4_missing_pagesz]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_4

    ; =======================================================================
    ; CASE 5 — missing AT_RANDOM
    ; =======================================================================

    lea rdi, [rel case_5_missing_random]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_5

    ; =======================================================================
    ; CASE 6 — argc scale overflow
    ; =======================================================================

    lea rdi, [rel case_6_argc_scale_overflow]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_6

    ; =======================================================================
    ; CASE 7 — argv pointer addition overflow
    ; =======================================================================

    lea rdi, [rel case_7_argv_pointer_overflow]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_7

    ; =======================================================================
    ; CASE 8 — environment MAX-1 accepted
    ; =======================================================================

    lea rdi, [rel case_8_env_max_minus_one]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_8

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.env_count], \
        ASMWEB_M0_MAX_ENVP_ENTRIES - 1
    jne .fail_8

    ; =======================================================================
    ; CASE 9 — environment MAX accepted
    ; =======================================================================

    lea rdi, [rel case_9_env_max]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_9

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.env_count], \
        ASMWEB_M0_MAX_ENVP_ENTRIES
    jne .fail_9

    ; =======================================================================
    ; CASE 10 — environment MAX+1 rejected
    ; =======================================================================

    lea rdi, [rel case_10_env_max_plus_one]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_10

    ; env_count is only committed when the environment terminator is
    ; accepted. A traversal-cap failure must therefore leave it zero.
    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.env_count], 0
    jne .fail_10

    ; =======================================================================
    ; CASE 11 — auxv MAX-1 accepted
    ; =======================================================================

    lea rdi, [rel case_11_auxv_max_minus_one]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_11

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.auxv_count], \
        ASMWEB_M0_MAX_AUXV_ENTRIES - 1
    jne .fail_11

    ; =======================================================================
    ; CASE 12 — auxv MAX accepted
    ; =======================================================================

    lea rdi, [rel case_12_auxv_max]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_12

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.auxv_count], \
        ASMWEB_M0_MAX_AUXV_ENTRIES
    jne .fail_12

    ; =======================================================================
    ; CASE 13 — auxv MAX+1 rejected
    ; =======================================================================

    lea rdi, [rel case_13_auxv_max_plus_one]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_13

    ; auxv_count is committed only after AT_NULL is accepted.
    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.auxv_count], 0
    jne .fail_13

    ; =======================================================================
    ; CASE 14 — page size below minimum rejected
    ; =======================================================================

    lea rdi, [rel case_14_pagesz_below_min]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_14

    ; =======================================================================
    ; CASE 15 — minimum page size accepted
    ; =======================================================================

    lea rdi, [rel case_15_pagesz_min]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_15

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.page_size], \
        ASMWEB_M0_MIN_PAGE_SIZE
    jne .fail_15

    ; =======================================================================
    ; CASE 16 — non-power-of-two page size rejected
    ; =======================================================================

    lea rdi, [rel case_16_pagesz_not_power_of_two]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_16

    ; =======================================================================
    ; CASE 17 — maximum page size accepted
    ; =======================================================================

    lea rdi, [rel case_17_pagesz_max]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_17

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.page_size], \
        ASMWEB_M0_MAX_PAGE_SIZE
    jne .fail_17

    ; =======================================================================
    ; CASE 18 — page size above maximum rejected
    ; =======================================================================

    lea rdi, [rel case_18_pagesz_above_max]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_18

    ; =======================================================================
    ; CASE 19 — argv MAX-1 accepted
    ; =======================================================================

    lea rdi, [rel case_19_argv_max_minus_one]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_19

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.argc],         ASMWEB_M0_MAX_ARGV_ENTRIES - 1
    jne .fail_19

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.env_count], 0
    jne .fail_19

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.auxv_count], 2
    jne .fail_19

    ; =======================================================================
    ; CASE 20 — argv MAX accepted
    ; =======================================================================

    lea rdi, [rel case_20_argv_max]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    test eax, eax
    jnz .fail_20

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.argc],         ASMWEB_M0_MAX_ARGV_ENTRIES
    jne .fail_20

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.env_count], 0
    jne .fail_20

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.auxv_count], 2
    jne .fail_20

    ; =======================================================================
    ; CASE 21 — argv MAX+1 rejected
    ; =======================================================================

    lea rdi, [rel case_21_argv_max_plus_one]
    lea rsi, [rel test_startup_info]
    call asm_linux_parse_process_entry

    cmp eax, 1
    jne .fail_21

    ; Parsing must stop before environment or auxv traversal begins.
    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.env_count], 0
    jne .fail_21

    cmp qword [rel test_startup_info + ASMWEB_STARTUP_INFO.auxv_count], 0
    jne .fail_21

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

.fail_20:
    mov edi, 20
    call asm_linux_exit
    ud2

.fail_21:
    mov edi, 21
    call asm_linux_exit
    ud2
