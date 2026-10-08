%ifndef ASMWEB_RUNTIME_INVARIANT_INC
%define ASMWEB_RUNTIME_INVARIANT_INC 1


; ===========================================================================
; M0 runtime invariant composition
;
; This layer does NOT duplicate subsystem validators.
;
; It composes the authoritative M0 READY-state truths already owned by:
;
;   - process runtime;
;   - OLR/MOT/RCT registry validation;
;   - startup-memory accounting;
;   - capacity dependency validation;
;   - direct-memory ceiling derivation;
;   - startup state;
;   - entropy bootstrap state;
;   - CPU bootstrap state;
;   - monotonic-time bootstrap state.
;
; The input is a temporary view over existing authoritative objects. It owns
; none of them and introduces no new persistent production state.
; ===========================================================================


; ---------------------------------------------------------------------------
; First-failure classes returned in RDX when validation fails.
;
; RAX determines success/failure:
;
;   ASMWEB_RESOURCE_OK
;       RDX = derived direct registered memory capacity.
;
;   ASMWEB_RESOURCE_INTEGRITY
;       RDX = one ASMWEB_RUNTIME_INVARIANT_FAIL_* code.
; ---------------------------------------------------------------------------

%define ASMWEB_RUNTIME_INVARIANT_FAIL_INPUT                  1
%define ASMWEB_RUNTIME_INVARIANT_FAIL_PROCESS                2
%define ASMWEB_RUNTIME_INVARIANT_FAIL_REGISTRY               3
%define ASMWEB_RUNTIME_INVARIANT_FAIL_STARTUP_MEMORY         4
%define ASMWEB_RUNTIME_INVARIANT_FAIL_DEPENDENCY             5
%define ASMWEB_RUNTIME_INVARIANT_FAIL_STARTUP_STATE          6
%define ASMWEB_RUNTIME_INVARIANT_FAIL_ENTROPY                7
%define ASMWEB_RUNTIME_INVARIANT_FAIL_CPU                    8
%define ASMWEB_RUNTIME_INVARIANT_FAIL_TIME                   9
%define ASMWEB_RUNTIME_INVARIANT_FAIL_MEMORY_RECONCILIATION 10
%define ASMWEB_RUNTIME_INVARIANT_FAIL_READY_STATE           11


; ---------------------------------------------------------------------------
; ASMWEB_RUNTIME_INVARIANT_VIEW
;
; All object pointers except dependency arrays are mandatory.
;
; Dependency graph uses canonical pointer/count semantics:
;
;   empty:
;       nodes = NULL
;       node_count = 0
;       edges = NULL
;       edge_count = 0
;
; The view is read-only and may be stack-local.
; ---------------------------------------------------------------------------

struc ASMWEB_RUNTIME_INVARIANT_VIEW
    .startup_info_ptr:       resq 1
    .entropy_ptr:            resq 1
    .cpu_ptr:                resq 1
    .time_ptr:               resq 1

    .process_runtime_ptr:     resq 1
    .startup_memory_ptr:      resq 1
    .registry_ptr:            resq 1

    .dependency_nodes_ptr:    resq 1
    .dependency_node_count:   resq 1
    .dependency_edges_ptr:    resq 1
    .dependency_edge_count:   resq 1
endstruc


%endif
