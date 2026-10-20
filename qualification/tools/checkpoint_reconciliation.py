#!/usr/bin/env python3
"""Verify CP-LEGACY-M1-5 v0.2 engineering reconciliation.

This validates a historical engineering draft only.
It does not determine checkpoint acceptance, formal qualification,
milestone closure, or commercial release eligibility.
"""

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = (
    ROOT / "qualification/checkpoints/"
    "CP-LEGACY-M1-5-reconciliation-v0.2.json"
)

BASELINE = "173db3f12e77977116ae5b914ae450f2186b9bd6"

COMMITS = {
    "CP-M15-CONTRIB-001": "f691f662277527de75045b5d4955b93221697836",
    "CP-M15-CONTRIB-002": "f691f662277527de75045b5d4955b93221697836",
    "CP-M15-CONTRIB-003": "9a0c875476b298df7dd71007a92a3da7afe5efcb",
    "CP-M15-CONTRIB-004": "497a73b91e8ea6bcb1fb8ce4e28fe6245477878d",
    "CP-M15-CONTRIB-005": BASELINE,
}

ADDITIONAL = {
    "CP-M15-CONTRIB-002":
        "375f4d82fcfbf64190508bab94faef6547f2b286"
}

ALLOCATIONS = {
    "CP-M15-CONTRIB-001": ["M1"],
    "CP-M15-CONTRIB-002": ["M4"],
    "CP-M15-CONTRIB-003": ["M0", "M1"],
    "CP-M15-CONTRIB-004": ["M1"],
    "CP-M15-CONTRIB-005": ["M1", "M2"],
}

ARTIFACTS = {
    "CP-M15-CONTRIB-001": [
        "src/linux/network.asm", "include/linux/network.inc"
    ],
    "CP-M15-CONTRIB-002": [
        "src/http/first_response.asm",
        "tests/integration/first_http.py",
    ],
    "CP-M15-CONTRIB-003": [
        "include/asmweb/production_registry.inc",
        "src/runtime/production_registry.asm",
    ],
    "CP-M15-CONTRIB-004": [
        "tests/integration/socket_failures.py"
    ],
    "CP-M15-CONTRIB-005": [
        "tests/qualification/http_descriptor_lifecycle.asm",
        "tests/qualification/http_descriptor_mutations.py",
    ],
}

EXPECTED_REQUESTS = [
    {
        "request_line": "GET / HTTP/1.1",
        "host_header": host,
        "line_ending": "CRLF",
        "termination": "CRLF CRLF",
        "additional_headers": False,
        "request_body": False,
        "trailing_bytes": False,
    }
    for host in ("Host: localhost", "Host: 127.0.0.1")
]


class ReconciliationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReconciliationError(message)


def git(*args):
    p = subprocess.run(
        ["git", "-C", str(ROOT), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    require(p.returncode == 0, "Git reference failure")
    return p.stdout.strip()


def digest(content):
    return hashlib.sha256(content).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ReconciliationError("Duplicate JSON property")
        result[key] = value
    return result


def valid_hex(value, length):
    return (
        isinstance(value, str)
        and re.fullmatch(r"[0-9a-f]+", value) is not None
        and len(value) == length
    )


def validate(path):
    require(path.is_file(), "Missing reconciliation report")
    record = json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=unique_object,
    )

    require(type(record) is dict, "Invalid record root")
    require(
        record.get("record_type")
        == "LEGACY_CHECKPOINT_RECONCILIATION_DRAFT",
        "Invalid record type",
    )
    require(record.get("report_version") == "0.2", "Wrong version")
    require(
        record.get("checkpoint_id") == "CP-LEGACY-M1-5",
        "Wrong checkpoint identity",
    )
    require(record.get("source_revision") == BASELINE, "Wrong baseline")
    require(
        git("cat-file", "-t", BASELINE) == "commit",
        "Historical baseline commit unavailable",
    )
    require(
        git("merge-base", "--is-ancestor", BASELINE, "HEAD") == "",
        "Current revision does not descend from historical baseline",
    )
    require(
        record.get("reconciliation_state") == "IN_PROGRESS",
        "Incorrect reconciliation state",
    )

    predecessor = (
        ROOT / "qualification/checkpoints/"
        "CP-LEGACY-M1-5-reconciliation-v0.1.json"
    )
    require(
        record.get("supersedes_draft") == predecessor.name,
        "Wrong predecessor",
    )
    require(
        predecessor.is_file()
        and record.get("superseded_draft_sha256")
        == digest(predecessor.read_bytes()),
        "Predecessor integrity failure",
    )

    governing = record.get("governing_specification")
    require(
        type(governing) is dict
        and governing.get("document_id") == "ASM-MIL-001"
        and governing.get("version") == "0.3"
        and governing.get("section") == "17",
        "Incorrect milestone authority",
    )

    commercial = record.get("commercial_boundary")
    require(
        type(commercial) is dict
        and commercial.get("document_id") == "ASM-COM-001"
        and commercial.get("version") == "0.3"
        and commercial.get("release_claim") == "NONE",
        "Incorrect commercial boundary",
    )

    historical = record.get("historical_definition")
    require(
        type(historical) is dict
        and historical.get("status") == "NOT_RECOVERED"
        and historical.get("definition_source_ref") is None,
        "Fabricated historical definition",
    )

    require(
        record.get("checkpoint_acceptance") == "NOT_ESTABLISHED",
        "Unsupported checkpoint acceptance",
    )
    require(
        record.get("formal_qualification") == "NOT_ESTABLISHED",
        "Unsupported formal qualification",
    )
    require(
        record.get("formal_milestone_closure") is False,
        "Unsupported milestone closure",
    )
    require(
        record.get("commercial_distribution_approval") is False,
        "Unsupported commercial approval",
    )

    authority = record.get("reconciliation_authority")
    require(
        type(authority) is dict
        and authority.get("checkpoint_allocation") == "PROPOSED"
        and authority.get("checkpoint_acceptance") == "NOT_ESTABLISHED"
        and authority.get("authoritative_qualification") == "NOT_ESTABLISHED"
        and authority.get("milestone_closure") == "NOT_ESTABLISHED"
        and authority.get("commercial_release") == "NOT_APPROVED",
        "Reconciliation authority escalation",
    )

    statuses = record.get("formal_baseline_status")
    require(
        type(statuses) is dict
        and statuses == {
            "M0": "BLOCKED",
            "M1": "NOT_FORMALLY_CLOSED",
            "M2": "NOT_FORMALLY_CLOSED",
            "M4": "NOT_FORMALLY_CLOSED",
        },
        "Incorrect milestone states",
    )

    m0 = json.loads(
        (ROOT / "qualification/milestones/M0.json").read_text()
    )
    require(
        m0.get("closure_status") == "BLOCKED",
        "M0 authority no longer matches",
    )

    contributions = record.get("contributions")
    require(
        type(contributions) is list
        and len(contributions) == len(COMMITS),
        "Incorrect contribution population",
    )

    seen = set()

    for contribution in contributions:
        require(type(contribution) is dict, "Invalid contribution")
        cid = contribution.get("id")
        require(
            cid in COMMITS and cid not in seen,
            "Unknown or duplicate contribution",
        )
        seen.add(cid)
        commit = contribution.get("commit")

        require(commit == COMMITS[cid], "Commit identity substitution")
        require(valid_hex(commit, 40), "Malformed commit identity")
        require(
            git("cat-file", "-t", commit) == "commit",
            "Invalid commit object",
        )
        require(
            git("merge-base", commit, BASELINE) == commit,
            "Commit not in baseline ancestry",
        )

        additional = contribution.get("additional_commit")
        if cid in ADDITIONAL:
            require(
                additional == ADDITIONAL[cid],
                "Additional commit substitution",
            )
        else:
            require(
                additional is None,
                "Unexpected additional commit",
            )

        require(
            contribution.get("baseline_milestones")
            == ALLOCATIONS[cid],
            "Milestone allocation changed",
        )
        require(
            contribution.get("allocation_authority")
            == "PROPOSED_NOT_APPROVED",
            "Unapproved allocation escalated",
        )
        require(
            contribution.get("formal_milestone_credit")
            == "NOT_ESTABLISHED",
            "Unqualified milestone credit",
        )
        require(
            contribution.get("qualification_state")
            in ("NOT_FORMALLY_DETERMINED", "ENGINEERING_TESTS_ONLY"),
            "Invalid qualification classification",
        )

        paths = contribution.get("artifact_paths")
        require(
            paths == ARTIFACTS[cid],
            "Artifact membership changed",
        )

        evidence = contribution.get("artifact_evidence")
        require(
            type(evidence) is list and len(evidence) == len(paths),
            "Artifact evidence population mismatch",
        )

        for path_string, item in zip(paths, evidence):
            require(
                type(item) is dict
                and item.get("path") == path_string,
                "Artifact path mismatch",
            )
            require(
                item.get("historical_git_blob")
                == git("rev-parse", f"{commit}:{path_string}"),
                "Historical blob identity mismatch",
            )
            require(
                item.get("baseline_git_blob")
                == git("rev-parse", f"{BASELINE}:{path_string}"),
                "Baseline blob identity mismatch",
            )

            historical_content = subprocess.check_output(
                [
                    "git", "-C", str(ROOT), "show",
                    f"{BASELINE}:{path_string}",
                ]
            )
            require(
                item.get("baseline_sha256")
                == digest(historical_content),
                "Historical artifact SHA-256 mismatch",
            )

    require(seen == set(COMMITS), "Missing contribution")

    capability = record.get("observed_capability")
    require(type(capability) is dict, "Missing capability record")
    require(
        capability.get("request_acceptance_model")
        == "EXACT_BYTE_SEQUENCE",
        "Overbroad request model",
    )
    require(
        capability.get("accepted_request_representations")
        == EXPECTED_REQUESTS,
        "Unsupported request representation",
    )
    require(
        capability.get("listen_address") == "127.0.0.1"
        and capability.get("port") == 18080
        and capability.get("request_buffer_bytes") == 1024
        and capability.get("accepted_connections_per_process") == 1,
        "Unsupported resource or listener claim",
    )
    require(
        capability.get("responses") == [200, 400, 431],
        "Unsupported response claim",
    )

    for key in (
        "general_http_parser",
        "general_get_request_support",
        "general_http11_conformance",
        "public_network_listener",
        "connection_persistence",
        "tls",
        "http2",
        "http3",
        "total_processing_deadline_established",
    ):
        require(
            capability.get(key) is False,
            "Unsupported capability: " + key,
        )

    engineering = record.get("engineering_evidence")
    require(type(engineering) is dict, "Missing engineering evidence")
    require(
        (
            engineering.get("http_integration_scenarios"),
            engineering.get("socket_failure_scenarios"),
            engineering.get("controlled_lifecycle_scenarios"),
            engineering.get("adversarial_mutations_rejected"),
        ) == (12, 2, 14, 4),
        "Incorrect test population",
    )
    require(
        engineering.get("production_direct_capacity_bytes") == 3488,
        "Incorrect direct memory capacity",
    )
    require(
        engineering.get("authoritative_effective_limit_manifest") is False,
        "False ELM authority",
    )
    require(
        engineering.get("formal_qualification_result")
        == "NOT_ESTABLISHED",
        "False qualification evidence",
    )
    require(
        engineering.get("memory_measurement_kind")
        == "REGISTERED_DIRECT_CAPACITY_NOT_RSS",
        "Misrepresented memory measurement",
    )
    require(
        engineering.get("ci_run_id") == "39240463549"
        and engineering.get("ci_outcome") == "SUCCESS",
        "Unexpected historical CI reference",
    )

    limitations = record.get("limitations")
    require(
        type(limitations) is list
        and len(limitations) >= 10,
        "Incomplete limitations inventory",
    )
    for required in (
        "No accept deadline.",
        "No established total request-processing deadline.",
        "No general HTTP/1.1 request parser.",
        "Commercial release has not been approved.",
    ):
        require(required in limitations, "Missing limitation: " + required)

    require(
        record.get("reconciliation_blockers")
        and type(record["reconciliation_blockers"]) is list,
        "Missing reconciliation blockers",
    )

    print("CHECKPOINT_ID=PASS")
    print("GIT_PROVENANCE=PASS")
    print("ARTIFACT_IDENTITY=PASS")
    print("CAPABILITY_BOUNDARY=PASS")
    print("EVIDENCE_BOUNDARY=PASS")
    print("AUTHORITY_BOUNDARY=PASS")
    print("CP_LEGACY_M1_5_VALIDATION=PASS")


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) == 2 else DEFAULT
    try:
        validate(target)
    except (
        ReconciliationError, ValueError, KeyError,
        TypeError, OSError, subprocess.CalledProcessError,
    ) as exc:
        print(f"CP_LEGACY_M1_5_VALIDATION=FAIL reason={exc}")
        sys.exit(1)
