"""EDLCompiler vectors (`compile`) and their checker. Module page: spec/studio/modules/compile.md.

Every case names a base compile context (one of the file's `context` cases) and patches it, names how its StoryPlan
was made (`planFrom`: the RulesPlanner on the patched context, or a Sample record with a `planPatch`) and stores that
plan inline, so a port reads one case and compiles one plan. The checker re-derives the contexts from the Sample
records and the synthetic builders below, re-plans every plan, recompiles it twice (the determinism check), validates
the EDL with `edl.validate` and the edit-plan schema, and checks the hand-derived `assert` block. Every literal in an
`assert` block is worked by hand from the keeper windows, the profile grammar and the rules on the module page, never
copied from the reference output.
"""

from __future__ import annotations

import copy
import hashlib
from fractions import Fraction

from studio import bundle, director, edl, planner
from studio import compile as compiler
from studio.cases.planner_cases import record_names, sample_context
from studio.core import Reject, apply_patch, canonical_bytes, canonical_sha256, require

KIND = "compile"
VECTOR = "vectors/compile.json"
PROFILE_IDS = ("coach-cut", "match-broadcast", "rally-pulse", "progress-story", "court-memories")
SAMPLE = "context-sample-court-day"
ONE_60, ONE_30, ONE_720, ONE_GAP = ("context-one-camera-60", "context-one-camera-30", "context-one-camera-720p",
                                    "context-one-camera-restart")
FPS30 = {"fps": {"num": 30, "den": 1}}


# ----- compile contexts ---------------------------------------------------------------------------------------------

def sample_compile_context(records: dict) -> dict:
    """The sample-court-day compile context: the planning context plus the trusted EDL context (bundle.edl_context),
    the media index (primary, angle slots, keeper views, B-roll windows), stage S2 (the project is multi-camera) and a
    renderer that supports every SD6b operation."""
    r = record_names(records)
    roles = {"manifest": r["source-manifest"], "syncMap": r["sync-map"], "keepers": r["keeper-catalog"],
             "brolls": r["broll-catalog"], "references": r["reference-catalog"]}
    manifest = r["source-manifest"]
    media = {
        "primarySourceId": next(s["sourceId"] for s in manifest["sources"] if s["isPrimary"]),
        "slots": {s["slot"]: s["sourceId"] for s in manifest["sources"] if s["role"] == "match"},
        "views": {k["keeperId"]: [{"sourceId": v["sourceId"], "window": dict(v["window"])} for v in k["views"]]
                  for k in r["keeper-catalog"]["keepers"]},
        "brolls": {i["brollId"]: {"sourceId": i["sourceId"], "window": dict(i["window"])}
                   for i in r["broll-catalog"]["items"]},
    }
    return _plain(dict(sample_context(r), edl=bundle.edl_context(roles), media=media, stage="S2",
                       renderer={"supportedOps": list(compiler.OPS)}))


def _plain(value):
    """JSON shape (tuples to lists), as the vector file stores it."""
    if isinstance(value, dict):
        return {k: _plain(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(v) for v in value]
    return value


# A fictional one-camera recording (Sample): 20 minutes from one phone on the near baseline, eight points of 60 s
# starting every 120 s from 00:30, two contacts per point (20 s and 40 s in), a reviewed cue and an annotation on k-02,
# and the goal, drill, next and players notes. The restart variant stopped at 10:00 of recording and started again a
# minute later, so its second piece runs on the session clock from 11:00.
ONE_CAMERA_POINTS = 8
ONE_CAMERA_SECONDS = 1200
RESTART_AT_S, RESTART_GAP_S = 600, 60


def one_camera_context(fps: int, width: int, height: int, restart: bool) -> dict:
    us = 1_000_000
    frames = ONE_CAMERA_SECONDS * fps

    def session(t):                                   # recording second -> session microseconds
        return (t + (RESTART_GAP_S if restart and t >= RESTART_AT_S else 0)) * us

    rate = {"num": 1_000_000_000, "den": 1_000_000_000}
    if restart:
        coverage = [{"inFrame": 0, "outFrame": RESTART_AT_S * fps, "sessionStartUs": 0, "rate": rate},
                    {"inFrame": RESTART_AT_S * fps, "outFrame": frames, "sessionStartUs": session(RESTART_AT_S),
                     "rate": rate}]
    else:
        coverage = [{"inFrame": 0, "outFrame": frames, "sessionStartUs": 0, "rate": rate}]
    tag = f"sample-one-camera/{fps}/{width}x{height}/{'restart' if restart else 'whole'}"
    source = {"sha256": hashlib.sha256(tag.encode()).hexdigest(), "role": "match", "hasAudio": True,
              "proxy": {"fps": {"num": fps, "den": 1}, "width": width, "height": height, "frameCount": frames,
                        "ptsTableSha256": hashlib.sha256((tag + "/pts").encode()).hexdigest()},
              "coverage": coverage}
    keepers, views, contacts, refs = [], {}, [], {}
    for i in range(ONE_CAMERA_POINTS):
        kid, pid, t = f"k-{i + 1:02d}", f"p-{i + 1:03d}", 30 + 120 * i
        start, end = session(t), session(t + 60)
        keepers.append({"keeperId": kid, "origin": "point", "eventRefs": [pid], "session": {"startUs": start, "endUs": end},
                        "slots": ["near-baseline"], "selection": "manual", "provenance": "manual", "markIds": [],
                        "lessonClipIds": [], "facts": {"index": i, "rallyLength": 8, "rallyReal": True,
                                                       "breakPoint": False, "setPoint": False, "matchPoint": False,
                                                       "provenance": "manual"}})
        views[kid] = [{"sourceId": "cam-a", "window": {"inFrame": t * fps, "outFrame": (t + 60) * fps}}]
        contacts += [(t + 20) * fps, (t + 40) * fps]
        refs[pid] = {"kind": "score", "provenance": "manual", "eventRevision": 1, "pointWindows": [[start, end]]}
    notes = {"note-goal": "goal", "note-drill": "drill", "note-next": "next", "note-players": "players"}
    for nid in notes:
        refs[nid] = {"kind": "note", "provenance": "manual", "eventRevision": 1, "pointWindows": None}
    refs["cue-01"] = {"kind": "cue", "provenance": "reviewed", "eventRevision": 1, "pointWindows": None}
    refs["ann-01"] = {"kind": "annotation", "provenance": "reviewed", "eventRevision": 1, "pointWindows": None}
    bindings = {"eventRevision": 1, "syncRevision": 1, "keeperCatalogRevision": 1, "brollCatalogRevision": 1}
    return _plain({
        "projectId": "sample-one-camera", "sample": True, "bindings": bindings,
        "coverageSeconds": ONE_CAMERA_SECONDS, "primaryHasAudio": True, "juniorMode": False,
        "pointCoverageComplete": True, "keepers": keepers, "brolls": [],
        "references": [{"refId": k, "kind": v["kind"], "provenance": v["provenance"]} for k, v in refs.items()],
        "notes": [{"noteId": n, "use": u, "date": None} for n, u in notes.items()], "lessons": [],
        "cues": [{"cueId": "cue-01", "keeperId": "k-02", "provenance": "reviewed"}],
        "annotations": [{"refId": "ann-01", "keeperId": "k-02"}], "progress": None, "rights": [], "consents": [],
        "edl": {"projectId": "sample-one-camera", "current": dict(bindings, sourceManifestRevision=1),
                "sources": {"cam-a": source}, "keepers": [k["keeperId"] for k in keepers],
                "contacts": {"cam-a": sorted(contacts)}, "brolls": [], "references": refs, "consents": {}, "rights": {}},
        "media": {"primarySourceId": "cam-a", "slots": {"near-baseline": "cam-a"}, "views": views, "brolls": {}},
        "stage": "S1", "renderer": {"supportedOps": list(compiler.OPS)},
    })


def base_contexts(records: dict) -> dict:
    return {SAMPLE: sample_compile_context(records), ONE_60: one_camera_context(60, 1920, 1080, False),
            ONE_30: one_camera_context(30, 1920, 1080, False), ONE_720: one_camera_context(60, 1280, 720, False),
            ONE_GAP: one_camera_context(60, 1920, 1080, True)}


CONTEXT_WHY = {
    SAMPLE: "The sample-court-day compile context (stage S2, every operation supported); cases patch it",
    ONE_60: "A fictional one-camera recording at 60 fps, 1920x1080, with no restart (stage S1)",
    ONE_30: "The same one-camera recording captured at 30 fps (stage S1)",
    ONE_720: "The same one-camera recording at 60 fps and 1280x720 (stage S1)",
    ONE_GAP: "The one-camera recording at 60 fps that restarted at 10:00 and resumed a minute later (stage S1)",
}
CONTEXT_ASSERT = {
    SAMPLE: {"primary": "camera-1", "stage": "S2", "sources": ["broll-1", "broll-2", "camera-1", "camera-2"],
             "slots": {"far-baseline": "camera-2", "near-baseline": "camera-1", "near-left-corner": "camera-3"}},
    ONE_60: {"primary": "cam-a", "stage": "S1", "fps": 60, "size": [1920, 1080], "intervals": [[0, 72000, 0]]},
    ONE_30: {"primary": "cam-a", "stage": "S1", "fps": 30, "size": [1920, 1080], "intervals": [[0, 36000, 0]]},
    ONE_720: {"primary": "cam-a", "stage": "S1", "fps": 60, "size": [1280, 720], "intervals": [[0, 72000, 0]]},
    ONE_GAP: {"primary": "cam-a", "stage": "S1", "fps": 60, "size": [1920, 1080],
              "intervals": [[0, 36000, 0], [36000, 72000, 660000000]]},
}


# ----- hand-derived expectations ------------------------------------------------------------------------------------
# Sample keeper windows on camera-1 (60 fps, session clock = camera clock): k-01 view 720-1180 inside the session
# window 12.0-19.5 s = frames 720-1170 -> 720-1170 (450 frames, 225 at 30 fps); k-02 view 71800-75800 inside
# 71760-75840 -> 71800-75800 (2000 out); k-03 119900-125000 inside 119880-125100 (2550 out); k-04 149950-157200 inside
# 149880-157200 (3625 out). A card holds 4 s = 120 frames at 30 fps (Rally Pulse 1.5 s = 45), a pause 2 s = 60, a 1/2x
# replay 8 s = 240 frames re-showing 240 frames of 60 fps source centred on the middle stored contact. B-roll plays the
# middle 6 s of its item at 30 fps: b-01 810-990, b-02 1260-1440. Every boundary is a cut.

COACH_SEGMENTS = ["title-card card.goal 0-120", "live camera-1 71800-75800 120-2120", "freeze camera-1 @73100 2120-2180",
                  "replay camera-1 72980-73220 1/2 2180-2420", "live camera-1 720-1170 2420-2645",
                  "live camera-1 119900-125000 2645-5195", "title-card card.drill 5195-5315",
                  "title-card card.next-checkpoint 5315-5435"]
COACH = {"segments": COACH_SEGMENTS, "totalFrames": 5435, "fps": "30/1", "size": [1920, 1080], "grade": "none",
         "chapters": [["chapter.goal", 0], ["chapter.example", 120], ["chapter.example", 2420],
                      ["chapter.example", 2645], ["chapter.practice", 5195]],
         # the hold-bed continues camera-1 from where the live bed ended: 75800 + 2 x 60 = 75920; 125000 + 2 x 120
         "bed": ["silence - 0-120", "primary-bed camera-1@71800 120-2120", "hold-bed camera-1@75800 2120-2180",
                 "hold-bed camera-1@75920 2180-2420", "primary-bed camera-1@720 2420-2645",
                 "primary-bed camera-1@119900 2645-5195", "hold-bed camera-1@125000 5195-5315",
                 "hold-bed camera-1@125240 5315-5435"], "omitted": []}
# Match Broadcast: k-01's far-baseline replay maps 12.0-19.5 s onto camera-2 (offset 119837 us, rate 1.000300102):
# frames 712.6-1162.5, so 713-1162 inside its view 700-1160; the contact at camera-1 frame 905 (15.0833 s) is camera-2
# frame 897.5 -> 898, so the 240-frame replay is 778-1018. k-04 has no camera-1 contact: its live window's middle
# 153575 (2559.583 s) is camera-2 frame 153521.7 -> 153522, so 153402-153642.
BROADCAST = {"segments": ["title-card card.match-intro 0-120", "live camera-1 720-1170 120-345",
                          "replay camera-2 778-1018 1/2 345-585", "live camera-1 71800-75800 585-2585",
                          "live camera-1 119900-125000 2585-5135", "live camera-1 149950-157200 5135-8760",
                          "replay camera-2 153402-153642 1/2 8760-9000"],
             "totalFrames": 9000, "chapters": [["chapter.intro", 0], ["chapter.games", 120]],
             "bed": ["silence - 0-120", "primary-bed camera-1@720 120-345", "hold-bed camera-1@1170 345-585",
                     "primary-bed camera-1@71800 585-2585", "primary-bed camera-1@119900 2585-5135",
                     "primary-bed camera-1@149950 5135-8760", "hold-bed camera-1@157200 8760-9000"], "omitted": []}
RALLY = {"segments": ["live camera-1 720-1170 0-225", "live camera-1 71800-75800 225-2225",
                      "live camera-1 119900-125000 2225-4775", "title-card card.accent 4775-4820"],
         "totalFrames": 4820, "chapters": [],
         "bed": ["primary-bed camera-1@720 0-225", "primary-bed camera-1@71800 225-2225",
                 "primary-bed camera-1@119900 2225-4775", "hold-bed camera-1@125000 4775-4820"], "omitted": []}
PROGRESS_SHORT = {"segments": ["title-card card.goal 0-120", "live camera-1 71800-75800 120-2120",
                               "live camera-1 149950-157200 2120-5745", "title-card card.what-changed 5745-5865",
                               "title-card card.next-goal 5865-5985"],
                  "totalFrames": 5985, "chapters": [["chapter.goal", 0], ["chapter.before", 120],
                                                    ["chapter.recent", 2120], ["chapter.what-changed", 5745],
                                                    ["chapter.next", 5865]],
                  "bed": ["silence - 0-120", "primary-bed camera-1@71800 120-2120",
                          "primary-bed camera-1@149950 2120-5745", "hold-bed camera-1@157200 5745-5865",
                          "hold-bed camera-1@157440 5865-5985"], "omitted": []}
# 5 min and Full add the two lesson cards dated between the examples and k-04's half-speed replay. That replay has no
# camera-1 contact, so it centres on the live window's middle 153575: 153455-153695
PROGRESS = {"segments": ["title-card card.goal 0-120", "live camera-1 71800-75800 120-2120",
                         "title-card card.lesson 2120-2240", "title-card card.lesson 2240-2360",
                         "live camera-1 149950-157200 2360-5985", "replay camera-1 153455-153695 1/2 5985-6225",
                         "title-card card.what-changed 6225-6345", "title-card card.next-goal 6345-6465"],
            "totalFrames": 6465, "chapters": [["chapter.goal", 0], ["chapter.before", 120], ["chapter.lessons", 2120],
                                              ["chapter.recent", 2360], ["chapter.what-changed", 6225],
                                              ["chapter.next", 6345]],
            "bed": ["silence - 0-120", "primary-bed camera-1@71800 120-2120", "hold-bed camera-1@75800 2120-2240",
                    "hold-bed camera-1@76040 2240-2360", "primary-bed camera-1@149950 2360-5985",
                    "hold-bed camera-1@157200 5985-6225", "hold-bed camera-1@157680 6225-6345",
                    "hold-bed camera-1@157920 6345-6465"], "omitted": []}
MEMORIES = {"segments": ["broll broll-1 810-990 0-180", "live camera-1 720-1170 180-405",
                         "live camera-1 71800-75800 405-2405", "live camera-1 119900-125000 2405-4955",
                         "broll broll-2 1260-1440 4955-5135"],
            "totalFrames": 5135, "grade": "warm-court-1",
            "chapters": [["chapter.arrival", 0], ["chapter.match", 180], ["chapter.after", 4955]],
            "bed": ["alt-bed broll-1@810 0-180", "primary-bed camera-1@720 180-405",
                    "primary-bed camera-1@71800 405-2405", "primary-bed camera-1@119900 2405-4955",
                    "alt-bed broll-2@1260 4955-5135"], "omitted": []}
MATRIX = {"coach-cut": COACH, "match-broadcast": BROADCAST, "rally-pulse": RALLY, "progress-story": PROGRESS,
          "court-memories": MEMORIES}

# The storyboard edits behind the final Court Memories film (edit-plan.court-memories-final.json, revision 2): the
# player added k-03 after the highlight and trimmed every shot. story-brief.court-memories.json does not carry them.
ADDED_K03 = {"beatId": "b05", "role": "match-moment", "treatment": "live", "keeperId": "k-03", "brollId": None,
             "angle": "near-baseline", "replaySpeedDen": None, "overlays": [], "noteId": None, "templateId": None,
             "reasonForReview": "Added in the storyboard: the longest rally of the day."}
FINAL_TRIMS = {"b01": {"inFrame": 60, "outFrame": 1320}, "b02": {"inFrame": 744, "outFrame": 1116},
               "b03": {"inFrame": 72000, "outFrame": 75600}, "b05": {"inFrame": 120000, "outFrame": 124488},
               "b04": {"inFrame": 30, "outFrame": 2280}}

# One camera, 60 fps output (the capture rate, by default): a point is 60 s = 3600 frames, a card 4 s = 240 frames.
# k-0n starts at 00:30 + 120 s x (n - 1) of recording; after the restart (10:00) the session clock runs a minute ahead.
ONE_POINTS = [f"live cam-a {a}-{a + 3600}" for a in (1800, 9000, 16200, 23400, 30600, 37800, 45000, 52200)]


def _one_broadcast(gap: bool) -> list:
    out, cursor = ["title-card card.match-intro 0-240"], 240
    for n, p in enumerate(ONE_POINTS):
        if gap and n == 5:
            out.append(f"title-card card.recording-gap {cursor}-{cursor + 240}")
            cursor += 240
        out.append(f"{p} {cursor}-{cursor + 3600}")
        cursor += 3600
    if not gap:
        out.append(f"title-card card.final-score {cursor}-{cursor + 240}")
    return out


def matrix_cases() -> list:
    out = []
    for profile in PROFILE_IDS:
        for length in director.LENGTH_KEYS:
            if (profile, length) in (("match-broadcast", "3min"), ("rally-pulse", "5min")):
                continue   # lengths the profile refuses (ST29); the planner vectors pin those refusals
            hand = PROGRESS_SHORT if (profile, length) == ("progress-story", "3min") else MATRIX[profile]
            a = dict({"fps": "30/1", "size": [1920, 1080], "grade": "none"}, **hand)
            out.append(_case(f"{profile}-{length}", f"{profile}, {length}, on the Sample context at 30 fps (stage S2)",
                             SAMPLE, [], {"profileId": profile, "options": {"length": length}}, FPS30, a))
    return out


def special_cases() -> list:
    s1 = [{"op": "replace", "path": "/stage", "value": "S1"}]
    no = lambda op: [{"op": "replace", "path": "/renderer/supportedOps",   # noqa: E731
                      "value": [o for o in compiler.OPS if o != op]}]
    coach = {"profileId": "coach-cut", "options": {"length": "3min"}}
    memories = {"profileId": "court-memories", "options": {"length": "3min"}}
    progress = {"profileId": "progress-story", "options": {"length": "full"}}
    broadcast = {"profileId": "match-broadcast", "options": {"length": "5min"}}
    final = {"record": "story-brief.court-memories",
             "planPatch": [{"op": "add", "path": "/beats/3", "value": ADDED_K03}]}
    final_request = dict(FPS30, planId="court-memories-final", trims=FINAL_TRIMS)
    one_coach_60 = ["title-card card.goal 0-120", "live cam-a 9000-12600 120-1920", "freeze cam-a @11400 1920-1980",
                    "replay cam-a 11280-11520 1/2 1980-2220", "live cam-a 1800-5400 2220-4020",
                    "live cam-a 16200-19800 4020-5820", "title-card card.drill 5820-5940",
                    "title-card card.next-checkpoint 5940-6060"]
    one_coach_30 = ["title-card card.goal 0-120", "live cam-a 4500-6300 120-1920", "freeze cam-a @5700 1920-1980",
                    "live cam-a 900-2700 1980-3780", "live cam-a 8100-9900 3780-5580",
                    "title-card card.drill 5580-5700", "title-card card.next-checkpoint 5700-5820"]
    return [
        _case("coach-cut-3min-stage-s1", "Stage S1 enables everything Coach's Cut uses on one angle, so the film is "
              "byte-identical to the S2 compile", SAMPLE, s1, coach, FPS30, {"sameAs": "coach-cut-3min"}),
        _case("match-broadcast-5min-stage-s1", "Stage S1 has no second angle: both far-baseline replays are omitted "
              "(notInThisStage) and 120 + 225 + 2000 + 2550 + 3625 = 8520 frames = 4 min 44 s is under 5 min",
              SAMPLE, s1, broadcast, FPS30,
              {"refusal": ["belowProfileMinimum", "About 4 min 44 s of real material; Match Broadcast needs at least "
                                                  "5 min. Mark more moments for a longer film."]}),
        _case("coach-cut-3min-default-clock", "No fps requested: the film runs at camera-1's 60 fps, where a 1/2x "
              "replay of 60 fps footage would need invented frames, so it is omitted; 10390 frames = 2 min 53 s is "
              "under Coach's Cut's 3 min", SAMPLE, [], coach, {},
              {"refusal": ["belowProfileMinimum", "About 2 min 53 s of real material; Coach’s Cut needs at least "
                                                  "3 min. Mark more moments for a longer film."]}),
        _case("court-memories-3min-default-clock", "No fps requested: camera-1 is 60 fps but the B-roll is 30 fps, so "
              "the film runs at 30 fps (never above a source it moves through)", SAMPLE, [], memories, {},
              dict(MEMORIES, fps="30/1", size=[1920, 1080])),
        _case("fps-above-source", "120 fps is above camera-1's 60 fps: refused rather than repeating frames",
              SAMPLE, [], coach, {"fps": {"num": 120, "den": 1}},
              {"refusal": ["fpsAboveSource", "A 120 fps film would repeat frames: camera-1 was recorded at 60 fps."]}),
        _case("fps-above-broll", "60 fps is camera-1's rate but above the 30 fps B-roll Court Memories cuts to",
              SAMPLE, [], memories, {"fps": {"num": 60, "den": 1}},
              {"refusal": ["fpsAboveSource", "A 60 fps film would repeat frames: broll-1 was recorded at 30 fps."]}),
        _case("half-speed-replay-30fps-source", "A 1/2x replay of 30 fps footage at 30 fps output would repeat every "
              "frame: omitted (cleanFrame), and the moment plays at original speed only (originalSpeedFallback)",
              ONE_30, [], coach, FPS30,
              {"segments": one_coach_30, "totalFrames": 5820, "fps": "30/1",
               "omitted": [["b04", "replay", "cleanFrame", "originalSpeedFallback"]]}),
        _case("half-speed-replay-60fps-source", "The same request from 60 fps footage: every replay frame is a real "
              "captured frame (60 x 1/2 = 30), so it compiles, centred on k-02's contact at 03:10 (frame 11400)",
              ONE_60, [], coach, FPS30, {"segments": one_coach_60, "totalFrames": 6060, "fps": "30/1", "omitted": []}),
        # k-03 ends at 330 s (cam-a 19800); the drill card would hold the court sound over 330-334 s. With k-04's
        # session starting at 333 s that is no longer dead time (a kept point is play), so both closing cards play over
        # one silent piece; the earlier holds (210-220 s, before k-03 at 270 s) are unchanged.
        _case("hold-bed-not-over-kept-play", "A hold-bed runs only over real dead time: when another kept point starts "
              "inside the court sound a card would hold, the card plays over silence instead", ONE_60,
              [{"op": "replace", "path": "/keepers/3/session/startUs", "value": 333_000_000}], coach, FPS30,
              {"segments": one_coach_60, "totalFrames": 6060,
               "bed": ["silence - 0-120", "primary-bed cam-a@9000 120-1920", "hold-bed cam-a@12600 1920-1980",
                       "hold-bed cam-a@12720 1980-2220", "primary-bed cam-a@1800 2220-4020",
                       "primary-bed cam-a@16200 4020-5820", "silence - 5820-6060"]}),
        _case("upscale-refused", "A 1920x1080 fill film from a 1280x720 recording is refused", ONE_720, [], broadcast,
              {"width": 1920, "height": 1080},
              {"refusal": ["upscaleRefused", "A 1920x1080 film from a 1280x720 recording would only enlarge it, which "
                                             "adds no detail. The film can be at most 1280x720."]}),
        _case("default-output-720p", "With nothing requested, a 1280x720 60 fps recording compiles to a 1280x720 "
              "60 fps film", ONE_720, [], broadcast, {},
              {"fps": "60/1", "size": [1280, 720], "totalFrames": 29280, "segments": _one_broadcast(False)}),
        _case("one-camera-restart", "Match Broadcast over a recording that restarted: a gap card between k-05 and k-06 "
              "says 'Recording gap · 1:00', and the final score card is omitted (coverage incomplete)", ONE_GAP, [],
              broadcast, {},
              {"segments": _one_broadcast(True), "totalFrames": 29280, "gaps": ["Recording gap · 1:00"],
               "omitted": [["b10", "card", "coverageIncomplete"]],
               "chapters": [["chapter.intro", 0], ["chapter.games", 240]]}),
        _case("one-camera-no-restart", "The same match without the restart: no gap card, and the final score card "
              "closes the film", ONE_60, [], broadcast, {},
              {"segments": _one_broadcast(False), "totalFrames": 29280, "gaps": [], "omitted": [],
               "chapters": [["chapter.intro", 0], ["chapter.games", 240], ["chapter.final", 29040]]}),
        _case("titles-not-in-this-build", "A renderer without title cards: every card beat is omitted "
              "(notInThisBuild) and listed, and the remaining 2000 + 3625 + 240 frames still make a valid film",
              SAMPLE, no("card"), progress, FPS30,
              {"segments": ["live camera-1 71800-75800 0-2000", "live camera-1 149950-157200 2000-5625",
                            "replay camera-1 153455-153695 1/2 5625-5865"], "totalFrames": 5865,
               "notInThisBuild": ["card"],
               "omitted": [["b01", "card", "notInThisBuild"], ["b03", "card", "notInThisBuild"],
                           ["b04", "card", "notInThisBuild"], ["b07", "card", "notInThisBuild"],
                           ["b08", "card", "notInThisBuild"]],
               "chapters": [["chapter.before", 0], ["chapter.recent", 2000]]}),
        _case("replays-not-in-this-build", "A renderer without replays: Progress Story's replay is omitted "
              "(notInThisBuild); 6465 - 240 frames is still inside 2-6 min", SAMPLE, no("replay"),
              {"profileId": "progress-story", "options": {"length": "5min"}}, FPS30,
              {"totalFrames": 6225, "notInThisBuild": ["replay"], "omitted": [["b06", "replay", "notInThisBuild"]]}),
        _case("overlays-not-in-this-build", "A renderer without overlays: the stat chips on the early example and the "
              "what-changed card are dropped and listed", SAMPLE, no("overlay"),
              {"profileId": "progress-story", "options": {"length": "3min"}}, FPS30,
              {"totalFrames": 5985, "notInThisBuild": ["overlay"],
               "omitted": [["b02", "overlay", "notInThisBuild"], ["b04", "overlay", "notInThisBuild"]]}),
        _case("hold-bed-not-in-this-build", "A renderer without hold-bed: the closing accent card plays over silence "
              "instead of holding the court sound, and hold-bed is listed", SAMPLE, no("hold-bed"),
              {"profileId": "rally-pulse", "options": {"length": "3min"}}, FPS30,
              {"segments": RALLY["segments"], "totalFrames": 4820, "notInThisBuild": ["hold-bed"],
               "omitted": [[None, "hold-bed", "notInThisBuild"]],
               "bed": ["primary-bed camera-1@720 0-225", "primary-bed camera-1@71800 225-2225",
                       "primary-bed camera-1@119900 2225-4775", "silence - 4775-4820"]}),
        _case("renderer-without-live", "A build that cannot render live play cannot make any film", SAMPLE, no("live"),
              coach, FPS30, {"refusal": ["rendererIncomplete", "This build cannot render a film yet (no live)."]}),
        _case("junior-mode-silent", "Junior mode: the brief asks for no audio, so the bed is one silent piece and names "
              "no primary source", SAMPLE, [{"op": "replace", "path": "/juniorMode", "value": True}],
              {"profileId": "rally-pulse", "options": {"length": "3min"}}, FPS30,
              {"totalFrames": 4820, "bed": ["silence - 0-4820"], "primary": None}),
        _case("court-memories-final-film", "The final Court Memories film from story-brief.court-memories.json with "
              "the storyboard edits it lacks (k-03 added, five trims): chapters 1260 + 4230 + 2250 frames = "
              "42 + 141 + 75 s = 258 s, cut for cut the record's", SAMPLE, [], final, final_request,
              {"totalFrames": 7740, "fps": "30/1", "chapterSeconds": [42, 141, 75], "totalSeconds": 258,
               "chapters": [["chapter.arrival", 0], ["chapter.match", 1260], ["chapter.after", 5490]],
               "finalFilm": "edit-plan.court-memories-final", "grade": "warm-court-1",
               "segments": ["broll broll-1 60-1320 0-1260", "live camera-2 744-1116 1260-1446",
                            "live camera-1 72000-75600 1446-3246", "live camera-1 120000-124488 3246-5490",
                            "broll broll-2 30-2280 5490-7740"]}),
        _case("court-memories-final-film-stage-s1", "The same edits at stage S1: the far-baseline shot needs a second "
              "angle (omitted, notInThisStage), the warm grade is S2, and B-roll sound (alt-bed) is S2, so the B-roll "
              "plays over silence", SAMPLE, s1, final, final_request,
              {"totalFrames": 7554, "grade": "none",
               "omitted": [["b02", "multi-angle", "notInThisStage"], [None, "grade", "notInThisStage"]],
               "chapters": [["chapter.arrival", 0], ["chapter.match", 1260], ["chapter.after", 5304]],
               "bed": ["silence - 0-1260", "primary-bed camera-1@72000 1260-3060",
                       "primary-bed camera-1@120000 3060-5304", "silence - 5304-7554"]}),
        _case("trim-outside-window", "A trim that leaves k-02's trusted window (71800-75800) is rejected", SAMPLE, [],
              final, dict(final_request, trims=dict(FINAL_TRIMS, b03={"inFrame": 71000, "outFrame": 75600})),
              {"rejectCode": "trimOutsideWindow"}),
        _case("unknown-keeper", "A plan naming a keeper the catalog does not hold is rejected before compiling "
              "(story 148)", SAMPLE, [], dict(coach, planPatch=[{"op": "replace", "path": "/beats/1/keeperId",
                                                                  "value": "k-99"}]), FPS30,
              {"rejectCode": "untrustedReference"}),
        _case("stale-event-revision", "A plan bound to an older event revision is rejected (story 148)", SAMPLE, [],
              dict(coach, planPatch=[{"op": "replace", "path": "/bindings/eventRevision", "value": 2}]), FPS30,
              {"rejectCode": "staleRevision"}),
        _case("window-across-gap", "camera-1 restarted at frame 73000, inside k-02's window: the plan would cut across "
              "a recording gap, so it is rejected (story 148)", SAMPLE,
              [{"op": "replace", "path": "/edl/sources/camera-1/coverage",
                "value": [{"inFrame": 0, "outFrame": 73000, "sessionStartUs": 0,
                           "rate": {"num": 1000000000, "den": 1000000000}},
                          {"inFrame": 73000, "outFrame": 216000, "sessionStartUs": 1300000000,
                           "rate": {"num": 1000000000, "den": 1000000000}}]}], coach, FPS30,
              {"rejectCode": "outsideCoverage"}),
        _case("unknown-request-field", "A request field outside fps, width, height, planId and trims is rejected",
              SAMPLE, [], coach, dict(FPS30, filter="scale=3840:2160"), {"rejectCode": "unknownField"}),
    ]


def _case(cid, why, context, patch, plan_from, request, a) -> dict:
    return {"id": cid, "why": why, "op": "compile", "context": context, "contextPatch": patch, "planFrom": plan_from,
            "input": {"request": request}, "assert": a}


# ----- building and resolving -------------------------------------------------------------------------------------

def make_plan(profiles: dict, plan_from: dict, context: dict, record) -> dict:
    """The StoryPlan a case compiles: the RulesPlanner on the case's context, or a Sample record; then `planPatch`."""
    if "record" in plan_from:
        doc = copy.deepcopy(record(plan_from["record"]))
    else:
        briefed = director.brief(profiles, context, plan_from["profileId"], plan_from["options"])
        out = planner.plan(profiles, briefed, context)
        require("plan" in out, "badVector", f"the planner did not plan {plan_from}: {out}")
        doc = out["plan"]
    return apply_patch(doc, plan_from["planPatch"]) if plan_from.get("planPatch") else doc


def resolve(case: dict, bases: dict) -> dict:
    """The full input a compile case runs on (the context is its base context case patched by contextPatch)."""
    context = apply_patch(bases[case["context"]], case["contextPatch"]) if case["contextPatch"] \
        else copy.deepcopy(bases[case["context"]])
    return {"op": "compile", "input": dict(copy.deepcopy(case["input"]), context=context)}


def build_vector(records: dict, profiles: dict) -> dict:
    bases = base_contexts(records)
    names = record_names(records)
    cases = [{"id": cid, "why": CONTEXT_WHY[cid], "op": "context", "input": {}, "expect": {"context": ctx},
              "assert": CONTEXT_ASSERT[cid]} for cid, ctx in bases.items()]
    for c in matrix_cases() + special_cases():
        context = apply_patch(bases[c["context"]], c["contextPatch"]) if c["contextPatch"] else bases[c["context"]]
        c["input"]["plan"] = make_plan(profiles, c["planFrom"], context, lambda n: names[n])
        c["expect"] = compiler.run_vector(profiles, resolve(c, bases))
        cases.append(c)
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": KIND,
            "status": "Sample: expect from spec/reference/studio/compile.py over the sample-court-day context and a "
                      "fictional one-camera recording; assert blocks are hand-derived frames, beds, chapters, omissions "
                      "and refusal copy",
            "cases": cases}


def fixtures(sample):
    return {VECTOR: build_vector(sample.records, sample.profiles)}


# ----- checker ----------------------------------------------------------------------------------------------------

def compact_segment(s: dict) -> str:
    if s["op"] == "title-card":
        return f"title-card {s['templateId']} {s['outputInFrame']}-{s['outputOutFrame']}"
    out = f"{s['outputInFrame']}-{s['outputOutFrame']}"
    if s["op"] == "freeze":
        return f"freeze {s['sourceId']} @{s['sourceFrame']} {out}"
    speed = f" 1/{s['speed']['den']}" if s["op"] == "replay" else ""
    return f"{s['op']} {s['sourceId']} {s['sourceInFrame']}-{s['sourceOutFrame']}{speed} {out}"


def compact_bed(p: dict) -> str:
    at = "-" if p["route"] == "silence" else f"{p['sourceId']}@{p['sourceInFrame']}"
    return f"{p['route']} {at} {p['outputInFrame']}-{p['outputOutFrame']}"


def _bases(ctx) -> dict:
    return base_contexts({f"records/{k}.json": v for k, v in ctx.records.items()})


def _context_problems(case: dict, bases: dict) -> list:
    got = case["expect"]["context"]
    if got != bases.get(case["id"]):
        return ["the stored context is out of date with the records or its builder"]
    a, e = case["assert"], got["edl"]
    prim = e["sources"][got["media"]["primarySourceId"]]
    have = {"primary": got["media"]["primarySourceId"], "stage": got["stage"], "sources": sorted(e["sources"]),
            "slots": got["media"]["slots"], "fps": prim["proxy"]["fps"]["num"],
            "size": [prim["proxy"]["width"], prim["proxy"]["height"]],
            "intervals": [[c["inFrame"], c["outFrame"], c["sessionStartUs"]] for c in prim["coverage"]]}
    return [f"{k}: {have[k]!r}, hand value {a[k]!r}" for k in a if have[k] != a[k]]


def _compiled_problems(ctx, got: dict, a: dict, resolved: dict, cases: dict) -> list:
    doc = got["edl"]
    have = {"segments": [compact_segment(s) for s in doc["segments"]], "totalFrames": doc["output"]["totalFrames"],
            "fps": f"{doc['output']['fps']['num']}/{doc['output']['fps']['den']}",
            "size": [doc["output"]["width"], doc["output"]["height"]], "grade": doc["grade"]["presetId"],
            "chapters": [[c["templateId"], c["outputInFrame"]] for c in doc["chapters"]],
            "bed": [compact_bed(p) for p in doc["audio"]["bed"]], "primary": doc["audio"]["primarySourceId"],
            "omitted": [[o["beatId"], o["op"], o["reason"]] + ([o["fallback"]] if "fallback" in o else [])
                        for o in got["omitted"]],
            "notInThisBuild": got["notInThisBuild"], "gaps": [g["display"] for g in got["gaps"]]}
    p = [f"{k}: {have[k]!r}, hand value {a[k]!r}" for k in have if k in a and a[k] != have[k]]
    if "chapterSeconds" in a:
        fps = Fraction(doc["output"]["fps"]["num"], doc["output"]["fps"]["den"])
        marks = [c["outputInFrame"] for c in doc["chapters"]] + [doc["output"]["totalFrames"]]
        secs = [Fraction(b - x) / fps for x, b in zip(marks, marks[1:])]
        if secs != a["chapterSeconds"] or sum(secs) != a["totalSeconds"]:
            p.append(f"chapters last {[str(s) for s in secs]} s, hand value {a['chapterSeconds']}")
    if "finalFilm" in a:
        record = ctx.records[a["finalFilm"]]
        cut = [(s["op"], s.get("sourceId"), s.get("sourceInFrame"), s.get("sourceOutFrame"), s["outputInFrame"],
                s["outputOutFrame"]) for s in record["segments"]]
        mine = [(s["op"], s.get("sourceId"), s.get("sourceInFrame"), s.get("sourceOutFrame"), s["outputInFrame"],
                 s["outputOutFrame"]) for s in doc["segments"]]
        marks = [(c["templateId"], c["outputInFrame"]) for c in record["chapters"]]
        if cut != mine or marks != [(c["templateId"], c["outputInFrame"]) for c in doc["chapters"]]:
            p.append(f"the compiled cut list or chapters differ from {a['finalFilm']}")
    if "sameAs" in a:
        other = cases.get(a["sameAs"], {}).get("expect", {})
        if other.get("sha256") != got["sha256"]:
            p.append(f"not byte-identical to {a['sameAs']}")
    if got["sha256"] != canonical_sha256(doc):
        p.append("sha256 is not the canonical hash of the EDL")
    context = resolved["input"]["context"]
    try:
        edl.validate(doc, ctx.profiles, context["edl"])
    except Reject as exc:
        p.append(f"edl.validate rejects the compiled plan: {exc}")
    p += [f"schema: {e}" for e in ctx.schemas.validate(doc, ctx.schema_for(doc["schemaVersion"]))[:3]]
    p += _window_problems(doc, context)
    return p


def _window_problems(doc: dict, context: dict) -> list:
    """Independent of the compiler: every live window sits inside its keeper's stored view and every B-roll window
    inside its item (the bundle rules), every card text is a stored note, and nothing is shown that the plan lacks."""
    views, brolls, p = context["media"]["views"], context["media"]["brolls"], []
    for s in doc["segments"]:
        if s["op"] == "live":
            v = next((x["window"] for x in views.get(s["keeperId"], []) if x["sourceId"] == s["sourceId"]), None)
            if v is None or not v["inFrame"] <= s["sourceInFrame"] < s["sourceOutFrame"] <= v["outFrame"]:
                p.append(f"{s['id']}: outside keeper {s['keeperId']}'s view")
        if s["op"] == "broll":
            w = brolls[s["brollId"]]["window"]
            if not w["inFrame"] <= s["sourceInFrame"] < s["sourceOutFrame"] <= w["outFrame"]:
                p.append(f"{s['id']}: outside B-roll item {s['brollId']}")
        if s["op"] == "title-card" and any(context["edl"]["references"].get(r, {}).get("kind") != "note"
                                           for r in s["textRefs"]):
            p.append(f"{s['id']}: card text that is not a stored note")
    return p


def _result_problems(ctx, got: dict, a: dict, resolved: dict, cases: dict) -> list:
    if "rejectCode" in a:
        return [] if got.get("rejectCode") == a["rejectCode"] else [f"expected {a['rejectCode']}, got {got}"]
    if "rejectCode" in got:
        return [f"rejected with {got['rejectCode']}"]
    if "refusal" in a:
        r = got.get("refusal") or {}
        return [] if [r.get("code"), r.get("message")] == a["refusal"] else [f"refusal {r}, hand value {a['refusal']}"]
    if "refusal" in got:
        return [f"refused: {got['refusal']}"]
    return _compiled_problems(ctx, got, a, resolved, cases)


def check_compile_vector(ctx, case, report, where) -> None:
    bases = _bases(ctx)
    if case["op"] == "context":
        problems = _context_problems(case, bases)
        for problem in problems:
            report.fail(where, problem)
        if not problems:
            report.ok("compile vectors (context)")
        return
    cases = {c["id"]: c for c in ctx.fixture(VECTOR)["cases"]}
    context = apply_patch(bases[case["context"]], case["contextPatch"]) if case["contextPatch"] \
        else bases[case["context"]]
    try:
        plan = make_plan(ctx.profiles, case["planFrom"], context, lambda n: ctx.records[n])
    except (Reject, IndexError, KeyError, ValueError) as exc:
        report.fail(where, f"the case's plan cannot be made: {exc}")
        return
    if plan != case["input"]["plan"]:
        report.fail(where, "the stored plan is not the one planFrom makes today")
        return
    resolved = resolve(case, bases)
    snapshot = copy.deepcopy(resolved)
    got = compiler.run_vector(ctx.profiles, resolved)
    if got != case["expect"]:
        report.fail(where, "reference output differs from the stored expectation")
        return
    problems = _result_problems(ctx, got, case["assert"], resolved, cases)
    if resolved != snapshot:
        problems.append("the compiler changed its input")
    if "edl" in got:
        again = compiler.run_vector(ctx.profiles, copy.deepcopy(snapshot))
        if canonical_bytes(again["edl"]) != canonical_bytes(got["edl"]) or again["sha256"] != got["sha256"]:
            problems.append("compiling the same plan twice gave different canonical JSON")
        else:
            report.ok("compile determinism (same plan, byte-identical canonical JSON and sha256)")
    for problem in problems:
        report.fail(where, problem)
    if not problems:
        report.ok("compile vectors (" + ("edl" if "edl" in got else "refusal" if "refusal" in got else "reject") + ")")


VECTOR_CHECKERS = {KIND: check_compile_vector}


# ----- self-tests -------------------------------------------------------------------------------------------------

def check_matrix(ctx, report) -> None:
    """Every profile x {3min, 5min, full} on the unpatched Sample context either has a compile vector whose EDL
    validates, or is a length the planner refuses (planner.json pins that refusal)."""
    cases = {c["id"]: c for c in ctx.fixture(VECTOR)["cases"]}
    planned = {c["id"]: c for c in ctx.fixture("vectors/planner.json")["cases"]}
    problems, compiled = [], 0
    for profile in PROFILE_IDS:
        for length in director.LENGTH_KEYS:
            cid = f"{profile}-{length}"
            c = cases.get(cid)
            if c is None:
                if planned.get(cid, {}).get("expect", {}).get("refusal", {}).get("code") != "lengthUnavailable":
                    problems.append(f"no compile vector for {cid}, and the planner does not refuse it")
                continue
            if c["contextPatch"] or c["context"] != SAMPLE or "edl" not in c["expect"]:
                problems.append(f"{cid} is not an unpatched Sample compile with an EDL")
                continue
            compiled += 1
    for problem in problems:
        report.fail("compile matrix", problem)
    if not problems:
        report.ok("compile matrix (profile x length) EDLs", compiled)


def check_mutations(ctx, report) -> None:
    """The compiler's output is checked, not trusted: a compiled EDL with one live segment shifted by a frame, its
    Replay label dropped, or a stale event revision must each fail edl.validate."""
    case = next(c for c in ctx.fixture(VECTOR)["cases"] if c["id"] == "coach-cut-3min")
    doc, context = case["expect"]["edl"], _bases(ctx)[SAMPLE]
    mutations = {"shift": [{"op": "replace", "path": "/segments/1/sourceInFrame", "value": 71801}],
                 "no-replay-label": [{"op": "replace", "path": "/segments/3/labelTemplateId", "value": "label.paused"}],
                 "stale": [{"op": "replace", "path": "/bindings/eventRevision", "value": 2}]}
    caught = 0
    for name, patch in mutations.items():
        try:
            edl.validate(apply_patch(doc, patch), ctx.profiles, context["edl"])
            report.fail("compile mutations", f"{name}: the mutated EDL still validates")
        except Reject:
            caught += 1
    if caught == len(mutations):
        report.ok("compile mutations caught", caught)


SELF_TESTS = {"compile-matrix": check_matrix, "compile-mutations": check_mutations}
