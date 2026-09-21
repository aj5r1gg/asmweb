%ifndef ASMWEB_ABI_INC
%define ASMWEB_ABI_INC

; AsmWeb Internal ABI v1
;
; Integer / pointer arguments:
;
;   arg1 = RDI
;   arg2 = RSI
;   arg3 = RDX
;   arg4 = RCX
;   arg5 = R8
;   arg6 = R9
;
; Primary result:
;
;   RAX
;
; Optional documented secondary result:
;
;   RDX
;
; Caller-saved:
;
;   RAX RCX RDX RSI RDI R8 R9 R10 R11
;
; Callee-saved:
;
;   RBX RBP R12 R13 R14 R15
;
; Condition flags:
;
;   caller-clobbered
;
; Direction flag:
;
;   SHALL be clear at ordinary call and return boundaries.
;
; Stack:
;
;   ordinary internal calls SHALL preserve the required
;   System V AMD64-compatible 16-byte call-boundary alignment.

%define ASMWEB_INTERNAL_ABI_VERSION 1

%endif
