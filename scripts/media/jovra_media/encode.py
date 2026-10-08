"""ffmpeg encode and decode. Options are limited to ones present in ffmpeg 6.1 (Ubuntu 24.04, CI) and
later (the build Mac), and every encode runs single-threaded with bitexact flags, so one machine renders
the same bytes on every run."""

from __future__ import annotations

import shutil
import struct
import subprocess
import sys
import tempfile
from array import array
from pathlib import Path

from . import audio, signature
from .clip import ClipSpec

FFMPEG = shutil.which("ffmpeg") or "ffmpeg"


def ffmpeg_version() -> str:
    out = subprocess.run([FFMPEG, "-hide_banner", "-version"], capture_output=True, text=True, check=True).stdout
    return out.splitlines()[0]


def _video_args(clip: ClipSpec) -> list[str]:
    common = ["-map_metadata", "-1", "-fflags", "+bitexact", "-flags:v", "+bitexact"]
    if clip.codec == "h264":
        return common + ["-c:v", "libx264", "-preset", "medium", "-crf", "16", "-threads", "1",
                         "-pix_fmt", "yuv420p", "-profile:v", "high", "-color_range", "tv",
                         "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709"]
    if clip.codec == "hevc":
        params = "log-level=error:pools=1:frame-threads=1:wpp=0"
        if clip.hdr == "hlg":
            params += ":colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc:range=limited"
            colour = ["-color_range", "tv", "-colorspace", "bt2020nc", "-color_primaries", "bt2020",
                      "-color_trc", "arib-std-b67"]
            pix, profile = "yuv420p10le", "main10"
        else:
            colour = ["-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709"]
            pix, profile = "yuv420p", "main"
        return common + ["-c:v", "libx265", "-preset", "medium", "-crf", "18", "-tag:v", "hvc1",
                         "-pix_fmt", pix, "-profile:v", profile, "-x265-params", params] + colour
    if clip.codec == "ffv1":
        return common + ["-c:v", "ffv1", "-threads", "1", "-pix_fmt", "yuv420p"]
    raise ValueError(f"unknown codec {clip.codec}")


def encode(clip: ClipSpec, out: Path, check_frame) -> None:
    """Draw every frame, pipe it to ffmpeg and write ``out``. ``check_frame(index, canvas)`` sees each
    source frame first (the renderer uses it for the signature margin check)."""
    out.parent.mkdir(parents=True, exist_ok=True)
    pix_in = "yuv420p10le" if clip.bit_depth == 10 else "yuv420p"
    with tempfile.TemporaryDirectory() as tmp:
        cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
               "-f", "rawvideo", "-pix_fmt", pix_in, "-s", f"{clip.width}x{clip.height}",
               "-framerate", clip.rate.ffmpeg(), "-i", "pipe:0"]
        maps = ["-map", "0:v:0"]
        if clip.audio is not None:
            wav = Path(tmp) / "audio.wav"
            audio.write_wav(wav, clip.audio, clip.audio_samples, clip.seed or 0)
            cmd += ["-i", str(wav)]
            maps += ["-map", "1:a:0", "-c:a", "aac", "-b:a", "96k", "-ar", "48000", "-flags:a", "+bitexact"]
        partial = out.with_name(out.name + ".partial" + out.suffix)
        cmd += maps + _video_args(clip) + ["-frames:v", str(clip.frame_count), "-f",
                                          "mov" if clip.container == "mov" else "mp4", str(partial)]
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        try:
            for i in range(clip.frame_count):
                canvas = clip.paint(i)
                check_frame(i, canvas)
                proc.stdin.write(canvas.raw())
        finally:
            proc.stdin.close()
            code = proc.wait()
        if code != 0:
            raise RuntimeError(f"ffmpeg failed for {clip.id} (exit {code})")
    if clip.rotation:
        set_rotation(partial, clip.rotation, clip.width, clip.height)
    partial.replace(out)


def set_rotation(path: Path, degrees: int, width: int, height: int) -> None:
    """Write the video track's display matrix (tkhd), the way iPhone portrait videos carry rotation.
    Done here rather than with ffmpeg options, which changed between ffmpeg 6 and 7."""
    data = bytearray(path.read_bytes())
    moov = data.find(b"moov")
    i = data.find(b"tkhd", moov)
    if moov < 0 or i < 0:
        raise RuntimeError(f"{path.name}: no tkhd box")
    version = data[i + 4]
    times = 8 + 8 + 4 + 4 + 8 if version == 1 else 4 + 4 + 4 + 4 + 4
    offset = i + 4 + 4 + times + 8 + 2 + 2 + 2 + 2
    one, w = 1 << 16, 1 << 30
    matrices = {
        90: [0, one, 0, -one, 0, 0, height << 16, 0, w],
        180: [-one, 0, 0, 0, -one, 0, width << 16, height << 16, w],
        270: [0, -one, 0, one, 0, 0, 0, width << 16, w],
    }
    data[offset: offset + 36] = struct.pack(">9i", *matrices[degrees])
    path.write_bytes(bytes(data))


def decoded_signatures(clip: ClipSpec, path: Path):
    """Yield the signature levels of every decoded frame of ``path`` (coded orientation)."""
    pix = "yuv420p10le" if clip.bit_depth == 10 else "yuv420p"
    bps = 2 if clip.bit_depth == 10 else 1
    luma_bytes = clip.width * clip.height * bps
    frame_bytes = luma_bytes * 3 // 2
    cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-noautorotate", "-i", str(path),
           "-map", "0:v:0", "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", pix, "pipe:1"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    columns, rows = clip.grid
    try:
        while True:
            buf = proc.stdout.read(frame_bytes)
            if not buf:
                break
            if len(buf) != frame_bytes:
                raise RuntimeError(f"{path.name}: truncated decoded frame")
            luma = buf[:luma_bytes]
            if bps == 2:
                plane = array("H")
                plane.frombytes(luma)
                if sys.byteorder != "little":
                    plane.byteswap()
                luma = plane
            yield signature.levels(signature.cell_means(luma, clip.width, clip.height, columns, rows), clip.bit_depth)
    finally:
        proc.stdout.close()
        if proc.wait() != 0:
            raise RuntimeError(f"ffmpeg could not decode {path.name}")
