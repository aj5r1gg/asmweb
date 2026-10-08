%ifndef ASMWEB_POOL_INC
%define ASMWEB_POOL_INC


; ===========================================================================
; M0 typed bounded-pool foundation
;
; This establishes pool semantics, ownership and accounting without freezing
; the final pool representation, stale-reference mechanism or worker topology.
;
; M0 representation:
;
;   object backing:
;       caller-provided contiguous fixed-stride storage;
;
;   slot ownership metadata:
;       one caller-provided byte per physical slot;
;
;       0 = FREE
;       1 = OWNED
;
; The one-byte slot-state representation is an implementation detail of this
; M0 primitive. Callers SHALL NOT depend upon it as durable architecture.
;
; No generation identity is provided by this slice.
; Returned object pointers are valid only within the qualified exclusive-owner
; lifetime established by successful acquisition and terminated by release.
; ===========================================================================


%define ASMWEB_POOL_SLOT_FREE   0
%define ASMWEB_POOL_SLOT_OWNED  1


; M0 partitioning model.
;
; More sophisticated worker-local or dynamically partitioned designs remain
; deliberately deferred.

%define ASMWEB_POOL_PARTITION_GLOBAL  1


; ---------------------------------------------------------------------------
; ASMWEB_TYPED_POOL_REQUEST
;
; object_class_id:
;   Non-zero caller/registry identity for the object class represented by this
;   pool.
;
; backing_base / backing_bytes:
;   Caller-owned storage offered to the pool. The pool requires at least:
;
;       effective_stride * physical_capacity
;
; slot_state_base / slot_state_bytes:
;   Caller-owned management storage. M0 requires at least one byte per physical
;   slot.
;
; actual_size:
;   Actual object bytes established by the governing layout authority.
;
; effective_stride:
;   Already-resolved stride established by the governing layout authority.
;   The pool validates but does not derive layout policy.
;
; alignment:
;   Non-zero power-of-two object alignment.
;
; physical_capacity:
;   Actually provisioned slot count.
;
; configured_capacity:
;   Maximum configured slots visible to this pool policy.
;
; reserved_capacity:
;   Protected portion of configured capacity. Ordinary acquisition does not
;   borrow from this reserve.
;
; ownership_scope:
;   Non-zero caller-defined bounded ownership scope identity.
;
; partitioning_model:
;   ASMWEB_POOL_PARTITION_*.
; ---------------------------------------------------------------------------

struc ASMWEB_TYPED_POOL_REQUEST
    .object_class_id:      resq 1

    .backing_base:         resq 1
    .backing_bytes:        resq 1

    .slot_state_base:      resq 1
    .slot_state_bytes:     resq 1

    .actual_size:          resq 1
    .effective_stride:     resq 1
    .alignment:            resq 1

    .physical_capacity:    resq 1
    .configured_capacity:  resq 1
    .reserved_capacity:    resq 1

    .ownership_scope:      resq 1
    .partitioning_model:   resq 1
endstruc


; ---------------------------------------------------------------------------
; ASMWEB_TYPED_POOL
;
; payload_bytes:
;
;     effective_stride * physical_capacity
;
; slot_metadata_bytes:
;
;     physical_capacity
;
; for the current M0 one-byte-per-slot representation.
;
; management_bytes_total:
;
;     sizeof(ASMWEB_TYPED_POOL) + slot_metadata_bytes
;
; This quantity makes the complete M0 management representation visible for
; accounting. A future registry relationship SHALL avoid double-counting if
; the descriptor itself is independently represented as another memory class.
;
; ordinary_capacity:
;
;     configured_capacity - reserved_capacity
;
; Ordinary asm_typed_pool_acquire searches only:
;
;     [0, ordinary_capacity)
;
; Slots in:
;
;     [ordinary_capacity, configured_capacity)
;
; are protected reserve and are not implicitly borrowed.
;
; Slots in:
;
;     [configured_capacity, physical_capacity)
;
; are provisioned but not configured for use.
;
; quiescent baseline:
;
;     current_occupancy == 0
;
; Publication:
;
;     ready is written last after all structural validation succeeds.
; ---------------------------------------------------------------------------

struc ASMWEB_TYPED_POOL
    .object_class_id:         resq 1

    .backing_base:            resq 1
    .payload_bytes:           resq 1

    .slot_state_base:         resq 1
    .slot_metadata_bytes:     resq 1
    .management_bytes_total:  resq 1

    .actual_size:             resq 1
    .effective_stride:        resq 1
    .alignment:               resq 1

    .physical_capacity:       resq 1
    .configured_capacity:     resq 1
    .reserved_capacity:       resq 1
    .ordinary_capacity:       resq 1

    .current_occupancy:       resq 1
    .high_water:              resq 1

    .acquisition_count:       resq 1
    .release_count:           resq 1
    .rejection_count:         resq 1

    .ownership_scope:         resq 1
    .partitioning_model:      resq 1

    .ready:                   resq 1
endstruc

%endif
