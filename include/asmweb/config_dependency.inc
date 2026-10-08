%ifndef ASMWEB_CONFIG_DEPENDENCY_INC
%define ASMWEB_CONFIG_DEPENDENCY_INC 1


; ===========================================================================
; M0 capacity dependency graph
;
; MEM-CAP-DEPENDENCY:
;
;   A configuration SHALL NOT enter READY when its full capacity dependency
;   graph cannot be provisioned or validly bounded.
;
; This M0 model validates dependency arithmetic over already-resolved capacity
; values. It does NOT parse configuration and does NOT define later protocol
; capacities prematurely.
;
; A node represents one independently bounded configured capacity.
;
; An edge:
;
;     parent -> child, units_per_parent = N
;
; means:
;
;     every configured parent unit requires N configured child units.
;
; Where several parents require the same child capacity, obligations are
; cumulative:
;
;     required_child =
;         SUM(parent.configured_capacity * units_per_parent)
;
; The aggregate must not exceed child.configured_capacity.
;
; A supplied topological rank is part of the resolved graph proof:
;
;     parent.dependency_rank < child.dependency_rank
;
; for every edge.
;
; Therefore an accepted graph cannot contain a directed cycle without the
; validator requiring mutable traversal scratch state.
;
; The validator does not infer dependency semantics. The authoritative
; configuration/provisioning layer supplies nodes, edges and multipliers.
; ===========================================================================


%define ASMWEB_M0_MAX_DEPENDENCY_NODES 256
%define ASMWEB_M0_MAX_DEPENDENCY_EDGES 256


; ---------------------------------------------------------------------------
; ASMWEB_CAPACITY_DEPENDENCY_NODE
;
; capacity_id:
;   Stable non-zero identity within this resolved dependency graph.
;
; configured_capacity:
;   Capacity configuration intends to expose/use.
;
; physical_capacity:
;   Provisionable ceiling for this node.
;
; dependency_rank:
;   Topological rank. Every dependency edge must strictly increase rank.
;
; M0 invariant:
;
;   configured_capacity <= physical_capacity
; ---------------------------------------------------------------------------

struc ASMWEB_CAPACITY_DEPENDENCY_NODE
    .capacity_id:          resq 1
    .configured_capacity: resq 1
    .physical_capacity:   resq 1
    .dependency_rank:     resq 1
endstruc


; ---------------------------------------------------------------------------
; ASMWEB_CAPACITY_DEPENDENCY_EDGE
;
; parent_capacity_id:
;   Capacity whose configured quantity creates the obligation.
;
; child_capacity_id:
;   Capacity required to support the parent.
;
; units_per_parent:
;   Non-zero child units required for each configured parent unit.
;
; Duplicate parent/child edges are rejected. Multiple dependency costs between
; the same two capacities must first be canonically combined by configuration
; resolution rather than represented ambiguously.
; ---------------------------------------------------------------------------

struc ASMWEB_CAPACITY_DEPENDENCY_EDGE
    .parent_capacity_id: resq 1
    .child_capacity_id:  resq 1
    .units_per_parent:   resq 1
endstruc


%endif
