%ifndef ASMWEB_ARITHMETIC_INC
%define ASMWEB_ARITHMETIC_INC 1


; ===========================================================================
; Checked unsigned 64-bit arithmetic
;
; Domain:
;   Non-negative capacity/accounting quantities represented as uint64.
;
; Common ABI:
;
;   RDI = operand A
;   RSI = operand B
;
; Result:
;
;   RAX = ASMWEB_RESOURCE_OK
;         ASMWEB_RESOURCE_INTEGRITY
;
;   RDX = calculated value on success
;         zero on failure
;
; Arithmetic failure is an integrity/configuration error, not ordinary bounded
; resource exhaustion.
;
; No routine:
;   - wraps;
;   - silently truncates;
;   - silently saturates;
;   - silently clamps.
; ===========================================================================


%define ASMWEB_U64_MAX 0xFFFFFFFFFFFFFFFF


%endif
