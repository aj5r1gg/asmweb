bits 64

%include "asmweb/abi.inc"
%include "asmweb/resource.inc"
%include "asmweb/startup.inc"
%include "asmweb/entropy.inc"
%include "asmweb/cpu.inc"
%include "asmweb/time.inc"
%include "asmweb/process_runtime.inc"
%include "asmweb/startup_memory.inc"
%include "asmweb/registry.inc"
%include "asmweb/memory_ceiling.inc"
%include "asmweb/config_dependency.inc"
%include "asmweb/runtime_invariant.inc"
%include "asmweb/diagnostic.inc"

global asm_runtime_main

extern asm_abi_probe
extern asm_http_serve_forever
extern asm_entropy_bootstrap
extern asm_cpu_discover
extern asm_monotonic_now

extern asm_process_runtime_init
extern asm_process_runtime_validate
extern asm_process_runtime_publish_ready

extern asm_startup_memory_account_init
extern asm_startup_memory_account_baseline

extern asm_memory_direct_capacity_from_mot
extern asm_capacity_dependency_validate
extern asm_diagnostic_init
extern asm_runtime_ready_validate_diagnose

extern asm_runtime_rules_init
extern asm_runtime_rules_get

extern asm_production_registry_init
extern asm_production_registry_get

section .text

; asm_runtime_main
;
; Purpose:
;   Initial ordinary AsmWeb runtime entry point.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Input:
;   RDI = pointer to validated ASMWEB_STARTUP_INFO
;   RSI = pointer to writable ASMWEB_ENTROPY_BOOTSTRAP
;   RDX = pointer to writable ASMWEB_CPU_INFO
;   RCX = pointer to writable ASMWEB_MONOTONIC_TIME
;   R8  = pointer to writable ASMWEB_PROCESS_RUNTIME
;   R9  = pointer to writable ASMWEB_STARTUP_MEMORY_ACCOUNT
;
; Result:
;   RAX = process status.
;
; Current M0 responsibilities:
;
;   - accept controlled startup state explicitly;
;   - initialise process-runtime and startup-memory accounting state;
;   - publish the canonical Runtime Rule Registry;
;   - publish the canonical production OLR/MOT/RCT projection;
;   - establish entropy, CPU and monotonic-time bootstrap state;
;   - publish READY only through the controlled READY gate;
;   - validate the resulting production process-runtime state;
;   - qualify the initial Internal ABI contract.
;
; Exit status:
;   0 = runtime bootstrap, controlled READY publication and ABI probe passed.
;   1 = runtime bootstrap, READY publication or ABI probe failed.
;
; Callee-saved registers:
;   RBX RBP R12 R13 R14 R15 preserved.
;
; Stack:
;   Ordinary callee entry:
;       RSP % 16 == 8
;
;   Six 8-byte callee-saved pushes:
;       RSP % 16 == 8
;
;   Additional 8-byte alignment adjustment:
;       RSP % 16 == 0 before CALL.

asm_runtime_main:
    cld

    ; -----------------------------------------------------------------------
    ; Validate explicit controlled startup state.
    ; -----------------------------------------------------------------------

    test rdi, rdi
    jz .early_failure

    test rsi, rsi
    jz .early_failure

    test rdx, rdx
    jz .early_failure

    test rcx, rcx
    jz .early_failure

    test r8, r8
    jz .early_failure

    test r9, r9
    jz .early_failure

    cmp qword [rdi + ASMWEB_STARTUP_INFO.page_size], 0
    je .early_failure

    cmp qword [rdi + ASMWEB_STARTUP_INFO.at_random], 0
    je .early_failure

    ; -----------------------------------------------------------------------
    ; Preserve the Internal ABI callee-saved register set used by this
    ; qualification routine.
    ; -----------------------------------------------------------------------

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Entry is RSP % 16 == 8.
    ; Six pushes consume 48 bytes and preserve that modulus.
    ;
    ; Local frame:
    ;
    ;   [rsp + 0]   published registry-set pointer
    ;   [rsp + 8]   temporary ASMWEB_RUNTIME_INVARIANT_VIEW
    ;   [rsp + 96]  padding
    ;   [rsp + 104] caller-owned ASMWEB_DIAGNOSTIC (48 bytes)
    ;
    ; ASMWEB_RUNTIME_INVARIANT_VIEW is 88 bytes.
    ; ASMWEB_DIAGNOSTIC is 48 bytes.
    ;
    ; Total local frame = 152 bytes.
    ; 152 mod 16 == 8; RSP is aligned before CALL.
    ; Diagnostic storage is transient and single-writer only.
    sub rsp, 152

    ; Preserve explicit bootstrap-state pointers in callee-saved registers.
    mov rbx, rdi
    mov rbp, rsi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, r9

    ; Establish a pristine caller-owned diagnostic record.
    ;
    ; Reserving stack space does not zero it. The diagnostic
    ; initializer requires every field to be zero before READY
    ; publication. Explicitly clear the entire 48-byte record.
    ;
    ; RDI, RAX and RCX are caller-saved. All six original runtime
    ; input pointers have already been retained in callee-saved
    ; registers. DF remains clear at call boundaries.
    ;
    ; No allocation, syscalls or persistent diagnostic storage.

%if ASMWEB_DIAGNOSTIC_size != 48
    %error "Unexpected diagnostic record size: review stack layout"
%endif

    lea rdi, [rsp + 104]
    xor eax, eax
    mov ecx, ASMWEB_DIAGNOSTIC_size / 8
    rep stosq

    lea rdi, [rsp + 104]
    call asm_diagnostic_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure


    ; -----------------------------------------------------------------------
    ; Establish canonical process-runtime state.
    ; -----------------------------------------------------------------------

    mov rdi, r14
    call asm_process_runtime_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure


    ; -----------------------------------------------------------------------
    ; Establish startup direct-memory accounting state.
    ;
    ; This first creates the structurally valid empty accounting authority.
    ; After the canonical production registry has published, the account is
    ; reconciled to the MOT-derived fixed registered state already retained
    ; during INITIALISATION.
    ;
    ; Future startup-only acquisitions may raise peak_bytes above that baseline.
    ; -----------------------------------------------------------------------

    mov rdi, r15
    call asm_startup_memory_account_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure


    ; -----------------------------------------------------------------------
    ; Materialise and publish the canonical Runtime Rule Registry.
    ; -----------------------------------------------------------------------

    call asm_runtime_rules_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure

    call asm_runtime_rules_get

    test rax, rax
    jz .failure

    test rdx, rdx
    jz .failure


    ; -----------------------------------------------------------------------
    ; Materialise, validate and publish the canonical production OLR/MOT/RCT
    ; projection.
    ;
    ; Preserve the published registry-set pointer in the existing eight-byte
    ; stack slot until all remaining bootstrap prerequisites have completed.
    ; -----------------------------------------------------------------------

    call asm_production_registry_init

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure

    call asm_production_registry_get

    test rax, rax
    jz .failure

    mov [rsp], rax


    ; -----------------------------------------------------------------------
    ; Reconcile startup accounting with registered fixed state that already
    ; exists during INITIALISATION.
    ;
    ; The baseline is mechanically derived from the authoritative production
    ; MOT. No separately maintained byte total is permitted here.
    ; -----------------------------------------------------------------------

    mov rdi, [rax + ASMWEB_REGISTRY_VALIDATION_SET.mot_ptr]
    mov rsi, [rax + ASMWEB_REGISTRY_VALIDATION_SET.mot_count]

    call asm_memory_direct_capacity_from_mot

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure

    ; Current production M0 contains registered fixed retained state.
    test rdx, rdx
    jz .failure

    mov rdi, r15
    mov rsi, rdx

    call asm_startup_memory_account_baseline

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure

    ; The baseline primitive returns its established current byte count.
    test rdx, rdx
    jz .failure


    ; -----------------------------------------------------------------------
    ; Transfer Linux AT_RANDOM material into AsmWeb-owned state.
    ; -----------------------------------------------------------------------

    mov rdi, rbx
    mov rsi, rbp
    call asm_entropy_bootstrap

    test eax, eax
    jnz .failure

    cmp qword [rbp + ASMWEB_ENTROPY_BOOTSTRAP.ready], 1
    jne .failure

    ; The raw borrowed AT_RANDOM pointer must be invalidated after transfer.
    cmp qword [rbx + ASMWEB_STARTUP_INFO.at_random], 0
    jne .failure

    ; -----------------------------------------------------------------------
    ; Discover CPU feature state once into AsmWeb-owned storage.
    ; -----------------------------------------------------------------------

    mov rdi, r12
    call asm_cpu_discover

    test eax, eax
    jnz .failure

    cmp qword [r12 + ASMWEB_CPU_INFO.ready], 1
    jne .failure

    ; M0 x86-64 baseline requires SSE2.
    bt qword [r12 + ASMWEB_CPU_INFO.features], ASMWEB_CPU_FEATURE_SSE2
    jnc .failure

    ; -----------------------------------------------------------------------
    ; Establish one controlled CLOCK_MONOTONIC bootstrap sample.
    ; -----------------------------------------------------------------------

    mov rdi, r13
    call asm_monotonic_now

    test eax, eax
    jnz .failure

    cmp qword [r13 + ASMWEB_MONOTONIC_TIME.ready], 1
    jne .failure

    cmp qword [r13 + ASMWEB_MONOTONIC_TIME.nsec], ASMWEB_NSEC_PER_SEC
    jae .failure


    ; -----------------------------------------------------------------------
    ; Validate the complete current production capacity-dependency graph.
    ;
    ; The present M0 production graph is canonically empty:
    ;
    ;   - the production RCT is empty;
    ;   - current production MOT entries are fixed process-persistent count-1
    ;     objects;
    ;   - no cross-capacity production dependency has yet been introduced.
    ;
    ; An empty graph is still passed through the authoritative dependency
    ; validator before READY. When production dependent capacities are added,
    ; this call site is the required startup gate and must receive that
    ; resolved graph rather than being bypassed.
    ; -----------------------------------------------------------------------

    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx

    call asm_capacity_dependency_validate

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure


    ; -----------------------------------------------------------------------
    ; Publish the real production process READY state.
    ;
    ; Every currently established M0 production bootstrap prerequisite above
    ; has succeeded. The READY gate re-validates the production registry,
    ; derives M_direct_capacity_max with checked arithmetic, validates startup
    ; memory accounting and commits READY failure-atomically.
    ; -----------------------------------------------------------------------

    mov rdi, r14
    mov rsi, [rsp]
    mov rdx, r15

    call asm_process_runtime_publish_ready

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure

    ; -----------------------------------------------------------------------
    ; Compose and validate the global M0 READY invariant set.
    ;
    ; The view is temporary stack-local state. It borrows authoritative
    ; runtime objects and owns none of them.
    ;
    ; Current production dependency graph remains canonically empty.
    ; -----------------------------------------------------------------------

    lea r10, [rsp + 8]

    mov [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.startup_info_ptr], rbx
    mov [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.entropy_ptr], rbp
    mov [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.cpu_ptr], r12
    mov [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.time_ptr], r13

    mov [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.process_runtime_ptr], r14
    mov [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.startup_memory_ptr], r15

    mov rax, [rsp]
    mov [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.registry_ptr], rax

    mov qword [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_nodes_ptr], 0
    mov qword [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_node_count], 0
    mov qword [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_edges_ptr], 0
    mov qword [r10 + ASMWEB_RUNTIME_INVARIANT_VIEW.dependency_edge_count], 0

    mov rdi, r10
    lea rsi, [rsp + 104]
    call asm_runtime_ready_validate_diagnose

    cmp eax, ASMWEB_RESOURCE_OK
    jne .failure

    ; Current production MOT contains registered fixed retained state.
    test rdx, rdx
    jz .failure


    ; -----------------------------------------------------------------------
    ; The production runtime has now earned READY.
    ;
    ; The ABI probe remains temporarily in the ordinary runtime path as the
    ; final M0 foundation check.
    ; -----------------------------------------------------------------------

    ; Seed callee-saved registers with known values for the ABI probe.
    mov rbx, 0x11111111
    mov rbp, 0x22222222
    mov r12, 0x33333333
    mov r13, 0x44444444
    mov r14, 0x55555555
    mov r15, 0x66666666

    ; Six Internal ABI arguments.
    mov edi, 0x11
    mov esi, 0x22
    mov edx, 0x33
    mov ecx, 0x44
    mov r8d, 0x55
    mov r9d, 0x66

    call asm_abi_probe

    ; Verify primary result.
    mov r10, 0x123456789abcdef0
    cmp rax, r10
    jne .failure

    ; Verify the called routine preserved callee-saved registers.
    cmp rbx, 0x11111111
    jne .failure

    cmp rbp, 0x22222222
    jne .failure

    cmp r12, 0x33333333
    jne .failure

    cmp r13, 0x44444444
    jne .failure

    cmp r14, 0x55555555
    jne .failure

    cmp r15, 0x66666666
    jne .failure

    ; Verify DF is clear.
    pushfq
    pop r10
    test r10, 1 << 10
    jnz .failure

    ; M1 prototype: serve one loopback HTTP connection only
    ; after all M0 READY and ABI gates have passed.
    call asm_http_serve_forever
    test eax, eax
    jnz .failure

    xor eax, eax
    jmp .restore

.failure:
    cld
    mov eax, 1

.restore:
    add rsp, 152

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ret

.early_failure:
    cld
    mov eax, 1
    ret
