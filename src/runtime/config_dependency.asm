bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/config_dependency.inc"

global asm_capacity_dependency_validate

extern asm_u64_mul_checked
extern asm_u64_add_checked


section .text


; ===========================================================================
; asm_capacity_dependency_validate
;
; Inputs:
;
;   RDI = ASMWEB_CAPACITY_DEPENDENCY_NODE * nodes
;   RSI = node_count
;   RDX = ASMWEB_CAPACITY_DEPENDENCY_EDGE * edges
;   RCX = edge_count
;
; Canonical empty graph:
;
;   nodes = NULL
;   node_count = 0
;   edges = NULL
;   edge_count = 0
;
; A non-empty node set with zero edges is valid.
;
; Returns:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
; Validates:
;
;   - bounded canonical pointer/count relationships;
;   - unique non-zero capacity identities;
;   - configured_capacity <= physical_capacity;
;   - non-zero dependency multipliers;
;   - no self-dependencies;
;   - every edge resolves both endpoints;
;   - strict increasing topological rank on every edge;
;   - duplicate parent/child edge rejection;
;   - checked per-edge multiplication;
;   - checked aggregate child dependency arithmetic;
;   - aggregate requirement <= child configured capacity.
;
; The routine validates an already-resolved bounded graph. It does not mutate
; graph state and does not calculate or publish configuration.
; ===========================================================================

asm_capacity_dependency_validate:
    cld

    ; Preserve Internal ABI callee-saved state.
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Six pushes leave RSP % 16 == 8.
    ;
    ; Reserve 24 bytes:
    ;
    ;   [rsp + 0]  aggregate required quantity for current child
    ;   [rsp + 8]  current edge index across nested arithmetic calls
    ;   [rsp + 16] spare / alignment
    ;
    ; RSP % 16 == 0 before nested calls.
    sub rsp, 24

    mov rbx, rdi                    ; nodes
    mov r12, rsi                    ; node_count
    mov r13, rdx                    ; edges
    mov r14, rcx                    ; edge_count


    ; -----------------------------------------------------------------------
    ; Bounded counts.
    ; -----------------------------------------------------------------------

    cmp r12, ASMWEB_M0_MAX_DEPENDENCY_NODES
    ja .integrity

    cmp r14, ASMWEB_M0_MAX_DEPENDENCY_EDGES
    ja .integrity


    ; -----------------------------------------------------------------------
    ; Canonical node pointer/count.
    ; -----------------------------------------------------------------------

    test r12, r12
    jnz .nodes_nonempty

    test rbx, rbx
    jnz .integrity

    jmp .edges_pointer


.nodes_nonempty:
    test rbx, rbx
    jz .integrity


.edges_pointer:

    ; -----------------------------------------------------------------------
    ; Canonical edge pointer/count.
    ; -----------------------------------------------------------------------

    test r14, r14
    jnz .edges_nonempty

    test r13, r13
    jnz .integrity

    jmp .validate_nodes


.edges_nonempty:
    test r13, r13
    jz .integrity

    ; An edge graph cannot exist without capacity nodes.
    test r12, r12
    jz .integrity


    ; =======================================================================
    ; NODE VALIDATION
    ; =======================================================================

.validate_nodes:
    xor ebp, ebp


.node_outer:
    cmp rbp, r12
    jae .validate_edges


    mov rax, rbp
    imul rax, ASMWEB_CAPACITY_DEPENDENCY_NODE_size
    jo .integrity

    lea r15, [rbx + rax]


    ; Stable non-zero identity.

    cmp qword [r15 + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id], 0
    je .integrity


    ; configured <= physical

    mov rax, [r15 + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity]
    cmp rax, [r15 + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity]
    ja .integrity


    ; Duplicate identity rejection.

    mov r8, rbp
    inc r8


.node_duplicate_loop:
    cmp r8, r12
    jae .node_next

    mov rax, r8
    imul rax, ASMWEB_CAPACITY_DEPENDENCY_NODE_size
    jo .integrity

    lea r9, [rbx + rax]

    mov rax, [r15 + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id]
    cmp rax, [r9 + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id]
    je .integrity

    inc r8
    jmp .node_duplicate_loop


.node_next:
    inc rbp
    jmp .node_outer


    ; =======================================================================
    ; EDGE STRUCTURE / RESOLUTION / TOPOLOGY
    ; =======================================================================

.validate_edges:
    xor ebp, ebp


.edge_outer:
    cmp rbp, r14
    jae .aggregate_dependencies

    mov rax, rbp
    imul rax, ASMWEB_CAPACITY_DEPENDENCY_EDGE_size
    jo .integrity

    lea r15, [r13 + rax]


    mov r8, [r15 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id]
    test r8, r8
    jz .integrity

    mov r9, [r15 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id]
    test r9, r9
    jz .integrity

    cmp r8, r9
    je .integrity

    cmp qword [r15 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent], 0
    je .integrity


    ; -----------------------------------------------------------------------
    ; Resolve parent.
    ; -----------------------------------------------------------------------

    xor r10d, r10d


.edge_find_parent:
    cmp r10, r12
    jae .integrity

    mov rax, r10
    imul rax, ASMWEB_CAPACITY_DEPENDENCY_NODE_size
    jo .integrity

    lea r11, [rbx + rax]

    cmp r8, [r11 + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id]
    je .edge_parent_found

    inc r10
    jmp .edge_find_parent


.edge_parent_found:
    mov r8, r11                    ; resolved parent node


    ; -----------------------------------------------------------------------
    ; Resolve child.
    ; -----------------------------------------------------------------------

    xor r10d, r10d


.edge_find_child:
    cmp r10, r12
    jae .integrity

    mov rax, r10
    imul rax, ASMWEB_CAPACITY_DEPENDENCY_NODE_size
    jo .integrity

    lea r11, [rbx + rax]

    mov rax, [r15 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id]

    cmp rax, [r11 + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id]
    je .edge_child_found

    inc r10
    jmp .edge_find_child


.edge_child_found:

    ; -----------------------------------------------------------------------
    ; Topological proof.
    ;
    ; Every accepted edge strictly increases dependency rank. A directed cycle
    ; therefore cannot exist in an accepted graph.
    ; -----------------------------------------------------------------------

    mov rax, [r8 + ASMWEB_CAPACITY_DEPENDENCY_NODE.dependency_rank]

    cmp rax, [r11 + ASMWEB_CAPACITY_DEPENDENCY_NODE.dependency_rank]
    jae .integrity


    ; -----------------------------------------------------------------------
    ; Duplicate parent/child edge rejection.
    ; -----------------------------------------------------------------------

    mov r10, rbp
    inc r10


.edge_duplicate_loop:
    cmp r10, r14
    jae .edge_next

    mov rax, r10
    imul rax, ASMWEB_CAPACITY_DEPENDENCY_EDGE_size
    jo .integrity

    lea r9, [r13 + rax]

    mov rax, [r15 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id]
    cmp rax, [r9 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id]
    jne .edge_duplicate_next

    mov rax, [r15 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id]
    cmp rax, [r9 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id]
    je .integrity


.edge_duplicate_next:
    inc r10
    jmp .edge_duplicate_loop


.edge_next:
    inc rbp
    jmp .edge_outer


    ; =======================================================================
    ; AGGREGATE DEPENDENCY CLOSURE
    ;
    ; For each child:
    ;
    ;   required =
    ;       SUM(parent.configured_capacity * units_per_parent)
    ;
    ; over every incoming edge.
    ;
    ; required <= child.configured_capacity
    ;
    ; Arithmetic is performed only through canonical checked primitives.
    ; =======================================================================

.aggregate_dependencies:
    xor ebp, ebp


.aggregate_child_outer:
    cmp rbp, r12
    jae .success

    mov rax, rbp
    imul rax, ASMWEB_CAPACITY_DEPENDENCY_NODE_size
    jo .integrity

    lea r15, [rbx + rax]            ; current child node

    mov qword [rsp + 0], 0          ; required aggregate

    xor r8d, r8d                    ; edge index


.aggregate_edge_loop:
    cmp r8, r14
    jae .aggregate_child_done

    mov rax, r8
    imul rax, ASMWEB_CAPACITY_DEPENDENCY_EDGE_size
    jo .integrity

    lea r9, [r13 + rax]


    ; Only incoming edges for this child contribute.

    mov rax, [r15 + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id]

    cmp rax, [r9 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id]
    jne .aggregate_edge_next


    ; Resolve parent again. Structural validation above guarantees it exists,
    ; but do not silently depend upon unchecked state.

    mov rax, [r9 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id]

    xor r10d, r10d


.aggregate_find_parent:
    cmp r10, r12
    jae .integrity

    mov r11, r10
    imul r11, ASMWEB_CAPACITY_DEPENDENCY_NODE_size
    jo .integrity

    add r11, rbx
    jc .integrity

    cmp rax, [r11 + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id]
    je .aggregate_parent_found

    inc r10
    jmp .aggregate_find_parent


.aggregate_parent_found:

    ; Preserve edge index over caller-saved arithmetic calls.
    mov [rsp + 8], r8


    ; contribution =
    ;     parent.configured_capacity * units_per_parent

    mov rdi, [r11 + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity]
    mov rsi, [r9 + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent]

    call asm_u64_mul_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .integrity


    ; aggregate += contribution

    mov rdi, [rsp + 0]
    mov rsi, rdx

    call asm_u64_add_checked

    cmp eax, ASMWEB_RESOURCE_OK
    jne .integrity

    mov [rsp + 0], rdx

    mov r8, [rsp + 8]


.aggregate_edge_next:
    inc r8
    jmp .aggregate_edge_loop


.aggregate_child_done:

    mov rax, [rsp + 0]

    cmp rax, [r15 + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity]
    ja .integrity

    inc rbp
    jmp .aggregate_child_outer


.success:
    add rsp, 24

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_OK
    ret


.integrity:
    add rsp, 24

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    mov eax, ASMWEB_RESOURCE_INTEGRITY
    ret
