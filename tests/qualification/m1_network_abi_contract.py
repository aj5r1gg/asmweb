#!/usr/bin/env python3
"""M1: fail-closed source-level checks for the Linux x86-64 network ABI.

These are supplementary contract checks; executable network tests remain mandatory.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'src/linux/network.asm'

# Direct wrappers and their required Linux syscall dispatch. Higher-level checked
# wrappers are tested for validation and delegation separately.
RAW = {
    'socket': 'socket', 'bind': 'bind', 'listen': 'listen',
    'accept': 'accept', 'accept4': 'accept4', 'recv': 'read',
    'send': 'sendto', 'recvfrom': 'recvfrom', 'sendto': 'sendto',
    'recvmmsg': 'recvmmsg', 'sendmmsg': 'sendmmsg',
    'getsockname': 'getsockname', 'getpeername': 'getpeername',
    'close': 'close', 'setsockopt': 'setsockopt',
}
FORWARD_R10 = {'accept4', 'send', 'recvfrom', 'sendto', 'recvmmsg', 'sendmmsg', 'setsockopt'}
NOSIGNAL = {'send', 'sendto', 'sendmmsg'}
FORBIDDEN_CALLEE_WRITES = re.compile(r'^\s*(?:mov|lea|xor|add|sub|inc|dec|pop|and|or|xchg)\s+(?:rbx|ebx|rbp|ebp|r1[2-5][dwb]?)\b', re.I | re.M)


def blocks(source: str) -> dict[str, str]:
    # NASM global function labels start at column zero; local labels begin with a dot.
    matches = list(re.finditer(r'^asm_linux_([a-z0-9_]+):\s*$', source, re.M))
    out = {}
    for idx, match in enumerate(matches):
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(source)
        body = source[match.end():end]
        out[match.group(1)] = '\n'.join(line.split(';', 1)[0].strip() for line in body.splitlines())
    return out


def check(source: str) -> list[str]:
    entries = blocks(source)
    errors = []
    for name, sys_name in RAW.items():
        body = entries.get(name)
        if body is None:
            errors.append(f'{name}: missing exported wrapper')
            continue
        expected = rf'\bmov\s+eax\s*,\s*LINUX_SYS_{sys_name}\b'
        if not re.search(expected, body, re.I):
            errors.append(f'{name}: wrong syscall number / dispatcher')
        if len(re.findall(r'\bsyscall\b', body, re.I)) != 1:
            errors.append(f'{name}: expected exactly one syscall')
        if not re.search(r'\bret\b', body):
            errors.append(f'{name}: missing return')
        if name in FORWARD_R10 and not re.search(r'\bmov\s+r10\s*,\s*rcx\b', body, re.I):
            errors.append(f'{name}: missing fourth-argument RCX->R10 translation')
        if name in NOSIGNAL and not re.search(r'\bor\s+r10d\s*,\s*LINUX_MSG_NOSIGNAL\b', body, re.I):
            errors.append(f'{name}: SIGPIPE suppression missing')
        if name == 'send':
            for op in (r'xor\s+r8d\s*,\s*r8d', r'xor\s+r9d\s*,\s*r9d'):
                if not re.search(op, body, re.I):
                    errors.append(f'{name}: missing null destination argument')
        if FORBIDDEN_CALLEE_WRITES.search(body):
            errors.append(f'{name}: callee-saved register modified')
        if re.search(r'\bcall\b|\bpush\b|\bloop\b', body, re.I):
            errors.append(f'{name}: implicit retry/call/stack modification')
    for name, delegate in [('recvmmsg_bounded', 'recvmmsg'), ('sendmmsg_bounded', 'sendmmsg'),
                            ('recvmmsg_checked', 'recvmmsg'), ('sendmmsg_checked', 'sendmmsg')]:
        body = entries.get(name)
        if not body:
            errors.append(f'{name}: missing validated wrapper')
            continue
        if not re.search(rf'\bjmp\s+asm_linux_{delegate}\b', body):
            errors.append(f'{name}: not delegating to raw syscall boundary')
        if not re.search(r'\bmov\s+rax\s*,\s*-LINUX_EINVAL\b', body):
            errors.append(f'{name}: missing -EINVAL rejection')
        if not re.search(r'\bcmp\s+rdx\s*,\s*ASMWEB_UDP_BATCH_MAX\b', body):
            errors.append(f'{name}: missing finite batch bound')
        if FORBIDDEN_CALLEE_WRITES.search(body):
            errors.append(f'{name}: callee-saved register modified')
    return errors


def main() -> int:
    text = SOURCE.read_text(encoding='utf-8')
    issues = check(text)
    for issue in issues:
        print(f'ABI_CONTRACT_FAIL={issue}')
    if issues:
        return 1
    mutations = [
        ('wrong-syscall', 'mov eax, LINUX_SYS_accept4', 'mov eax, LINUX_SYS_accept'),
        ('missing-r10', 'mov r10, rcx\n    mov eax, LINUX_SYS_accept4', 'mov eax, LINUX_SYS_accept4'),
        ('missing-nosignal', 'or r10d, LINUX_MSG_NOSIGNAL', 'nop'),
        ('missing-batch-bound', 'cmp rdx, ASMWEB_UDP_BATCH_MAX', 'nop'),
        ('missing-einval', 'mov rax, -LINUX_EINVAL', 'xor eax, eax'),
    ]
    for title, before, after in mutations:
        if before not in text:
            print(f'ABI_MUTATION_SETUP_FAIL={title}')
            return 1
        if not check(text.replace(before, after, 1)):
            print(f'ABI_MUTATION_UNDETECTED={title}')
            return 1
        print(f'ABI_MUTATION_REJECTED={title}')
    print(f'M1_NETWORK_ABI_WRAPPERS={len(RAW) + 4}')
    print('M1_NETWORK_ABI_CONTRACT=PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
