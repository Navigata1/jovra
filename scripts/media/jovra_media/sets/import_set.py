"""The import fixture set: HEVC and H.264, 24 to 240 fps (and 29.97), HDR (HLG), portrait by rotation
matrix (as an iPhone writes it) and by native portrait pixels, landscape, an unsupported codec (FFV1 in
QuickTime) and a byte-identical duplicate pair.

Every clip shows the frame code, an arrow that points to the top of the *displayed* picture and a
per-clip colour key, all in whole signature cells.
"""

from __future__ import annotations

from ..canvas import ACCENT_RED, ACCENT_TEAL, BLACK, COURT, MID, SURROUND, WHITE, Canvas, Colour, Grid
from ..clip import AudioSpec, ClipSpec, Rate
from ..scene import hit_schedule

SET = "import"

ARROW = [  # display-space cells relative to the arrow's top-left, pointing up
    "..#..",
    ".###.",
    "#####",
    "..#..",
    "..#..",
    "..#..",
]


class _Painter:
    def __init__(self, width: int, height: int, grid: tuple[int, int], rotation: int, bit_depth: int,
                 background: Colour, key: Colour):
        self.width, self.height, self.grid, self.rotation = width, height, grid, rotation
        self.base = Canvas(width, height, bit_depth=bit_depth, fill=background)
        g = Grid(self.base, *grid)
        cols, rows = grid
        dcols, drows = (rows, cols) if rotation in (90, 270) else (cols, rows)
        top = 2 if drows <= 9 else 4
        left = (dcols - len(ARROW[0])) // 2
        for dy, line in enumerate(ARROW):
            for dx, mark in enumerate(line):
                if mark == "#":
                    col, row = self._coded(left + dx, top + dy, dcols, drows)
                    g.cell(col, row, WHITE)
        col, row = self._coded(0, drows - 1, dcols, drows)   # colour key: bottom-left of the display
        g.cell(col, row, key)

    def _coded(self, dcol: int, drow: int, dcols: int, drows: int) -> tuple[int, int]:
        """Map a display-space cell to the coded cell under the clip's clockwise rotation."""
        if self.rotation == 0:
            return dcol, drow
        if self.rotation == 90:      # display (x', y') = (h - y, x)  =>  coded (x, y) = (y', h - x')
            return drow, dcols - 1 - dcol
        if self.rotation == 270:
            return drows - 1 - drow, dcol
        return dcols - 1 - dcol, drows - 1 - drow

    def __call__(self, n: int) -> Canvas:
        canvas = self.base.copy()
        Grid(canvas, *self.grid).frame_code(n)
        return canvas


def _clip(clip_id: str, file: str, description: str, codec: str, size: tuple[int, int], rate: Rate, frames: int,
          grid=(16, 9), rotation=0, bit_depth=8, hdr=None, audio_seed=None, supported=True,
          background=COURT, key=ACCENT_RED, duplicate_of=None) -> ClipSpec:
    width, height = size
    audio = None
    if audio_seed is not None:
        samples = frames * rate.den * 48_000 // rate.num
        audio = AudioSpec(events=hit_schedule(audio_seed, samples))
    return ClipSpec(
        id=clip_id, file=file, description=description, codec=codec, width=width, height=height, rate=rate,
        frame_count=frames, grid=grid, rotation=rotation, bit_depth=bit_depth, hdr=hdr, audio=audio,
        supported=supported, seed=audio_seed, duplicate_of=duplicate_of,
        paint=_Painter(width, height, grid, rotation, bit_depth, background, key),
    )


def clips() -> list[ClipSpec]:
    return [
        _clip("h264-1080p30-landscape", "h264-1080p30-landscape.mp4",
              "H.264 High, 1920x1080 landscape, 30 fps, AAC audio.",
              "h264", (1920, 1080), Rate(30), 90, audio_seed=101),
        _clip("hevc-720p60-landscape", "hevc-720p60-landscape.mov",
              "HEVC Main, 1280x720 landscape, 60 fps, AAC audio.",
              "hevc", (1280, 720), Rate(60), 120, audio_seed=102, background=SURROUND, key=ACCENT_TEAL),
        _clip("hevc-1080p30-portrait-rotated", "hevc-1080p30-portrait-rotated.mov",
              "HEVC Main, coded 1920x1080 with a 90-degree display matrix (iPhone portrait), 30 fps, AAC audio.",
              "hevc", (1920, 1080), Rate(30), 60, rotation=90, audio_seed=103),
        _clip("h264-720x1280-24-portrait", "h264-720x1280-24fps-portrait.mp4",
              "H.264 High, native 720x1280 portrait pixels, 24 fps, no audio track.",
              "h264", (720, 1280), Rate(24), 48, grid=(9, 16), background=SURROUND, key=MID),
        _clip("hevc-hlg-720p30", "hevc-hlg-720p30.mov",
              "HEVC Main 10, HLG transfer, BT.2020 primaries, 1280x720 landscape, 30 fps, AAC audio.",
              "hevc", (1280, 720), Rate(30), 60, bit_depth=10, hdr="hlg", audio_seed=105, key=ACCENT_TEAL),
        _clip("hevc-720p240-slowmo", "hevc-720p240-slowmo.mov",
              "HEVC Main, 1280x720 landscape, 240 fps slow motion, AAC audio.",
              "hevc", (1280, 720), Rate(240), 240, audio_seed=106, background=SURROUND, key=WHITE),
        _clip("h264-360p2997-landscape", "h264-360p29.97-landscape.mp4",
              "H.264 High, 640x360 landscape, 30000/1001 fps (29.97), no audio track.",
              "h264", (640, 360), Rate(30000, 1001), 60, key=BLACK),
        _clip("ffv1-unsupported", "ffv1-unsupported.mov",
              "FFV1 in QuickTime: a codec neither iOS nor Android decodes; import must reject it with a reason.",
              "ffv1", (640, 360), Rate(30), 30, supported=False),
        _clip("duplicate-a", "duplicate-a.mp4",
              "H.264, 640x360, 30 fps with audio: first file of a duplicate pair.",
              "h264", (640, 360), Rate(30), 60, audio_seed=109, key=WHITE),
        _clip("duplicate-b", "duplicate-b.mp4",
              "Byte-identical copy of duplicate-a under another name: import must detect it as a duplicate.",
              "h264", (640, 360), Rate(30), 60, audio_seed=109, key=WHITE, duplicate_of="duplicate-a"),
    ]
