"""A planar Y'CbCr 4:2:0 canvas in video range (8- or 10-bit), drawn with flat rectangles only.

Colours are given as 8-bit video-range triples (Y' 16-235, Cb/Cr 16-240); 10-bit canvases store them
shifted left by two, so a 10-bit white is 940. Everything is integer arithmetic, so every run draws the
same bytes on every machine.
"""

from __future__ import annotations

import sys
from array import array
from dataclasses import dataclass


@dataclass(frozen=True)
class Colour:
    y: int
    cb: int
    cr: int


# Luma values keep >= 12 code values away from the signature boundaries 64/128/192 (signature.py).
BLACK = Colour(16, 128, 128)
SURROUND = Colour(40, 118, 120)      # dark green-grey outside the court (level 0)
COURT = Colour(96, 150, 112)         # blue court surface (level 1)
MID = Colour(160, 128, 128)          # mid grey (level 2)
WHITE = Colour(235, 128, 128)        # level 3
BALL = Colour(210, 60, 140)          # optic yellow-green
ACCENT_RED = Colour(96, 100, 200)    # level 1, red-ish
ACCENT_TEAL = Colour(160, 150, 90)   # level 2, teal-ish


class Canvas:
    def __init__(self, width: int, height: int, bit_depth: int = 8, fill: Colour = BLACK):
        if width % 2 or height % 2:
            raise ValueError("4:2:0 needs even dimensions")
        if bit_depth not in (8, 10):
            raise ValueError("bit depth must be 8 or 10")
        self.width, self.height, self.bit_depth = width, height, bit_depth
        self.shift = bit_depth - 8
        cw, ch = width // 2, height // 2
        if bit_depth == 8:
            self.y = bytearray([fill.y]) * (width * height)
            self.cb = bytearray([fill.cb]) * (cw * ch)
            self.cr = bytearray([fill.cr]) * (cw * ch)
        else:
            self.y = array("H", [fill.y << 2]) * (width * height)
            self.cb = array("H", [fill.cb << 2]) * (cw * ch)
            self.cr = array("H", [fill.cr << 2]) * (cw * ch)

    def copy(self) -> "Canvas":
        other = Canvas.__new__(Canvas)
        other.width, other.height, other.bit_depth, other.shift = self.width, self.height, self.bit_depth, self.shift
        other.y, other.cb, other.cr = self.y[:], self.cb[:], self.cr[:]
        return other

    def _run(self, value: int, n: int):
        if self.bit_depth == 8:
            return bytearray([value]) * n
        return array("H", [value << self.shift]) * n

    def fill(self, x: int, y: int, w: int, h: int, colour: Colour) -> None:
        """Fill a rectangle in luma pixels, clipped to the canvas. Chroma covers every chroma sample the
        rectangle touches, so keep shapes on even coordinates where chroma accuracy matters."""
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.width, x + w), min(self.height, y + h)
        if x0 >= x1 or y0 >= y1:
            return
        run = self._run(colour.y, x1 - x0)
        for row in range(y0, y1):
            base = row * self.width
            self.y[base + x0: base + x1] = run
        cw = self.width // 2
        cx0, cx1, cy0, cy1 = x0 // 2, (x1 + 1) // 2, y0 // 2, (y1 + 1) // 2
        run_cb, run_cr = self._run(colour.cb, cx1 - cx0), self._run(colour.cr, cx1 - cx0)
        for row in range(cy0, cy1):
            base = row * cw
            self.cb[base + cx0: base + cx1] = run_cb
            self.cr[base + cx0: base + cx1] = run_cr

    def disc(self, cx: int, cy: int, radius: int, colour: Colour) -> None:
        """A filled disc drawn as one horizontal span per row (integer geometry)."""
        r2 = radius * radius
        for dy in range(-radius, radius + 1):
            half = 0
            while (half + 1) * (half + 1) + dy * dy <= r2:
                half += 1
            self.fill(cx - half, cy + dy, 2 * half + 1, 1, colour)

    def raw(self) -> bytes:
        """The frame as ffmpeg's rawvideo ``yuv420p`` / ``yuv420p10le``."""
        if self.bit_depth == 8:
            return bytes(self.y) + bytes(self.cb) + bytes(self.cr)
        planes = [self.y, self.cb, self.cr]
        if sys.byteorder != "little":
            planes = [p[:] for p in planes]
            for p in planes:
                p.byteswap()
        return b"".join(p.tobytes() for p in planes)


# ----- cell grid helpers -------------------------------------------------------------------------

class Grid:
    """The signature grid of a canvas: drawing whole cells keeps every cell flat."""

    def __init__(self, canvas: Canvas, columns: int, rows: int):
        if canvas.width % columns or canvas.height % rows:
            raise ValueError("grid must divide the canvas")
        self.canvas, self.columns, self.rows = canvas, columns, rows
        self.cw, self.ch = canvas.width // columns, canvas.height // rows

    def cell(self, index_or_col: int, row: int | None = None, colour: Colour = WHITE) -> None:
        if row is None:
            col, row = index_or_col % self.columns, index_or_col // self.columns
        else:
            col = index_or_col
        self.canvas.fill(col * self.cw, row * self.ch, self.cw, self.ch, colour)

    def frame_code(self, value: int, cells: int = 16) -> None:
        """The burned-in frame code: ``cells`` cells in row-major order from the top-left, most significant
        bit first, white for 1 and black for 0."""
        if value >= 1 << cells:
            raise ValueError("frame code overflow")
        for i in range(cells):
            bit = (value >> (cells - 1 - i)) & 1
            self.cell(i, colour=WHITE if bit else BLACK)


# 3x5 block digits: each string is one row, '#' a lit cell.
DIGITS = {
    "0": ["###", "#.#", "#.#", "#.#", "###"],
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"],
    "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"],
    "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "###"],
}


def block_text(grid: Grid, text: str, col: int, row: int, on: Colour, off: Colour) -> None:
    """Human-readable digits drawn in whole cells (3 cells wide, 5 tall, 1-cell gaps)."""
    for k, ch in enumerate(text):
        for dy, line in enumerate(DIGITS[ch]):
            for dx, mark in enumerate(line):
                grid.cell(col + 4 * k + dx, row + dy, on if mark == "#" else off)
