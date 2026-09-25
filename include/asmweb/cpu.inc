%ifndef ASMWEB_CPU_INC
%define ASMWEB_CPU_INC

; ---------------------------------------------------------------------------
; M0 CPU discovery state
; ---------------------------------------------------------------------------
;
; Feature bits represent hardware/OS state discovered once during bootstrap.
;
; Raw AVX advertisement and usable AVX execution state are deliberately
; separate concepts.
;
; AVX_USABLE requires:
;
;   - CPUID AVX;
;   - CPUID OSXSAVE;
;   - XCR0.XMM = 1;
;   - XCR0.YMM = 1.
;
; Raw AVX2 means only that CPUID leaf 7 advertises AVX2. Code wishing to
; execute AVX2 must also require ASMWEB_CPU_FEATURE_AVX_USABLE.

%define ASMWEB_CPU_FEATURE_SSE2        0
%define ASMWEB_CPU_FEATURE_SSSE3       1
%define ASMWEB_CPU_FEATURE_SSE41       2
%define ASMWEB_CPU_FEATURE_SSE42       3
%define ASMWEB_CPU_FEATURE_AVX         4
%define ASMWEB_CPU_FEATURE_AVX2        5
%define ASMWEB_CPU_FEATURE_BMI1        6
%define ASMWEB_CPU_FEATURE_BMI2        7
%define ASMWEB_CPU_FEATURE_AESNI       8
%define ASMWEB_CPU_FEATURE_RDRAND      9
%define ASMWEB_CPU_FEATURE_RDSEED      10
%define ASMWEB_CPU_FEATURE_OSXSAVE     11
%define ASMWEB_CPU_FEATURE_AVX_USABLE  12

struc ASMWEB_CPU_INFO
    ; CPUID vendor string is EBX, EDX, ECX from leaf zero.
    .vendor_0:       resd 1
    .vendor_1:       resd 1
    .vendor_2:       resd 1
    .vendor_pad:     resd 1

    .max_basic:      resd 1
    .max_extended:   resd 1
    .reserved_0:     resq 1

    .features:       resq 1
    .xcr0:           resq 1
    .ready:          resq 1
endstruc

%endif
