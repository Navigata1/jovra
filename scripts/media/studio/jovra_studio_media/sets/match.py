"""The coherent synthetic match with barcode and click tracks (film-engine section 7; ADR-0012 extended).

It is the core T11 sample match, not a new one: the same 124 points of the Jon vs Alex sample
(``spec/fixtures/sample/jon-vs-alex.points.csv``), played by T11's ``sample.jon_vs_alex`` on the full 54:00 timeline
and drawn by T11's court scene from the behind-the-baseline camera, with the "Sample video (synthetic)" label. Studio
adds three things:

* a 40-bit barcode strip in the bottom 20 px (source 16; frame id = frame index), below every signature cell's central
  half, so the scene's decoded-frame signature is unchanged;
* a 1 kHz click (``clicks.py``) at every hit, the hit onsets T11's play records;
* the point event log of the sample session and the score it must fold to through the core reference
  (``spec/reference/jovra_ref/scoring.py``), stated here as a literal and checked by the Studio validator and tests.

H.264 640x360 at 30 fps (half the T11 rate, so a full decode stays quick), 97,200 frames.
"""

from __future__ import annotations

import json
from pathlib import Path

from jovra_media.animation import Scene
from jovra_media.clip import ClipSpec, EncodeOptions, Rate
from jovra_media.sets import sample as t11

from ..badge import sample_label_truth
from ..model import StudioClip, with_barcode

SET = "match"
ROOT = Path(__file__).resolve().parents[5]
SESSION = "spec/fixtures/sample/jon-vs-alex.session.json"
INPUTS = (t11.MANIFEST, t11.POINTS, SESSION)
WIDTH, HEIGHT, GRID = 640, 360, t11.GRID
RATE = Rate(30)
DURATION_MS = 3_240_000
SOURCE_ID = 16
BARCODE_RECT = (0, 340, 640, 20)
# The score the 124 point events fold to (core sample: Jon beats Alex 6-4 6-3). A claim, checked by folding.
EXPECTED = {"scoreline": "6-4 6-3", "winnerSide": "A", "sets": [{"A": 6, "B": 4}, {"A": 6, "B": 3}], "status": "completed"}


def session() -> dict:
    return json.loads((ROOT / SESSION).read_text(encoding="utf-8"))


def point_windows(play, log: list[dict]) -> list[dict]:
    rate = RATE
    out = []
    for event, rally in zip(log, play.rallies):
        start, end = event["tStartMs"], event["tEndMs"]
        out.append({"pointNumber": rally["pointNumber"], "eventId": event["id"], "tStartMs": start, "tEndMs": end,
                    "startFrame": start * rate.num // (1000 * rate.den), "endFrame": end * rate.num // (1000 * rate.den),
                    "hits": rally["hits"]})
    return out


def clips() -> list[StudioClip]:
    play, ends = t11.jon_vs_alex(RATE)
    cam = t11.behind_baseline(WIDTH, HEIGHT)
    scene = Scene(WIDTH, HEIGHT, RATE, cam, GRID, [play.tracks[e] for e in ends], play.ball)
    frames = DURATION_MS * RATE.num // (1000 * RATE.den)
    s = session()
    log = s["match"]["log"]
    if len(log) != len(play.rallies) or any(e["seq"] != r["pointNumber"] for e, r in zip(log, play.rallies)):
        raise ValueError("the session's point log and the played points differ")
    core = ClipSpec(id="match-jon-vs-alex", file="match-jon-vs-alex-360p30.mp4",
                    description="Sample video (synthetic): the Jon vs Alex sample match, 54:00, behind the baseline, "
                                "with a frame barcode and a 1 kHz click at every hit.",
                    codec="h264", width=WIDTH, height=HEIGHT, rate=RATE, frame_count=frames,
                    paint=with_barcode(scene.paint, SOURCE_ID, 0, 0, BARCODE_RECT), grid=GRID, seed=t11.SEED,
                    frame_code=False, encode=EncodeOptions(crf=28, keyint=60))
    extra = {"match": {
        "basedOn": {"mediaId": "sample-media.jon-vs-alex", "points": t11.POINTS, "session": SESSION,
                    "camera": "behindBaseline"},
        "setup": {"format": s["match"]["format"], "toss": s["match"]["toss"], "sides": s["sides"]},
        "log": log,
        "points": point_windows(play, log),
        "expected": EXPECTED,
    }}
    return [StudioClip(core=core, role="match", source_id=SOURCE_ID, barcode_rect=BARCODE_RECT,
                       clicks=tuple(sorted(play.hits)), audio_seed=SOURCE_ID,
                       labels=(sample_label_truth(WIDTH, HEIGHT, HEIGHT // GRID[1]),), extra=extra)]
