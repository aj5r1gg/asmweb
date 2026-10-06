%ifndef ASMWEB_MEMORY_CEILING_INC
%define ASMWEB_MEMORY_CEILING_INC 1


; ===========================================================================
; Direct memory-capacity arithmetic
;
; Runtime & Memory v0.3 fixed-stride class formula:
;
;   payload_max = effective_stride_bytes * maximum_count
;
;   M_class =
;       payload_max
;     + pool_metadata_bytes
;     + mapping_overhead_bytes
;
; All arithmetic SHALL be checked.
;
; This M0 foundation operates on already-resolved uint64 quantities. It does
; not treat zero as an UNRESOLVED sentinel and does not perform registry,
; provenance, applicability or unit validation. Those belong to the governing
; registry/limit layers.
; ===========================================================================


; ===========================================================================
; Direct-capacity accumulation
;
; A bounded list of already-resolved direct-memory class contributions may be
; summed to form the arithmetic component of:
;
;   M_direct_capacity_max
;
; Applicability, registry state, shared/dependent backing relationships and
; provenance remain responsibilities of their governing layers.
;
; The M0 accumulation count is bounded by the existing MOT safety ceiling.
; ===========================================================================


; ===========================================================================
; MOT-derived direct-memory capacity
;
; asm_memory_direct_capacity_from_mot derives the arithmetic process ceiling
; directly from a bounded Maximum-Object Table projection.
;
; Only ACTIVE MOT entries contribute. Other valid lifecycle states are
; ignored. Invalid lifecycle values, malformed pointer/count state, per-class
; arithmetic failure or aggregate overflow fail deterministically.
;
; This routine derives from the authoritative MOT arithmetic operands:
;
;   effective_stride_bytes
;   maximum_count
;   pool_metadata_bytes
;   mapping_overhead_bytes
;
; It does not invent or consume a separately writable maximum_bytes value.
; ===========================================================================


%endif
