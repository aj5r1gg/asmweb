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


%endif
