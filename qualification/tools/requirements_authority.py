#!/usr/bin/env python3
"""Validate the frozen AsmWeb Requirements v0.3 source authorities."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "qualification/requirements"

MEMBERSHIP = BASE / "requirements-membership-v0.3.json"
SOURCE = BASE / "requirements-source-v0.3.json"

AUTHORITY = "AsmWeb — Requirements & Scope Specification v0.3"
ODT_NAME = "AsmWeb-Requirements-n-ScopeSpecification-v0.3.odt"

PINNED_ODT = (
    "a6f3fa4f310f09dcce7fc747597b4f99"
    "a6b9c2b356dbccb83e5bde969155a62b"
)
PINNED_MEMBERSHIP = (
    "6f4c9c49e86a06bd9331ce508c5caf0"
    "a90753df18400c1e966aa0e16ed6b5c2a"
)
PINNED_TEXT = (
    "d0ce098435114d9262e4522de6c77dbe"
    "1c2ddc547646f9b293e144312567b16e"
)

CANONICALISATION = (
    "UTF-8; frozen membership-authority order; "
    "exactly one complete normative REQ identity per "
    "ODT text element; ODF-aware whitespace-normalised "
    "same-element statement; "
    "requirement_id + TAB + normative_statement + LF"
)

ID = re.compile(r"REQ-[A-Z0-9]+-[0-9]{3}\Z")
ANCHOR = re.compile(r"^(REQ-[A-Z0-9]+-[0-9]{3})(.*)$")

TEXT_NS = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
P = f"{{{TEXT_NS}}}p"
H = f"{{{TEXT_NS}}}h"
SPACE = f"{{{TEXT_NS}}}s"
TAB = f"{{{TEXT_NS}}}tab"
BREAK = f"{{{TEXT_NS}}}line-break"


class AuthorityError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise AuthorityError(message)


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise AuthorityError(
                f"duplicate JSON object key: {key}"
            )
        result[key] = value
    return result


def reject_nonfinite_constant(value):
    raise AuthorityError(
        f"non-finite JSON constant prohibited: {value}"
    )


def load(path):
    try:
        raw = path.read_bytes()
        return json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=reject_nonfinite_constant,
        )
    except (OSError, ValueError, UnicodeError) as exc:
        raise AuthorityError(
            f"{path}: invalid JSON: {exc}"
        ) from exc


def normalise(value):
    for char in ("\u00a0", "\u2007", "\u202f"):
        value = value.replace(char, " ")
    return re.sub(r"\s+", " ", value).strip()


def odf_text(element):
    pieces = []

    def walk(node):
        if node.text:
            pieces.append(node.text)
        for child in node:
            if child.tag == SPACE:
                count = int(child.get(f"{{{TEXT_NS}}}c", "1"))
                require(1 <= count <= 100000, "invalid ODF space count")
                pieces.append(" " * count)
            elif child.tag == TAB:
                pieces.append("\t")
            elif child.tag == BREAK:
                pieces.append("\n")
            else:
                walk(child)
            if child.tail:
                pieces.append(child.tail)

    walk(element)
    return normalise("".join(pieces))


def extract_odt(path):
    require(path.name == ODT_NAME, "unexpected ODT filename")
    require(path.is_file(), "controlled ODT is missing")
    require(digest(path.read_bytes()) == PINNED_ODT,
            "controlled ODT digest mismatch")

    try:
        with zipfile.ZipFile(path) as archive:
            root = ET.fromstring(archive.read("content.xml"))
    except (OSError, KeyError, ValueError, zipfile.BadZipFile,
            ET.ParseError) as exc:
        raise AuthorityError(f"invalid ODT: {exc}") from exc

    entries = []
    for element in root.iter():
        if element.tag not in (P, H):
            continue
        text = odf_text(element)
        match = ANCHOR.match(text)
        if not match:
            continue

        requirement_id, statement = match.groups()
        statement = statement.strip()

        require(ID.fullmatch(requirement_id) is not None,
                "invalid ODT requirement identity")
        require(bool(statement), f"{requirement_id}: empty ODT statement")
        require(sum(child.tag == BREAK for child in element.iter()) == 1,
                f"{requirement_id}: unexpected ODF line breaks")

        legacy_match = ANCHOR.match(
            normalise("".join(element.itertext()))
        )
        require(
            legacy_match is not None
            and legacy_match.group(1) == requirement_id
            and legacy_match.group(2).strip() == statement,
            f"{requirement_id}: source extraction disagreement"
        )

        entries.append({
            "requirement_id": requirement_id,
            "normative_statement": statement,
        })
    return entries


def validate(membership_path, source_path, odt_path=None):
    membership = load(membership_path)
    source = load(source_path)

    require(type(membership) is dict, "membership root is not an object")
    require(type(source) is dict, "source root is not an object")

    require(set(membership) == {
        "schema_version", "authority", "source_document_sha256",
        "canonical_membership_sha256", "requirement_count",
        "requirement_ids",
    }, "membership field shape mismatch")

    require(set(source) == {
        "schema_version", "authority", "source_document",
        "source_document_sha256", "requirement_count",
        "canonical_requirement_text_sha256", "canonicalisation",
        "entries",
    }, "source field shape mismatch")

    for name, data in (("membership", membership), ("source", source)):
        require(type(data["schema_version"]) is int
                and data["schema_version"] == 1,
                f"{name}: unsupported schema version")
        require(data["authority"] == AUTHORITY,
                f"{name}: authority mismatch")
        require(data["source_document_sha256"] == PINNED_ODT,
                f"{name}: provenance mismatch")
        require(type(data["requirement_count"]) is int
                and data["requirement_count"] == 1001,
                f"{name}: requirement count mismatch")

    require(source["source_document"] == ODT_NAME,
            "source document name mismatch")
    require(source["canonicalisation"] == CANONICALISATION,
            "canonicalisation contract mismatch")

    ids = membership["requirement_ids"]
    entries = source["entries"]

    require(type(ids) is list and len(ids) == 1001,
            "membership must contain exactly 1001 IDs")
    require(type(entries) is list and len(entries) == 1001,
            "source must contain exactly 1001 entries")

    require(all(type(identity) is str and ID.fullmatch(identity)
                for identity in ids),
            "invalid requirement ID")
    require(len(set(ids)) == len(ids), "duplicate requirement IDs")

    for index, entry in enumerate(entries):
        require(type(entry) is dict
                and set(entry) == {
                    "requirement_id", "normative_statement"
                }, f"source entry {index}: field shape mismatch")
        require(type(entry["requirement_id"]) is str,
                f"source entry {index}: invalid ID type")
        require(type(entry["normative_statement"]) is str
                and bool(entry["normative_statement"].strip()),
                f"source entry {index}: empty or invalid statement")
        statement = entry["normative_statement"]
        require(
            not any(0xD800 <= ord(char) <= 0xDFFF for char in statement),
            f"source entry {index}: invalid Unicode surrogate"
        )
        require(
            statement == normalise(statement),
            f"source entry {index}: noncanonical whitespace"
        )

    require(
        [entry["requirement_id"] for entry in entries] == ids,
        "source order or membership mismatch"
    )

    require(ids[0] == "REQ-GOV-001"
            and ids[-1] == "REQ-DEV-003",
            "source boundary identities mismatch")

    namespaces = [identity.split("-")[1] for identity in ids]
    runs = []
    for namespace in namespaces:
        if not runs or runs[-1] != namespace:
            runs.append(namespace)

    require(len(runs) == 115 and len(set(runs)) == 115,
            "namespace structure mismatch")

    membership_payload = "".join(
        identity + "\n" for identity in sorted(ids)
    ).encode("utf-8")

    text_payload = "".join(
        entry["requirement_id"] + "\t"
        + entry["normative_statement"] + "\n"
        for entry in entries
    ).encode("utf-8")

    actual_membership = digest(membership_payload)
    actual_text = digest(text_payload)

    require(membership["canonical_membership_sha256"]
            == actual_membership, "membership declared digest mismatch")
    require(actual_membership == PINNED_MEMBERSHIP,
            "membership frozen digest mismatch")
    require(source["canonical_requirement_text_sha256"]
            == actual_text, "source declared digest mismatch")
    require(actual_text == PINNED_TEXT,
            "source frozen digest mismatch")

    if odt_path is not None:
        require(entries == extract_odt(odt_path),
                "frozen source differs from controlled ODT")

    return {
        "requirement_count": len(ids),
        "namespace_count": len(runs),
        "membership_sha256": actual_membership,
        "normative_text_sha256": actual_text,
        "odt_checked": odt_path is not None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--membership", type=Path, default=MEMBERSHIP)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--odt", type=Path, default=None)
    args = parser.parse_args()

    try:
        result = validate(args.membership, args.source, args.odt)
    except (AuthorityError, OSError, ValueError) as exc:
        print(f"REQUIREMENTS_AUTHORITY_VALIDATION=FAIL: {exc}")
        return 1

    for key, value in result.items():
        print(f"{key}={value}")
    print("REQUIREMENTS_AUTHORITY_VALIDATION=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
