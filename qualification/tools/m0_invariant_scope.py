#!/usr/bin/env python3
"""Source-bound M0 invariant scope review; proposals cannot grant deferral."""
import argparse
import hashlib
import json
import sys
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'qualification/invariants/ir-normative-source-v0.3.json'
ASSESSMENT = ROOT / 'qualification/invariants/m0-applicability-v0.1.json'
LEDGER = ROOT / 'qualification/invariants/m0-scope-decisions-v0.1.json'
SIGNATURE = ROOT / 'qualification/invariants/m0-scope-decisions-v0.1.sig'
TRUSTED_KEY = Path.home() / '.config/asmweb/owner-public.pem'
FUTURE_PROPOSALS = {
    'INV-QUE-OWNER-001', 'INV-BUF-BORROW-001',
    'INV-OBJ-ASYNC-001', 'INV-OBJ-EVENT-001',
    'INV-MEM-SCRATCH-001',
}

def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'),
                       ensure_ascii=False, allow_nan=False) + '\n').encode()

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def load(path):
    def unique(pairs):
        out = {}
        for key, val in pairs:
            if key in out:
                raise ValueError('duplicate JSON key: '+key)
            out[key] = val
        return out
    raw = path.read_bytes()
    return json.loads(raw.decode(), object_pairs_hook=unique), raw

def verify_owner_signature(ledger, public_key=TRUSTED_KEY, signature=SIGNATURE):
    """Verify detached Ed25519 signature; trust anchor is outside repository.

    The signed bytes are the canonical complete decision ledger, including
    its source and assessment digests. This never signs or approves for owner.
    """
    if not public_key.is_file() or not signature.is_file():
        raise ValueError('owner trust anchor or detached signature absent')
    try:
        # Never follow a repository-local signature symlink.
        if signature.is_symlink() or public_key.is_symlink():
            raise ValueError('signature or trust anchor symlink')
        with tempfile.TemporaryDirectory(prefix='asmweb-scope-') as temp:
            msg = Path(temp) / 'decision.json'
            msg.write_bytes(canonical(ledger))
            result = subprocess.run(
                ['openssl', 'pkeyutl', '-verify', '-pubin', '-inkey',
                 str(public_key), '-rawin', '-in', str(msg),
                 '-sigfile', str(signature)],
                capture_output=True, timeout=10, check=False,
            )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ValueError('signature verification unavailable') from exc
    if result.returncode != 0:
        raise ValueError('owner signature invalid')
    return True

def initial():
    source, sb = load(SOURCE)
    assessment, ab = load(ASSESSMENT)
    statements = {e['invariant_id']: e['normative_statement'] for e in source['entries']}
    candidates = [e for e in assessment['entries'] if e['m0_applicability']=='CANDIDATE_APPLICABLE']
    if len(candidates) != 42 or len(statements) != 144:
        raise ValueError('unexpected normative population')
    if not FUTURE_PROPOSALS <= {e['invariant_id'] for e in candidates}:
        raise ValueError('proposal not in candidate population')
    return {
        'schema_version': 1,
        'document_type': 'ASMWEB_M0_INVARIANT_SCOPE_DECISIONS',
        'source_sha256': digest(sb),
        'assessment_sha256': digest(ab),
        'authority_status': 'NOT_ESTABLISHED',
        'review_status': 'OPEN',
        'entries': [{
            'invariant_id': e['invariant_id'],
            'normative_statement_sha256': digest(statements[e['invariant_id']].encode()),
            'decision': 'REVIEW_REQUIRED',
            'proposal': 'DEFER_CANDIDATE' if e['invariant_id'] in FUTURE_PROPOSALS else 'M0_REQUIRED_CANDIDATE',
            'first_mandatory_milestone': None,
            'semantic_rationale': None,
            'qualified_evidence_refs': [],
            'authorisation_ref': None,
        } for e in candidates],
    }

def verify_document(ledger, source, source_raw, assessment, assessment_raw, *, signature_verified=False):
    def check(ok, message):
        if not ok: raise ValueError(message)
    check(set(ledger)=={'schema_version','document_type','source_sha256','assessment_sha256','authority_status','review_status','entries'}, 'ledger schema')
    check(ledger['schema_version']==1 and ledger['document_type']=='ASMWEB_M0_INVARIANT_SCOPE_DECISIONS', 'ledger type')
    check(ledger['source_sha256']==digest(source_raw) and ledger['assessment_sha256']==digest(assessment_raw), 'stale source or assessment')
    statements = {e['invariant_id']:e['normative_statement'] for e in source['entries']}
    check(len(statements)==len(source['entries'])==144, 'source identity population')
    candidates = {e['invariant_id'] for e in assessment['entries'] if e['m0_applicability']=='CANDIDATE_APPLICABLE'}
    check(len(candidates)==assessment['candidate_applicable_count'], 'assessment population')
    rows = ledger['entries']
    check(len(rows)==len(candidates), 'scope population')
    check(len({e['invariant_id'] for e in rows})==len(rows), 'duplicate scope identity')
    check({e['invariant_id'] for e in rows}==candidates, 'missing or extraneous scope identity')
    mandatory = deferred = pending = 0
    rowfields = {'invariant_id','normative_statement_sha256','decision','proposal',
                 'first_mandatory_milestone','semantic_rationale',
                 'qualified_evidence_refs','authorisation_ref'}
    for row in rows:
        check(set(row)==rowfields, 'scope entry schema')
        identity = row['invariant_id']
        check(row['normative_statement_sha256']==digest(statements[identity].encode()), 'statement digest mismatch: '+identity)
        expected = 'DEFER_CANDIDATE' if identity in FUTURE_PROPOSALS else 'M0_REQUIRED_CANDIDATE'
        check(row['proposal']==expected, 'unreviewed proposal change: '+identity)
        check(row['decision'] in ('REVIEW_REQUIRED','M0_REQUIRED','DEFERRED_APPROVED'), 'invalid decision')
        if row['decision']=='REVIEW_REQUIRED':
            pending += 1
            check(row['first_mandatory_milestone'] is None and row['semantic_rationale'] is None
                  and row['qualified_evidence_refs']==[] and row['authorisation_ref'] is None,
                  'unapproved scope row contains adopted decision')
        else:
            # No unverified authority can silently create effective decisions.
            check(ledger['authority_status']=='ESTABLISHED' and signature_verified, 'verified scope authority unavailable')
            check(isinstance(row['semantic_rationale'],str) and len(row['semantic_rationale'].strip())>=40, 'missing semantic rationale')
            check(isinstance(row['qualified_evidence_refs'],list) and row['qualified_evidence_refs'], 'missing qualified evidence')
            check(row['authorisation_ref']=='qualification/invariants/m0-scope-decisions-v0.1.sig', 'incorrect owner-signature reference')
            check(all(isinstance(ref,str) and not Path(ref).is_absolute()
                      and '..' not in Path(ref).parts and (ROOT/ref).is_file()
                      for ref in row['qualified_evidence_refs']), 'invalid qualification evidence')
            if row['decision']=='M0_REQUIRED':
                check(row['first_mandatory_milestone']=='M0', 'incorrect M0 milestone')
                mandatory += 1
            else:
                check(row['first_mandatory_milestone'] in {'M'+str(i) for i in range(1,17)}, 'invalid deferral milestone')
                deferred += 1
    # Establishing authority requires a separate verified identity mechanism;
    # the ledger alone cannot establish it, including a forged flag.
    check(ledger['authority_status'] == ('ESTABLISHED' if signature_verified else 'NOT_ESTABLISHED'), 'unsupported scope authority')
    check(ledger['review_status'] in ('OPEN','CLOSED'), 'invalid review status')
    check(ledger['review_status']!='CLOSED' or (signature_verified and pending==0), 'unsupported scope closure')
    return {'pending':pending,'required':mandatory,'deferred':deferred}

def verified_decisions(*, public_key=TRUSTED_KEY, signature=SIGNATURE):
    """Return reviewed scope decisions only after verifying the actual signer.

    This API is shared by the IR projector and closure gate. Calling
    verify_document(..., signature_verified=True) is not an authority check.
    """
    source, sb = load(SOURCE)
    assessment, ab = load(ASSESSMENT)
    ledger, _ = load(LEDGER)
    signed = ledger.get('authority_status') == 'ESTABLISHED'
    if signed:
        verify_owner_signature(ledger, public_key, signature)
    counts = verify_document(ledger, source, sb, assessment, ab,
                             signature_verified=signed)
    return ledger, counts

def verify():
    ledger, result = verified_decisions()
    print('M0_SCOPE_IDENTITIES='+str(len(ledger['entries'])))
    print('M0_SCOPE_PENDING='+str(result['pending']))
    print('M0_DEFER_PROPOSALS='+str(sum(e['proposal']=='DEFER_CANDIDATE' for e in ledger['entries'])))
    print('M0_EFFECTIVE_DEFERRALS='+str(result['deferred']))
    print('M0_SCOPE_INTEGRITY=PASS')
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['verify','initialise','print-signing-payload'])
    args=parser.parse_args()
    try:
        if args.action=='print-signing-payload':
            # stdout is the exact byte sequence to sign, with no status text.
            ledger, _ = load(LEDGER)
            sys.stdout.buffer.write(canonical(ledger))
            return 0
        if args.action=='initialise':
            if LEDGER.exists(): raise ValueError('ledger already exists')
            LEDGER.write_bytes(canonical(initial()))
        verify()
    except (ValueError,KeyError,TypeError,OSError) as exc:
        print('M0_SCOPE_INTEGRITY=FAIL:',exc,file=sys.stderr)
        return 1
    return 0

if __name__=='__main__':
    raise SystemExit(main())
