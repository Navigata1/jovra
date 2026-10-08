#!/usr/bin/env python3
"""Route coverage: every route of docs/backend/architecture.md §5.1 has a contract (S81).

Reads the "Method and path" column of the §5.1 table, compares it with backend/contracts/routes.v1.json and checks
that each route has its request and response schema files and at least one request and one response fixture.
Exits 1 on a missing route, an extra route the document does not name, a missing schema or a missing fixture.

    python3 backend/contracts/tools/route_coverage.py [--contracts DIR] [--manifest FILE] [--architecture FILE]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

CONTRACTS = Path(__file__).resolve().parents[1]
REPO = CONTRACTS.parents[1]
HEADING = "### 5.1 Endpoints"
METHODS = ("GET", "POST", "PUT", "PATCH", "DELETE")
ROUTE_CELL = re.compile(r"^`(" + "|".join(METHODS) + r") (/[^`\s]*)`")


def routes_from_architecture(text: str) -> list[tuple[str, str]]:
    """(method, path) pairs from the first column of the §5.1 table, in document order.

    A cell such as "`POST /v1/jobs/{jobId}/pause`, `/resume`" names a sibling route: the second path segment list
    replaces the last segment of the first route's path.
    """
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == HEADING)
    except StopIteration as exc:
        raise ValueError(f"no '{HEADING}' heading in the architecture document") from exc
    routes: list[tuple[str, str]] = []
    for line in lines[start + 1:]:
        if line.startswith("#"):
            break
        if not line.startswith("| `"):
            continue
        cell = line.split("|")[1].strip()
        match = ROUTE_CELL.match(cell)
        if not match:
            continue
        method, path = match.groups()
        routes.append((method, path))
        for sibling in re.findall(r"`(/[^`\s]+)`", cell[match.end():]):
            routes.append((method, path.rsplit("/", 1)[0] + sibling))
    return routes


def check(contracts: Path, manifest_path: Path, architecture: Path) -> list[str]:
    documented = routes_from_architecture(architecture.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    declared = {(r["method"], r["path"]): r for r in manifest["routes"]}
    problems: list[str] = []
    print(f"{len(documented)} routes in architecture §5.1 ({architecture.relative_to(REPO) if architecture.is_relative_to(REPO) else architecture})")
    for method, path in documented:
        route = declared.get((method, path))
        if route is None:
            problems.append(f"MISSING  {method} {path}: no entry in {manifest_path.name}")
            print(f"MISSING  {method} {path}")
            continue
        route_problems = route_files_problems(contracts, route)
        problems += route_problems
        status = "ok" if not route_problems else "INCOMPLETE"
        print(f"{status:<8} {method:<6} {path}  -> {route['id']}")
        for problem in route_problems:
            print(f"         {problem}")
    for method, path in sorted(set(declared) - set(documented)):
        problems.append(f"EXTRA    {method} {path}: not in architecture §5.1")
        print(f"EXTRA    {method} {path}")
    return problems


def route_files_problems(contracts: Path, route: dict) -> list[str]:
    problems = []
    route_id = route["id"]
    for side in ("request", "response"):
        schema = contracts / "schemas" / route[side]["schema"]
        if not schema.is_file():
            problems.append(f"{route_id}: {side} schema {schema.name} missing")
        fixtures = sorted((contracts / "fixtures" / "routes" / route_id).glob(f"{side}.*.json"))
        if not fixtures:
            problems.append(f"{route_id}: no {side} fixture")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--contracts", type=Path, default=CONTRACTS)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--architecture", type=Path, default=REPO / "docs" / "backend" / "architecture.md")
    args = parser.parse_args(argv)
    manifest = args.manifest or args.contracts / "routes.v1.json"
    problems = check(args.contracts, manifest, args.architecture)
    if problems:
        print(f"FAIL  {len(problems)} problem(s)")
        return 1
    print("OK  every documented route has a request and response schema and at least one fixture of each")
    return 0


if __name__ == "__main__":
    sys.exit(main())
