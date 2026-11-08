"""The synthetic benchmark corpus (D8, ADR-0004): the clips analysis estimators are tuned and gated on.

Four kinds, each rendered from tuning seeds (1xx) and held-out seeds (2xx); the harness gates on held-out
seeds only and a seed never appears in both splits:

* ``neighbourCourtClicks`` - rallies whose audio also carries a neighbouring court's hits, 12 dB quieter
  and lower in pitch, never within 120 ms of an own-court hit. They are ``distractors`` in the ground
  truth, never ``events``, so an own-court hit detector that fires on them loses precision.
* ``cameraNudges`` - rallies during which the tripod is knocked by exactly 1 degree (yaw or pitch) at known
  frames (``cameraMoves``).
* ``serves`` - 12 serves per clip from behind the baseline, contact and bounce on whole frames, with true
  average contact-to-bounce speeds.
* ``noNudge`` - 15-minute low-resolution (320 x 180) rallies with a camera that never moves: 2 h in all,
  the denominator for camera-moved false alarms per hour.

``manifest()`` writes ``spec/benchmarks/corpus/manifest.json``: the clips by split, and the totals.
Corpus clips are never shown in the app, so they carry no burned-in label; their ground truth says
``band: synthetic`` like every rendered fixture, and no synthetic result ever promotes a capability.
"""

from __future__ import annotations

from .. import court3d as c3
from ..animation import Scene
from ..clip import AUDIO_RATE, AudioSpec, ClipSpec, EncodeOptions, Event, Rate
from ..play import Play, rational, uniform

SET = "corpus"
MANIFEST_PATH = "spec/benchmarks/corpus/manifest.json"
GRID = (8, 4)
ENCODE = EncodeOptions(crf=28, preset="veryfast", keyint=300, audio_bitrate="48k")
MIN_NO_NUDGE_MS = 2 * 60 * 60 * 1000
DISTRACTOR_GAP = AUDIO_RATE * 120 // 1000
KINDS = {
    # kind: (seeds by split, width, height, fps, seconds)
    "neighbourCourtClicks": ({"tuning": (101, 102), "heldOut": (201, 202)}, 640, 360, 30, 60),
    "cameraNudges": ({"tuning": (111, 112), "heldOut": (211, 212)}, 640, 360, 30, 60),
    "serves": ({"tuning": (121, 122), "heldOut": (221, 222)}, 640, 360, 60, 60),
    "noNudge": ({"tuning": (131, 132, 133, 134), "heldOut": (231, 232, 233, 234)}, 320, 180, 30, 900),
}


def camera(width: int, height: int) -> c3.Camera:
    return c3.Camera.looking((0.0, -15.0, 7.5), (0.0, 9.0, 0.0), 1.05 * width, width, height)


def rally_stream(play: Play, seconds: int) -> None:
    """Points back to back: 4-12 s windows with 4-9 s between them, serving ends and sides alternating
    like a real game, stroke counts 1-8 (with some second serves and double faults)."""
    rng = play.rng
    play.tracks["near"].key(0.0, 0.8, -0.9)
    play.tracks["far"].key(0.0, -0.8, c3.LENGTH + 0.9)
    t_ms, number = 1_000, 1
    while True:
        strokes = rng.between(0, 8)
        window = 2_500 + 1_250 * max(1, strokes) + rng.between(0, 1_500)
        if t_ms + window > seconds * 1000 - 500:
            break
        second = strokes > 0 and rng.between(0, 4) == 0
        server = "near" if (number - 1) // 6 % 2 == 0 else "far"
        play.point(number, t_ms, t_ms + window, server, "deuce" if number % 2 else "ad", strokes, second)
        t_ms += window + rng.between(4_000, 9_000)
        number += 1


def distractors(play: Play, seconds: int) -> tuple[Event, ...]:
    """A neighbouring court's rally: clicks every 0.9-1.6 s in bursts, kept 120 ms clear of own hits."""
    rng = play.rng
    own = sorted(play.hits)
    out, t = [], AUDIO_RATE * 2
    end = seconds * AUDIO_RATE - AUDIO_RATE
    while t < end:
        if all(abs(t - h) >= DISTRACTOR_GAP for h in own):
            out.append(Event("neighbourCourtHit", t))
        t += rng.between(AUDIO_RATE * 9 // 10, AUDIO_RATE * 16 // 10)
        if rng.between(0, 5) == 0:
            t += rng.between(AUDIO_RATE * 3, AUDIO_RATE * 8)     # the neighbours stop between points
    return tuple(out)


def build(kind: str, split: str, seed: int) -> ClipSpec:
    _, width, height, fps, seconds = KINDS[kind]
    rate = Rate(fps)
    frames = fps * seconds
    cam = camera(width, height)
    play = Play(rate, seed)
    moves, extra_audio = [], ()
    if kind == "serves":
        play.tracks["near"].key(0.0, 0.6, -0.4)
        for k in range(12):
            at = 2.5 + 4.75 * k
            frame = int(round(at * fps))
            play.serve(play.sample_of_frame(frame), "near", "deuce" if k % 2 == 0 else "ad",
                       uniform(play.rng, 140, 195), bounce_frame_aligned=True, cam=cam)
            play.run_out(at + 0.9)
        tracks = [play.tracks["near"]]
    else:
        rally_stream(play, seconds)
        tracks = [play.tracks["near"], play.tracks["far"]]
    if kind == "neighbourCourtClicks":
        extra_audio = distractors(play, seconds)
    if kind == "cameraNudges":
        current = cam
        for k, at in enumerate(sorted(uniform(play.rng, 8 + 17 * i, 20 + 17 * i) for i in range(3))):
            yaw, pitch = ((1, 0), (0, -1), (-1, 0))[(seed + k) % 3]
            current = current.nudged(yaw=yaw, pitch=pitch)
            moves.append((int(round(at * fps)), current, yaw, pitch))
    scene = Scene(width, height, rate, cam, GRID, tracks, play.ball, label=False,
                  camera_moves=[(f, c) for f, c, _, _ in moves])
    extra = {
        "corpus": {"kind": kind},
        "camera": {"angle": "behindBaseline"},
        "cameraMoves": [{"frame": f, "time": rational(f * AUDIO_RATE // fps), "kind": "nudge",
                         "yawDegrees": yaw, "pitchDegrees": pitch} for f, _, yaw, pitch in moves],
    }
    if play.rallies:
        extra["rallies"] = play.rallies
    if play.bounces:
        extra["bounces"] = [{k: v for k, v in b.items() if k != "sample"} for b in play.bounces]
    if play.serves:
        extra["serves"] = play.serves
    if extra_audio:
        extra["distractors"] = [{"type": e.type, "time": rational(e.sample), "sample": e.sample,
                                 "frame": e.sample * fps // AUDIO_RATE} for e in extra_audio]
    if play.net_faults:
        raise ValueError(f"{kind} seed {seed}: {play.net_faults} rally shots could not clear the net")
    slug = {"neighbourCourtClicks": "neighbour", "cameraNudges": "nudge", "serves": "serves", "noNudge": "static"}[kind]
    return ClipSpec(
        id=f"{slug}-s{seed}", file=f"corpus-{slug}-s{seed}.mp4",
        description=f"Benchmark corpus, {kind}, seed {seed} ({split}).",
        codec="h264", width=width, height=height, rate=rate, frame_count=frames, paint=scene.paint, grid=GRID,
        audio=AudioSpec(events=play.events(), distractors=extra_audio, tiled_noise=True),
        seed=seed, split=split, frame_code=False, encode=ENCODE, extra=extra,
    )


def clips() -> list[ClipSpec]:
    out = []
    for kind, (splits, *_rest) in KINDS.items():
        for split, seeds in splits.items():
            out += [build(kind, split, seed) for seed in seeds]
    return out


def manifest(truths: dict[str, dict]) -> tuple[str, dict]:
    """The corpus manifest: every clip under its split, and the no-nudge total the false-alarm rate needs."""
    splits: dict[str, list] = {"tuning": [], "heldOut": []}
    no_nudge = {"tuning": 0, "heldOut": 0}
    source = None
    for clip_id in sorted(truths):
        doc = truths[clip_id]
        source = doc["renderer"]["sourceHash"]
        v = doc["video"]
        duration_ms = v["frameCount"] * 1000 * v["frameRate"]["den"] // v["frameRate"]["num"]
        kind = doc["corpus"]["kind"]
        splits[doc["split"]].append({
            "truthId": doc["id"], "seed": doc["seed"], "kind": kind, "durationMs": duration_ms,
            "width": v["codedWidth"], "height": v["codedHeight"], "frameRate": v["frameRate"],
            "events": len(doc.get("events", [])), "distractors": len(doc.get("distractors", [])),
            "cameraMoves": len(doc.get("cameraMoves", [])), "serves": len(doc.get("serves", [])),
        })
        if kind == "noNudge":
            no_nudge[doc["split"]] += duration_ms
    doc = {
        "schemaVersion": "1.0.0",
        "kind": "jovra.benchmarkCorpus",
        "band": "synthetic",
        "set": SET,
        "renderer": {"script": "scripts/media/render.py", "sourceHash": source},
        "kinds": sorted(KINDS),
        "splits": splits,
        "totals": {
            "clips": {"tuning": len(splits["tuning"]), "heldOut": len(splits["heldOut"])},
            "noNudgeMs": {"tuning": no_nudge["tuning"], "heldOut": no_nudge["heldOut"],
                          "all": no_nudge["tuning"] + no_nudge["heldOut"]},
        },
        "minimumNoNudgeMs": MIN_NO_NUDGE_MS,
    }
    return MANIFEST_PATH, doc
