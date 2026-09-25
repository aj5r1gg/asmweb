bits 64

%include "asmweb/abi.inc"
%include "asmweb/cpu.inc"

global asm_cpu_discover

section .text

; asm_cpu_discover
;
; Purpose:
;   Discover the CPU capabilities required by later AsmWeb runtime decisions.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Input:
;   RDI = pointer to writable ASMWEB_CPU_INFO
;
; Result:
;   RAX = 0 on success
;   RAX = 1 on failure
;
; Success:
;   Destination contains one immutable bootstrap snapshot of CPU state.
;
; Failure:
;   Destination is zeroed when destination is non-NULL.
;
; Notes:
;
;   CPUID clobbers EAX, EBX, ECX and EDX.
;
;   RBX is callee-saved under Internal ABI v1, therefore this function
;   explicitly preserves it.
;
;   XGETBV is executed only when CPUID advertises OSXSAVE.
;
;   AVX_USABLE is distinct from raw CPUID AVX advertisement.
;
; Resource acquisition:
;   None.
;
; Blocking:
;   No.
;
; Direction flag:
;   Clear on return.

asm_cpu_discover:
    cld

    test rdi, rdi
    jz .failure_no_destination

    mov rsi, rdi

    ; Deterministic destination state.
    xor eax, eax

    mov [rsi + ASMWEB_CPU_INFO.vendor_0], eax
    mov [rsi + ASMWEB_CPU_INFO.vendor_1], eax
    mov [rsi + ASMWEB_CPU_INFO.vendor_2], eax
    mov [rsi + ASMWEB_CPU_INFO.vendor_pad], eax

    mov [rsi + ASMWEB_CPU_INFO.max_basic], eax
    mov [rsi + ASMWEB_CPU_INFO.max_extended], eax
    mov qword [rsi + ASMWEB_CPU_INFO.reserved_0], 0

    mov qword [rsi + ASMWEB_CPU_INFO.features], 0
    mov qword [rsi + ASMWEB_CPU_INFO.xcr0], 0
    mov qword [rsi + ASMWEB_CPU_INFO.ready], 0

    ; CPUID destroys RBX.
    push rbx

    ; -----------------------------------------------------------------------
    ; CPUID leaf 0 — vendor and maximum basic leaf.
    ; -----------------------------------------------------------------------

    xor eax, eax
    xor ecx, ecx
    cpuid

    mov [rsi + ASMWEB_CPU_INFO.max_basic], eax
    mov [rsi + ASMWEB_CPU_INFO.vendor_0], ebx
    mov [rsi + ASMWEB_CPU_INFO.vendor_1], edx
    mov [rsi + ASMWEB_CPU_INFO.vendor_2], ecx

    ; M0 requires leaf 1.
    cmp eax, 1
    jb .failure

    ; -----------------------------------------------------------------------
    ; Maximum extended CPUID leaf.
    ; -----------------------------------------------------------------------

    mov eax, 0x80000000
    xor ecx, ecx
    cpuid

    mov [rsi + ASMWEB_CPU_INFO.max_extended], eax

    ; -----------------------------------------------------------------------
    ; CPUID leaf 1.
    ; -----------------------------------------------------------------------

    mov eax, 1
    xor ecx, ecx
    cpuid

    ; Preserve leaf-1 feature registers across later CPUID calls.
    mov r10d, ecx
    mov r11d, edx

    xor r8, r8

    bt r11d, 26
    jnc .no_sse2
    bts r8, ASMWEB_CPU_FEATURE_SSE2
.no_sse2:

    bt r10d, 9
    jnc .no_ssse3
    bts r8, ASMWEB_CPU_FEATURE_SSSE3
.no_ssse3:

    bt r10d, 19
    jnc .no_sse41
    bts r8, ASMWEB_CPU_FEATURE_SSE41
.no_sse41:

    bt r10d, 20
    jnc .no_sse42
    bts r8, ASMWEB_CPU_FEATURE_SSE42
.no_sse42:

    bt r10d, 28
    jnc .no_avx
    bts r8, ASMWEB_CPU_FEATURE_AVX
.no_avx:

    bt r10d, 25
    jnc .no_aesni
    bts r8, ASMWEB_CPU_FEATURE_AESNI
.no_aesni:

    bt r10d, 30
    jnc .no_rdrand
    bts r8, ASMWEB_CPU_FEATURE_RDRAND
.no_rdrand:

    bt r10d, 27
    jnc .no_osxsave
    bts r8, ASMWEB_CPU_FEATURE_OSXSAVE
.no_osxsave:

    ; -----------------------------------------------------------------------
    ; CPUID leaf 7, subleaf 0.
    ; -----------------------------------------------------------------------

    cmp dword [rsi + ASMWEB_CPU_INFO.max_basic], 7
    jb .after_leaf7

    mov eax, 7
    xor ecx, ecx
    cpuid

    bt ebx, 3
    jnc .no_bmi1
    bts r8, ASMWEB_CPU_FEATURE_BMI1
.no_bmi1:

    bt ebx, 5
    jnc .no_avx2
    bts r8, ASMWEB_CPU_FEATURE_AVX2
.no_avx2:

    bt ebx, 8
    jnc .no_bmi2
    bts r8, ASMWEB_CPU_FEATURE_BMI2
.no_bmi2:

    bt ebx, 18
    jnc .no_rdseed
    bts r8, ASMWEB_CPU_FEATURE_RDSEED
.no_rdseed:

.after_leaf7:

    ; -----------------------------------------------------------------------
    ; OS-enabled extended state.
    ;
    ; XGETBV is valid here only when OSXSAVE is advertised.
    ; -----------------------------------------------------------------------

    bt r8, ASMWEB_CPU_FEATURE_OSXSAVE
    jnc .store_features

    xor ecx, ecx
    xgetbv

    ; XGETBV returns EDX:EAX.
    shl rdx, 32
    or rax, rdx

    mov [rsi + ASMWEB_CPU_INFO.xcr0], rax

    ; AVX execution additionally requires raw AVX advertisement.
    bt r8, ASMWEB_CPU_FEATURE_AVX
    jnc .store_features

    ; XCR0 bit 1 = XMM state
    ; XCR0 bit 2 = YMM state
    mov r9, rax
    and r9, 0x6
    cmp r9, 0x6
    jne .store_features

    bts r8, ASMWEB_CPU_FEATURE_AVX_USABLE

.store_features:
    mov [rsi + ASMWEB_CPU_INFO.features], r8

    ; x86-64 M0 baseline requires SSE2.
    bt r8, ASMWEB_CPU_FEATURE_SSE2
    jnc .failure

    mov qword [rsi + ASMWEB_CPU_INFO.ready], 1

    pop rbx

    xor eax, eax
    ret

.failure:
    pop rbx

    ; Restore deterministic failure state.
    xor eax, eax

    mov [rsi + ASMWEB_CPU_INFO.vendor_0], eax
    mov [rsi + ASMWEB_CPU_INFO.vendor_1], eax
    mov [rsi + ASMWEB_CPU_INFO.vendor_2], eax
    mov [rsi + ASMWEB_CPU_INFO.vendor_pad], eax

    mov [rsi + ASMWEB_CPU_INFO.max_basic], eax
    mov [rsi + ASMWEB_CPU_INFO.max_extended], eax
    mov qword [rsi + ASMWEB_CPU_INFO.reserved_0], 0

    mov qword [rsi + ASMWEB_CPU_INFO.features], 0
    mov qword [rsi + ASMWEB_CPU_INFO.xcr0], 0
    mov qword [rsi + ASMWEB_CPU_INFO.ready], 0

    mov eax, 1
    ret

.failure_no_destination:
    mov eax, 1
    ret
