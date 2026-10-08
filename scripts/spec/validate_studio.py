#!/usr/bin/env python3
"""Validate JOVRA Studio's contracts (spec/schemas/studio, spec/studio). Standard library only.

Separate from scripts/spec/validate.py (the core contracts), which it never imports or changes.

1. Every Studio schema uses only keywords the bundled checker implements, and every $ref resolves.
2. Drift checks: provenance enum = core common.schema.json; RenderJob states = the transition contract; film classes
   = the credit contract; profile text = design-reference/studio/brief/story-profiles.json.
3. Contracts (spec/studio/contracts) validate against their schemas.
4. Every record fixture validates against the schema its schemaVersion names, then passes its reference rule
   (EDL v2 validator, sync-map refit, job history replay, ledger totals, record rules).
5. Cross-record rules for the sample project (bundle.py) pass, and deliberate mutations of them fail.
6. Every invalid case is rejected by the expected layer: 'schema' cases fail the schema; 'reference' cases pass
   the schema and are rejected by the reference with the expected code.
7. Vectors: each vector file's `kind` is checked by the checker its cases module registers (a kind with no checker
   fails); both the reference outputs and the hand-derived assertions must hold.
8. Module pages (spec/studio/modules/*.md): every registered vector kind and schemaVersion appears in exactly one
   page's `kinds:` front matter, every page's kinds are registered, and spec/studio/README.md names no module.
9. Determinism: regenerating the fixtures gives exactly the files on disk, and the module index is current.

Schemas, reference rules and vector checkers are registered by the cases modules
(spec/reference/studio/cases/*_cases.py, discovered by file name), so a new contract adds files and never edits this
script. Exit status is non-zero on any failure.

Usage:  python3 scripts/spec/validate_studio.py [-v]
        python3 scripts/spec/validate_studio.py --list   # every registered kind: type, count, module and status
"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "spec"
SCHEMAS = SPEC / "schemas" / "studio"
STUDIO = SPEC / "studio"
FIX = STUDIO / "fixtures"
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(SPEC / "reference"))
sys.path.insert(0, str(SPEC / "reference" / "studio"))

import re  # noqa: E402

from jsonschema_subset import SchemaSet  # noqa: E402

from studio import bundle, edl, jobstate, records, syncfit  # noqa: E402
from studio import cases as studio_cases  # noqa: E402
from studio.core import Reject, apply_patch  # noqa: E402

MODULES = STUDIO / "modules"
MODULE_INDEX = MODULES / "README.md"
PAGE_KEYS = ("module", "reference", "cases", "kinds", "coverage", "swift", "kotlin")
PAGE_LISTS = ("reference", "cases", "kinds")
PAGE_ENUMS = {"coverage": ("covered", "not-covered"), "swift": ("pending", "consumed"), "kotlin": ("pending", "consumed")}


def ecma_pattern(pattern: str) -> str:
    r"""JSON Schema 2020-12 'pattern' is an ECMA-262 regex: without the multiline flag, '$' matches only at the very end
    of the input. Python's '$' also matches before a trailing newline, so 'c01\n' would pass '^...$'. Rewrite every
    unescaped '$' outside a character class as '\Z' (Python's end-of-input anchor)."""
    out, i, in_class = [], 0, False
    while i < len(pattern):
        ch = pattern[i]
        if ch == "\\":
            out.append(pattern[i:i + 2])
            i += 2
            continue
        if ch == "[" and not in_class:
            in_class = True
        elif ch == "]" and in_class:
            in_class = False
        out.append("\\Z" if ch == "$" and not in_class else ch)
        i += 1
    return "".join(out)


class StudioSchemaSet(SchemaSet):
    """The shared subset checker with ECMA-262 end anchors (scripts/spec/jsonschema_subset.py uses re.search, whose '$'
    accepts a trailing newline; that file belongs to the core gate, so Studio corrects the semantics here and the Swift
    and Kotlin ports must follow ECMA, not Python)."""

    def _pattern(self, pattern: str) -> re.Pattern:
        if pattern not in self._patterns:
            self._patterns[pattern] = re.compile(ecma_pattern(pattern))
        return self._patterns[pattern]


class Report:
    def __init__(self, verbose: bool):
        self.verbose = verbose
        self.failures: list[str] = []
        self.counts: dict[str, int] = {}

    def ok(self, what: str, n: int = 1) -> None:
        self.counts[what] = self.counts.get(what, 0) + n

    def fail(self, where: str, message: str) -> None:
        self.failures.append(f"FAIL {where}: {message}")

    def log(self, message: str) -> None:
        if self.verbose:
            print(message)


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class Ctx:
    """Loaded schemas, contracts and the sample project's records."""

    def __init__(self, registry: studio_cases.Registry):
        self.registry = registry
        self.schemas = StudioSchemaSet(SCHEMAS)
        self.profiles_doc = load(STUDIO / "contracts" / "story-profiles.v1.json")
        self.profiles = {p["id"]: p for p in self.profiles_doc["profiles"]}
        self.transitions = load(STUDIO / "contracts" / "render-job-transitions.v1.json")
        self.classes = load(STUDIO / "contracts" / "credit-classes.v1.json")
        self.machine = jobstate.Machine(self.transitions)
        self.records = {p.name[: -len(".json")]: load(p) for p in sorted((FIX / "records").glob("*.json"))}
        r = self.records
        self.bundle = {
            "lock": r["project-lock"], "manifest": r["source-manifest"], "syncMap": r["sync-map"],
            "keepers": r["keeper-catalog"], "brolls": r["broll-catalog"], "references": r["reference-catalog"],
            "plans": [d for d in r.values() if d["schemaVersion"] == "jovra.edit-plan/2"],
            "artifacts": [d for d in r.values() if d["schemaVersion"] == "jovra.delivered-artifact/1"],
            "jobs": {d["jobId"]: d for d in r.values() if d["schemaVersion"] == "jovra.render-job/1"},
            "reservations": {d["reservationId"]: d for d in r.values() if d["schemaVersion"] == "jovra.usage-reservation/1"},
            "quotes": {d["quoteId"]: d for d in r.values() if d["schemaVersion"] == "jovra.quote/1"},
            "briefs": [d for d in r.values() if d["schemaVersion"] == "jovra.story-brief/1"],
            "observations": [d for d in r.values() if d["schemaVersion"] == "jovra.observation/1"],
            "lessons": [d for d in r.values() if d["schemaVersion"] == "jovra.lesson/1"],
        }
        self.edl_context = bundle.edl_context(self.bundle)

    def fixture(self, rel: str):
        """A parsed file under spec/studio/fixtures."""
        return load(FIX / rel)

    def schema_for(self, version) -> str | None:
        return self.registry.schemas.get(version)

    def semantic(self, doc: dict):
        """The reference rule for one record, as its cases module registered it (raises Reject)."""
        rule = self.registry.rules.get(doc["schemaVersion"])
        if rule is None:
            raise Reject("noReferenceRule", f"no reference rule registered for {doc['schemaVersion']}")
        return rule(self, doc)


# ----- 1-3: schemas, drift, contracts --------------------------------------------------------------

def check_schemas(ctx: Ctx, rep: Report) -> None:
    for problem in ctx.schemas.check_all():
        rep.fail("schemas", problem)
    missing = set(ctx.registry.schemas.values()) - set(ctx.schemas.files)
    for name in sorted(missing):
        rep.fail("schemas", f"missing {name}")
    rep.ok("schemas checked", len(ctx.schemas.files))
    # the checker is not vacuous for these schemas
    if ctx.schemas._pattern("^[0-9a-f]{64}$").search("a" * 64 + "\n") or not ctx.schemas._pattern("^[0-9a-f]{64}$").search("a" * 64):
        rep.fail("schema self-test", "pattern anchors are not ECMA-262 ('$' must not accept a trailing newline)")
    else:
        rep.ok("schema self-tests")
    for label, doc, schema in (("empty EDL", {}, "edit-plan.schema.json"),
                               ("EDL with a command", {"schemaVersion": "jovra.edit-plan/2", "command": "x"}, "edit-plan.schema.json")):
        if not ctx.schemas.validate(doc, schema):
            rep.fail("schema self-test", f"{label} passed")
        else:
            rep.ok("schema self-tests")


def check_drift(ctx: Ctx, rep: Report) -> None:
    core = load(SPEC / "schemas" / "common.schema.json")["$defs"]["provenanceStatus"]["enum"]
    studio = ctx.schemas.files["studio-common.schema.json"]["$defs"]["provenanceStatus"]["enum"]
    if core != studio:
        rep.fail("drift", f"provenance enum {studio} != core {core}")
    states = ctx.schemas.files["render-job.schema.json"]["$defs"]["state"]["enum"]
    if states != ctx.transitions["states"]:
        rep.fail("drift", "RenderJob states differ from the transition contract")
    for key in ("terminal", "resumable", "reservationRequiredFrom", "budgetCheckedBefore", "pausableFrom",
                "retryableFrom", "terminalFailureFrom", "budgetExceededFrom"):
        if not set(ctx.transitions[key]) <= set(states):
            rep.fail("drift", f"transition contract {key} names unknown states")
    for frm, tos in ctx.transitions["forward"].items():
        if frm not in states or not set(tos) <= set(states):
            rep.fail("drift", f"forward[{frm}] names unknown states")
    resume = ctx.schemas.files["render-job.schema.json"]["$defs"]["resumeStage"]["enum"]
    union = set(ctx.transitions["pausableFrom"]) | set(ctx.transitions["retryableFrom"]) | set(ctx.transitions["budgetExceededFrom"])
    if set(resume) != union or len(resume) != len(union):
        rep.fail("drift", "render-job resumeStage enum differs from pausableFrom U retryableFrom U budgetExceededFrom")
    if union & set(ctx.transitions["terminal"]):
        rep.fail("drift", "a terminal state can be a resume stage")
    film = ctx.schemas.files["quote.schema.json"]["properties"]["filmClass"]["enum"]
    if film != [c["id"] for c in ctx.classes["classes"]]:
        rep.fail("drift", "quote film classes differ from the credit contract")
    design = load(ROOT / "design-reference" / "studio" / "brief" / "story-profiles.json")
    if design["defaults"] != ctx.profiles_doc["defaults"]:
        rep.fail("drift", "profile defaults differ from design-reference")
    for src in design["profiles"]:
        mine = ctx.profiles.get(src["id"])
        if mine is None or any(mine[k] != src[k] for k in src):
            rep.fail("drift", f"profile {src['id']} text differs from design-reference/studio/brief/story-profiles.json")
    rep.ok("drift checks")


def check_contracts(ctx: Ctx, rep: Report) -> None:
    for path in sorted((STUDIO / "contracts").glob("*.json")):
        doc = load(path)
        schema = ctx.schema_for(doc.get("schemaVersion"))
        errors = ctx.schemas.validate(doc, schema) if schema else [f"no schema registered for {doc.get('schemaVersion')!r}"]
        if errors:
            rep.fail(str(path.relative_to(ROOT)), "; ".join(errors[:5]))
            continue
        rep.ok("contracts valid")
    try:
        records.check_profile_catalog(ctx.profiles_doc)
        rep.ok("contracts valid (reference)")
    except Reject as exc:
        rep.fail("story-profiles.v1.json", str(exc))


# ----- 4-5: records and bundle --------------------------------------------------------------------

def check_records(ctx: Ctx, rep: Report) -> None:
    for name, doc in ctx.records.items():
        where = f"records/{name}.json"
        schema = ctx.schema_for(doc.get("schemaVersion"))
        if schema is None:
            rep.fail(where, f"no schema registered for {doc.get('schemaVersion')!r}")
            continue
        errors = ctx.schemas.validate(doc, schema)
        if errors:
            rep.fail(where, f"schema {schema}: " + "; ".join(errors[:5]))
            continue
        if not doc.get("sample", True):
            rep.fail(where, "every Studio fixture is fictional and must be labelled sample")
        try:
            result = ctx.semantic(doc)
        except Reject as exc:
            rep.fail(where, f"reference: {exc}")
            continue
        rep.log(f"ok {where} {result if isinstance(result, dict) and 'status' in result else ''}")
        rep.ok("records valid")


def check_bundle(ctx: Ctx, rep: Report) -> None:
    try:
        counts = bundle.check_all(ctx.bundle)
        rep.ok("cross-record checks")
        rep.log(f"bundle {counts}")
    except Reject as exc:
        rep.fail("bundle", str(exc))
        return

    def mutated(mutate):
        b = copy.deepcopy(ctx.bundle)
        mutate(b)
        return lambda: bundle.check_all(b)

    def plan(b, plan_id):
        return [p for p in b["plans"] if p["planId"] == plan_id][0]

    def unmapped_restart(b):
        # camera-2 restarted (a second recorded segment) but the sync map keeps only its first piece: the one piece
        # must never stand for the whole recording (the lock is re-pinned so only the sync rule can refuse it)
        src = b["manifest"]["sources"][1]
        seg1 = copy.deepcopy(src["segments"][0])
        seg1.update(segmentId="seg-1", index=1, reason="restart")
        src["segments"].append(seg1)
        b["lock"]["sourceManifest"]["sha256"] = bundle.canonical_sha256(b["manifest"])

    def topup_from_initial_quote(b):
        # one accepted quote funding two holds: the initial reserve and a top-up keyed by the same quote
        res = b["reservations"]["res-0002"]
        e0 = res["entries"][0]
        e0["credits"] = 2
        top = dict(e0, entryId="e-1b", key=e0["key"] + ":topup:" + res["initialQuoteId"])
        res["entries"].insert(1, top)

    def topup_leaves_initial_accepted(b):
        # a real top-up by a second quote, but the initial quote is still 'accepted' rather than superseded
        res = b["reservations"]["res-0002"]
        e0 = res["entries"][0]
        e0["credits"] = 2
        res["entries"].insert(1, dict(e0, entryId="e-1b", key=e0["key"] + ":topup:quote-test-02"))
        b["quotes"]["quote-test-02"] = dict(copy.deepcopy(b["quotes"]["quote-test-01"]), quoteId="quote-test-02")
        res["quoteId"] = "quote-test-02"
        b["jobs"]["job-film-01"]["quoteId"] = "quote-test-02"

    tests = [
        ("restart-segment-unmapped", "unmappedSegment", unmapped_restart),
        ("model-film-from-rules-quote", "plannerMismatch",
         lambda b: b["artifacts"][0]["bindings"]["planner"].update(kind="model", modelId="claude-opus-5-5")),
        ("topup-from-initial-quote", "moneyMismatch", topup_from_initial_quote),
        ("topup-leaves-initial-quote-accepted", "moneyMismatch", topup_leaves_initial_accepted),
        ("coverage-rate-tampered", "coverageMismatch",
         lambda b: plan(b, "coach-cut-serve")["sources"][1]["coverage"][0]["rate"].update(num=1_000_000_000)),
        ("sync-not-reviewed", "unreviewedSync",
         lambda b: b["syncMap"]["sources"][1]["pieces"][0].update(state="needs-review")),
        ("film-bound-to-missing-plan", "unknownPlan",
         lambda b: b["artifacts"][0]["bindings"].update(editPlanSha256="0" * 64)),
        ("lock-manifest-hash", "lockMismatch", lambda b: b["lock"]["sourceManifest"].update(sha256="1" * 64)),
        ("contact-unprotected", "contactUnprotected",
         lambda b: plan(b, "court-memories-storyboard")["segments"][2].update(protectedFrames=[])),
        ("clean-alternate-drift", "cleanAlternateMismatch",
         lambda b: plan(b, "rally-pulse-portrait-clean")["segments"][0].update(framing={"mode": "fill"})),
        ("reservation-of-other-plan", "moneyMismatch",
         lambda b: b["reservations"]["res-0002"]["idempotencyKey"].update(planRevision=1)),
        ("cue-provenance-laundered", "provenanceMismatch",
         lambda b: [l for l in b["lessons"] if l["lessonId"] == "lesson-1007"][0]["cues"][1].update(provenance="reviewed")),
        ("job-lists-ghost-artifact", "unknownArtifact",
         lambda b: b["jobs"]["job-film-01"].update(deliveredArtifactIds=["film-court-memories", "ghost-film"])),
        ("ready-film-unverified", "unverifiedReady",
         lambda b: b["artifacts"][0]["verification"].update(status="pending")),
        ("quote-bound-to-other-output", "moneyMismatch",
         lambda b: b["quotes"]["quote-test-01"].update(outputSpecSha256="c" * 64)),
        ("catalog-cue-laundered", "provenanceMismatch",
         lambda b: [r for r in b["references"]["references"] if r["refId"] == "cue-04"][0].update(provenance="reviewed")),
        ("consent-of-unknown-participant", "unknownParticipant",
         lambda b: b["references"]["consents"][0].update(participantId="nobody")),
        ("reservation-entry-of-other-job", "moneyMismatch",
         lambda b: b["reservations"]["res-0002"]["entries"][1].update(key="consume:job-queue-38:normalizing:1")),
        ("brief-overlay-unresolved", "untrustedReference",
         lambda b: [x for x in b["briefs"] if x["briefId"] == "brief-court-memories"][0]["beats"][2]["overlays"][0].update(refId="6-4")),
    ]
    for label, code, mutate in tests:
        try:
            bundle.expect_reject(mutated(mutate), code)
            rep.ok("cross-record mutations rejected")
        except Reject as exc:
            rep.fail(f"bundle mutation {label}", str(exc))


# ----- 6: invalid cases ---------------------------------------------------------------------------

def check_invalid(ctx: Ctx, rep: Report) -> None:
    for path in sorted((FIX / "invalid").glob("*.json")):
        where = str(path.relative_to(ROOT))
        doc = load(path)
        errors = ctx.schemas.validate(doc, "fixture.schema.json")
        if errors:
            rep.fail(where, "; ".join(errors[:3]))
            continue
        base = load(FIX / doc["base"])
        schema = ctx.schema_for(base["schemaVersion"])
        if schema is None:
            rep.fail(where, f"no schema registered for the base's {base['schemaVersion']!r}")
            continue
        for case in doc["cases"]:
            label = f"{where}#{case['id']}"
            try:
                bad = apply_patch(base, case["patch"])
            except (KeyError, IndexError, ValueError) as exc:
                rep.fail(label, f"patch does not apply: {exc}")
                continue
            schema_errors = ctx.schemas.validate(bad, schema)
            if case["expect"]["layer"] == "schema":
                if not schema_errors:
                    rep.fail(label, "expected a schema rejection; the schema accepted it")
                else:
                    rep.ok("invalid cases rejected (schema)")
                continue
            if schema_errors:
                rep.fail(label, "reference case must pass the schema first: " + "; ".join(schema_errors[:2]))
                continue
            try:
                ctx.semantic(bad)
            except Reject as exc:
                if exc.code != case["expect"]["code"]:
                    rep.fail(label, f"rejected with {exc.code} ({exc.message}), expected {case['expect']['code']}")
                else:
                    rep.ok("invalid cases rejected (reference)")
                continue
            rep.fail(label, f"accepted; expected {case['expect']['code']}")


# ----- 7: vectors ---------------------------------------------------------------------------------

def check_vectors(ctx: Ctx, rep: Report) -> None:
    for path in sorted((FIX / "vectors").glob("*.json")):
        doc = load(path)
        errors = ctx.schemas.validate(doc, "fixture.schema.json")
        if errors:
            rep.fail(str(path.relative_to(ROOT)), "; ".join(errors[:3]))
            continue
        checker = ctx.registry.checkers.get(doc["kind"])
        if checker is None:
            rep.fail(str(path.relative_to(ROOT)), f"no checker for kind {doc['kind']} (register one in the VECTOR_CHECKERS "
                                                  "of the cases module that writes it)")
            continue
        for case in doc["cases"]:
            where = f"{path.relative_to(ROOT)}#{case['id']}"
            try:
                checker(ctx, case, rep, where)
            except Reject as exc:
                rep.fail(where, str(exc))


# ----- 8: module pages ----------------------------------------------------------------------------

def parse_page(path: Path) -> dict:
    """The front matter of a module page: the first lines between two '---' lines, each 'key: value' with value a
    word or a flow list '[a, b]'. Exactly the keys in PAGE_KEYS. Raises ValueError."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        raise ValueError("no front matter (the page must start with a '---' line and close it with another)")
    meta: dict = {}
    for line in lines[1:lines.index("---", 1)]:
        key, sep, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if not sep or key in meta:
            raise ValueError(f"bad front matter line {line!r}")
        if key in PAGE_LISTS:
            if not (value.startswith("[") and value.endswith("]")):
                raise ValueError(f"{key} must be a flow list like [a, b]")
            meta[key] = [item.strip() for item in value[1:-1].split(",") if item.strip()]
        else:
            meta[key] = value
    if sorted(meta) != sorted(PAGE_KEYS):
        raise ValueError(f"front matter keys {sorted(meta)}, expected {sorted(PAGE_KEYS)}")
    if meta["module"] != path.stem:
        raise ValueError(f"module {meta['module']!r} differs from the file name")
    for key, allowed in PAGE_ENUMS.items():
        if meta[key] not in allowed:
            raise ValueError(f"{key}: {meta[key]!r} is not one of {', '.join(allowed)}")
    for key in ("reference", "cases"):
        for rel in meta[key]:
            if not (ROOT / rel).is_file():
                raise ValueError(f"{key} names {rel}, which does not exist")
    if meta["coverage"] == "covered" and not meta["kinds"]:
        raise ValueError("a covered module owns at least one kind")
    if meta["coverage"] == "not-covered" and meta["kinds"]:
        raise ValueError("a not-covered module has no fixtures yet, so it owns no kind")
    return meta


def load_pages(rep: Report | None = None) -> dict:
    """Module name -> parsed front matter, for every page under spec/studio/modules (the index excluded)."""
    pages = {}
    for path in sorted(MODULES.glob("*.md")):
        if path == MODULE_INDEX:
            continue
        try:
            pages[path.stem] = parse_page(path)
        except ValueError as exc:
            if rep is not None:
                rep.fail(str(path.relative_to(ROOT)), str(exc))
    return pages


def vector_cases_by_kind() -> dict:
    counts: dict = {}
    for path in sorted((FIX / "vectors").glob("*.json")):
        doc = load(path)
        counts[doc.get("kind")] = counts.get(doc.get("kind"), 0) + len(doc.get("cases", []))
    return counts


def check_modules(ctx: Ctx, rep: Report, pages: dict) -> None:
    registry = ctx.registry
    for problem in registry.problems:
        rep.fail("cases modules", problem)
    claimed: dict = {}
    for name, meta in pages.items():
        for kind in meta["kinds"]:
            if kind in claimed:
                rep.fail("module pages", f"kind {kind} is claimed by {claimed[kind]}.md and {name}.md")
            claimed[kind] = name
            if kind not in registry.owner:
                rep.fail(f"spec/studio/modules/{name}.md", f"names kind {kind}, which no cases module registers")
        rep.ok("module pages checked")
    on_disk = vector_cases_by_kind()
    for kind in registry.kinds():
        page = claimed.get(kind)
        if page is None:
            rep.fail("module pages", f"kind {kind} has no module page (add it to the kinds: of "
                                     "spec/studio/modules/<module>.md)")
            continue
        if registry.owner[kind] not in pages[page]["cases"]:
            rep.fail(f"spec/studio/modules/{page}.md", f"kind {kind} is registered by {registry.owner[kind]}, "
                                                       "which the page's cases: does not list")
            continue
        if kind in registry.checkers and kind not in on_disk:
            rep.fail("module pages", f"kind {kind} has a checker but no vector file")
            continue
        rep.ok("registered kinds with a module page")
    check_readme(rep, pages)


def readme_patterns(name: str, meta: dict) -> list:
    """What would make a README line a per-module line: the page path, or a file name (or `stem.attribute`) of the
    module's reference or cases files."""
    patterns = [re.escape(f"modules/{name}.md")]
    for rel in meta["reference"] + meta["cases"]:
        stem = Path(rel).stem
        patterns += [rf"\b{re.escape(Path(rel).name)}\b", rf"\b{re.escape(stem)}\.[A-Za-z_]"]
    return [re.compile(p) for p in patterns]


def check_readme(rep: Report, pages: dict) -> None:
    readme = STUDIO / "README.md"
    text = readme.read_text(encoding="utf-8").splitlines()
    if not any("modules/README.md" in line for line in text):
        rep.fail("spec/studio/README.md", "does not link the generated module index modules/README.md")
    clean = True
    for name, meta in pages.items():
        for number, line in enumerate(text, 1):
            if any(p.search(line) for p in readme_patterns(name, meta)):
                rep.fail("spec/studio/README.md", f"names module {name} on line {number}; per-module text belongs on "
                                                  f"spec/studio/modules/{name}.md")
                clean = False
    if clean:
        rep.ok("README without per-module lines")


# ----- 8: determinism -----------------------------------------------------------------------------

def check_determinism(rep: Report) -> None:
    import generate_studio_fixtures as gen
    try:
        expected = gen.build()
    except gen.DeclarationError as exc:
        rep.fail("determinism", str(exc))
        return
    on_disk = {p.relative_to(FIX).as_posix(): load(p) for p in FIX.rglob("*.json")}
    for rel in sorted(set(expected) - set(on_disk)):
        rep.fail("determinism", f"generated file missing: {rel}; run spec/reference/studio/generate_studio_fixtures.py")
    for rel in sorted(set(on_disk) - set(expected)):
        rep.fail("determinism", f"file not written by any cases module: {rel}")
    for rel, doc in expected.items():
        if rel in on_disk and json.loads(json.dumps(doc)) != on_disk[rel]:
            rep.fail("determinism", f"{rel} is stale; run spec/reference/studio/generate_studio_fixtures.py")
    if gen.profile_catalog() != load(STUDIO / "contracts" / "story-profiles.v1.json"):
        rep.fail("determinism", "story-profiles.v1.json is stale")
    if not MODULE_INDEX.is_file() or MODULE_INDEX.read_text(encoding="utf-8") != gen.module_index():
        rep.fail("determinism", "spec/studio/modules/README.md is stale; run "
                                "spec/reference/studio/generate_studio_fixtures.py")
    rep.ok("generated files current", len(expected) + 2)


def check_context_required(ctx: Ctx, rep: Report) -> None:
    """edl.validate refuses to run on a plan alone or with a partial context (no self-declared coverage, provenance,
    consent or rights is ever accepted)."""
    plan = ctx.records["edit-plan.coach-cut-serve"]
    for label, context in (("no context", None), ("empty context", {}),
                           ("context without references", {k: v for k, v in ctx.edl_context.items() if k != "references"})):
        try:
            edl.validate(plan, ctx.profiles, context)
            rep.fail("edl context", f"{label}: accepted")
        except Reject as exc:
            if exc.code == "contextMissing":
                rep.ok("context-required self-tests")
            else:
                rep.fail("edl context", f"{label}: {exc.code}, expected contextMissing")
    # type confusion the schema also catches: the reference must refuse it on its own (Swift/Kotlin ports mirror it)
    bad = copy.deepcopy(ctx.records["edit-plan.court-memories-storyboard"])
    bad["segments"][1]["speed"] = {"num": True, "den": 1}
    try:
        edl.validate(bad, ctx.profiles, ctx.edl_context)
        rep.fail("edl type confusion", "speed {num: true} accepted")
    except Reject as exc:
        if exc.code == "badSpeed":
            rep.ok("context-required self-tests")
        else:
            rep.fail("edl type confusion", f"{exc.code}, expected badSpeed")


def check_hint_states(ctx: Ctx, rep: Report) -> None:
    """from-hints is reachable at the record layer, and only with the hint the SourceManifest gives: a camera piece
    with no anchors, and a restarted segment of the reference device placed from its own capture journal."""
    manifest = copy.deepcopy(ctx.records["source-manifest"])
    base = ctx.records["sync-map"]
    hour = base["sources"][0]["pieces"][0]["sourceDurationUs"]
    restart_us = hour + 50_000_000
    cam1 = manifest["sources"][0]
    first = cam1["segments"][0]
    cam1["segments"].append(dict(first, segmentId="seg-1", index=1, reason="restart", durationUs=600_000_000,
                                 fileZeroHostNs=first["fileZeroHostNs"] + restart_us * 1000))

    def doc_with(offset):
        d = copy.deepcopy(base)
        t = {"offsetUs": offset, "rate": {"num": 1_000_000_000, "den": 1_000_000_000}}
        d["sources"][0]["pieces"].append({
            "segmentId": "seg-1", "sourceDurationUs": 600_000_000,
            "matchCoverage": {"startUs": syncfit.map_us(t, 0), "endUs": syncfit.map_us(t, 600_000_000)},
            "transform": t, "fit": None, "anchors": [], "state": "from-hints", "reasons": [], "checkpoints": [],
            "reviewedAt": None})
        d["sources"][0]["gaps"] = [{"match": {"startUs": hour, "endUs": syncfit.map_us(t, 0)}, "reason": "restart"}]
        return d

    def no_anchor_camera3(offset):
        d = copy.deepcopy(base)
        t = {"offsetUs": offset, "rate": {"num": 1_000_000_000, "den": 1_000_000_000}}
        piece = d["sources"][2]["pieces"][0]
        piece.update(anchors=[], fit=None, transform=t, state="from-hints", reasons=["no anchors; capture hint only"],
                     matchCoverage={"startUs": syncfit.map_us(t, 0), "endUs": syncfit.map_us(t, piece["sourceDurationUs"])})
        return d

    hints = bundle.capture_hints(manifest, base)
    tests = [
        ("reference restart from its journal", doc_with(restart_us), hints, None),
        ("reference restart, offset not the journal's", doc_with(restart_us + 1000), hints, "badReference"),
        ("camera without anchors placed from its hint", no_anchor_camera3(hints["camera-3"]["seg-0"]), hints, None),
        ("hint-only piece without the manifest hints", no_anchor_camera3(hints["camera-3"]["seg-0"]), {},
         "syncFitMismatch"),
    ]
    for label, doc, h, code in tests:
        errors = ctx.schemas.validate(doc, "sync-map.schema.json")
        if errors:
            rep.fail(f"hint self-test {label}", "schema: " + "; ".join(errors[:2]))
            continue
        try:
            records.check_sync_map(doc, hints=h)
            got = None
        except Reject as exc:
            got = exc.code
        if got != code:
            rep.fail(f"hint self-test {label}", f"got {got}, expected {code}")
        else:
            rep.ok("hint self-tests")


def list_kinds(ctx: Ctx, rep: Report, pages: dict) -> None:
    """--list: every registered kind with its type, count, invalid cases, module page and statuses, then every page
    that owns no kind (a not-covered module)."""
    page_of = {kind: name for name, meta in pages.items() for kind in meta["kinds"]}
    vectors = vector_cases_by_kind()
    records_by_version: dict = {}
    invalid_by_version: dict = {}
    for path in sorted(FIX.rglob("*.json")) + sorted((STUDIO / "contracts").glob("*.json")):
        doc = load(path)
        v = doc.get("schemaVersion")
        records_by_version[v] = records_by_version.get(v, 0) + 1
        if v == "jovra.studio-fixture.invalid-cases/1":
            base = load(FIX / doc["base"])["schemaVersion"]
            invalid_by_version[base] = invalid_by_version.get(base, 0) + len(doc["cases"])
    rows = [("kind", "type", "count", "invalid", "module", "coverage", "swift", "kotlin")]
    for kind in ctx.registry.kinds():
        meta = pages.get(page_of.get(kind), {})
        status = (page_of.get(kind, "(none)"), meta.get("coverage", "-"), meta.get("swift", "-"), meta.get("kotlin", "-"))
        if kind in ctx.registry.checkers:
            rows.append((kind, "vector", str(vectors.get(kind, 0)), "-", *status))
        else:
            rows.append((kind, "schema", str(records_by_version.get(kind, 0)), str(invalid_by_version.get(kind, 0)),
                         *status))
    for name, meta in pages.items():
        if not meta["kinds"]:
            rows.append((name, "page", "-", "-", name, meta["coverage"], meta["swift"], meta["kotlin"]))
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    for r in rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(r, widths)).rstrip())


def main() -> int:
    args = sys.argv[1:]
    rep = Report("-v" in args)
    try:
        registry = studio_cases.Registry(studio_cases.discover())
        ctx = Ctx(registry)
    except (OSError, KeyError, ValueError, ImportError) as exc:
        print(f"FAIL loading Studio contracts: {exc}")
        return 1
    pages = load_pages(rep)
    if "--list" in args:
        check_modules(ctx, rep, pages)
        list_kinds(ctx, rep, pages)
        for line in rep.failures:
            print(line)
        return 1 if rep.failures else 0
    check_schemas(ctx, rep)
    check_drift(ctx, rep)
    check_contracts(ctx, rep)
    check_records(ctx, rep)
    check_bundle(ctx, rep)
    check_invalid(ctx, rep)
    check_vectors(ctx, rep)
    check_context_required(ctx, rep)
    check_hint_states(ctx, rep)
    check_modules(ctx, rep, pages)
    check_determinism(rep)
    for line in rep.failures:
        print(line)
    width = max(len(k) for k in rep.counts) if rep.counts else 0
    for key, value in rep.counts.items():
        print(f"{key:<{width}}  {value}")
    print("RESULT:", "FAIL" if rep.failures else "PASS")
    return 1 if rep.failures else 0


if __name__ == "__main__":
    sys.exit(main())
