%ifndef ASMWEB_PROCESS_RUNTIME_INC
%define ASMWEB_PROCESS_RUNTIME_INC 1


; ===========================================================================
; Process lifecycle state
;
; Requirements & Scope v0.3:
;   STARTING
;   READY
;   PRESSURED
;   DRAINING
;   STOPPING
;
; Pressure is retained here because it is part of the requirements-level
; process lifecycle vocabulary. Later pressure machinery may additionally
; carry the richer runtime pressure classification.
; ===========================================================================

%define ASMWEB_PROCESS_STATE_STARTING   1
%define ASMWEB_PROCESS_STATE_READY      2
%define ASMWEB_PROCESS_STATE_PRESSURED  3
%define ASMWEB_PROCESS_STATE_DRAINING   4
%define ASMWEB_PROCESS_STATE_STOPPING   5

%define ASMWEB_PROCESS_STATE_MIN ASMWEB_PROCESS_STATE_STARTING
%define ASMWEB_PROCESS_STATE_MAX ASMWEB_PROCESS_STATE_STOPPING


; ===========================================================================
; Runtime & memory epoch
;
; Runtime & Memory v0.3:
;   INITIALISATION
;   STEADY_STATE
;   DRAINING
;   STOPPING
; ===========================================================================

%define ASMWEB_MEMORY_EPOCH_INITIALISATION 1
%define ASMWEB_MEMORY_EPOCH_STEADY_STATE   2
%define ASMWEB_MEMORY_EPOCH_DRAINING       3
%define ASMWEB_MEMORY_EPOCH_STOPPING       4

%define ASMWEB_MEMORY_EPOCH_MIN ASMWEB_MEMORY_EPOCH_INITIALISATION
%define ASMWEB_MEMORY_EPOCH_MAX ASMWEB_MEMORY_EPOCH_STOPPING


; ===========================================================================
; Process runtime object
;
; lifecycle_state:
;   Requirements-level process lifecycle state.
;
; memory_epoch:
;   Runtime & Memory allocation/provisioning epoch.
;
; ready:
;   Publication/admission marker. This is intentionally explicit rather than
;   inferred from lifecycle alone so later READY publication machinery can
;   enforce startup atomicity.
;
; initialised:
;   Structural object initialisation marker.
;
; generation:
;   Process-runtime publication generation. M0 begins at generation 1.
;   Dynamic capacity reconfiguration remains out of scope for v1 unless later
;   explicitly introduced.
;
; transition_count:
;   Bounded historical count of controlled lifecycle publications/transitions.
;   M0 initialisation begins at zero. The READY publication gate increments
;   this count exactly once on successful STARTING -> READY publication.
; ===========================================================================

struc ASMWEB_PROCESS_RUNTIME
    .lifecycle_state:  resq 1
    .memory_epoch:     resq 1
    .ready:            resq 1
    .initialised:      resq 1
    .generation:       resq 1
    .transition_count: resq 1
endstruc


; ===========================================================================
; READY publication gate
;
; asm_process_runtime_publish_ready is the controlled M0 publication boundary.
;
; It may publish READY only from the canonical initial process state:
;
;   lifecycle_state  = STARTING
;   memory_epoch     = INITIALISATION
;   ready            = 0
;   initialised      = 1
;   generation       != 0
;
; Before publication it requires:
;
;   - the process-runtime object itself is valid;
;   - the supplied OLR/MOT/RCT registry set validates;
;   - M_direct_capacity_max can be derived from the authoritative MOT;
;   - the startup-memory account validates;
;   - transition_count can be incremented without overflow.
;
; Publication is failure-atomic at the logical API boundary: no READY-state
; field is mutated until every prerequisite has succeeded.
;
; The gate does NOT currently prove that every startup-only temporary
; allocation has been reclaimed. The startup account does not yet classify
; retained bytes as temporary versus legitimate persistent steady-state state.
; ===========================================================================


%endif
