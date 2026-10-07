#!/usr/bin/env python3
"""Regenerate every golden fixture under spec/fixtures from the reference engine.

A case is written only if the engine output satisfies the case's hand-written assertions, so a
fixture is never just "whatever the engine said". Run:  python3 spec/reference/generate_fixtures.py
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = HERE.parent
sys.path.insert(0, str(HERE))

from cases import records, stats_cases, units_cases  # noqa: E402
from cases.scoring_cases import CASES  # noqa: E402
from jovra_ref import canonical, conformance, sample_match  # noqa: E402

SCHEMA_VERSION = "1.0.0"


def write_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(canonical.dumps(obj) + "\n", encoding="utf-8")


def scoring_fixtures(out: Path) -> int:
    failures = []
    for build in CASES:
        c = build()
        fixture_input = dict(c["setup"])
        fixture_input["log"] = c["log"]
        assertions = [{"checkpoint": cp, "path": path, "equals": value} for cp, path, value in c["assertions"]]
        doc = {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "jovra.fixture.scoring",
            "id": c["id"],
            "title": c["title"],
            "covers": c["covers"],
            "input": fixture_input,
        }
        if c["expectError"] is not None:
            code = conformance.run_scoring_error(fixture_input)
            if code != c["expectError"]["code"]:
                failures.append(f"{c['id']}: expected error {c['expectError']['code']}, engine {code}")
                continue
            doc["expectError"] = c["expectError"]
        else:
            checkpoints = conformance.run_scoring(fixture_input, c["checkpoints"])
            problems = conformance.check_assertions(checkpoints, assertions)
            if problems:
                failures += [f"{c['id']}: {p}" for p in problems]
                continue
            doc["assertions"] = assertions
            doc["checkpoints"] = checkpoints
        write_json(out / f"{c['id']}.json", doc)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        raise SystemExit(f"{len(failures)} hand assertion(s) disagree with the engine; nothing trusted")
    return len(CASES)


def main() -> None:
    fixtures = SPEC / "fixtures"
    n_scoring = scoring_fixtures(fixtures / "scoring")
    n_stats = stats_cases.write(fixtures / "stats", write_json, SCHEMA_VERSION)
    n_units = units_cases.write(fixtures / "units", write_json, SCHEMA_VERSION)
    n_sample = sample_match.write(fixtures / "sample", write_json, SCHEMA_VERSION)
    n_records = records.write(fixtures / "records", SPEC / "contracts", write_json, SCHEMA_VERSION)
    print(f"scoring {n_scoring}, stats {n_stats}, units {n_units}, sample {n_sample}, records {n_records}")


if __name__ == "__main__":
    main()
