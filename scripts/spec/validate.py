#!/usr/bin/env python3
"""Validate JOVRA's cross-platform contracts (spec/). Standard library only.

1. Every schema uses only keywords the bundled checker implements, and every $ref resolves.
2. Self-tests: known-bad instances must fail and known-good ones pass (the checker is not vacuous).
3. Every JSON file under spec/fixtures and spec/contracts validates against the schema its "kind" names.
4. The reference engine (spec/reference) is re-run on every fixture: expected outputs must match exactly,
   hand-written assertions must hold, the sample match must satisfy C1-C16, CSV exports must match
   byte-for-byte, and file sizes/hashes quoted in export/archive examples must match the files.

Exit status is non-zero on any failure.  Usage:  python3 scripts/spec/validate.py [-v]
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "spec"
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(SPEC / "reference"))

from jsonschema_subset import SchemaSet  # noqa: E402

from jovra_ref import conformance, csv_export, sample_match, scoring, stats  # noqa: E402

KIND_TO_SCHEMA = {
    "jovra.session": "session.schema.json",
    "jovra.equipment": "equipment.schema.json",
    "jovra.archiveManifest": "archive-manifest.schema.json",
    "jovra.capabilityRegistry": "capability-registry.schema.json",
    "jovra.practicePlan": "practice-plan.schema.json",
    "jovra.export": "export.schema.json",
    "jovra.csvContract": "csv-contract.schema.json",
    "jovra.fixture.scoring": "fixture-scoring.schema.json",
    "jovra.fixture.stats": "fixture-stats.schema.json",
    "jovra.fixture.pct": "fixture-pct.schema.json",
    "jovra.fixture.units": "fixture-units.schema.json",
    "jovra.fixture.sample": "fixture-sample.schema.json",
}


class Report:
    def __init__(self, verbose: bool):
        self.verbose = verbose
        self.failures: list[str] = []
        self.counts: dict[str, int] = {}

    def ok(self, what: str) -> None:
        self.counts[what] = self.counts.get(what, 0) + 1

    def fail(self, where: str, message: str) -> None:
        self.failures.append(f"FAIL {where}: {message}")

    def log(self, message: str) -> None:
        if self.verbose:
            print(message)


def canon(value) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def first_difference(a, b, path="$") -> str:
    if type(a) is not type(b):
        return f"{path}: {a!r} != {b!r}"
    if isinstance(a, dict):
        for key in sorted(set(a) | set(b)):
            if key not in a or key not in b:
                return f"{path}.{key}: present on one side only"
            if canon(a[key]) != canon(b[key]):
                return first_difference(a[key], b[key], f"{path}.{key}")
    if isinstance(a, list):
        if len(a) != len(b):
            return f"{path}: length {len(a)} != {len(b)}"
        for i, (x, y) in enumerate(zip(a, b)):
            if canon(x) != canon(y):
                return first_difference(x, y, f"{path}[{i}]")
    return f"{path}: {a!r} != {b!r}"


def same(actual, expected, rep: Report, where: str) -> bool:
    if canon(actual) == canon(expected):
        return True
    rep.fail(where, "engine output differs from fixture: " + first_difference(expected, actual))
    return False


# ----- 1 + 2: schemas ----------------------------------------------------------------------------

def schema_self_tests(schemas: SchemaSet, rep: Report) -> None:
    session = json.loads((SPEC / "fixtures/sample/jon-vs-alex.session.json").read_text(encoding="utf-8"))
    archive = json.loads((SPEC / "fixtures/sample/archive.json").read_text(encoding="utf-8"))
    cases = []
    bad = json.loads(canon(session))
    bad["match"]["log"][0]["reviewed"]["winner"] = "C"
    cases.append(("session.schema.json", bad, False, "point winner outside A/B/unknown"))
    bad = json.loads(canon(session))
    del bad["match"]
    cases.append(("session.schema.json", bad, False, "match session without a match block"))
    bad = json.loads(canon(session))
    bad["match"]["log"][0]["insertBefore"] = bad["match"]["log"][1]["id"]
    bad["match"]["log"][0]["supersedes"] = bad["match"]["log"][2]["id"]
    cases.append(("session.schema.json", bad, False, "supersedes and insertBefore together"))
    bad = json.loads(canon(session))
    bad["match"]["log"][0]["reviewed"]["confidence"] = 1.5
    cases.append(("session.schema.json", bad, False, "confidence above 1"))
    bad = json.loads(canon(session))
    bad["unexpected"] = True
    cases.append(("session.schema.json", bad, False, "unknown top-level property"))
    bad = json.loads(canon(archive))
    bad["files"][0]["upload"]["state"] = "backedUp"
    cases.append(("archive-manifest.schema.json", bad, False, "backedUp without verification"))
    bad = json.loads(canon(archive))
    del bad["files"][0]["md5"]
    cases.append(("archive-manifest.schema.json", bad, False, "hash missing after hashing"))
    ok = json.loads(canon(archive))
    del ok["files"][0]["md5"], ok["files"][0]["sha256"]
    ok["files"][0]["upload"]["state"] = "queued"
    cases.append(("archive-manifest.schema.json", ok, True, "queued file may omit hashes"))
    cases.append(("common.schema.json#ratio", {"n": 1, "d": 8, "pct": 12.5, "display": "12.5%"}, False,
                  "fractional pct"))
    cases.append(("common.schema.json#tension", {"value": "23.6", "unit": "kg"}, True, "tension as entered"))
    cases.append(("common.schema.json#tension", {"value": 23.6, "unit": "kg"}, False, "tension as a float"))
    expected = json.loads((SPEC / "fixtures/sample/jon-vs-alex.expected.json").read_text(encoding="utf-8"))
    bad = json.loads(canon(expected))
    c15 = next(c for c in bad["constraints"] if c["id"] == "C15")
    del c15["waived"]
    cases.append(("fixture-sample.schema.json", bad, False, "partial constraint without its waiver"))
    bad = json.loads(canon(expected))
    next(c for c in bad["constraints"] if c["id"] == "C15")["status"] = "pass"
    cases.append(("fixture-sample.schema.json", bad, False, "waiver hidden under status pass"))
    for schema, instance, must_pass, label in cases:
        file, _, definition = schema.partition("#")
        target = {"$ref": f"{file}#/$defs/{definition}"} if definition else schemas.files[file]
        errors = schemas._validate(instance, target, file, "$")
        if (not errors) != must_pass:
            rep.fail("schema self-test", f"{label}: expected {'pass' if must_pass else 'fail'}")
        else:
            rep.ok("schema self-tests")


# ----- 3: instances ------------------------------------------------------------------------------

def validate_instances(schemas: SchemaSet, rep: Report) -> dict[Path, dict]:
    docs = {}
    for path in sorted(list((SPEC / "fixtures").rglob("*.json")) + list((SPEC / "contracts").rglob("*.json"))):
        rel = path.relative_to(ROOT)
        doc = json.loads(path.read_text(encoding="utf-8"))
        kind = doc.get("kind")
        schema = KIND_TO_SCHEMA.get(kind)
        if schema is None:
            rep.fail(str(rel), f"unknown kind {kind!r}")
            continue
        errors = schemas.validate(doc, schema)
        if errors:
            rep.fail(str(rel), f"schema {schema}: " + "; ".join(errors[:5]))
            continue
        rep.ok("instances valid")
        docs[path] = doc
    return docs


# ----- 4: engine re-run --------------------------------------------------------------------------

def check_scoring(path: Path, doc: dict, rep: Report) -> None:
    where = str(path.relative_to(ROOT))
    if "expectError" in doc:
        code = conformance.run_scoring_error(doc["input"])
        if code != doc["expectError"]["code"]:
            rep.fail(where, f"expected rejection {doc['expectError']['code']}, engine gave {code}")
        else:
            rep.ok("scoring fixtures")
        return
    seqs = [cp["afterSeq"] for cp in doc["checkpoints"]]
    actual = conformance.run_scoring(doc["input"], seqs)
    good = same(actual, doc["checkpoints"], rep, where)
    problems = conformance.check_assertions(actual, doc["assertions"])
    for p in problems:
        rep.fail(where, "assertion " + p)
    if good and not problems:
        rep.ok("scoring fixtures")
        rep.counts["hand assertions"] = rep.counts.get("hand assertions", 0) + len(doc["assertions"])


def check_stats(path: Path, doc: dict, rep: Report) -> None:
    where = str(path.relative_to(ROOT))
    result = stats.compute(scoring.fold(doc["input"], doc["input"]["log"]))
    good = same(result, doc["expected"], rep, where)
    bad = 0
    for a in doc["assertions"]:
        if canon(conformance.get_path(result, a["path"])) != canon(a["equals"]):
            rep.fail(where, f"assertion {a['path']} != {a['equals']!r}")
            bad += 1
    if good and not bad:
        rep.ok("stats fixtures")
        rep.counts["hand assertions"] = rep.counts.get("hand assertions", 0) + len(doc["assertions"])


def check_vectors(path: Path, doc: dict, run, label: str, rep: Report) -> None:
    where = str(path.relative_to(ROOT))
    bad = 0
    for i, case in enumerate(doc["cases"]):
        actual = run(case)
        if canon(actual) != canon(case["expected"]):
            rep.fail(where, f"case {i} ({case['op']}): expected {case['expected']!r}, engine {actual!r}")
            bad += 1
    if not bad:
        rep.ok(f"{label} fixtures")
        rep.counts[f"{label} vectors"] = rep.counts.get(f"{label} vectors", 0) + len(doc["cases"])


def engine_input_from_session(session: dict) -> dict:
    match = session["match"]
    return {"format": match["format"], "players": session["players"], "sides": session["sides"],
            "toss": match["toss"], "log": match["log"]}


def check_sample(path: Path, doc: dict, docs: dict, rep: Report) -> None:
    where = str(path.relative_to(ROOT))
    session_path = path.parent / doc["sessionFile"]
    session = docs.get(session_path)
    if session is None:
        rep.fail(where, f"session file {doc['sessionFile']} missing or invalid")
        return
    fixture_input = engine_input_from_session(session)
    result = scoring.fold(fixture_input, fixture_input["log"])
    st = stats.compute(result)
    good = same({"fold": result, "stats": st}, doc["expected"], rep, where)
    checks = sample_match.constraints(session, result, st)
    good = same(checks, doc["constraints"], rep, f"{where} constraints") and good
    for c in checks:
        if c["status"] == "fail" or (c["status"] == "partial") != bool(c.get("waived")):
            rep.fail(where, f"{c['id']} fails: {c['detail']}")
            good = False
    A = st["sides"]["A"]
    engine_overview = {
        "scoreline": result["match"]["scoreline"], "durationMs": st["durationMs"],
        "points": result["match"]["pointsPlayed"], "pointsWon": A["totalPointsWon"],
        "firstServeIn": A["firstServeIn"], "firstServePointsWon": A["firstServePointsWon"],
        "shots": st["shots"]["total"], "reviewed": st["review"]["reviewed"], "flagged": st["review"]["needsReview"],
        "reviewCompletion": st["review"]["completion"],
    }
    good = same(engine_overview, doc["overview"], rep, f"{where} overview") and good
    for name, render in (("points", lambda: csv_export.points_csv(fixture_input, result)),
                         ("stats", lambda: csv_export.stats_csv(fixture_input, st))):
        golden = (path.parent / doc["csv"][name]).read_bytes()
        produced = render().encode("utf-8")
        contract = csv_export.load_contract(name)
        header = golden.split(b"\n", 1)[0].decode("utf-8").split(",")
        if header != [c["name"] for c in contract["columns"]]:
            rep.fail(where, f"{name}.csv header does not follow its contract")
            good = False
        if produced != golden:
            rep.fail(where, f"{name}.csv differs byte-for-byte from the regenerated export")
            good = False
        else:
            rep.ok("csv byte-for-byte")
    if good:
        rep.ok("sample match (C1-C16)")


def check_file_facts(path: Path, doc: dict, rep: Report) -> None:
    where = str(path.relative_to(ROOT))
    entries = doc["files"]
    for entry in entries:
        rel = entry.get("path") or entry.get("localPath")
        target = path.parent / rel
        if not target.exists():
            rep.fail(where, f"{rel} does not exist")
            continue
        data = target.read_bytes()
        if entry["bytes"] != len(data) or ("sha256" in entry and entry["sha256"] != hashlib.sha256(data).hexdigest()) \
                or ("md5" in entry and entry["md5"] != hashlib.md5(data).hexdigest()):
            rep.fail(where, f"size/hash of {rel} does not match the file")
            continue
        rep.ok("file hashes")


def check_registry(doc: dict, docs: dict, rep: Report) -> None:
    ids = [c["id"] for c in doc["capabilities"]]
    if len(ids) != len(set(ids)):
        rep.fail("capability registry", "duplicate capability ids")
    for c in doc["capabilities"]:
        for dep in c["requires"].get("capabilities", []):
            if dep not in ids:
                rep.fail("capability registry", f"{c['id']} depends on unknown {dep}")
        if c["status"] == "validated" and not (c["lastBenchmark"] and c["lastBenchmark"]["passed"]):
            rep.fail("capability registry", f"{c['id']} is validated without a passing benchmark (ADR-0004)")
    referenced = set()

    def walk(node):
        if isinstance(node, dict):
            if "capabilityId" in node:
                referenced.add(node["capabilityId"])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    for d in docs.values():
        walk(d)
    for cid in sorted(referenced - set(ids)):
        rep.fail("capability registry", f"fixtures reference unknown capability {cid}")
    rep.ok("registry checks")


def check_references(docs: dict, rep: Report) -> None:
    by_kind: dict[str, list] = {}
    for path, d in docs.items():
        by_kind.setdefault(d["kind"], []).append((path, d))
    equipment = [d for _, d in by_kind.get("jovra.equipment", [])]
    rackets = {r["id"] for e in equipment for r in e["rackets"]}
    jobs = {j["id"]: j for e in equipment for j in e["stringJobs"]}
    for e in equipment:
        for j in e["stringJobs"]:
            if j["racketId"] not in rackets:
                rep.fail("equipment", f"string job {j['id']} names unknown racket")
    sessions = {d["id"]: d for _, d in by_kind.get("jovra.session", [])}
    for s in sessions.values():
        for use in s.get("equipmentUse", []):
            if use["racketId"] not in rackets or ("stringJobId" in use and use["stringJobId"] not in jobs):
                rep.fail("session", f"{s['id']} equipmentUse references unknown equipment")
    for path, plan in by_kind.get("jovra.practicePlan", []):
        for item in plan["items"]:
            for ev in item["evidence"]:
                session = sessions.get(ev["sessionId"])
                if session is None:
                    rep.fail(str(path.relative_to(ROOT)), "evidence names an unknown session")
                    continue
                inp = engine_input_from_session(session)
                st = stats.compute(scoring.fold(inp, inp["log"]))
                if canon(st["sides"][ev["side"]][ev["stat"]]) != canon(ev["value"]):
                    rep.fail(str(path.relative_to(ROOT)), f"evidence {ev['stat']} does not match the engine")
                log_ids = {e["id"] for e in session["match"]["log"]}
                if not set(ev.get("pointIds", [])) <= log_ids:
                    rep.fail(str(path.relative_to(ROOT)), "evidence points are not in the session log")
    rep.ok("cross-references")


def main() -> int:
    rep = Report("-v" in sys.argv)
    schemas = SchemaSet(SPEC / "schemas")
    for problem in schemas.check_all():
        rep.fail("schema", problem)
    rep.counts["schemas"] = len(schemas.files)
    schema_self_tests(schemas, rep)
    docs = validate_instances(schemas, rep)
    for path, doc in docs.items():
        kind = doc["kind"]
        if kind == "jovra.fixture.scoring":
            check_scoring(path, doc, rep)
        elif kind == "jovra.fixture.stats":
            check_stats(path, doc, rep)
        elif kind == "jovra.fixture.pct":
            check_vectors(path, doc, conformance.run_pct_case, "pct", rep)
        elif kind == "jovra.fixture.units":
            check_vectors(path, doc, conformance.run_units_case, "units", rep)
        elif kind == "jovra.fixture.sample":
            check_sample(path, doc, docs, rep)
        elif kind in ("jovra.export", "jovra.archiveManifest"):
            check_file_facts(path, doc, rep)
        elif kind == "jovra.capabilityRegistry":
            check_registry(doc, docs, rep)
    check_references(docs, rep)

    for line in rep.failures:
        print(line)
    print("---- spec validation summary ----")
    for key in sorted(rep.counts):
        print(f"{key:28} {rep.counts[key]}")
    if rep.failures:
        print(f"RESULT: FAIL ({len(rep.failures)} failure(s))")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
