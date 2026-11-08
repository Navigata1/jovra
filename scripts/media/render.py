#!/usr/bin/env python3
"""Render JOVRA's media fixtures and write their ground truth.

    python3 scripts/media/render.py            render missing clips, write spec/fixtures/media/<set>/*.truth.json
                                               (refuses to rewrite a committed hash from a cached clip whose
                                               renderer source is unchanged: that clip was altered)
    python3 scripts/media/render.py --check    render missing clips, then fail unless every committed truth file
                                               (including each clip's decoded-frame hash) is reproduced byte-for-byte
    python3 scripts/media/render.py --force    re-encode every clip even when the cache has it
    options: --set NAME (repeatable), --cache DIR (default .cache/media under the repository root),
             --jobs N (clips rendered in parallel; default: the CPU count, at most 8)

A set module may also define ``INPUTS`` (repository files it reads, hashed into its source hash),
``BUDGET_BYTES`` (the run fails when the set's rendered files add up to more) and
``manifest(truths) -> (repo-relative path, document)``, a set-level document written next to the truth
(and compared byte-for-byte under --check), such as the benchmark corpus manifest.

Media goes to ``.cache/media/<set>-<hash16>/`` (git-ignored), keyed by the SHA-256 of the renderer core plus
that set's module, so editing a set re-renders only that set. Only ground truth and decoded-frame hashes are
committed. Needs ffmpeg with libx264, libx265 and ffv1 on PATH; standard-library Python 3.10+.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from jovra_media import encode, signature, truth  # noqa: E402
from jovra_media.sets import discover  # noqa: E402

TRUTH_DIR = ROOT / "spec" / "fixtures" / "media"
SIDECAR = ".render.json"


class RenderError(Exception):
    pass


def render_clip(clip, out: Path) -> dict:
    """Encode one clip, refusing any frame whose signature margin is too small, and confirm that the
    decoded signature of every frame equals the source signature."""
    source_levels: list[bytes] = []
    worst = [255]
    columns, rows = clip.grid
    source = hashlib.sha256()

    def check(index: int, canvas) -> None:
        source.update(canvas.raw())
        means = signature.cell_means(canvas.y, canvas.width, canvas.height, columns, rows)
        m = signature.margin(means, canvas.bit_depth)
        if m < signature.MIN_MARGIN:
            raise RenderError(f"{clip.id} frame {index}: a cell mean is {m} code values from a signature "
                              f"boundary (minimum {signature.MIN_MARGIN}); keep content flat per cell")
        worst[0] = min(worst[0], m)
        source_levels.append(signature.levels(means, canvas.bit_depth))

    encode.encode(clip, out, check)
    for i, decoded in enumerate(encode.decoded_signatures(clip, out)):
        if i >= len(source_levels) or decoded != source_levels[i]:
            out.unlink()
            raise RenderError(f"{clip.id}: decoded frame {i} does not match its source signature")
    return {"minimumMargin": worst[0], "frames": len(source_levels), "ffmpeg": encode.ffmpeg_version(),
            "sourceFramesSha256": source.hexdigest()}


def set_hash(module) -> str:
    return truth.source_hash(ROOT, Path(module.__file__), tuple(getattr(module, "INPUTS", ())))


def clip_truth(module, clip, cache_root: Path, force: bool, log) -> tuple[str, int]:
    src_hash = set_hash(module)
    folder = cache_root / f"{module.SET}-{src_hash[:16]}"
    out = folder / clip.file
    sidecar = out.with_name(out.name + SIDECAR)
    started = time.monotonic()
    if clip.duplicate_of:
        source = next(c for c in module.clips() if c.id == clip.duplicate_of)
        source_out = folder / source.file
        if not source_out.exists():
            raise RenderError(f"{clip.id}: render {source.id} first")
        if force or not out.exists() or out.read_bytes() != source_out.read_bytes():
            shutil.copyfile(source_out, out)
            shutil.copyfile(source_out.with_name(source_out.name + SIDECAR), sidecar)
        action = "copied"
    elif force or not out.exists() or not sidecar.exists():
        facts = render_clip(clip, out)
        sidecar.write_text(json.dumps(facts, sort_keys=True) + "\n", encoding="utf-8")
        action = "rendered"
    else:
        action = "cached"
    facts = json.loads(sidecar.read_text(encoding="utf-8"))
    hasher = signature.ClipHasher()
    for levels in encode.decoded_signatures(clip, out):
        hasher.add(levels)
    if hasher.frames != clip.frame_count:
        raise RenderError(f"{clip.id}: decoded {hasher.frames} frames, expected {clip.frame_count}")
    if clip.variable_frame_rate and encode.video_presentation_ticks(out) != (clip.vfr_timescale, clip.presentation_ticks()):
        raise RenderError(f"{clip.id}: the encoded presentation times are not the variable-frame-rate schedule "
                          f"(this ffmpeg rounded them back to a constant rate?)")
    if action != "rendered":
        committed = TRUTH_DIR / module.SET / f"{clip.id}.truth.json"
        if committed.exists():
            old = json.loads(committed.read_text(encoding="utf-8"))
            if old["renderer"]["sourceHash"] == src_hash and old["signature"]["decodedFramesSha256"] != hasher.hexdigest():
                raise RenderError(f"{clip.id}: the cached {out.name} decodes to sig {hasher.hexdigest()[:12]} but the committed "
                                  f"truth says {old['signature']['decodedFramesSha256'][:12]} for the same renderer source, so "
                                  f"the cached clip or the committed truth was altered. Re-render it with --force; if the "
                                  f"hash still differs, the committed truth is wrong")
    try:
        cache_rel = out.relative_to(ROOT).as_posix()
    except ValueError:
        cache_rel = (Path(".cache/media") / out.relative_to(cache_root)).as_posix()
    if "sourceFramesSha256" not in facts:
        raise RenderError(f"{clip.id}: the cached render predates source-frame hashing; re-render it with --force")
    doc = truth.document(module.SET, clip, src_hash, cache_rel, facts["minimumMargin"], hasher.hexdigest(), hasher.frames,
                         facts["sourceFramesSha256"])
    size = out.stat().st_size
    log(f"  {action:8} {module.SET}/{clip.id:32} {size:>10,} B  {time.monotonic() - started:5.1f} s  "
        f"frames {hasher.frames}  sig {hasher.hexdigest()[:12]}")
    return truth.dumps(doc), size


def prune(cache_root: Path, module, keep: str) -> None:
    for old in cache_root.glob(f"{module.SET}-*"):
        if old.is_dir() and old.name != keep:
            shutil.rmtree(old)


def _render_one(job: tuple[str, str, str, bool]) -> tuple[str, str, int | None, str]:
    """Worker: render one clip by (set, clip id). Re-discovers the set so nothing unpicklable crosses
    processes. Returns (clip id, truth text or failure, size or None, log line)."""
    set_name, clip_id, cache, force = job
    module = next(m for m in discover() if m.SET == set_name)
    clip = next(c for c in module.clips() if c.id == clip_id)
    lines: list[str] = []
    try:
        text, size = clip_truth(module, clip, Path(cache), force, lines.append)
    except (RenderError, RuntimeError, ValueError) as e:
        return clip_id, str(e), None, ""
    return clip_id, text, size, "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--set", action="append", dest="sets")
    parser.add_argument("--cache", type=Path, default=ROOT / ".cache" / "media")
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    args = parser.parse_args(argv)
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found on PATH (brew install ffmpeg / apt-get install ffmpeg)", file=sys.stderr)
        return 2
    print(f"==> {encode.ffmpeg_version()}")
    modules = [m for m in discover() if not args.sets or m.SET in args.sets]
    failures, total, produced = [], 0, set()
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for module in modules:
            src_hash = set_hash(module)
            print(f"==> set {module.SET} (renderer hash {src_hash[:16]})", flush=True)
            clips = module.clips()
            # Duplicates copy another clip's bytes, so they wait for every original to finish first.
            originals = [c for c in clips if not c.duplicate_of]
            duplicates = [c for c in clips if c.duplicate_of]
            results: dict[str, tuple[str, int | None]] = {}
            for batch in (originals, duplicates):
                jobs = [(module.SET, c.id, str(args.cache), args.force) for c in batch]
                for clip_id, text, size, log in pool.map(_render_one, jobs):
                    if log:
                        print(log, flush=True)
                    results[clip_id] = (text, size)
            set_size, texts = 0, {}
            for clip in clips:
                path = TRUTH_DIR / module.SET / f"{clip.id}.truth.json"
                produced.add(path)   # a clip that fails to render keeps its committed truth (never pruned as stale)
                text, size = results[clip.id]
                if size is None:
                    failures.append(text)
                    continue
                set_size += size
                texts[clip.id] = text
                if args.check:
                    if not path.exists():
                        failures.append(f"{path.relative_to(ROOT)} is not committed")
                    elif path.read_text(encoding="utf-8") != text:
                        old = json.loads(path.read_text(encoding="utf-8"))
                        new = json.loads(text)
                        keys = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
                        failures.append(f"{path.relative_to(ROOT)} differs from the render (fields: {', '.join(keys)})")
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(text, encoding="utf-8")
            total += set_size
            print(f"==> set {module.SET}: {len(clips)} clips, {set_size:,} bytes ({set_size / 1_048_576:.2f} MiB, "
                  f"{set_size / 1_000_000:.2f} MB)", flush=True)
            budget = getattr(module, "BUDGET_BYTES", None)
            if budget is not None:
                verdict = "within" if set_size <= budget else "OVER"
                print(f"==> set {module.SET} budget: {set_size / 1_000_000:.2f} MB of {budget / 1_000_000:.0f} MB ({verdict})")
                if set_size > budget:
                    failures.append(f"set {module.SET} renders {set_size:,} bytes, over its {budget:,}-byte budget")
            if hasattr(module, "manifest") and len(texts) == len(clips):
                rel, doc = module.manifest({cid: json.loads(t) for cid, t in texts.items()})
                target = ROOT / rel
                text = truth.dumps(doc)
                if args.check:
                    if not target.exists() or target.read_text(encoding="utf-8") != text:
                        failures.append(f"{rel} differs from the set's manifest")
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(text, encoding="utf-8")
            if not args.check:
                prune(args.cache, module, f"{module.SET}-{src_hash[:16]}")
            for stale in sorted((TRUTH_DIR / module.SET).glob("*.truth.json")):
                if stale not in produced:
                    if args.check:
                        failures.append(f"{stale.relative_to(ROOT)} has no clip in the renderer")
                    else:
                        stale.unlink()
    print(f"==> {len(produced)} clips, total rendered size {total:,} bytes ({total / 1_048_576:.2f} MiB)")
    for f in failures:
        print(f"FAIL {f}")
    if args.check:
        print("decoded-frame hash check: " + ("FAIL" if failures else f"PASS ({len(produced)} clips match the committed ground truth)"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
