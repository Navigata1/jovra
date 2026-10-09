#!/usr/bin/env python3
"""Validate JOVRA's cross-platform contracts (spec/). Standard library only.

1. Every schema uses only keywords the bundled checker implements, and every $ref resolves.
2. Self-tests: known-bad instances must fail and known-good ones pass (the checker is not vacuous).
3. Every JSON file under spec/fixtures and spec/contracts validates against the schema its "kind" names by
   convention (jovra.archiveManifest -> archive-manifest.schema.json; no lookup table), and every schema that
   declares a kind const declares the kind its file name stands for.
4. The reference engine (spec/reference) is re-run on every fixture: expected outputs must match exactly,
   hand-written assertions must hold, the sample match must satisfy C1-C16, CSV exports must match
   byte-for-byte, and file sizes/hashes quoted in export/archive examples must match the files.
5. Reference integrity (jovra_ref/references.py): every id a record holds names a record that exists, ranges run
   forwards, 1.1 times fall inside the recording, event-log versions are not later than the log, a stored serve speed
   and its range are recomputed from its mark, consent fields agree, and sample media ids exist in the sample media
   manifest.
6. Media ground truth is internally consistent, and every benchmark record is re-scored from its outputs and
   the committed ground truth (spec/reference/jovra_ref/benchmark.py); gating runs use held-out seeds only,
   each clip counts once, each clip carries its ground truth's renderer and decoded-frame hashes, and a record
   naming a capability is a candidate run on that capability's registry gate (ADR-0004) with the task,
   tolerance and metric names of its binding (spec/fixtures/media/benchmark-bindings.json, itself checked
   against the registry gates and the reference scorers). Malformed numbers are reported as failures, never
   crashes.

Exit status is non-zero on any failure.  Usage:  python3 scripts/spec/validate.py [-v]
"""

from __future__ import annotations

import hashlib
import json
import sys
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "spec"
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(SPEC / "reference"))

from jsonschema_subset import SchemaSet  # noqa: E402

from jovra_ref import benchmark, conformance, csv_export, references, sample_match, scoring, stats  # noqa: E402



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
    cases.append(("session.schema.json", session, True, "a schemaVersion 1.0.0 document after the 1.1 bump"))
    # JSON Schema patterns are ECMA-262: '$' is the end of the input, so a trailing newline must not pass '^...$'
    cases.append(("session.schema.json", dict(session, id=session["id"] + "\n"), False, "id ending in a newline"))
    cases.append(("session.schema.json", dict(session, createdAt=session["createdAt"] + "\n"), False,
                  "createdAt ending in a newline"))
    cases.append(("common.schema.json#sha256", "a" * 64 + "\n", False, "sha256 ending in a newline"))
    # a document stamped 1.0.x carries nothing added in 1.1.0 (each schema's $defs/v1_0)
    for name, schema in (("session", "session.schema.json"), ("practice-plan", "practice-plan.schema.json"),
                         ("export", "export.schema.json"), ("archive", "archive-manifest.schema.json")):
        example = json.loads((SPEC / f"fixtures/records/{name}.all-fields.json").read_text(encoding="utf-8"))
        cases.append((schema, dict(example, schemaVersion="1.0.0"), False, f"{name} 1.1 fields stamped 1.0.0"))
    example = json.loads((SPEC / "fixtures/records/session.all-fields.json").read_text(encoding="utf-8"))
    bad = json.loads(canon(example))
    bad["derivedValues"][0]["scope"].pop("serveMarkId", None)
    cases.append(("session.schema.json", bad, False, "serve speed naming no serve mark"))
    bad = json.loads(canon(example))
    bad["derivedValues"][0]["unit"] = "m/s"
    cases.append(("session.schema.json", bad, False, "serve speed in a unit other than mph or km/h"))
    bad = json.loads(canon(example))
    bad["derivedValues"][0].pop("range", None)
    cases.append(("session.schema.json", bad, False, "serve speed without its range"))
    bad = json.loads(canon(example))
    next(e for e in bad["recording"]["captureEvents"] if e["kind"] == "frameRateChange").pop("frameRate", None)
    cases.append(("session.schema.json", bad, False, "frameRateChange without its frame rate"))
    bad = json.loads(canon(example))
    next(e for e in bad["recording"]["captureEvents"] if e["kind"] == "thermalState").pop("thermalState", None)
    cases.append(("session.schema.json", bad, False, "thermalState event without its state"))
    for schema, instance, must_pass, label in cases:
        file, _, definition = schema.partition("#")
        target = {"$ref": f"{file}#/$defs/{definition}"} if definition else schemas.files[file]
        errors = schemas._validate(instance, target, file, "$")
        if (not errors) != must_pass:
            rep.fail("schema self-test", f"{label}: expected {'pass' if must_pass else 'fail'}")
        else:
            rep.ok("schema self-tests")


def object_paths(node, path="$"):
    """JSON paths of every object in a document, outermost first."""
    if isinstance(node, dict):
        yield path, node
        for key, value in node.items():
            yield from object_paths(value, f"{path}.{key}")
    elif isinstance(node, list):
        for i, value in enumerate(node):
            yield from object_paths(value, f"{path}[{i}]")


def closed_object_self_tests(schemas: SchemaSet, rep: Report) -> None:
    """Every object in a contract example (records/*.all-fields.json) is closed: an unknown property must fail."""
    for path in sorted((SPEC / "fixtures").rglob("*.all-fields.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        schema = conformance.schema_file_for_kind(doc["kind"])
        for where, _ in list(object_paths(doc)):
            probe = json.loads(canon(doc))
            target = dict(object_paths(probe))[where]
            target["unexpectedProperty"] = True
            if not schemas.validate(probe, schema):
                rep.fail(str(path.relative_to(ROOT)), f"{where} accepts an unknown property")
            else:
                rep.ok("closed-object rejections")


def kind_schema_checks(schemas: SchemaSet, rep: Report) -> None:
    """A schema that pins its kind must sit in the file its kind maps to, so the convention cannot drift."""
    for name, schema in schemas.files.items():
        const = schema.get("properties", {}).get("kind", {}).get("const")
        if const is None:
            continue
        expected = conformance.schema_file_for_kind(const)
        if expected != name:
            rep.fail("schema", f"{name} declares kind {const!r}, which maps to {expected}")
        else:
            rep.ok("kind-to-schema names")


# ----- 3: instances ------------------------------------------------------------------------------

def validate_instances(schemas: SchemaSet, rep: Report) -> dict[Path, dict]:
    docs = {}
    for path in sorted(list((SPEC / "fixtures").rglob("*.json")) + list((SPEC / "contracts").rglob("*.json"))
                       + list((SPEC / "benchmarks").rglob("*.json"))):
        rel = path.relative_to(ROOT)
        doc = json.loads(path.read_text(encoding="utf-8"))
        kind = doc.get("kind")
        try:
            schema = conformance.schema_file_for_kind(kind)
        except ValueError:
            rep.fail(str(rel), f"malformed kind {kind!r}")
            continue
        if schema not in schemas.files:
            rep.fail(str(rel), f"no schema {schema} for kind {kind!r}")
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
        if "md5" not in entry and "sha256" not in entry:
            continue  # not hashed yet (a queued archive job): nothing to verify against the file
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
            if node.get("capabilityId") is not None:   # a benchmark record may name no capability
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
    manifests = [d for _, d in by_kind.get("jovra.sampleMediaManifest", [])]
    manifest = manifests[0] if len(manifests) == 1 else None
    if len(manifests) != 1:
        rep.fail("sample media manifest", f"expected exactly one, found {len(manifests)}")
    per_kind = {
        "jovra.session": lambda d: references.session_problems(d, manifest),
        "jovra.practicePlan": references.practice_plan_problems,
        "jovra.export": lambda d: references.export_problems(d, sessions),
        "jovra.archiveManifest": lambda d: references.archive_problems(d, sessions),
    }
    for path, d in sorted(docs.items()):
        rule = per_kind.get(d["kind"], references.time_range_problems)
        problems = rule(d)
        for problem in problems:
            rep.fail(str(path.relative_to(ROOT)), problem)
        if not problems:
            rep.ok("reference-integrity documents")
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


# ----- 5: media ground truth and benchmark records ------------------------------------------------

def check_ground_truth(path: Path, doc: dict, docs: dict, rep: Report) -> None:
    where = str(path.relative_to(ROOT))
    try:
        problems = ground_truth_problems(path, doc, docs)
    except (ArithmeticError, ValueError, KeyError, TypeError) as e:   # malformed input is a failure, not a crash
        problems = [f"malformed ground truth: {type(e).__name__}: {e}"]
    for p in problems:
        rep.fail(where, p)
    if not problems:
        rep.ok("media ground truth")


def ground_truth_problems(path: Path, doc: dict, docs: dict) -> list[str]:
    problems = []
    set_name, _, clip_id = doc["id"].partition("/")
    if set_name != doc["set"] or path.parent.name != doc["set"] or path.name != f"{clip_id}.truth.json":
        problems.append("id, set, folder and file name disagree")
    v, sig = doc["video"], doc["signature"]
    rotated = v["rotationDegrees"] in (90, 270)
    if (v["displayWidth"], v["displayHeight"]) != ((v["codedHeight"], v["codedWidth"]) if rotated else (v["codedWidth"], v["codedHeight"])):
        problems.append("display size does not follow the coded size and rotation")
    w, h = v["displayWidth"], v["displayHeight"]
    if v["orientation"] != ("portrait" if h > w else "landscape" if w > h else "square"):
        problems.append("orientation does not follow the display size")
    rate = Fraction(v["frameRate"]["num"], v["frameRate"]["den"])
    duration = Fraction(v["frameCount"]) / rate
    if benchmark.rt(v["duration"]) != duration or benchmark.rt(v["duration"]).denominator != v["duration"]["timescale"]:
        problems.append("duration is not frameCount / frameRate in lowest terms")
    if sig["frameCount"] != v["frameCount"]:
        problems.append("decoded frame count differs from the encoded frame count")
    if v["codedWidth"] % sig["columns"] or v["codedHeight"] % sig["rows"] or sig["columns"] * sig["rows"] < doc["frameCode"]["cells"]:
        problems.append("signature grid does not divide the coded picture or cannot hold the frame code")
    if doc["audio"] is not None and doc["audio"]["sampleCount"] != duration * doc["audio"]["sampleRate"]:
        problems.append("audio sample count does not match the duration")
    folder, _, file = doc["media"]["path"].split("/", 2)[2].partition("/")
    if folder != f"{doc['set']}-{doc['renderer']['sourceHash'][:16]}" or not file.endswith("." + doc["media"]["container"]):
        problems.append("media path is not <set>-<sourceHash[:16]>/<file>.<container>")
    previous = Fraction(-1)
    for e in doc.get("events", []):
        t = benchmark.rt(e["time"])
        if t != Fraction(e["sample"], 48000) or t.denominator != e["time"]["timescale"]:
            problems.append(f"event at sample {e['sample']}: time is not sample / 48000 in lowest terms")
        if e["frame"] != int(t * rate) or not (previous < t < duration):
            problems.append(f"event at sample {e['sample']}: frame or order wrong, or outside the clip")
        previous = t
        if doc["audio"] is None:
            problems.append("events need an audio track")
            break
    if doc["duplicateOf"]:
        original = next((d for d in docs.values() if d.get("kind") == "jovra.groundTruth" and d["id"] == doc["duplicateOf"]), None)
        if original is None or original["set"] != doc["set"] or original["video"] != v \
                or original["signature"]["decodedFramesSha256"] != sig["decodedFramesSha256"]:
            problems.append(f"duplicateOf {doc['duplicateOf']} is missing or not the same media")
    return problems


def check_benchmark_record(path: Path, doc: dict, docs: dict, rep: Report) -> None:
    where = str(path.relative_to(ROOT)) if path.is_absolute() else str(path)
    try:
        problems = benchmark_record_problems(doc, docs)
    except (ArithmeticError, ValueError, KeyError, TypeError) as e:   # malformed input is a failure, not a crash
        problems = [f"malformed record: {type(e).__name__}: {e}"]
    for p in problems:
        rep.fail(where, p)
    if not problems:
        rep.ok("benchmark records")


def benchmark_record_problems(doc: dict, docs: dict) -> list[str]:
    truths = {d["id"]: d for d in docs.values() if d.get("kind") == "jovra.groundTruth"}
    problems = []
    ids = [clip["truthId"] for clip in doc["clips"]]
    repeated = sorted({i for i in ids if ids.count(i) > 1})
    if repeated:
        problems.append(f"clips repeat {', '.join(repeated)}: each clip counts once")
    capability = doc["capabilityId"]
    if capability is not None:
        gates = registry_gates(docs)
        if doc["estimator"]["role"] != "candidate":
            problems.append(f"a {doc['estimator']['role']} record cannot back {capability}; only a candidate can (ADR-0004)")
        if capability not in gates:
            problems.append(f"{capability} is not in the capability registry")
        elif gates[capability] is None:
            problems.append(f"{capability} has no research gate in the capability registry")
        elif doc["floor"] is not None and canon(doc["floor"]["metrics"]) != canon(gates[capability]["metrics"]):
            problems.append(f"the floor is not {capability}'s registry gate")
        binding = benchmark_bindings(docs).get(capability)
        if binding is None:
            problems.append(f"{capability} has no benchmark binding in {BINDINGS_PATH}")
        elif canon(doc["task"]) != canon(binding["task"]):
            problems.append(f"the task is not {capability}'s binding: {canon(doc['task'])} instead of {canon(binding['task'])}")
    for clip in doc["clips"]:
        truth = truths.get(clip["truthId"])
        if truth is None:
            problems.append(f"{clip['truthId']}: no committed ground truth")
            continue
        if (clip["seed"], clip["split"]) != (truth["seed"], truth["split"]):
            problems.append(f"{clip['truthId']}: seed/split differ from the ground truth")
        if clip["rendererSourceHash"] != truth["renderer"]["sourceHash"]:
            problems.append(f"{clip['truthId']}: rendererSourceHash is not the ground truth's renderer.sourceHash")
        if clip["decodedFramesSha256"] != truth["signature"]["decodedFramesSha256"]:
            problems.append(f"{clip['truthId']}: decodedFramesSha256 is not the ground truth's decoded-frame hash")
        if clip["truthEventsSha256"] != benchmark.truth_events_sha256(truth):
            problems.append(f"{clip['truthId']}: truthEventsSha256 does not match the committed events")
        if doc["mode"] == "gate" and truth["split"] != "heldOut":
            problems.append(f"{clip['truthId']}: a gating run used a {truth['split']} seed")
        if doc["estimator"]["role"] == "oracle" and clip["outputs"] != [e["time"] for e in truth.get("events", [])]:
            problems.append(f"{clip['truthId']}: oracle outputs are not the truth events")
        if doc["estimator"]["role"] == "null" and clip["outputs"]:
            problems.append(f"{clip['truthId']}: null estimator produced outputs")
    scorer = benchmark.SCORERS.get(doc["task"]["id"])
    if scorer is None:
        problems.append(f"no reference scorer for task {doc['task']['id']!r}")
    elif not problems:
        metrics = scorer(doc, truths)
        if capability is not None:
            metrics = benchmark.gate_metrics(metrics, benchmark_bindings(docs)[capability])
        if canon(metrics) != canon(doc["metrics"]):
            problems.append("metrics differ from the reference re-score: " + first_difference(metrics, doc["metrics"]))
        expected = benchmark.verdict(metrics, doc["floor"]) if doc["mode"] == "gate" else None
        if canon(expected) != canon(doc["verdict"]):
            problems.append("verdict differs from the floor applied to the re-scored metrics")
    return problems


BINDINGS_PATH = "spec/fixtures/media/benchmark-bindings.json"


def benchmark_bindings(docs: dict) -> dict[str, dict]:
    """capability id -> its benchmark binding, from the committed bindings document."""
    return {b["capabilityId"]: b for d in docs.values() if d.get("kind") == "jovra.benchmarkBindings"
            for b in d["bindings"]}


def check_bindings(path: Path, doc: dict, docs: dict, rep: Report) -> None:
    where = str(path.relative_to(ROOT)) if path.is_absolute() else str(path)
    try:
        problems = binding_problems(doc, docs)
    except (ArithmeticError, ValueError, KeyError, TypeError) as e:
        problems = [f"malformed bindings: {type(e).__name__}: {e}"]
    for p in problems:
        rep.fail(where, p)
    if not problems:
        rep.ok("benchmark bindings")


def binding_problems(doc: dict, docs: dict) -> list[str]:
    """Each binding names a gated capability, a task with a reference scorer of that version, and maps every gate
    metric exactly once from a metric that scorer emits, with the gate's unit."""
    problems = []
    gates = registry_gates(docs)
    ids = [b["capabilityId"] for b in doc["bindings"]]
    for cid in sorted({i for i in ids if ids.count(i) > 1}):
        problems.append(f"{cid} is bound more than once")
    for b in doc["bindings"]:
        cid, task = b["capabilityId"], b["task"]
        if gates.get(cid) is None:
            problems.append(f"{cid}: no research gate in the capability registry to bind")
            continue
        if task["id"] not in benchmark.SCORERS:
            problems.append(f"{cid}: no reference scorer for task {task['id']!r}")
            continue
        if task["version"] != benchmark.TASK_VERSIONS[task["id"]]:
            problems.append(f"{cid}: task {task['id']} is version {benchmark.TASK_VERSIONS[task['id']]}, not {task['version']}")
        if "tolerance" in task:
            benchmark.rt(task["tolerance"])
        emitted = dict(benchmark.TASK_METRICS[task["id"]])
        gate_units = {m["name"]: m.get("unit") for m in gates[cid]["metrics"]}
        task_names = [m["task"] for m in b["metrics"]]
        gate_names = [m["gate"] for m in b["metrics"]]
        if sorted(task_names) != sorted(emitted):
            problems.append(f"{cid}: maps task metrics {sorted(task_names)}, but {task['id']} emits {sorted(emitted)}")
        if sorted(gate_names) != sorted(gate_units):
            problems.append(f"{cid}: maps gate metrics {sorted(gate_names)}, but the gate has {sorted(gate_units)}")
        for m in b["metrics"]:
            if m["task"] in emitted and m["gate"] in gate_units and emitted[m["task"]] != gate_units[m["gate"]]:
                problems.append(f"{cid}: {m['task']!r} is in {emitted[m['task']]!r} but gate metric {m['gate']!r} is in {gate_units[m['gate']]!r}")
    return problems


def registry_gates(docs: dict) -> dict[str, dict | None]:
    """capability id -> its research gate (None without one), from the committed capability registry."""
    return {c["id"]: c["gate"] for d in docs.values() if d.get("kind") == "jovra.capabilityRegistry"
            for c in d["capabilities"]}


def candidate_on_gate(record: dict, docs: dict) -> dict:
    """A copy of ``record`` as a candidate run backing audio.hitDetection: that capability's registry gate, its
    binding's task, the metrics re-scored under the gate's names and the verdict recomputed: the shape a real
    capability record has."""
    doc = json.loads(canon(record))
    doc["estimator"] = {"id": "selfTest.candidate", "methodVersion": "0", "role": "candidate"}
    doc["capabilityId"] = "audio.hitDetection"
    gate = registry_gates(docs)["audio.hitDetection"]
    binding = benchmark_bindings(docs)["audio.hitDetection"]
    doc["task"] = json.loads(canon(binding["task"]))
    doc["floor"] = {"source": "spec/contracts/capability-registry.v1.json gate of audio.hitDetection",
                    "metrics": json.loads(canon(gate["metrics"]))}
    truths = {d["id"]: d for d in docs.values() if d.get("kind") == "jovra.groundTruth"}
    doc["metrics"] = benchmark.gate_metrics(benchmark.SCORERS[doc["task"]["id"]](doc, truths), binding)
    doc["verdict"] = benchmark.verdict(doc["metrics"], doc["floor"])
    return doc


SELF_TEST_RECORDS = SPEC / "fixtures" / "media" / "benchmark"


def truths_by_id(docs: dict) -> dict[str, dict]:
    return {d["id"]: d for d in docs.values() if d.get("kind") == "jovra.groundTruth"}


def media_self_tests(schemas: SchemaSet, docs: dict, rep: Report) -> None:
    """Known-bad media documents must fail and known-good ones pass (the new checks are not vacuous)."""
    truth = next((d for d in docs.values() if d.get("kind") == "jovra.groundTruth" and d["split"] == "heldOut"), None)
    # The committed harness self-test records only: a record elsewhere (spec/benchmarks) is under test, not a base.
    committed = [d for p, d in docs.items() if d.get("kind") == "jovra.benchmarkRecord" and SELF_TEST_RECORDS in p.parents]
    record = next((d for d in committed if d["mode"] == "gate"), None)
    if truth is None or record is None:
        rep.fail("media self-test", "needs a held-out ground truth and a gating benchmark record")
        return
    tuning = next(d for d in docs.values() if d.get("kind") == "jovra.groundTruth" and d["split"] == "tuning")
    schema_cases = []
    bad = json.loads(canon(truth)); bad["video"]["rotationDegrees"] = 45
    schema_cases.append(("ground-truth.schema.json", bad, False, "rotation that is not a right angle"))
    bad = json.loads(canon(truth)); bad["video"]["hdr"] = {"transfer": "hlg", "primaries": "bt2020", "matrix": "bt2020nc"}
    schema_cases.append(("ground-truth.schema.json", bad, False, "HDR on 8-bit H.264"))
    bad = json.loads(canon(truth)); bad["seed"] = None
    schema_cases.append(("ground-truth.schema.json", bad, False, "benchmark split without a seed"))
    bad = json.loads(canon(record)); bad["clips"][0]["split"] = "tuning"
    schema_cases.append(("benchmark-record.schema.json", bad, False, "gating run on a tuning seed"))
    bad = json.loads(canon(record)); bad["mode"] = "tuning"
    schema_cases.append(("benchmark-record.schema.json", bad, False, "tuning run carrying a verdict"))
    ok = json.loads(canon(record)); ok["mode"] = "tuning"; ok["verdict"] = None
    schema_cases.append(("benchmark-record.schema.json", ok, True, "tuning run without a verdict"))
    for role in ("oracle", "null"):
        bad = json.loads(canon(record)); bad["estimator"]["role"] = role; bad["capabilityId"] = "audio.hitDetection"
        schema_cases.append(("benchmark-record.schema.json", bad, False, f"a {role} record naming a capability"))
    oracle = next((d for d in committed if d["mode"] == "gate" and d["estimator"]["role"] == "oracle"), record)
    candidate = candidate_on_gate(oracle, docs)   # perfect outputs: the truth's own event times
    schema_cases.append(("benchmark-record.schema.json", candidate, True, "a candidate record naming a capability"))
    bad = json.loads(canon(record)); del bad["clips"][0]["decodedFramesSha256"]
    schema_cases.append(("benchmark-record.schema.json", bad, False, "a clip without its decoded-frame hash"))
    for schema, instance, must_pass, label in schema_cases:
        errors = schemas.validate(instance, schema)
        if (not errors) != must_pass:
            rep.fail("media self-test", f"{label}: expected {'pass' if must_pass else 'fail'}")
        else:
            rep.ok("media self-tests")
    check_cases = []
    bad = json.loads(canon(record)); bad["metrics"][1]["value"] = "1.0000"; bad["metrics"][1]["exact"] = {"n": 1, "d": 1}
    check_cases.append((bad, "a metric that the reference re-score disagrees with"))
    bad = json.loads(canon(record)); bad["verdict"]["passed"] = not bad["verdict"]["passed"]
    check_cases.append((bad, "a verdict that contradicts the floor"))
    bad = json.loads(canon(record)); bad["clips"][0]["truthId"] = tuning["id"]
    bad["clips"][0]["seed"], bad["clips"][0]["split"] = tuning["seed"], "heldOut"
    check_cases.append((bad, "a tuning clip relabelled heldOut"))
    bad = json.loads(canon(record)); bad["clips"] = bad["clips"] * 3
    bad["metrics"] = benchmark.SCORERS[bad["task"]["id"]](bad, {d["id"]: d for d in docs.values() if d.get("kind") == "jovra.groundTruth"})
    bad["verdict"] = benchmark.verdict(bad["metrics"], bad["floor"])
    check_cases.append((bad, "the same clip pooled three times (an inflated denominator)"))
    bad = json.loads(canon(oracle)); bad["capabilityId"] = "audio.hitDetection"
    check_cases.append((bad, "an oracle record naming a capability"))
    bad = json.loads(canon(candidate)); bad["floor"] = json.loads(canon(record["floor"]))
    bad["verdict"] = benchmark.verdict(bad["metrics"], bad["floor"])
    check_cases.append((bad, "a capability record gated by a self-declared floor instead of the registry gate"))
    bad = json.loads(canon(candidate)); bad["capabilityId"] = "scoring.manual"
    check_cases.append((bad, "a capability record for a capability without a gate"))
    bad = json.loads(canon(candidate)); bad["task"]["tolerance"] = {"value": 200, "timescale": 1000}
    bad["metrics"] = benchmark.gate_metrics(benchmark.SCORERS[bad["task"]["id"]](bad, truths_by_id(docs)),
                                            benchmark_bindings(docs)["audio.hitDetection"])
    bad["verdict"] = benchmark.verdict(bad["metrics"], bad["floor"])
    check_cases.append((bad, "a capability record with a tolerance other than its binding's"))
    bad = json.loads(canon(candidate)); bad["metrics"] = benchmark.SCORERS[bad["task"]["id"]](bad, truths_by_id(docs))
    bad["verdict"] = benchmark.verdict(bad["metrics"], bad["floor"])
    check_cases.append((bad, "a capability record whose metrics keep the task's names instead of the gate's"))
    bad = json.loads(canon(candidate)); bad["capabilityId"] = "camera.movedDetection"
    bad["floor"]["metrics"] = json.loads(canon(registry_gates(docs)["camera.movedDetection"]["metrics"]))
    bad["verdict"] = benchmark.verdict(bad["metrics"], bad["floor"])
    check_cases.append((bad, "a capability record for a gated capability without a binding"))
    bad = json.loads(canon(record)); bad["clips"][0]["decodedFramesSha256"] = "0" * 64
    check_cases.append((bad, "a clip whose decoded-frame hash is not its ground truth's"))
    bad = json.loads(canon(record)); bad["clips"][0]["rendererSourceHash"] = "0" * 64
    check_cases.append((bad, "a clip whose renderer source hash is not its ground truth's"))
    bad = json.loads(canon(record)); bad["task"]["tolerance"]["timescale"] = 0
    check_cases.append((bad, "a zero timescale (reported, not a crash)"))
    bad = json.loads(canon(record)); bad["floor"]["metrics"][0]["threshold"] = "1e-3"
    check_cases.append((bad, "a threshold that is not a plain decimal (reported, not a crash)"))
    for instance, label in check_cases:
        probe = Report(False)
        try:
            check_benchmark_record(Path("media self-test"), instance, docs, probe)
        except Exception as e:  # noqa: BLE001 - a crash is itself the failure under test
            rep.fail("media self-test", f"{label}: the record check crashed ({type(e).__name__}: {e})")
            continue
        if not probe.failures:
            rep.fail("media self-test", f"{label}: expected the record check to fail")
        else:
            rep.ok("media self-tests")
    probe = Report(False)
    check_benchmark_record(Path("media self-test"), candidate, docs, probe)
    if probe.failures:
        rep.fail("media self-test", "a candidate record on its capability's registry gate: expected the record check to pass, "
                 + "; ".join(probe.failures))
    else:
        rep.ok("media self-tests")
    if not candidate["verdict"]["passed"]:
        rep.fail("media self-test", "a perfect candidate (the truth's own event times) fails the real audio.hitDetection gate: "
                 + canon(candidate["verdict"]))
    else:
        rep.ok("media self-tests")
    bindings_doc = next((d for d in docs.values() if d.get("kind") == "jovra.benchmarkBindings"), None)
    if bindings_doc is None:
        rep.fail("media self-test", f"needs {BINDINGS_PATH}")
        return
    binding_cases = []
    bad = json.loads(canon(bindings_doc)); bad["bindings"][0]["metrics"].pop()
    binding_cases.append((bad, "a binding that leaves a gate metric unmapped"))
    bad = json.loads(canon(bindings_doc)); bad["bindings"][0]["metrics"][0]["task"] = "f1"
    binding_cases.append((bad, "a binding that maps a metric its task does not emit"))
    bad = json.loads(canon(bindings_doc)); bad["bindings"][0]["metrics"][0]["gate"] = "precision"
    binding_cases.append((bad, "a binding whose gate names are not the registry gate's"))
    bad = json.loads(canon(bindings_doc)); bad["bindings"][0]["capabilityId"] = "scoring.manual"
    binding_cases.append((bad, "a binding for a capability without a gate"))
    bad = json.loads(canon(bindings_doc)); bad["bindings"].append(json.loads(canon(bad["bindings"][0])))
    binding_cases.append((bad, "a capability bound twice"))
    bad = json.loads(canon(bindings_doc)); bad["bindings"][0]["task"]["tolerance"]["timescale"] = 0
    binding_cases.append((bad, "a zero tolerance timescale in a binding (reported, not a crash)"))
    for instance, label in binding_cases:
        probe = Report(False)
        try:
            check_bindings(Path("media self-test"), instance, docs, probe)
        except Exception as e:  # noqa: BLE001 - a crash is itself the failure under test
            rep.fail("media self-test", f"{label}: the bindings check crashed ({type(e).__name__}: {e})")
            continue
        if not probe.failures:
            rep.fail("media self-test", f"{label}: expected the bindings check to fail")
        else:
            rep.ok("media self-tests")
    truth_path = next(p for p, d in docs.items() if d is truth)
    truth_cases = []
    bad = json.loads(canon(truth)); bad["events"][0]["frame"] += 1
    truth_cases.append((bad, "an event on the wrong video frame"))
    bad = json.loads(canon(truth)); bad["video"]["duration"]["value"] += 1
    truth_cases.append((bad, "a duration that is not frameCount / frameRate"))
    bad = json.loads(canon(truth)); bad["video"]["displayWidth"], bad["video"]["displayHeight"] = 360, 640
    truth_cases.append((bad, "a display size that ignores the rotation"))
    bad = json.loads(canon(truth)); bad["video"]["duration"]["timescale"] = 0
    truth_cases.append((bad, "a zero duration timescale (reported, not a crash)"))
    bad = json.loads(canon(truth)); bad["video"]["frameRate"]["num"] = 0
    truth_cases.append((bad, "a zero frame rate (reported, not a crash)"))
    for instance, label in truth_cases:
        probe = Report(False)
        try:
            check_ground_truth(truth_path, instance, docs, probe)
        except Exception as e:  # noqa: BLE001 - a crash is itself the failure under test
            rep.fail("media self-test", f"{label}: the ground-truth check crashed ({type(e).__name__}: {e})")
            continue
        if not probe.failures:
            rep.fail("media self-test", f"{label}: expected the ground-truth check to fail")
        else:
            rep.ok("media self-tests")


def main() -> int:
    rep = Report("-v" in sys.argv)
    schemas = SchemaSet(SPEC / "schemas")
    for problem in schemas.check_all():
        rep.fail("schema", problem)
    rep.counts["schemas"] = len(schemas.files)
    kind_schema_checks(schemas, rep)
    schema_self_tests(schemas, rep)
    closed_object_self_tests(schemas, rep)
    docs = validate_instances(schemas, rep)
    extra_checks = conformance.discovered_checks()
    media_self_tests(schemas, docs, rep)
    for path, doc in docs.items():
        kind = doc["kind"]
        if kind in extra_checks:
            for problem in extra_checks[kind](path, doc, docs):
                rep.fail(str(path.relative_to(ROOT)), problem)
            rep.ok(f"{kind} checks")
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
        elif kind == "jovra.groundTruth":
            check_ground_truth(path, doc, docs, rep)
        elif kind == "jovra.benchmarkRecord":
            check_benchmark_record(path, doc, docs, rep)
        elif kind == "jovra.benchmarkBindings":
            check_bindings(path, doc, docs, rep)
    check_references(docs, rep)

    for line in rep.failures:
        print(line)
    print("---- spec validation summary ----")
    for key in sorted(rep.counts):
        print(f"{key:34} {rep.counts[key]}")
    if rep.failures:
        print(f"RESULT: FAIL ({len(rep.failures)} failure(s))")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
