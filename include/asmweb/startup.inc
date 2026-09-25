%ifndef ASMWEB_STARTUP_INC
%define ASMWEB_STARTUP_INC

; ---------------------------------------------------------------------------
; M0 bootstrap traversal bounds
; ---------------------------------------------------------------------------
;
; These are safety bounds for controlled initial-stack traversal.
;
; They are NOT yet final product limits.
; Final authoritative numerical limits will move to the
; Invariants & Limits Register.
;
; Until that registry exists, these values prevent raw unbounded scans.

%define ASMWEB_M0_MAX_ARGV_ENTRIES 4096
%define ASMWEB_M0_MAX_ENVP_ENTRIES 4096
%define ASMWEB_M0_MAX_AUXV_ENTRIES 256

; Provisional M0 page-size acceptance range.
;
; A discovered page size SHALL:
;
;   - be at least 4096 bytes;
;   - be no greater than 65536 bytes;
;   - be an exact power of two.
;
; These are M0 bootstrap safety limits, not yet final product limits.

%define ASMWEB_M0_MIN_PAGE_SIZE 4096
%define ASMWEB_M0_MAX_PAGE_SIZE 65536

; ---------------------------------------------------------------------------
; Startup information structure
; ---------------------------------------------------------------------------
;
; All fields are 64-bit.
;
; This is an initial M0 structure and is not yet declared ABI-stable.

struc ASMWEB_STARTUP_INFO
    .argc:          resq 1
    .argv:          resq 1
    .envp:          resq 1
    .auxv:          resq 1
    .page_size:     resq 1
    .at_random:     resq 1
    .env_count:     resq 1
    .auxv_count:    resq 1
endstruc

%endif
