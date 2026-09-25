bits 64

%include "asmweb/abi.inc"
%include "asmweb/startup.inc"
%include "asmweb/memory.inc"
%include "linux/syscall.inc"

global asm_memory_map_rw
global asm_memory_unmap

extern asm_linux_mmap
extern asm_linux_munmap

section .text

; ---------------------------------------------------------------------------
; asm_memory_map_rw
;
; Purpose:
;   Acquire one anonymous private read/write mapping.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Input:
;
;   RDI = requested byte count
;   RSI = validated runtime page size
;   RDX = pointer to writable ASMWEB_MEMORY_MAPPING
;
; Result:
;
;   RAX = 0 on success
;   RAX = 1 on failure
;
; Success invariants:
;
;   base != 0
;   length >= requested byte count
;   length is page-aligned
;   ready = 1
;
; Mapping policy:
;
;   PROT_READ | PROT_WRITE
;   MAP_PRIVATE | MAP_ANONYMOUS
;   fd = -1
;   offset = 0
;
; No PROT_EXEC permission is requested.
;
; Failure:
;   An initially empty destination remains deterministically zeroed.
;
;   A non-empty destination is rejected without modification because it may
;   represent an already-owned live resource.
;
; Callee-saved registers:
;   RBX, R12, R13 preserved.
;
; Direction flag:
;   Clear on return.

asm_memory_map_rw:
    cld

    test rdx, rdx
    jz .failure_no_destination

    push rbx
    push r12
    push r13

    ; Three pushes from ordinary entry establish RSP % 16 == 0.
    mov r13, rdx

    ; -----------------------------------------------------------------------
    ; Ownership precondition.
    ;
    ; A non-empty record may represent a live mapping. Never erase or
    ; overwrite such state: doing so could orphan the owned resource.
    ;
    ; New acquisition therefore requires a fully empty destination record.
    ; -----------------------------------------------------------------------

    cmp qword [r13 + ASMWEB_MEMORY_MAPPING.base], 0
    jne .failure_preserve_state

    cmp qword [r13 + ASMWEB_MEMORY_MAPPING.length], 0
    jne .failure_preserve_state

    cmp qword [r13 + ASMWEB_MEMORY_MAPPING.ready], 0
    jne .failure_preserve_state

    ; Deterministic empty destination state.
    xor eax, eax
    mov [r13 + ASMWEB_MEMORY_MAPPING.base], rax
    mov [r13 + ASMWEB_MEMORY_MAPPING.length], rax
    mov [r13 + ASMWEB_MEMORY_MAPPING.ready], rax

    ; Request must be non-zero.
    test rdi, rdi
    jz .failure

    mov rbx, rdi
    mov r12, rsi

    ; Re-validate the page-size invariant at this boundary.
    cmp r12, ASMWEB_M0_MIN_PAGE_SIZE
    jb .failure

    cmp r12, ASMWEB_M0_MAX_PAGE_SIZE
    ja .failure

    mov rax, r12
    lea rcx, [rax - 1]
    test rax, rcx
    jnz .failure

    ; -----------------------------------------------------------------------
    ; Checked round-up:
    ;
    ;   aligned = (requested + page_size - 1) & ~(page_size - 1)
    ; -----------------------------------------------------------------------

    mov rax, r12
    dec rax

    mov rcx, rbx
    add rcx, rax
    jc .failure

    not rax
    and rcx, rax

    ; A valid non-zero request cannot produce a zero aligned size.
    test rcx, rcx
    jz .failure

    ; Preserve aligned length across mmap.
    mov r12, rcx

    ; -----------------------------------------------------------------------
    ; mmap(
    ;   NULL,
    ;   aligned_length,
    ;   PROT_READ | PROT_WRITE,
    ;   MAP_PRIVATE | MAP_ANONYMOUS,
    ;   -1,
    ;   0
    ; )
    ; -----------------------------------------------------------------------

    xor edi, edi
    mov rsi, r12
    mov edx, LINUX_PROT_READ | LINUX_PROT_WRITE
    mov ecx, LINUX_MAP_PRIVATE | LINUX_MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d

    call asm_linux_mmap

    ; Linux syscall failures occupy the range -4095 through -1.
    cmp rax, -4095
    jae .failure

    ; Anonymous mmap should not return NULL for this interface.
    test rax, rax
    jz .failure

    mov [r13 + ASMWEB_MEMORY_MAPPING.base], rax
    mov [r13 + ASMWEB_MEMORY_MAPPING.length], r12
    mov qword [r13 + ASMWEB_MEMORY_MAPPING.ready], 1

    pop r13
    pop r12
    pop rbx

    xor eax, eax
    ret

.failure:
    ; The destination was proven empty before acquisition began, therefore
    ; deterministic zeroing is safe here.
    xor eax, eax
    mov [r13 + ASMWEB_MEMORY_MAPPING.base], rax
    mov [r13 + ASMWEB_MEMORY_MAPPING.length], rax
    mov [r13 + ASMWEB_MEMORY_MAPPING.ready], rax

.failure_preserve_state:
    pop r13
    pop r12
    pop rbx

    mov eax, 1
    ret

.failure_no_destination:
    mov eax, 1
    ret


; ---------------------------------------------------------------------------
; asm_memory_unmap
;
; Purpose:
;   Release one live ASMWEB_MEMORY_MAPPING.
;
; Input:
;
;   RDI = pointer to mutable ASMWEB_MEMORY_MAPPING
;
; Result:
;
;   RAX = 0 on successful release
;   RAX = 1 on failure
;
; Success:
;   Mapping state is zeroed after the kernel confirms unmap.
;
; Failure:
;   Existing mapping state is left intact because the resource may still
;   remain live and owned.
;
; Callee-saved registers:
;   RBX preserved.

asm_memory_unmap:
    cld

    test rdi, rdi
    jz .unmap_failure_no_state

    push rbx
    mov rbx, rdi

    cmp qword [rbx + ASMWEB_MEMORY_MAPPING.ready], 1
    jne .unmap_failure

    mov rdi, [rbx + ASMWEB_MEMORY_MAPPING.base]
    test rdi, rdi
    jz .unmap_failure

    mov rsi, [rbx + ASMWEB_MEMORY_MAPPING.length]
    test rsi, rsi
    jz .unmap_failure

    call asm_linux_munmap

    test rax, rax
    jnz .unmap_failure

    xor eax, eax
    mov [rbx + ASMWEB_MEMORY_MAPPING.base], rax
    mov [rbx + ASMWEB_MEMORY_MAPPING.length], rax
    mov [rbx + ASMWEB_MEMORY_MAPPING.ready], rax

    pop rbx

    xor eax, eax
    ret

.unmap_failure:
    pop rbx

.unmap_failure_no_state:
    mov eax, 1
    ret
