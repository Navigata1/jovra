#!/usr/bin/env python3
"""Measure the S08 media the barcode-court context binds, and check that the context still matches it.

    python3 scripts/media/studio/barcode_court.py --check     regenerate any missing media into the cache with the S08
                                                              generator, then compare every file's SHA-256, size and
                                                              decoded PTS index with the committed context; exit 1 when
                                                              the context is stale
    python3 scripts/media/studio/barcode_court.py --measure   the same, then write the measurements into
                                                              spec/studio/fixtures/vectors/barcode-court.json and
                                                              regenerate the Studio fixtures (records and vectors)
    options: --cache DIR (default .cache/media/studio)

The barcode-court context (spec/studio/modules/barcode-court.md) binds real media files: each SourceManifest carries
the file's SHA-256 and the hash of its decoded PTS table. The media is never committed; it is regenerated at test time
by the S08 generator (scripts/media/studio/render_studio.py) into the git-ignored cache. A file's bytes depend on the
ffmpeg build (media-fixtures.md, "Manifests"), so the measurements name the encoder that made them and the generator
source they were made from: a different generator source is a stale context, and a different encoder is reported as
not comparable rather than compared. The validator runs the same check when JOVRA_STUDIO_MEDIA=1 is set.
Needs ffmpeg and ffprobe on PATH; standard-library Python 3.10+.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
for _p in (HERE, HERE.parent):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

import render_studio  # noqa: E402
from jovra_media import encode  # noqa: E402
from jovra_studio_media import manifest, pipeline  # noqa: E402
from jovra_studio_media.sets import discover  # noqa: E402

VECTOR = ROOT / "spec" / "studio" / "fixtures" / "vectors" / "barcode-court.json"
MEDIA_CASE = "media"


def clip_for(rel: str):
    """(set module, clip) for an S08 manifest id such as 'barcodeSources/bc-060'."""
    set_name, clip_id = rel.split("/")
    module = next(m for m in discover() if m.SET == set_name)
    return module, next(c for c in module.clips() if c.id == clip_id)


def live_source_hash(rel: str) -> str:
    """The S08 generator's source hash for this clip's set, as the generator computes it now."""
    module, _ = clip_for(rel)
    return render_studio.set_hash(module)


def ensure_rendered(rel: str, cache: Path) -> Path:
    """The cached file for the current generator source, rendered by the S08 pipeline when it is missing."""
    module, clip = clip_for(rel)
    src_hash = render_studio.set_hash(module)
    out = cache / f"{module.SET}-{src_hash[:16]}" / clip.file
    sidecar = out.with_name(out.name + render_studio.SIDECAR)
    if not out.exists() or not sidecar.exists():
        facts = pipeline.render(clip, out)
        sidecar.write_text(json.dumps(facts, sort_keys=True) + "\n", encoding="utf-8")
    return out


def decoded_pts(path: Path) -> dict:
    """The decoded presentation index of the video track: time base and every frame's PTS from the first."""
    den, ticks = encode.video_presentation_ticks(path)
    return {"timescale": den, "ticks": ticks}


def measure_one(rel: str, cache: Path) -> dict:
    path = ensure_rendered(rel, cache)
    pts = decoded_pts(path)
    return {"measuredWithSourceHash": live_source_hash(rel), "encoder": encode.ffmpeg_version(),
            "sha256": pipeline.file_sha256(path), "sizeBytes": path.stat().st_size,
            "videoTimescale": pts["timescale"], "ptsTicks": compress(pts["ticks"])}


def compress(ticks: list) -> list:
    """Canonical runs {value, step, count} (the jovra.pts-table/1 greedy form)."""
    runs, i, n = [], 0, len(ticks)
    while i < n:
        if i + 1 == n:
            runs.append({"value": ticks[i], "step": 0, "count": 1})
            break
        step, j = ticks[i + 1] - ticks[i], i + 1
        while j + 1 < n and ticks[j + 1] - ticks[j] == step:
            j += 1
        runs.append({"value": ticks[i], "step": step, "count": j - i + 1})
        i = j + 1
    return runs


def committed_media() -> list:
    doc = json.loads(VECTOR.read_text(encoding="utf-8"))
    return next(c for c in doc["cases"] if c["id"] == MEDIA_CASE)["input"]["media"]


def compare(entries: list, cache: Path) -> list:
    """Problems between the committed measurements and the media the S08 generator produces now (empty: current)."""
    problems = []
    encoder = encode.ffmpeg_version()
    for e in entries:
        rel, stored = e["manifest"], e["measured"]
        if stored is None:
            problems.append(f"{rel}: not measured yet")
            continue
        now = live_source_hash(rel)
        if stored["measuredWithSourceHash"] != now:
            problems.append(f"{rel}: stale, measured from generator source {stored['measuredWithSourceHash'][:16]}, "
                            f"the generator is now {now[:16]}")
        if stored["encoder"] != encoder:
            problems.append(f"{rel}: measured with '{stored['encoder']}', this machine has '{encoder}'; file hashes "
                            "are per encoder build, so they are not comparable here")
            continue
        got = measure_one(rel, cache)
        for key in ("sha256", "sizeBytes", "videoTimescale", "ptsTicks"):
            if got[key] != stored[key]:
                shown = f" ({stored[key]} in the context, {got[key]} regenerated)" if key != "ptsTicks" else ""
                problems.append(f"{rel}: stale, the regenerated file's {key} differs from the context's{shown}")
    return problems


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--measure", action="store_true")
    parser.add_argument("--cache", type=Path, default=ROOT / manifest.CACHE)
    args = parser.parse_args(argv)
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        print("ffmpeg and ffprobe are needed on PATH", file=sys.stderr)
        return 2
    print(f"==> {encode.ffmpeg_version()}")
    entries = committed_media()
    if args.check:
        problems = compare(entries, args.cache)
        for e in entries:
            if e["measured"] is not None:
                print(f"  {e['manifest']:38} sha256 {e['measured']['sha256']}")
        for p in problems:
            print(f"FAIL {p}")
        print("barcode-court media: " + ("STALE" if problems else f"CURRENT ({len(entries)} files match the context)"))
        return 1 if problems else 0
    doc = json.loads(VECTOR.read_text(encoding="utf-8"))
    case = next(c for c in doc["cases"] if c["id"] == MEDIA_CASE)
    for e in case["input"]["media"]:
        e["measured"] = measure_one(e["manifest"], args.cache)
        print(f"  {e['manifest']:38} sha256 {e['measured']['sha256']}  {e['measured']['sizeBytes']:,} B")
    VECTOR.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    gen = ROOT / "spec" / "reference" / "studio" / "generate_studio_fixtures.py"
    return subprocess.run([sys.executable, str(gen)], cwd=ROOT).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
