#!/usr/bin/env python3
"""Read-only, non-effective ownership decision preflight.

Checks candidate PROPOSED records against the v0.2 field model,
frozen requirement identity and current baseline snapshot.

Does not verify approval authority, publish decisions or change
milestone status. A PASS is not an authorised decision.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "qualification/requirements"
CONTRACT = BASE / "ownership-decision-contract-v0.2.json"
SOURCE = BASE / "requirements-source-v0.3.json"
SNAPSHOT = ROOT / "qualification/tools/ownership_snapshot.py"


class Rejected(ValueError):
    pass


def pairs_unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Rejected("duplicate JSON key")
        result[key] = value
    return result


def nonfinite(value):
    raise Rejected(f"nonfinite JSON constant: {value}")


def load(data):
    return json.loads(
        data.decode("utf-8"),
        object_pairs_hook=pairs_unique,
        parse_constant=nonfinite,
    )


def require(condition, reason):
    if not condition:
        raise Rejected(reason)


def checked_text(value):
    return (
        isinstance(value, str)
        and bool(value.strip())
        and len(value) <= 1024
        and not any(ord(c) < 32 for c in value)
    )


def refs(value, *, required):
    require(isinstance(value, list), "references must be arrays")
    require(not required or bool(value), "missing source references")

    require(
        all(checked_text(item) for item in value),
        "invalid reference",
    )
    require(
        len(value) == len(set(value)),
        "duplicate reference",
    )

    for item in value:
        relative = Path(item)
        require(
            not relative.is_absolute()
            and ".." not in relative.parts,
            "unsafe reference path",
        )

        resolved = (ROOT / relative).resolve()
        require(
            resolved.is_relative_to(ROOT)
            and resolved.is_file(),
            "unresolvable reference",
        )


def current_snapshot():
    result = subprocess.run(
        [sys.executable, str(SNAPSHOT)],
        cwd=ROOT,
        capture_output=True,
        check=True,
    )
    document = load(result.stdout)
    return document["snapshot_sha256"]


def validate(candidate, expected_snapshot):
    contract = load(CONTRACT.read_bytes())
    source = load(SOURCE.read_bytes())

    require(type(candidate) is dict, "candidate must be an object")

    fields = set(contract["decision_record_schema"]["fields"])

    require(
        set(candidate) == fields,
        "candidate fields differ from v0.2 contract",
    )

    require(
        type(candidate["schema_version"]) is int
        and candidate["schema_version"] == 1,
        "invalid schema version",
    )

    require(
        checked_text(candidate["decision_id"]),
        "invalid decision ID",
    )

    requirement_id = candidate["requirement_id"]

    require(
        isinstance(requirement_id, str)
        and requirement_id in {
            entry["requirement_id"]
            for entry in source["entries"]
        },
        "unknown requirement",
    )

    require(
        candidate["first_mandatory_milestone"]
        in contract["scope"]["milestones"],
        "invalid milestone",
    )

    require(
        candidate["decision_status"] == "PROPOSED",
        "preflight accepts proposals only",
    )

    require(
        checked_text(candidate["decision_rationale"]),
        "missing or invalid rationale",
    )

    require(
        candidate["baseline_snapshot_id"] == expected_snapshot,
        "stale or invalid baseline snapshot",
    )

    refs(candidate["source_authority_refs"], required=True)
    refs(candidate["review_evidence_refs"], required=False)

    require(
        "qualification/requirements/requirements-source-v0.3.json"
        in candidate["source_authority_refs"],
        "frozen requirement source not referenced",
    )

    require(
        candidate["authority_designation_ref"] is None
        and candidate["approval_evidence_ref"] is None,
        "candidate must not claim approval authority",
    )

    require(
        candidate["supersedes_decision_ref"] is None,
        "supersession requires separate verification",
    )

    provenance = candidate["decision_provenance"]

    require(
        type(provenance) is dict
        and provenance == {
            "verification_status": "UNVERIFIED"
        },
        "preflight provenance must remain unverified",
    )

    return {
        "result": "PASS_NON_EFFECTIVE_PREFLIGHT",
        "requirement_id": requirement_id,
        "candidate_milestone": (
            candidate["first_mandatory_milestone"]
        ),
        "snapshot_sha256": expected_snapshot,
        "authority_verified": False,
        "decision_published": False,
        "milestone_closed": False,
    }


def main():
    if len(sys.argv) != 2:
        print(
            "Usage: ownership_decision_preflight.py CANDIDATE.json",
            file=sys.stderr,
        )
        return 2

    try:
        candidate = load(Path(sys.argv[1]).read_bytes())
        result = validate(candidate, current_snapshot())
    except (
        OSError, ValueError, KeyError, TypeError,
        subprocess.CalledProcessError,
    ) as exc:
        print(f"OWNERSHIP_PREFLIGHT=REJECT: {exc}")
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
