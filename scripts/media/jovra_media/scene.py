"""Shared drawing for fixture scenes: a stylized top-down court on the signature grid, a ball that
travels between the baselines and turns at each hit, a hit-flash cell, and seeded hit schedules.

Court lines sit exactly on cell boundaries and are thinner than a quarter cell, and the ball rides a
boundary, so neither ever enters a cell's central half: every signature cell stays flat (signature.py).
"""

from __future__ import annotations

from fractions import Fraction

from .canvas import BALL, COURT, MID, SURROUND, WHITE, Canvas, Grid
from .clip import AUDIO_RATE, Event, Rate
from .prng import SplitMix64

LINE = 4


def hit_schedule(seed: int, total_samples: int) -> tuple[Event, ...]:
    """Hits 0.9-1.7 s apart (rally pace on a real court), the first 0.6-1.2 s in, none in the last 0.6 s."""
    rng = SplitMix64(seed)
    events = []
    t = rng.between(AUDIO_RATE * 6 // 10, AUDIO_RATE * 12 // 10)
    while t < total_samples - AUDIO_RATE * 6 // 10:
        events.append(Event("hit", t))
        t += rng.between(AUDIO_RATE * 9 // 10, AUDIO_RATE * 17 // 10)
    return tuple(events)


class CourtScene:
    """Court from cell (2, 2) to cell (14, 8) on a 16 x 9 grid; the frame code fills the top row."""

    def __init__(self, width: int, height: int, rate: Rate, events: tuple[Event, ...]):
        self.width, self.height, self.rate, self.events = width, height, rate, events
        self.base = Canvas(width, height, fill=SURROUND)
        grid = Grid(self.base, 16, 9)
        self.cw, self.ch = grid.cw, grid.ch
        c = self.base
        c.fill(2 * self.cw, 2 * self.ch, 12 * self.cw, 6 * self.ch, COURT)
        x0, x1, y0, y1 = 2 * self.cw, 14 * self.cw, 2 * self.ch, 8 * self.ch
        h = LINE // 2
        for y in (y0, y1):                                   # sidelines
            c.fill(x0 - h, y - h, x1 - x0 + LINE, LINE, WHITE)
        for x in (x0, x1, 5 * self.cw, 11 * self.cw):        # baselines and service lines
            c.fill(x - h, y0 - h, LINE, y1 - y0 + LINE, WHITE)
        c.fill(8 * self.cw - h, y0 - h, LINE, y1 - y0 + LINE, MID)   # net
        c.fill(5 * self.cw, 5 * self.ch - h, 6 * self.cw, LINE, WHITE)  # centre service line
        self.ball_y = 5 * self.ch
        self.left, self.right = x0, x1

    @property
    def corners(self) -> dict:
        x0, x1, y0, y1 = 2 * self.cw, 14 * self.cw, 2 * self.ch, 8 * self.ch
        return {"space": "displayPixels", "order": "topLeft,topRight,bottomRight,bottomLeft",
                "points": [{"x": x0, "y": y0}, {"x": x1, "y": y0}, {"x": x1, "y": y1}, {"x": x0, "y": y1}]}

    def _ball_x(self, t: Fraction) -> int:
        times = [Fraction(e.sample, AUDIO_RATE) for e in self.events]
        ends = [self.left if k % 2 == 0 else self.right for k in range(len(times))]
        if not times or t <= times[0]:
            return self.left
        for k in range(len(times) - 1):
            if times[k] <= t < times[k + 1]:
                frac = (t - times[k]) / (times[k + 1] - times[k])
                return int(round(ends[k] + (ends[k + 1] - ends[k]) * frac))
        # after the last hit the ball crosses once more at the last rally pace and stops
        last = ends[-1]
        target = self.right if last == self.left else self.left
        pace = times[-1] - times[-2] if len(times) > 1 else Fraction(13, 10)
        frac = min(Fraction(1), (t - times[-1]) / pace)
        return int(round(last + (target - last) * frac))

    def flash_frames(self) -> set[int]:
        frames = set()
        for e in self.events:
            f = int(Fraction(e.sample, AUDIO_RATE) * self.rate.fraction)
            frames.update({f, f + 1})
        return frames

    def painter(self):
        flashes = self.flash_frames()

        def paint(n: int) -> Canvas:
            canvas = self.base.copy()
            grid = Grid(canvas, 16, 9)
            grid.frame_code(n)
            grid.cell(15, 8, WHITE if n in flashes else SURROUND)
            t = Fraction(n) / self.rate.fraction
            canvas.disc(self._ball_x(t), self.ball_y, max(4, self.cw // 14), BALL)
            return canvas
        return paint
