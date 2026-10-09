"""Frame-counter clips at 24, 30, 60, 120 and 240 fps (H.264, 640x360, 2 s, no audio).

Frame N shows counter N three ways, all in whole signature cells (16 x 9 cells of 40 px):
the 16-bit frame code in the top row, four 3x5 block digits for people, and a scan cell in the bottom
row at column N mod 16. Playback and seek tests decode frame N and read the code back.
"""

from __future__ import annotations

from ..canvas import BLACK, COURT, MID, SURROUND, WHITE, Canvas, Grid, block_text
from ..clip import ClipSpec, Rate

SET = "frameCounter"
WIDTH, HEIGHT, GRID = 640, 360, (16, 9)
SECONDS = 2


def _painter(base: Canvas):
    def paint(n: int) -> Canvas:
        canvas = base.copy()
        grid = Grid(canvas, *GRID)
        grid.frame_code(n)
        block_text(grid, f"{n:04d}", 0, 2, WHITE, SURROUND)
        grid.cell(n % 16, 8, MID)
        return canvas
    return paint


def clips() -> list[ClipSpec]:
    base = Canvas(WIDTH, HEIGHT, fill=COURT)
    Grid(base, *GRID)  # validates the grid
    for col in range(16):
        Grid(base, *GRID).cell(col, 8, BLACK)
    out = []
    for fps in (24, 30, 60, 120, 240):
        out.append(ClipSpec(
            id=f"fc-{fps:03d}",
            file=f"frame-counter-{fps:03d}fps.mp4",
            description=f"Frame counter at {fps} fps: frame N shows the 16-bit code N, the digits and a scan cell.",
            codec="h264", width=WIDTH, height=HEIGHT, rate=Rate(fps), frame_count=fps * SECONDS,
            paint=_painter(base), grid=GRID,
        ))
    return out
