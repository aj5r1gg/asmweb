bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/arithmetic.inc"
%include "asmweb/config_dependency.inc"

global _start

extern asm_capacity_dependency_validate
extern asm_linux_exit


; ===========================================================================
; M0 configuration dependency qualification
;
; Valid reference graph:
;
;       A(10)
;        |
;       x2
;        v
;       B(20) ----x3----\
;                        > C(65)
;       D(5) -----x1----/
;
; Required:
;
;   B >= 10 * 2 = 20
;
;   C >=
;       (20 * 3)
;     + (5  * 1)
;     = 65
;
; Ranks:
;
;   A = 0
;   D = 0
;   B = 1
;   C = 2
;
; This proves both multi-level dependency closure and aggregate obligations
; from multiple parents into one child.
; ===========================================================================


%define CAP_A  0x610001
%define CAP_B  0x610002
%define CAP_C  0x610003
%define CAP_D  0x610004
%define CAP_UNKNOWN 0x61ffff


section .bss

alignb 8
nodes:
    resb ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 4

edges:
    ; Reserve four so qualification can add one temporary cyclic/duplicate edge.
    resb ASMWEB_CAPACITY_DEPENDENCY_EDGE_size * 4


section .text


; ===========================================================================
; qual_build_valid_graph
;
; Rebuilds the canonical four-node / three-edge fixture completely.
; ===========================================================================

qual_build_valid_graph:
    cld


    ; -----------------------------------------------------------------------
    ; A
    ; -----------------------------------------------------------------------

    lea rax, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 0]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id], CAP_A
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], 10
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], 10
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.dependency_rank], 0


    ; -----------------------------------------------------------------------
    ; B
    ; -----------------------------------------------------------------------

    lea rax, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 1]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id], CAP_B
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], 20
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], 20
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.dependency_rank], 1


    ; -----------------------------------------------------------------------
    ; C
    ; -----------------------------------------------------------------------

    lea rax, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 2]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id], CAP_C
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], 65
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], 65
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.dependency_rank], 2


    ; -----------------------------------------------------------------------
    ; D
    ; -----------------------------------------------------------------------

    lea rax, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 3]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id], CAP_D
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], 5
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], 5
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.dependency_rank], 0


    ; -----------------------------------------------------------------------
    ; A -> B, x2
    ; -----------------------------------------------------------------------

    lea rax, [rel edges + ASMWEB_CAPACITY_DEPENDENCY_EDGE_size * 0]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id], CAP_A
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id], CAP_B
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent], 2


    ; -----------------------------------------------------------------------
    ; B -> C, x3
    ; -----------------------------------------------------------------------

    lea rax, [rel edges + ASMWEB_CAPACITY_DEPENDENCY_EDGE_size * 1]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id], CAP_B
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id], CAP_C
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent], 3


    ; -----------------------------------------------------------------------
    ; D -> C, x1
    ; -----------------------------------------------------------------------

    lea rax, [rel edges + ASMWEB_CAPACITY_DEPENDENCY_EDGE_size * 2]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id], CAP_D
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id], CAP_C
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent], 1


    ; Clear spare edge completely.

    lea rax, [rel edges + ASMWEB_CAPACITY_DEPENDENCY_EDGE_size * 3]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id], 0
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id], 0
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent], 0

    ret


; ===========================================================================
; Qualification exit codes
;
;   0  PASS
;   1  canonical empty graph failed
;   2  valid dependency closure failed
;   3  insufficient aggregate child capacity accepted
;   4  configured > physical accepted
;   5  unknown parent accepted
;   6  unknown child accepted
;   7  self dependency accepted
;   8  zero multiplier accepted
;   9  rank inversion accepted
;   10 explicit directed cycle accepted
;   11 duplicate node identity accepted
;   12 duplicate edge accepted
;   13 multiplication overflow accepted
;   14 node count bound failed
;   15 edge count bound failed
;   16 canonical node pointer/count semantics failed
;   17 canonical edge pointer/count semantics failed
;   18 non-empty nodes with no dependencies failed
;   19 ABI/DF preservation failed
; ===========================================================================

_start:
    cld


    ; =======================================================================
    ; CASE 1 — canonical empty graph
    ; =======================================================================

    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_1


    ; =======================================================================
    ; CASE 2 — valid multi-level aggregate dependency closure
    ; =======================================================================

    call qual_build_valid_graph

    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_2


    ; =======================================================================
    ; CASE 3 — each C edge individually fits, aggregate does not
    ;
    ; B -> C = 60
    ; D -> C = 5
    ; C configured = 64
    ;
    ; 60 <= 64 and 5 <= 64 independently, but 65 > 64 collectively.
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 2]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], 64
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], 65


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_3


    ; =======================================================================
    ; CASE 4 — local configured > physical contradiction
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel nodes]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], 11
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], 10


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_4


    ; =======================================================================
    ; CASE 5 — unknown parent
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel edges]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id], \
        CAP_UNKNOWN


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_5


    ; =======================================================================
    ; CASE 6 — unknown child
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel edges]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id], \
        CAP_UNKNOWN


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_6


    ; =======================================================================
    ; CASE 7 — self dependency
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel edges]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id], CAP_A


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_7


    ; =======================================================================
    ; CASE 8 — zero multiplier
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel edges]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent], 0


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_8


    ; =======================================================================
    ; CASE 9 — topological rank inversion
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 2]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.dependency_rank], 1


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_9


    ; =======================================================================
    ; CASE 10 — explicit cycle C -> A
    ;
    ; Existing path:
    ;
    ;   A -> B -> C
    ;
    ; Adding C -> A creates:
    ;
    ;   A -> B -> C -> A
    ;
    ; No assignment of strict increasing rank can satisfy that cycle. The
    ; supplied canonical ranks therefore reject the closing edge.
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel edges + ASMWEB_CAPACITY_DEPENDENCY_EDGE_size * 3]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id], CAP_C
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id], CAP_A
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent], 1


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 4

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_10


    ; =======================================================================
    ; CASE 11 — duplicate node identity
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 3]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_NODE.capacity_id], CAP_A


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_11


    ; =======================================================================
    ; CASE 12 — duplicate edge
    ; =======================================================================

    call qual_build_valid_graph

    lea rax, [rel edges + ASMWEB_CAPACITY_DEPENDENCY_EDGE_size * 3]

    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.parent_capacity_id], CAP_A
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.child_capacity_id], CAP_B
    mov qword [rax + ASMWEB_CAPACITY_DEPENDENCY_EDGE.units_per_parent], 2


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 4

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_12


    ; =======================================================================
    ; CASE 13 — checked multiplication overflow
    ;
    ; A configured = UINT64_MAX
    ; A -> B multiplier = 2
    ; B itself is provisioned to UINT64_MAX so local validation succeeds.
    ; Dependency multiplication must still fail.
    ; =======================================================================

    call qual_build_valid_graph

    mov rax, ASMWEB_U64_MAX

    lea r10, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 0]
    mov [r10 + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], rax
    mov [r10 + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], rax

    lea r10, [rel nodes + ASMWEB_CAPACITY_DEPENDENCY_NODE_size * 1]
    mov [r10 + ASMWEB_CAPACITY_DEPENDENCY_NODE.configured_capacity], rax
    mov [r10 + ASMWEB_CAPACITY_DEPENDENCY_NODE.physical_capacity], rax


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_13


    ; =======================================================================
    ; CASE 14 — node count bound rejected before traversal
    ; =======================================================================

    call qual_build_valid_graph

    lea rdi, [rel nodes]
    mov esi, ASMWEB_M0_MAX_DEPENDENCY_NODES + 1
    xor edx, edx
    xor ecx, ecx

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_14


    ; =======================================================================
    ; CASE 15 — edge count bound rejected before traversal
    ; =======================================================================

    call qual_build_valid_graph

    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, ASMWEB_M0_MAX_DEPENDENCY_EDGES + 1

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_15


    ; =======================================================================
    ; CASE 16 — canonical node pointer/count
    ; =======================================================================

    xor edi, edi
    mov esi, 1
    xor edx, edx
    xor ecx, ecx

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    lea rdi, [rel nodes]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_16


    ; =======================================================================
    ; CASE 17 — canonical edge pointer/count
    ; =======================================================================

    call qual_build_valid_graph

    lea rdi, [rel nodes]
    mov esi, 4
    xor edx, edx
    mov ecx, 1

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    xor ecx, ecx

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_INTEGRITY
    jne .fail_17


    ; =======================================================================
    ; CASE 18 — independent configured nodes require no artificial edges
    ; =======================================================================

    call qual_build_valid_graph

    lea rdi, [rel nodes]
    mov esi, 4
    xor edx, edx
    xor ecx, ecx

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_18


    ; =======================================================================
    ; CASE 19 — ABI callee-saved + DF
    ; =======================================================================

    call qual_build_valid_graph


    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    std


    lea rdi, [rel nodes]
    mov esi, 4
    lea rdx, [rel edges]
    mov ecx, 3

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .fail_19


    cmp rbx, 0x11111111
    jne .fail_19

    cmp rbp, 0x22222222
    jne .fail_19

    cmp r12, 0x33333333
    jne .fail_19

    cmp r13, 0x44444444
    jne .fail_19

    mov rax, 0x55555555
    cmp r14, rax
    jne .fail_19

    mov rax, 0x66666666
    cmp r15, rax
    jne .fail_19


    pushfq
    pop rax

    test rax, 1 << 10
    jnz .fail_19


    xor edi, edi
    call asm_linux_exit
    ud2


.fail_1:
    mov edi, 1
    call asm_linux_exit
    ud2

.fail_2:
    mov edi, 2
    call asm_linux_exit
    ud2

.fail_3:
    mov edi, 3
    call asm_linux_exit
    ud2

.fail_4:
    mov edi, 4
    call asm_linux_exit
    ud2

.fail_5:
    mov edi, 5
    call asm_linux_exit
    ud2

.fail_6:
    mov edi, 6
    call asm_linux_exit
    ud2

.fail_7:
    mov edi, 7
    call asm_linux_exit
    ud2

.fail_8:
    mov edi, 8
    call asm_linux_exit
    ud2

.fail_9:
    mov edi, 9
    call asm_linux_exit
    ud2

.fail_10:
    mov edi, 10
    call asm_linux_exit
    ud2

.fail_11:
    mov edi, 11
    call asm_linux_exit
    ud2

.fail_12:
    mov edi, 12
    call asm_linux_exit
    ud2

.fail_13:
    mov edi, 13
    call asm_linux_exit
    ud2

.fail_14:
    mov edi, 14
    call asm_linux_exit
    ud2

.fail_15:
    mov edi, 15
    call asm_linux_exit
    ud2

.fail_16:
    mov edi, 16
    call asm_linux_exit
    ud2

.fail_17:
    mov edi, 17
    call asm_linux_exit
    ud2

.fail_18:
    mov edi, 18
    call asm_linux_exit
    ud2

.fail_19:
    mov edi, 19
    call asm_linux_exit
    ud2
