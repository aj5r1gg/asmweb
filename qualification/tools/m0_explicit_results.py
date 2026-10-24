#!/usr/bin/env python3
"""Evidence-backed engineering results for explicitly scoped M0 requirements.

Not a final M0 qualification manifest. First-mandatory ownership
and normative approval remain subject to the authority contract.
"""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "qualification/requirements"
OUTPUT = BASE / "review/m0-explicit-results-v0.1.json"

TESTS = {
    "REQ-M0-001": (
        "qualify-m0-scope-boundary",
        "REQ_M0_001_ENGINEERING_QUALIFICATION=PASS",
        "tests/qualification/m0_scope_boundary.py",
    ),
    "REQ-M0-004": (
        "qualify-m0-requirement-identity",
        "REQ_M0_004_ENGINEERING_QUALIFICATION=PASS",
        "tests/qualification/m0_requirement_identity.py",
    ),
    "REQ-M0-005": (
        "qualify-m0-binary-identity",
        "REQ_M0_005_ENGINEERING_QUALIFICATION=PASS",
        "tests/qualification/m0_binary_identity.py",
    ),
}

OUTSTANDING = {
    "REQ-M0-002":
        "Architecture-compatibility review has not been accepted",
    "REQ-M0-003":
        "Complete authoritative M0 ownership and result population "
        "does not yet exist",
}


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (
        json.dumps(
            value, sort_keys=True, separators=(",", ":"),
            ensure_ascii=False, allow_nan=False
        ) + "\n"
    ).encode("utf-8")


def read(relative):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def run_test(target, expected):
    result = subprocess.run(
        ["make", "--no-print-directory", target],
        cwd=ROOT, capture_output=True, text=True,
        timeout=120,
    )
    require(
        result.returncode == 0 and expected in result.stdout,
        "qualification failed: " + target + "\n"
        + result.stdout[-2000:] + result.stderr[-2000:],
    )


def build():
    proposal_path = (
        "qualification/requirements/review/"
        "m0-explicit-ownership-proposals-v0.1.json"
    )
    source_path = (
        "qualification/requirements/requirements-source-v0.3.json"
    )
    ownership_path = (
        "qualification/requirements/"
        "requirements-milestone-ownership-v0.3.json"
    )
    config_path = (
        "qualification/limits/m0-effective-configuration-v0.1.json"
    )

    proposals = read(proposal_path)
    source = read(source_path)
    ownership = read(ownership_path)
    configuration = read(config_path)

    require(proposals["authoritative"] is False,
            "unexpected proposal authority")
    require(proposals["proposal_count"] == 5,
            "wrong proposal count")

    statements = {
        e["requirement_id"]: e["normative_statement"]
        for e in source["entries"]
    }
    decisions = {
        e["requirement_id"]: e for e in ownership["entries"]
    }

    require(len(statements) == 1001, "source population")
    require(len(decisions) == 1001, "ownership population")

    require(
        set(TESTS) | set(OUTSTANDING)
        == {e["requirement_id"] for e in proposals["entries"]},
        "unexpected M0 proposal identities",
    )

    require(
        configuration["formal_m0_qualification"] is False,
        "unexpected existing formal qualification",
    )
    require(
        configuration["configuration"]["binary_sha256"]
        == sha((ROOT / "build/asmweb").read_bytes()),
        "build binary identity disagreement",
    )

    entries = []

    for proposal in proposals["entries"]:
        identity = proposal["requirement_id"]
        require(
            proposal["normative_statement"] == statements[identity],
            "source text disagreement: " + identity,
        )
        require(
            proposal["proposed_first_mandatory_milestone"] == "M0",
            "milestone proposal mismatch: " + identity,
        )
        require(
            proposal["review_status"] == "PROPOSED_NOT_APPROVED"
            and proposal["approval_evidence_ref"] is None,
            "unexpected proposal approval: " + identity,
        )
        require(
            decisions[identity]["review_status"] == "UNREVIEWED"
            and decisions[identity][
                "approved_first_mandatory_milestone"
            ] is None,
            "unexpected ownership decision: " + identity,
        )

        if identity in TESTS:
            target, expected, evidence = TESTS[identity]
            require((ROOT / evidence).is_file(),
                    "missing test: " + identity)
            run_test(target, expected)
            status = "ENGINEERING_PASS"
            unresolved = None
            evidence_refs = [evidence]
        else:
            status = "BLOCKED"
            unresolved = OUTSTANDING[identity]
            evidence_refs = []

        entries.append({
            "requirement_id": identity,
            "normative_statement": statements[identity],
            "proposed_first_mandatory_milestone": "M0",
            "ownership_approved": False,
            "engineering_result": status,
            "formal_qualification_status": "NOT_QUALIFIED",
            "evidence_refs": evidence_refs,
            "unresolved_reason": unresolved,
        })

    return {
        "schema_version": 1,
        "document_type": "ASMWEB_M0_EXPLICIT_REQUIREMENT_RESULTS",
        "status": "ENGINEERING_EVIDENCE_NOT_FORMAL_QUALIFICATION",
        "authoritative_m0_population_complete": False,
        "milestone_closed": False,
        "approved_ownership_count": 0,
        "proposal_source_sha256":
            sha((ROOT / proposal_path).read_bytes()),
        "requirements_source_sha256":
            sha((ROOT / source_path).read_bytes()),
        "ownership_source_sha256":
            sha((ROOT / ownership_path).read_bytes()),
        "effective_configuration_sha256":
            configuration["effective_configuration_sha256"],
        "binary_sha256":
            configuration["configuration"]["binary_sha256"],
        "entry_count": len(entries),
        "engineering_pass_count": sum(
            e["engineering_result"] == "ENGINEERING_PASS"
            for e in entries
        ),
        "blocked_count": sum(
            e["engineering_result"] == "BLOCKED"
            for e in entries
        ),
        "entries": entries,
    }


def verify():
    expected = build()
    require(OUTPUT.read_bytes() == canonical(expected),
            "controlled results differ from current qualification")
    require(expected["entry_count"] == 5, "entry population")
    require(expected["engineering_pass_count"] == 3,
            "engineering pass count")
    require(expected["blocked_count"] == 2,
            "blocked count")
    require(expected["approved_ownership_count"] == 0,
            "false authority")
    require(
        all(
            e["formal_qualification_status"] == "NOT_QUALIFIED"
            and e["ownership_approved"] is False
            for e in expected["entries"]
        ),
        "false formal qualification",
    )
    print("EXPLICIT_M0_REQUIREMENTS=5")
    print("ENGINEERING_PASS=3")
    print("BLOCKED=2")
    print("OWNERSHIP_APPROVED=0")
    print("FORMAL_M0_QUALIFICATION=NOT_ESTABLISHED")
    print("M0_EXPLICIT_RESULT_QUALIFICATION=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("build", "verify"))
    action = parser.parse_args().action
    if action == "build":
        require(not OUTPUT.exists(), "output already exists")
        OUTPUT.write_bytes(canonical(build()))
    verify()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError,
            subprocess.TimeoutExpired) as exc:
        print("M0_EXPLICIT_RESULT_QUALIFICATION=FAIL:", exc,
              file=sys.stderr)
        raise SystemExit(1)
