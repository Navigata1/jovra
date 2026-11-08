"""The synthetic sample media (D8, ADR-0012): one rendered file per entry of the sample media manifest
(``spec/fixtures/sample/media-manifest.json``), with exactly its file name, duration, frame rate and size.

* The Jon vs Alex match covers the whole 54:00 timeline. Every one of the 124 points of the sample match
  (``spec/fixtures/sample/jon-vs-alex.points.csv``) is played inside its own [t_start, t_end) window: the
  serve (after a fault when the point was played on a second serve; two faults for a double fault), then a
  rally with the point's stroke count. Players change ends after odd games and walk round the net post.
* Serve practice clips are 12 (or 1-2) serves of known speed from behind the baseline; the ground truth
  names each serve's contact and bounce frames, court positions in millimetres, pixel positions and the
  true average contact-to-bounce speed (what ``serveSpeed.manualAssisted`` estimates).
* Stroke practice clips are side-on forehands with named key moments (Ready, Unit turn, Racket drop,
  Contact, Finish).

Every frame burns in "Sample video (synthetic)" (label.py). The scene is drawn from flat primitives only
(court3d.py): no real person, likeness, logo, photograph or font file.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

from .. import court3d as c3
from ..animation import Scene
from ..clip import AudioSpec, ClipSpec, EncodeOptions, Rate
from ..label import Label
from ..play import Play, baseline_y, other, side_on_forehands, uniform

SET = "sample"
ROOT = Path(__file__).resolve().parents[4]
MANIFEST = "spec/fixtures/sample/media-manifest.json"
POINTS = "spec/fixtures/sample/jon-vs-alex.points.csv"
INPUTS = (MANIFEST, POINTS)
BUDGET_BYTES = 60_000_000          # the bundled sample media budget (ticket T11): 60 MB
GRID = (8, 4)
SEED = 1006
ENCODE = EncodeOptions(crf=28, preset="medium", keyint=120, audio_bitrate="32k")


def behind_baseline(width: int, height: int) -> c3.Camera:
    """A phone on the back fence: 15 m behind the baseline, 7.5 m up, looking at the far service line."""
    return c3.Camera.looking((0.0, -15.0, 7.5), (0.0, 9.0, 0.0), 1.05 * width, width, height)


def side_on(width: int, height: int) -> c3.Camera:
    """Side-on, level with the hitting player: the net is to the right."""
    return c3.Camera.looking((8.8, 0.7, 1.3), (0.0, 0.7, 1.0), 1.15 * width, width, height)


def manifest_entries() -> list[dict]:
    return json.loads((ROOT / MANIFEST).read_text(encoding="utf-8"))["media"]


def slug(entry: dict) -> str:
    return entry["mediaId"].removeprefix("sample-media.")


# ----- scenes ----------------------------------------------------------------------------------

def jon_vs_alex(rate: Rate) -> tuple[Play, list[str]]:
    """The 124 points of the sample match on its own timeline (Jon is the near player at the start)."""
    play = Play(rate, SEED)
    rows = list(csv.DictReader((ROOT / POINTS).read_text(encoding="utf-8").splitlines()))
    jon_end = "near"
    near, far = play.tracks["near"], play.tracks["far"]
    near.key(0.0, 0.8, -0.9)
    far.key(0.0, -0.8, c3.LENGTH + 0.9)
    previous_end_ms = None
    for row in rows:
        games_done = int(row["game_number"]) - 1
        new_jon_end = "near" if ((games_done + 1) // 2) % 2 == 0 else "far"
        start, end = int(row["t_start_ms"]), int(row["t_end_ms"])
        if new_jon_end != jon_end and previous_end_ms is not None:
            walk_round_the_post(play, previous_end_ms / 1000, start / 1000)
            jon_end = new_jon_end
        server_end = jon_end if row["server"] == "Jon" else other(jon_end)
        play.point(int(row["point_number"]), start, end, server_end, row["court_side"],
                   int(row["stroke_count"]), row["serve_number"] == "2")
        previous_end_ms = end
    return play, ["near", "far"]


def walk_round_the_post(play: Play, after: float, before: float) -> None:
    """At a changeover both players walk round the net post, outside the doubles sideline, to the other
    end (so nobody walks through the net); then they swap ends in the play."""
    for end, x in (("near", c3.POST_X + 1.0), ("far", -(c3.POST_X + 1.0))):
        track = play.tracks[end]
        toward = 1 if end == "near" else -1
        track.key(after + 1.0, x * 0.6, baseline_y(end, 0.9))
        track.key(after + 3.0, x, c3.HALF - 2.0 * toward)
        track.key(before - 3.0, x, c3.HALF + 2.0 * toward)
        track.key(before - 2.0, x * 0.6, baseline_y(other(end), 0.9))
    play.tracks = {"near": play.tracks["far"], "far": play.tracks["near"]}


def short_match(rate: Rate, seed: int, duration_s: int) -> tuple[Play, list[str]]:
    """Two points in a 20 s thumbnail clip of an older match."""
    play = Play(rate, seed)
    play.tracks["near"].key(0.0, 0.8, -0.9)
    play.tracks["far"].key(0.0, -0.8, c3.LENGTH + 0.9)
    windows = ((600, 9_400), (10_600, duration_s * 1000 - 200))
    for k, (start, end) in enumerate(windows):
        strokes = 2 + play.rng.between(1, 4)
        play.point(k + 1, start, end, "near" if k % 2 == 0 else "far", "deuce" if k % 2 == 0 else "ad", strokes, False)
    return play, ["near", "far"]


def serve_practice(rate: Rate, seed: int, firsts: list[float], cam: c3.Camera) -> tuple[Play, list[str]]:
    """Serves from the near baseline at the given times, alternating deuce and ad, each at a seeded speed
    with the bounce on a whole frame, so contact and bounce frames are exact."""
    play = Play(rate, seed)
    play.tracks["near"].key(0.0, 0.6, -0.4)
    for k, at in enumerate(firsts):
        contact_frame = int(round(at * rate.fraction))
        side = "deuce" if k % 2 == 0 else "ad"
        speed = uniform(play.rng, 150, 190)
        play.serve(play.sample_of_frame(contact_frame), "near", side, speed, bounce_frame_aligned=True, cam=cam)
        play.run_out(at + 0.9)
    return play, ["near"]


def forehands(rate: Rate, seed: int, first: float, every: float, count: int) -> tuple[Play, list[str], object]:
    play = Play(rate, seed)
    swing = side_on_forehands(rate, first, every, count, play)
    return play, ["near"], swing


# ----- clips -----------------------------------------------------------------------------------

def build(entry: dict) -> ClipSpec:
    name = slug(entry)
    rate = Rate(entry["frameRate"]["num"], entry["frameRate"]["den"])
    width, height = entry["width"], entry["height"]
    frames = entry["durationMs"] * rate.num // (1000 * rate.den)
    seconds = entry["durationMs"] / 1000
    cam = behind_baseline(width, height) if entry["angle"] == "behindBaseline" else side_on(width, height)
    swing = None
    if name == "jon-vs-alex":
        play, ends = jon_vs_alex(rate)
    elif entry["sessionKind"] == "match" and entry["role"] == "practiceClip":
        play, ends = serve_practice(rate, 928, [3.0], cam)
    elif entry["sessionKind"] == "match":
        play, ends = short_match(rate, int(entry["sessionDate"].replace("-", "")) % 10_000, int(seconds))
    elif entry["sessionKind"] == "servePractice":
        if entry["role"] == "practiceClip":
            times = [4.0 + 9.5 * k for k in range(12)]
        else:
            times = [4.0, 13.0]
        play, ends = serve_practice(rate, int(entry["sessionDate"].replace("-", "")) % 10_000, times, cam)
    else:
        every = 2.9 if seconds > 20 else 3.0
        count = int((seconds - 2.1) // every)
        play, ends, swing = forehands(rate, int(entry["sessionDate"].replace("-", "")) % 10_000 + 7, 1.8, every, count)
    scene = Scene(width, height, rate, cam, GRID, [play.tracks[e] for e in ends], play.ball, side_on=swing)
    events = play.events()
    if any(e.sample >= frames * 48_000 * rate.den // rate.num for e in events):
        raise ValueError(f"{name}: a hit falls after the end of the clip")
    label = Label(width, height, height // GRID[1])
    extra = {
        "sampleMedia": {"mediaId": entry["mediaId"], "thumbnailFrame": thumbnail_frame(play, rate, frames)},
        "label": label.truth(),
        "camera": {"angle": entry["angle"]},
    }
    if play.rallies:
        extra["rallies"] = play.rallies
    if play.bounces:
        extra["bounces"] = [{k: v for k, v in b.items() if k != "sample"} for b in play.bounces]
    if play.serves:
        extra["serves"] = play.serves
    if swing is not None:
        extra["swings"] = [
            {"index": k, "keyMoments": {m: {"frame": int(t * rate.num / rate.den)} for m, t in swing.key_moments(tc).items()}}
            for k, tc in enumerate(swing.contacts)
        ]
    if play.net_faults:
        raise ValueError(f"{name}: {play.net_faults} rally shots could not clear the net")
    return ClipSpec(
        id=name, file=entry["fileName"],
        description=f"Sample video (synthetic): {entry.get('purpose', name)}"[:300],
        codec="h264", width=width, height=height, rate=rate, frame_count=frames,
        paint=scene.paint, grid=GRID, audio=AudioSpec(events=events, tiled_noise=True), seed=SEED,
        frame_code=False, encode=ENCODE, extra=extra,
    )


def thumbnail_frame(play: Play, rate: Rate, frames: int) -> int:
    """A frame with the ball in play: half a second after the second hit (or the first)."""
    hits = sorted(play.hits)
    if not hits:
        return frames // 2
    pick = hits[1] if len(hits) > 1 else hits[0]
    if len(play.rallies) > 40:     # the full match: Point 42, the point the demo opens on
        rally = next(r for r in play.rallies if r["pointNumber"] == 42)
        pick = rally["start"]["value"] * 48_000 // rally["start"]["timescale"] + 48_000 * 2
    return min(frames - 1, int((pick + 24_000) * rate.num // (48_000 * rate.den)))


def clips() -> list[ClipSpec]:
    return [build(entry) for entry in manifest_entries()]
