%ifndef ASMWEB_QUAL_FAULT_HOOK_INC
%define ASMWEB_QUAL_FAULT_HOOK_INC 1


; ===========================================================================
; AsmWeb M0 qualification-only fault controller
;
; This interface exists solely for controlled qualification.
;
; It SHALL NOT be linked into the production AsmWeb binary.
;
; One controller represents one deterministic fault-injection campaign:
;
;   initialise
;       ->
;   arm exactly one fault identity + injection point + trigger budget
;       ->
;   evaluate that hook zero or more times
;       ->
;   optionally disarm
;
; The campaign identity and historical counters remain visible after disarm.
;
; No random triggering exists.
; No implicit global state exists.
; No production acceptance criterion is modified.
; ===========================================================================


; ---------------------------------------------------------------------------
; M0 qualification fault identities.
;
; These identify the simulated failure class.
; They do not claim later networking/crypto/timer fault classes.
; ---------------------------------------------------------------------------

%define ASMWEB_QUAL_FAULT_RESOURCE_ACQUISITION  0x1001


; ---------------------------------------------------------------------------
; M0 injection-point identities.
;
; These identify exact qualification seams.
; ---------------------------------------------------------------------------

%define ASMWEB_QUAL_POINT_AFTER_ACQUIRE_A       0x2001
%define ASMWEB_QUAL_POINT_AFTER_ACQUIRE_B       0x2002


; ---------------------------------------------------------------------------
; ASMWEB_QUAL_FAULT_CONTROLLER
;
; fault_id:
;   identity of the configured simulated fault.
;
; point_id:
;   exact configured injection point.
;
; trigger_budget:
;   maximum number of times the configured fault may trigger.
;
; hit_count:
;   number of times the exact configured fault+point hook was reached.
;
; trigger_count:
;   number of actual injected failures.
;
; active:
;   1 while the campaign may be consulted;
;   0 after explicit disarm.
;
; ready:
;   controller initialisation publication marker.
;
; Historical counters never wrap.
;
; One controller may be armed only once. Qualification requiring another
; campaign uses another pristine controller.
; ---------------------------------------------------------------------------

struc ASMWEB_QUAL_FAULT_CONTROLLER
    .fault_id:        resq 1
    .point_id:        resq 1
    .trigger_budget:  resq 1
    .hit_count:       resq 1
    .trigger_count:   resq 1
    .active:          resq 1
    .ready:           resq 1
endstruc


%endif
