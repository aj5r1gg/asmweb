#!/usr/bin/env python3
"""M1 network foundation executable regression gate (not formal milestone closure)."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import subprocess
import sys

TARGETS = (
    'qualify-m1-network-abi',
    'qualify-udp-loopback',
    'qualify-tcp-accept4',
    'qualify-network-error-paths',
    'qualify-stream-fragments',
    'qualify-stream-short-write',
    'qualify-network-eintr',
    'qualify-udp-batch-transfer',
    'qualify-udp-batch-bounds',
    'qualify-udp-batch-mutations',
    'qualify-udp-checked-descriptors',
    'qualify-udp-checked-transfer',
    'qualify-udp-checked-mutations',
    'qualify-http-descriptor-lifecycle',
    'qualify-http-descriptor-mutations',
)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    args = parser.parse_args()
    root = args.root.resolve()
    if not (root / 'Makefile').is_file() or not (root / 'src/linux/network.asm').is_file():
        print('M1_ACCEPTANCE=FAIL: run in AsmWeb repository root', file=sys.stderr)
        return 2
    if len(TARGETS) != len(set(TARGETS)):
        print('M1_ACCEPTANCE=FAIL: duplicate qualification target', file=sys.stderr)
        return 2
    # Make must recognise every target before any is executed; no hidden omissions.
    for target in TARGETS:
        result = subprocess.run(['make', '-s', '-n', target], cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        if result.returncode:
            print(f'M1_ACCEPTANCE=FAIL: missing target {target}: {result.stderr.strip()}', file=sys.stderr)
            return 2
    print(f'M1_ACCEPTANCE_TARGETS={len(TARGETS)}', flush=True)
    for index, target in enumerate(TARGETS, 1):
        print(f'[{index:02}/{len(TARGETS):02}] {target}', flush=True)
        result = subprocess.run(['make', '--no-print-directory', '-s', target], cwd=root)
        if result.returncode:
            print(f'M1_ACCEPTANCE=FAIL target={target} exit={result.returncode}', flush=True)
            return 1
    print('M1_NETWORK_FOUNDATION_ACCEPTANCE=PASS', flush=True)
    print('M1_FORMAL_MILESTONE_CLOSURE=NOT_ASSERTED', flush=True)
    return 0

if __name__ == '__main__':
    sys.exit(main())
