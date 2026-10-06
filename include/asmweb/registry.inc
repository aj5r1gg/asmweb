%ifndef ASMWEB_REGISTRY_INC
%define ASMWEB_REGISTRY_INC

; ---------------------------------------------------------------------------
; AsmWeb M0 registry-validation foundation
; ---------------------------------------------------------------------------
;
; The Runtime & Memory Specification defines four authoritative registries:
;
;   RRR — Runtime Rule Registry
;   OLR — Object Layout Registry
;   MOT — Maximum-Object Table
;   RCT — Resource Capacity Table
;
; This include establishes the common lifecycle vocabulary and the compact
; validation descriptors required to qualify OLR/MOT/RCT consistency before
; real protocol objects depend upon those registries.
;
; These descriptors are NOT yet the complete descriptive schemas. They carry
; the machine-relevant identity, layout, capacity and cross-reference state
; needed by the first M0 validator.
;
; Full registry representation remains an M0 responsibility.
; ---------------------------------------------------------------------------


; ---------------------------------------------------------------------------
; Registry lifecycle state
; ---------------------------------------------------------------------------

%define ASMWEB_REGISTRY_STATUS_ACTIVE      1
%define ASMWEB_REGISTRY_STATUS_DEFERRED    2
%define ASMWEB_REGISTRY_STATUS_SUPERSEDED  3
%define ASMWEB_REGISTRY_STATUS_RETIRED     4


; ---------------------------------------------------------------------------
; Runtime Rule Registry qualification state
;
; Runtime & Memory requires qualification state to remain distinct from
; registry definition/lifecycle state.
;
; These values consume the project-wide implementation/qualification-state
; vocabulary defined by Qualification & Verification v0.3.
; ---------------------------------------------------------------------------

%define ASMWEB_QUAL_STATE_NOT_STARTED           1
%define ASMWEB_QUAL_STATE_IN_PROGRESS           2
%define ASMWEB_QUAL_STATE_IMPLEMENTED           3
%define ASMWEB_QUAL_STATE_QUALIFICATION_PENDING 4
%define ASMWEB_QUAL_STATE_QUALIFIED             5
%define ASMWEB_QUAL_STATE_FAILED                6
%define ASMWEB_QUAL_STATE_BLOCKED               7
%define ASMWEB_QUAL_STATE_DEFERRED              8
%define ASMWEB_QUAL_STATE_NOT_APPLICABLE        9


; ---------------------------------------------------------------------------
; Runtime Rule Registry namespace identity
; ---------------------------------------------------------------------------

%define ASMWEB_RRR_NAMESPACE_GOV   1
%define ASMWEB_RRR_NAMESPACE_OBJ   2
%define ASMWEB_RRR_NAMESPACE_POL   3
%define ASMWEB_RRR_NAMESPACE_CAP   4
%define ASMWEB_RRR_NAMESPACE_OWN   5
%define ASMWEB_RRR_NAMESPACE_LIFE  6
%define ASMWEB_RRR_NAMESPACE_BUF   7
%define ASMWEB_RRR_NAMESPACE_ASY   8
%define ASMWEB_RRR_NAMESPACE_EVT   9
%define ASMWEB_RRR_NAMESPACE_TMR  10
%define ASMWEB_RRR_NAMESPACE_ACC  11
%define ASMWEB_RRR_NAMESPACE_PRS  12
%define ASMWEB_RRR_NAMESPACE_EXT  13
%define ASMWEB_RRR_NAMESPACE_CFG  14
%define ASMWEB_RRR_NAMESPACE_QUI  15
%define ASMWEB_RRR_NAMESPACE_SEC  16
%define ASMWEB_RRR_NAMESPACE_QUA  17
%define ASMWEB_RRR_NAMESPACE_CHG  18

%define ASMWEB_RRR_NAMESPACE_MIN ASMWEB_RRR_NAMESPACE_GOV
%define ASMWEB_RRR_NAMESPACE_MAX ASMWEB_RRR_NAMESPACE_CHG


; ---------------------------------------------------------------------------
; Initial RRR bounds
;
; The current Runtime & Memory v0.3 rule population has a longest observed
; rule identity of 30 bytes. 64 bytes is the bounded M0 validator ceiling,
; providing controlled headroom without creating an unbounded string model.
; ---------------------------------------------------------------------------

%define ASMWEB_M0_MAX_RRR_ENTRIES         256
%define ASMWEB_M0_MAX_RULE_ID_BYTES        64
%define ASMWEB_M0_MIN_RULE_ID_BYTES         9
%define ASMWEB_M0_MAX_RULE_STATEMENT_BYTES 512


; ---------------------------------------------------------------------------
; RRR validation descriptor
;
; This is the machine-validation subset required for the first M0 RRR slice.
; It is not yet the complete descriptive/traceability schema.
;
; rule_id_ptr / rule_id_length:
;   Explicit non-NUL-terminated byte identity.
;
; namespace:
;   Must agree with the namespace encoded textually in rule_id.
;
; status:
;   Registry definition/lifecycle state.
;
; qualification_state:
;   Independent project qualification/implementation state.
;
; normative_statement_ptr / normative_statement_length:
;   Explicit bounded atomic normative statement represented by this rule.
; ---------------------------------------------------------------------------

struc ASMWEB_RRR_VALIDATION_ENTRY
    .rule_id_ptr:                resq 1
    .rule_id_length:             resq 1
    .namespace:                  resq 1
    .status:                     resq 1
    .qualification_state:        resq 1
    .normative_statement_ptr:    resq 1
    .normative_statement_length: resq 1
endstruc


; ---------------------------------------------------------------------------
; Object-layout qualification state
; ---------------------------------------------------------------------------

%define ASMWEB_LAYOUT_STATUS_CONCEPTUAL            1
%define ASMWEB_LAYOUT_STATUS_PROVISIONAL           2
%define ASMWEB_LAYOUT_STATUS_QUALIFIED             3
%define ASMWEB_LAYOUT_STATUS_FROZEN_FOR_MILESTONE  4


; ---------------------------------------------------------------------------
; Initial bounded registry sizes
;
; These are M0 validator safety bounds, not final product limits.
; ---------------------------------------------------------------------------

%define ASMWEB_M0_MAX_OLR_ENTRIES 256
%define ASMWEB_M0_MAX_MOT_ENTRIES 256
%define ASMWEB_M0_MAX_RCT_ENTRIES 256


; ---------------------------------------------------------------------------
; OLR validation descriptor
;
; object_id:
;   Stable non-zero object identity.
;
; status:
;   ASMWEB_REGISTRY_STATUS_*.
;
; layout_status:
;   ASMWEB_LAYOUT_STATUS_*.
;
; actual_size_bytes / effective_stride_bytes:
;   Mechanically cross-validated layout quantities.
;
; pooled:
;   0 = not represented as a pooled retained object for this descriptor.
;   1 = pooled and therefore requires applicable MOT linkage while ACTIVE.
;
; mot_ref:
;   Referenced MOT limit_id, or zero when not applicable.
; ---------------------------------------------------------------------------

struc ASMWEB_OLR_VALIDATION_ENTRY
    .object_id:              resq 1
    .status:                 resq 1
    .layout_status:          resq 1
    .actual_size_bytes:      resq 1
    .effective_stride_bytes: resq 1
    .pooled:                 resq 1
    .mot_ref:                resq 1
endstruc


; ---------------------------------------------------------------------------
; MOT validation descriptor
;
; limit_id:
;   Stable non-zero maximum-object identity.
;
; object_id:
;   OLR object identity represented by this limit.
;
; actual_size_bytes / effective_stride_bytes:
;   Must agree with the corresponding qualified OLR values.
;
; maximum_count:
;   Absolute represented count bound.
;
; physical_capacity:
;   Physically provisionable count under this descriptor.
;
; configured_capacity:
;   Configured usable count.
;
; owner_resource_id:
;   RCT resource that owns/accounts this object class, or zero when the
;   ownership relationship is not RCT-based.
; ---------------------------------------------------------------------------

struc ASMWEB_MOT_VALIDATION_ENTRY
    .limit_id:               resq 1
    .status:                 resq 1
    .object_id:              resq 1
    .actual_size_bytes:      resq 1
    .effective_stride_bytes: resq 1
    .maximum_count:          resq 1
    .physical_capacity:      resq 1
    .configured_capacity:    resq 1
    .owner_resource_id:      resq 1
endstruc


; ---------------------------------------------------------------------------
; RCT validation descriptor
;
; resource_id:
;   Stable non-zero resource identity.
;
; physical_capacity:
;   Physical/provisionable resource ceiling.
;
; configured_capacity:
;   Policy/configuration ceiling.
;
; reserved_capacity:
;   Protected capacity not ordinarily available to general admission.
;
; direct_bytes:
;   Direct userspace bytes represented by the resource when applicable.
;
; mot_ref:
;   MOT limit_id for direct memory represented by an object class.
;
; direct_memory_justified:
;   Explicit exception marker when direct memory legitimately has no MOT
;   object representation. This is not a shortcut for missing registration.
; ---------------------------------------------------------------------------

struc ASMWEB_RCT_VALIDATION_ENTRY
    .resource_id:              resq 1
    .status:                   resq 1
    .physical_capacity:        resq 1
    .configured_capacity:      resq 1
    .reserved_capacity:        resq 1
    .direct_bytes:             resq 1
    .mot_ref:                  resq 1
    .direct_memory_justified:  resq 1
endstruc


; ---------------------------------------------------------------------------
; Registry-set descriptor
;
; Empty registries are permitted by the generic validator, provided pointer
; and count state is structurally consistent.
; ---------------------------------------------------------------------------

struc ASMWEB_REGISTRY_VALIDATION_SET
    .olr_ptr:    resq 1
    .olr_count:  resq 1

    .mot_ptr:    resq 1
    .mot_count:  resq 1

    .rct_ptr:    resq 1
    .rct_count:  resq 1
endstruc

%endif
