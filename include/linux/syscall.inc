%ifndef ASMWEB_LINUX_SYSCALL_INC
%define ASMWEB_LINUX_SYSCALL_INC

; Linux x86-64 syscall numbers used by AsmWeb.
;
; Keep this file intentionally small.
; Add syscall numbers only when implementation actually requires them.

%define LINUX_SYS_mmap           9
%define LINUX_SYS_munmap        11
%define LINUX_SYS_exit          60
%define LINUX_SYS_clock_gettime 228

%define LINUX_CLOCK_MONOTONIC   1

%endif


; ---------------------------------------------------------------------------
; Linux mmap protection and mapping flags used by M0.
; ---------------------------------------------------------------------------

%define LINUX_PROT_READ          0x1
%define LINUX_PROT_WRITE         0x2

%define LINUX_MAP_PRIVATE        0x02
%define LINUX_MAP_ANONYMOUS      0x20
