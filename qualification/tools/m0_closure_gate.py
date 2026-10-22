#!/usr/bin/env python3
"""M0 acceptance preflight.

An audit PASS means the audit executed; it does not mean M0 passed.
This gate is necessary but not sufficient for authoritative closure.
Final acceptance additionally requires independently verified normative
authority, evidence provenance and prescribed milestone qualification.
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(relative_path):
    path = ROOT / relative_path

    def no_duplicates(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key: " + key)
            result[key] = value
        return result

    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=no_duplicates,
        parse_constant=lambda value: (_ for _ in ()).throw(
            ValueError("nonfinite JSON value: " + value)
        ),
    )


def documents():
    return {
        "milestone": load("qualification/milestones/M0.json"),
        "assessment": load(
            "qualification/invariants/m0-applicability-v0.1.json"
        ),
        "ir": load(
            "qualification/invariants/m0-normative-ir-v0.1.json"
        ),
        "lr": load(
            "qualification/limits/m0-normative-lr-v0.1.json"
        ),
        "configuration": load(
            "qualification/limits/m0-effective-configuration-v0.1.json"
        ),
        "ownership": load(
            "qualification/requirements/"
            "requirements-milestone-ownership-v0.3.json"
        ),
        "authority": load(
            "qualification/requirements/"
            "ownership-decision-contract-v0.2.json"
        ),
    }


def evaluate(docs):
    m = docs["milestone"]
    a = docs["assessment"]
    ir = docs["ir"]
    lr = docs["lr"]
    cfg = docs["configuration"]
    own = docs["ownership"]
    auth = docs["authority"]

    blockers = []

    def fail(identity, detail):
        blockers.append((identity, detail))

    if m.get("milestone_id") != "M0":
        fail("M0-IDENTITY", "Incorrect milestone identity")

    active = [
        x.get("blocker_id", "<missing>")
        for x in m.get("blocked_items", [])
    ]

    if active:
        fail("M0-BLOCKERS", ",".join(active))

    if m.get("known_failures"):
        fail("M0-KNOWN-FAILURES", "Unresolved known failures")

    if m.get("waivers"):
        fail(
            "M0-WAIVER-REVIEW",
            "Waivers require independent validity verification"
        )

    assessment = a.get("entries", [])
    ir_entries = ir.get("entries", [])
    lr_entries = lr.get("entries", [])
    owned = own.get("entries", [])

    if len(assessment) != 144 or len(ir_entries) != 144:
        fail("M0-IR-POPULATION", "Expected 144 controlled identities")

    # §34 permits later-milestone invariants to remain unresolved.
    # Check local candidate consistency without requiring all 144
    # future identities to have an M0 disposition.
    m0_candidates = [
        e for e in assessment
        if e.get("m0_applicability") == "CANDIDATE_APPLICABLE"
    ]
    if not m0_candidates or len(m0_candidates) != a.get(
        "candidate_applicable_count"
    ):
        fail("M0-IR-APPLICABILITY", "M0 candidate population inconsistent")

    unapproved = sum(
        e.get("m0_applicability") == "CANDIDATE_APPLICABLE"
        and e.get("normative_approval") is not True
        for e in assessment
    )

    if unapproved:
        fail("M0-IR-APPROVAL", str(unapproved) + " M0 candidates not approved")

    # Validate M0-applicable invariants locally. Later milestone
    # protocol semantics must not be forced into the M0 exit predicate.
    assessed_by_id = {e.get("invariant_id"): e for e in assessment}
    ir_by_id = {e.get("invariant_id"): e for e in ir_entries}
    if len(assessed_by_id) != len(assessment) or len(ir_by_id) != len(ir_entries):
        fail("M0-IR-IDENTITY", "Duplicate invariant identity")
    elif set(assessed_by_id) != set(ir_by_id):
        fail("M0-IR-IDENTITY", "Assessment/IR identity mismatch")
    else:
        m0_ids = {
            identity for identity, entry in assessed_by_id.items()
            if entry.get("m0_applicability") == "CANDIDATE_APPLICABLE"
        }
        incomplete = sum(
            not (
                ir_by_id[identity].get("status") == "ACTIVE"
                and ir_by_id[identity].get("first_required_milestone") == "M0"
                and ir_by_id[identity].get("evidence_refs")
                and ir_by_id[identity].get("qualification_refs")
                and (
                    ir_by_id[identity].get("machine_expression")
                    or ir_by_id[identity].get("detection_method")
                )
            )
            for identity in m0_ids
        )
        if incomplete:
            fail("M0-IR-CONTENT", str(incomplete) + " M0 candidates incomplete")

    # The global IR authority flag includes future milestone population.
    # Local M0 authority instead requires each M0 candidate to have
    # an approved, qualified ACTIVE invariant record.
    if any(
        e.get("normative_approval") is not True
        or ir_by_id.get(e.get("invariant_id"), {}).get("status") != "ACTIVE"
        for e in m0_candidates
    ):
        fail("M0-IR-AUTHORITY", "M0 foundation IR is not qualified")

    if not lr_entries:
        fail("M0-LR-POPULATION", "No limit entries")

    provisional = sum(
        e.get("status") != "ACTIVE"
        for e in lr_entries
    )

    if provisional:
        fail("M0-LR-STATUS", str(provisional) + " not ACTIVE")

    if lr.get("authoritative_lr_complete") is not True:
        fail("M0-LR-AUTHORITY", "LR is not authoritative")

    if not all(
        e.get("evidence_refs") and
        e.get("implementation_refs") and
        e.get("qualification_refs")
        for e in lr_entries
    ):
        fail("M0-LR-EVIDENCE", "Missing limit evidence")

    if cfg.get("normative_lr_complete") is not True:
        fail(
            "M0-CONFIG-NORMATIVE-LR",
            "Configuration lacks adopted normative LR"
        )

    if not cfg.get("effective_configuration_sha256"):
        fail("M0-CONFIG-IDENTITY", "Configuration identity absent")

    # A published engineering configuration is NOT, by itself,
    # evidence that an authoritative ELM exists.
    fail(
        "M0-ELM-ACCEPTANCE",
        "No independently verified authoritative ELM "
        "acceptance record supplied to this gate"
    )

    if len(owned) != 1001:
        fail("M0-OWNERSHIP-POPULATION", "Expected 1001 requirements")

    # Milestone Specification v0.3 MIL-OWN-001..003:
    # M0 local closure does not depend on M1-M16 allocation completion.
    # All explicitly M0-owned requirements must be verified locally.
    m0_refs = m.get("first_mandatory_requirement_refs", [])
    if not m0_refs:
        fail("M0-OWNERSHIP", "M0 local ownership population not established")
    elif len(m0_refs) != len(set(m0_refs)):
        fail("M0-OWNERSHIP", "Duplicate M0 requirement references")
    else:
        by_id = {e.get("requirement_id"): e for e in owned}
        if len(by_id) != len(owned):
            fail("M0-OWNERSHIP", "Duplicate requirement ownership identities")
        else:
            missing = [key for key in m0_refs if key not in by_id]
            pending = [
                key for key in m0_refs if key in by_id and (
                    by_id[key].get("review_status") != "APPROVED"
                    or by_id[key].get(
                        "approved_first_mandatory_milestone"
                    ) != "M0"
                )
            ]
            if missing or pending:
                fail(
                    "M0-OWNERSHIP",
                    "M0 local missing="
                    + str(len(missing))
                    + " unapproved="
                    + str(len(pending)),
                )

    if auth.get("authority_status") != "ESTABLISHED":
        fail("M0-AUTHORITY", "Approval authority not established")

    if auth.get("approval_enabled") is not True:
        fail("M0-APPROVAL", "Approval publication disabled")

    def valid_evidence_refs(refs):
        """Reject placeholders, traversal, missing and duplicate artifacts."""
        if not isinstance(refs, list) or not refs:
            return False
        if any(not isinstance(ref, str) or not ref for ref in refs):
            return False
        if len(refs) != len(set(refs)):
            return False
        for ref in refs:
            candidate = Path(ref)
            if candidate.is_absolute() or ".." in candidate.parts:
                return False
            if not candidate.parts or candidate.parts[0] != "qualification":
                return False
            absolute = (ROOT / candidate).resolve()
            if not absolute.is_relative_to(ROOT / "qualification"):
                return False
            if not absolute.is_file() or (ROOT / candidate).is_symlink():
                return False
        return True

    if not valid_evidence_refs(m.get("required_verification_refs")):
        fail(
            "M0-VERIFICATION-RECORD",
            "Verification artifacts absent or invalid",
        )

    if not valid_evidence_refs(m.get("result_refs")):
        fail("M0-RESULTS", "Result artifacts absent or invalid")

    # Diagnostic-domain acceptance cannot be inferred from
    # incidental passing tests; no such signed result is supplied.
    fail(
        "M0-DIAGNOSTICS-ACCEPTANCE",
        "Normative diagnostic-domain acceptance unverified"
    )

    # Provisional guard: full independent authority verification
    # has not yet been integrated into this gate.
    fail(
        "M0-FINAL-ATTESTATION",
        "Independent signed closure attestation unverified"
    )

    return blockers


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("audit", "close"))
    args = parser.parse_args()

    try:
        blockers = evaluate(documents())
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print("M0_CLOSURE_GATE=ERROR:", exc, file=sys.stderr)
        return 2

    for identity, detail in blockers:
        print(identity + ": " + detail)

    print("M0_BLOCKING_CATEGORIES=" + str(len(blockers)))

    if args.action == "audit":
        print("M0_CLOSURE_AUDIT=PASS")
        print("M0_CLOSURE_ELIGIBLE=" + str(not blockers))
        return 0

    if blockers:
        print("M0_CLOSURE=REJECTED")
        return 1

    print("M0_CLOSURE_GATE=ELIGIBLE_PENDING_ATTESTATION")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
