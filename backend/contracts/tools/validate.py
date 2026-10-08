#!/usr/bin/env python3
"""Validate the backend contracts (S81): schemas, every fixture, the deliberately invalid cases and cross-checks.

    python3 backend/contracts/tools/validate.py [--contracts DIR] [--require-jsonschema] [-v]

1. Every schema uses only keywords the bundled checker implements (scripts/spec/jsonschema_subset.py), so no rule
   can be silently ignored, and is a valid draft 2020-12 schema.
2. Every fixture under fixtures/routes/<route id>/ validates against its route's request or response schema, and
   every fixture under fixtures/queues/<queue>/ against that queue's message schema.
3. Every case in fixtures/invalid/cases.json fails its schema, with an error containing errorContains.
4. Cross-checks a schema cannot express: a JSON body's requestId equals its X-Request-Id header; a 206 response's
   Content-Length equals the length of its Content-Range; a response's error code is one the manifest lists.
5. The job states equal spec/studio/contracts/render-job-transitions.v1.json minus the quote states.

When the `jsonschema` package is importable (CI installs it; --require-jsonschema makes it mandatory) every check
in 1-3 also runs through it, so a fixture must satisfy both an independent validator and the bundled one.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

CONTRACTS = Path(__file__).resolve().parents[1]
REPO = CONTRACTS.parents[1]
sys.path.insert(0, str(REPO / "scripts" / "spec"))

from jsonschema_subset import SchemaSet  # noqa: E402

TRANSITIONS = REPO / "spec" / "studio" / "contracts" / "render-job-transitions.v1.json"
QUOTE_STATES = {"draft", "quoted"}


class Independent:
    """The `jsonschema` package, when present: a second, independent validator."""

    def __init__(self, schema_dir: Path, required: bool):
        try:
            from jsonschema import Draft202012Validator
            from referencing import Registry, Resource
        except ImportError:
            if required:
                raise SystemExit("FAIL  --require-jsonschema: the jsonschema package is not installed")
            self.enabled = False
            return
        self.enabled = True
        self.cls = Draft202012Validator
        self.schemas = {p.name: json.loads(p.read_text(encoding="utf-8")) for p in schema_dir.glob("*.schema.json")}
        registry = Registry()
        for name, schema in self.schemas.items():
            registry = registry.with_resource(name, Resource.from_contents(schema))
        self.registry = registry

    def meta_errors(self, name: str) -> list[str]:
        from jsonschema.exceptions import SchemaError
        try:
            self.cls.check_schema(self.schemas[name])
        except SchemaError as exc:
            return [f"jsonschema: {exc.message}"]
        return []

    def errors(self, instance, name: str) -> list[str]:
        validator = self.cls(self.schemas[name], registry=self.registry)
        return [f"jsonschema {'/'.join(str(p) for p in e.absolute_path) or '$'}: {e.message}"
                for e in validator.iter_errors(instance)]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def cross_checks(instance: dict, side: str, route: dict | None) -> list[str]:
    problems = []
    if side != "response" or not isinstance(instance, dict):
        return problems
    headers = instance.get("headers", {})
    body = instance.get("body")
    if isinstance(body, dict) and "requestId" in body and body["requestId"] != headers.get("X-Request-Id"):
        problems.append("requestId differs from the X-Request-Id header")
    if instance.get("status") == 206:
        match = re.fullmatch(r"bytes ([0-9]+)-([0-9]+)/([0-9]+)", headers.get("Content-Range", ""))
        if match:
            first, last, total = (int(g) for g in match.groups())
            if not first <= last < total:
                problems.append(f"Content-Range {headers['Content-Range']!r} is not inside the object")
            if headers.get("Content-Length") != str(last - first + 1):
                problems.append("Content-Length differs from the Content-Range length")
    if route is not None and isinstance(body, dict) and isinstance(body.get("error"), dict):
        code = body["error"].get("code")
        if code not in route["errors"]:
            problems.append(f"error code {code!r} is not listed for {route['id']} in routes.v1.json")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--contracts", type=Path, default=CONTRACTS)
    parser.add_argument("--require-jsonschema", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    contracts: Path = args.contracts
    schema_dir = contracts / "schemas"
    fixtures = contracts / "fixtures"
    subset = SchemaSet(schema_dir)
    independent = Independent(schema_dir, args.require_jsonschema)
    manifest = load(contracts / "routes.v1.json")
    routes = {r["id"]: r for r in manifest["routes"]}
    queues = {q["name"]: q for q in manifest["queues"]}
    problems: list[str] = []
    counts = {"schemas": 0, "fixtures": 0, "invalid": 0}

    def report(where: str, errors: list[str]):
        for error in errors:
            problems.append(f"{where}: {error}")
            print(f"FAIL  {where}: {error}")

    # 1. Schemas.
    report("schemas", subset.check_all())
    for name in sorted(subset.files):
        counts["schemas"] += 1
        if independent.enabled:
            report(f"schemas/{name}", independent.meta_errors(name))
    for route in manifest["routes"]:
        for side in ("request", "response"):
            if route[side]["schema"] not in subset.files:
                report(route["id"], [f"{side} schema {route[side]['schema']} missing"])
    for queue in manifest["queues"]:
        if queue["schema"] not in subset.files:
            report(queue["name"], [f"queue schema {queue['schema']} missing"])
    known_codes = {e["code"] for e in manifest["errorCodes"]}
    for route in manifest["routes"]:
        unknown = set(route["errors"]) - known_codes
        if unknown:
            report(route["id"], [f"unknown error codes {sorted(unknown)}"])

    # 2. Valid fixtures.
    def check_valid(path: Path, schema: str, side: str, route: dict | None):
        counts["fixtures"] += 1
        rel = path.relative_to(fixtures)
        try:
            instance = load(path)
        except json.JSONDecodeError as exc:
            report(str(rel), [f"not JSON ({exc})"])
            return
        errors = subset.validate(instance, schema)
        if independent.enabled:
            errors += independent.errors(instance, schema)
        errors += cross_checks(instance, side, route)
        report(str(rel), errors)
        if not errors and args.verbose:
            print(f"ok    {rel}  ({schema})")

    route_dirs = fixtures / "routes"
    for folder in sorted(p for p in route_dirs.iterdir() if p.is_dir()):
        route = routes.get(folder.name)
        if route is None:
            report(f"routes/{folder.name}", ["no such route in routes.v1.json"])
            continue
        for path in sorted(folder.glob("*.json")):
            side = path.name.split(".", 1)[0]
            if side not in ("request", "response"):
                report(str(path.relative_to(fixtures)), ["name must start with request. or response."])
                continue
            check_valid(path, route[side]["schema"], side, route)
    for folder in sorted(p for p in (fixtures / "queues").iterdir() if p.is_dir()):
        queue = queues.get(folder.name)
        if queue is None:
            report(f"queues/{folder.name}", ["no such queue in routes.v1.json"])
            continue
        paths = sorted(folder.glob("message.*.json"))
        if not paths:
            report(f"queues/{folder.name}", ["no message fixture"])
        for path in paths:
            check_valid(path, queue["schema"], "message", None)
    for queue in queues:
        if not (fixtures / "queues" / queue).is_dir():
            report(f"queues/{queue}", ["no fixture folder"])

    # 3. Deliberately invalid cases.
    invalid_dir = fixtures / "invalid"
    cases = load(invalid_dir / "cases.json")["cases"]
    listed = set()
    for case in cases:
        counts["invalid"] += 1
        listed.add(case["file"])
        path = invalid_dir / case["file"]
        if not path.is_file():
            report(f"invalid/{case['file']}", ["listed in cases.json but missing"])
            continue
        instance = load(path)
        subset_errors = subset.validate(instance, case["schema"])
        if not subset_errors:
            report(case["file"], ["expected to be invalid but validated (bundled checker)"])
            continue
        if not any(case["errorContains"] in e for e in subset_errors):
            report(case["file"], [f"invalid for another reason than {case['errorContains']!r}: {subset_errors[:3]}"])
        if independent.enabled and not independent.errors(instance, case["schema"]):
            report(case["file"], ["expected to be invalid but validated (jsonschema)"])
        if args.verbose:
            print(f"ok    invalid/{case['file']}  rejected: {case['why']}")
    for path in sorted(invalid_dir.rglob("*.json")):
        rel = str(path.relative_to(invalid_dir))
        if rel != "cases.json" and rel not in listed:
            report(f"invalid/{rel}", ["not listed in cases.json"])

    # 5. Job states agree with the shared transition contract.
    transitions = load(TRANSITIONS)
    common = load(schema_dir / "common.schema.json")
    job_states = set(common["$defs"]["jobState"]["enum"])
    expected = set(transitions["states"]) - QUOTE_STATES
    if job_states != expected:
        report("common.schema.json#/$defs/jobState", [
            f"differs from {TRANSITIONS.relative_to(REPO)} minus {sorted(QUOTE_STATES)}: "
            f"missing {sorted(expected - job_states)}, extra {sorted(job_states - expected)}"])

    validators = "bundled checker + jsonschema" if independent.enabled else "bundled checker only"
    summary = (f"{counts['schemas']} schemas, {counts['fixtures']} fixtures valid, {counts['invalid']} invalid cases "
               f"rejected, {len(manifest['routes'])} routes, {len(manifest['queues'])} queues ({validators})")
    if problems:
        print(f"FAIL  {len(problems)} problem(s); {summary}")
        return 1
    print(f"OK  {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
