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
;
; A startup account begins numerically empty because the accounting object must
; first be structurally initialised. That zero state does NOT imply that the
; process has zero registered memory at that instant.
;
; asm_startup_memory_account_baseline reconciles direct registered memory that
; already exists when startup accounting becomes authoritative, including
; applicable process-persistent fixed state.
;
; Baseline establishment is distinct from acquisition:
;
;   baseline:
;       reconciles already-retained registered bytes;
;
;   acquire:
;       charges newly retained registered bytes after baseline establishment;
;
;   release:
;       removes bytes no longer retained while preserving historical peak.
;
; Baseline may be established only while:
;
;   initialised   = 1
;   current_bytes = 0
;   peak_bytes    = 0
;
; This prevents later rebasing from silently rewriting accounting history.
; ===========================================================================


struc ASMWEB_STARTUP_MEMORY_ACCOUNT
    .current_bytes: resq 1
    .peak_bytes:    resq 1
    .initialised:   resq 1
endstruc


%endif
