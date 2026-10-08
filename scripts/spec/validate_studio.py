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
7. Vectors: sync fits, sound delays, job transitions, ledger sequences, quote credits and the implementation-states
   sample truth; both the reference outputs and the hand-derived assertions must hold.
8. Determinism: regenerating the fixtures gives exactly the files on disk.

Exit status is non-zero on any failure.  Usage:  python3 scripts/spec/validate_studio.py [-v]
"""

from __future__ import annotations

import copy
import json
import sys
from fractions import Fraction
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

from studio import bundle, edl, jobstate, ledger, records, syncfit  # noqa: E402
from studio.core import Reject, apply_patch, delta_pp_display, pct, round_half_up  # noqa: E402

SCHEMA_BY_VERSION = {
    "jovra.project-lock/1": "project-lock.schema.json",
    "jovra.source-manifest/1": "source-manifest.schema.json",
    "jovra.sync-map/1": "sync-map.schema.json",
    "jovra.observation/1": "observation.schema.json",
    "jovra.keeper-catalog/1": "keeper-catalog.schema.json",
    "jovra.broll-catalog/1": "broll-catalog.schema.json",
    "jovra.story-profile-catalog/1": "story-profile.schema.json",
    "jovra.story-brief/1": "story-brief.schema.json",
    "jovra.edit-plan/2": "edit-plan.schema.json",
    "jovra.render-job/1": "render-job.schema.json",
    "jovra.usage-reservation/1": "usage-reservation.schema.json",
    "jovra.quote/1": "quote.schema.json",
    "jovra.delivered-artifact/1": "delivered-artifact.schema.json",
    "jovra.lesson/1": "lesson.schema.json",
    "jovra.camera-invite/1": "camera-invite.schema.json",
    "jovra.storage-providers/1": "storage-provider-capability.schema.json",
    "jovra.reference-catalog/1": "reference-catalog.schema.json",
    "jovra.render-job-transitions/1": "contracts.schema.json",
    "jovra.credit-classes/1": "contracts.schema.json",
    "jovra.studio-fixture.invalid-cases/1": "fixture.schema.json",
    "jovra.studio-fixture.vectors/1": "fixture.schema.json",
}


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

    def __init__(self):
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

    def semantic(self, doc: dict):
        """The reference rule for one record (raises Reject)."""
        v = doc["schemaVersion"]
        if v == "jovra.edit-plan/2":
            return edl.validate(doc, self.profiles, self.edl_context)
        if v == "jovra.sync-map/1":
            # capture hints come from the stored SourceManifest, so a from-hints piece is checked, never trusted
            return records.check_sync_map(doc, hints=bundle.capture_hints(self.bundle["manifest"], doc))
        if v == "jovra.render-job/1":
            # resolved against the delivered artifacts: a non-empty id list is not a verified film
            return self.machine.replay(doc, verified_artifact=bundle.verified_artifact_for(doc, self.bundle["artifacts"]))
        if v == "jovra.usage-reservation/1":
            return ledger.check_reservation_record(doc)
        if v == "jovra.quote/1":
            return records.check_quote(doc, self.classes)
        if v == "jovra.story-brief/1":
            return records.check_story_brief(doc, self.profiles)
        rule = {
            "jovra.project-lock/1": records.check_project_lock,
            "jovra.source-manifest/1": records.check_source_manifest,
            "jovra.observation/1": records.check_observation,
            "jovra.keeper-catalog/1": records.check_keeper_catalog,
            "jovra.broll-catalog/1": records.check_broll_catalog,
            "jovra.delivered-artifact/1": records.check_artifact,
            "jovra.lesson/1": records.check_lesson,
            "jovra.camera-invite/1": records.check_camera_invites,
            "jovra.storage-providers/1": records.check_storage_providers,
            "jovra.reference-catalog/1": records.check_reference_catalog,
        }[v]
        return rule(doc)


# ----- 1-3: schemas, drift, contracts --------------------------------------------------------------

def check_schemas(ctx: Ctx, rep: Report) -> None:
    for problem in ctx.schemas.check_all():
        rep.fail("schemas", problem)
    missing = set(SCHEMA_BY_VERSION.values()) - set(ctx.schemas.files)
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
        schema = SCHEMA_BY_VERSION.get(doc.get("schemaVersion"))
        errors = ctx.schemas.validate(doc, schema) if schema else [f"unknown schemaVersion {doc.get('schemaVersion')!r}"]
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
        schema = SCHEMA_BY_VERSION.get(doc.get("schemaVersion"))
        if schema is None:
            rep.fail(where, f"unknown schemaVersion {doc.get('schemaVersion')!r}")
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

    tests = [
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
        schema = SCHEMA_BY_VERSION[base["schemaVersion"]]
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

def within(value, bounds) -> bool:
    return bounds[0] <= value <= bounds[1]


def check_sync_vector(case, rep, where) -> None:
    inp = case["input"]
    got = syncfit.fit_device(inp["pieces"], source_position=inp["sourcePosition"],
                             reference_position=inp["referencePosition"], c_mm_per_s=inp["mmPerSecond"],
                             output_fps=inp["outputFps"], hints=inp["hints"])
    if got != case["expect"]:
        rep.fail(where, "fitter output differs from the stored expectation")
        return
    a = case["assert"]
    fitted = [p for p in got if p["fit"] is not None]
    problems = []
    if "state" in a and [p["state"] for p in got] != a["state"]:
        problems.append(f"states {[p['state'] for p in got]}")
    for p, bounds in zip(got, a.get("offsetUsWithin", [])):
        if p["transform"] is None or not within(p["transform"]["offsetUs"], bounds):
            problems.append(f"offset {p['transform']} outside {bounds}")
    if "driftPpbWithin" in a and not all(within(p["fit"]["driftPpb"], a["driftPpbWithin"]) for p in fitted):
        problems.append("drift outside bounds")
    if "driftMsPerMinRounded" in a and round_half_up(syncfit.drift_ms_per_min(got[0]["transform"])) != a["driftMsPerMinRounded"]:
        problems.append("drift ms/min")
    if "residualMaxUsAtMost" in a and max(p["fit"]["residualMaxUs"] for p in fitted) > a["residualMaxUsAtMost"]:
        problems.append("residual too large")
    if "residualMaxUsAtLeast" in a and max(p["fit"]["residualMaxUs"] for p in fitted) < a["residualMaxUsAtLeast"]:
        problems.append("residual unexpectedly small (bias not visible)")
    if "uncorrectedAudio" in a and any(p["fit"]["uncorrectedAudio"] != a["uncorrectedAudio"] for p in fitted):
        problems.append("uncorrectedAudio flag")
    if a.get("sharedRate") and len({json.dumps(p["transform"]["rate"]) for p in fitted}) != 1:
        problems.append("pieces of one device must share one rate")
    if "nOutliers" in a and sum(p["fit"]["nOutliers"] for p in fitted) != a["nOutliers"]:
        problems.append("outlier count")
    if "reasonsInclude" in a and not any(a["reasonsInclude"] in r for p in got for r in p["reasons"]):
        problems.append("missing review reason")
    if "reviewable" in a:
        # can a person mark the first piece reviewed after confirming start, middle and end?
        try:
            syncfit.check_review_state("reviewed", got[0]["state"], ["start", "middle", "end"], got[0]["fit"])
            reviewable = True
        except Reject:
            reviewable = False
        if reviewable != a["reviewable"]:
            problems.append(f"reviewable is {reviewable}")
    if problems:
        rep.fail(where, "hand assertions: " + ", ".join(problems))
    else:
        rep.ok("sync-fit vectors")


def check_sound_vector(case, rep, where) -> None:
    tol = Fraction(case["assert"]["toleranceMs"])
    if "temperatureC" in case:
        c = syncfit.speed_of_sound_mm_per_s(case["temperatureC"])
        ms = Fraction(23_770 * 1000, c)
        ok = c == case["expectMmPerSecond"] and abs(ms - Fraction(case["assert"]["docMsOver23770mm"])) <= tol
    else:
        got = syncfit.sound_delay_us(case["event"], case["mic"], case["mmPerSecond"])
        if "otherMic" in case:
            got -= syncfit.sound_delay_us(case["event"], case["otherMic"], case["mmPerSecond"])
        ok = got == case["expectUs"] and abs(Fraction(got, 1000) - Fraction(case["assert"]["docTableMs"])) <= tol
    if ok:
        rep.ok("sound-delay vectors")
    else:
        rep.fail(where, "differs from the reference or from the research table")


def check_sample_truth(ctx: Ctx, case, rep, where) -> None:
    kind = case["kind"]
    rec = load(FIX / case["record"]) if "record" in case else None
    ok = True
    if kind == "sync":
        t = [s for s in rec["sources"] if s["sourceId"] == case["sourceId"]][0]["pieces"][0]["transform"]
        ok = (round_half_up(Fraction(t["offsetUs"], 1000)) == case["offsetMs"]
              and round_half_up(syncfit.drift_ms_per_min(t)) == case["driftMsPerMin"]
              and round_half_up(Fraction(t["rate"]["num"] - t["rate"]["den"], 1000)) == case["driftPpm"])
    elif kind == "progress":
        b, a = case["before"], case["after"]
        cmp = rec["comparisons"][0]
        ok = (pct(*b) == case["beforePct"] and pct(*a) == case["afterPct"]
              and delta_pp_display(pct(*b), pct(*a)) == case["delta"] == cmp["display"]["delta"]
              and [cmp["before"]["numerator"], cmp["before"]["denominator"]] == b
              and [cmp["after"]["numerator"], cmp["after"]["denominator"]] == a)
    elif kind == "chapters":
        fps = Fraction(rec["media"]["fps"]["num"], rec["media"]["fps"]["den"])
        secs = [Fraction(c["endFrame"] - c["startFrame"]) / fps for c in rec["chapters"]]
        total = sum(case["chapterSeconds"])
        ok = (secs == case["chapterSeconds"] and total == case["totalSeconds"]
              and f"{total // 60:02d}:{total % 60:02d}" == case["display"]
              and Fraction(rec["media"]["durationFrames"]) / fps == total
              and rec["media"]["height"] == case["height"] and rec["media"]["sizeBytes"] == case["sizeBytes"])
    elif kind == "window":
        seg = [s for s in rec["segments"] if s["id"] == case["segmentId"]][0]
        src = [s for s in rec["sources"] if s["id"] == seg["sourceId"]][0]["proxy"]["fps"]
        out = rec["output"]["fps"]

        def ms(frames, fps):
            return Fraction(frames * 1000 * fps["den"], fps["num"])
        ok = (ms(seg["sourceInFrame"], src) == case["sourceStartMs"] and ms(seg["sourceOutFrame"], src) == case["sourceEndMs"]
              and ms(seg["outputInFrame"], out) == case["outputStartMs"] and ms(seg["outputOutFrame"], out) == case["outputEndMs"]
              and case["sourceEndMs"] - case["sourceStartMs"] == case["durationMs"]
              == case["outputEndMs"] - case["outputStartMs"])
    elif kind == "import":
        per = case["megabitsPerSecond"] * 1_000_000 * case["minutes"] * 60 // 8
        match = [s for s in rec["sources"] if s["role"] == "match"]
        ok = (per == case["perSourceBytes"] and per * case["sources"] == case["totalBytes"]
              and len(match) == case["sources"] and sum(s["original"]["sizeBytes"] for s in match) == case["totalBytes"])
    elif kind == "upload":
        secs = Fraction(case["bytes"] * 8, case["megabitsPerSecond"] * 1_000_000)
        ok = secs == case["seconds"] and secs / 60 == case["minutes"]
    elif kind == "storage":
        usd = Fraction(case["gigabytes"]) * case["days"] / 30 * Fraction(case["usdPerGbMonth"])
        ok = usd * 1_000_000 == case["microUsd"]
    elif kind == "queue":
        ok = rec["stageProgress"] == {"stage": case["stage"], "percent": case["percent"], "sample": True}
    elif kind == "lessons":
        docs = [load(FIX / r) for r in case["records"]]
        last = docs[-1]["practice"]
        ok = ([len(d["clips"]) for d in docs] == case["clipCounts"]
              and [p["done"] for p in last[:2]] == case["practice"]["done"]
              and last[2]["target"] == case["practice"]["pendingClipGoal"] and last[2]["status"] == "pending")
    elif kind == "quote":
        d = rec["displayAmounts"]
        ok = (d["minMinor"], d["maxMinor"], d["capMinor"]) == (case["minUsd"] * 100, case["maxUsd"] * 100,
                                                              case["capUsd"] * 100) and rec["illustrative"]
    else:
        ok = False
    if ok:
        rep.ok("sample-truth vectors")
    else:
        rep.fail(where, f"sample truth '{case['id']}' does not hold")


def check_edl_context_vector(ctx: Ctx, case, rep, where) -> None:
    """An EDL validated against a patched trusted context (e.g. a source with two adjacent coverage intervals)."""
    plan = apply_patch(load(FIX / case["plan"]), case["planPatch"])
    context = apply_patch(ctx.edl_context, case["contextPatch"])
    errors = ctx.schemas.validate(plan, "edit-plan.schema.json")
    if errors:
        rep.fail(where, "patched plan fails the schema: " + "; ".join(errors[:2]))
        return
    try:
        got = {"status": edl.validate(plan, ctx.profiles, context)["status"]}
    except Reject as exc:
        got = {"rejectCode": exc.code}
    if got != case["expect"]:
        rep.fail(where, f"reference gives {got}, stored {case['expect']}")
        return
    a = case["assert"]
    seg = plan["segments"][4]
    cov = context["sources"][seg["sourceId"]]["coverage"]
    problems = []
    if "sessionInUs" in a:
        # hand rule: the interval holding the first frame is the half-open one with inFrame <= frame < outFrame
        holder = [c for c in cov if c["inFrame"] <= seg["sourceInFrame"] < c["outFrame"]][0]
        valid = got == {"status": "valid-plan"}
        if holder["inFrame"] == seg["sourceInFrame"] and valid != (a["sessionInUs"] == holder["sessionStartUs"]):
            problems.append("the first frame of an interval must map to that interval's sessionStartUs")
    if a.get("handlesCrossRestart") and got.get("rejectCode") != "transitionHandle":
        problems.append("a dissolve across a restart must be refused for its handles")
    if problems:
        rep.fail(where, "hand assertions: " + ", ".join(problems))
    else:
        rep.ok("edl-context vectors")


def check_vectors(ctx: Ctx, rep: Report) -> None:
    for path in sorted((FIX / "vectors").glob("*.json")):
        doc = load(path)
        errors = ctx.schemas.validate(doc, "fixture.schema.json")
        if errors:
            rep.fail(str(path.relative_to(ROOT)), "; ".join(errors[:3]))
            continue
        for case in doc["cases"]:
            where = f"{path.relative_to(ROOT)}#{case['id']}"
            try:
                if doc["kind"] == "sync-fit":
                    check_sync_vector(case, rep, where)
                elif doc["kind"] == "sound-delay":
                    check_sound_vector(case, rep, where)
                elif doc["kind"] == "job-transitions":
                    jobstate.run_vector(ctx.machine, case)
                    rep.ok("job-transition vectors")
                elif doc["kind"] == "ledger":
                    ledger.run_sequence(ctx.classes, case)
                    rep.ok("ledger vectors")
                elif doc["kind"] == "quote-credits":
                    got = ledger.quote_credits(ctx.classes, case["filmClass"], case["estimatedMaxCostMicroUsd"])
                    if got != case["expectCredits"]:
                        rep.fail(where, f"{got} credits, expected {case['expectCredits']}")
                    else:
                        rep.ok("quote-credit vectors")
                elif doc["kind"] == "sample-truth":
                    check_sample_truth(ctx, case, rep, where)
                elif doc["kind"] == "edl-context":
                    check_edl_context_vector(ctx, case, rep, where)
            except Reject as exc:
                rep.fail(where, str(exc))


# ----- 8: determinism -----------------------------------------------------------------------------

def check_determinism(rep: Report) -> None:
    import generate_studio_fixtures as gen
    expected = gen.build()
    on_disk = {str(p.relative_to(FIX)): load(p) for p in FIX.rglob("*.json")}
    if set(expected) != set(on_disk):
        rep.fail("determinism", f"fixture set differs: missing {sorted(set(expected) - set(on_disk))}, "
                                f"extra {sorted(set(on_disk) - set(expected))}")
    for rel, doc in expected.items():
        if rel in on_disk and json.loads(json.dumps(doc)) != on_disk[rel]:
            rep.fail("determinism", f"{rel} is stale; run spec/reference/studio/generate_studio_fixtures.py")
    if gen.profile_catalog() != load(STUDIO / "contracts" / "story-profiles.v1.json"):
        rep.fail("determinism", "story-profiles.v1.json is stale")
    rep.ok("generated files current", len(expected) + 1)


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


def main() -> int:
    rep = Report("-v" in sys.argv[1:])
    try:
        ctx = Ctx()
    except (OSError, KeyError, ValueError) as exc:
        print(f"FAIL loading Studio contracts: {exc}")
        return 1
    check_schemas(ctx, rep)
    check_drift(ctx, rep)
    check_contracts(ctx, rep)
    check_records(ctx, rep)
    check_bundle(ctx, rep)
    check_invalid(ctx, rep)
    check_vectors(ctx, rep)
    check_context_required(ctx, rep)
    check_hint_states(ctx, rep)
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
