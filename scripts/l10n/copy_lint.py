#!/usr/bin/env python3
"""Copy lint: no claim one camera cannot back (story 371), no sample-only value, anywhere in the app.

Usage: scripts/l10n/copy_lint.py [catalog.xcstrings | file.swift | directory ...]
       (default: every String Catalog in ios/ and every Swift string literal in the app target ios/Jovra)

Every catalog key and localized value (plural and device variations included), and every string literal
in the app's Swift sources (Text(verbatim:), accessibility labels, anything else outside comments), is
checked against the banned terms below. A catalog entry may allow one rule when it states what JOVRA
does *not* do, by putting `copy-lint: allow <rule> — <reason>` in the entry's comment; a Swift line may
do the same with a trailing `// copy-lint: allow <rule> — <reason>`. The reason is required.
A directory argument covers its catalogs and its Swift files outside test folders (*Tests).
Exit status 1 when anything is flagged.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
from dataclasses import dataclass

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from literal_lint import _comment_spans, _string_end  # noqa: E402

RULES: list[tuple[str, re.Pattern[str], str]] = [
    ("spin-rate", re.compile(r"\bspin[- ]rates?\b", re.I), "no spin measurement (CLAUDE.md rule 1)"),
    ("rpm", re.compile(r"\brpm\b", re.I), "no spin RPM (CLAUDE.md rule 1)"),
    ("line-call", re.compile(r"\bline[- ]calls?\b", re.I), "no officiating-grade line calls (CLAUDE.md rule 1)"),
    ("injury", re.compile(r"\binjur(?:y|ies|ed)\b", re.I), "no injury or medical claims (CLAUDE.md rule 1)"),
    ("calories", re.compile(r"\bcalories?\b", re.I), "no invented calories (story 379)"),
    ("fastest-serve", re.compile(r"\bfastest\s+serves?\b", re.I), "say 'Fastest marked serve' (screen spec S12)"),
    ("reference-concept", re.compile(r"\breference concept\b", re.I), "the settings footer shows the app version"),
    ("mailto", re.compile(r"mailto:", re.I), "contact address as text only (CLAUDE.md rule 7)"),
    ("sample-storage", re.compile(r"(?<![\d.,])3[.,]2\s*GB\b", re.I), "the storage estimate is computed, never the sample 3.2 GB"),
]
ADVANTAGE_SEGMENT = re.compile(r"^\s*Advantage\s*$")
ADVANTAGE_RULE = ("advantage-format", "games are 'Ad' or 'No-Ad'; sets 'Advantage set' (screen spec §0.2 rule 2)")
ALLOW = re.compile(r"copy-lint:\s*allow\s+(?P<rule>[\w-]+)\s*[—–-]+\s*\S")


@dataclass(frozen=True)
class Finding:
    catalog: str
    key: str
    rule: str
    text: str
    why: str

    def __str__(self) -> str:
        return f"{self.catalog}: “{self.key}”: {self.rule}: “{self.text}” ({self.why})"


def _texts(node):
    """Every stringUnit value under a localization node (variations included)."""
    if isinstance(node, dict):
        unit = node.get("stringUnit")
        if isinstance(unit, dict) and isinstance(unit.get("value"), str):
            yield unit["value"]
        for key, value in node.items():
            if key != "stringUnit":
                yield from _texts(value)
    elif isinstance(node, list):
        for item in node:
            yield from _texts(item)


def check_text(text: str) -> list[tuple[str, str]]:
    """(rule, why) for every banned term in one string."""
    hits = [(rule, why) for rule, pattern, why in RULES if pattern.search(text)]
    if any(ADVANTAGE_SEGMENT.match(segment) for segment in text.split("·")):
        hits.append(ADVANTAGE_RULE)
    return hits


def lint_catalog(path: pathlib.Path) -> list[Finding]:
    catalog = json.loads(path.read_text(encoding="utf-8"))
    findings: list[Finding] = []
    for key, entry in catalog.get("strings", {}).items():
        allowed = {match.group("rule") for match in ALLOW.finditer(entry.get("comment", "") or "")}
        seen: set[str] = set()  # one finding per rule per entry
        for text in [key, *_texts(entry.get("localizations", {}))]:
            for rule, why in check_text(text):
                if rule in allowed or rule in seen:
                    continue
                seen.add(rule)
                findings.append(Finding(str(path), key, rule, text, why))
    return findings


def _string_literals(text: str):
    """(offset, literal) for every string literal outside comments (interpolations stay inside)."""
    comments = _comment_spans(text)
    index = 0
    while index < len(text):
        if any(start <= index < end for start, end in comments):
            index = next(end for start, end in comments if start <= index < end)
            continue
        if text[index] == '"':
            end = _string_end(text, index)
            yield index, text[index:end]
            index = end
            continue
        index += 1


def lint_swift(path: pathlib.Path) -> list[Finding]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    findings: list[Finding] = []
    for offset, literal in _string_literals(text):
        number = text.count("\n", 0, offset) + 1
        allowed = {match.group("rule") for match in ALLOW.finditer(lines[number - 1])}
        for rule, why in check_text(literal):
            if rule not in allowed:
                findings.append(Finding(str(path), f"line {number}", rule, literal, why))
    return findings


IGNORED_DIRECTORIES = {".derivedData", "DerivedData", ".build", "build"}


def find_catalogs(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted(p for p in root.rglob("*.xcstrings") if not IGNORED_DIRECTORIES.intersection(p.parts))


def find_swift_sources(root: pathlib.Path) -> list[pathlib.Path]:
    """App Swift sources under `root`; test targets are skipped (their fixtures quote banned copy)."""
    return sorted(p for p in root.rglob("*.swift")
                  if not IGNORED_DIRECTORIES.intersection(p.parts)
                  and not any(part.endswith("Tests") for part in p.relative_to(root).parts[:-1]))


def default_targets(root: pathlib.Path) -> tuple[list[pathlib.Path], list[pathlib.Path]]:
    """(catalog roots, Swift roots) linted when no argument is given."""
    return [root / "ios"], [root / "ios" / "Jovra"]


def main(argv: list[str]) -> int:
    root = pathlib.Path(__file__).resolve().parents[2]
    if argv:
        targets = [pathlib.Path(arg) for arg in argv]
        catalog_roots, swift_roots = targets, targets
    else:
        catalog_roots, swift_roots = default_targets(root)
    catalogs = [c for t in catalog_roots for c in ([t] if t.suffix == ".xcstrings" else [] if t.is_file() else find_catalogs(t))]
    sources = [s for t in swift_roots for s in ([t] if t.suffix == ".swift" else [] if t.is_file() else find_swift_sources(t))]
    findings = [finding for catalog in catalogs for finding in lint_catalog(catalog)]
    findings += [finding for source in sources for finding in lint_swift(source)]
    for finding in findings:
        print(finding)
    print(f"copy lint: {len(findings)} finding(s) in {len(catalogs)} catalog(s) and {len(sources)} Swift file(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
