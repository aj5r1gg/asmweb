#!/usr/bin/env python3
"""Signed scope reaches IR without granting unearned normative qualification."""
import copy
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'qualification/tools'))
import m0_invariant_scope as scope
import m0_normative_ir as ir


def command(*args):
    result = subprocess.run(['openssl', *args], capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(result.stderr)


def main():
    baseline = ir.build()
    ledger, _ = scope.load(scope.LEDGER)
    with tempfile.TemporaryDirectory(prefix='asmweb-signed-ir-') as temp:
        tmp = Path(temp)
        private, public = tmp / 'private.pem', tmp / 'public.pem'
        payload, signature, ledger_file = (
            tmp / 'payload.json', tmp / 'signature', tmp / 'ledger.json'
        )
        command('genpkey', '-algorithm', 'ED25519', '-out', str(private))
        command('pkey', '-in', str(private), '-pubout', '-out', str(public))
        signed = copy.deepcopy(ledger)
        signed['authority_status'] = 'ESTABLISHED'
        mandatory = signed['entries'][0]
        deferred = signed['entries'][1]
        for row, decision, milestone in (
            (mandatory, 'M0_REQUIRED', 'M0'),
            (deferred, 'DEFERRED_APPROVED', 'M2'),
        ):
            row['decision'] = decision
            row['first_mandatory_milestone'] = milestone
            row['semantic_rationale'] = (
                'Test-only reviewed semantic decision, verified under an '
                'ephemeral key; no normative adoption is conferred.'
            )
            row['qualified_evidence_refs'] = [
                'qualification/invariants/ir-normative-source-v0.3.json'
            ]
            row['authorisation_ref'] = (
                'qualification/invariants/m0-scope-decisions-v0.1.sig'
            )
        payload.write_bytes(scope.canonical(signed))
        ledger_file.write_bytes(scope.canonical(signed))
        command('pkeyutl', '-sign', '-inkey', str(private), '-rawin',
                '-in', str(payload), '-out', str(signature))
        original_ledger = scope.LEDGER
        original_verifier = scope.verified_decisions
        try:
            scope.LEDGER = ledger_file
            scope.verified_decisions = lambda: original_verifier(
                public_key=public, signature=signature
            )
            output = ir.build()
            rows = {e['invariant_id']: e for e in output['entries']}
            a = rows[mandatory['invariant_id']]
            b = rows[deferred['invariant_id']]
            assert a['scope'] == 'M0_FOUNDATION'
            assert a['first_required_milestone'] == 'M0'
            assert b['scope'] == 'DEFERRED_FROM_M0'
            assert b['first_required_milestone'] == 'M2'
            assert a['status'] is None and b['status'] is None
            assert output['authoritative_ir_complete'] is False
            print('SIGNED_IR_SCOPE_PROJECTION=PASS')
            print('SCOPE_DECISION_NOT_NORMATIVE_APPROVAL=PASS')
            # Mutation of the signed ledger must not reach the IR.
            signed['entries'][1]['first_mandatory_milestone'] = 'M3'
            ledger_file.write_bytes(scope.canonical(signed))
            try:
                ir.build()
            except ValueError:
                print('FORGED_IR_SCOPE_PROJECTION=REJECTED')
            else:
                raise AssertionError('FORGED_SCOPE_PROJECTED')
        finally:
            scope.LEDGER = original_ledger
            scope.verified_decisions = original_verifier
    assert ir.canonical(ir.build()) == ir.canonical(baseline)
    assert ir.OUTPUT.read_bytes() == ir.canonical(baseline)
    print('PUBLISHED_IR_UNCHANGED=PASS')
    print('M0_SIGNED_IR_PROJECTION=PASS')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, ValueError, KeyError, OSError, TypeError) as exc:
        print('M0_SIGNED_IR_PROJECTION=FAIL:', exc, file=sys.stderr)
        sys.exit(1)
