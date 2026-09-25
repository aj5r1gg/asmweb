%ifndef ASMWEB_MEMORY_INC
%define ASMWEB_MEMORY_INC

; ---------------------------------------------------------------------------
; M0 controlled memory mapping state
; ---------------------------------------------------------------------------
;
; A mapping record represents one live anonymous private mapping owned by
; AsmWeb.
;
; length is always page-aligned.
;
; M0 mappings created through this interface are:
;
;   readable
;   writable
;   non-executable
;   anonymous
;   private
;
; This is NOT yet:
;
;   - a general allocator;
;   - a pool implementation;
;   - an OLR/MOT/RCT implementation;
;   - a final memory-accounting interface.

struc ASMWEB_MEMORY_MAPPING
    .base:      resq 1
    .length:    resq 1
    .ready:     resq 1
endstruc

%endif
