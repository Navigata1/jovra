#!/usr/bin/env python3
"""Recover every frame's match time from the multi-angle media and its committed ground truth (S58 acceptance 2).

    python3 scripts/media/studio/multiangle/recover.py                  every profile
    python3 scripts/media/studio/multiangle/recover.py --profile shake  one profile (repeatable)
    options: --report FILE (JSON summary), --jobs N

This reads only the ground-truth JSON under spec/studio/fixtures/media/multiangle/ and the rendered files, never the
generator's code. For each coded file it decodes every frame, reads the S08 barcode (source id, segment, frame id),
finds that camera and segment in the ground truth, takes the frame id's presentation time from the ground truth's
frame timing (CFR, or the VFR cycle) and applies the segment's transform ``offset + rate * t_src``. The result must
equal the match time the generator painted that frame at (kept beside the file in the cache, ``paintedMatchUs``)
within half an output frame; the run also requires the decoded presentation time to equal the ground-truth one and
reports the worst error (exact maps leave only microsecond rounding). Then it detects the clicks in the audio, maps
each onset to the match clock, subtracts the ground truth's sound delay and device latency, and compares the result
with the event's light time: that checks the sound-delay and arrival truth through the audio path. Needs ffmpeg.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
for _p in (HERE.parent, HERE.parents[1]):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

from jovra_media import encode  # noqa: E402
from jovra_studio_media import barcode as bc  # noqa: E402
from jovra_studio_media import pipeline  # noqa: E402

TRUTH = ROOT / "spec" / "studio" / "fixtures" / "media" / "multiangle"
US = 1_000_000
AUDIO_RATE = 48_000
LIGHT_TOLERANCE_US = 250      # click detection (a few samples) plus the arrival's rounding to a sample


class RecoveryError(Exception):
    pass


def exact(q: dict) -> Fraction:
    return Fraction(q["num"], q["den"])


def source_time_us(cam: dict, frame_id: int) -> Fraction:
    """A frame id's presentation time from the ground truth's frame timing alone."""
    timing, rate = cam["frameTiming"], Fraction(cam["frameRate"]["num"], cam["frameRate"]["den"])
    if timing["kind"] == "cfr":
        return Fraction(frame_id * US) / rate
    cycle = timing["cycle"]
    ticks = (frame_id // len(cycle)) * sum(cycle) + sum(cycle[: frame_id % len(cycle)])
    return Fraction(ticks * US, timing["timescale"])


def apply(transform: dict, source_us: Fraction) -> Fraction:
    return exact(transform["offsetUs"]) + exact(transform["rate"]) * source_us


def presentation_us(path: Path) -> list[Fraction]:
    """Every video frame's presentation time, sorted and counted from the first frame (the muxer may start the track
    at an offset). JSON output, because the compact writer's line shape varies with the stream's side data."""
    out = subprocess.run([encode.FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=time_base:packet=pts", "-of", "json", str(path)],
                         capture_output=True, text=True, check=True).stdout
    doc = json.loads(out)
    num, den = (int(x) for x in doc["streams"][0]["time_base"].split("/"))
    ticks = sorted(int(p["pts"]) for p in doc["packets"])
    return [Fraction((t - ticks[0]) * num * US, den) for t in ticks]


def rect_of(barcode: dict) -> tuple[int, int, int, int]:
    r = barcode["rect"]
    return r["x"], r["y"], r["width"], r["height"]


def recover_file(doc: dict, camera_id: str, segment: int) -> dict:
    """Recover one coded file. Raises RecoveryError on any frame outside tolerance or any inconsistency."""
    cams = {c["sourceId"]: c for c in doc["cameras"]}
    cam = next(c for c in doc["cameras"] if c["cameraId"] == camera_id)
    seg = next(s for s in cam["segments"] if s["segment"] == segment)
    coded = next(f for f in seg["files"] if f["variant"] == "coded")
    path = ROOT / coded["path"]
    sidecar = path.with_name(path.name + ".render.json")
    if not path.is_file() or not sidecar.is_file():
        raise RecoveryError(f"{coded['path']} is not rendered: run python3 scripts/media/studio/multiangle/generate.py")
    painted = json.loads(sidecar.read_text(encoding="utf-8"))["paintedMatchUs"]
    half = exact(doc["matchClock"]["halfOutputFrameUs"])
    pts = presentation_us(path)
    rect = rect_of(coded["barcode"])
    worst = Fraction(0)
    frames = 0
    # Decode to the end before judging, so a failure never closes the decoder (and its ffmpeg pipe) mid-file.
    payloads = [bc.read(luma, cam["width"], cam["height"], rect)
                for luma in pipeline.decoded_frames(path, cam["width"], cam["height"])]
    for n, p in enumerate(payloads):
        owner = cams.get(p.source)
        if owner is None:
            raise RecoveryError(f"{coded['fileName']} frame {n}: barcode source {p.source} is no camera of {doc['profile']}")
        piece = next((s for s in owner["segments"] if s["segment"] == p.segment), None)
        if piece is None:
            raise RecoveryError(f"{coded['fileName']} frame {n}: {owner['cameraId']} has no segment {p.segment}")
        t_src = source_time_us(owner, p.frame)
        if n >= len(pts) or pts[n] != t_src:
            raise RecoveryError(f"{coded['fileName']} frame {n}: presented at {pts[n] if n < len(pts) else None} us, "
                                f"the ground truth puts frame id {p.frame} at {t_src} us")
        recovered = apply(piece["transform"], t_src)
        error = abs(recovered - painted[n])
        if error > half:
            raise RecoveryError(f"{coded['fileName']} frame {n} (id {p.frame}): recovered {float(recovered):.1f} us, "
                                f"painted at {painted[n]} us ({float(error):.1f} us off, more than half an output frame)")
        worst = max(worst, error)
        frames += 1
    if frames != seg["frameCount"] or frames != len(painted):
        raise RecoveryError(f"{coded['fileName']}: decoded {frames} frames, the ground truth has {seg['frameCount']}")
    light = {e["id"]: Fraction(e["sceneSample"] * US, doc["scene"]["sceneSampleRate"]) for e in doc["scene"]["events"]}
    heard = sorted((a for a in cam["audioArrivals"] if a["heard"] and a["segment"] == segment),
                   key=lambda a: a["sourceSample"])
    onsets, _ = pipeline.decoded_audio(path)
    if len(onsets) != len(heard):
        raise RecoveryError(f"{coded['fileName']}: {len(onsets)} clicks detected, the ground truth hears {len(heard)}")
    light_worst = Fraction(0)
    for onset, a in zip(onsets, heard):
        at = apply(seg["transform"], Fraction(onset * US, AUDIO_RATE)) - a["delayUs"] - a["latencyUs"]
        error = abs(at - light[a["eventId"]])
        if error > LIGHT_TOLERANCE_US:
            raise RecoveryError(f"{coded['fileName']}: the click for {a['eventId']} maps to light time {float(at):.0f} us, "
                                f"{float(error):.0f} us from the event")
        light_worst = max(light_worst, error)
    return {"profile": doc["profile"], "file": coded["fileName"], "frames": frames,
            "maxFrameErrorUs": float(worst), "halfOutputFrameUs": float(half),
            "clicks": len(onsets), "maxLightTimeErrorUs": float(light_worst)}


def _job(args: tuple[str, str, int]) -> dict:
    pid, cid, k = args
    doc = json.loads((TRUTH / f"{pid}.json").read_text(encoding="utf-8"))
    try:
        return recover_file(doc, cid, k)
    except (RecoveryError, bc.BarcodeError, pipeline.StudioRenderError, subprocess.CalledProcessError) as e:
        return {"profile": pid, "file": f"{cid}-s{k}", "error": str(e)}


def profile_ids() -> list[str]:
    return sorted(p.stem for p in TRUTH.glob("*.json") if p.name != "rig.json")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--profile", action="append", dest="profiles")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    args = parser.parse_args(argv)
    pids = args.profiles or profile_ids()
    work = []
    for pid in pids:
        doc = json.loads((TRUTH / f"{pid}.json").read_text(encoding="utf-8"))
        work += [(pid, c["cameraId"], s["segment"]) for c in doc["cameras"] for s in c["segments"]]
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(_job, work))
    failures = [r for r in results if "error" in r]
    for r in results:
        if "error" in r:
            print(f"FAIL {r['profile']:30} {r['file']}: {r['error']}")
        else:
            print(f"  ok {r['profile']:30} {r['file']:34} frames {r['frames']:5}  max frame error {r['maxFrameErrorUs']:.3f} us "
                  f"(limit {r['halfOutputFrameUs']:.1f})  clicks {r['clicks']:2}  max light-time error "
                  f"{r['maxLightTimeErrorUs']:.1f} us")
    ok = [r for r in results if "error" not in r]
    print(f"==> {len(ok)} of {len(results)} coded files recovered: {sum(r['frames'] for r in ok):,} frames, worst frame "
          f"error {max((r['maxFrameErrorUs'] for r in ok), default=0):.3f} us, {sum(r['clicks'] for r in ok)} clicks, worst "
          f"light-time error {max((r['maxLightTimeErrorUs'] for r in ok), default=0):.1f} us")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({"files": results}, indent=2) + "\n", encoding="utf-8")
    print("multi-angle recovery: " + ("FAIL" if failures or not results else "PASS"))
    return 1 if failures or not results else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
