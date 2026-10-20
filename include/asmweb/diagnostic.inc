%ifndef ASMWEB_DIAGNOSTIC_INC
%define ASMWEB_DIAGNOSTIC_INC 1

; M0-DIAG-001 — fixed-size first-failure diagnostic latch.
;
; Engineering scope:
;   M0 READY-state runtime invariant integrity failures only.
;
; This is not an authoritative general diagnostics registry.
; It does not own resource accounting or telemetry.
;
; All fields are unsigned 64-bit integers.
; A zeroed object is pristine but not initialised.
;
; Publication:
;   published=0: no failure recorded; all data fields zero.
;   published=1: one valid failure record.
;
; ready is the initialisation marker.
; published is the final publication marker.
;
; No allocation, I/O, recursion, or shared global state.

%define ASMWEB_DIAG_DOMAIN_RUNTIME_INVARIANT  1
%define ASMWEB_DIAG_ORIGIN_READY_VALIDATOR    1

%define ASMWEB_DIAG_MIN_INVARIANT_CODE        1
%define ASMWEB_DIAG_MAX_INVARIANT_CODE        11

struc ASMWEB_DIAGNOSTIC
    .domain:           resq 1
    .classification:   resq 1
    .origin:           resq 1
    .local_code:       resq 1
    .published:        resq 1
    .ready:            resq 1
endstruc

; asm_diagnostic_init
;   RDI = pointer to pristine ASMWEB_DIAGNOSTIC
;   RAX = ASMWEB_RESOURCE_OK or ASMWEB_RESOURCE_INTEGRITY
;
; asm_diagnostic_validate
;   RDI = pointer to ASMWEB_DIAGNOSTIC
;   RAX = ASMWEB_RESOURCE_OK or ASMWEB_RESOURCE_INTEGRITY
;
; asm_diagnostic_record_invariant
;   RDI = pointer to initialised ASMWEB_DIAGNOSTIC
;   RSI = ASMWEB_RUNTIME_INVARIANT_FAIL_* code, 1..11
;   RAX = ASMWEB_RESOURCE_OK or ASMWEB_RESOURCE_INTEGRITY
;
; The recording function accepts only a first failure.
; Failed operations do not change a coherent destination.
; No function reads beyond the fixed structure.

%endif
