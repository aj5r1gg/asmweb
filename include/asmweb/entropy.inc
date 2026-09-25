%ifndef ASMWEB_ENTROPY_INC
%define ASMWEB_ENTROPY_INC

; ---------------------------------------------------------------------------
; M0 entropy bootstrap state
; ---------------------------------------------------------------------------
;
; Linux AT_RANDOM identifies 16 bytes of kernel-supplied startup randomness.
;
; M0 copies those 16 bytes into AsmWeb-owned storage and then invalidates
; the borrowed AT_RANDOM pointer in ASMWEB_STARTUP_INFO.
;
; This is bootstrap seed material only.
;
; It is NOT yet:
;
;   - the complete AsmWeb CSPRNG;
;   - a reusable entropy API;
;   - a final entropy-pool representation.

%define ASMWEB_AT_RANDOM_BYTES 16

struc ASMWEB_ENTROPY_BOOTSTRAP
    .seed_lo:    resq 1
    .seed_hi:    resq 1
    .ready:      resq 1
endstruc

%endif
