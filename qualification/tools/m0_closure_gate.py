#!/usr/bin/env python3
"""M0 acceptance preflight.

An audit PASS means the audit executed; it does not mean M0 passed.
This gate is necessary but not sufficient for authoritative closure.
Final acceptance additionally requires independently verified normative
authority, evidence provenance and prescribed milestone qualification.
"""

import argparse
import json
import subprocess
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


def diagnostics_qualified():
    # Reuse the existing M0 diagnostic qualification procedures.
    # Exit status, rather than a declared PASS flag, is authoritative
    # for this engineering portion of the milestone evaluation.
    targets = (
        "qualify-diagnostic-adversarial",
        "qualify-ready-diagnostic",
        "qualify-ready-bootstrap-injection",
    )
    try:
        process = subprocess.run(
            ["make", "--no-print-directory", *targets],
            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=180, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return process.returncode == 0


def documents():
    return {
        "diagnostics_qualified": diagnostics_qualified(),
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

    # Verify the candidate population against the governing statement
    # digests. Pending decisions remain real M0 closure blockers.
    from m0_invariant_scope import verified_decisions
    try:
        scope_doc, scope_counts = verified_decisions()
        if scope_counts["pending"]:
            fail("M0-IR-SCOPE", str(scope_counts["pending"]) +
                 " invariant scope decisions pending")
    except (OSError, ValueError, KeyError, TypeError) as exc:
        fail("M0-IR-SCOPE", "Invalid or unauthorised invariant scope: " + str(exc))
        scope_doc = {"entries": []}

    # Deferral never counts as qualified M0 behaviour, but a verified
    # deferral is not a missing M0 obligation either. Eligibility still
    # requires every M0_REQUIRED record to independently qualify.
    required_ids = {
        row["invariant_id"] for row in scope_doc["entries"]
        if row["decision"] == "M0_REQUIRED"
    }
    deferred_ids = {
        row["invariant_id"] for row in scope_doc["entries"]
        if row["decision"] == "DEFERRED_APPROVED"
    }

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

    # Only a cryptographically verified deferral removes an invariant
    # from the M0 qualification obligation. Pending decisions remain
    # mandatory for gate purposes, never implicit deferrals.
    candidate_ids = {
        e.get("invariant_id") for e in m0_candidates
    }
    effective_m0_ids = candidate_ids - deferred_ids
    unapproved = sum(
        e.get("invariant_id") in effective_m0_ids
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
        m0_ids = effective_m0_ids
        # A legitimate deferral must be projected in the IR and must
        # preserve the signed destination milestone; an inactive M0
        # record alone cannot satisfy this obligation.
        scope_rows = {
            row["invariant_id"]: row for row in scope_doc["entries"]
        }
        bad_deferrals = [
            identity for identity in deferred_ids
            if (
                identity not in ir_by_id
                or ir_by_id[identity].get("scope") != "DEFERRED_FROM_M0"
                or ir_by_id[identity].get("first_required_milestone")
                   != scope_rows[identity]["first_mandatory_milestone"]
            )
        ]
        if bad_deferrals:
            fail("M0-IR-DEFERRAL-PROJECTION", ",".join(sorted(bad_deferrals)))
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
        assessed_by_id.get(identity, {}).get("normative_approval") is not True
        or ir_by_id.get(identity, {}).get("status") != "ACTIVE"
        for identity in effective_m0_ids
    ):
        fail("M0-IR-AUTHORITY", "M0 foundation IR is not qualified")

    if not lr_entries:
        fail("M0-LR-POPULATION", "No limit entries")

    # The M0 limit acceptance path must enforce the same dimensional
    # contract as the normative LR validator, not just ACTIVE flags.
    from m0_normative_lr import validate_m0_dimensions
    for entry in lr_entries:
        try:
            validate_m0_dimensions(entry)
        except (ValueError, AttributeError, TypeError) as exc:
            fail("M0-LR-DIMENSION", str(exc))

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

    # ELM is derived from adopted LR; never treat the projection as an
    # independent numerical authority. Verify the actual reconciliation.
    import hashlib
    projection = cfg.get("configuration")
    reconciled_elm = False
    if isinstance(projection, dict):
        limits = projection.get("limits")
        lr_by_id = {
            e.get("limit_id"): e for e in lr_entries if isinstance(e, dict)
        }
        if (
            isinstance(limits, list) and bool(limits)
            and len(limits) == len(lr_entries) == len(lr_by_id)
            and all(isinstance(item, dict) for item in limits)
        ):
            ids = [item.get("normative_lim_id") for item in limits]
            canonical = (json.dumps(
                projection, sort_keys=True, separators=(",", ":"),
                ensure_ascii=False, allow_nan=False,
            ) + "\n").encode("utf-8")
            reconciled_elm = (
                len(set(ids)) == len(ids)
                and set(ids) == set(lr_by_id)
                and all(
                    lr_by_id[item["normative_lim_id"]].get("status") == "ACTIVE"
                    and lr_by_id[item["normative_lim_id"]].get("configured_value")
                        == item.get("configured_capacity")
                    and lr_by_id[item["normative_lim_id"]].get("effective_value")
                        == item.get("effective_count")
                    and lr_by_id[item["normative_lim_id"]].get("provenance", {}).get("runtime_limit_id")
                        == item.get("runtime_limit_id")
                    for item in limits
                )
                and cfg.get("effective_configuration_sha256")
                    == hashlib.sha256(canonical).hexdigest()
                 and projection.get("normative_limit_register_sha256")
                     == hashlib.sha256((json.dumps(
                         lr, sort_keys=True, separators=(",", ":"),
                         ensure_ascii=False, allow_nan=False,
                     ) + "\n").encode("utf-8")).hexdigest()
                and projection.get("total_projected_bytes")
                    == projection.get("total_direct_capacity_bytes", -1)
                    + projection.get("total_overhead_bytes", -1)
            )

    if not (
        cfg.get("authoritative_elm_adopted") is True
        and cfg.get("normative_lr_complete") is True
        and lr.get("authoritative_lr_complete") is True
        and reconciled_elm
    ):
        fail(
            "M0-ELM-ACCEPTANCE",
            "ELM adoption or production LR/ELM reconciliation incomplete",
        )

    if len(owned) != 1001:
        fail("M0-OWNERSHIP-POPULATION", "Expected 1001 requirements")

    # Milestone Specification v0.3 MIL-OWN-001..003:
    # M0 local closure does not depend on M1-M16 allocation completion.
    # All explicitly M0-owned requirements must be verified locally.
    m0_refs = m.get("first_mandatory_requirement_refs", [])
    # All explicitly M0-named normative requirements are mandatory M0
    # members; selecting a convenient subset must never allow closure.
    mandatory_m0 = {
        "REQ-M0-001", "REQ-M0-002", "REQ-M0-003",
        "REQ-M0-004", "REQ-M0-005",
    }
    if not m0_refs:
        fail("M0-OWNERSHIP", "M0 local ownership population not established")
    elif not mandatory_m0.issubset(set(m0_refs)):
        fail(
            "M0-OWNERSHIP",
            "Explicit M0 requirements missing from closure population: "
            + ",".join(sorted(mandatory_m0 - set(m0_refs))),
        )
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

    # M0_OWNER_SIGNED_ADOPTION_V1
    # Verify owner authority and publication against an independently trusted key.
    try:
        import hashlib as _m0hash
        import tempfile as _m0temp
        from m0_invariant_scope import TRUSTED_KEY as _owner_key
        _adoption_path = ROOT / "qualification/requirements/m0-ownership-adoption-v0.1.json"
        _sig_path = ROOT / "qualification/requirements/m0-ownership-adoption-v0.1.sig"
        if _adoption_path.is_symlink() or _sig_path.is_symlink() or _owner_key.is_symlink():
            raise ValueError("unsafe ownership attestation path")
        _payload = _adoption_path.read_bytes()
        _adoption = json.loads(_payload)
        _canonical = (json.dumps(_adoption, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False) + "\n").encode()
        if _payload != _canonical or _adoption.get("schema_version") != 1:
            raise ValueError("noncanonical ownership attestation")
        for _name, _data in (("ownership", own), ("contract", auth), ("milestone", m)):
            _raw = (json.dumps(_data, ensure_ascii=False, indent=2) + "\n").encode()
            if _adoption["document_sha256"][_name] != _m0hash.sha256(_raw).hexdigest():
                raise ValueError("changed M0 ownership authority or milestone")
        with _m0temp.TemporaryDirectory() as _dir:
            _message = Path(_dir) / "ownership.json"
            _message.write_bytes(_canonical)
            _verified = subprocess.run(
                ["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(_owner_key),
                 "-rawin", "-in", str(_message), "-sigfile", str(_sig_path)],
                capture_output=True, timeout=10, check=False,
            ).returncode == 0
        if not _verified or set(_adoption["approved_requirement_ids"]) != {
            "REQ-M0-001", "REQ-M0-002", "REQ-M0-003", "REQ-M0-004", "REQ-M0-005"
        }:
            raise ValueError("invalid owner signature or M0 membership")
        if any(ownrow.get("review_status") != "APPROVED"
               or ownrow.get("approved_first_mandatory_milestone") != "M0"
               for ownrow in own.get("entries", [])
               if ownrow.get("requirement_id") in _adoption["approved_requirement_ids"]):
            raise ValueError("ownership register differs from signed decision")
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as _error:
        fail("M0-AUTHORITY", "Owner-signed ownership evidence invalid: " + str(_error))
        fail("M0-APPROVAL", "Owner-signed publication not verified")

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
            allowed = (ROOT / "qualification", ROOT / "tests/qualification")
            if not candidate.parts or (
                candidate.parts[0] != "qualification"
                and candidate.parts[:2] != ("tests", "qualification")
            ):
                return False
            absolute = (ROOT / candidate).resolve()
            if not any(absolute.is_relative_to(base) for base in allowed):
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

    if docs.get("diagnostics_qualified") is not True:
        fail(
            "M0-DIAGNOSTICS-ACCEPTANCE",
            "M0 diagnostic qualification targets did not pass",
        )

    # Final approval follows a successful eligibility evaluation.
    # MIL closure sequencing forbids the approval itself as a
    # prerequisite of that evaluation. Publication remains separate.

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

    print("M0_CLOSURE_GATE=ELIGIBLE_PENDING_OWNER_APPROVAL")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
