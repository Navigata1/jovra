#!/usr/bin/env python3
"""Render JOVRA Studio's media fixtures and write their ground-truth manifests.

    python3 scripts/media/studio/render_studio.py              render missing media, then (re)write the manifests
                                                               under spec/studio/fixtures/media/
    python3 scripts/media/studio/render_studio.py --check      render missing media, verify every file, and fail
                                                               unless every committed manifest is reproduced exactly
    python3 scripts/media/studio/render_studio.py --force      re-encode everything, even what the cache has
    options: --set NAME (repeatable), --cache DIR (default .cache/media/studio), --jobs N,
             --sha256-log FILE (write "<sha256>  <set>/<file>" for every media file, for the two-run check)

Every clip is drawn and encoded by T10's renderer core (scripts/media/render.py ``render_clip``), its click track is
muxed after, and then the finished file is decoded in full: every frame's barcode must read back as its frame map,
every click must be detected within +/-1 frame with none extra, and the decoded-frame signature is hashed. Only the
manifests are committed; the media stays in the git-ignored cache, keyed by the source hash of the renderer core, the
Studio package and the set module. Needs ffmpeg with libx264 on PATH; standard-library Python 3.10+.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from jovra_media import encode, truth  # noqa: E402
from jovra_studio_media import manifest, pipeline  # noqa: E402
from jovra_studio_media.sets import discover  # noqa: E402

FIXTURES = ROOT / "spec" / "studio" / "fixtures"
SIDECAR = ".render.json"
DEMO_SUBSET = "media/demo-subset.json"
DEMO_BUDGET_BYTES = 25_000_000    # the bundled Studio demo subset (S08; the lead confirms the figure)


def studio_files() -> list[str]:
    """The Studio renderer's own source, hashed into every set's source hash with the core files."""
    package = HERE / "jovra_studio_media"
    files = [HERE / "render_studio.py", *package.glob("*.py"), package / "sets" / "__init__.py"]
    return sorted(p.relative_to(ROOT).as_posix() for p in files)


def set_hash(module) -> str:
    return truth.source_hash(ROOT, Path(module.__file__), tuple(studio_files()) + tuple(getattr(module, "INPUTS", ())))


def plan_for(module, clip, src_hash: str | None = None) -> dict:
    return manifest.plan(module.SET, clip, src_hash or set_hash(module))


def demo_subset(modules) -> dict:
    """The bundled demo subset: every clip marked ``bundled``, in set then clip order."""
    files = []
    for module in modules:
        for clip in module.clips():
            if clip.bundled:
                files.append({"manifest": manifest.rel_path(module.SET, clip.id), "fileName": clip.file,
                              "role": clip.role, **({"angle": clip.extra["angle"]["name"]} if "angle" in clip.extra else {})})
    return {"schemaVersion": "jovra.studio-media-demo-subset/1", "sample": True,
            "installTo": "ios/Jovra/Resources/StudioSampleMedia", "budgetBytes": DEMO_BUDGET_BYTES,
            "installer": "scripts/media/studio/install_demo.py", "files": files}


def _render_one(job: tuple[str, str, str, str, bool]) -> dict:
    """Worker: render (or reuse) and verify one clip; returns its manifest text and run facts, or an error. The
    source hash is the one taken when the run started, so an edit during a run never moves its output."""
    set_name, src_hash, clip_id, cache, force = job
    module = next(m for m in discover() if m.SET == set_name)
    clip = next(c for c in module.clips() if c.id == clip_id)
    folder = Path(cache) / f"{set_name}-{src_hash[:16]}"
    out = folder / clip.file
    sidecar = out.with_name(out.name + SIDECAR)
    started = time.monotonic()
    try:
        if force or not out.exists() or not sidecar.exists():
            facts = pipeline.render(clip, out)
            sidecar.write_text(json.dumps(facts, sort_keys=True) + "\n", encoding="utf-8")
            action = "rendered"
        else:
            facts = json.loads(sidecar.read_text(encoding="utf-8"))
            action = "cached"
        checked = pipeline.verify(clip, out)
    except (pipeline.StudioRenderError, RuntimeError, ValueError) as e:
        return {"id": clip_id, "error": str(e)}
    hashes = manifest.hashes(src_hash, facts["sourceFramesSha256"], checked.decoded_signature, facts["pcmSha256"])
    doc = manifest.document(plan_for(module, clip, src_hash), hashes)
    worst = max((abs(e) for e in checked.click_frame_errors), default=0)
    worst_samples = max((abs(e) for e in checked.click_sample_errors), default=0)
    log = (f"  {action:8} {set_name}/{clip.file:34} {checked.size:>11,} B  {time.monotonic() - started:6.1f} s  "
           f"frames {checked.frames} barcodes {checked.barcode_frames}/{checked.frames}  clicks {checked.clicks} "
           f"(max {worst} frame, {worst_samples} samples off)  sha256 {checked.file_sha256}")
    return {"id": clip_id, "text": manifest.dumps(doc), "size": checked.size, "sha256": checked.file_sha256,
            "file": f"{set_name}/{clip.file}", "bundled": clip.bundled, "log": log}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--set", action="append", dest="sets")
    parser.add_argument("--cache", type=Path, default=ROOT / manifest.CACHE)
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--sha256-log", type=Path)
    args = parser.parse_args(argv)
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found on PATH (brew install ffmpeg / apt-get install ffmpeg)", file=sys.stderr)
        return 2
    print(f"==> {encode.ffmpeg_version()}")
    print(f"==> studio media generator {manifest.GENERATOR_VERSION}")
    all_modules = discover()
    modules = [m for m in all_modules if not args.sets or m.SET in args.sets]
    failures: list[str] = []
    sha_lines: list[str] = []
    bundled_bytes = 0
    hashes = {m.SET: set_hash(m) for m in modules}
    jobs = [(m.SET, hashes[m.SET], c.id, str(args.cache), args.force) for m in modules for c in m.clips()]
    # Longest clips first, so the long match does not start last.
    lengths = {(m.SET, c.id): c.frame_count * c.core.width * c.core.height for m in modules for c in m.clips()}
    jobs.sort(key=lambda j: -lengths[(j[0], j[2])])
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = {(job[0], r["id"]): r for job, r in zip(jobs, pool.map(_render_one, jobs))}
    for module in modules:
        src_hash = hashes[module.SET]
        if src_hash != set_hash(module):
            failures.append(f"set {module.SET}: its source changed during the run; run again")
        set_failures = len(failures)
        folder = FIXTURES / "media" / module.SET
        print(f"==> set {module.SET} (source hash {src_hash[:16]})")
        produced = set()
        set_bytes = 0
        for clip in module.clips():
            r = results[(module.SET, clip.id)]
            path = FIXTURES / manifest.rel_path(module.SET, clip.id)
            produced.add(path)
            if "error" in r:
                failures.append(f"{module.SET}/{clip.id}: {r['error']}")
                continue
            print(r["log"])
            set_bytes += r["size"]
            bundled_bytes += r["size"] if r["bundled"] else 0
            sha_lines.append(f"{r['sha256']}  {r['file']}")
            if args.check:
                if not path.exists():
                    failures.append(f"{path.relative_to(ROOT)} is not committed")
                elif path.read_text(encoding="utf-8") != r["text"]:
                    old, new = json.loads(path.read_text(encoding="utf-8")), json.loads(r["text"])
                    keys = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
                    failures.append(f"{path.relative_to(ROOT)} differs from the render (fields: {', '.join(keys)})")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(r["text"], encoding="utf-8")
        print(f"==> set {module.SET}: {len(produced)} files, {set_bytes:,} bytes ({set_bytes / 1_000_000:.2f} MB)")
        for stale in sorted(folder.glob("*.json")):
            if stale not in produced:
                if args.check:
                    failures.append(f"{stale.relative_to(ROOT)} has no clip in the generator")
                else:
                    stale.unlink()
        if not args.check and len(failures) == set_failures:
            for old in args.cache.glob(f"{module.SET}-*"):
                if old.is_dir() and old.name != f"{module.SET}-{src_hash[:16]}":
                    shutil.rmtree(old)
    if not args.sets:
        subset = manifest.dumps(demo_subset(all_modules))
        target = FIXTURES / DEMO_SUBSET
        if args.check:
            if not target.exists() or target.read_text(encoding="utf-8") != subset:
                failures.append(f"{target.relative_to(ROOT)} differs from the generator")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(subset, encoding="utf-8")
        verdict = "within" if bundled_bytes <= DEMO_BUDGET_BYTES else "OVER"
        print(f"==> demo subset: {bundled_bytes:,} bytes ({bundled_bytes / 1_000_000:.2f} MB of "
              f"{DEMO_BUDGET_BYTES / 1_000_000:.0f} MB, {verdict})")
        if bundled_bytes > DEMO_BUDGET_BYTES:
            failures.append(f"the demo subset renders {bundled_bytes:,} bytes, over its {DEMO_BUDGET_BYTES:,}-byte budget")
    if args.sha256_log:
        args.sha256_log.parent.mkdir(parents=True, exist_ok=True)
        args.sha256_log.write_text("".join(f"{line}\n" for line in sorted(sha_lines, key=lambda s: s.split("  ")[1])),
                                   encoding="utf-8")
    for f in failures:
        print(f"FAIL {f}")
    if args.check:
        print("studio media check: " + ("FAIL" if failures else f"PASS ({len(jobs)} files verified, manifests match)"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
