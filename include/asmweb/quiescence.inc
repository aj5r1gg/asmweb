%ifndef ASMWEB_QUIESCENCE_INC
%define ASMWEB_QUIESCENCE_INC 1


; ===========================================================================
; M0 quiescence machinery
;
; Runtime & Memory v0.3 §63 requires each subsystem to define a
; configuration-derived quiescent baseline and, after any applicable grace
; period, classify retained state as:
;
;   EXPECTED_PERSISTENT
;   GRACE_TRANSIENT
;   EXTERNAL_COMPLETION_PENDING
;   UNEXPLAINED_RETAINED
;   CONFIRMED_LEAK
;
; This primitive does NOT discover or scan resources.
;
; Each subsystem remains authoritative for:
;
;   - its baseline;
;   - its current retained quantity;
;   - classification of retained state above baseline.
;
; This layer provides:
;
;   - bounded representation;
;   - exact decomposition validation;
;   - checked arithmetic;
;   - historical observation count;
;   - deterministic quiescence outcome.
;
; A quantity may represent objects, bytes, mappings, registrations or another
; explicitly defined homogeneous unit. One ASMWEB_QUIESCENCE_STATE describes
; one such accounting domain.
;
; Different units SHALL NOT be mixed in one state.
; ===========================================================================


; ---------------------------------------------------------------------------
; Classification-presence flags returned by asm_quiescence_evaluate in RDX.
;
; A flag means the corresponding category has a non-zero quantity.
; ---------------------------------------------------------------------------

%define ASMWEB_QUIESCENCE_CLASS_EXPECTED_PERSISTENT            (1 << 0)
%define ASMWEB_QUIESCENCE_CLASS_GRACE_TRANSIENT                (1 << 1)
%define ASMWEB_QUIESCENCE_CLASS_EXTERNAL_COMPLETION_PENDING    (1 << 2)
%define ASMWEB_QUIESCENCE_CLASS_UNEXPLAINED_RETAINED           (1 << 3)
%define ASMWEB_QUIESCENCE_CLASS_CONFIRMED_LEAK                 (1 << 4)


; ---------------------------------------------------------------------------
; Evaluation outcomes.
;
; BASELINE:
;   Exact expected persistent baseline remains. No transient, external,
;   unexplained or leak quantity remains.
;
; PENDING:
;   State is structurally valid but GRACE_TRANSIENT and/or
;   EXTERNAL_COMPLETION_PENDING remains.
;
; FAIL:
;   UNEXPLAINED_RETAINED and/or CONFIRMED_LEAK is non-zero.
;   This is a qualification failure classification, not automatically an
;   internal accounting-corruption result.
;
; INTEGRITY:
;   The quiescence representation itself is contradictory or invalid.
;
; Keep this vocabulary separate from ASMWEB_RESOURCE_*.
; ---------------------------------------------------------------------------

%define ASMWEB_QUIESCENCE_OUTCOME_BASELINE   0
%define ASMWEB_QUIESCENCE_OUTCOME_PENDING    1
%define ASMWEB_QUIESCENCE_OUTCOME_FAIL       2
%define ASMWEB_QUIESCENCE_OUTCOME_INTEGRITY  3


; ---------------------------------------------------------------------------
; ASMWEB_QUIESCENCE_STATE
;
; baseline:
;   Configuration-derived expected persistent quantity.
;
; current:
;   Total currently retained quantity represented by this state.
;
; expected_persistent:
;   Must exactly equal baseline in M0.
;
; Remaining category fields:
;   Exact decomposition of current - baseline.
;
; observation_count:
;   Number of successfully committed observations after initialisation.
;   Historical and non-wrapping.
;
; ready:
;   Publication marker written last by init.
;
; Required invariant:
;
;   current =
;       expected_persistent
;     + grace_transient
;     + external_completion_pending
;     + unexplained_retained
;     + confirmed_leak
;
; and:
;
;   expected_persistent == baseline
; ---------------------------------------------------------------------------

struc ASMWEB_QUIESCENCE_STATE
    .baseline:                     resq 1
    .current:                      resq 1

    .expected_persistent:          resq 1
    .grace_transient:              resq 1
    .external_completion_pending:  resq 1
    .unexplained_retained:         resq 1
    .confirmed_leak:               resq 1

    .observation_count:            resq 1
    .ready:                        resq 1
endstruc


%endif
