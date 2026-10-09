%ifndef ASMWEB_TELEMETRY_INC
%define ASMWEB_TELEMETRY_INC 1


; ===========================================================================
; AsmWeb M0 telemetry foundation
;
; Design rule:
;
;   telemetry observes;
;   subsystem authorities account.
;
; This object is therefore NOT the ownership/accounting authority for:
;
;   - direct-memory capacity;
;   - startup-memory occupancy or peak;
;   - process lifecycle transitions;
;   - mapping occupancy/history;
;   - pool occupancy/history;
;   - quiescence classification.
;
; Those values remain owned by their governing runtime objects.
;
; ASMWEB_RUNTIME_TELEMETRY contains the most recently committed validated
; snapshot of those authorities plus explicitly recorded RSS observations.
;
; No snapshot field may be used to drive resource admission or ownership.
; ===========================================================================


; ---------------------------------------------------------------------------
; Optional-source presence mask.
; ---------------------------------------------------------------------------

%define ASMWEB_TELEMETRY_SOURCE_MAPPING     (1 << 0)
%define ASMWEB_TELEMETRY_SOURCE_POOL        (1 << 1)
%define ASMWEB_TELEMETRY_SOURCE_QUIESCENCE  (1 << 2)

%define ASMWEB_TELEMETRY_SOURCE_MASK_ALL \
    (ASMWEB_TELEMETRY_SOURCE_MAPPING | \
     ASMWEB_TELEMETRY_SOURCE_POOL | \
     ASMWEB_TELEMETRY_SOURCE_QUIESCENCE)


; ---------------------------------------------------------------------------
; RSS observation phases.
;
; M0 deliberately separates telemetry storage from the future Linux RSS
; provider. A caller may record observations only when it actually has a
; trustworthy RSS byte measurement.
;
; INITIAL:
;   first process RSS observation; may be committed once.
;
; SAMPLE:
;   intermediate observation; updates historical maximum if larger.
;
; FINAL:
;   terminal process RSS observation; may be committed once.
;
; Every successful observation contributes to rss_max_bytes.
; ---------------------------------------------------------------------------

%define ASMWEB_TELEMETRY_RSS_PHASE_INITIAL  1
%define ASMWEB_TELEMETRY_RSS_PHASE_SAMPLE   2
%define ASMWEB_TELEMETRY_RSS_PHASE_FINAL    3

%define ASMWEB_TELEMETRY_RSS_SEEN_INITIAL   (1 << 0)
%define ASMWEB_TELEMETRY_RSS_SEEN_FINAL     (1 << 1)

%define ASMWEB_TELEMETRY_RSS_SEEN_MASK_ALL \
    (ASMWEB_TELEMETRY_RSS_SEEN_INITIAL | \
     ASMWEB_TELEMETRY_RSS_SEEN_FINAL)


; ---------------------------------------------------------------------------
; ASMWEB_TELEMETRY_VIEW
;
; Mandatory:
;
;   registry_ptr
;   startup_memory_ptr
;   process_runtime_ptr
;
; Optional:
;
;   mapping_capacity_ptr
;   pool_ptr
;   quiescence_ptr
;
; NULL means the corresponding subsystem does not yet exist in the runtime
; topology being observed. Telemetry must not fabricate zero-valued subsystem
; metrics and pretend that they were observed; source_present records exactly
; which optional authorities were supplied.
; ---------------------------------------------------------------------------

struc ASMWEB_TELEMETRY_VIEW
    .registry_ptr:          resq 1
    .startup_memory_ptr:    resq 1
    .process_runtime_ptr:   resq 1

    .mapping_capacity_ptr:  resq 1
    .pool_ptr:              resq 1
    .quiescence_ptr:        resq 1
endstruc


; ---------------------------------------------------------------------------
; ASMWEB_RUNTIME_TELEMETRY
;
; snapshot_count:
;   Number of successfully committed aggregate snapshots.
;   Historical, monotonically increasing, never wraps.
;
; source_present:
;   ASMWEB_TELEMETRY_SOURCE_* bitmask for the current snapshot.
;
; Mandatory snapshot:
;
;   direct_capacity_max
;   startup_current_bytes
;   startup_peak_bytes
;   lifecycle_state
;   memory_epoch
;   transition_count
;
; Mapping snapshot:
;
;   copied only when SOURCE_MAPPING is present.
;
; Pool snapshot:
;
;   copied only when SOURCE_POOL is present.
;
; Quiescence snapshot:
;
;   copied only when SOURCE_QUIESCENCE is present.
;
; RSS state:
;
;   independent of aggregate snapshots.
;   A zero rss_seen_mask means no RSS measurement has been supplied.
;
; ready:
;   structural publication marker, written last by init.
; ---------------------------------------------------------------------------

struc ASMWEB_RUNTIME_TELEMETRY
    .snapshot_count:              resq 1
    .source_present:              resq 1

    ; Mandatory runtime snapshot.
    .direct_capacity_max:         resq 1
    .startup_current_bytes:       resq 1
    .startup_peak_bytes:          resq 1

    .lifecycle_state:             resq 1
    .memory_epoch:                resq 1
    .transition_count:            resq 1

    ; Mapping capacity snapshot.
    .mapping_configured_count:    resq 1
    .mapping_configured_bytes:    resq 1
    .mapping_current_count:       resq 1
    .mapping_current_bytes:       resq 1
    .mapping_high_water_count:    resq 1
    .mapping_high_water_bytes:    resq 1
    .mapping_acquisition_count:   resq 1
    .mapping_release_count:       resq 1
    .mapping_rejection_count:     resq 1

    ; Typed-pool snapshot.
    .pool_configured_capacity:    resq 1
    .pool_reserved_capacity:      resq 1
    .pool_ordinary_capacity:      resq 1
    .pool_current_occupancy:      resq 1
    .pool_high_water:             resq 1
    .pool_acquisition_count:      resq 1
    .pool_release_count:          resq 1
    .pool_rejection_count:        resq 1

    ; Quiescence snapshot.
    .quiescence_baseline:         resq 1
    .quiescence_current:          resq 1
    .quiescence_grace:            resq 1
    .quiescence_external:         resq 1
    .quiescence_unexplained:      resq 1
    .quiescence_confirmed_leak:   resq 1
    .quiescence_observation_count: resq 1
    .quiescence_outcome:          resq 1
    .quiescence_class_mask:       resq 1

    ; RSS observations.
    .rss_seen_mask:               resq 1
    .rss_initial_bytes:           resq 1
    .rss_max_bytes:               resq 1
    .rss_final_bytes:             resq 1
    .rss_observation_count:       resq 1

    .ready:                       resq 1
endstruc


%endif
