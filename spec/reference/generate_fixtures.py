#!/usr/bin/env python3
"""Regenerate every golden fixture under spec/fixtures (and the shipped contracts) from the reference engine.

Fixture sources are found by convention: every module in spec/reference/cases/ that defines
generate(ctx) is run, in (ORDER, name) order. Adding a fixture kind means adding a cases module and a
schema; this file never changes. A case is written only if the engine output satisfies the case's
hand-written assertions, so a fixture is never just "whatever the engine said".

Run:  python3 spec/reference/generate_fixtures.py
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

HERE = Path(__file__).resolve().parent
SPEC = HERE.parent
sys.path.insert(0, str(HERE))

from jovra_ref import canonical, conformance  # noqa: E402

# Version stamped on fixtures whose bytes predate T02. Records that use 1.1 fields set their own version.
SCHEMA_VERSION = "1.0.0"


def write_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(canonical.dumps(obj) + "\n", encoding="utf-8")


@dataclass(frozen=True)
class Context:
    """What every cases module's generate(ctx) receives."""
    spec: Path
    fixtures: Path
    contracts: Path
    write_json: Callable[[Path, object], None]
    version: str


def main() -> None:
    ctx = Context(spec=SPEC, fixtures=SPEC / "fixtures", contracts=SPEC / "contracts", write_json=write_json,
                  version=SCHEMA_VERSION)
    counts = []
    for module in conformance.case_modules():
        n = module.generate(ctx)
        counts.append(f"{module.__name__.removeprefix('cases.')} {n}")
    print(", ".join(counts))


if __name__ == "__main__":
    main()
