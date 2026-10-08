"""StoryDirector vectors (`director`) and RulesPlanner vectors (`planner`), with their checkers. Module page:
spec/studio/modules/planner.md.

Every case carries its planning context inline, so a port reads one case and compares one output. The context is the
sample-court-day project projected by `sample_context` from the Sample records (keeper, B-roll and reference catalogs,
lessons, observations, source manifest, sync map and the progress brief) plus the few Sample facts no record carries
(SAMPLE_* below), then the case's `contextPatch`. The checker re-derives it, so a record change cannot leave a stale
context behind. "expect" comes from the reference (director.py, planner.py); every "assert" block is a hand-derived
literal worked from the profile grammar (film-engine section 6), the stories and the keeper windows, checked
independently of the reference.
"""

from __future__ import annotations

import copy

from studio import director, planner
from studio import keepers as keeper_rules
from studio.cases.progress_cases import sample_scopes
from studio.core import Reject, apply_patch, canonical_bytes, require

DIRECTOR = "director"
PLANNER = "planner"
VECTORS = {DIRECTOR: "vectors/director.json", PLANNER: "vectors/planner.json"}
PROFILE_IDS = ("coach-cut", "match-broadcast", "rally-pulse", "progress-story", "court-memories")
CONTEXT_CASE = "context-sample-court-day"
# Hand-read from the Sample records: keeper -> [view slots, primary first; lesson clips; real rally; break point;
# window ms], cue -> [keeper via its observation's point, provenance], note uses, B-roll lengths (1800 and 2700 frames at
# 30 fps), the lesson notes the reference catalog holds, and the primary's 0-3600 s match coverage.
CONTEXT_ASSERT = {
    "coverageSeconds": 3600, "primaryHasAudio": True,
    "bindings": {"eventRevision": 3, "syncRevision": 2, "keeperCatalogRevision": 1, "brollCatalogRevision": 1},
    "keepers": {"k-01": [["near-baseline", "far-baseline"], [], True, False, 7500],
                "k-02": [["near-baseline"], ["l3-clip-1"], True, True, 68000],
                "k-03": [["near-baseline"], [], True, False, 87000],
                "k-04": [["near-baseline", "far-baseline"], [], False, False, 122000]},
    "cues": {"cue-03": ["k-02", "reviewed"], "cue-04": ["k-02", "estimated"]},
    "notes": {"note-caption": "caption", "note-goal": "goal", "note-drill": "drill", "note-next": "next",
              "note-players": "players", "note-lesson-2": "lesson", "l3-note-1": "lesson", "l3-note-2": "lesson"},
    "brollMs": {"b-01": 60000, "b-02": 90000},
    "lessons": {"lesson-0909": [], "lesson-0923": ["note-lesson-2"], "lesson-1007": ["l3-note-1", "l3-note-2"]},
}

# ----- Sample facts no record carries (fictional, labelled Sample like every fixture) ----------------------------------
# Rally lengths for the four catalog keepers (provenance is the keeper's own); k-02 (p-041, "Jon's favourite point,
# reviewed" in the court-memories brief) is a break point. Fold index = point number - 1.
SAMPLE_RALLIES = {"k-01": 14, "k-02": 9, "k-03": 6, "k-04": 11}
SAMPLE_BREAK_POINTS = ("k-02",)
# What each user note is for (the app knows the field a note was typed into).
SAMPLE_NOTE_USES = {"note-goal": "goal", "note-drill": "drill", "note-next": "next", "note-players": "players",
                    "note-caption": "caption"}
# The B-roll chapter the player marked ("Walking to the court", "Packing the bag after the match").
SAMPLE_BROLL_CHAPTERS = {"b-01": "arrival", "b-02": "after"}
# Session dates of the dated examples, as the Sample progress brief uses them (b02 September evidence, b04 October).
SAMPLE_KEEPER_DATES = {"k-02": "2026-09-09", "k-04": "2026-10-07"}
# The annotation drawn on a keeper (edit-plan.coach-cut-serve.json pauses k-02 at frame 73100 with ann-01).
SAMPLE_ANNOTATIONS = {"ann-01": "k-02"}
SAMPLE_JUNIOR_MODE = False
SAMPLE_POINT_COVERAGE_COMPLETE = False   # the catalog keeps 4 moments of the match, not every point


# ----- the sample-court-day planning context --------------------------------------------------------------------

def _docs(records: dict, version: str) -> list:
    return [d for _, d in sorted(records.items()) if d["schemaVersion"] == version]


def sample_context(records: dict) -> dict:
    """The planning context of the Sample project. `records` maps a record name (file name without .json) to it."""
    manifest, smap = records["source-manifest"], records["sync-map"]
    cat, broll_cat, refs = records["keeper-catalog"], records["broll-catalog"], records["reference-catalog"]
    slot = {s["sourceId"]: s["slot"] for s in manifest["sources"]}
    primary = next(s for s in manifest["sources"] if s["isPrimary"])
    pieces = next(x for x in smap["sources"] if x["sourceId"] == primary["sourceId"])["pieces"]
    coverage_us = sum(p["matchCoverage"]["endUs"] - p["matchCoverage"]["startUs"] for p in pieces
                      if p["state"] in keeper_rules.USABLE_SYNC_STATES)
    lessons = sorted(_docs(records, "jovra.lesson/1"), key=lambda x: (x["date"], x["lessonId"]))
    observations = {o["observationId"]: o for o in _docs(records, "jovra.observation/1")}
    ref_by_id = {r["refId"]: r for r in refs["references"]}
    clip_keeper = {c["clipId"]: c["keeperId"] for x in lessons for c in x["clips"] if c["keeperId"]}

    def keeper_of_event(event_id):
        return next((k["keeperId"] for k in cat["keepers"] if event_id in k["eventRefs"]), None)

    keepers = []
    for k in cat["keepers"]:
        views = sorted(k["views"], key=lambda v: not v["primary"])
        rally = SAMPLE_RALLIES.get(k["keeperId"])
        keepers.append({
            "keeperId": k["keeperId"], "origin": "point", "eventRefs": list(k["eventRefs"]),
            "session": dict(k["session"]), "slots": [slot[v["sourceId"]] for v in views],
            "selection": k["selection"], "provenance": k["provenance"], "markIds": [],
            "lessonClipIds": sorted(c for c, owner in clip_keeper.items() if owner == k["keeperId"]),
            "facts": {"index": int(k["eventRefs"][0].split("-")[1]) - 1, "rallyLength": rally,
                      "rallyReal": rally is not None and k["provenance"] in keeper_rules.REAL_PROVENANCE,
                      "breakPoint": k["keeperId"] in SAMPLE_BREAK_POINTS, "setPoint": False, "matchPoint": False,
                      "provenance": k["provenance"]}})
    cues = []
    for x in lessons:
        for cue in x["cues"]:
            obs = observations.get(cue["observationId"])
            owner = keeper_of_event(obs["eventRef"]) if obs and obs["eventRef"] else clip_keeper.get(cue["clipId"])
            cues.append({"cueId": cue["cueId"], "keeperId": owner, "provenance": cue["provenance"]})
    notes = [{"noteId": r["refId"], "use": SAMPLE_NOTE_USES[r["refId"]], "date": None} for r in refs["references"]
             if r["kind"] == "note" and r["origin"]["recordKind"] == "user-note" and r["refId"] in SAMPLE_NOTE_USES]
    notes += [{"noteId": n["noteId"], "use": "lesson", "date": x["date"]} for x in lessons for n in x["notes"]
              if n["noteId"] in ref_by_id]
    fps = {s["sourceId"]: [p for p in s["proxies"] if p["class"] == "render"][0]["fps"] for s in manifest["sources"]}
    brolls = []
    for b in broll_cat["items"]:
        f = fps[b["sourceId"]]
        brolls.append({"brollId": b["brollId"], "chapter": SAMPLE_BROLL_CHAPTERS[b["brollId"]],
                       "durationMs": (b["window"]["outFrame"] - b["window"]["inFrame"]) * 1000 * f["den"] // f["num"],
                       "depictsThisMatch": b["depictsThisMatch"], "revealsLocation": b["revealsLocation"]})
    brief = records["story-brief.progress"]
    cmp = brief["comparisons"][0]
    earlier, later = sample_scopes(brief)
    return {
        "projectId": cat["projectId"], "sample": cat["sample"],
        "bindings": {"eventRevision": cat["eventRevision"], "syncRevision": smap["revision"],
                     "keeperCatalogRevision": cat["revision"], "brollCatalogRevision": broll_cat["revision"]},
        "coverageSeconds": coverage_us // 1_000_000,
        "primaryHasAudio": primary["original"]["audio"] is not None,
        "juniorMode": SAMPLE_JUNIOR_MODE, "pointCoverageComplete": SAMPLE_POINT_COVERAGE_COMPLETE,
        "keepers": keepers, "brolls": brolls,
        "references": [{"refId": r["refId"], "kind": r["kind"], "provenance": r["provenance"]}
                       for r in refs["references"]],
        "notes": notes,
        "lessons": [{"lessonId": x["lessonId"], "date": x["date"],
                     "noteIds": [n["noteId"] for n in x["notes"] if n["noteId"] in ref_by_id]} for x in lessons],
        "cues": cues,
        "annotations": [{"refId": a, "keeperId": k} for a, k in sorted(SAMPLE_ANNOTATIONS.items())],
        "progress": {"statId": cmp["statId"], "statDefinitionId": cmp["metricDefinitionId"], "earlier": earlier,
                     "later": later, "dates": dict(SAMPLE_KEEPER_DATES), "selectionRule": cmp["selectionRule"]},
        "rights": [{"rightsRecordId": r["rightsRecordId"], "assetId": r["assetId"]} for r in refs["rights"]],
        "consents": [{"consentRecordId": c["consentRecordId"], "scope": list(c["scope"]), "granted": c["granted"]}
                     for c in refs["consents"]],
    }


def record_names(records: dict) -> dict:
    """generate_studio_fixtures keys records by 'records/<name>.json'; the validator by '<name>'."""
    return {k[len("records/"):-len(".json")] if k.startswith("records/") else k: v for k, v in records.items()}


def _at(items: list, key: str, value) -> int:
    return next(i for i, x in enumerate(items) if x[key] == value)


def compact(b: dict) -> str:
    """A beat as a hand-checkable string: role, treatment, the id it shows, angle and replay speed."""
    shown = b["keeperId"] or b["brollId"] or b["templateId"]
    den = f"1/{b['replaySpeedDen']}" if b["replaySpeedDen"] else None
    return " ".join(x for x in (b["role"], b["treatment"], shown, b["angle"], den) if x)


# ----- hand-derived plans (film-engine section 6 worked over the Sample keepers) ----------------------------------
# Keeper windows: k-01 12.0-19.5 s = 7500 ms, k-02 1196-1264 s = 68000 ms, k-03 1998-2085 s = 87000 ms,
# k-04 2498-2620 s = 122000 ms. Cards hold 4000 ms (Rally Pulse 1500 ms, its cardMs maximum), a freeze 2000 ms, a
# replay min(8000 ms, 2 x the keeper) = 8000 ms, a B-roll shot at most 6000 ms.

COACH = ["goal title-card card.goal", "example live k-02 near-baseline", "cue freeze k-02 near-baseline",
         "replay replay k-02 near-baseline 1/2", "example live k-01 near-baseline", "example live k-03 near-baseline",
         "drill title-card card.drill", "checkpoint title-card card.next-checkpoint"]
COACH_MS = 4000 + 68000 + 2000 + 8000 + 7500 + 87000 + 4000 + 4000                    # 184500
BROADCAST = ["intro title-card card.match-intro", "point live k-01 near-baseline", "replay replay k-01 far-baseline 1/2",
             "point live k-02 near-baseline", "point live k-03 near-baseline", "point live k-04 near-baseline",
             "replay replay k-04 far-baseline 1/2"]
BROADCAST_MS = 4000 + 7500 + 8000 + 68000 + 87000 + 122000 + 8000                     # 304500
RALLY = ["opening live k-01 near-baseline", "key-exchange live k-02 near-baseline", "payoff live k-03 near-baseline",
         "close title-card card.accent"]
RALLY_MS = 7500 + 68000 + 87000 + 1500                                                 # 164000
PROGRESS_SHORT = ["goal title-card card.goal", "early-evidence live k-02 near-baseline",
                  "recent-evidence live k-04 near-baseline", "what-changed title-card card.what-changed",
                  "next-goal title-card card.next-goal"]
PROGRESS_SHORT_MS = 4000 + 68000 + 122000 + 4000 + 4000                                # 202000
PROGRESS = ["goal title-card card.goal", "early-evidence live k-02 near-baseline", "lesson title-card card.lesson",
            "lesson title-card card.lesson", "recent-evidence live k-04 near-baseline",
            "replay replay k-04 near-baseline 1/2", "what-changed title-card card.what-changed",
            "next-goal title-card card.next-goal"]
PROGRESS_MS = 4000 + 68000 + 4000 + 4000 + 122000 + 8000 + 4000 + 4000                 # 218000
MEMORIES = ["arrival broll b-01", "match-moment live k-01 near-baseline", "highlight live k-02 near-baseline",
            "match-moment live k-03 near-baseline", "after broll b-02"]
MEMORIES_MS = 6000 + 7500 + 68000 + 87000 + 6000                                       # 174500
SERVE_DISPLAY = ["12 / 30 · 40%", "18 / 30 · 60%", "+20 percentage points"]


def shorter(estimate: str, length: str) -> str:
    return f"About {estimate} of real material, so this film is shorter than {length}. Nothing is padded."


def too_short(estimate: str, name: str, minimum: str) -> str:
    return f"About {estimate} of real material; {name} needs at least {minimum}. Mark more moments for a longer film."


# ----- vectors ----------------------------------------------------------------------------------------------------

def resolve(case: dict, base: dict, planned: dict, record) -> dict:
    """The full input a case runs on. Its context is the Sample context (the file's context case) patched by its
    `contextPatch`; a lint or check case's plan is the named planner case's expected plan (`fromCase`, patched by
    `planPatch`) or a Sample record (`fromRecord`)."""
    inp = dict(case["input"])
    if case["op"] in ("plan", "brief", "lint", "check"):
        inp["context"] = apply_patch(base, case["contextPatch"]) if case["contextPatch"] else copy.deepcopy(base)
    if case["op"] in ("lint", "check"):
        if "fromRecord" in case:
            inp["plan"] = copy.deepcopy(record(case["fromRecord"]))
        else:
            source = planned.get(case["fromCase"], {}).get("expect", {})
            require("plan" in source, "badVector", f"fromCase {case['fromCase']!r} is not a planner case with a plan")
            inp["plan"] = _patched(source["plan"], case["planPatch"])
    return {"op": case["op"], "input": inp}


def _patched(doc: dict, patch: list) -> dict:
    try:
        return apply_patch(doc, patch)
    except (IndexError, KeyError, TypeError, ValueError) as exc:
        raise Reject("badVector", f"planPatch does not apply to its source plan ({exc!r})") from None


def beat_of(case: dict, index: int):
    """A planned beat of a case, for a patch that moves it (None when a broken reference planned nothing)."""
    beats = case["expect"].get("plan", {}).get("beats", [])
    return beats[index] if index < len(beats) else None


def context_case(base: dict) -> dict:
    return {"id": CONTEXT_CASE, "why": "The sample-court-day planning context every other case starts from (its "
            "contextPatch applies to this)", "op": "context", "input": {}, "expect": {"context": base},
            "assert": CONTEXT_ASSERT}


def build_vectors(records: dict, profiles: dict) -> tuple[dict, dict]:
    base = sample_context(record_names(records))
    plans: list = [context_case(base)]
    briefs: list = [context_case(base)]
    planned: dict = {}

    def run(module, c):
        try:
            resolved = resolve(c, base, planned, lambda rel: records[rel])
        except Reject as exc:   # a broken reference cannot crash the generator (the validator regenerates too)
            return {"rejectCode": exc.code}
        return module.run_vector(profiles, resolved)

    def plan(cid, why, profile, options, assertions, patch=()):
        c = {"id": cid, "why": why, "op": "plan", "contextPatch": list(patch),
             "input": {"profileId": profile, "options": options}}
        c["expect"] = run(planner, c)
        c["assert"] = assertions
        plans.append(c)
        planned[cid] = c
        return c

    def check(cid, why, from_case, plan_patch, assertions, patch=()):
        c = {"id": cid, "why": why, "op": "check", "fromCase": from_case["id"], "planPatch": plan_patch,
             "contextPatch": list(patch), "input": {}}
        c["expect"] = run(planner, c)
        c["assert"] = assertions
        plans.append(c)

    def check_record(cid, why, rel, assertions):
        c = {"id": cid, "why": why, "op": "check", "fromRecord": rel, "contextPatch": [], "input": {}}
        c["expect"] = run(planner, c)
        c["assert"] = assertions
        plans.append(c)

    def brief(cid, why, profile, options, assertions, patch=()):
        c = {"id": cid, "why": why, "op": "brief", "contextPatch": list(patch),
             "input": {"profileId": profile, "options": options}}
        c["expect"] = run(director, c)
        c["assert"] = assertions
        briefs.append(c)

    def lint(cid, why, assertions, from_case=None, plan_patch=(), patch=(), rel=None):
        c = {"id": cid, "why": why, "op": "lint", "contextPatch": list(patch), "input": {}}
        if rel:
            c["fromRecord"] = rel
        else:
            c["fromCase"], c["planPatch"] = from_case["id"], list(plan_patch)
        c["expect"] = run(director, c)
        c["assert"] = assertions
        briefs.append(c)

    # --- the five profiles x {3 min, 5 min, Full} on sample-court-day (13 plans, 2 lengths the profile refuses) ---
    m = {}
    m["coach-cut-3min"] = plan(
        "coach-cut-3min", "Coach's Cut, 3 min: goal card, the reviewed-cue example k-02 at 1x, a paused frame with "
        "annotation ann-01 and cue cue-03, a labelled half-speed replay, then the player's chosen k-01 and k-03, the "
        "drill and next-checkpoint cards. k-03 brings it over 3 min, allowed only to reach the profile minimum",
        "coach-cut", {"length": "3min"},
        {"target": 180, "beats": COACH, "estimateMs": COACH_MS, "fallback": None, "belowMinimum": False,
         "omitted": [], "unresolved": [],
         "overlays": {"b02": ["score:p-041"], "b03": ["annotation:ann-01", "cue:cue-03"]},
         "notes": {"b01": "note-goal", "b07": "note-drill", "b08": "note-next"}})
    for length, target, label in (("5min", 300, "5 min"), ("full", 600, "10 min")):
        m[f"coach-cut-{length}"] = plan(
            f"coach-cut-{length}", f"Coach's Cut, {length}: the same three examples (the most it shows); 3 min 5 s "
            "of real material is not padded", "coach-cut", {"length": length},
            {"target": target, "beats": COACH, "estimateMs": COACH_MS, "fallback": None, "belowMinimum": False,
             "unresolved": [shorter("3 min 5 s", label)]})
    brief_refusals = (("match-broadcast", "3min", "Match Broadcast needs at least 5 min."),
                      ("rally-pulse", "5min", "Rally Pulse films are up to 3 min."))
    for profile, length, message in brief_refusals:
        plan(f"{profile}-{length}", f"ST29: {length} is outside the profile's range, so the length is offered "
             "disabled with this reason", profile, {"length": length},
             {"refusal": ["lengthUnavailable", message]})
    m["match-broadcast-5min"] = plan(
        "match-broadcast-5min", "Match Broadcast, 5 min: intro card, every kept point in match order on the wide "
        "angle, far-baseline replays right after k-01 and k-04 (the second only to reach 5 min); no final score card "
        "because the recorded points do not cover the match", "match-broadcast", {"length": "5min"},
        {"target": 300, "beats": BROADCAST, "estimateMs": BROADCAST_MS, "fallback": None, "belowMinimum": False,
         "omitted": ["Final score"], "unresolved": [], "overlays": {"b04": ["score:p-041"], "b06": ["score:p-090"]},
         "notes": {"b01": "note-players"}})
    m["match-broadcast-full"] = plan(
        "match-broadcast-full", "Match Broadcast, Full = min(7200 s, 3600 s of recording) = 60 min; 5 min 5 s of "
        "real material", "match-broadcast", {"length": "full"},
        {"target": 3600, "beats": BROADCAST, "estimateMs": BROADCAST_MS, "belowMinimum": False,
         "unresolved": [shorter("5 min 5 s", "60 min")]})
    for length in ("3min", "full"):
        m[f"rally-pulse-{length}"] = plan(
            f"rally-pulse-{length}", f"Rally Pulse, {length} (Full = its 3 min maximum): the break point k-02 and "
            "the real rallies k-01 (14 shots) and k-03 (6) whole, in time order, then a static close; the estimated "
            "k-04 rally is not real", "rally-pulse", {"length": length},
            {"target": 180, "beats": RALLY, "estimateMs": RALLY_MS, "fallback": None, "belowMinimum": False,
             "unresolved": [shorter("2 min 44 s", "3 min")], "effectIntensity": "low", "cleanAlternate": True,
             "overlays": {"b02": ["score:p-041"]}})
    m["progress-story-3min"] = plan(
        "progress-story-3min", "Progress Story, 3 min: goal, the dated early (k-02, Sep 9) and recent (k-04, Oct 7) "
        "evidence, the what-changed card and the next goal; the lesson cards do not fit", "progress-story",
        {"length": "3min"},
        {"target": 180, "beats": PROGRESS_SHORT, "estimateMs": PROGRESS_SHORT_MS, "fallback": None,
         "belowMinimum": False, "unresolved": [], "comparisons": [SERVE_DISPLAY],
         "overlays": {"b02": ["metric:stat-first-serve-in"], "b04": ["metric:stat-first-serve-in"]}})
    for length, target, label in (("5min", 300, "5 min"), ("full", 360, "6 min")):
        m[f"progress-story-{length}"] = plan(
            f"progress-story-{length}", f"Progress Story, {length}: adds the Sep 23 and Oct 7 lesson cards and a "
            "half-speed replay of the recent evidence", "progress-story", {"length": length},
            {"target": target, "beats": PROGRESS, "estimateMs": PROGRESS_MS, "fallback": None, "belowMinimum": False,
             "unresolved": [shorter("3 min 38 s", label)], "comparisons": [SERVE_DISPLAY],
             "notes": {"b01": "note-goal", "b03": "note-lesson-2", "b04": "l3-note-1", "b08": "note-next"}})
    for length, target, label in (("3min", 180, "3 min"), ("5min", 300, "5 min"), ("full", 480, "8 min")):
        m[f"court-memories-{length}"] = plan(
            f"court-memories-{length}", f"Court Memories, {length}: arrival B-roll, the day's moments in time order "
            "(k-02, lesson-linked break point, is the highlight), after B-roll; no score bug", "court-memories",
            {"length": length},
            {"target": target, "beats": MEMORIES, "estimateMs": MEMORIES_MS, "fallback": None, "belowMinimum": False,
             "unresolved": [shorter("2 min 55 s", label)], "omitted": [], "overlays": {}, "cleanAlternate": True})

    # --- documented fallbacks --------------------------------------------------------------------------------------
    cue = _at(base["cues"], "cueId", "cue-03")
    ref = _at(base["references"], "refId", "cue-03")
    m["coach-cut-your-examples"] = plan(
        "coach-cut-your-examples", "Story 125: with no reviewed cue (cue-03 only estimated) Coach's Cut opens with "
        "'Your examples', shows the examples at 1x with no paused cue, no drill and no checkpoint card",
        "coach-cut", {"length": "3min"},
        {"target": 180, "fallback": "your-examples",
         "beats": ["context title-card card.examples", "example live k-02 near-baseline",
                   "example live k-01 near-baseline", "example live k-03 near-baseline"],
         "estimateMs": 4000 + 68000 + 7500 + 87000, "belowMinimum": True,
         "omitted": ["Reviewed cue", "Practice drill and next checkpoint"],
         "unresolved": [too_short("2 min 47 s", "Coach’s Cut", "3 min")], "noTemplates": ["card.drill",
                                                                                       "card.next-checkpoint"]},
        patch=[{"op": "replace", "path": f"/cues/{cue}/provenance", "value": "estimated"},
               {"op": "replace", "path": f"/references/{ref}/provenance", "value": "estimated"}])
    plan("match-broadcast-one-angle", "Match Broadcast with one camera: the complete one-angle match, no replays",
         "match-broadcast", {"length": "5min"},
         {"target": 300, "fallback": "one-angle-match",
          "beats": ["intro title-card card.match-intro", "point live k-01 near-baseline",
                    "point live k-02 near-baseline", "point live k-03 near-baseline", "point live k-04 near-baseline"],
          "estimateMs": 4000 + 7500 + 68000 + 87000 + 122000, "belowMinimum": True,
          "omitted": ["Replays from another angle", "Final score"],
          "unresolved": [too_short("4 min 49 s", "Match Broadcast", "5 min")]},
         patch=[{"op": "replace", "path": f"/keepers/{i}/slots", "value": ["near-baseline"]}
                for i in range(len(base["keepers"]))])
    plan("progress-story-method-change", "Story 137: the Oct 7 session was tagged with method version 2, so the "
         "comparison is dropped and the film is a lesson chronology with a method-change note and no metric",
         "progress-story", {"length": "5min"},
         {"target": 300, "fallback": "lesson-chronology",
          "beats": ["goal title-card card.goal", "early-evidence live k-02 near-baseline",
                    "lesson title-card card.lesson", "lesson title-card card.lesson",
                    "what-changed title-card card.method-change", "next-goal title-card card.next-goal"],
          "estimateMs": 4000 + 68000 + 4000 + 4000 + 4000 + 4000, "belowMinimum": True,
          "omitted": ["Before and after comparison"], "comparisons": [], "overlays": {},
          "unresolved": [too_short("1 min 28 s", "Progress Story", "2 min")]},
         patch=[{"op": "replace", "path": "/progress/later/methodVersion", "value": "2"}])
    m["court-memories-no-broll"] = plan(
        "court-memories-no-broll", "Court Memories with no B-roll: the Arrival chapter shrinks from a 6 s shot to a "
        "4 s date card, there is no after chapter, and both are listed as missing", "court-memories",
        {"length": "3min"},
        {"target": 180, "fallback": "one-camera-excerpts",
         "beats": ["arrival title-card card.date", "match-moment live k-01 near-baseline",
                   "highlight live k-02 near-baseline", "match-moment live k-03 near-baseline"],
         "estimateMs": 4000 + 7500 + 68000 + 87000, "arrivalMs": 4000, "belowMinimum": False,
         "omitted": ["Arrival footage", "After the match"], "unresolved": [shorter("2 min 47 s", "3 min")]},
        patch=[{"op": "replace", "path": "/brolls", "value": []}])
    plan("rally-pulse-court-sound", "Rally Pulse with a track that has no rights record and Medium effects: "
         "court-sound highlights with static titles (effects back to low), the track listed as missing",
         "rally-pulse", {"length": "3min", "music": {"assetId": "track-02"}, "effects": "medium"},
         {"target": 180, "fallback": "court-sound-highlights", "beats": RALLY, "estimateMs": RALLY_MS,
          "music": None, "effectIntensity": "low", "omitted": ["Licensed music"]})
    plan("rally-pulse-licensed-music", "Rally Pulse with track-01, which has a rights record: the music is bound "
         "to it", "rally-pulse", {"length": "3min", "music": {"assetId": "track-01"}},
         {"target": 180, "fallback": None, "beats": RALLY, "omitted": [],
          "music": {"assetId": "track-01", "rightsRecordId": "rights-track-01"}})
    plan("no-keepers", "Story 120: with no keepers the planner refuses and asks for marks", "court-memories",
         {"length": "3min"}, {"refusal": ["noKeepers", "Mark a few moments first"]},
         patch=[{"op": "replace", "path": "/keepers", "value": []}])

    # --- trust check: what a plan from any planner must pass ----------------------------------------------------------
    c3 = m["coach-cut-3min"]
    check("check-coach-cut-3min", "The RulesPlanner's own plan passes", c3, [], {"ok": True, "beats": 8})
    check("unknown-keeper", "A planner output naming keeper k-99, which is not in the catalog", c3,
          [{"op": "replace", "path": "/beats/1/keeperId", "value": "k-99"}], {"rejectCode": "untrustedReference"})
    check("card-with-free-text", "Story 157: a card carrying its own text instead of a template slot", c3,
          [{"op": "add", "path": "/beats/0/text", "value": "Sample: Best serve ever!"}], {"rejectCode": "unknownField"})
    check("unknown-card-template", "A card template that is not in the catalog", c3,
          [{"op": "replace", "path": "/beats/0/templateId", "value": "card.quote"}],
          {"rejectCode": "untrustedReference"})
    check("card-note-of-the-wrong-use", "card.goal filled with the drill note", c3,
          [{"op": "replace", "path": "/beats/0/noteId", "value": "note-drill"}], {"rejectCode": "badTemplateSlot"})
    check("card-without-its-note", "card.drill with no note", c3,
          [{"op": "replace", "path": "/beats/6/noteId", "value": None}], {"rejectCode": "badTemplateSlot"})
    check("angle-with-no-view", "k-02 has no far-baseline view", c3,
          [{"op": "replace", "path": "/beats/1/angle", "value": "far-baseline"}], {"rejectCode": "untrustedReference"})
    check("overlay-not-stored", "A score overlay for a point that is not in the reference catalog", c3,
          [{"op": "replace", "path": "/beats/1/overlays/0/refId", "value": "p-999"}],
          {"rejectCode": "untrustedReference"})
    check("card-showing-a-keeper", "A title card that also names a keeper", c3,
          [{"op": "replace", "path": "/beats/0/keeperId", "value": "k-02"}], {"rejectCode": "treatmentMismatch"})
    check("stale-event-revision", "A plan bound to event revision 2 after a correction made it 3", c3,
          [{"op": "replace", "path": "/bindings/eventRevision", "value": 2}], {"rejectCode": "staleRevision"})
    check("other-project", "A plan for another project", c3,
          [{"op": "replace", "path": "/projectId", "value": "other-court-day"}], {"rejectCode": "projectMismatch"})
    check("music-without-rights", "Music naming a rights record the project does not hold", m["rally-pulse-3min"],
          [{"op": "replace", "path": "/music", "value": {"assetId": "track-02", "rightsRecordId": "rights-track-02"}}],
          {"rejectCode": "untrustedReference"})
    check_record("check-sample-court-memories-brief", "The Sample court-memories brief resolves in the context",
                 "records/story-brief.court-memories.json", {"ok": True, "beats": 4})
    check_record("check-sample-progress-brief", "The Sample progress brief resolves in the context",
                 "records/story-brief.progress.json", {"ok": True, "beats": 5})

    # --- director: briefs -----------------------------------------------------------------------------------------
    for profile, target in (("coach-cut", 600), ("match-broadcast", 3600), ("rally-pulse", 180),
                            ("progress-story", 360), ("court-memories", 480)):
        brief(f"full-{profile}", f"Full is the profile maximum bounded by the 3600 s recording: {target} s", profile,
              {"length": "full"}, {"target": target, "briefId": f"brief-{profile}-full", "lint": []})
    brief("default-length-coach-cut", "ST29: 5 min by default when the profile allows it", "coach-cut", {},
          {"target": 300, "length": "5min", "aspect": "16:9", "audio": "continuous-primary-court-audio",
           "effectIntensity": "low", "audience": "self", "cleanAlternate": False, "lint": []})
    brief("default-length-rally-pulse", "Rally Pulse cannot be 5 min, so it starts at 3 min", "rally-pulse", {},
          {"target": 180, "length": "3min", "cleanAlternate": True})
    brief("court-memories-defaults", "Court Memories is for family by default, venue hidden, faces shown",
          "court-memories", {}, {"target": 300, "audience": "family", "venueVisible": False, "faces": "show"})
    for profile, length, message in brief_refusals:
        brief(f"refuse-{profile}-{length}", "The disabled length's reason", profile, {"length": length},
              {"refusal": ["lengthUnavailable", message]})
    short = [{"op": "replace", "path": "/coverageSeconds", "value": 200}]
    brief("short-recording-5min", "A 3 min 20 s recording cannot make a 5 min film", "coach-cut", {"length": "5min"},
          {"refusal": ["lengthUnavailable", "The recording is shorter than 5 min."]}, patch=short)
    brief("short-recording-full", "Full is bounded by the 200 s recording", "coach-cut", {"length": "full"},
          {"target": 200}, patch=short)
    brief("short-recording-broadcast-full", "Full Match Broadcast from 200 s is under its 5 min minimum",
          "match-broadcast", {"length": "full"},
          {"refusal": ["lengthUnavailable", "Match Broadcast needs at least 5 min."]}, patch=short)
    for profile in PROFILE_IDS:
        brief(f"no-keepers-{profile}", "Any profile with no keepers: 'Mark a few moments first'", profile, {},
              {"refusal": ["noKeepers", "Mark a few moments first"]},
              patch=[{"op": "replace", "path": "/keepers", "value": []}])
    brief("portrait-letterboxed", "SD15: 9:16 is letterboxed landscape by default", "rally-pulse",
          {"length": "3min", "aspect": "9:16"}, {"aspect": "9:16", "framing": "letterbox"})
    brief("junior-mode-no-audio", "SD5: junior mode films have no audio", "court-memories", {},
          {"audio": "no-audio"}, patch=[{"op": "replace", "path": "/juniorMode", "value": True}])
    brief("silent-source-no-audio", "SD5: a primary with no audio track gives a film with no audio", "coach-cut", {},
          {"audio": "no-audio"}, patch=[{"op": "replace", "path": "/primaryHasAudio", "value": False}])
    brief("rally-pulse-medium-effects", "Rally Pulse offers Medium effects", "rally-pulse", {"effects": "medium"},
          {"effectIntensity": "medium", "lint": []})
    brief("rally-pulse-high-effects", "High is not in the grammar yet (low or medium)", "rally-pulse",
          {"effects": "high"}, {"rejectCode": "optionUnavailable"})
    brief("effects-on-coach-cut", "Only Rally Pulse offers an effects choice", "coach-cut", {"effects": "medium"},
          {"rejectCode": "optionUnavailable"})
    brief("shake-stays-off", "Shake is off", "rally-pulse", {"shake": True}, {"rejectCode": "optionUnavailable"})
    brief("rallies-stay-whole", "Keep full rallies is on", "rally-pulse", {"keepFullRallies": False},
          {"rejectCode": "optionUnavailable"})
    brief("music-on-coach-cut", "Coach's Cut has no music", "coach-cut", {"music": {"assetId": "track-01"}},
          {"rejectCode": "optionUnavailable"})
    brief("court-memories-licensed-music", "Music is bound to its rights record", "court-memories",
          {"music": {"assetId": "track-01"}}, {"music": {"assetId": "track-01", "rightsRecordId": "rights-track-01"}})
    brief("narration-with-consent", "Narration needs the granted voice consent", "coach-cut",
          {"narration": {"voice": "user-recorded", "consentRecordId": "consent-voice-jon"}},
          {"narration": {"voice": "user-recorded", "consentRecordId": "consent-voice-jon"}, "lint": []})
    brief("narration-on-broadcast", "Match Broadcast has no narration", "match-broadcast",
          {"narration": {"voice": "user-recorded", "consentRecordId": "consent-voice-jon"}},
          {"rejectCode": "optionUnavailable"})
    brief("narration-without-consent", "A consent record the project does not hold", "coach-cut",
          {"narration": {"voice": "user-recorded", "consentRecordId": "consent-voice-alex"}},
          {"rejectCode": "noConsent"})
    brief("caption-and-venue", "Caption note and venue opt-in", "court-memories",
          {"caption": "note-caption", "venueVisible": True}, {"venueVisible": True, "caption": "note-caption"})
    brief("caption-must-be-a-caption", "The goal note is not a caption", "court-memories", {"caption": "note-goal"},
          {"rejectCode": "untrustedReference"})
    brief("unknown-option", "Options are a closed set", "coach-cut", {"music2": True}, {"rejectCode": "unknownField"})
    brief("unknown-profile", "Five profiles only", "highlight-reel", {}, {"rejectCode": "unknownProfile"})
    briefs.append({"id": "card-templates", "why": "The card text catalog: template ids with typed slots, and the "
                   "Coach's Cut cards that instruct", "op": "templates", "input": {},
                   "expect": director.run_vector(profiles, {"op": "templates", "input": {}}),
                   "assert": {"ids": ["card.accent", "card.date", "card.dedication", "card.drill", "card.examples",
                                      "card.final-score", "card.goal", "card.lesson", "card.match-intro",
                                      "card.method-change", "card.next-checkpoint", "card.next-goal",
                                      "card.not-compared", "card.what-changed"],
                              "examplesText": "Your examples",
                              "instruction": ["card.drill", "card.next-checkpoint"]}})

    # --- director: grammar lint (bold rules) -----------------------------------------------------------------------
    def rules(*pairs):
        return {"rules": [list(p) for p in pairs]}

    lint("sample-court-memories-brief", "The Sample court-memories brief keeps its grammar", rules(),
         rel="records/story-brief.court-memories.json")
    lint("sample-progress-brief-replay-first", "The Sample progress brief shows k-04 only as a replay, before any "
         "original-speed showing (film-engine 6.0: replays come after the 1x showing)",
         rules(("replay-before-live", "b04")), rel="records/story-brief.progress.json")
    lint("planned-coach-cut-clean", "The planner's own plan passes", rules(), from_case=c3)
    lint("replay-at-one-eighth", "Coach's Cut replays at 1/2 or 1/4 only", rules(("replay-speed", "b04")),
         from_case=c3, plan_patch=[{"op": "replace", "path": "/beats/3/replaySpeedDen", "value": 8}])
    lint("replay-before-its-live", "A replay of k-03 before k-03 is shown at 1x", rules(("replay-before-live", "b04")),
         from_case=c3, plan_patch=[{"op": "replace", "path": "/beats/3/keeperId", "value": "k-03"}])
    lint("estimated-cue-as-instruction", "An estimated cue is never an instruction title, and with no reviewed cue "
         "left the drill and checkpoint cards would instruct without one",
         rules(("overlay-not-allowed", "b03"), ("instruction-without-cue", "b07"), ("instruction-without-cue", "b08")),
         from_case=c3,
         plan_patch=[{"op": "replace", "path": "/beats/2/overlays/1/refId", "value": "cue-04"}])
    lint("music-in-coach-cut", "Coach's Cut has no music", rules(("music", None)), from_case=c3,
         plan_patch=[{"op": "replace", "path": "/music",
                      "value": {"assetId": "track-01", "rightsRecordId": "rights-track-01"}}])
    lint("medium-effects-in-coach-cut", "Effects above low only in Rally Pulse", rules(("effect-intensity", None)),
         from_case=c3, plan_patch=[{"op": "replace", "path": "/effectIntensity", "value": "medium"}])
    lint("instruction-without-reviewed-cue", "Story 125: a drill card in 'Your examples' would instruct without a "
         "reviewed cue", rules(("instruction-without-cue", "b05")), from_case=m["coach-cut-your-examples"],
         plan_patch=[{"op": "add", "path": "/beats/-", "value": {
             "beatId": "b05", "role": "drill", "treatment": "title-card", "keeperId": None, "brollId": None,
             "angle": None, "replaySpeedDen": None, "overlays": [], "noteId": "note-drill",
             "templateId": "card.drill", "reasonForReview": "Sample: an added drill card."}}],
         patch=[{"op": "replace", "path": f"/cues/{cue}/provenance", "value": "estimated"},
                {"op": "replace", "path": f"/references/{ref}/provenance", "value": "estimated"}])
    b5 = m["match-broadcast-5min"]
    lint("broadcast-off-the-wide-angle", "During live play Match Broadcast stays on the wide angle",
         rules(("wide-angle-only", "b02")), from_case=b5,
         plan_patch=[{"op": "replace", "path": "/beats/1/angle", "value": "far-baseline"}])
    lint("broadcast-out-of-order", "Match Broadcast is strictly chronological: k-02 after k-03",
         rules(("strict-chronology", "b05")), from_case=b5,
         plan_patch=[{"op": "replace", "path": "/beats/3/keeperId", "value": "k-03"},
                     {"op": "replace", "path": "/beats/4/keeperId", "value": "k-02"}])
    lint("broadcast-replay-after-the-next-point", "A replay must end before the next point's serve: k-01's replay "
         "(b03) moved after k-02's point", rules(("strict-chronology", "b03")), from_case=b5,
         plan_patch=[{"op": "replace", "path": "/beats/2", "value": beat_of(b5, 3)},
                     {"op": "replace", "path": "/beats/3", "value": beat_of(b5, 2)}])
    lint("final-score-on-incomplete-coverage", "A final score card only when every point is recorded",
         rules(("final-score-incomplete", "b08")), from_case=b5,
         plan_patch=[{"op": "add", "path": "/beats/-", "value": {
             "beatId": "b08", "role": "final-score", "treatment": "title-card", "keeperId": None, "brollId": None,
             "angle": None, "replaySpeedDen": None, "overlays": [], "noteId": None, "templateId": "card.final-score",
             "reasonForReview": "Sample: an added final score."}}])
    lint("narration-in-broadcast", "Match Broadcast invents no commentary", rules(("narration", None)), from_case=b5,
         plan_patch=[{"op": "replace", "path": "/narration",
                      "value": {"voice": "user-recorded", "consentRecordId": "consent-voice-jon"}}])
    r3 = m["rally-pulse-3min"]
    lint("rally-pulse-five-minutes", "Rally Pulse runs 30-180 s", rules(("duration-range", None)), from_case=r3,
         plan_patch=[{"op": "replace", "path": "/durationTargetSeconds", "value": 300}])
    lint("freeze-in-rally-pulse", "Rally Pulse has no freeze", rules(("op-not-in-profile", "b01")), from_case=r3,
         plan_patch=[{"op": "replace", "path": "/beats/0/treatment", "value": "freeze"}])
    lint("goal-card-in-rally-pulse", "card.goal is not a Rally Pulse card", rules(("card-template", "b04")),
         from_case=r3, plan_patch=[{"op": "replace", "path": "/beats/3/templateId", "value": "card.goal"}])
    p5 = m["progress-story-5min"]
    lint("percent-improvement", "'% improvement' on a proportion is banned", rules(("comparison-claim", None)),
         from_case=p5, plan_patch=[{"op": "replace", "path": "/comparisons/0/display/delta",
                                    "value": "+50% improvement"}])
    lint("change-claim-from-manual-counts", "Improvement language needs Reviewed on both sides",
         rules(("comparison-claim", None)), from_case=p5,
         plan_patch=[{"op": "replace", "path": "/comparisons/0/before/provenance", "value": "manual"}])
    cm = m["court-memories-3min"]
    b02 = _at(base["brolls"], "brollId", "b-02")
    b01 = _at(base["brolls"], "brollId", "b-01")
    lint("broll-not-from-this-match", "B-roll must depict this match", rules(("broll-not-this-match", "b05")),
         from_case=cm, patch=[{"op": "replace", "path": f"/brolls/{b02}/depictsThisMatch", "value": False}])
    lint("broll-reveals-hidden-venue", "A hidden location stays hidden", rules(("hidden-location", "b01")),
         from_case=cm, patch=[{"op": "replace", "path": f"/brolls/{b01}/revealsLocation", "value": True}])
    lint("same-moment-twice", "A moment is shown at 1x once", rules(("one-live-showing", "b04")), from_case=cm,
         plan_patch=[{"op": "replace", "path": "/beats/3/keeperId", "value": "k-02"}])

    director_doc = {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": DIRECTOR,
                    "status": "Sample: expect from spec/reference/studio/director.py (briefs, card catalog, grammar "
                              "lint); assert blocks are hand-derived from the profile grammar and the ST29 copy",
                    "cases": briefs}
    planner_doc = {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": PLANNER,
                   "status": "Sample: expect from spec/reference/studio/planner.py over the sample-court-day context; "
                             "assert blocks are hand-derived beat lists and estimates worked from the keeper windows",
                   "cases": plans}
    return director_doc, planner_doc


def fixtures(sample):
    director_doc, planner_doc = build_vectors(sample.records, sample.profiles)
    return {VECTORS[DIRECTOR]: director_doc, VECTORS[PLANNER]: planner_doc}


# ----- checkers ---------------------------------------------------------------------------------------------------

def _resolved(ctx, case) -> dict:
    """A case's full input, from the Sample records as they are now (so a changed record cannot hide behind a stored
    context) and the stored planner cases (each checked against the reference on its own)."""
    planned = {c["id"]: c for c in ctx.fixture(VECTORS[PLANNER])["cases"]}
    return resolve(case, sample_context(ctx.records), planned, ctx.fixture)


def _context_problems(ctx, case) -> list:
    """The context case: the stored context is today's projection of the records, and it agrees with the hand list."""
    got = case["expect"]["context"]
    if got != sample_context(ctx.records):
        return ["the stored Sample context is out of date with the records"]
    a = case["assert"]
    keepers = {k["keeperId"]: [k["slots"], k["lessonClipIds"], k["facts"]["rallyReal"], k["facts"]["breakPoint"],
                               (k["session"]["endUs"] - k["session"]["startUs"]) // 1000] for k in got["keepers"]}
    have = {"coverageSeconds": got["coverageSeconds"], "bindings": got["bindings"], "keepers": keepers,
            "cues": {c["cueId"]: [c["keeperId"], c["provenance"]] for c in got["cues"]},
            "notes": {n["noteId"]: n["use"] for n in got["notes"]},
            "brollMs": {b["brollId"]: b["durationMs"] for b in got["brolls"]},
            "lessons": {x["lessonId"]: x["noteIds"] for x in got["lessons"]},
            "primaryHasAudio": got["primaryHasAudio"]}
    return [f"{k}: {have[k]!r}, hand value {a[k]!r}" for k in a if have.get(k) != a[k]]


def _brief_problems(got: dict, a: dict, ctx, resolved) -> list:
    if "rejectCode" in a:
        return [] if got.get("rejectCode") == a["rejectCode"] else [f"expected {a['rejectCode']}, got {got}"]
    if "rejectCode" in got:
        return [f"rejected with {got['rejectCode']}"]
    if "refusal" in a:
        r = got.get("refusal") or {}
        return [] if [r.get("code"), r.get("message")] == a["refusal"] else [f"refusal {r}, hand value {a['refusal']}"]
    if "refusal" in got:
        return [f"refused: {got['refusal']}"]
    b, d = got["brief"], got["directions"]
    have = {"target": b["durationTargetSeconds"], "briefId": b["briefId"], "length": d["length"], "aspect": b["aspect"],
            "audio": b["primaryAudioPolicy"], "effectIntensity": b["effectIntensity"], "audience": b["audience"],
            "cleanAlternate": b["cleanAlternate"], "venueVisible": b["privacy"]["venueVisible"],
            "faces": b["privacy"]["faces"], "framing": d["framing"], "music": b["music"], "narration": b["narration"],
            "caption": d["caption"]}
    p = [f"{k}: {have[k]!r}, hand value {a[k]!r}" for k in have if k in a and a[k] != have[k]]
    if "lint" in a and director.lint(ctx.profiles, b, resolved["input"]["context"]) != a["lint"]:
        p.append("the brief does not pass the grammar lint")
    return p


def _lint_problems(got: dict, a: dict) -> list:
    if "findings" not in got:
        return [f"lint failed: {got}"]
    have = [[f["rule"], f["beatId"]] for f in got["findings"]]
    p = [] if have == a["rules"] else [f"findings {have}, hand value {a['rules']}"]
    if any(f["code"] != "grammarViolation" for f in got["findings"]):
        p.append("a lint finding is not a grammarViolation")
    return p


def check_director_vector(ctx, case, report, where) -> None:
    if case["op"] == "context":
        problems = _context_problems(ctx, case)
        for problem in problems:
            report.fail(where, problem)
        if not problems:
            report.ok("director vectors (context)")
        return
    resolved = _resolved(ctx, case)
    got = director.run_vector(ctx.profiles, resolved)
    if got != case["expect"]:
        report.fail(where, "reference output differs from the stored expectation")
        return
    a = case["assert"]
    if case["op"] == "brief":
        problems = _brief_problems(got, a, ctx, resolved)
    elif case["op"] == "lint":
        problems = _lint_problems(got, a)
    else:
        t = got["templates"]
        problems = []
        if sorted(t) != a["ids"] or t["card.examples"].get("text") != a["examplesText"] or \
                got["instructionTemplates"] != a["instruction"]:
            problems.append("card catalog differs from the hand list")
        if any(set(v) - {"profiles", "note", "slots", "text"} for v in t.values()):
            problems.append("a card template has a field outside profiles, note, slots, text")
    for problem in problems:
        report.fail(where, problem)
    if not problems:
        report.ok(f"director vectors ({case['op']})")


def _catalog_problems(ctx, doc: dict, context: dict) -> list:
    """Independent of planner.check: every id a beat names is one the context or the card catalog holds."""
    keepers = {k["keeperId"] for k in context["keepers"]}
    brolls = {b["brollId"] for b in context["brolls"]}
    notes = {n["noteId"] for n in context["notes"]}
    refs = {(r["kind"], r["refId"]) for r in context["references"]}
    p = []
    for b in doc["beats"]:
        if b["keeperId"] is not None and b["keeperId"] not in keepers:
            p.append(f"{b['beatId']}: keeper {b['keeperId']}")
        if b["brollId"] is not None and b["brollId"] not in brolls:
            p.append(f"{b['beatId']}: B-roll {b['brollId']}")
        if b["noteId"] is not None and b["noteId"] not in notes:
            p.append(f"{b['beatId']}: note {b['noteId']}")
        if b["templateId"] is not None and b["templateId"] not in director.CARD_TEMPLATES:
            p.append(f"{b['beatId']}: template {b['templateId']}")
        p += [f"{b['beatId']}: overlay {o}" for o in b["overlays"] if (o["kind"], o["refId"]) not in refs]
    return p


def _plan_problems(ctx, got: dict, a: dict, resolved) -> list:
    if "rejectCode" in a:
        return [] if got.get("rejectCode") == a["rejectCode"] else [f"expected {a['rejectCode']}, got {got}"]
    if "rejectCode" in got:
        return [f"rejected with {got['rejectCode']}"]
    if resolved["op"] == "check":
        return [] if a == {"ok": True, "beats": got["beats"]} else [f"check gave {got}, hand value {a}"]
    if "refusal" in a:
        r = got.get("refusal") or {}
        return [] if [r.get("code"), r.get("message")] == a["refusal"] else [f"refusal {r}, hand value {a['refusal']}"]
    if "refusal" in got:
        return [f"refused: {got['refusal']}"]
    doc, context = got["plan"], resolved["input"]["context"]
    beats = {b["beatId"]: b for b in doc["beats"]}
    have = {"target": doc["durationTargetSeconds"], "beats": [compact(b) for b in doc["beats"]],
            "estimateMs": got["estimate"]["totalMs"], "fallback": got["fallback"], "belowMinimum": got["belowMinimum"],
            "omitted": [o["idea"] for o in doc["omitted"]], "unresolved": doc["unresolved"],
            "effectIntensity": doc["effectIntensity"], "cleanAlternate": doc["cleanAlternate"], "music": doc["music"],
            "comparisons": [list(c["display"].values()) for c in doc["comparisons"]]}
    p = [f"{k}: {have[k]!r}, hand value {a[k]!r}" for k in have if k in a and a[k] != have[k]]
    if "overlays" in a:
        shown = {i: [f"{o['kind']}:{o['refId']}" for o in b["overlays"]] for i, b in beats.items() if b["overlays"]}
        if shown != a["overlays"]:
            p.append(f"overlays {shown}, hand value {a['overlays']}")
    for bid, note in a.get("notes", {}).items():
        if bid not in beats or beats[bid]["noteId"] != note:
            p.append(f"{bid} note is not {note}")
    if any(b["templateId"] in a.get("noTemplates", []) for b in doc["beats"]):
        p.append("an instruction card appears")
    if "arrivalMs" in a:
        arrival = sum(x["ms"] for x, b in zip(got["estimate"]["beats"], doc["beats"]) if b["role"] == "arrival")
        if arrival != a["arrivalMs"]:
            p.append(f"arrival chapter {arrival} ms, hand value {a['arrivalMs']}")
    if sum(x["ms"] for x in got["estimate"]["beats"]) != got["estimate"]["totalMs"]:
        p.append("the estimate does not add up")
    p += [f"schema: {e}" for e in ctx.schemas.validate(doc, "story-brief.schema.json")[:3]]
    p += [f"not a catalog id: {x}" for x in _catalog_problems(ctx, doc, context)]
    if director.lint(ctx.profiles, doc, context):
        p.append("the plan breaks its grammar")
    return p


def check_planner_vector(ctx, case, report, where) -> None:
    if case["op"] == "context":
        problems = _context_problems(ctx, case)
        for problem in problems:
            report.fail(where, problem)
        if not problems:
            report.ok("planner vectors (context)")
        return
    resolved = _resolved(ctx, case)
    snapshot = copy.deepcopy(resolved)
    got = planner.run_vector(ctx.profiles, resolved)
    if got != case["expect"]:
        report.fail(where, "reference output differs from the stored expectation")
        return
    problems = _plan_problems(ctx, got, case["assert"], resolved)
    if resolved != snapshot:
        problems.append("the planner changed its input")
    if case["op"] == "plan" and "plan" in got:
        again = planner.run_vector(ctx.profiles, copy.deepcopy(snapshot))
        if canonical_bytes(again["plan"]) != canonical_bytes(got["plan"]):
            problems.append("planning the same brief twice gave different canonical JSON")
        else:
            report.ok("planner determinism (same brief, byte-identical canonical JSON)")
    for problem in problems:
        report.fail(where, problem)
    if not problems:
        report.ok(f"planner vectors ({case['op']})")


VECTOR_CHECKERS = {DIRECTOR: check_director_vector, PLANNER: check_planner_vector}


# ----- self-tests ---------------------------------------------------------------------------------------------------

def check_matrix(ctx, report) -> None:
    """Every profile x {3min, 5min, full} has a planner vector on the unpatched Sample context, and each either plans
    a lint-clean StoryPlan or is a length the profile refuses (story 119)."""
    cases = {c["id"]: c for c in ctx.fixture(VECTORS[PLANNER])["cases"]}
    problems, planned = [], 0
    for profile in PROFILE_IDS:
        for length in director.LENGTH_KEYS:
            c = cases.get(f"{profile}-{length}")
            if c is None or c["contextPatch"] or c["input"]["options"] != {"length": length}:
                problems.append(f"no unpatched vector for {profile} x {length}")
                continue
            got = c["expect"]
            if "plan" in got:
                planned += 1
            elif got.get("refusal", {}).get("code") != "lengthUnavailable":
                problems.append(f"{profile} x {length} neither plans nor refuses the length")
    for problem in problems:
        report.fail("planner matrix", problem)
    if not problems:
        report.ok("planner matrix (profile x length) plans", planned)


SELF_TESTS = {"planner-matrix": check_matrix}
