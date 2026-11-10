"""The committed ground truth of the multi-angle generator (only these files are committed; the media is not).

* ``rig()`` -> ``spec/studio/fixtures/media/multiangle/rig.json`` (``jovra.studio-multiangle-rig/1``): the six
  placements and the research 4.4 sound-delay and pairwise-bias tables computed from them.
* ``profile_plan(pid)`` -> ``spec/studio/fixtures/media/multiangle/<profile>.json``
  (``jovra.studio-multiangle-truth/1``), everything but ``hashes``: the scene events, and per camera its clock (true
  offset and drift), segments with their exact piece transforms and match coverage, restart gaps (host and match
  clock), the capture journal when there is one, the shake stretch, the frame on screen at every visible event, each
  hit's sound arrival (delay to this placement, device latency, source sample, heard or why not) and every file it
  renders (coded and clean). ``plan`` computes all of it without drawing a pixel, so the Studio validator recomputes
  it on every run (spec/reference/studio/cases/multiangle_cases.py).
* ``hashes`` (written by ``generate.py`` after a render): per file the drawn-frame SHA-256, the decoded-frame
  signature and the click-track PCM SHA-256, which every machine reproduces. The media files' own SHA-256 differ
  between ffmpeg builds and are printed in the run log instead (S08's rule).

Exact quantities are rationals ``{"num", "den"}`` in microseconds (offsets) or per unit (rates); ``...Us`` integers
are the same times rounded half up.
"""

from __future__ import annotations

import hashlib
import json
from fractions import Fraction
from itertools import combinations
from pathlib import Path

from jovra_media import truth as core_truth
from jovra_studio_media import barcode as bc
from jovra_studio_media import clicks as ck
from jovra_studio_media.badge import AngleBadge, sample_label_truth
from studio import syncfit

from . import profiles, scene
from .rig import (AUDIO_RATE, BARCODE_RECT, BIAS_PAIRS, GRID, HEIGHT, PLACEMENTS, SHAKE_HOLD, SHAKE_PATTERN,
                  RATE_DEN, SHAKE_SETTLED, TABLE_ROWS, US, WIDTH, CameraSpec, half_up)

RIG_SCHEMA = "jovra.studio-multiangle-rig/1"
SCHEMA = "jovra.studio-multiangle-truth/1"
GENERATOR_VERSION = "1.0.0"
SCRIPT = "scripts/media/studio/multiangle/generate.py"
CACHE = Path(".cache/media/studio")
FIXTURES = "media/multiangle"           # under spec/studio/fixtures
SPEED_MM_PER_S = syncfit.DEFAULT_SPEED_MM_PER_S
OUTPUT_FPS = Fraction(30)
EDGE_SAMPLES = 4_800                    # a click is heard only 100 ms or more inside its file (the detector's quiet lead)
VARIANTS = ("coded", "clean")

ROOT = Path(__file__).resolve().parents[5]
PACKAGE = Path(__file__).resolve().parent


# ----- the source hash ---------------------------------------------------------------------------

def source_files() -> list[str]:
    """Every file whose bytes can change a pixel, a click or a ground-truth fact (repo-relative)."""
    studio = ROOT / "scripts" / "media" / "studio"
    files = [*(studio / "jovra_studio_media" / f for f in ("barcode.py", "clicks.py", "model.py", "pipeline.py",
                                                         "badge.py")),
             studio / "jovra_studio_media" / "sets" / "angles.py", studio / "multiangle" / "generate.py",
             *PACKAGE.glob("*.py"), *(ROOT / "spec" / "reference" / "studio" / f for f in ("syncfit.py", "core.py"))]
    return sorted({p.relative_to(ROOT).as_posix() for p in files} | set(scene.INPUTS))


def source_hash() -> str:
    """SHA-256 over T10's renderer core plus ``source_files()`` (S08's ``source_hash`` rule)."""
    return core_truth.source_hash(ROOT, PACKAGE / "__init__.py", tuple(source_files()))


def cache_folder(src_hash: str) -> Path:
    return CACHE / f"multiangle-{src_hash[:16]}"


def file_name(camera_id: str, segment: int, variant: str) -> str:
    return f"{camera_id}-s{segment}-{variant}.mp4"


# ----- helpers -----------------------------------------------------------------------------------

def dumps(doc: dict) -> str:
    """The exact bytes spec/reference/studio/generate_studio_fixtures.py writes for a fixture."""
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def q(value: Fraction) -> dict:
    value = Fraction(value)
    return {"num": value.numerator, "den": value.denominator}


def rate_q(cam: CameraSpec) -> dict:
    """A clock rate held to 1 ppb, as studio-common's ``rate`` (den 1e9, never reduced)."""
    return {"num": RATE_DEN + cam.drift_ppb, "den": RATE_DEN}


def interval(start: Fraction, end: Fraction) -> dict:
    return {"startUs": half_up(start), "endUs": half_up(end)}


def delay_us(event_mm: dict, mic_mm: dict) -> int:
    """Sound travel from an event to a microphone, whole microseconds (syncfit's exact half-up rule)."""
    return syncfit.sound_delay_us(event_mm, mic_mm, SPEED_MM_PER_S)


def frame_times_sha256(cam: CameraSpec, k: int) -> str:
    """SHA-256 of every frame's match time (half-up microseconds, 8-byte big-endian signed) in file order."""
    sha = hashlib.sha256()
    for n in range(cam.segments[k].frames):
        sha.update(half_up(cam.frame_match_us(k, n)).to_bytes(8, "big", signed=True))
    return sha.hexdigest()


def frame_map_sha256(source_id: int, segment: int, frames: int) -> str:
    """S08's frame-map hash: 5 bytes per frame (source, segment, 24-bit frame id) in file order."""
    sha = hashlib.sha256()
    for n in range(frames):
        sha.update(bytes([source_id, segment]) + n.to_bytes(3, "big"))
    return sha.hexdigest()


def audio_samples(cam: CameraSpec, k: int) -> int:
    samples = cam.segment_duration_us(k) * AUDIO_RATE / US
    if samples.denominator != 1:
        raise ValueError(f"{cam.id}: segment {k} is not a whole number of 48 kHz samples")
    return int(samples)


def labels(cam: CameraSpec) -> list[dict]:
    cell_h = HEIGHT // GRID[1]
    return [sample_label_truth(WIDTH, HEIGHT, cell_h), AngleBadge(WIDTH, HEIGHT, cell_h, cam.placement.name).truth()]


# ----- the rig -----------------------------------------------------------------------------------

def placements() -> list[dict]:
    return [{"code": p.code, "slot": p.slot, "name": p.name, "positionMm": dict(p.position_mm),
             "picture": f"angle-{p.picture}"} for p in PLACEMENTS.values()]


def rig() -> dict:
    rows = [{"id": rid, "event": label, "positionMm": dict(pos),
             "delaysUs": {code: delay_us(pos, p.position_mm) for code, p in PLACEMENTS.items()}}
            for rid, label, pos in TABLE_ROWS]
    biases = [{"id": r["id"], "biasUs": {f"{a}-{b}": r["delaysUs"][a] - r["delaysUs"][b] for a, b in BIAS_PAIRS}}
              for r in rows if r["id"] != "south-baseline-wide"]
    return {
        "schemaVersion": RIG_SCHEMA,
        "id": "multiangle/rig",
        "sample": True,
        "description": "The six club-fence phone placements of the synthetic multi-angle rig and the sound travel from "
                       "the multicam research 4.4 table events to each (343 m/s, impact 1.0 m, phones 1.5 m).",
        "speedOfSound": {"mmPerSecond": SPEED_MM_PER_S, "temperatureC": None, "method": "default-343"},
        "placements": placements(),
        "soundDelayTable": {"source": "docs/research/studio/multicam-sync.md section 4.4 (club fence)", "rows": rows},
        "pairwiseBiasTable": {"rule": "(d_A - d_B) / c, the bias an uncorrected audio lag adds to the clock offset",
                              "pairs": [f"{a}-{b}" for a, b in BIAS_PAIRS], "rows": biases},
    }


# ----- one camera --------------------------------------------------------------------------------

def arrivals(cam: CameraSpec) -> list[dict]:
    """Each racket contact's sound at this camera: light time + travel to the placement + device latency."""
    out = []
    for e in scene.events():
        if not e.audible:
            continue
        d = delay_us(e.position_mm, cam.placement.position_mm)
        arrival = e.light_us + d + cam.latency_us
        k = cam.segment_at(arrival)
        row = {"eventId": e.id, "delayUs": d, "latencyUs": cam.latency_us, "arrivalMatchUs": half_up(arrival),
               "segment": k, "sourceSample": None, "heard": False, "reason": None}
        if k is None:
            row["reason"] = "notRecording"
        else:
            sample = half_up(cam.to_source_us(k, arrival) * AUDIO_RATE / US)
            row["sourceSample"] = sample
            if cam.audio == "muted":
                row["reason"] = "muted"
            elif sample < EDGE_SAMPLES or sample + ck.SAMPLES + EDGE_SAMPLES > audio_samples(cam, k):
                row["reason"] = "fileEdge"
            else:
                row["heard"] = True
        out.append(row)
    return out


def visual_events(cam: CameraSpec) -> list[dict]:
    """The frame on screen at each event's light time, for every event the camera records (none when covered)."""
    if cam.view == "covered":
        return []
    out = []
    for e in scene.events():
        k = cam.segment_at(e.light_us)
        if k is None:
            continue
        n = cam.frame_at(k, e.light_us)
        s = cam.shake
        out.append({"eventId": e.id, "kind": e.kind, "segment": k, "frame": n,
                    "frameMatchUs": half_up(cam.frame_match_us(k, n)),
                    "inShake": s is not None and s.segment == k and s.from_frame <= n < s.to_frame})
    return out


def files(cam: CameraSpec, k: int, src_hash: str, heard: list[int]) -> list[dict]:
    out = []
    for variant in VARIANTS:
        name = file_name(cam.id, k, variant)
        barcode = None
        if variant == "coded":
            frames = cam.segments[k].frames
            barcode = dict(bc.layout(BARCODE_RECT), sourceId=cam.source_id, segment=k,
                           frameMap=[{"frame": 0, "frameId": 0, "count": frames}],
                           frameMapSha256=frame_map_sha256(cam.source_id, k, frames))
        out.append({"variant": variant, "fileName": name, "path": (cache_folder(src_hash) / name).as_posix(),
                    "audioSampleCount": audio_samples(cam, k), "audioSeed": audio_seed(cam, k),
                    "clickSamples": heard, "barcode": barcode, "labels": labels(cam)})
    return out


def audio_seed(cam: CameraSpec, k: int) -> int:
    return cam.source_id * 8 + k


def segments(cam: CameraSpec, src_hash: str, heard: list[dict]) -> list[dict]:
    out = []
    for k, seg in enumerate(cam.segments):
        start, end = cam.coverage_us(k)
        clicks = sorted(a["sourceSample"] for a in heard if a["heard"] and a["segment"] == k)
        out.append({"segment": k, "frameCount": seg.frames, "hostStartUs": seg.host_start_us,
                    "sourceDurationUs": q(cam.segment_duration_us(k)),
                    "transform": {"offsetUs": q(cam.segment_offset_us(k)), "rate": rate_q(cam)},
                    "matchCoverageUs": interval(start, end),
                    "frameTimesSha256": frame_times_sha256(cam, k),
                    "files": files(cam, k, src_hash, clicks)})
    return out


def gaps(cam: CameraSpec) -> list[dict]:
    out = []
    for k in range(len(cam.segments) - 1):
        host_end = cam.segments[k].host_start_us + cam.segment_duration_us(k)
        out.append({"afterSegment": k, "reason": "restart",
                    "hostUs": interval(host_end, Fraction(cam.segments[k + 1].host_start_us)),
                    "matchUs": interval(cam.coverage_us(k)[1], cam.coverage_us(k + 1)[0])})
    return out


def camera(cam: CameraSpec, src_hash: str) -> dict:
    heard = arrivals(cam)
    s = cam.shake
    return {
        "cameraId": cam.id,
        "reference": cam.reference,
        "placement": cam.code,
        "slot": cam.placement.slot,
        "name": cam.placement.name,
        "positionMm": dict(cam.placement.position_mm),
        "view": cam.view,
        "sourceId": cam.source_id,
        "codec": "hevc" if cam.hdr else "h264",
        "bitDepth": 10 if cam.hdr else 8,
        "hdr": cam.hdr,
        "rotation": cam.rotation,
        "width": WIDTH,
        "height": HEIGHT,
        "frameRate": {"num": cam.fps.num, "den": cam.fps.den},
        "frameTiming": ({"kind": "vfr", "timescale": cam.vfr_timescale, "cycle": list(cam.vfr_cycle)}
                        if cam.vfr_cycle else {"kind": "cfr"}),
        "clock": {"driftPpb": cam.drift_ppb, "rate": rate_q(cam), "hostOffsetUs": cam.host_offset_us},
        "journal": ({"segments": [{"segment": k, "fileZeroHostUs": seg.host_start_us}
                                  for k, seg in enumerate(cam.segments)]} if cam.journal else None),
        "audio": {"mode": cam.audio, "latencyUs": cam.latency_us, "sampleRate": AUDIO_RATE, "channels": 1},
        "segments": segments(cam, src_hash, heard),
        "gaps": gaps(cam),
        "shake": None if s is None else {
            "segment": s.segment, "fromFrame": s.from_frame, "toFrame": s.to_frame,
            "matchUs": interval(cam.frame_match_us(s.segment, s.from_frame), cam.frame_match_us(s.segment, s.to_frame)),
            "holdFrames": SHAKE_HOLD, "nudgesDeg": [{"yaw": y, "pitch": p} for y, p in SHAKE_PATTERN],
            "settledNudgeDeg": {"yaw": SHAKE_SETTLED[0], "pitch": SHAKE_SETTLED[1]}},
        "visualEvents": visual_events(cam),
        "audioArrivals": heard,
    }


# ----- one profile -------------------------------------------------------------------------------

def shared_coverage(cams: list[CameraSpec]) -> list[dict]:
    out = []
    for a, b in combinations(cams, 2):
        spans = []
        for ka in range(len(a.segments)):
            for kb in range(len(b.segments)):
                (sa, ea), (sb, eb) = a.coverage_us(ka), b.coverage_us(kb)
                lo, hi = max(sa, sb), min(ea, eb)
                if lo < hi:
                    spans.append((lo, hi))
        out.append({"cameras": [a.id, b.id], "matchUs": [interval(lo, hi) for lo, hi in sorted(spans)] or None})
    return out


def profile_ids() -> list[str]:
    return [p.id for p in profiles.PROFILES]


def profile_plan(pid: str, src_hash: str | None = None) -> dict:
    src_hash = src_hash or source_hash()
    p = profiles.profile(pid)
    cams = [profiles.CAMERAS[c] for c in p.cameras]
    ref = next(c for c in cams if c.reference)
    return {
        "schemaVersion": SCHEMA,
        "id": f"multiangle/{p.id}",
        "profile": p.id,
        "description": p.description,
        "stresses": list(p.stresses),
        "sample": True,
        "band": "synthetic",
        "generator": {"script": SCRIPT, "version": GENERATOR_VERSION, "sourceHash": src_hash},
        "rig": f"{FIXTURES}/rig.json",
        "matchClock": {"unit": "us", "referenceCameraId": ref.id, "referenceSegment": 0, "origin": "scene-start",
                       "outputFps": {"num": OUTPUT_FPS.numerator, "den": OUTPUT_FPS.denominator},
                       "halfOutputFrameUs": q(Fraction(US) / OUTPUT_FPS / 2)},
        "speedOfSound": {"mmPerSecond": SPEED_MM_PER_S, "temperatureC": None, "method": "default-343"},
        "scene": {"basedOn": {"mediaId": "sample-media.jon-vs-alex", "points": scene.INPUTS[1],
                              "window": "the first 120 s of the sample match (its points 1-6)"},
                  "durationUs": scene.SCENE_US, "sceneSampleRate": AUDIO_RATE, "events": scene.as_dicts()},
        "cameras": [camera(c, src_hash) for c in cams],
        "sharedCoverage": shared_coverage(cams),
    }


def document(plan_doc: dict, file_hashes: dict | None) -> dict:
    doc = dict(plan_doc)
    if file_hashes is not None:
        doc["hashes"] = file_hashes
    return doc
