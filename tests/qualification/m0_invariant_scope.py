#!/usr/bin/env python3
"""Adversarial acceptance of source-bound scope, without invented approvals."""
import copy
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
    print('M0_SCOPE_ADVERSARIAL=PASS')
if __name__=='__main__':
    try: main()
    except (AssertionError,ValueError,KeyError,TypeError,OSError) as exc:
        print('M0_SCOPE_ADVERSARIAL=FAIL:',exc,file=sys.stderr)
        raise SystemExit(1)
