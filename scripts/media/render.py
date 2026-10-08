#!/usr/bin/env python3
"""Render JOVRA's media fixtures and write their ground truth.

    python3 scripts/media/render.py            render missing clips, write spec/fixtures/media/<set>/*.truth.json
                                               (refuses to rewrite a committed hash from a cached clip whose
                                               renderer source is unchanged: that clip was altered)
    python3 scripts/media/render.py --check    render missing clips, then fail unless every committed truth file
                                               (including each clip's decoded-frame hash) is reproduced byte-for-byte
    python3 scripts/media/render.py --force    re-encode every clip even when the cache has it
    options: --set NAME (repeatable), --cache DIR (default .cache/media under the repository root)

Media goes to ``.cache/media/<set>-<hash16>/`` (git-ignored), keyed by the SHA-256 of the renderer core plus
that set's module, so editing a set re-renders only that set. Only ground truth and decoded-frame hashes are
committed. Needs ffmpeg with libx264, libx265 and ffv1 on PATH; standard-library Python 3.10+.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
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

    def check(index: int, canvas) -> None:
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
    return {"minimumMargin": worst[0], "frames": len(source_levels), "ffmpeg": encode.ffmpeg_version()}


def clip_truth(module, clip, cache_root: Path, force: bool, log) -> tuple[str, int]:
    set_file = Path(module.__file__)
    src_hash = truth.source_hash(ROOT, set_file)
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
    doc = truth.document(module.SET, clip, src_hash, cache_rel, facts["minimumMargin"], hasher.hexdigest(), hasher.frames)
    size = out.stat().st_size
    log(f"  {action:8} {module.SET}/{clip.id:32} {size:>10,} B  {time.monotonic() - started:5.1f} s  "
        f"frames {hasher.frames}  sig {hasher.hexdigest()[:12]}")
    return truth.dumps(doc), size


def prune(cache_root: Path, module, keep: str) -> None:
    for old in cache_root.glob(f"{module.SET}-*"):
        if old.is_dir() and old.name != keep:
            shutil.rmtree(old)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--set", action="append", dest="sets")
    parser.add_argument("--cache", type=Path, default=ROOT / ".cache" / "media")
    args = parser.parse_args(argv)
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found on PATH (brew install ffmpeg / apt-get install ffmpeg)", file=sys.stderr)
        return 2
    print(f"==> {encode.ffmpeg_version()}")
    modules = [m for m in discover() if not args.sets or m.SET in args.sets]
    failures, total, produced = [], 0, set()
    for module in modules:
        src_hash = truth.source_hash(ROOT, Path(module.__file__))
        print(f"==> set {module.SET} (renderer hash {src_hash[:16]})")
        for clip in module.clips():
            path = TRUTH_DIR / module.SET / f"{clip.id}.truth.json"
            produced.add(path)   # a clip that fails to render keeps its committed truth (never pruned as stale)
            try:
                text, size = clip_truth(module, clip, args.cache, args.force, print)
            except RenderError as e:
                failures.append(str(e))
                continue
            total += size
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
