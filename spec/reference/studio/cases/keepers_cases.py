"""Keeper selection and ranking vectors (`keepers`) and staleness propagation vectors (`staleness`), with their
checkers. Module page: spec/studio/modules/keepers.md.

Inputs come from the Sample project (records/sync-map.json, source-manifest.json, the edit plans and the delivered
film) and from the core Jon vs Alex fixture (spec/fixtures/sample/jon-vs-alex.session.json, folded by the core
reference jovra_ref.scoring.fold). "expect" comes from the reference (keepers.py, staleness.py); every "assert" block is
a hand-derived literal (worked from the spec, the stories and the raw log times) that the checker compares
independently of the reference.
"""

from __future__ import annotations

import csv
import json

from studio import keepers, staleness
from studio.core import canonical_sha256

import generate_studio_fixtures as g

JVA_SESSION = "spec/fixtures/sample/jon-vs-alex.session.json"
JVA_CSV = "spec/fixtures/sample/jon-vs-alex.points.csv"
JVA_FIRST = "3a24700f-0a33-528d-8bf6-851e1b3e23b7"     # log seq 1: tStartMs 0, tEndMs 3014
JVA_P42 = "787834ed-9edc-5024-b62c-b36f790eac7e"       # log seq 42: tStartMs 1103730
JVA_LAST = "bfee0b5d-d021-59e7-a55c-9e1f2bb1ab46"      # log seq 124: tStartMs 3228736, tEndMs 3240000 (match point)
JVA_MARK = "3f8f7619-45ef-5e3c-9897-e22c17cf7ee5"      # tMs 1103730, "Sample: check this point"
JVA_DURATION_US = 3_240_000_000                        # recording.durationMs 3240000
MINUTE_US = 60_000_000
OTHER = "other-court-day"


# ----- shared inputs ------------------------------------------------------------------------------

def sample_sources(manifest: dict, smap: dict) -> list:
    """The Sample project's match sources as keeper inputs (the sync piece's state and transform, the render proxy)."""
    pieces = {s["sourceId"]: s["pieces"][0] for s in smap["sources"]}
    out = []
    for src in manifest["sources"]:
        if src["role"] != "match":
            continue
        proxy = [p for p in src["proxies"] if p["class"] == "render"][0]
        piece = pieces[src["sourceId"]]
        out.append({"sourceId": src["sourceId"], "isPrimary": src["isPrimary"], "syncState": piece["state"],
                    "transform": piece["transform"], "fps": proxy["fps"], "frameCount": proxy["frameCount"]})
    return out


def _load(root, rel):
    return json.loads((root / rel).read_text(encoding="utf-8"))


def resolve_project(project: dict, root) -> dict:
    """A vector's project input as candidates() takes it: a `coreFold` entry is replaced by the points of the core
    fold of that session file (or of an inline setup and log), on a session clock starting at sessionStartUs."""
    from jovra_ref import scoring
    out = {k: v for k, v in project.items() if k != "coreFold"}
    fold = project.get("coreFold")
    if fold is not None:
        if "session" in fold:
            s = _load(root, fold["session"])
            setup = {"format": s["match"]["format"], "players": s["players"], "sides": s["sides"],
                     "toss": s["match"]["toss"]}
            log = s["match"]["log"]
        else:
            setup, log = fold["setup"], fold["log"]
        out["points"] = keepers.points_from_fold(scoring.fold(setup, log), fold["sessionStartUs"]) + project["points"]
    return out


def jva_setup(root) -> dict:
    s = _load(root, JVA_SESSION)
    return {"format": s["match"]["format"], "players": s["players"], "sides": s["sides"], "toss": s["match"]["toss"]}


def point(eid, start_s10, end_s10, index=0, rally=None, prov="reviewed", source=None, bp=False, sp=False, mp=False):
    """A point input; times in tenths of a second on the session clock."""
    return {"eventId": eid, "index": index, "startUs": start_s10 * 100_000, "endUs": end_s10 * 100_000,
            "rallyLength": rally, "provenance": prov, "breakPoint": bp, "setPoint": sp, "matchPoint": mp,
            "sourceId": source}


def shot(eid, at_s10, prov):
    return {"eventId": eid, "atUs": at_s10 * 100_000, "provenance": prov}


def project(points=(), *, sources=(), shots=(), marks=(), clips=(), duration=MINUTE_US, core=None):
    p = {"sessionDurationUs": duration, "sources": list(sources), "points": list(points), "shots": list(shots),
         "marks": list(marks), "lessonClips": list(clips)}
    if core is not None:
        p["coreFold"] = core
    return p


RANK_POINTS = [
    point("p1", 100, 140, 0, rally=3, prov="manual"),
    point("p2", 200, 240, 1, rally=12),
    point("p3", 300, 340, 2, rally=7, prov="estimated"),
    point("p4", 400, 440, 3, rally=2, bp=True),
    point("p5", 500, 540, 4, rally=9, prov="manual"),
    point("p6", 600, 640, 5, rally=None, mp=True),
]


def rank_project(marks=()):
    return project(RANK_POINTS, marks=marks,
                   clips=[{"clipId": "clip-p1", "lessonId": "lesson-0909", "eventId": "p1", "window": None}])


# ----- keepers vectors --------------------------------------------------------------------------------------------

def keeper_vectors(sample, root) -> dict:
    src = sample_sources(sample.manifest, sample.smap)
    cam1 = [s for s in src if s["sourceId"] == "camera-1"]
    jva = {"session": JVA_SESSION, "sessionStartUs": 0}
    jva_mark = {"markId": JVA_MARK, "atUs": 1_103_730_000, "note": "Sample: check this point"}
    rows = list(csv.DictReader((root / JVA_CSV).open(encoding="utf-8")))
    break_points = [r["point_id"] for r in rows if r["break_point"] == "true"]
    cases = []

    def cand(cid, why, proj, assertions):
        c = {"id": cid, "why": why, "op": "candidates", "input": {"project": proj}}
        c["expect"] = keepers.run_vector(c, resolve_project(proj, root))
        c["assert"] = assertions
        cases.append(c)

    def rank(cid, why, proj, profile, options, assertions):
        c = {"id": cid, "why": why, "op": "rank", "input": {"project": proj, "profileId": profile, "options": options}}
        c["expect"] = keepers.run_vector(c, resolve_project(proj, root))
        c["assert"] = assertions
        cases.append(c)

    cand("jon-vs-alex-one-per-point", "Story 102: one keeper per effective point of the core Jon vs Alex fold (124 "
         "points); the Mark at 18:23.730 lands on point 42 and is counted once",
         project(marks=[jva_mark], duration=JVA_DURATION_US, core=jva),
         {"keeperCount": 124, "origins": {"point": 124}, "eventRefsUnique": True,
          "sessions": {"k-" + JVA_FIRST: [0, 5_514_000], "k-" + JVA_LAST: [3_227_236_000, 3_240_000_000]},
          "markOn": {JVA_MARK: "k-" + JVA_P42}})
    setup = jva_setup(root)
    voided = [
        {"id": "v-1", "seq": 1, "type": "point", "tStartMs": 1000, "tEndMs": 4000,
         "reviewed": {"winner": "A", "endType": "winner", "provenance": "manual", "source": "user"}},
        {"id": "v-2", "seq": 2, "type": "point", "tStartMs": 20000, "tEndMs": 24000,
         "reviewed": {"winner": "A", "endType": "winner", "provenance": "manual", "source": "user"}},
        {"id": "v-3", "seq": 3, "type": "point", "tStartMs": 40000, "tEndMs": 44000,
         "reviewed": {"winner": "B", "endType": "winner", "provenance": "manual", "source": "user"}},
        {"id": "v-4", "seq": 4, "type": "void", "target": "v-2"},
    ]
    cand("voided-point-is-not-a-keeper", "A voided point is not an effective point, so it is not a keeper",
         project(core={"setup": setup, "log": voided, "sessionStartUs": 0}),
         {"keeperCount": 2, "absentEventIds": ["v-2"], "sessions": {"k-v-1": [0, 6_500_000],
                                                                    "k-v-3": [38_500_000, 46_500_000]}})
    cand("default-pre-and-post-roll", "Story 104: 10.0-14.0 s gets 1.5 s before and 2.5 s after: 8.5-16.5 s, "
         "frames 510-990 at 60 fps on Camera 1",
         project([point("e-1", 100, 140)], sources=cam1),
         {"keeperCount": 1, "sessions": {"k-e-1": [8_500_000, 16_500_000]},
          "views": {"k-e-1": [["camera-1", 510, 990, True]]}})
    cand("clamped-to-the-session", "Rolls never reach outside the session: 0.5-3.0 s starts at 0, 56.0-59.0 s ends "
         "at 60 s", project([point("e-1", 5, 30, 0), point("e-2", 560, 590, 1)]),
         {"keeperCount": 2, "sessions": {"k-e-1": [0, 5_500_000], "k-e-2": [54_500_000, 60_000_000]}})
    cand("same-point-two-angles-one-keeper", "Story 107: point p-003 scored from Camera 1 (12.0-19.5 s) and from "
         "Camera 2 (12.2-19.6 s) is one keeper with two views; Camera 3's sync needs review, so it offers no view",
         project([point("p-003", 120, 195, source="camera-1"), point("p-003", 122, 196, source="camera-2")],
                 sources=src, duration=g.HOUR_US),
         {"keeperCount": 1, "sessions": {"k-p-003": [10_500_000, 22_100_000]},
          "viewSources": {"k-p-003": ["camera-1", "camera-2"]}, "primary": {"k-p-003": "camera-1"},
          "seenFrom": {"k-p-003": ["camera-1", "camera-2"]},
          "views": {"k-p-003": [["camera-1", 630, 1326, True]]}})
    cand("angle-without-coverage-has-no-view", "Camera 2 starts 0.12 s into the session, so a point at 0.0-2.0 s "
         "(window 0-4.5 s) has only the Camera 1 view",
         project([point("e-1", 0, 20)], sources=src, duration=g.HOUR_US),
         {"viewSources": {"k-e-1": ["camera-1"]}, "primary": {"k-e-1": "camera-1"}})
    cand("primary-angle-missing", "Camera 1 ends at 3600 s; a point at 3597-3599 s (window 3595.5-3601 s) is seen "
         "only by Camera 2, which becomes the primary view",
         project([point("e-1", 35970, 35990)], sources=src, duration=3_601_000_000),
         {"sessions": {"k-e-1": [3_595_500_000, 3_601_000_000]}, "viewSources": {"k-e-1": ["camera-2"]},
          "primary": {"k-e-1": "camera-2"}})
    cand("reviewed-contacts-widen-the-window", "Reviewed contacts at 19.9 s and 23.9 s protect 19.65-20.15 s and "
         "23.65-24.15 s, so the 20.0-24.0 s point is kept from 18.15 s to 26.65 s",
         project([point("e-1", 200, 240)], shots=[shot("e-1", 199, "reviewed"), shot("e-1", 239, "reviewed")],
                 sources=cam1),
         {"sessions": {"k-e-1": [18_150_000, 26_650_000]},
          "contacts": {"k-e-1": [[19_900_000, "reviewed", None, 19_650_000, 20_150_000],
                                 [23_900_000, "reviewed", None, 23_650_000, 24_150_000]]}})
    cand("estimated-hit-inside-reviewed-window", "An estimated hit at 31.1 s inside the reviewed contact window "
         "30.75-31.25 s keeps the reviewed window unchanged",
         project([point("e-1", 300, 340)], shots=[shot("e-1", 311, "estimated"), shot("e-1", 310, "reviewed")],
                 sources=cam1),
         {"contacts": {"k-e-1": [[31_000_000, "reviewed", None, 30_750_000, 31_250_000]]},
          "sessions": {"k-e-1": [28_500_000, 36_500_000]}})
    cand("estimated-hit-outside-is-labelled", "An estimated hit at 32.0 s away from the reviewed contact stays, "
         "labelled Estimated, with the same 0.5 s protection (never less)",
         project([point("e-1", 300, 340)], shots=[shot("e-1", 310, "reviewed"), shot("e-1", 320, "estimated")],
                 sources=cam1),
         {"contacts": {"k-e-1": [[31_000_000, "reviewed", None, 30_750_000, 31_250_000],
                                 [32_000_000, "estimated", "Estimated", 31_750_000, 32_250_000]]}})
    cand("mark-on-a-point-and-mark-alone", "A Mark at 12.0 s inside point 10.0-14.0 s is that keeper; a Mark at "
         "40.0 s outside every point is its own keeper, 38.5-42.5 s",
         project([point("e-1", 100, 140)], marks=[{"markId": "m-1", "atUs": 12_000_000, "note": None},
                                                  {"markId": "m-2", "atUs": 40_000_000, "note": None}]),
         {"keeperCount": 2, "origins": {"point": 1, "mark": 1}, "markOn": {"m-1": "k-e-1", "m-2": "k-m-2"},
          "sessions": {"k-m-2": [38_500_000, 42_500_000]}})
    cand("lesson-clips", "A lesson clip on a point links to that keeper; a clip with its own window (50.0-52.0 s) is "
         "its own keeper; a clip with neither cannot be placed",
         project([point("e-1", 100, 140)],
                 clips=[{"clipId": "c-1", "lessonId": "lesson-1007", "eventId": "e-1", "window": None},
                        {"clipId": "c-2", "lessonId": "lesson-1007", "eventId": None,
                         "window": {"startUs": 50_000_000, "endUs": 52_000_000}},
                        {"clipId": "c-3", "lessonId": "lesson-1007", "eventId": None, "window": None}]),
         {"keeperCount": 2, "origins": {"point": 1, "lesson-clip": 1}, "lessonOn": {"c-1": "k-e-1", "c-2": "k-c-2"},
          "sessions": {"k-c-2": [48_500_000, 54_500_000]}, "unplaced": [["c-3", "noWindow"]]})
    cand("shot-for-unknown-event", "A contact for an event that is not a point is not placed",
         project([point("e-1", 100, 140)], shots=[shot("e-9", 120, "reviewed")]),
         {"keeperCount": 1, "unplaced": [["e-9", "unknownEvent"]], "contacts": {"k-e-1": []}})

    rp = rank_project()
    rank("rally-pulse-order", "Rally Pulse: break, set and match points first, then the longest real rallies; the "
         "estimated 7-shot rally is not real", rp, "rally-pulse", {},
         {"order": ["k-p4", "k-p6", "k-p2", "k-p5", "k-p1"]})
    rank("rally-pulse-limit", "A limit keeps the head of the same order", rp, "rally-pulse", {"limit": 3},
         {"order": ["k-p4", "k-p6", "k-p2"]})
    rank("coach-cut-order", "Coach's Cut: keepers linked to a reviewed cue first, then keepers linked to a lesson; "
         "an estimated cue links nothing", rp, "coach-cut",
         {"cues": [{"cueId": "cue-a", "keeperId": "k-p5", "provenance": "reviewed"},
                   {"cueId": "cue-b", "keeperId": "k-p2", "provenance": "estimated"}]},
         {"order": ["k-p5", "k-p1"]})
    rank("match-broadcast-all-in-order", "Match Broadcast: every point, in order", rp, "match-broadcast", {},
         {"order": ["k-p1", "k-p2", "k-p3", "k-p4", "k-p5", "k-p6"]})
    rank("excluded-keeper-never-offered", "Story 108: an excluded keeper is in no profile's order", rp,
         "match-broadcast", {"excluded": ["k-p2"]}, {"order": ["k-p1", "k-p3", "k-p4", "k-p5", "k-p6"]})
    dates = {"k-p1": "2026-09-09", "k-p2": "2026-09-09", "k-p4": "2026-10-07", "k-p5": "2026-10-07"}
    rank("progress-all", "Progress Story, selection all: every dated example, by date", rp, "progress-story",
         {"dates": dates, "selectionRule": "all", "comparable": True},
         {"order": ["k-p1", "k-p2", "k-p4", "k-p5"], "label": None})
    rank("progress-user-chosen", "Story 136: hand-picked examples are labelled", rp, "progress-story",
         {"dates": dates, "selectionRule": "user-chosen", "chosen": ["k-p5", "k-p1"], "comparable": True},
         {"order": ["k-p1", "k-p5"], "label": "Examples you chose"})
    rank("progress-seeded-random", "A seeded random pick of two dated examples, shown by date", rp, "progress-story",
         {"dates": dates, "selectionRule": "seeded-random", "seed": 20261006, "count": 2, "comparable": True},
         {"orderSize": 2, "orderWithin": sorted(dates), "orderByDate": dates})
    rank("progress-no-comparable-evidence", "Story 137: without comparable evidence the film is a lesson "
         "chronology", rp, "progress-story", {"dates": dates, "selectionRule": "all", "comparable": False},
         {"order": ["k-p1"], "fallback": "lesson-chronology"})
    rank("court-memories-chapters", "Court Memories: arrival B-roll, then match moments (marked, lesson-linked, "
         "break, set or match points) by time, then after B-roll", rank_project(
             marks=[{"markId": "m-1", "atUs": 21_000_000, "note": None}]), "court-memories",
         {"brolls": [{"brollId": "b-02", "chapter": "after"}, {"brollId": "b-01", "chapter": "arrival"}]},
         {"order": ["b-01", "k-p1", "k-p2", "k-p4", "k-p6", "b-02"], "missing": []})
    rank("court-memories-says-what-is-missing", "Story 120: with no B-roll the film says what is missing", rp,
         "court-memories", {"brolls": []}, {"missing": ["arrival-broll", "after-broll"]})
    full = project(marks=[jva_mark], duration=JVA_DURATION_US, core=jva)
    rank("jon-vs-alex-broadcast", "Match Broadcast over the Jon vs Alex fold: 124 points from the first to the "
         "last", full, "match-broadcast", {},
         {"orderSize": 124, "first": "k-" + JVA_FIRST, "last": "k-" + JVA_LAST})
    rank("jon-vs-alex-rally-pulse", "Rally Pulse over the fold: every rally is manual or reviewed with a length "
         "(core CSV), so all 124 rank; the 13 break points (core CSV) and the match point rank before every point "
         "without pressure", full, "rally-pulse", {},
         {"orderSize": 124, "beforeNoPressure": ["k-" + i for i in break_points] + ["k-" + JVA_LAST]})
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "keepers",
            "status": "expect from spec/reference/studio/keepers.py; assert blocks hand-derived literals from the spec, "
                      "the stories and the raw core log", "cases": cases}


# ----- staleness vectors ------------------------------------------------------------------------------------------

SAMPLE_PLANS = ("coach-cut-serve", "court-memories-final", "court-memories-storyboard",
                "court-memories-storyboard.clean", "match-broadcast-set-1", "rally-pulse-portrait",
                "rally-pulse-portrait.clean")
ALL_SAMPLE_PLAN_IDS = ["coach-cut-serve", "court-memories-final", "court-memories-storyboard",
                       "court-memories-storyboard-clean", "match-broadcast-set-1", "rally-pulse-portrait",
                       "rally-pulse-portrait-clean"]


def staleness_vectors(sample) -> dict:
    r = sample.records
    plans = [dict(staleness.plan_dependencies(r[f"records/edit-plan.{name}.json"]),
                  fromRecord=f"records/edit-plan.{name}.json") for name in SAMPLE_PLANS]
    film = dict(staleness.film_dependencies(r["records/delivered-artifact.film.json"]),
                fromRecord="records/delivered-artifact.film.json")
    one_angle = {"planId": "one-angle-excerpt", "planRevision": 1, "projectId": g.PROJECT,
                 "editPlanSha256": g.fake_sha("one-angle-excerpt"),
                 "bindings": {"eventRevision": g.EVENT_REVISION, "syncRevision": g.SYNC_REVISION,
                              "keeperCatalogRevision": g.KEEPER_REVISION},
                 "sourceIds": ["camera-1"], "keeperIds": ["k-02"], "fromRecord": None}
    other_plan = {"planId": "other-coach-cut", "planRevision": 1, "projectId": OTHER,
                  "editPlanSha256": g.fake_sha("other-coach-cut"),
                  "bindings": {"eventRevision": 1, "syncRevision": 1, "keeperCatalogRevision": 1},
                  "sourceIds": ["camera-1"], "keeperIds": ["k-01"], "fromRecord": None}
    other_film = {"artifactId": "film-other", "projectId": OTHER, "editPlanSha256": other_plan["editPlanSha256"],
                  "stale": False, "fromRecord": None}
    projects = {g.PROJECT: {"eventRevision": g.EVENT_REVISION, "syncRevision": g.SYNC_REVISION,
                            "keeperCatalogRevision": g.KEEPER_REVISION},
                OTHER: {"eventRevision": 1, "syncRevision": 1, "keeperCatalogRevision": 1}}
    cases = []

    def case(cid, why, changes, assertions, extra_plans=(), films=None):
        state = {"projects": projects, "plans": plans + list(extra_plans),
                 "films": [film] if films is None else films}
        c = {"id": cid, "why": why, "input": {"state": state, "changes": changes}}
        c["expect"] = staleness.run_vector(c)
        c["assert"] = assertions
        cases.append(c)

    def change(kind, revision, project=g.PROJECT, **named):
        return dict({"kind": kind, "projectId": project, "revision": revision}, **named)

    case("event-revision-stales-the-project", "Story 231: correcting a point (event revision 3 to 4) stales every plan "
         "of the project and its film, labelled and kept; the other project's plan and film stay current",
         [change("event", 4, changedPointIds=["p-003"])],
         {"stalePlanIds": ALL_SAMPLE_PLAN_IDS, "staleFilmIds": ["film-court-memories"],
          "currentPlanIds": ["other-coach-cut"], "currentFilmIds": ["film-other"],
          "filmLabels": {"film-court-memories": "Made before a correction", "film-other": None}},
         extra_plans=[other_plan], films=[film, other_film])
    case("sync-camera-2-spares-a-camera-1-plan", "A sync change on Camera 2 (revision 2 to 3) stales every plan that "
         "cuts or plays Camera 2; the one-angle plan on Camera 1 stays current, carried to sync revision 3",
         [change("sync", 3, sourceIds=["camera-2"])],
         {"stalePlanIds": ALL_SAMPLE_PLAN_IDS, "currentPlanIds": ["one-angle-excerpt"],
          "bindings": {"one-angle-excerpt": {"eventRevision": 3, "syncRevision": 3, "keeperCatalogRevision": 1}},
          "staleFilmIds": ["film-court-memories"]}, extra_plans=[one_angle])
    case("sync-camera-1-stales-every-plan-using-it", "A sync change on Camera 1 stales every plan, the one-angle plan "
         "too", [change("sync", 3, sourceIds=["camera-1"])],
         {"stalePlanIds": sorted(ALL_SAMPLE_PLAN_IDS + ["one-angle-excerpt"]), "currentPlanIds": []},
         extra_plans=[one_angle])
    case("keeper-k04-change", "Changing keeper k-04 (catalog revision 1 to 2) stales the plans that use it; the final "
         "film's plan does not use it, so the plan is carried to revision 2 and the film stays current",
         [change("keepers", 2, keeperIds=["k-04"])],
         {"stalePlanIds": ["coach-cut-serve", "court-memories-storyboard", "court-memories-storyboard-clean",
                           "rally-pulse-portrait", "rally-pulse-portrait-clean"],
          "currentPlanIds": ["court-memories-final", "match-broadcast-set-1"],
          "bindings": {"court-memories-final": {"eventRevision": 3, "syncRevision": 2, "keeperCatalogRevision": 2}},
          "staleFilmIds": [], "filmLabels": {"film-court-memories": None}})
    case("keeper-k01-change-stales-the-film", "Changing keeper k-01 stales the two storyboards and the final plan, so "
         "the delivered film is made before a correction",
         [change("keepers", 2, keeperIds=["k-01"])],
         {"stalePlanIds": ["court-memories-final", "court-memories-storyboard", "court-memories-storyboard-clean"],
          "staleFilmIds": ["film-court-memories"], "filmReasons": {"film-court-memories": ["keeper-revision"]}})
    case("keeper-then-event", "Two changes in order: keeper k-04, then a point correction; every plan is stale and "
         "each lists the reasons that apply",
         [change("keepers", 2, keeperIds=["k-04"]), change("event", 4)],
         {"stalePlanIds": ALL_SAMPLE_PLAN_IDS,
          "planReasons": {"court-memories-final": ["event-revision"],
                          "coach-cut-serve": ["event-revision", "keeper-revision"]},
          "current": {"eventRevision": 4, "syncRevision": 2, "keeperCatalogRevision": 2}})
    case("old-version-kept", "A film already made before an earlier correction stays a labelled version; a change "
         "that spares its plan neither deletes nor relabels anything",
         [change("keepers", 2, keeperIds=["k-04"])],
         {"staleFilmIds": ["film-court-memories-v1"], "currentFilmIds": ["film-court-memories"],
          "filmLabels": {"film-court-memories-v1": "Made before a correction", "film-court-memories": None},
          "keptAsVersion": True},
         films=[film, dict(film, artifactId="film-court-memories-v1", stale=True, fromRecord=None)])
    case("revision-must-increase", "Revisions only move forward: event revision 3 is already current",
         [change("event", 3)], {"rejectCode": "revisionNotIncreasing"})
    case("film-without-its-plan", "A film whose plan is not listed cannot be judged",
         [change("event", 4)], {"rejectCode": "unknownPlan"},
         films=[dict(film, editPlanSha256=g.fake_sha("missing-plan"), fromRecord=None)])
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "staleness",
            "status": "expect from spec/reference/studio/staleness.py; plan and film inputs derived from the Sample "
                      "records (fromRecord) or hand-written; assert blocks are hand-derived literals", "cases": cases}


def fixtures(sample):
    return {"vectors/keepers.json": keeper_vectors(sample, g.ROOT),
            "vectors/staleness.json": staleness_vectors(sample)}


# ----- checkers ---------------------------------------------------------------------------------------------------

def _keeper_problems(got: dict, a: dict, fold_pressure) -> list:
    if "rejectCode" in got:
        return [f"rejected with {got['rejectCode']}"]
    p = []
    if "order" in got:
        ids = [i["id"] for i in got["order"]]
        for key, value in (("order", ids), ("label", got["label"]), ("fallback", got["fallback"]),
                           ("missing", got["missing"])):
            if key in a and a[key] != value:
                p.append(f"{key}: {value}, hand value {a[key]}")
        if "orderSize" in a and len(ids) != a["orderSize"]:
            p.append(f"order has {len(ids)} items, hand value {a['orderSize']}")
        if "orderWithin" in a and not set(ids) <= set(a["orderWithin"]):
            p.append(f"order {ids} leaves {a['orderWithin']}")
        if "orderByDate" in a:
            days = [a["orderByDate"][i] for i in ids]
            if days != sorted(days):
                p.append("examples are not in date order")
        if "first" in a and (not ids or ids[0] != a["first"] or ids[-1] != a["last"]):
            p.append("first or last item differs")
        if "beforeNoPressure" in a:
            cut = next((n for n, i in enumerate(ids) if i not in fold_pressure), len(ids))
            late = [i for i in a["beforeNoPressure"] if i not in ids[:cut]]
            if late:
                p.append(f"{len(late)} pressure points rank after a point without pressure")
        return p
    ks = {k["keeperId"]: k for k in got["keepers"]}
    if "keeperCount" in a and len(ks) != a["keeperCount"]:
        p.append(f"{len(ks)} keepers, hand value {a['keeperCount']}")
    if "origins" in a:
        counts: dict = {}
        for k in ks.values():
            counts[k["origin"]] = counts.get(k["origin"], 0) + 1
        if counts != a["origins"]:
            p.append(f"origins {counts}")
    if a.get("eventRefsUnique"):
        refs = [e for k in ks.values() for e in k["eventRefs"]]
        if len(refs) != len(set(refs)):
            p.append("an event is in two keepers")
    for kid, (start, end) in a.get("sessions", {}).items():
        k = ks.get(kid)
        if k is None or [k["session"]["startUs"], k["session"]["endUs"]] != [start, end]:
            p.append(f"{kid} session {k and k['session']}, hand value {[start, end]}")
    for kid, sids in a.get("viewSources", {}).items():
        if kid not in ks or [v["sourceId"] for v in ks[kid]["views"]] != sids:
            p.append(f"{kid} views differ from {sids}")
    for kid, sid in a.get("primary", {}).items():
        if kid not in ks or [v["sourceId"] for v in ks[kid]["views"] if v["primary"]] != [sid]:
            p.append(f"{kid} primary is not {sid}")
    for kid, sids in a.get("seenFrom", {}).items():
        if kid not in ks or ks[kid]["seenFrom"] != sids:
            p.append(f"{kid} seen from differs")
    for kid, views in a.get("views", {}).items():
        have = {v["sourceId"]: [v["sourceId"], v["window"]["inFrame"], v["window"]["outFrame"], v["primary"]]
                for v in ks.get(kid, {"views": []})["views"]}
        for want in views:
            if have.get(want[0]) != want:
                p.append(f"{kid} view {have.get(want[0])}, hand value {want}")
    for kid, contacts in a.get("contacts", {}).items():
        have = [[c["atUs"], c["provenance"], c["label"], c["protect"]["startUs"], c["protect"]["endUs"]]
                for c in ks.get(kid, {"contacts": []})["contacts"]]
        if have != contacts:
            p.append(f"{kid} contacts {have}, hand value {contacts}")
    for mark, kid in a.get("markOn", {}).items():
        if kid not in ks or mark not in ks[kid]["markIds"]:
            p.append(f"mark {mark} is not on {kid}")
    for clip, kid in a.get("lessonOn", {}).items():
        if kid not in ks or clip not in ks[kid]["lessonClipIds"]:
            p.append(f"lesson clip {clip} is not on {kid}")
    for eid in a.get("absentEventIds", []):
        if any(eid in k["eventRefs"] for k in ks.values()):
            p.append(f"{eid} is a keeper")
    if "unplaced" in a and [[u["id"], u["reason"]] for u in got["unplaced"]] != a["unplaced"]:
        p.append(f"unplaced {got['unplaced']}")
    return p


def _fold_pressure(ctx) -> set:
    """Keeper ids of Jon vs Alex points the core fold marks as break, set or match points (an oracle outside
    keepers.py, used only by the rally-pulse ordering assertion)."""
    from jovra_ref import scoring
    s = ctx.load(JVA_SESSION)
    setup = {"format": s["match"]["format"], "players": s["players"], "sides": s["sides"], "toss": s["match"]["toss"]}
    out = set()
    for p in scoring.fold(setup, s["match"]["log"])["points"]:
        pr = p["pressure"] or {}
        if pr.get("breakPoint") or pr.get("setPointFor") or pr.get("matchPointFor"):
            out.add("k-" + p["id"])
    return out


def check_keeper_vector(ctx, case, report, where) -> None:
    got = keepers.run_vector(case, resolve_project(case["input"]["project"], ctx.root))
    if got != case["expect"]:
        report.fail(where, "reference output differs from the stored expectation")
        return
    problems = _keeper_problems(got, case["assert"], _fold_pressure(ctx) if "beforeNoPressure" in case["assert"] else set())
    for problem in problems:
        report.fail(where, problem)
    if not problems:
        report.ok("keepers vectors")


def _staleness_problems(ctx, case, got: dict) -> list:
    a = case["assert"]
    if "rejectCode" in a:
        return [] if got.get("rejectCode") == a["rejectCode"] else [f"expected {a['rejectCode']}, got {got}"]
    if "rejectCode" in got:
        return [f"rejected with {got['rejectCode']}"]
    p = []
    plans = {x["planId"]: x for x in got["plans"]}
    films = {x["artifactId"]: x for x in got["films"]}
    for key, value in (("stalePlanIds", got["stalePlanIds"]), ("staleFilmIds", got["staleFilmIds"]),
                       ("current", got["current"].get(g.PROJECT))):
        if key in a and a[key] != value:
            p.append(f"{key}: {value}, hand value {a[key]}")
    if "currentPlanIds" in a and sorted(i for i, x in plans.items() if x["status"] == "current") != a["currentPlanIds"]:
        p.append("current plans differ")
    if "currentFilmIds" in a and sorted(i for i, x in films.items() if x["status"] == "current") != a["currentFilmIds"]:
        p.append("current films differ")
    for pid, bindings in a.get("bindings", {}).items():
        if plans[pid]["bindings"] != bindings:
            p.append(f"{pid} bindings {plans[pid]['bindings']}")
    for pid, reasons in a.get("planReasons", {}).items():
        if plans[pid]["reasons"] != reasons:
            p.append(f"{pid} reasons {plans[pid]['reasons']}")
    for fid, reasons in a.get("filmReasons", {}).items():
        if films[fid]["reasons"] != reasons:
            p.append(f"{fid} reasons {films[fid]['reasons']}")
    for fid, label in a.get("filmLabels", {}).items():
        if films[fid]["label"] != label:
            p.append(f"{fid} label {films[fid]['label']!r}")
    if not all(f["keptAsVersion"] for f in got["films"]) or len(got["films"]) != len(case["input"]["state"]["films"]):
        p.append("a film was dropped")
    return p


def check_staleness_vector(ctx, case, report, where) -> None:
    for dep in case["input"]["state"]["plans"] + case["input"]["state"]["films"]:
        rel = dep.get("fromRecord")
        if rel is None:
            continue
        doc = ctx.fixture(rel)
        derived = staleness.plan_dependencies(doc) if "planId" in dep else staleness.film_dependencies(doc)
        if dict(derived, fromRecord=rel) != dep:
            report.fail(where, f"input derived from {rel} is out of date")
            return
    got = staleness.run_vector(case)
    if got != case["expect"]:
        report.fail(where, "reference output differs from the stored expectation")
        return
    problems = _staleness_problems(ctx, case, got)
    for problem in problems:
        report.fail(where, problem)
    if not problems:
        report.ok("staleness vectors")


VECTOR_CHECKERS = {"keepers": check_keeper_vector, "staleness": check_staleness_vector}


# ----- self-tests ---------------------------------------------------------------------------------------------------

def check_sample_catalog_contacts(ctx, report) -> None:
    """The Sample keeper catalog's views follow the same frame rule: each stored view of a keeper fits inside the
    recording of its source, and the film's plan hash is the canonical hash of the final plan (what staleness keys on)."""
    sources = {s["sourceId"]: s for s in sample_sources(ctx.bundle["manifest"], ctx.bundle["syncMap"])}
    problems = []
    for k in ctx.bundle["keepers"]["keepers"]:
        for v in k["views"]:
            src = sources[v["sourceId"]]
            if not 0 <= v["window"]["inFrame"] < v["window"]["outFrame"] <= src["frameCount"]:
                problems.append(f"{k['keeperId']} view on {v['sourceId']} is outside the recording")
    final = ctx.records["edit-plan.court-memories-final"]
    if ctx.records["delivered-artifact.film"]["bindings"]["editPlanSha256"] != canonical_sha256(final):
        problems.append("the Sample film does not bind the final plan's canonical hash")
    for problem in problems:
        report.fail("keepers self-test", problem)
    if not problems:
        report.ok("keepers self-tests")


SELF_TESTS = {"keepers-sample-catalog": check_sample_catalog_contacts}
