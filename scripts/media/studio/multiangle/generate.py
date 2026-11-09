#!/usr/bin/env python3
"""Render the synthetic multi-angle fixtures (S58) and write their ground truth.

    python3 scripts/media/studio/multiangle/generate.py             render what the cache lacks, (re)write the ground
                                                                     truth under spec/studio/fixtures/media/multiangle/
    python3 scripts/media/studio/multiangle/generate.py --check     render what the cache lacks, verify every file and
                                                                     fail unless every committed file is reproduced
    python3 scripts/media/studio/multiangle/generate.py --force --sha256-log run.txt
                                                                     re-encode everything; list each file's SHA-256
    options: --camera ID (repeatable), --cache DIR (default .cache/media/studio), --jobs N

Every camera segment is rendered twice (coded: with the S08 frame barcode; clean: without), each by S08's pipeline on
T10's renderer core, then decoded in full: every barcode must read back as its frame index, every heard click must be
detected within one frame with none extra, a VFR file's presentation times must be its cycle, a rotated file must
carry its display matrix, and the match times the painter drew must hash to the ground truth's ``frameTimesSha256``.
Media stays in the git-ignored cache (``.cache/media/studio/multiangle-<hash16>/``); only the ground truth is
committed. Needs ffmpeg with libx264 and libx265; standard-library Python 3.10+.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
for _p in (HERE, HERE.parent, HERE.parents[1], ROOT / "spec" / "reference"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

from jovra_media import encode  # noqa: E402
from jovra_multiangle import clips, profiles, truth  # noqa: E402
from jovra_studio_media import pipeline  # noqa: E402

FIXTURES = ROOT / "spec" / "studio" / "fixtures"
SIDECAR = ".render.json"


class GenerateError(Exception):
    pass


def jobs_for(cameras: list[str]) -> list[tuple[str, int, str]]:
    return [(cid, k, v) for cid in cameras for k in range(len(profiles.CAMERAS[cid].segments)) for v in truth.VARIANTS]


def _segment_doc(cid: str, k: int, src_hash: str) -> dict:
    cam = profiles.CAMERAS[cid]
    return truth.segments(cam, src_hash, truth.arrivals(cam))[k]


def rotation_of(path: Path) -> int:
    """Clockwise display rotation from the video stream's display matrix (ffprobe reports it counter-clockwise)."""
    out = subprocess.run([encode.FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_streams", "-of", "json",
                          str(path)], capture_output=True, text=True, check=True).stdout
    side = json.loads(out)["streams"][0].get("side_data_list", [])
    values = [int(s["rotation"]) for s in side if "rotation" in s]
    return (-values[0]) % 360 if values else 0


def _render_one(job: tuple[str, int, str, str, str, bool]) -> dict:
    """Worker: render (or reuse) and verify one file. Returns its hashes and log line, or an error."""
    cid, k, variant, src_hash, cache, force = job
    cam = profiles.CAMERAS[cid]
    seg = _segment_doc(cid, k, src_hash)
    entry = next(f for f in seg["files"] if f["variant"] == variant)
    description = (f"Sample video (synthetic): the multi-angle scene from {cam.placement.name} ({cam.code}), "
                   f"camera {cid}, segment {k}, {variant}.")
    studio, painter = clips.clip(cam, k, variant, entry["clickSamples"], description)
    out = Path(cache) / truth.cache_folder(src_hash).name / entry["fileName"]
    sidecar = out.with_name(out.name + SIDECAR)
    started = time.monotonic()
    try:
        if force or not out.exists() or not sidecar.exists():
            facts = pipeline.render(studio, out)
            facts["paintedMatchUs"] = painter.painted
            sidecar.write_text(json.dumps(facts, sort_keys=True) + "\n", encoding="utf-8")
            action = "rendered"
        else:
            facts = json.loads(sidecar.read_text(encoding="utf-8"))
            action = "cached"
        checked = pipeline.verify(studio, out)
        painted = facts["paintedMatchUs"]
        sha = hashlib.sha256(b"".join(t.to_bytes(8, "big", signed=True) for t in painted)).hexdigest()
        if len(painted) != cam.segments[k].frames or sha != seg["frameTimesSha256"]:
            raise GenerateError(f"{entry['fileName']}: the painted match times are not the ground truth's frame times")
        if cam.vfr_cycle:
            ticks = encode.video_presentation_ticks(out)
            if ticks != (cam.vfr_timescale, studio.core.presentation_ticks()):
                raise GenerateError(f"{entry['fileName']}: presentation times are not the VFR cycle")
        if rotation_of(out) != cam.rotation:
            raise GenerateError(f"{entry['fileName']}: display rotation {rotation_of(out)}, expected {cam.rotation}")
    except (pipeline.StudioRenderError, GenerateError, RuntimeError, ValueError) as e:
        return {"file": entry["fileName"], "error": str(e)}
    worst = max((abs(e) for e in checked.click_sample_errors), default=0)
    log = (f"  {action:8} {entry['fileName']:34} {checked.size:>10,} B {time.monotonic() - started:6.1f} s  "
           f"frames {checked.frames} barcodes {checked.barcode_frames}  clicks {checked.clicks} "
           f"(max {worst} samples off)  sha256 {checked.file_sha256}")
    return {"file": entry["fileName"], "sha256": checked.file_sha256, "size": checked.size, "log": log,
            "hashes": {"sourceFramesSha256": facts["sourceFramesSha256"],
                       "decodedSignature": {"method": "jovra.cellLuma.v1", "sha256": checked.decoded_signature},
                       "pcmSha256": facts["pcmSha256"]}}


def compare_or_write(path: Path, text: str, check: bool, failures: list[str]) -> None:
    if check:
        if not path.exists():
            failures.append(f"{path.relative_to(ROOT)} is not committed")
        elif path.read_text(encoding="utf-8") != text:
            old, new = json.loads(path.read_text(encoding="utf-8")), json.loads(text)
            keys = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
            failures.append(f"{path.relative_to(ROOT)} differs from the generator (fields: {', '.join(keys)})")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--camera", action="append", dest="cameras")
    parser.add_argument("--cache", type=Path, default=ROOT / truth.CACHE)
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--sha256-log", type=Path)
    args = parser.parse_args(argv)
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        print("ffmpeg/ffprobe not found on PATH (brew install ffmpeg / apt-get install ffmpeg)", file=sys.stderr)
        return 2
    src_hash = truth.source_hash()
    print(f"==> {encode.ffmpeg_version()}")
    print(f"==> multi-angle generator {truth.GENERATOR_VERSION} (source hash {src_hash[:16]})")
    cameras = args.cameras or profiles.cameras_in_use()
    unknown = sorted(set(cameras) - set(profiles.CAMERAS))
    if unknown:
        print(f"unknown camera(s): {', '.join(unknown)}", file=sys.stderr)
        return 2
    work = jobs_for(cameras)
    work.sort(key=lambda j: -profiles.CAMERAS[j[0]].segments[j[1]].frames)    # longest first
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(_render_one, [(c, k, v, src_hash, str(args.cache), args.force) for c, k, v in work]))
    failures = [f"{r['file']}: {r['error']}" for r in results if "error" in r]
    done = {r["file"]: r for r in results if "error" not in r}
    for r in sorted(done.values(), key=lambda r: r["file"]):
        print(r["log"])
    total = sum(r["size"] for r in done.values())
    print(f"==> {len(done)} files verified, {total:,} bytes ({total / 1_000_000:.1f} MB)")
    if truth.source_hash() != src_hash:
        failures.append("the generator source changed during the run; run again")
    if not args.cameras:
        compare_or_write(FIXTURES / truth.FIXTURES / "rig.json", truth.dumps(truth.rig()), args.check, failures)
        written = {FIXTURES / truth.FIXTURES / "rig.json"}
        for pid in truth.profile_ids():
            plan = truth.profile_plan(pid, src_hash)
            names = sorted(f["fileName"] for c in plan["cameras"] for s in c["segments"] for f in s["files"])
            if any(n not in done for n in names):
                failures.append(f"profile {pid}: not every file verified, its ground truth is left as it was")
                written.add(FIXTURES / truth.FIXTURES / f"{pid}.json")
                continue
            hashes = {"renderedWithSourceHash": src_hash, "files": {n: done[n]["hashes"] for n in names}}
            path = FIXTURES / truth.FIXTURES / f"{pid}.json"
            written.add(path)
            compare_or_write(path, truth.dumps(truth.document(plan, hashes)), args.check, failures)
        for stale in sorted((FIXTURES / truth.FIXTURES).glob("*.json")):
            if stale not in written:
                if args.check:
                    failures.append(f"{stale.relative_to(ROOT)} has no profile in the generator")
                else:
                    stale.unlink()
        if not args.check and not failures:
            for old in args.cache.glob("multiangle-*"):
                if old.is_dir() and old.name != truth.cache_folder(src_hash).name:
                    shutil.rmtree(old)
    if args.sha256_log:
        args.sha256_log.parent.mkdir(parents=True, exist_ok=True)
        args.sha256_log.write_text("".join(f"{done[n]['sha256']}  {n}\n" for n in sorted(done)), encoding="utf-8")
    for f in failures:
        print(f"FAIL {f}")
    if args.check:
        print("multi-angle check: " + ("FAIL" if failures else f"PASS ({len(done)} files verified, ground truth matches)"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
