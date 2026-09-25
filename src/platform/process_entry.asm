bits 64

%include "asmweb/abi.inc"
%include "asmweb/startup.inc"
%include "linux/auxv.inc"

global asm_linux_parse_process_entry

section .text

; asm_linux_parse_process_entry
;
; Purpose:
;   Parse the Linux x86-64 initial process stack into a controlled
;   AsmWeb startup representation.
;
; ABI:
;   AsmWeb Internal ABI v1.
;
; Input:
;   RDI = pointer to original Linux process-entry stack
;   RSI = pointer to writable ASMWEB_STARTUP_INFO
;
; Result:
;   RAX = 0 on success
;   RAX = 1 on structural/bounds failure
;
; Mutation:
;   COMMITTED_MUTATION on success.
;   Output structure is zero-initialised before parsing; on failure
;   it remains safe but SHALL NOT be treated as valid startup state.
;
; Ownership:
;   Input stack is BORROWED.
;   Output structure is MUTABLE_BORROW.
;
; Resource acquisition:
;   None.
;
; Blocking:
;   No.
;
; Important:
;   This routine parses pointer-vector structure only.
;   It does NOT scan argv/environment strings.
;
; Initial Linux x86-64 stack:
;
;   argc
;   argv[0]
;   ...
;   argv[argc-1]
;   NULL
;   envp[0]
;   ...
;   NULL
;   auxv.type
;   auxv.value
;   ...
;   AT_NULL
;   0

asm_linux_parse_process_entry:
    ; Preserve callee-saved registers used by this function.
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Five pushes = 40 bytes.
    ;
    ; Ordinary entry RSP % 16 == 8.
    ; After 40 bytes, RSP % 16 == 0.
    ;
    ; This routine currently makes no ordinary calls.

    mov r12, rdi                    ; original process-entry stack
    mov r13, rsi                    ; output structure

    ; -----------------------------------------------------------------------
    ; Initialise output deterministically.
    ; -----------------------------------------------------------------------

    xor eax, eax

    mov [r13 + ASMWEB_STARTUP_INFO.argc], rax
    mov [r13 + ASMWEB_STARTUP_INFO.argv], rax
    mov [r13 + ASMWEB_STARTUP_INFO.envp], rax
    mov [r13 + ASMWEB_STARTUP_INFO.auxv], rax
    mov [r13 + ASMWEB_STARTUP_INFO.page_size], rax
    mov [r13 + ASMWEB_STARTUP_INFO.at_random], rax
    mov [r13 + ASMWEB_STARTUP_INFO.env_count], rax
    mov [r13 + ASMWEB_STARTUP_INFO.auxv_count], rax

    ; -----------------------------------------------------------------------
    ; argc / argv
    ; -----------------------------------------------------------------------

    mov rax, [r12]                  ; argc
    mov [r13 + ASMWEB_STARTUP_INFO.argc], rax

    ; argv begins immediately after argc.
    lea r14, [r12 + 8]
    mov [r13 + ASMWEB_STARTUP_INFO.argv], r14

    ; Calculate address of argv[argc].
    ;
    ; Reject multiplication/addition overflow.
    mov rbx, rax

    ; Multiplication by eight is valid only when the top three
    ; bits of argc are clear.
    mov rdx, rbx
    shr rdx, 61
    jnz .failure

    shl rbx, 3

    mov r15, r14
    add r15, rbx
    jc .failure

    ; -----------------------------------------------------------------------
    ; Explicit argv traversal bound.
    ;
    ; Arithmetic validity alone is not sufficient. A very large but
    ; non-overflowing argc could otherwise direct the parser far beyond the
    ; real initial process stack before argv[argc] is inspected.
    ;
    ; Keep the arithmetic checks above as independent defence-in-depth, then
    ; enforce the finite M0 vector bound before the first argc-derived
    ; dereference.
    ; -----------------------------------------------------------------------

    cmp rax, ASMWEB_M0_MAX_ARGV_ENTRIES
    ja .failure

    ; argv[argc] must be NULL.
    cmp qword [r15], 0
    jne .failure

    ; envp begins after argv terminating NULL.
    add r15, 8
    jc .failure

    mov [r13 + ASMWEB_STARTUP_INFO.envp], r15

    ; -----------------------------------------------------------------------
    ; Environment vector
    ; -----------------------------------------------------------------------

    xor ecx, ecx

.env_loop:
    ; Inspect the current slot first so that exactly
    ; ASMWEB_M0_MAX_ENVP_ENTRIES non-NULL entries are permitted,
    ; followed immediately by the required terminating NULL.
    mov rax, [r15]

    test rax, rax
    jz .env_done

    cmp rcx, ASMWEB_M0_MAX_ENVP_ENTRIES
    jae .failure

    inc rcx

    add r15, 8
    jc .failure

    jmp .env_loop

.env_done:
    mov [r13 + ASMWEB_STARTUP_INFO.env_count], rcx

    ; Skip envp terminating NULL.
    add r15, 8
    jc .failure

    mov [r13 + ASMWEB_STARTUP_INFO.auxv], r15

    ; -----------------------------------------------------------------------
    ; Auxiliary vector
    ; -----------------------------------------------------------------------

    xor ecx, ecx

.auxv_loop:
    ; Each auxv entry is two 64-bit words:
    ; type, value.
    ;
    ; Inspect the type first so that exactly
    ; ASMWEB_M0_MAX_AUXV_ENTRIES non-NULL entries are permitted,
    ; followed immediately by AT_NULL.
    mov rax, [r15]
    mov rdx, [r15 + 8]

    cmp rax, LINUX_AT_NULL
    je .auxv_done

    cmp rcx, ASMWEB_M0_MAX_AUXV_ENTRIES
    jae .failure

    cmp rax, LINUX_AT_PAGESZ
    jne .check_random

    mov [r13 + ASMWEB_STARTUP_INFO.page_size], rdx
    jmp .auxv_next

.check_random:
    cmp rax, LINUX_AT_RANDOM
    jne .auxv_next

    mov [r13 + ASMWEB_STARTUP_INFO.at_random], rdx

.auxv_next:
    inc rcx

    add r15, 16
    jc .failure

    jmp .auxv_loop

.auxv_done:
    mov [r13 + ASMWEB_STARTUP_INFO.auxv_count], rcx

    ; -----------------------------------------------------------------------
    ; Validate discovered base page size.
    ;
    ; The M0 bootstrap accepts only power-of-two page sizes within the
    ; provisional supported range.
    ; -----------------------------------------------------------------------

    mov rax, [r13 + ASMWEB_STARTUP_INFO.page_size]

    cmp rax, ASMWEB_M0_MIN_PAGE_SIZE
    jb .failure

    cmp rax, ASMWEB_M0_MAX_PAGE_SIZE
    ja .failure

    ; Power-of-two test:
    ;
    ;   n != 0 && (n & (n - 1)) == 0
    ;
    ; The range checks above already exclude zero.
    lea rdx, [rax - 1]
    test rax, rdx
    jnz .failure

    ; AT_RANDOM is required for later controlled entropy bootstrap.
    cmp qword [r13 + ASMWEB_STARTUP_INFO.at_random], 0
    je .failure

    xor eax, eax
    jmp .restore

.failure:
    mov eax, 1

.restore:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    ret
