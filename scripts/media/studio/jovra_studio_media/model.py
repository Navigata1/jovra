"""What a Studio fixture set hands the pipeline: one ``StudioClip`` per media file.

A Studio clip wraps a core ``ClipSpec`` (T10's renderer core encodes its picture and proves the decoded frames equal
the drawn ones) and adds what the core clip does not carry: the barcode drawn on every frame, the 1 kHz click track
muxed after the core encode, the burned-in labels and the set's own manifest facts. The core clip is always
picture-only (``audio=None``); the click audio is Studio's, so the core audio module stays untouched.

A set module (``jovra_studio_media/sets/<name>.py``) defines ``SET`` (its name and its folder under
spec/studio/fixtures/media), ``clips() -> list[StudioClip]`` and optionally ``INPUTS`` (repository files it reads,
hashed into its source hash). Sets are discovered by file name, so a new set never edits a shared list.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction

from jovra_media.canvas import Canvas
from jovra_media.clip import AUDIO_RATE, ClipSpec

from . import barcode as bc

ROLES = ("barcodeSource", "match", "broll", "angle")


@dataclass(frozen=True)
class StudioClip:
    core: ClipSpec                       # picture only; ``core.paint`` already draws the barcode and labels
    role: str                            # one of ROLES
    source_id: int | None = None         # barcode source id; None: no barcode on this clip
    segment: int = 0
    first_frame_id: int = 0              # the frame id file frame 0 carries (the session clock)
    barcode_rect: tuple[int, int, int, int] | None = None
    audio: bool = True                   # False: a file with no audio track at all
    clicks: tuple[int, ...] = ()         # click onsets, 48 kHz samples from the start of the file
    audio_seed: int = 0
    labels: tuple[dict, ...] = ()        # each {"kind", "text", "region", ...}: what the reader checks
    bundled: bool = False                # part of the app's demo subset
    extra: dict = field(default_factory=dict)   # set-specific manifest facts, written as is

    def __post_init__(self) -> None:
        if self.role not in ROLES:
            raise ValueError(f"{self.core.id}: unknown role {self.role}")
        if self.core.audio is not None:
            raise ValueError(f"{self.core.id}: the core clip must be picture-only; Studio muxes the click track")
        if (self.source_id is None) != (self.barcode_rect is None):
            raise ValueError(f"{self.core.id}: a barcode needs both a source id and a rectangle")
        if self.clicks and not self.audio:
            raise ValueError(f"{self.core.id}: clicks need an audio track")

    @property
    def id(self) -> str:
        return self.core.id

    @property
    def file(self) -> str:
        return self.core.file

    @property
    def frame_count(self) -> int:
        return self.core.frame_count

    @property
    def audio_samples(self) -> int:
        return self.core.audio_samples

    def payload(self, frame: int) -> bc.Payload:
        """The barcode file frame ``frame`` carries."""
        return bc.Payload(self.source_id, self.segment, self.first_frame_id + frame)

    def click_frames(self) -> list[int]:
        rate = self.core.rate
        return [int(Fraction(s, AUDIO_RATE) * rate.fraction) for s in self.clicks]


def with_barcode(paint, source_id: int, segment: int, first_frame_id: int, rect: tuple[int, int, int, int]):
    """Wrap a painter so every frame also carries its barcode (drawn last, over any moving content)."""
    def painted(n: int) -> Canvas:
        canvas = paint(n)
        bc.draw(canvas, bc.Payload(source_id, segment, first_frame_id + n), rect)
        return canvas
    return painted
