"""The named rigs (multicam-sync research 8.1 and ticket S58). Every camera id is unique; a camera used by several
profiles (the full-length reference ``bs-ref``) is one spec and is rendered once.

Numbers are chosen, not measured: start offsets put each camera's frames at a different phase to the reference,
drifts span the realistic 1-50 ppm with both signs (phones measure about 8 ppm) plus the 300 ppm stress, and the
device audio latencies are small (0-2.5 ms) so tests that ignore them see the bias they would have on a phone.
"""

from __future__ import annotations

from dataclasses import dataclass

from jovra_media.clip import Rate

from .rig import CameraSpec, Segment, Shake

S = 1_000_000
R30, R60, R240 = Rate(30), Rate(60), Rate(240)
VFR_TIMESCALE = 30_000
# A phone's variable frame rate (T10's import fixture): one 25 ms and one 41.7 ms frame in every ten, 30 fps median.
VFR_CYCLE = (1000, 1000, 1000, 1000, 749, 1251, 1000, 1000, 1000, 1000)


def _cam(cid: str, code: str, source: int, drift_ppb: int, start_us: int, frames: int, **kw) -> CameraSpec:
    return CameraSpec(cid, code, source, kw.pop("fps", R30), drift_ppb, start_us, (Segment(0, frames),), **kw)


CAMERAS = {c.id: c for c in (
    # The reference: BS records the whole two-minute scene and defines the match clock.
    CameraSpec("bs-ref", "BS", 64, R30, 0, 0, (Segment(0, 3600),), reference=True),
    # Default drift, 1-50 ppm, the other five placements.
    _cam("bn-drift", "BN", 65, 20_000, 137_500, 3560, latency_us=1_200),
    _cam("csw-drift", "CSW", 66, -8_000, 402_300, 3550),
    _cam("cse-drift", "CSE", 67, 1_000, 61_900, 3570, latency_us=800),
    _cam("cnw-drift", "CNW", 68, 50_000, 733_100, 3540, latency_us=2_500),
    _cam("cne-drift", "CNE", 69, -35_000, 259_700, 3560, latency_us=1_500),
    # Stress: 300 ppm (18 ms a minute, the research's UI sample).
    _cam("cse-stress", "CSE", 70, 300_000, 318_400, 3570),
    # A restart after a 41 s gap on the phone's host clock: with the capture journal, and as an import without it.
    CameraSpec("cne-restart-journal", "CNE", 71, R30, 12_000, 511_000,
               (Segment(0, 900), Segment(30 * S + 41 * S, 1440)), journal=True, latency_us=700),
    CameraSpec("cnw-restart-import", "CNW", 72, R30, -20_000, 1_207_000,
               (Segment(0, 750), Segment(25 * S + 41 * S, 1560)), journal=False),
    # A camera that starts recording 47.3 s into the scene.
    _cam("bn-late", "BN", 73, 5_000, 47_300_000, 2150),
    # A knocked tripod: frames 1105-1209 (match 57.0-60.5 s, the third and fourth points' serves) jolt, then the
    # view settles one degree off.
    _cam("csw-shake", "CSW", 74, 3_000, 20_150_000, 1800, shake=Shake(0, 1105, 1210)),
    # A muted microphone: the file has an audio track holding only the noise floor.
    _cam("cse-muted", "CSE", 75, 7_000, 402_000, 1800, audio="muted"),
    # Mixed frame rates against the 30 fps reference.
    _cam("cse-60fps", "CSE", 76, 10_000, 10_013_000, 1800, fps=R60),
    _cam("cnw-240fps", "CNW", 77, -15_000, 12_004_100, 4320, fps=R240),
    # Normalization variants: variable frame rate, rotated (portrait), HLG-tagged 10-bit HEVC.
    _cam("bn-vfr", "BN", 78, 4_000, 5_120_000, 1200, vfr_timescale=VFR_TIMESCALE, vfr_cycle=VFR_CYCLE),
    _cam("csw-rot90", "CSW", 79, -6_000, 5_480_000, 1200, rotation=90),
    _cam("cne-hdr", "CNE", 80, 9_000, 14_900_000, 900, hdr="hlg"),
    # No shared coverage: the reference stops at 50 s, the other angle starts at 70.25 s.
    CameraSpec("bs-first-half", "BS", 81, R30, 0, 0, (Segment(0, 1500),), reference=True),
    _cam("bn-second-half", "BN", 82, 25_000, 70_250_000, 1450),
    # Opposite baselines, audio only: both lenses covered.
    CameraSpec("bs-covered", "BS", 83, R30, 0, 0, (Segment(0, 3600),), reference=True, view="covered"),
    _cam("bn-covered", "BN", 84, 15_000, 289_000, 3570, view="covered", latency_us=1_000),
)}


@dataclass(frozen=True)
class Profile:
    id: str
    description: str
    cameras: tuple[str, ...]          # the reference first
    stresses: tuple[str, ...]


PROFILES = (
    Profile("drift-default", "All six placements; every non-reference clock drifts by 1-50 ppm (both signs).",
            ("bs-ref", "bn-drift", "csw-drift", "cse-drift", "cnw-drift", "cne-drift"), ("drift", "six-placements")),
    Profile("drift-stress-300ppm", "One corner camera whose clock drifts by 300 ppm, the stress fixture.",
            ("bs-ref", "cse-stress"), ("drift-stress",)),
    Profile("restart-41s-journal", "A corner camera restarts after a 41 s gap; the capture journal records both "
            "segments' file zero on the host clock, so one host-clock map covers both.",
            ("bs-ref", "cne-restart-journal"), ("restart", "journal")),
    Profile("restart-41s-no-journal", "A corner camera restarts after a 41 s gap and is imported without a capture "
            "journal: each segment needs its own offset with the shared rate.",
            ("bs-ref", "cnw-restart-import"), ("restart", "no-journal")),
    Profile("late-start", "The far-baseline camera starts recording 47.3 s into the scene.",
            ("bs-ref", "bn-late"), ("late-start",)),
    Profile("shake", "A knocked tripod: a 3.5 s shaken stretch across three racket contacts, then the view settles "
            "one degree off. Anchors inside the stretch are marked so anchor tests can assert down-weighting.",
            ("bs-ref", "csw-shake"), ("shake",)),
    Profile("muted", "A corner camera whose microphone is muted: visual anchors only.",
            ("bs-ref", "cse-muted"), ("muted",)),
    Profile("mixed-fps", "60 fps and 240 fps angles against the 30 fps reference: compare times, never frame indices.",
            ("bs-ref", "cse-60fps", "cnw-240fps"), ("mixed-fps",)),
    Profile("vfr-rotated-hdr", "Normalization inputs: a variable-frame-rate angle, a portrait (rotated 90) angle and an "
            "HLG-tagged 10-bit HEVC angle.",
            ("bs-ref", "bn-vfr", "csw-rot90", "cne-hdr"), ("vfr", "rotated", "hdr")),
    Profile("no-shared-coverage", "Two angles with no shared coverage: they cannot be synced to each other and are "
            "never offered for cross-cutting.",
            ("bs-first-half", "bn-second-half"), ("no-shared-coverage",)),
    Profile("opposite-baseline-audio-only", "Both baselines with covered lenses: audio anchors only, and every hit's "
            "sound reaches the two phones up to 69 ms apart depending on who hit it.",
            ("bs-covered", "bn-covered"), ("audio-only", "opposite-baselines")),
)


def profile(pid: str) -> Profile:
    return next(p for p in PROFILES if p.id == pid)


def cameras_in_use() -> list[str]:
    """Every camera any profile uses, in first-use order (what the generator renders)."""
    out: list[str] = []
    for p in PROFILES:
        out += [c for c in p.cameras if c not in out]
    return out
