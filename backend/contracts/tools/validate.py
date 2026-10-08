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


class Run:
    """One validation pass over a contracts folder: collects problems and counts as it goes."""

    def __init__(self, contracts: Path, require_jsonschema: bool, verbose: bool):
        self.schema_dir = contracts / "schemas"
        self.fixtures = contracts / "fixtures"
        self.subset = SchemaSet(self.schema_dir)
        self.independent = Independent(self.schema_dir, require_jsonschema)
        self.manifest = load(contracts / "routes.v1.json")
        self.verbose = verbose
        self.problems: list[str] = []
        self.counts = {"schemas": 0, "fixtures": 0, "invalid": 0}

    def report(self, where: str, errors: list[str]) -> None:
        for error in errors:
            self.problems.append(f"{where}: {error}")
            print(f"FAIL  {where}: {error}")

    def errors(self, instance, schema: str) -> list[str]:
        errors = self.subset.validate(instance, schema)
        if self.independent.enabled:
            errors += self.independent.errors(instance, schema)
        return errors

    # 1. Schemas and manifest.
    def check_schemas(self) -> None:
        self.report("schemas", self.subset.check_all())
        for name in sorted(self.subset.files):
            self.counts["schemas"] += 1
            if self.independent.enabled:
                self.report(f"schemas/{name}", self.independent.meta_errors(name))
        named = [(r["id"], r[side]["schema"]) for r in self.manifest["routes"] for side in ("request", "response")]
        named += [(q["name"], q["schema"]) for q in self.manifest["queues"]]
        for owner, schema in named:
            if schema not in self.subset.files:
                self.report(owner, [f"schema {schema} missing"])
        known_codes = {e["code"] for e in self.manifest["errorCodes"]}
        for route in self.manifest["routes"]:
            unknown = set(route["errors"]) - known_codes
            if unknown:
                self.report(route["id"], [f"unknown error codes {sorted(unknown)}"])

    # 2. Valid fixtures.
    def check_valid(self, path: Path, schema: str, side: str, route: dict | None) -> None:
        self.counts["fixtures"] += 1
        rel = path.relative_to(self.fixtures)
        try:
            instance = load(path)
        except json.JSONDecodeError as exc:
            self.report(str(rel), [f"not JSON ({exc})"])
            return
        errors = self.errors(instance, schema) + cross_checks(instance, side, route)
        self.report(str(rel), errors)
        if not errors and self.verbose:
            print(f"ok    {rel}  ({schema})")

    def check_route_fixtures(self) -> None:
        routes = {r["id"]: r for r in self.manifest["routes"]}
        for folder in sorted(p for p in (self.fixtures / "routes").iterdir() if p.is_dir()):
            route = routes.get(folder.name)
            if route is None:
                self.report(f"routes/{folder.name}", ["no such route in routes.v1.json"])
                continue
            for path in sorted(folder.glob("*.json")):
                side = path.name.split(".", 1)[0]
                if side not in ("request", "response"):
                    self.report(str(path.relative_to(self.fixtures)), ["name must start with request. or response."])
                    continue
                self.check_valid(path, route[side]["schema"], side, route)

    def check_queue_fixtures(self) -> None:
        for queue in self.manifest["queues"]:
            paths = sorted((self.fixtures / "queues" / queue["name"]).glob("message.*.json"))
            if not paths:
                self.report(f"queues/{queue['name']}", ["no message fixture"])
            for path in paths:
                self.check_valid(path, queue["schema"], "message", None)
        known = {q["name"] for q in self.manifest["queues"]}
        for folder in sorted(p for p in (self.fixtures / "queues").iterdir() if p.is_dir()):
            if folder.name not in known:
                self.report(f"queues/{folder.name}", ["no such queue in routes.v1.json"])

    # 3. Deliberately invalid cases.
    def check_invalid_case(self, invalid_dir: Path, case: dict) -> None:
        self.counts["invalid"] += 1
        path = invalid_dir / case["file"]
        if not path.is_file():
            self.report(f"invalid/{case['file']}", ["listed in cases.json but missing"])
            return
        instance = load(path)
        subset_errors = self.subset.validate(instance, case["schema"])
        if not subset_errors:
            self.report(case["file"], ["expected to be invalid but validated (bundled checker)"])
            return
        if not any(case["errorContains"] in e for e in subset_errors):
            self.report(case["file"], [f"invalid for another reason than {case['errorContains']!r}: "
                                       f"{subset_errors[:3]}"])
        if self.independent.enabled and not self.independent.errors(instance, case["schema"]):
            self.report(case["file"], ["expected to be invalid but validated (jsonschema)"])
        if self.verbose:
            print(f"ok    invalid/{case['file']}  rejected: {case['why']}")

    def check_invalid_cases(self) -> None:
        invalid_dir = self.fixtures / "invalid"
        cases = load(invalid_dir / "cases.json")["cases"]
        for case in cases:
            self.check_invalid_case(invalid_dir, case)
        listed = {case["file"] for case in cases}
        for path in sorted(invalid_dir.rglob("*.json")):
            rel = str(path.relative_to(invalid_dir))
            if rel != "cases.json" and rel not in listed:
                self.report(f"invalid/{rel}", ["not listed in cases.json"])

    # 5. Job states agree with the shared transition contract.
    def check_job_states(self) -> None:
        transitions = load(TRANSITIONS)
        common = load(self.schema_dir / "common.schema.json")
        job_states = set(common["$defs"]["jobState"]["enum"])
        expected = set(transitions["states"]) - QUOTE_STATES
        if job_states != expected:
            self.report("common.schema.json#/$defs/jobState", [
                f"differs from {TRANSITIONS.relative_to(REPO)} minus {sorted(QUOTE_STATES)}: "
                f"missing {sorted(expected - job_states)}, extra {sorted(job_states - expected)}"])

    def summary(self) -> str:
        validators = "bundled checker + jsonschema" if self.independent.enabled else "bundled checker only"
        return (f"{self.counts['schemas']} schemas, {self.counts['fixtures']} fixtures, "
                f"{self.counts['invalid']} invalid cases, {len(self.manifest['routes'])} routes, "
                f"{len(self.manifest['queues'])} queues ({validators})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--contracts", type=Path, default=CONTRACTS)
    parser.add_argument("--require-jsonschema", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    run = Run(args.contracts, args.require_jsonschema, args.verbose)
    run.check_schemas()
    run.check_route_fixtures()
    run.check_queue_fixtures()
    run.check_invalid_cases()
    run.check_job_states()
    if run.problems:
        print(f"FAIL  {len(run.problems)} problem(s); {run.summary()}")
        return 1
    print(f"OK  {run.summary()}: every fixture valid, every invalid case rejected for its stated reason")
    return 0


if __name__ == "__main__":
    sys.exit(main())
