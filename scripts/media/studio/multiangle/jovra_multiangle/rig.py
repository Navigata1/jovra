"""Placements, camera specs and camera clocks. Times are exact ``Fraction`` microseconds; nothing here rounds.

**Placements** are the six club-fence phone positions of the multicam research section 4.4 (ITF court, club run-back
5.48 m and side run 3.05 m, phone height 1.5 m), in the Studio court frame (``positionMm``: x across, 0 on the centre
line, positive east; y along, 0 at the net, negative towards the south/primary end; z up). The microphone sits at the
placement. The synthetic *picture* is drawn from the matching S08 angle camera (raised so the court reads), which is a
picture convention only: picture geometry is never calibration truth.

**Camera clock.** Each phone has one oscillator. Its host clock maps to the match clock (light time on the reference
camera's clock, origin at the scene start) as ``t_match = A + rate * t_host`` with ``rate = (1e9 + driftPpb) / 1e9``
(so ``driftPpm = (rate - 1) * 1e6``, multicam-sync 4.1/4.6). Segment ``k`` (one recorded file) starts at host time
``h_k``, so its piece is ``t_match = a_k + rate * t_src`` with ``a_k = A + rate * h_k`` and ``t_src`` the file's own
presentation time. A restart is a second segment after a host-clock gap; the capture journal, when present, records
each ``h_k`` (``fileZeroHost``), and an import has none.
"""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction

from jovra_media.clip import Rate

US = 1_000_000
RATE_DEN = 1_000_000_000
AUDIO_RATE = 48_000

# Every camera file: 640x360 coded (T11's signature grid of 8 x 4 cells), the S08 barcode strip in the bottom 20 px
# of the coded variant (below every cell's central half, so it never moves the decoded-frame signature).
WIDTH, HEIGHT, GRID = 640, 360, (8, 4)
BARCODE_RECT = (0, 340, 640, 20)


def half_up(value: Fraction) -> int:
    """floor(value + 1/2), exactly (Python's round() is half-even and is never used for times)."""
    return (Fraction(value) + Fraction(1, 2)).__floor__()


@dataclass(frozen=True)
class Placement:
    code: str          # research 4.4 column: BS, BN, CSW, CSE, CNW, CNE
    slot: str          # studio-common placementSlot
    name: str          # burned-in angle name (S08 AngleBadge)
    position_mm: dict  # microphone, Studio court frame
    picture: str       # the S08 angle camera slug the synthetic picture is drawn from


RUN_BACK_MM, SIDE_RUN_MM = 5_480, 3_050
HALF_LENGTH_MM, HALF_DOUBLES_MM = 11_885, 5_485
PHONE_Z_MM = 1_500
_Y = HALF_LENGTH_MM + RUN_BACK_MM            # 17 365
_X = HALF_DOUBLES_MM + SIDE_RUN_MM           # 8 535

PLACEMENTS = {p.code: p for p in (
    Placement("BS", "near-baseline", "Baseline", {"xMm": 0, "yMm": -_Y, "zMm": PHONE_Z_MM}, "baseline"),
    Placement("BN", "far-baseline", "Far baseline", {"xMm": 0, "yMm": _Y, "zMm": PHONE_Z_MM}, "far-baseline"),
    Placement("CSW", "near-left-corner", "Near left", {"xMm": -_X, "yMm": -_Y, "zMm": PHONE_Z_MM}, "near-left"),
    Placement("CSE", "near-right-corner", "Near right", {"xMm": _X, "yMm": -_Y, "zMm": PHONE_Z_MM}, "near-right"),
    Placement("CNW", "far-left-corner", "Far left", {"xMm": -_X, "yMm": _Y, "zMm": PHONE_Z_MM}, "far-left"),
    Placement("CNE", "far-right-corner", "Far right", {"xMm": _X, "yMm": _Y, "zMm": PHONE_Z_MM}, "far-right"),
)}

# The event rows of the research 4.4 tables (impact height 1.0 m) and the bias pairs of its second table.
TABLE_ROWS = (
    ("south-baseline-centre", "South baseline, centre", {"xMm": 0, "yMm": -HALF_LENGTH_MM, "zMm": 1_000}),
    ("south-baseline-wide", "South baseline, wide (singles sideline)", {"xMm": 4_115, "yMm": -HALF_LENGTH_MM, "zMm": 1_000}),
    ("south-service-t", "South service T", {"xMm": 0, "yMm": -6_400, "zMm": 1_000}),
    ("net-centre", "Net centre", {"xMm": 0, "yMm": 0, "zMm": 1_000}),
    ("north-service-t", "North service T", {"xMm": 0, "yMm": 6_400, "zMm": 1_000}),
    ("north-baseline-centre", "North baseline, centre", {"xMm": 0, "yMm": HALF_LENGTH_MM, "zMm": 1_000}),
)
BIAS_PAIRS = (("BS", "BN"), ("BS", "CSE"), ("BS", "CNE"))

# A knocked tripod: the view jolts by whole degrees (yaw, pitch) every SHAKE_HOLD frames while the stretch lasts,
# then settles one degree off its first pose, where it stays.
SHAKE_PATTERN = ((1, 0), (2, -1), (-1, 1), (1, 2), (-2, 0), (0, -1), (2, 1), (-1, -1))
SHAKE_HOLD = 2
SHAKE_SETTLED = (1, 0)


@dataclass(frozen=True)
class Segment:
    host_start_us: int      # the file's first frame on the phone's host clock
    frames: int


@dataclass(frozen=True)
class Shake:
    segment: int
    from_frame: int         # first shaken frame of the segment file
    to_frame: int           # first settled frame (exclusive end of the stretch)


@dataclass(frozen=True)
class CameraSpec:
    id: str
    code: str                       # placement code
    source_id: int                  # S08 barcode source id (64-127 are the multi-angle cameras)
    fps: Rate
    drift_ppb: int
    host_offset_us: int             # A: the match time of host time 0
    segments: tuple[Segment, ...]
    reference: bool = False
    journal: bool = True            # False: an import with no capture journal (no fileZeroHost per segment)
    audio: str = "present"          # "present" | "muted" (an AAC track with the noise floor only)
    latency_us: int = 0             # device audio-vs-video latency lambda (multicam-sync 4.1)
    view: str = "court"             # "court" | "covered" (lens covered: audio only)
    rotation: int = 0               # clockwise display rotation (tkhd matrix)
    hdr: str | None = None          # "hlg": 10-bit HEVC with BT.2020 HLG tags
    vfr_timescale: int = 0
    vfr_cycle: tuple[int, ...] = ()
    shake: Shake | None = None

    def __post_init__(self) -> None:
        if self.code not in PLACEMENTS:
            raise ValueError(f"{self.id}: unknown placement {self.code}")
        if not 64 <= self.source_id <= 127:
            raise ValueError(f"{self.id}: multi-angle source ids are 64-127")
        if self.reference and (self.drift_ppb or self.host_offset_us or len(self.segments) != 1
                               or self.segments[0].host_start_us):
            raise ValueError(f"{self.id}: the reference camera defines the match clock (rate 1, offset 0, one segment)")
        if self.audio not in ("present", "muted") or self.view not in ("court", "covered"):
            raise ValueError(f"{self.id}: bad audio or view")
        ends = [s.host_start_us + self.segment_duration_us(k) for k, s in enumerate(self.segments)]
        if any(self.segments[k + 1].host_start_us < ends[k] for k in range(len(self.segments) - 1)):
            raise ValueError(f"{self.id}: segments overlap on the host clock")
        if self.vfr_cycle and any(s.frames % len(self.vfr_cycle) for s in self.segments):
            raise ValueError(f"{self.id}: every VFR segment holds whole cycles")

    # ----- clock ------------------------------------------------------------------------------------

    @property
    def placement(self) -> Placement:
        return PLACEMENTS[self.code]

    @property
    def rate(self) -> Fraction:
        return Fraction(RATE_DEN + self.drift_ppb, RATE_DEN)

    @property
    def frame_rate(self) -> Fraction:
        return self.fps.fraction

    def source_time_us(self, n: int) -> Fraction:
        """Presentation time of file frame ``n`` (from the file's zero)."""
        if not self.vfr_cycle:
            return Fraction(n * US) / self.frame_rate
        period, total = len(self.vfr_cycle), sum(self.vfr_cycle)
        ticks = (n // period) * total + sum(self.vfr_cycle[: n % period])
        return Fraction(ticks * US, self.vfr_timescale)

    def segment_duration_us(self, k: int) -> Fraction:
        return Fraction(self.segments[k].frames * US) / self.frame_rate

    def segment_offset_us(self, k: int) -> Fraction:
        """a_k: the match time of segment ``k``'s file zero."""
        return self.host_offset_us + self.rate * self.segments[k].host_start_us

    def to_match_us(self, k: int, source_us: Fraction) -> Fraction:
        return self.segment_offset_us(k) + self.rate * source_us

    def to_source_us(self, k: int, match_us: Fraction) -> Fraction:
        return (Fraction(match_us) - self.segment_offset_us(k)) / self.rate

    def frame_match_us(self, k: int, n: int) -> Fraction:
        return self.to_match_us(k, self.source_time_us(n))

    def coverage_us(self, k: int) -> tuple[Fraction, Fraction]:
        """[first frame, end of the last frame) of segment ``k`` on the match clock."""
        return self.segment_offset_us(k), self.to_match_us(k, self.segment_duration_us(k))

    def segment_at(self, match_us: Fraction) -> int | None:
        for k in range(len(self.segments)):
            start, end = self.coverage_us(k)
            if start <= match_us < end:
                return k
        return None

    def frame_at(self, k: int, match_us: Fraction) -> int:
        """The file frame on screen at ``match_us`` (the last frame presented at or before it)."""
        source = self.to_source_us(k, match_us)
        n = int(source * self.frame_rate / US)
        while n + 1 < self.segments[k].frames and self.source_time_us(n + 1) <= source:
            n += 1
        while n > 0 and self.source_time_us(n) > source:
            n -= 1
        return n

    # ----- shake ------------------------------------------------------------------------------------

    def nudge(self, k: int, n: int) -> tuple[int, int]:
        """The (yaw, pitch) nudge in whole degrees of file frame ``n`` of segment ``k``."""
        s = self.shake
        if s is None or s.segment != k or n < s.from_frame:
            return (0, 0)
        if n >= s.to_frame:
            return SHAKE_SETTLED
        return SHAKE_PATTERN[((n - s.from_frame) // SHAKE_HOLD) % len(SHAKE_PATTERN)]
