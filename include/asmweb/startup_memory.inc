%ifndef ASMWEB_STARTUP_MEMORY_INC
%define ASMWEB_STARTUP_MEMORY_INC


; ===========================================================================
; AsmWeb startup direct-memory accounting
;
; Runtime & Memory v0.3 defines:
;
;   M_startup_peak
;
; as the maximum direct registered memory expected during INITIALISATION.
;
; This M0 primitive tracks simultaneous registered startup memory:
;
;   current_bytes
;   peak_bytes
;
; It intentionally does not calculate M_startup_peak by summing every
; startup-only class. Different startup objects may have different and
; overlapping lifetimes; the required quantity is a high-water value.
;
; Startup orchestration is responsible for using this account only for the
; applicable INITIALISATION lifetime. Epoch enforcement is not performed by
; this arithmetic/accounting primitive itself.
; ===========================================================================


struc ASMWEB_STARTUP_MEMORY_ACCOUNT
    .current_bytes: resq 1
    .peak_bytes:    resq 1
    .initialised:   resq 1
endstruc


%endif
