%ifndef ASMWEB_STALE_CANDIDATE_INC
%define ASMWEB_STALE_CANDIDATE_INC 1


; ===========================================================================
; M0 stale-reference qualification candidate
;
; Runtime & Memory v0.3 §23 permits index-plus-generation as the initial M0/M1
; candidate while explicitly deferring the final stale-reference mechanism.
;
; This include therefore defines a QUALIFICATION CANDIDATE, not a frozen
; production object-identity architecture.
;
; Candidate identity:
;
;   { object_class_id, slot_index, generation }
;
; The candidate is layered over ASMWEB_TYPED_POOL without changing the pool's
; raw-pointer API.
;
; Raw pointers remain valid only inside the existing lifetime-safe
; exclusive-owner scope.
;
; Durable/cross-lifetime candidate lookup additionally validates:
;
;   object class;
;   slot index;
;   current generation;
;   current slot ownership.
;
; Important non-claims:
;
;   - generation width is NOT finalized;
;   - this does NOT solve concurrent ABA;
;   - this does NOT establish concurrent reclamation safety;
;   - this does NOT define worker handoff;
;   - this does NOT replace the typed-pool API;
;   - this is NOT yet used by production runtime objects.
;
; The current 64-bit generation field exists only to qualify the candidate
; behaviour. Generation wrap is forbidden.
; ===========================================================================


; ---------------------------------------------------------------------------
; Candidate result vocabulary
;
; Values intentionally correspond to the existing resource-result classes:
;
;   OK         = operation/lookup succeeded;
;   REJECTED   = stale/invalid candidate reference or bounded generation
;                refusal; internal integrity remains intact;
;   INTEGRITY  = candidate/pool accounting or representation is contradictory.
; ---------------------------------------------------------------------------

%define ASMWEB_STALE_RESULT_OK         0
%define ASMWEB_STALE_RESULT_REJECTED   1
%define ASMWEB_STALE_RESULT_INTEGRITY  2


; ---------------------------------------------------------------------------
; ASMWEB_STALE_HANDLE
;
; This is the candidate durable identity presented to lookup/release.
;
; object_class_id:
;   Stable non-zero object-class identity.
;
; slot_index:
;   Zero-based slot identity within the represented typed pool.
;
; generation:
;   Non-zero lifetime generation for that slot.
; ---------------------------------------------------------------------------

struc ASMWEB_STALE_HANDLE
    .object_class_id: resq 1
    .slot_index:      resq 1
    .generation:      resq 1
endstruc


; ---------------------------------------------------------------------------
; ASMWEB_STALE_CANDIDATE
;
; pool_ptr:
;   Underlying validated ASMWEB_TYPED_POOL.
;
; object_class_id:
;   Cached class identity. Must equal the pool class.
;
; generation_base:
;   Caller-provided contiguous uint64 generation array.
;
; generation_count:
;   Exactly one generation entry per physical pool slot for this candidate.
;
; generation_bytes:
;   generation_count * 8.
;
; management_bytes_total:
;   sizeof(ASMWEB_STALE_CANDIDATE) + generation_bytes.
;
; This is candidate-specific management cost. It SHALL remain visible in any
; qualification accounting using this candidate.
;
; ready:
;   Publication marker, written last.
; ---------------------------------------------------------------------------

struc ASMWEB_STALE_CANDIDATE
    .pool_ptr:                resq 1
    .object_class_id:         resq 1

    .generation_base:         resq 1
    .generation_count:        resq 1
    .generation_bytes:        resq 1
    .management_bytes_total:  resq 1

    .ready:                   resq 1
endstruc


%endif
