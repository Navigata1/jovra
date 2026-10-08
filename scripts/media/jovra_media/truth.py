"""Ground-truth documents (``spec/schemas/ground-truth.schema.json``) and the renderer source hash."""

from __future__ import annotations

import hashlib
import json
from math import gcd
from pathlib import Path

from . import signature
from .clip import AUDIO_RATE, ClipSpec

SCHEMA_VERSION = "1.0.0"
FOURCC = {"h264": "avc1", "hevc": "hvc1", "ffv1": "FFV1"}
MEDIA_DIR = Path("scripts/media")


def dumps(doc: dict) -> str:
    return json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def core_files(root: Path) -> list[Path]:
    pkg = root / MEDIA_DIR / "jovra_media"
    return sorted([root / MEDIA_DIR / "render.py", *pkg.glob("*.py"), pkg / "sets" / "__init__.py"])


def source_hash(root: Path, set_module: Path) -> str:
    """SHA-256 over the renderer core plus one set module: the cache key and ``renderer.sourceHash``.
    Each entry is ``<repo-relative path>\\0<sha256 of bytes>\\n``, sorted by path."""
    sha = hashlib.sha256()
    for path in sorted(set(core_files(root)) | {set_module}):
        rel = path.relative_to(root).as_posix()
        sha.update(f"{rel}\0{hashlib.sha256(path.read_bytes()).hexdigest()}\n".encode())
    return sha.hexdigest()


def rational(value: int, timescale: int) -> dict:
    g = gcd(value, timescale) or 1
    return {"value": value // g, "timescale": timescale // g}


def document(set_name: str, clip: ClipSpec, src_hash: str, media_path: str, margin: int,
             decoded_hash: str, decoded_frames: int) -> dict:
    rotated = clip.rotation in (90, 270)
    display_w, display_h = (clip.height, clip.width) if rotated else (clip.width, clip.height)
    orientation = "portrait" if display_h > display_w else "landscape" if display_w > display_h else "square"
    duration = clip.duration
    doc = {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "jovra.groundTruth",
        "id": f"{set_name}/{clip.id}",
        "set": set_name,
        "description": clip.description,
        "band": "synthetic",
        "renderer": {"script": (MEDIA_DIR / "render.py").as_posix(), "sourceHash": src_hash},
        "media": {"path": media_path, "container": clip.container},
        "seed": clip.seed,
        "split": clip.split,
        "duplicateOf": f"{set_name}/{clip.duplicate_of}" if clip.duplicate_of else None,
        "video": {
            "codec": clip.codec,
            "fourCC": FOURCC[clip.codec],
            "bitDepth": clip.bit_depth,
            "codedWidth": clip.width,
            "codedHeight": clip.height,
            "rotationDegrees": clip.rotation,
            "displayWidth": display_w,
            "displayHeight": display_h,
            "orientation": orientation,
            "frameRate": {"num": clip.rate.num, "den": clip.rate.den},
            "frameCount": clip.frame_count,
            "duration": rational(duration.numerator, duration.denominator),
            "hdr": {"transfer": "hlg", "primaries": "bt2020", "matrix": "bt2020nc"} if clip.hdr == "hlg" else None,
            "supported": clip.supported,
        },
        "audio": None if clip.audio is None else {
            "codec": "aac", "sampleRate": AUDIO_RATE, "channels": clip.audio.channels,
            "sampleCount": clip.audio_samples,
        },
        "frameCode": {"cells": 16, "encodes": "frameIndex"},
        "signature": {
            "method": signature.METHOD,
            "columns": clip.grid[0],
            "rows": clip.grid[1],
            "minimumMargin": margin,
            "frameCount": decoded_frames,
            "decodedFramesSha256": decoded_hash,
        },
    }
    if clip.audio is not None and clip.audio.events:
        doc["events"] = [
            {"type": e.type, "time": rational(e.sample, AUDIO_RATE), "sample": e.sample, "frame": clip.frame_of_sample(e.sample)}
            for e in clip.audio.events
        ]
    doc.update(clip.extra)
    return doc
