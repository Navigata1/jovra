"""Barcode sources: the frame-truth media every Studio renderer and FilmVerifier test reads (film-engine section 7).

H.264 1280x720, 10 s, CFR. The picture is drawn in whole signature cells (40 x 9 cells of 32 x 80 px):

* bottom row: the 40-bit frame barcode (``barcode.py``; one bit per cell), source id, segment and frame id;
* rows 1-5: the frame id in 3 x 5 block digits, for people;
* row 6: a scan cell at column ``frame mod 40``;
* row 7: a white flash bar on every frame that carries a click onset, so a click is seen as well as heard.

Audio is AAC 48 kHz mono: 1 kHz clicks (``clicks.py``) starting 1 ms into seeded frames, over a quiet noise floor.

Variants: 24, 30 and 60 fps; a 30 fps capture restarted once (two files: segment 0 is session frames 0-149, segment
1 resumes at session frame 195 after a 1.5 s gap, and the barcode keeps counting on the session clock, so the gap is
visible in the frame ids; a click that fell in the gap is in no file); and a 30 fps file with no audio track.
"""

from __future__ import annotations

from jovra_media.canvas import BLACK, COURT, MID, WHITE, Canvas, Grid, block_text
from jovra_media.clip import ClipSpec, EncodeOptions, Rate
from jovra_media.prng import SplitMix64

from ..model import StudioClip, with_barcode

SET = "barcodeSources"
WIDTH, HEIGHT, GRID = 1280, 720, (40, 9)
SECONDS = 10
BARCODE_RECT = (0, 640, 1280, 80)
DIGITS = 6
CLICK_LEAD = 48     # each click starts 1 ms after its frame's presentation time, so its frame is unambiguous

RESTART = {"group": "bc-030-restart", "sessionFrames": 345, "segments": [(0, 150), (195, 150)]}
SOURCE_IDS = {"bc-024": 1, "bc-030": 2, "bc-060": 3, "bc-030-restart": 4, "bc-030-silent": 5}


def click_frames(seed: int, fps: int, first: int, last: int, count: int) -> list[int]:
    """``count`` click frames in [first, last], at least half a second apart, from a SplitMix64 schedule."""
    rng = SplitMix64(seed)
    gap = fps // 2
    out: list[int] = []
    while len(out) < count:
        f = rng.between(first, last)
        if all(abs(f - g) >= gap for g in out):
            out.append(f)
    return sorted(out)


def _painter(first_frame_id: int, flashes: frozenset[int]):
    base = Canvas(WIDTH, HEIGHT, fill=COURT)
    grid = Grid(base, *GRID)
    for col in range(GRID[0]):
        grid.cell(col, 6, BLACK)
        grid.cell(col, 7, BLACK)

    def paint(n: int) -> Canvas:
        canvas = base.copy()
        g = Grid(canvas, *GRID)
        block_text(g, f"{first_frame_id + n:0{DIGITS}d}", 8, 1, WHITE, COURT)
        g.cell(n % GRID[0], 6, MID)
        if n in flashes:
            for col in range(GRID[0]):
                g.cell(col, 7, WHITE)
        return canvas
    return paint


def _clip(clip_id: str, fps: int, frames: int, *, segment: int = 0, first_frame_id: int = 0,
          clicks_at: list[int] = (), audio: bool = True, description: str, extra: dict | None = None) -> StudioClip:
    source = SOURCE_IDS[RESTART["group"] if clip_id.startswith(RESTART["group"]) else clip_id]
    rate = Rate(fps)
    samples = [f * 48_000 // fps + CLICK_LEAD for f in clicks_at]
    paint = with_barcode(_painter(first_frame_id, frozenset(clicks_at)), source, segment, first_frame_id, BARCODE_RECT)
    core = ClipSpec(id=clip_id, file=f"{clip_id}.mp4", description=description, codec="h264", width=WIDTH,
                    height=HEIGHT, rate=rate, frame_count=frames, paint=paint, grid=GRID, seed=source,
                    frame_code=False, encode=EncodeOptions(crf=18, keyint=fps, audio_bitrate="64k"))
    return StudioClip(core=core, role="barcodeSource", source_id=source, segment=segment, first_frame_id=first_frame_id,
                      barcode_rect=BARCODE_RECT, audio=audio, clicks=tuple(samples), audio_seed=source,
                      extra=extra or {})


def clips() -> list[StudioClip]:
    out = []
    for fps in (24, 30, 60):
        frames = fps * SECONDS
        at = click_frames(fps, fps, fps // 4, frames - fps // 2, 8)
        out.append(_clip(f"bc-{fps:03d}", fps, frames, clicks_at=at,
                         description=f"Barcode source at {fps} fps, 10 s: every frame carries its frame id; "
                                     f"8 clicks of 1 kHz at known frames."))
    # One restarted 30 fps capture: clicks are scheduled on the session clock; each file keeps those inside it.
    session_clicks = click_frames(4, 30, 10, RESTART["sessionFrames"] - 15, 8) + [170]
    session_clicks = sorted(set(session_clicks))
    for segment, (start, count) in enumerate(RESTART["segments"]):
        inside = [f - start for f in session_clicks if start <= f < start + count - 1]
        out.append(_clip(f"{RESTART['group']}-seg{segment}", 30, count, segment=segment, first_frame_id=start,
                         clicks_at=inside,
                         description=f"Barcode source, 30 fps capture restarted once: segment {segment} holds session "
                                     f"frames {start}-{start + count - 1}.",
                         extra={"restart": {"group": RESTART["group"], "segment": segment, "sessionStartFrame": start,
                                            "sessionFrameCount": RESTART["sessionFrames"],
                                            "gaps": [{"fromFrame": 150, "toFrame": 195}],
                                            "clicksInGapFrames": [f for f in session_clicks if 150 <= f < 195]}}))
    out.append(_clip("bc-030-silent", 30, 30 * SECONDS, audio=False,
                     description="Barcode source at 30 fps, 10 s, with no audio track at all."))
    return out
