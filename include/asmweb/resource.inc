%ifndef ASMWEB_RESOURCE_INC
%define ASMWEB_RESOURCE_INC

; ---------------------------------------------------------------------------
; Runtime resource result classes
; ---------------------------------------------------------------------------
;
; OK:
;   Operation completed.
;
; EXHAUSTED:
;   Ordinary bounded refusal or underlying acquisition failure.
;   Runtime integrity remains intact.
;
; INTEGRITY:
;   Internal ownership/accounting state is contradictory.
;   This is not ordinary resource exhaustion.

%define ASMWEB_RESOURCE_OK         0
%define ASMWEB_RESOURCE_EXHAUSTED  1
%define ASMWEB_RESOURCE_INTEGRITY  2

; ---------------------------------------------------------------------------
; M0 mapping-capacity state
; ---------------------------------------------------------------------------
;
; This is process runtime state intended to become the occupancy source for
; the authoritative mapping/VMA RCT entry.
;
; It distinguishes:
;
;   configured capacity
;   current occupancy
;   high-water occupancy
;   acquisition count
;   release count
;   bounded rejection count
;
; It is NOT itself the complete RCT schema.

struc ASMWEB_MAPPING_CAPACITY
    .configured_count:     resq 1
    .configured_bytes:     resq 1

    .current_count:        resq 1
    .current_bytes:        resq 1

    .high_water_count:     resq 1
    .high_water_bytes:     resq 1

    .acquisition_count:    resq 1
    .release_count:        resq 1
    .rejection_count:      resq 1

    .page_size:            resq 1
    .ready:                resq 1
endstruc

%endif
