"""What a fixture set hands the renderer core: one ``ClipSpec`` per clip.

A set module (``jovra_media/sets/<name>.py``) defines ``SET`` (its name, also the ground-truth folder)
and ``clips() -> list[ClipSpec]``. The core discovers set modules by convention, so a new set is a new
file and never an edit to a shared list.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction
from typing import Callable

from .canvas import Canvas

AUDIO_RATE = 48_000


@dataclass(frozen=True)
class Rate:
    num: int
    den: int = 1

    @property
    def fraction(self) -> Fraction:
        return Fraction(self.num, self.den)

    def ffmpeg(self) -> str:
        return f"{self.num}/{self.den}"


@dataclass(frozen=True)
class Event:
    """A ground-truth event at an exact audio sample (``time = sample / 48000`` s)."""
    type: str
    sample: int


@dataclass(frozen=True)
class AudioSpec:
    events: tuple[Event, ...] = ()
    channels: int = 1


@dataclass(frozen=True)
class ClipSpec:
    id: str                      # unique within its set, kebab-case
    file: str                    # file name inside the set's cache folder
    description: str
    codec: str                   # "h264" | "hevc" | "ffv1"
    width: int                   # coded width (before rotation)
    height: int                  # coded height
    rate: Rate
    frame_count: int
    paint: Callable[[int], Canvas]
    grid: tuple[int, int]        # signature grid (columns, rows)
    bit_depth: int = 8
    rotation: int = 0            # clockwise display rotation in degrees (tkhd matrix)
    hdr: str | None = None       # "hlg" for HEVC Main10 HLG BT.2020
    audio: AudioSpec | None = None
    supported: bool = True       # False: a codec the app must reject with a reason
    seed: int | None = None
    split: str | None = None     # "tuning" | "heldOut" for benchmark clips
    duplicate_of: str | None = None   # id of a clip in the same set whose bytes this file copies
    extra: dict = field(default_factory=dict)   # set-specific truth (court corners, ...)

    @property
    def container(self) -> str:
        return self.file.rsplit(".", 1)[1]

    @property
    def duration(self) -> Fraction:
        return Fraction(self.frame_count) / self.rate.fraction

    @property
    def audio_samples(self) -> int:
        samples = self.duration * AUDIO_RATE
        if samples.denominator != 1:
            raise ValueError(f"{self.id}: duration is not a whole number of 48 kHz samples")
        return int(samples)

    def frame_of_sample(self, sample: int) -> int:
        """The video frame on screen when the audio sample plays: floor(t * fps)."""
        return int(Fraction(sample, AUDIO_RATE) * self.rate.fraction)
