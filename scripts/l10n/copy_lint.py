#!/usr/bin/env python3
"""Copy lint over String Catalogs: no claim one camera cannot back (story 371), no sample-only value.

Usage: scripts/l10n/copy_lint.py [catalog.xcstrings | directory ...]   (default: every catalog in ios/)

Every key and every localized value (plural and device variations included) is checked against the
banned terms below. An entry may allow one rule when it states what JOVRA does *not* do, by putting
`copy-lint: allow <rule> — <reason>` in the entry's comment; the reason is required.
Exit status 1 when anything is flagged.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
from dataclasses import dataclass

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


def find_catalogs(root: pathlib.Path) -> list[pathlib.Path]:
    ignored = {".derivedData", "DerivedData", ".build", "build"}
    return sorted(p for p in root.rglob("*.xcstrings") if not ignored.intersection(p.parts))


def main(argv: list[str]) -> int:
    root = pathlib.Path(__file__).resolve().parents[2]
    targets = [pathlib.Path(arg) for arg in argv] or [root / "ios"]
    catalogs = [c for t in targets for c in ([t] if t.is_file() else find_catalogs(t))]
    findings = [finding for catalog in catalogs for finding in lint_catalog(catalog)]
    for finding in findings:
        print(finding)
    print(f"copy lint: {len(findings)} finding(s) in {len(catalogs)} catalog(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
