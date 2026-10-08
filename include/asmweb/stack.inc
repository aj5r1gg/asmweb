%ifndef ASMWEB_STACK_INC
%define ASMWEB_STACK_INC

%include "asmweb/memory.inc"


; ===========================================================================
; M0 guarded-stack provisioning foundation
;
; This interface establishes stack provisioning mechanics without freezing
; final worker topology or final stack sizes.
;
; Exact stack sizes remain caller/configuration authority and require
; evidence before a production execution context depends upon them.
; ===========================================================================


; Guard-policy bits derived from the request.
;
; These describe which ends of the provisioned usable range are protected.
;
; x86-64 stacks conventionally grow toward lower addresses, therefore a low
; guard is the primary overflow guard. A high guard remains independently
; representable where a runtime design requires it.

%define ASMWEB_STACK_GUARD_LOW   0x1
%define ASMWEB_STACK_GUARD_HIGH  0x2


; ---------------------------------------------------------------------------
; Stack provisioning request
;
; owner_id:
;   Non-zero stable owner identity supplied by the caller.
;
; usable_bytes:
;   Requested minimum usable bytes. Provisioning rounds this upward to the
;   established runtime page size.
;
; low_guard_pages / high_guard_pages:
;   Guard-page counts. Zero is permitted because final guard policy belongs to
;   the eventual execution-context design. Non-zero guards are protected with
;   PROT_NONE before stack publication.
;
; expected_max_use_bytes:
;   Evidence-derived maximum expected/qualified stack use supplied by the
;   caller. It must be non-zero and no greater than actual rounded usable
;   capacity.
;
; page_size:
;   Established runtime page size.
; ---------------------------------------------------------------------------

struc ASMWEB_STACK_REQUEST
    .owner_id:               resq 1
    .usable_bytes:           resq 1
    .low_guard_pages:        resq 1
    .high_guard_pages:       resq 1
    .expected_max_use_bytes: resq 1
    .page_size:              resq 1
endstruc


; ---------------------------------------------------------------------------
; Provisioned stack descriptor
;
; mapping:
;   Exactly one owned mapping covering guards plus usable stack storage.
;
; usable_base:
;   Lowest accessible byte of usable stack storage.
;
; usable_bytes:
;   Actual rounded usable capacity.
;
; stack_top:
;   One-past-the-end address of usable stack storage. A downward-growing
;   execution context would establish its initial RSP from this boundary,
;   subject to the Internal ABI alignment contract.
;
; low_guard_bytes / high_guard_bytes:
;   Protected mapping ranges counted in total mapping capacity but excluded
;   from usable stack capacity.
;
; guard_policy:
;   ASMWEB_STACK_GUARD_* bitmask derived from non-zero guard-page counts.
;
; ready:
;   Published last. A ready stack has fully established mapping ownership and
;   all requested guard protections.
;
; A failed guard-protection operation attempts transactional mapping rollback.
; If kernel rollback itself fails, the embedded mapping record deliberately
; remains live so ownership is not lost; asm_stack_release can reclaim this
; unpublished recovery residue.
; ---------------------------------------------------------------------------

struc ASMWEB_STACK
    .owner_id:               resq 1
    .mapping:                resb ASMWEB_MEMORY_MAPPING_size
    .usable_base:            resq 1
    .usable_bytes:           resq 1
    .stack_top:              resq 1
    .low_guard_bytes:        resq 1
    .high_guard_bytes:       resq 1
    .expected_max_use_bytes: resq 1
    .guard_policy:           resq 1
    .ready:                  resq 1
endstruc

%endif
