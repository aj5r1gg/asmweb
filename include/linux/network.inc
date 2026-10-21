%ifndef ASMWEB_LINUX_NETWORK_INC
%define ASMWEB_LINUX_NETWORK_INC

; Linux x86-64 syscall numbers.
%define LINUX_SYS_read       0
%define LINUX_SYS_close      3
%define LINUX_SYS_socket    41
%define LINUX_SYS_accept    43
%define LINUX_SYS_accept4  288
%define LINUX_SYS_sendto    44
%define LINUX_SYS_recvfrom  45
%define LINUX_SYS_bind      49
%define LINUX_SYS_listen    50
%define LINUX_SYS_getsockname 51
%define LINUX_SYS_getpeername 52
%define LINUX_SYS_setsockopt 54
%define LINUX_SYS_recvmmsg 299
%define LINUX_SYS_sendmmsg 307

; Provisional M1 UDP batch upper bound.
; Not yet an approved effective limit.
%define ASMWEB_UDP_BATCH_MAX 16

; Provisional checked connected-UDP descriptor profile.
; These are engineering limits, not approved LIM identities.
%define ASMWEB_UDP_CHECKED_IOV_MAX 1
%define ASMWEB_UDP_CHECKED_PAYLOAD_MAX 65507
%define ASMWEB_LINUX_MMSGHDR_BYTES 64
%define ASMWEB_LINUX_MSG_IOV_OFFSET 16
%define ASMWEB_LINUX_MSG_IOVLEN_OFFSET 24
%define ASMWEB_LINUX_MSG_CONTROL_OFFSET 32
%define ASMWEB_LINUX_MSG_CONTROLLEN_OFFSET 40
%define LINUX_EINVAL 22
%define LINUX_SOCK_CLOEXEC 0x80000
%define LINUX_SOL_SOCKET 1
%define LINUX_SO_REUSEADDR 2
%define LINUX_SO_RCVTIMEO 20
%define LINUX_SO_SNDTIMEO 21

; Linux socket constants.
%define LINUX_AF_INET        2
%define LINUX_SOCK_STREAM    1
%define LINUX_SOCK_DGRAM     2
%define LINUX_SOCK_NONBLOCK  0x800
%define LINUX_IPPROTO_TCP    6
%define LINUX_IPPROTO_UDP    17

; Suppress SIGPIPE for socket sends.
%define LINUX_MSG_NOSIGNAL  0x4000

%endif
