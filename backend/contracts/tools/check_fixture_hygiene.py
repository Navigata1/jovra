#!/usr/bin/env python3
"""Fixture hygiene (S81): no real identifier, URL, token or address in the backend contracts.

    python3 backend/contracts/tools/check_fixture_hygiene.py [path ...]
    default: backend/contracts/fixtures, backend/contracts/schemas and backend/contracts/routes.v1.json

Fails (exit 1) on:
  - a URL whose host is not example.test or a subdomain of it (a hosted URL)
  - a hosted-platform hostname even without a scheme (supabase.co, workers.dev, r2.dev, ...)
  - a project ref: a 20-letter Supabase ref, or a 32-hex Cloudflare account or zone id
  - a JWT-shaped string (three base64url parts, the first two starting with eyJ)
  - an email address outside example.test
  - a UUID that is not of the reserved sample form 00000000-0000-4000-8000-xxxxxxxxxxxx
  - a jv*_ capability token that does not start with jv?_Sample
A self-test runs first, so a broken pattern fails the check instead of passing silently (as S75's
check-hosted-identifiers.sh does). CLAUDE.md rules 5 and 7; ADR-0014 gate 2.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

CONTRACTS = Path(__file__).resolve().parents[1]
REPO = CONTRACTS.parents[1]

# Hosted-platform names are assembled from pieces so this file does not match itself.
HOSTED = ["supa" + "base.co", "supa" + "base.in", "workers" + ".dev", "pages" + ".dev", "r2" + ".dev",
          "r2.cloudflare" + "storage.com", "run" + ".app", "vercel" + ".app", "islanddevcrew."]
RULES: list[tuple[str, re.Pattern, callable]] = [
    ("hosted URL", re.compile(r"https?://([A-Za-z0-9.-]+)", re.I),
     lambda m: not re.fullmatch(r"([a-z0-9-]+\.)*example\.test", m.group(1).lower())),
    ("hosted platform hostname", re.compile(r"[A-Za-z0-9.-]*(" + "|".join(re.escape(h) for h in HOSTED) + r")[A-Za-z0-9.-]*",
                                            re.I), lambda m: True),
    ("Supabase project ref", re.compile(r"(?<![A-Za-z0-9_-])[a-z]{20}(?![A-Za-z0-9_-])"), lambda m: True),
    ("Cloudflare account or zone id", re.compile(r"(?<![0-9a-fA-F-])[0-9a-f]{32}(?![0-9a-fA-F-])"), lambda m: True),
    ("JWT-shaped string", re.compile(r"eyJ[A-Za-z0-9_-]{4,}\.eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*"), lambda m: True),
    ("email outside example.test", re.compile(r"[A-Za-z0-9._%+-]+@((?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,})(?![A-Za-z0-9-])"),
     lambda m: not re.fullmatch(r"([a-z0-9-]+\.)*example\.test", m.group(1).lower())),
    ("non-sample UUID", re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"),
     lambda m: not re.fullmatch(r"00000000-0000-4000-8000-[0-9A-Fa-f]{12}", m.group(0))),
    ("non-sample capability token", re.compile(r"jv[igslhc]_[A-Za-z0-9_-]{43}"),
     lambda m: not m.group(0)[4:].startswith("Sample")),
]


def scan_text(text: str) -> list[tuple[int, str, str]]:
    found = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for kind, pattern, offending in RULES:
            for match in pattern.finditer(line):
                if offending(match):
                    found.append((lineno, kind, match.group(0)))
    return found


SELF_TEST = {
    "hosted URL": "https://jovra-gateway.example.com/v1/health",
    "hosted platform hostname": "gateway." + HOSTED[2],
    "Supabase project ref": '"ref": "abcdefghijklmnopqrst"',
    "Cloudflare account or zone id": '"account": "' + "0123456789abcdef" * 2 + '"',
    "JWT-shaped string": "Bearer eyJ" + "hbGciOiJFUzI1NiJ9.eyJ" + "zdWIiOiJ4In0.sig",
    "email outside example.test": "coach@" + "gmail.com",
    "non-sample UUID": "3f2b8c1e-9d4a-4e7b-8a6c-1b2d3e4f5a6b",
    "non-sample capability token": "jvh_" + "Q" * 43,
}
CLEAN = ('{"url": "https://gateway.example.test/s/jvh_' + "Sample" * 7 + 'S", "email": "owner.tester@example.test", '
         '"id": "00000000-0000-4000-8000-0000000003AA", "sha256": "' + "5a" * 32 + '", '
         '"schema": "https://json-schema.org/draft/2020-12/schema", "word": "uploaded_unverified", '
         '"consentTextVersion": "studio-cloud-consent@1.0.0"}')
ALLOWED_URL_HOSTS = {"json-schema.org"}  # the draft 2020-12 meta-schema URI in every schema's $schema


def self_test() -> list[str]:
    failures = []
    for kind, sample in SELF_TEST.items():
        if not any(k == kind for _, k, _ in scan_text(sample)):
            failures.append(f"self-test: the {kind} rule missed its sample")
    leftovers = [(k, v) for _, k, v in scan_text(CLEAN) if not _allowed(k, v)]
    if leftovers:
        failures.append(f"self-test: a clean sample was flagged: {leftovers}")
    return failures


def _allowed(kind: str, value: str) -> bool:
    return kind == "hosted URL" and re.sub(r"^https?://", "", value).lower() in ALLOWED_URL_HOSTS


def main(argv: list[str]) -> int:
    failures = self_test()
    if failures:
        print("\n".join(failures))
        return 2
    targets = [Path(a) for a in argv] or [CONTRACTS / "fixtures", CONTRACTS / "schemas", CONTRACTS / "routes.v1.json"]
    files = []
    for target in targets:
        files += sorted(target.rglob("*.json")) if target.is_dir() else [target]
    problems = 0
    for path in files:
        for lineno, kind, value in scan_text(path.read_text(encoding="utf-8")):
            if _allowed(kind, value):
                continue
            problems += 1
            shown = path.relative_to(REPO) if path.is_relative_to(REPO) else path
            print(f"FAIL  {shown}:{lineno}: {kind}: {value}")
    if problems:
        print(f"FAIL  {problems} finding(s) in {len(files)} files")
        return 1
    print(f"OK  {len(files)} files: no hosted URL, project ref, JWT, real email, non-sample UUID or token")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
