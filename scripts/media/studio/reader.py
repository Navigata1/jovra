#!/usr/bin/env python3
"""Read Studio fixture media back: frame ids from barcodes, and the burned-in Sample and angle labels.

    python3 scripts/media/studio/reader.py FILE --manifest spec/studio/fixtures/media/barcodeSources/bc-030.json
        decode every frame, read its barcode and compare it with the manifest's frame map (exit 1 on any mismatch)
    python3 scripts/media/studio/reader.py FILE --manifest M --picture X,Y,W,H
        the same for an output frame that shows the source scaled or letterboxed into that picture rectangle
    python3 scripts/media/studio/reader.py FILE --manifest M --labels 12
        check every label of the manifest on 12 frames spread across the file (exit 1 when one is missing)
    python3 scripts/media/studio/reader.py FILE --rect X,Y,W,H --print
        print "frame source segment frameId" for every frame (no manifest needed)

Renderer and FilmVerifier tests use the functions directly: ``expected_payloads``, ``read_frames``,
``compare_to_map``, ``frame_luma`` and ``check_labels``.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from jovra_media import encode  # noqa: E402
from jovra_studio_media import barcode as bc  # noqa: E402
from jovra_studio_media.badge import banner_pixels  # noqa: E402
from jovra_studio_media.pipeline import decoded_frames  # noqa: E402


@dataclass
class MapReport:
    frames: int = 0
    matched: int = 0
    mismatches: list = field(default_factory=list)   # (frame, expected, got or error text)

    @property
    def ok(self) -> bool:
        return self.frames > 0 and self.matched == self.frames and not self.mismatches


def rect_of(manifest: dict) -> tuple[int, int, int, int]:
    r = manifest["barcode"]["rect"]
    return r["x"], r["y"], r["width"], r["height"]


def expected_payloads(manifest: dict) -> list[bc.Payload]:
    """Every frame's expected barcode, from the manifest's frame map runs."""
    b = manifest["barcode"]
    out: list[bc.Payload] = []
    for run in b["frameMap"]:
        if run["frame"] != len(out):
            raise ValueError("frame map runs must be contiguous from frame 0")
        out.extend(bc.Payload(b["sourceId"], b["segment"], run["frameId"] + k) for k in range(run["count"]))
    if len(out) != manifest["video"]["frameCount"]:
        raise ValueError("the frame map does not cover every frame")
    return out


def read_frames(path: Path, width: int, height: int, rect: tuple[int, int, int, int]):
    """Yield (frame index, Payload or BarcodeError) for every decoded frame of ``path``."""
    for n, luma in enumerate(decoded_frames(path, width, height)):
        try:
            yield n, bc.read(luma, width, height, rect)
        except bc.BarcodeError as e:
            yield n, e


def probe_size(path: Path) -> tuple[int, int]:
    out = subprocess.run([encode.FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True).stdout
    w, h = out.strip().split(",")[:2]
    return int(w), int(h)


def compare_to_map(path: Path, manifest: dict, picture: tuple[int, int, int, int] | None = None,
                   expected: list[bc.Payload] | None = None) -> MapReport:
    """Decode ``path`` fully and compare every frame's barcode with ``expected`` (default: the manifest's frame map).
    ``picture`` is where the source picture sits in the file's frames when it is an output that scaled it."""
    width, height = probe_size(path)
    rect = rect_of(manifest)
    if picture is not None:
        rect = bc.map_rect(rect, (manifest["video"]["width"], manifest["video"]["height"]), picture)
    want = expected if expected is not None else expected_payloads(manifest)
    report = MapReport()
    for n, got in read_frames(path, width, height, rect):
        report.frames += 1
        target = want[n] if n < len(want) else None
        if isinstance(got, bc.BarcodeError):
            report.mismatches.append((n, target, str(got)))
        elif got != target:
            report.mismatches.append((n, target, got))
        else:
            report.matched += 1
    if report.frames != len(want):
        report.mismatches.append((report.frames, None, f"decoded {report.frames} frames, the plan has {len(want)}"))
    return report


def frame_luma(path: Path, frame: int, rate: Fraction, width: int, height: int) -> bytes:
    """The luma plane of one frame, by accurate seek to its presentation time."""
    t = Fraction(frame) / rate
    out = subprocess.run([encode.FFMPEG, "-hide_banner", "-loglevel", "error", "-ss", f"{float(t):.6f}", "-i", str(path),
                          "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1"],
                         capture_output=True, check=True).stdout
    if len(out) != width * height:
        raise ValueError(f"{path.name} frame {frame}: decoded {len(out)} bytes")
    return out


def label_failures(luma: bytes, width: int, height: int, entry: dict) -> list[str]:
    """Why ``entry``'s label is not visible in this frame (empty when it is): every glyph pixel must decode as ink
    and the banner around the glyphs as background, allowing 2% of either for codec smear."""
    ink, background = banner_pixels(entry, width, height)
    tolerance = 48
    dark_ink = sum(1 for x, y in ink if luma[y * width + x] < entry["ink"]["y"] - tolerance)
    bright = sum(1 for x, y in background if luma[y * width + x] > entry["background"]["y"] + tolerance)
    out = []
    if dark_ink > len(ink) // 50:
        out.append(f"{entry['kind']} label {entry['text']!r}: {dark_ink} of {len(ink)} glyph pixels are not ink")
    if bright > len(background) // 50:
        out.append(f"{entry['kind']} label {entry['text']!r}: {bright} of {len(background)} banner pixels are covered")
    return out


def sample_frames(frame_count: int, count: int) -> list[int]:
    """First, last and ``count - 2`` frames evenly between."""
    count = max(2, count)
    return sorted({0, frame_count - 1, *(frame_count * k // (count - 1) for k in range(1, count - 1))})


def check_labels(path: Path, manifest: dict, frames: list[int]) -> list[str]:
    v = manifest["video"]
    rate = Fraction(v["frameRate"]["num"], v["frameRate"]["den"])
    out = []
    if not manifest["labels"]:
        return ["the manifest lists no label"]
    for frame in frames:
        luma = frame_luma(path, frame, rate, v["width"], v["height"])
        for entry in manifest["labels"]:
            out += [f"frame {frame}: {f}" for f in label_failures(luma, v["width"], v["height"], entry)]
    return out


def _rect(text: str) -> tuple[int, int, int, int]:
    parts = [int(p) for p in text.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("expected X,Y,W,H")
    return tuple(parts)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--rect", type=_rect, help="barcode rectangle in the file's pixels (without a manifest)")
    parser.add_argument("--picture", type=_rect, help="where the source picture sits in the file's frames")
    parser.add_argument("--labels", type=int, metavar="N", help="check the labels on N frames spread across the file")
    parser.add_argument("--print", action="store_true", dest="print_ids")
    args = parser.parse_args(argv)
    manifest = json.loads(args.manifest.read_text(encoding="utf-8")) if args.manifest else None
    if args.print_ids or manifest is None:
        if args.rect is None and manifest is None:
            parser.error("--print needs --rect or --manifest")
        width, height = probe_size(args.file)
        rect = args.rect or rect_of(manifest)
        bad = 0
        for n, got in read_frames(args.file, width, height, rect):
            if isinstance(got, bc.BarcodeError):
                bad += 1
                print(f"{n} unreadable: {got}")
            else:
                print(f"{n} {got.source} {got.segment} {got.frame}")
        return 1 if bad else 0
    status = 0
    if args.labels:
        failures = check_labels(args.file, manifest, sample_frames(manifest["video"]["frameCount"], args.labels))
        for f in failures:
            print(f"LABEL {f}")
        print(f"labels: {'FAIL' if failures else 'PASS'} ({len(manifest['labels'])} labels on {args.labels} frames)")
        status |= 1 if failures else 0
    if manifest.get("barcode"):
        report = compare_to_map(args.file, manifest, args.picture)
        for n, want, got in report.mismatches[:20]:
            print(f"MISMATCH frame {n}: expected {want}, read {got}")
        print(f"barcodes: {'PASS' if report.ok else 'FAIL'} ({report.matched} of {report.frames} frames match the frame map)")
        status |= 0 if report.ok else 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
