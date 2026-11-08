#!/usr/bin/env python3
"""Independently check the export bundles Swift's DataExporter wrote (JOVRA_DATA_BUNDLE_OUTPUT_DIR, T05).

For every folder holding an export.json: the manifest validates against spec/schemas/export.schema.json, it lists
exactly the files on disk, each file's size and SHA-256 (Python hashlib, not the Swift implementation) match, every
sessionJson file validates against the session schema, the sample session's CSVs are byte-identical to the golden
files, and a Share Pack viewer is self-contained (no scripts, external URLs or mailto). Negative controls prove the
checks can fail: a flipped byte, an unlisted file and an external URL must each be refused.

Run:  python3 scripts/spec/verify_native_bundle.py <dir>
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

from jsonschema_subset import SchemaSet

ROOT = Path(__file__).resolve().parents[2]
GOLDEN = ROOT / "spec/fixtures/sample"
SAMPLE_ID = json.loads((GOLDEN / "jon-vs-alex.session.json").read_text(encoding="utf-8"))["id"]
FORBIDDEN_VIEWER = [re.compile(p, re.I) for p in (r"<script", r"https?://", r"mailto:", r"<link\b", r"@import", r"<iframe")]


def bundle_problems(folder: Path, files: dict[str, bytes], schemas: SchemaSet) -> list[str]:
    """Problems with one bundle given as {relative path: bytes}; export.json must be among them."""
    problems: list[str] = []
    if "export.json" not in files:
        return [f"{folder}: no export.json"]
    manifest = json.loads(files["export.json"].decode("utf-8"))
    problems += [f"export.json: {e}" for e in schemas.validate(manifest, "export.schema.json")]
    listed = {entry["path"]: entry for entry in manifest.get("files", [])}
    on_disk = set(files) - {"export.json"}
    if set(listed) != on_disk:
        problems.append(f"manifest lists {sorted(set(listed) - on_disk)} missing, {sorted(on_disk - set(listed))} unlisted")
    for path, entry in listed.items():
        data = files.get(path)
        if data is None:
            continue
        if entry["bytes"] != len(data) or entry["sha256"] != hashlib.sha256(data).hexdigest():
            problems.append(f"{path}: size or SHA-256 differs from the file")
        if entry["role"] == "sessionJson":
            session = json.loads(data.decode("utf-8"))
            problems += [f"{path}: {e}" for e in schemas.validate(session, "session.schema.json")]
        if entry["role"] in ("pointsCsv", "statsCsv") and entry.get("sessionId") == SAMPLE_ID \
                and manifest.get("sharePack", {}).get("selection") != "selectedPoints":
            name = "jon-vs-alex.points.csv" if entry["role"] == "pointsCsv" else "jon-vs-alex.stats.csv"
            if data != (GOLDEN / name).read_bytes():
                problems.append(f"{path}: not byte-identical to spec/fixtures/sample/{name}")
        if entry["role"] == "viewerHtml":
            text = data.decode("utf-8")
            problems += [f"{path}: viewer contains {p.pattern}" for p in FORBIDDEN_VIEWER if p.search(text)]
    for session in manifest.get("sessions", []):
        if session["path"] not in listed:
            problems.append(f"session {session['id']} points at unlisted {session['path']}")
    if manifest.get("scope") == "sharePack" and not {"index.html", "match.json", "points.csv"} <= set(listed):
        problems.append("a Share Pack holds index.html, match.json and points.csv")
    return problems


def negative_controls(files: dict[str, bytes], schemas: SchemaSet, folder: Path) -> None:
    target = next(p for p in sorted(files) if p != "export.json")
    flipped = dict(files)
    flipped[target] = bytes([files[target][0] ^ 1]) + files[target][1:]
    extra = {**files, "unlisted.txt": b"x"}
    controls = [("flipped byte", flipped), ("unlisted file", extra)]
    viewer = next((p for p in files if p.endswith("index.html")), None)
    if viewer:
        controls.append(("external URL", {**files, viewer: files[viewer] + b"<img src=\"https://example.com/t.gif\">"}))
    for label, mutated in controls:
        if not bundle_problems(folder, mutated, schemas):
            raise SystemExit(f"FAIL negative control accepted: {label} in {folder.name}")


def main(directory: Path) -> int:
    schemas = SchemaSet(ROOT / "spec/schemas")
    folders = sorted({p.parent for p in directory.rglob("export.json")})
    if not folders:
        print(f"FAIL no export.json under {directory}")
        return 1
    failures = 0
    for folder in folders:
        files = {p.relative_to(folder).as_posix(): p.read_bytes() for p in folder.rglob("*") if p.is_file()}
        problems = bundle_problems(folder, files, schemas)
        for problem in problems:
            print(f"FAIL {folder.name}: {problem}")
        failures += len(problems)
        negative_controls(files, schemas, folder)
        print(f"{'FAIL' if problems else 'PASS'} {folder.name}: {len(files) - 1} files hashed and schema-checked; negative controls refused")
    print(f"RESULT: {'FAIL' if failures else 'PASS'} ({len(folders)} bundles)")
    return int(bool(failures))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: verify_native_bundle.py <dir>")
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]).resolve()))
