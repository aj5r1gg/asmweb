bits 64

%include "asmweb/cpu.inc"

global _start

extern asm_cpu_discover
extern asm_linux_exit

section .bss

align 8
guard_before:
    resq 1

test_cpu_info:
    resb ASMWEB_CPU_INFO_size

guard_after:
    resq 1

section .text

; ---------------------------------------------------------------------------
; CPU discovery qualification
;
; Exit status:
;
;   0 = all checks passed
;   1 = discovery failed
;   2 = guard corruption
;   3 = leaf-0 identity mismatch
;   4 = extended-leaf mismatch
;   5 = feature bitmap mismatch
;   6 = XCR0 / AVX usability mismatch
;   7 = required SSE2 baseline missing
;   8 = NULL destination semantics failed
; ---------------------------------------------------------------------------

_start:
    cld

    mov qword [rel guard_before], 0x11111111
    mov qword [rel guard_after], 0x22222222

    lea rdi, [rel test_cpu_info]
    call asm_cpu_discover

    test eax, eax
    jnz .fail_1

    cmp qword [rel test_cpu_info + ASMWEB_CPU_INFO.ready], 1
    jne .fail_1

    ; -----------------------------------------------------------------------
    ; Destination guards.
    ; -----------------------------------------------------------------------

    cmp qword [rel guard_before], 0x11111111
    jne .fail_2

    cmp qword [rel guard_after], 0x22222222
    jne .fail_2

    ; -----------------------------------------------------------------------
    ; Leaf 0 exact identity.
    ; -----------------------------------------------------------------------

    xor eax, eax
    xor ecx, ecx
    cpuid

    cmp eax, dword [rel test_cpu_info + ASMWEB_CPU_INFO.max_basic]
    jne .fail_3

    cmp ebx, dword [rel test_cpu_info + ASMWEB_CPU_INFO.vendor_0]
    jne .fail_3

    cmp edx, dword [rel test_cpu_info + ASMWEB_CPU_INFO.vendor_1]
    jne .fail_3

    cmp ecx, dword [rel test_cpu_info + ASMWEB_CPU_INFO.vendor_2]
    jne .fail_3

    ; -----------------------------------------------------------------------
    ; Maximum extended leaf exact identity.
    ; -----------------------------------------------------------------------

    mov eax, 0x80000000
    xor ecx, ecx
    cpuid

    cmp eax, dword [rel test_cpu_info + ASMWEB_CPU_INFO.max_extended]
    jne .fail_4

    ; -----------------------------------------------------------------------
    ; Reconstruct expected feature bitmap directly from CPUID.
    ; -----------------------------------------------------------------------

    xor r8, r8

    mov eax, 1
    xor ecx, ecx
    cpuid

    mov r10d, ecx
    mov r11d, edx

    bt r11d, 26
    jnc .q_no_sse2
    bts r8, ASMWEB_CPU_FEATURE_SSE2
.q_no_sse2:

    bt r10d, 9
    jnc .q_no_ssse3
    bts r8, ASMWEB_CPU_FEATURE_SSSE3
.q_no_ssse3:

    bt r10d, 19
    jnc .q_no_sse41
    bts r8, ASMWEB_CPU_FEATURE_SSE41
.q_no_sse41:

    bt r10d, 20
    jnc .q_no_sse42
    bts r8, ASMWEB_CPU_FEATURE_SSE42
.q_no_sse42:

    bt r10d, 28
    jnc .q_no_avx
    bts r8, ASMWEB_CPU_FEATURE_AVX
.q_no_avx:

    bt r10d, 25
    jnc .q_no_aesni
    bts r8, ASMWEB_CPU_FEATURE_AESNI
.q_no_aesni:

    bt r10d, 30
    jnc .q_no_rdrand
    bts r8, ASMWEB_CPU_FEATURE_RDRAND
.q_no_rdrand:

    bt r10d, 27
    jnc .q_no_osxsave
    bts r8, ASMWEB_CPU_FEATURE_OSXSAVE
.q_no_osxsave:

    cmp dword [rel test_cpu_info + ASMWEB_CPU_INFO.max_basic], 7
    jb .q_after_leaf7

    mov eax, 7
    xor ecx, ecx
    cpuid

    bt ebx, 3
    jnc .q_no_bmi1
    bts r8, ASMWEB_CPU_FEATURE_BMI1
.q_no_bmi1:

    bt ebx, 5
    jnc .q_no_avx2
    bts r8, ASMWEB_CPU_FEATURE_AVX2
.q_no_avx2:

    bt ebx, 8
    jnc .q_no_bmi2
    bts r8, ASMWEB_CPU_FEATURE_BMI2
.q_no_bmi2:

    bt ebx, 18
    jnc .q_no_rdseed
    bts r8, ASMWEB_CPU_FEATURE_RDSEED
.q_no_rdseed:

.q_after_leaf7:

    ; -----------------------------------------------------------------------
    ; Derive expected XCR0 and AVX usability.
    ; -----------------------------------------------------------------------

    xor r9, r9

    bt r8, ASMWEB_CPU_FEATURE_OSXSAVE
    jnc .q_compare

    xor ecx, ecx
    xgetbv

    shl rdx, 32
    or rax, rdx
    mov r9, rax

    bt r8, ASMWEB_CPU_FEATURE_AVX
    jnc .q_compare

    mov r10, rax
    and r10, 0x6
    cmp r10, 0x6
    jne .q_compare

    bts r8, ASMWEB_CPU_FEATURE_AVX_USABLE

.q_compare:
    cmp r8, qword [rel test_cpu_info + ASMWEB_CPU_INFO.features]
    jne .fail_5

    cmp r9, qword [rel test_cpu_info + ASMWEB_CPU_INFO.xcr0]
    jne .fail_6

    ; If AVX_USABLE is set, all prerequisites must be visible.
    bt qword [rel test_cpu_info + ASMWEB_CPU_INFO.features], \
        ASMWEB_CPU_FEATURE_AVX_USABLE
    jnc .q_sse2

    bt qword [rel test_cpu_info + ASMWEB_CPU_INFO.features], \
        ASMWEB_CPU_FEATURE_AVX
    jnc .fail_6

    bt qword [rel test_cpu_info + ASMWEB_CPU_INFO.features], \
        ASMWEB_CPU_FEATURE_OSXSAVE
    jnc .fail_6

    mov rax, [rel test_cpu_info + ASMWEB_CPU_INFO.xcr0]
    and rax, 0x6
    cmp rax, 0x6
    jne .fail_6

.q_sse2:
    bt qword [rel test_cpu_info + ASMWEB_CPU_INFO.features], \
        ASMWEB_CPU_FEATURE_SSE2
    jnc .fail_7

    ; -----------------------------------------------------------------------
    ; NULL destination.
    ; -----------------------------------------------------------------------

    xor edi, edi
    call asm_cpu_discover

    cmp eax, 1
    jne .fail_8

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
