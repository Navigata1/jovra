"""Rally fixtures.

1. Hand-derived valid-output controls for inconsistent zero-stroke error observations (scoring fixtures S65, S66).
2. T32: rally segmentation and rally-only plan vectors (jovra.fixture.rally, spec/fixtures/rally/R*.json) and a
   session whose rallyPlayback carries per-session and per-clip rolls (spec/fixtures/rally/session.rolls.json).
   Every expected value below was worked by hand from the rules in jovra_ref/rally.py's docstring; the generator
   refuses to write a case the reference engine disagrees with, and CHECKS re-runs every case in the validator.
"""
from __future__ import annotations

import copy

from .common import CLUB_BO3, singles
from jovra_ref import conformance, rally, references, scoring

ORDER = 12
RALLY_VERSION = "1.0.0"
SESSION_VERSION = "1.1.0"


# ----- 1. zero-stroke controls -------------------------------------------------------------------

def _zero_stroke(ctx) -> int:
    for index, end in enumerate(('forcedError', 'unforcedError'), 65):
        fixture_id = f"S{index}-zero-stroke-{'forced' if end == 'forcedError' else 'unforced'}-error"
        setup = singles(CLUB_BO3)
        setup['log'] = [{'id': 'p01', 'seq': 1, 'type': 'point', 'reviewState': 'reviewed', 'reviewed': {
            'winner': 'B', 'endType': end, 'strokeCount': 0, 'provenance': 'reviewed', 'source': 'user'}}]
        assertions = [{'checkpoint': 0, 'path': path, 'equals': value} for path, value in [
            ('fold.points[0].strokeCount', 0), ('fold.points[0].winner', 'B'),
            ('fold.points[0].rallyLength', None), ('fold.points[0].endType', end),
            ('fold.conflicts', [{'type': 'outcomeInconsistent', 'pointId': 'p01'}]),
            ('fold.next.before.points', {'A': 0, 'B': 1}), ('stats.rallyLength.unknown', 1),
            ('stats.rallyLength.0-4', 0), ('stats.shots.total', 0)]]
        checkpoints = conformance.run_scoring(setup, [1])
        errors = conformance.check_assertions(checkpoints, assertions)
        if errors:
            raise ValueError(f'{fixture_id}: {errors}')
        ctx.write_json(ctx.fixtures / 'scoring' / f'{fixture_id}.json', {
            'schemaVersion': '1.2.0', 'kind': 'jovra.fixture.scoring', 'id': fixture_id,
            'title': f'Zero-stroke {end}: keep observation, derived rally length unknown',
            'covers': ['C11', 'ADR0003', 'valid-input-valid-output'], 'input': setup,
            'assertions': assertions, 'checkpoints': checkpoints})
    return 2


# ----- 2. rally segmentation and the rally-only plan (T32) ---------------------------------------

def hit(hid: str, t: int, side: str | None = None, kind: str = "hit") -> dict:
    out = {"id": hid, "tMs": t, "kind": kind}
    if side is not None:
        out["side"] = side
    return out


def mark(mid: str, t: int, kind: str = "point") -> dict:
    return {"id": mid, "tMs": t, "kind": kind}


def span(a: int, b: int) -> dict:
    return {"fromMs": a, "toMs": b}


def from_hits(start: int, end: int, clip: tuple, hit_ids: list, rallies: list, mark_ids: list = ()) -> dict:
    return {"source": "hits", "startMs": start, "endMs": end, "clip": span(*clip), "hitIds": list(hit_ids),
            "markIds": list(mark_ids), "rallies": [{"startMs": s, "endMs": e, "hitCount": n} for s, e, n in rallies],
            "provenance": "estimated", "needsReview": True}


def from_mark(mid: str, t: int, clip: tuple) -> dict:
    return {"source": "mark", "startMs": t, "endMs": t, "clip": span(*clip), "hitIds": [], "markIds": [mid],
            "rallies": [], "provenance": "manual", "needsReview": False}


def segmented(candidates: list, excluded: list = (), not_hit: list = (), not_point: list = ()) -> dict:
    return {"candidates": candidates, "dropped": {"excludedSide": list(excluded), "notHit": list(not_hit),
                                                  "notPointMark": list(not_point)}}


def seg(name: str, hits, marks: list, params: dict, expected=None, error: str | None = None) -> dict:
    case = {"op": "segment", "name": name, "hits": hits, "marks": marks, "params": params}
    case.update({"expectedError": error} if error else {"expected": expected})
    return case


def target(tid: str, start: int, end: int | None = None) -> dict:
    return {"targetId": tid, "startMs": start, "endMs": start if end is None else end}


def rng(a: int, b: int, ids: list) -> dict:
    return {"range": span(a, b), "durationMs": b - a, "targetIds": list(ids)}


def gap(a: int, b: int, label: str) -> dict:
    return {"range": span(a, b), "durationMs": b - a, "label": label}


def planned(ranges: list, gaps: list, kept: int, skipped: int, duration: int, excluded: list = ()) -> dict:
    return {"ranges": ranges, "gaps": gaps, "excludedTargetIds": list(excluded), "keptMs": kept,
            "skippedMs": skipped, "durationMs": duration}


def plan(name: str, targets: list, rolls, duration: int, expected=None, error: str | None = None) -> dict:
    case = {"op": "plan", "name": name, "targets": targets, "rolls": rolls, "durationMs": duration}
    case.update({"expectedError": error} if error else {"expected": expected})
    return case


R01 = ("R01-bookmarks-only", "Without audio every point mark is a candidate on its own, rolled 1.5 s / 2.5 s", [
    seg("no audio: point marks become candidates, sorted by time; other marks are left out",
        None, [mark("m3", 120_000), mark("m1", 60_000), mark("m2", 90_000, "highlight"), mark("m4", 1_000)],
        {"durationMs": 600_000},
        segmented([from_mark("m4", 1_000, (0, 3_500)), from_mark("m1", 60_000, (58_500, 62_500)),
                   from_mark("m3", 120_000, (118_500, 122_500))], not_point=["m2"])),
    seg("audio with no hits: marks still stand on their own", [], [mark("m1", 60_000)], {"durationMs": 600_000},
        segmented([from_mark("m1", 60_000, (58_500, 62_500))])),
    seg("a mark near the end is clamped to the recording", None, [mark("m1", 60_000)], {"durationMs": 61_000},
        segmented([from_mark("m1", 60_000, (58_500, 61_000))])),
    seg("no marks and no audio: nothing to play", None, [], {"durationMs": 600_000}, segmented([])),
    plan("plan from marks with the default rolls: leading, middle and trailing gaps",
         [target("m1", 60_000), target("m3", 120_000), target("m4", 1_000)], None, 600_000,
         planned([rng(0, 3_500, ["m4"]), rng(58_500, 62_500, ["m1"]), rng(118_500, 122_500, ["m3"])],
                 [gap(3_500, 58_500, "+0:55"), gap(62_500, 118_500, "+0:56"), gap(122_500, 600_000, "+7:57")],
                 11_500, 588_500, 600_000)),
    plan("marks 3 s apart overlap once rolled and play as one range",
         [target("m5", 63_000), target("m1", 60_000)], None, 70_000,
         planned([rng(58_500, 65_500, ["m1", "m5"])], [gap(0, 58_500, "+0:58"), gap(65_500, 70_000, "+0:04")],
                 7_000, 63_000, 70_000)),
])

R02 = ("R02-threshold-edges", "Same rally below 3 s, same point up to 5 s, new point above 5 s", [
    seg("2999 ms between hits: one rally", [hit("h1", 10_000), hit("h2", 12_999)], [], {"durationMs": 60_000},
        segmented([from_hits(10_000, 12_999, (8_500, 15_499), ["h1", "h2"], [(10_000, 12_999, 2)])])),
    seg("exactly 3000 ms: the rally ends, the point does not", [hit("h1", 10_000), hit("h2", 13_000)], [],
        {"durationMs": 60_000},
        segmented([from_hits(10_000, 13_000, (8_500, 15_500), ["h1", "h2"],
                             [(10_000, 10_000, 1), (13_000, 13_000, 1)])])),
    seg("exactly 5000 ms: still the same point", [hit("h1", 10_000), hit("h2", 15_000)], [], {"durationMs": 60_000},
        segmented([from_hits(10_000, 15_000, (8_500, 17_500), ["h1", "h2"],
                             [(10_000, 10_000, 1), (15_000, 15_000, 1)])])),
    seg("5001 ms: a new point", [hit("h1", 10_000), hit("h2", 15_001)], [], {"durationMs": 60_000},
        segmented([from_hits(10_000, 10_000, (8_500, 12_500), ["h1"], [(10_000, 10_000, 1)]),
                   from_hits(15_001, 15_001, (13_501, 17_501), ["h2"], [(15_001, 15_001, 1)])])),
    seg("custom thresholds and rolls",
        [hit("h1", 1_000), hit("h2", 2_500), hit("h3", 5_000), hit("h4", 9_001), hit("h5", 9_500)], [],
        {"durationMs": 10_000, "rallyGapMs": 2_000, "pointGapMs": 4_000, "preRollMs": 500, "postRollMs": 1_000},
        segmented([from_hits(1_000, 5_000, (500, 6_000), ["h1", "h2", "h3"], [(1_000, 2_500, 2), (5_000, 5_000, 1)]),
                   from_hits(9_001, 9_500, (8_501, 10_000), ["h4", "h5"], [(9_001, 9_500, 2)])])),
    seg("unsorted input; simultaneous hits order by id",
        [hit("hc", 21_000), hit("ha", 20_000), hit("hb", 21_000)], [], {"durationMs": 60_000, "excludedSide": None},
        segmented([from_hits(20_000, 21_000, (18_500, 23_500), ["ha", "hb", "hc"], [(20_000, 21_000, 3)])])),
    seg("refused: rally gap must be positive", [hit("h1", 0)], [], {"durationMs": 10, "rallyGapMs": 0},
        error="rallyGapNotPositive"),
    seg("refused: point gap below rally gap", [hit("h1", 0)], [],
        {"durationMs": 10, "rallyGapMs": 4_000, "pointGapMs": 3_000}, error="pointGapBelowRallyGap"),
    seg("refused: pre-roll above 10 s", [], [], {"durationMs": 10, "preRollMs": 10_001}, error="rollOutOfRange"),
    seg("refused: hit after the recording ends", [hit("h1", 10_001)], [], {"durationMs": 10_000},
        error="timeOutsideRecording"),
    seg("refused: a negative mark time", None, [mark("m1", -1)], {"durationMs": 10_000},
        error="timeOutsideRecording"),
    seg("refused: a hit and a mark share an id", [hit("x", 1_000)], [mark("x", 2_000)], {"durationMs": 10_000},
        error="duplicateId"),
])

R03 = ("R03-excluded-side", "Hits attributed to the excluded frame half never form rallies; marks are never masked", [
    seg("excluded left: left hits dropped, unattributed hits kept, no false point at 20 s",
        [hit("h1", 10_000, "right"), hit("h2", 11_000, "left"), hit("h3", 12_000), hit("h4", 20_000, "left"),
         hit("h5", 30_000, "right")], [], {"durationMs": 60_000, "excludedSide": "left"},
        segmented([from_hits(10_000, 12_000, (8_500, 14_500), ["h1", "h3"], [(10_000, 12_000, 2)]),
                   from_hits(30_000, 30_000, (28_500, 32_500), ["h5"], [(30_000, 30_000, 1)])],
                  excluded=["h2", "h4"])),
    seg("the same hits with no excluded side",
        [hit("h1", 10_000, "right"), hit("h2", 11_000, "left"), hit("h3", 12_000), hit("h4", 20_000, "left"),
         hit("h5", 30_000, "right")], [], {"durationMs": 60_000},
        segmented([from_hits(10_000, 12_000, (8_500, 14_500), ["h1", "h2", "h3"], [(10_000, 12_000, 3)]),
                   from_hits(20_000, 20_000, (18_500, 22_500), ["h4"], [(20_000, 20_000, 1)]),
                   from_hits(30_000, 30_000, (28_500, 32_500), ["h5"], [(30_000, 30_000, 1)])])),
    seg("bounces and other sounds are not hits",
        [hit("h1", 10_000), hit("o1", 40_000, kind="other"), hit("b1", 11_000, kind="bounce"), hit("h2", 12_000)],
        [], {"durationMs": 60_000},
        segmented([from_hits(10_000, 12_000, (8_500, 14_500), ["h1", "h2"], [(10_000, 12_000, 2)])],
                  not_hit=["b1", "o1"])),
    seg("excluded right: a mark among right-side hits still stands",
        [hit("r2", 51_000, "right"), hit("r1", 50_000, "right")], [mark("m1", 50_500)],
        {"durationMs": 60_000, "excludedSide": "right"},
        segmented([from_mark("m1", 50_500, (49_000, 53_000))], excluded=["r1", "r2"])),
])

R04 = ("R04-hits-and-marks", "With audio a point mark joins the first hit candidate whose clip holds it", [
    seg("marks inside the rolled clip attach; a mark outside stands alone",
        [hit("h1", 10_000), hit("h2", 12_000)], [mark("m1", 14_000), mark("m2", 30_000), mark("m3", 8_600)],
        {"durationMs": 60_000},
        segmented([from_hits(10_000, 12_000, (8_500, 14_500), ["h1", "h2"], [(10_000, 12_000, 2)], ["m3", "m1"]),
                   from_mark("m2", 30_000, (28_500, 32_500))])),
    seg("a mark where two clips overlap joins the earlier candidate",
        [hit("h1", 10_000), hit("h2", 16_000)], [mark("m1", 14_800)], {"durationMs": 60_000, "postRollMs": 5_000},
        segmented([from_hits(10_000, 10_000, (8_500, 15_000), ["h1"], [(10_000, 10_000, 1)], ["m1"]),
                   from_hits(16_000, 16_000, (14_500, 21_000), ["h2"], [(16_000, 16_000, 1)])])),
    seg("clips are half-open: a mark on the clip's last millisecond attaches, one at its end stands alone",
        [hit("h1", 10_000)], [mark("m1", 12_499), mark("m2", 12_500)], {"durationMs": 60_000},
        segmented([from_hits(10_000, 10_000, (8_500, 12_500), ["h1"], [(10_000, 10_000, 1)], ["m1"]),
                   from_mark("m2", 12_500, (11_000, 15_000))])),
])

SESSION_ROLLS = {"preRollMs": 2_000, "postRollMs": 3_000,
                 "clips": [{"targetId": "rp-point-2", "preRollMs": 500},
                           {"targetId": "rp-mark-1", "postRollMs": 4_000},
                           {"targetId": "rp-point-3", "excluded": True}]}
SESSION_TARGETS = [target("rp-point-1", 30_000, 38_000), target("rp-point-2", 52_000, 61_000),
                   target("rp-point-3", 80_000, 95_000), target("rp-mark-1", 100_000)]

R05 = ("R05-plan-rolls", "Per-session and per-clip rolls, deselected clips, merged ranges and gap chips", [
    plan("session rolls 2 s / 3 s, a per-clip pre-roll, a per-clip post-roll and a deselected point",
         SESSION_TARGETS, SESSION_ROLLS, 120_000,
         planned([rng(28_000, 41_000, ["rp-point-1"]), rng(51_500, 64_000, ["rp-point-2"]),
                  rng(98_000, 104_000, ["rp-mark-1"])],
                 [gap(0, 28_000, "+0:28"), gap(41_000, 51_500, "+0:10"), gap(64_000, 98_000, "+0:34"),
                  gap(104_000, 120_000, "+0:16")], 31_500, 88_500, 120_000, excluded=["rp-point-3"])),
    plan("no rallyPlayback: the defaults apply and the end is clamped", [target("p1", 30_000, 38_000)], None, 40_000,
         planned([rng(28_500, 40_000, ["p1"])], [gap(0, 28_500, "+0:28")], 11_500, 28_500, 40_000)),
    plan("touching ranges merge; a clip roll wins over the session roll",
         [target("c", 15_000, 16_000), target("a", 10_000, 12_000), target("b", 13_000, 15_000)],
         {"preRollMs": 0, "postRollMs": 0, "clips": [{"targetId": "a", "postRollMs": 1_000}]}, 20_000,
         planned([rng(10_000, 16_000, ["a", "b", "c"])], [gap(0, 10_000, "+0:10"), gap(16_000, 20_000, "+0:04")],
                 6_000, 14_000, 20_000)),
    plan("gap chips count hours from one hour", [target("x", 3_725_000, 3_730_000)],
         {"preRollMs": 0, "postRollMs": 0}, 3_800_000,
         planned([rng(3_725_000, 3_730_000, ["x"])], [gap(0, 3_725_000, "+1:02:05"), gap(3_730_000, 3_800_000, "+1:10")],
                 5_000, 3_795_000, 3_800_000)),
    plan("gap chips truncate to whole seconds", [target("y", 1_000, 2_000)], {"preRollMs": 0, "postRollMs": 0}, 2_999,
         planned([rng(1_000, 2_000, ["y"])], [gap(0, 1_000, "+0:01"), gap(2_000, 2_999, "+0:00")], 1_000, 1_999, 2_999)),
    plan("a clip override for a target not in the plan is ignored", [target("y", 1_000, 2_000)],
         {"preRollMs": 0, "postRollMs": 0, "clips": [{"targetId": "gone", "excluded": True}]}, 2_000,
         planned([rng(1_000, 2_000, ["y"])], [gap(0, 1_000, "+0:01")], 1_000, 1_000, 2_000)),
    plan("nothing to play: one gap over the whole recording", [], None, 60_000,
         planned([], [gap(0, 60_000, "+1:00")], 0, 60_000, 60_000)),
    plan("every clip deselected", [target("a", 1_000, 2_000)],
         {"preRollMs": 1_500, "postRollMs": 2_500, "clips": [{"targetId": "a", "excluded": True}]}, 60_000,
         planned([], [gap(0, 60_000, "+1:00")], 0, 60_000, 60_000, excluded=["a"])),
    plan("refused: a target that runs backwards", [target("a", 5_000, 4_000)], None, 60_000, error="rangeBackwards"),
    plan("refused: a target past the end", [target("a", 5_000, 60_001)], None, 60_000, error="timeOutsideRecording"),
    plan("refused: the same target twice", [target("a", 1_000), target("a", 2_000)], None, 60_000,
         error="duplicateId"),
    plan("refused: a clip post-roll above 10 s", [target("a", 1_000)],
         {"preRollMs": 1_500, "postRollMs": 2_500, "clips": [{"targetId": "a", "postRollMs": 10_001}]}, 60_000,
         error="rollOutOfRange"),
])

SAMPLE_PROV = {"status": "manual", "source": "user", "sample": True}
T = "2026-11-08T18:00:00Z"
JON, ALEX = "rp-player-jon", "rp-player-alex"


def _point(pid: str, seq: int, winner: str, start: int, end: int) -> dict:
    outcome = {"winner": winner, "endType": "winner", "serves": [{"result": "in"}], "strokeCount": 3,
               "provenance": "manual", "source": "user"}
    return {"id": pid, "seq": seq, "type": "point", "recordedServer": JON, "tStartMs": start, "tEndMs": end,
            "reviewed": outcome, "reviewState": "reviewed"}


def base_session() -> dict:
    """A small Sample match with three points and one point mark, before any roll is set."""
    log = [_point("rp-point-1", 1, "A", 30_000, 38_000), _point("rp-point-2", 2, "B", 52_000, 61_000),
           _point("rp-point-3", 3, "A", 80_000, 95_000)]
    return {
        "schemaVersion": SESSION_VERSION, "kind": "jovra.session", "id": "rp-session-rolls", "sport": "tennis",
        "createdAt": T, "updatedAt": T, "title": "Rally fixture: per-session and per-clip rolls",
        "sample": {"label": "Sample", "synthetic": True, "generator": "sample:rallyFixture@1.0.0"},
        "sessionKind": "match",
        "players": [{"id": JON, "displayName": "Jon", "handedness": "right", "backhand": "twoHanded", "isSelf": True},
                    {"id": ALEX, "displayName": "Alex", "handedness": "left", "backhand": "oneHanded",
                     "isSelf": False}],
        "sides": {"A": [JON], "B": [ALEX]},
        "match": {"format": {"presetId": "club_bo3", "setsToWin": 2, "gameScoring": "ad",
                             "set": {"kind": "tiebreakSet", "games": 6, "tiebreakAt": 6, "tiebreak": {"points": 7}},
                             "lets": "let"},
                  "toss": {"firstServer": JON, "startingEnds": {"A": "near", "B": "far"}}, "log": log},
        "recording": {"mode": "camera", "durationMs": 120_000,
                      "segments": [{"id": "rp-segment-0", "index": 0, "file": {"path": "media/segment-000.mp4"},
                                    "startMs": 0, "durationMs": 120_000, "frameRate": {"num": 60, "den": 1},
                                    "width": 1920, "height": 1080, "codec": "hevc", "hasAudio": False,
                                    "finalized": True}],
                      "gaps": [], "microphone": "notRequested", "mediaAvailable": True},
        "marks": [{"id": "rp-mark-1", "tMs": 100_000, "kind": "point", "provenance": SAMPLE_PROV}],
        "archive": {"state": "localOnly"},
        "storage": {"originals": "onDevice", "includeInDeviceBackup": False},
    }


def rolls_session() -> dict:
    """The edits a player makes in Playback settings and the Rallies list, applied in this order. The Swift test
    (JovraCoreTests/Rally) applies the same edits with JovraCore's writer and must produce these exact bytes."""
    doc = rally.set_session_rolls(base_session(), 2_000, 3_000)
    doc = rally.set_clip_rolls(doc, "rp-point-2", pre_roll_ms=500)
    doc = rally.set_clip_rolls(doc, "rp-mark-1", post_roll_ms=4_000)
    doc = rally.set_clip_excluded(doc, "rp-point-3", True)
    if doc["rallyPlayback"] != SESSION_ROLLS:
        raise ValueError(f"rolls writer disagrees with the hand-written rolls: {doc['rallyPlayback']}")
    match = doc["match"]
    scoring.fold({"format": match["format"], "players": doc["players"], "sides": doc["sides"],
                  "toss": match["toss"], "log": match["log"]}, match["log"])
    problems = references.session_problems(doc, None)
    if problems:
        raise ValueError("rolls session is inconsistent: " + "; ".join(problems))
    return doc


def case_problems(case: dict) -> list[str]:
    """Re-run one case through the reference and compare it with its hand-written result."""
    runner = rally.run_segment_case if case["op"] == "segment" else rally.run_plan_case
    actual = runner(case)
    wanted = {"error": case["expectedError"]} if "expectedError" in case else {"result": case["expected"]}
    problems = [] if actual == wanted else [f"{case['op']} case {case['name']!r}: expected {wanted!r}, engine {actual!r}"]
    if case["op"] == "plan" and "expected" in case:
        out = case["expected"]
        if out["keptMs"] + out["skippedMs"] != out["durationMs"]:
            problems.append(f"plan case {case['name']!r}: kept + skipped is not the recording")
    return problems


def _rally_fixtures(ctx) -> int:
    out = ctx.fixtures / "rally"
    for fixture_id, title, cases in (R01, R02, R03, R04, R05):
        problems = [p for c in cases for p in case_problems(c)]
        if problems:
            raise ValueError(f"{fixture_id}: " + "; ".join(problems))
        ctx.write_json(out / f"{fixture_id}.json", {
            "schemaVersion": RALLY_VERSION, "kind": "jovra.fixture.rally", "id": fixture_id, "title": title,
            "covers": ["T32", "ios-v1-spec RallySegmenter", "screens.md N7", "stories 192, 195, 200"],
            "cases": copy.deepcopy(cases)})
    ctx.write_json(out / "session.rolls.json", rolls_session())
    return 6


def generate(ctx) -> int:
    return _zero_stroke(ctx) + _rally_fixtures(ctx)


def check(path, doc, docs) -> list[str]:
    return [p for c in doc["cases"] for p in case_problems(c)]


CHECKS = {"jovra.fixture.rally": check}
