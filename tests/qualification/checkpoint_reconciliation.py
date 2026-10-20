#!/usr/bin/env python3
"""Adversarial mutation tests for the draft checkpoint validator."""

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT / "qualification/checkpoints/"
    "CP-LEGACY-M1-5-reconciliation-v0.2.json"
)
VALIDATOR = (
    ROOT / "qualification/tools/checkpoint_reconciliation.py"
)


def run(path):
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def main():
    original = json.loads(SOURCE.read_text(encoding="utf-8"))

    baseline = run(SOURCE)
    if baseline.returncode:
        print(baseline.stdout)
        print(baseline.stderr)
        sys.exit("UNMODIFIED_RECONCILIATION=FAIL")

    print("UNMODIFIED_RECONCILIATION=PASS")

    cases = {
        "FABRICATED_CLOSURE":
            lambda r: r.update(formal_milestone_closure=True),
        "FABRICATED_COMMERCIAL_APPROVAL":
            lambda r: r.update(commercial_distribution_approval=True),
        "FABRICATED_CHECKPOINT_ACCEPTANCE":
            lambda r: r.update(checkpoint_acceptance="ACCEPTED"),
        "FABRICATED_QUALIFICATION":
            lambda r: r.update(formal_qualification="PASS"),
        "SUBSTITUTED_COMMIT":
            lambda r: r["contributions"][0].update(
                commit=r["source_revision"]
            ),
        "SUBSTITUTED_HISTORICAL_BLOB":
            lambda r: r["contributions"][0]["artifact_evidence"][0].update(
                historical_git_blob="0" * 40
            ),
        "SUBSTITUTED_BASELINE_BLOB":
            lambda r: r["contributions"][0]["artifact_evidence"][0].update(
                baseline_git_blob="0" * 40
            ),
        "SUBSTITUTED_SHA256":
            lambda r: r["contributions"][0]["artifact_evidence"][0].update(
                baseline_sha256="0" * 64
            ),
        "FABRICATED_ALLOCATION_APPROVAL":
            lambda r: r["contributions"][0].update(
                allocation_authority="APPROVED"
            ),
        "EXCESSIVE_HTTP_CAPABILITY":
            lambda r: r["observed_capability"].update(
                general_http11_conformance=True
            ),
        "EXTRA_ACCEPTED_REQUEST":
            lambda r: r["observed_capability"][
                "accepted_request_representations"
            ].append({
                "request_line": "GET /anything HTTP/1.1",
                "host_header": "Host: localhost",
            }),
        "UNSUPPORTED_TLS":
            lambda r: r["observed_capability"].update(tls=True),
        "FALSE_ELM_AUTHORITY":
            lambda r: r["engineering_evidence"].update(
                authoritative_effective_limit_manifest=True
            ),
        "FALSE_MEMORY_MEASUREMENT":
            lambda r: r["engineering_evidence"].update(
                memory_measurement_kind="MEASURED_RSS"
            ),
        "MISSING_CONTRIBUTION":
            lambda r: r["contributions"].pop(),
        "DUPLICATE_CONTRIBUTION":
            lambda r: r["contributions"].append(
                copy.deepcopy(r["contributions"][0])
            ),
        "MISSING_ACCEPT_DEADLINE_LIMITATION":
            lambda r: r["limitations"].remove(
                "No accept deadline."
            ),
        "ALTERED_PREDECESSOR":
            lambda r: r.update(
                superseded_draft_sha256="0" * 64
            ),
    }

    failures = []

    with tempfile.TemporaryDirectory(prefix="asmweb-cp-audit-") as tmp:
        for name, mutate in cases.items():
            candidate = copy.deepcopy(original)
            mutate(candidate)
            target = Path(tmp) / f"{name}.json"
            target.write_text(
                json.dumps(candidate, indent=2) + "\n",
                encoding="utf-8",
            )

            outcome = run(target)
            rejected = outcome.returncode != 0 and (
                "CP_LEGACY_M1_5_VALIDATION=FAIL"
                in outcome.stdout
            )

            print(
                f"{name}="
                + ("REJECTED" if rejected else "NOT_REJECTED")
            )

            if not rejected:
                failures.append(name)

    print(f"MUTATIONS_TESTED={len(cases)}")
    print(f"MUTATIONS_REJECTED={len(cases) - len(failures)}")
    print(
        "CP_LEGACY_M1_5_ADVERSARIAL="
        + ("PASS" if not failures else "FAIL")
    )

    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
