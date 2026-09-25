%ifndef ASMWEB_LINUX_SYSCALL_INC
%define ASMWEB_LINUX_SYSCALL_INC

; Linux x86-64 syscall numbers used by AsmWeb.
;
; Keep this file intentionally small.
; Add syscall numbers only when implementation actually requires them.

%define LINUX_SYS_exit          60
%define LINUX_SYS_clock_gettime 228

%define LINUX_CLOCK_MONOTONIC   1

%endif
