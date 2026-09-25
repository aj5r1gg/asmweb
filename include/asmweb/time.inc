%ifndef ASMWEB_TIME_INC
%define ASMWEB_TIME_INC

; ---------------------------------------------------------------------------
; M0 monotonic-time state
; ---------------------------------------------------------------------------
;
; sec/nsec preserve the normalized kernel CLOCK_MONOTONIC representation.
;
; total_ns is a checked convenience representation:
;
;     sec * 1,000,000,000 + nsec
;
; M0 rejects a sample if that conversion cannot be represented in 64 bits.

%define ASMWEB_NSEC_PER_SEC 1000000000

struc ASMWEB_MONOTONIC_TIME
    .sec:       resq 1
    .nsec:      resq 1
    .total_ns:  resq 1
    .ready:     resq 1
endstruc

%endif
