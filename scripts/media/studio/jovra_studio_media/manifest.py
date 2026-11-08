"""The committed ground truth of a Studio fixture (``jovra.studio-media-truth/1``).

A manifest has two parts:

* the **plan**: everything that follows from the generator's source alone (the generator version and source hash,
  the video and audio facts, the barcode layout and frame map, the click frames, the labels and the set's facts).
  ``plan(clip, ...)`` computes it without drawing a pixel, so the Studio contract validator recomputes it on every
  run (spec/reference/studio/cases/media_fixtures_cases.py) and fails on any drift;
* the **hashes**: what only a render proves, and that every machine reproduces (they do not depend on the
  encoder's bytes): the SHA-256 of every drawn frame, the decoded-frame signature (``jovra.cellLuma.v1``, T10) and
  the SHA-256 of the click-track PCM. ``hashes.renderedWithSourceHash`` names the source they were rendered from,
  so stale hashes are caught.

The media file's own SHA-256 is not committed: x264 and the AAC encoder differ between ffmpeg builds (T10), so it is
reproducible on one machine, which is what the generator's two-run check proves, and it is printed in the run log.
"""

from __future__ import annotations

import hashlib
import json
from math import gcd
from pathlib import Path

from jovra_media import signature
from jovra_media.clip import AUDIO_RATE

from . import barcode as bc
from . import clicks as ck
from .model import StudioClip

SCHEMA_VERSION = "jovra.studio-media-truth/1"
GENERATOR_VERSION = "1.0.0"
SCRIPT = "scripts/media/studio/render_studio.py"
MEDIA_ROOT = Path("spec/studio/fixtures/media")
CACHE = Path(".cache/media/studio")


def dumps(doc: dict) -> str:
    """The exact bytes spec/reference/studio/generate_studio_fixtures.py writes for a fixture."""
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def rel_path(set_name: str, clip_id: str) -> str:
    """The manifest's path relative to spec/studio/fixtures."""
    return f"media/{set_name}/{clip_id}.json"


def rational(value: int, timescale: int) -> dict:
    g = gcd(value, timescale) or 1
    return {"value": value // g, "timescale": timescale // g}


def frame_map_sha256(clip: StudioClip) -> str:
    """SHA-256 of every frame's expected barcode, as 5 bytes (source, segment, frame id 24-bit big-endian) in
    file order: what a full decode must reproduce."""
    sha = hashlib.sha256()
    for n in range(clip.frame_count):
        p = clip.payload(n)
        sha.update(bytes([p.source, p.segment]) + p.frame.to_bytes(3, "big"))
    return sha.hexdigest()


def plan(set_name: str, clip: StudioClip, source_hash: str) -> dict:
    core = clip.core
    duration = core.duration
    doc = {
        "schemaVersion": SCHEMA_VERSION,
        "id": f"{set_name}/{clip.id}",
        "set": set_name,
        "role": clip.role,
        "description": core.description,
        "sample": True,
        "band": "synthetic",
        "generator": {"script": SCRIPT, "version": GENERATOR_VERSION, "sourceHash": source_hash},
        "media": {"path": (CACHE / f"{set_name}-{source_hash[:16]}" / clip.file).as_posix(), "fileName": clip.file,
                  "container": core.container, "bundled": clip.bundled},
        "video": {"codec": core.codec, "width": core.width, "height": core.height,
                  "frameRate": {"num": core.rate.num, "den": core.rate.den}, "frameCount": core.frame_count,
                  "duration": rational(duration.numerator, duration.denominator)},
        "audio": None if not clip.audio else {"codec": "aac", "sampleRate": AUDIO_RATE, "channels": 1,
                                              "sampleCount": clip.audio_samples},
        "barcode": None,
        "clicks": None,
        "labels": list(clip.labels),
    }
    if clip.source_id is not None:
        doc["barcode"] = dict(bc.layout(clip.barcode_rect), sourceId=clip.source_id, segment=clip.segment,
                              frameMap=[{"frame": 0, "frameId": clip.first_frame_id, "count": clip.frame_count}],
                              frameMapSha256=frame_map_sha256(clip))
    if clip.audio:
        doc["clicks"] = {"hz": ck.HZ, "durationSamples": ck.SAMPLES, "peak": ck.PEAK, "toleranceFrames": 1,
                         "events": [{"sample": s, "time": rational(s, AUDIO_RATE), "frame": f}
                                    for s, f in zip(clip.clicks, clip.click_frames())]}
    doc.update(clip.extra)
    return doc


def hashes(source_hash: str, source_frames: str, decoded_signature: str, pcm: str | None) -> dict:
    return {"renderedWithSourceHash": source_hash, "sourceFramesSha256": source_frames,
            "decodedSignature": {"method": signature.METHOD, "sha256": decoded_signature},
            "pcmSha256": pcm}


def document(plan_doc: dict, hash_doc: dict | None) -> dict:
    doc = dict(plan_doc)
    if hash_doc is not None:
        doc["hashes"] = hash_doc
    return doc
