"""Render one Studio clip and prove it, reusing T10's renderer core (never a fork of it):

1. ``render.render_clip`` (scripts/media/render.py) draws every frame, encodes the picture with the core encoder
   settings, refuses any frame whose signature margin is too small and refuses the encode unless every decoded frame's
   signature equals the drawn one. It returns the SHA-256 of the drawn frames.
2. The click track (``clicks.pcm``) is written as 48 kHz PCM and muxed as AAC next to the untouched video stream.
3. ``verify`` decodes the finished file completely: every frame's barcode must read back as the clip's frame map,
   every click must be detected within +/-1 frame of its ground-truth frame with none extra, and the decoded-frame
   signature hash is computed for the manifest.

Nothing here writes outside the given cache folder.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import tempfile
from array import array
from dataclasses import dataclass
from pathlib import Path

import render as core_render  # scripts/media/render.py, the T10 renderer core
from jovra_media import encode, signature

from . import barcode as bc
from . import clicks as ck
from .model import StudioClip


class StudioRenderError(Exception):
    pass


@dataclass(frozen=True)
class Verified:
    frames: int
    barcode_frames: int          # frames whose barcode read back as the plan (all of them, or render fails)
    clicks: int
    click_frame_errors: list[int]
    click_sample_errors: list[int]
    decoded_signature: str
    file_sha256: str
    size: int


def file_sha256(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            sha.update(chunk)
    return sha.hexdigest()


def render(clip: StudioClip, out: Path) -> dict:
    """Encode ``clip`` to ``out``; returns the render facts (drawn-frame hash, PCM hash, ffmpeg version)."""
    out.parent.mkdir(parents=True, exist_ok=True)
    picture = out.with_name(out.stem + ".picture" + out.suffix)
    try:
        facts = core_render.render_clip(clip.core, picture)
    except core_render.RenderError as e:
        raise StudioRenderError(str(e)) from e
    pcm_hash = None
    if clip.audio:
        with tempfile.TemporaryDirectory() as tmp:
            wav = Path(tmp) / "clicks.wav"
            pcm_hash = ck.write_wav(wav, list(clip.clicks), clip.audio_samples, clip.audio_seed)
            partial = out.with_name(out.name + ".partial" + out.suffix)
            cmd = [encode.FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(picture), "-i", str(wav),
                   "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac", "-b:a", "96k", "-ar", "48000",
                   "-ac", "1", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", "-f", "mp4",
                   str(partial)]
            if subprocess.run(cmd).returncode != 0:
                raise StudioRenderError(f"{clip.id}: ffmpeg could not mux the click track")
            partial.replace(out)
        picture.unlink()
    else:
        picture.replace(out)
    return {"sourceFramesSha256": facts["sourceFramesSha256"], "minimumMargin": facts["minimumMargin"],
            "pcmSha256": pcm_hash, "ffmpeg": facts["ffmpeg"]}


def decoded_frames(path: Path, width: int, height: int):
    """Yield the 8-bit luma plane of every decoded frame, in presentation order."""
    luma_bytes = width * height
    frame_bytes = luma_bytes * 3 // 2
    cmd = [encode.FFMPEG, "-hide_banner", "-loglevel", "error", "-noautorotate", "-i", str(path), "-map", "0:v:0",
           "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "yuv420p", "pipe:1"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    try:
        while True:
            buf = proc.stdout.read(frame_bytes)
            if not buf:
                break
            if len(buf) != frame_bytes:
                raise StudioRenderError(f"{path.name}: truncated decoded frame")
            yield buf[:luma_bytes]
    finally:
        proc.stdout.close()
        if proc.wait() != 0:
            raise StudioRenderError(f"ffmpeg could not decode {path.name}")


def audio_streams(path: Path) -> list[str]:
    """Codec name of every audio stream in the file."""
    out = subprocess.run([encode.FFPROBE, "-v", "error", "-select_streams", "a", "-show_entries", "stream=codec_name",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True).stdout
    return [line.strip() for line in out.splitlines() if line.strip()]


def decoded_audio(path: Path) -> tuple[list[int], int]:
    """Decode the first audio track to mono 16-bit 48 kHz, streaming; returns (click onsets, sample count)."""
    cmd = [encode.FFMPEG, "-hide_banner", "-loglevel", "error", "-i", str(path), "-map", "0:a:0",
           "-f", "s16le", "-ac", "1", "-ar", "48000", "pipe:1"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    detector, count = ck.Detector(), 0
    try:
        while True:
            raw = proc.stdout.read(2 * ck.RATE)
            if not raw:
                break
            chunk = array("h")
            chunk.frombytes(raw[: len(raw) // 2 * 2])
            if sys.byteorder != "little":
                chunk.byteswap()
            detector.feed(chunk)
            count += len(chunk)
    finally:
        proc.stdout.close()
        if proc.wait() != 0:
            raise StudioRenderError(f"ffmpeg could not decode the audio of {path.name}")
    return detector.finish(), count


def match_clicks(found: list[int], truth: list[int], rate_num: int, rate_den: int) -> list[int]:
    """Frame error of each ground-truth click against the detection (raises when a click is missing or extra)."""
    if len(found) != len(truth):
        raise StudioRenderError(f"detected {len(found)} clicks, expected {len(truth)}")
    errors = []
    for got, want in zip(found, truth):
        error = ck.frame_of(got, rate_num, rate_den) - ck.frame_of(want, rate_num, rate_den)
        if abs(error) > 1:
            raise StudioRenderError(f"click at sample {want} detected at {got} ({error} frames off)")
        errors.append(error)
    return errors


def verify(clip: StudioClip, path: Path) -> Verified:
    core = clip.core
    columns, rows = core.grid
    hasher = signature.ClipHasher()
    frames = barcode_frames = 0
    for n, luma in enumerate(decoded_frames(path, core.width, core.height)):
        hasher.add(signature.levels(signature.cell_means(luma, core.width, core.height, columns, rows), 8))
        if clip.source_id is not None:
            try:
                got = bc.read(luma, core.width, core.height, clip.barcode_rect)
            except bc.BarcodeError as e:
                raise StudioRenderError(f"{clip.id} frame {n}: {e}") from e
            if got != clip.payload(n):
                raise StudioRenderError(f"{clip.id} frame {n}: barcode reads {got}, expected {clip.payload(n)}")
            barcode_frames += 1
        frames += 1
    if frames != core.frame_count:
        raise StudioRenderError(f"{clip.id}: decoded {frames} frames, expected {core.frame_count}")
    errors: list[int] = []
    sample_errors: list[int] = []
    streams = audio_streams(path)
    if streams != (["aac"] if clip.audio else []):
        raise StudioRenderError(f"{clip.id}: audio streams {streams}, expected {'one AAC' if clip.audio else 'none'}")
    if clip.audio:
        found, count = decoded_audio(path)
        if abs(count - clip.audio_samples) > 1024:
            raise StudioRenderError(f"{clip.id}: decoded {count} audio samples, expected {clip.audio_samples}")
        try:
            errors = match_clicks(found, list(clip.clicks), core.rate.num, core.rate.den)
            sample_errors = [got - want for got, want in zip(found, clip.clicks)]
        except StudioRenderError as e:
            raise StudioRenderError(f"{clip.id}: {e}") from e
    return Verified(frames, barcode_frames, len(clip.clicks), errors, sample_errors, hasher.hexdigest(), file_sha256(path),
                    path.stat().st_size)


def copy_if_changed(source: Path, target: Path) -> None:
    if not target.exists() or file_sha256(target) != file_sha256(source):
        shutil.copyfile(source, target)
