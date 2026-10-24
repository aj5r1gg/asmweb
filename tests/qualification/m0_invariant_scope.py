#!/usr/bin/env python3
"""Adversarial acceptance of source-bound scope, without invented approvals."""
import copy
import subprocess
import tempfile
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'qualification/tools'))
import m0_invariant_scope as scope

def main():
    source,sb=scope.load(scope.SOURCE)
    assessment,ab=scope.load(scope.ASSESSMENT)
    baseline,_=scope.load(scope.LEDGER)
    result=scope.verify_document(baseline,source,sb,assessment,ab)
    assert result=={'pending':42,'required':0,'deferred':0}
    def rejects(label,modify):
        doc=copy.deepcopy(baseline)
        modify(doc)
        try: scope.verify_document(doc,source,sb,assessment,ab)
        except (ValueError,KeyError,TypeError):
            print(label+'=REJECTED')
            return
        raise AssertionError(label+' ACCEPTED')
    rejects('FORGED_SOURCE_DIGEST',lambda d:d.update(source_sha256='0'*64))
    rejects('FORGED_ASSESSMENT_DIGEST',lambda d:d.update(assessment_sha256='0'*64))
    rejects('MISSING_IDENTITY',lambda d:d['entries'].pop())
    rejects('DUPLICATE_IDENTITY',lambda d:d['entries'][1].update(invariant_id=d['entries'][0]['invariant_id']))
    rejects('TAMPERED_STATEMENT_DIGEST',lambda d:d['entries'][0].update(normative_statement_sha256='0'*64))
    rejects('FALSE_SCOPE_APPROVAL',lambda d:d['entries'][0].update(decision='M0_REQUIRED',first_mandatory_milestone='M0'))
    rejects('FALSE_DEFERRAL',lambda d:d['entries'][0].update(decision='DEFERRED_APPROVED',first_mandatory_milestone='M1'))
    rejects('FORGED_AUTHORITY',lambda d:d.update(authority_status='ESTABLISHED'))
    rejects('FORGED_CLOSURE',lambda d:d.update(review_status='CLOSED'))
    rejects('PROPOSAL_TAMPERING',lambda d:d['entries'][0].update(proposal='DEFER_CANDIDATE'))
    # Exercise the legitimate owner-signed decision path with an ephemeral
    # test key.  No test key or private material enters the real repository.
    with tempfile.TemporaryDirectory(prefix='asmweb-test-authority-') as tmp:
        t=Path(tmp)
        private=t/'owner-private.pem'
        public=t/'owner-public.pem'
        signature=t/'scope.sig'
        message=t/'decision.json'
        def command(*args):
            result=subprocess.run(['openssl',*args],capture_output=True,text=True)
            assert result.returncode==0, result.stderr
        command('genpkey','-algorithm','ED25519','-out',str(private))
        command('pkey','-in',str(private),'-pubout','-out',str(public))
        signed=copy.deepcopy(baseline)
        signed['authority_status']='ESTABLISHED'
        row=signed['entries'][0]
        row['decision']='M0_REQUIRED'
        row['first_mandatory_milestone']='M0'
        row['semantic_rationale']=(
            'Mandatory foundation obligation, subject to independent '
            'semantic evidence review before normative adoption.'
        )
        row['qualified_evidence_refs']=[
            'qualification/invariants/ir-normative-source-v0.3.json'
        ]
        row['authorisation_ref']='qualification/invariants/m0-scope-decisions-v0.1.sig'
        message.write_bytes(scope.canonical(signed))
        command('pkeyutl','-sign','-inkey',str(private),'-rawin',
                '-in',str(message),'-out',str(signature))
        assert scope.verify_owner_signature(signed,public,signature)
        assert scope.verify_document(signed,source,sb,assessment,ab,
                                     signature_verified=True)=={
            'pending':41,'required':1,'deferred':0
        }
        forged=copy.deepcopy(signed)
        forged['entries'][0]['first_mandatory_milestone']='M2'
        try:
            scope.verify_owner_signature(forged,public,signature)
        except ValueError:
            print('SIGNED_DECISION_TAMPERING=REJECTED')
        else:
            raise AssertionError('TAMPERED_SIGNATURE_ACCEPTED')
        try:
            scope.verify_document(signed,source,sb,assessment,ab)
        except ValueError:
            print('UNVERIFIED_SIGNED_APPROVAL=REJECTED')
        else:
            raise AssertionError('UNVERIFIED_AUTHORITY_ACCEPTED')
        # A signature cannot be reused to approve unrelated identities.
        forged=copy.deepcopy(signed)
        forged['entries'][1]['decision']='DEFERRED_APPROVED'
        forged['entries'][1]['first_mandatory_milestone']='M1'
        try: scope.verify_owner_signature(forged,public,signature)
        except ValueError: print('REPLAYED_SIGNATURE=REJECTED')
        else: raise AssertionError('REPLAYED_SIGNATURE_ACCEPTED')
    print('OWNER_SIGNED_SCOPE_DECISION=ACCEPTED')
    print('M0_SCOPE_ADVERSARIAL=PASS')
if __name__=='__main__':
    try: main()
    except (AssertionError,ValueError,KeyError,TypeError,OSError) as exc:
        print('M0_SCOPE_ADVERSARIAL=FAIL:',exc,file=sys.stderr)
        raise SystemExit(1)
