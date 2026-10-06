%ifndef ASMWEB_PRODUCTION_REGISTRY_INC
%define ASMWEB_PRODUCTION_REGISTRY_INC


; ===========================================================================
; Canonical production M0 OLR / MOT authority
;
; These identities describe real fixed runtime state retained by the current
; production executable. They are deliberately separate from qualification
; fixtures.
;
; No arbitrary byte counts are encoded here. Object sizes are derived from the
; actual assembly structure definitions.
; ===========================================================================


%define ASMWEB_PROD_OBJECT_STARTUP_INFO             0x10000001
%define ASMWEB_PROD_OBJECT_ENTROPY_BOOTSTRAP        0x10000002
%define ASMWEB_PROD_OBJECT_CPU_INFO                 0x10000003
%define ASMWEB_PROD_OBJECT_MONOTONIC_TIME           0x10000004
%define ASMWEB_PROD_OBJECT_PROCESS_RUNTIME          0x10000005
%define ASMWEB_PROD_OBJECT_STARTUP_MEMORY_ACCOUNT   0x10000006
%define ASMWEB_PROD_OBJECT_RUNTIME_RULE_STORAGE     0x10000007
%define ASMWEB_PROD_OBJECT_REGISTRY_STORAGE         0x10000008


%define ASMWEB_PROD_LIMIT_STARTUP_INFO              0x20000001
%define ASMWEB_PROD_LIMIT_ENTROPY_BOOTSTRAP         0x20000002
%define ASMWEB_PROD_LIMIT_CPU_INFO                  0x20000003
%define ASMWEB_PROD_LIMIT_MONOTONIC_TIME            0x20000004
%define ASMWEB_PROD_LIMIT_PROCESS_RUNTIME           0x20000005
%define ASMWEB_PROD_LIMIT_STARTUP_MEMORY_ACCOUNT    0x20000006
%define ASMWEB_PROD_LIMIT_RUNTIME_RULE_STORAGE      0x20000007
%define ASMWEB_PROD_LIMIT_REGISTRY_STORAGE          0x20000008


%define ASMWEB_PRODUCTION_OLR_COUNT 8
%define ASMWEB_PRODUCTION_MOT_COUNT 8
%define ASMWEB_PRODUCTION_RCT_COUNT 0


; Count the canonical Runtime Rule Registry from its authority file rather
; than duplicating the value by hand.

%assign ASMWEB_PRODUCTION_RUNTIME_RULE_COUNT 0

%macro ASMWEB_RUNTIME_RULE 6
    %assign ASMWEB_PRODUCTION_RUNTIME_RULE_COUNT \
        ASMWEB_PRODUCTION_RUNTIME_RULE_COUNT + 1
%endmacro

%include "asmweb/runtime_rules.def"

%unmacro ASMWEB_RUNTIME_RULE 6


; Resident storage used by the canonical RRR implementation:
;
;   validation entries + publication marker.

ASMWEB_PRODUCTION_RUNTIME_RULE_STORAGE_BYTES equ \
    ASMWEB_RRR_VALIDATION_ENTRY_size * ASMWEB_PRODUCTION_RUNTIME_RULE_COUNT + 8


; Resident storage owned by production_registry.asm itself:
;
;   OLR array
;   MOT array
;   registry-set descriptor
;   publication marker
;
; The registry therefore accounts for its own resident direct state.

ASMWEB_PRODUCTION_REGISTRY_STORAGE_BYTES equ \
    ASMWEB_OLR_VALIDATION_ENTRY_size * ASMWEB_PRODUCTION_OLR_COUNT + \
    ASMWEB_MOT_VALIDATION_ENTRY_size * ASMWEB_PRODUCTION_MOT_COUNT + \
    ASMWEB_REGISTRY_VALIDATION_SET_size + \
    8


%endif
