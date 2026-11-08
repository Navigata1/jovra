"""The burned-in "Sample video (synthetic)" label: a hand-drawn 5 x 9 pixel font and a flat banner.

Every glyph is a list of rows ('#' lit). Nothing here reads a font file or an image: the label is drawn
with the same flat rectangles as everything else (canvas.Canvas.fill), so it is identical on every machine.

The banner sits in the top-left corner and is shorter than a quarter of a signature cell, so it never
enters a cell's central half (signature.py) and never moves a cell's level. Sets that burn it in restore
the banner rows after drawing moving content, so a lobbed ball passes behind the label, never over it.
"""

from __future__ import annotations

from .canvas import Canvas, Colour

TEXT = "Sample video (synthetic)"
GLYPH_W, GLYPH_H, ADVANCE, SPACE = 5, 9, 6, 4

_BLANK = "....."
GLYPHS = {
    "S": [".###.", "#...#", "#....", ".###.", "....#", "#...#", ".###.", _BLANK, _BLANK],
    "a": [_BLANK, _BLANK, ".###.", "....#", ".####", "#...#", ".####", _BLANK, _BLANK],
    "m": [_BLANK, _BLANK, "##.#.", "#.#.#", "#.#.#", "#.#.#", "#.#.#", _BLANK, _BLANK],
    "p": [_BLANK, _BLANK, "####.", "#...#", "#...#", "#...#", "####.", "#....", "#...."],
    "l": [".##..", "..#..", "..#..", "..#..", "..#..", "..#..", ".###.", _BLANK, _BLANK],
    "e": [_BLANK, _BLANK, ".###.", "#...#", "#####", "#....", ".###.", _BLANK, _BLANK],
    "v": [_BLANK, _BLANK, "#...#", "#...#", "#...#", ".#.#.", "..#..", _BLANK, _BLANK],
    "i": ["..#..", _BLANK, ".##..", "..#..", "..#..", "..#..", ".###.", _BLANK, _BLANK],
    "d": ["....#", "....#", ".####", "#...#", "#...#", "#...#", ".####", _BLANK, _BLANK],
    "o": [_BLANK, _BLANK, ".###.", "#...#", "#...#", "#...#", ".###.", _BLANK, _BLANK],
    "(": ["...#.", "..#..", ".#...", ".#...", ".#...", ".#...", "..#..", "...#.", _BLANK],
    ")": [".#...", "..#..", "...#.", "...#.", "...#.", "...#.", "..#..", ".#...", _BLANK],
    "s": [_BLANK, _BLANK, ".####", "#....", ".###.", "....#", "####.", _BLANK, _BLANK],
    "y": [_BLANK, _BLANK, "#...#", "#...#", "#...#", "#...#", ".####", "....#", ".###."],
    "n": [_BLANK, _BLANK, "####.", "#...#", "#...#", "#...#", "#...#", _BLANK, _BLANK],
    "t": [".#...", ".#...", "####.", ".#...", ".#...", ".#..#", "..##.", _BLANK, _BLANK],
    "h": ["#....", "#....", "####.", "#...#", "#...#", "#...#", "#...#", _BLANK, _BLANK],
    "c": [_BLANK, _BLANK, ".####", "#....", "#....", "#....", ".####", _BLANK, _BLANK],
}

BANNER = Colour(28, 128, 129)      # near-black slate (sRGB about #101418)
INK = Colour(230, 127, 129)        # warm white (sRGB about #F4F4EE)
ACCENT = Colour(173, 72, 139)      # optic-yellow keyline, the ball's colour family


def text_width(text: str = TEXT) -> int:
    """Width of ``text`` in font pixels (no trailing gap)."""
    width = 0
    for ch in text:
        width += SPACE if ch == " " else ADVANCE
    return width - 1


class Label:
    """The label laid out for one frame size. ``region`` is in coded pixels: x, y, width, height."""

    def __init__(self, width: int, height: int, cell_height: int, text: str = TEXT):
        self.text = text
        # The banner must stay inside the outer quarter of the top signature row.
        limit = cell_height // 4
        self.scale = max(1, min(height // 180, (limit - 2) // GLYPH_H))
        self.pad = max(1, self.scale)
        self.height = GLYPH_H * self.scale + self.pad
        if self.height > limit:
            raise ValueError(f"label {self.height} px tall does not fit the top {limit} px of the frame")
        self.margin = 2 * self.scale
        self.width = text_width(text) * self.scale + 2 * self.margin + self.scale
        if self.width > width:
            raise ValueError("label wider than the frame")
        self.region = {"x": 0, "y": 0, "width": self.width, "height": self.height}

    def lit_pixels(self) -> list[tuple[int, int, int, int]]:
        """Every lit font pixel as a rectangle (x, y, w, h) in frame pixels."""
        out = []
        x = self.margin + self.scale       # after the keyline
        y = self.pad // 2 + self.pad % 2
        s = self.scale
        for ch in self.text:
            if ch == " ":
                x += SPACE * s
                continue
            for row, line in enumerate(GLYPHS[ch]):
                for col, mark in enumerate(line):
                    if mark == "#":
                        out.append((x + col * s, y + row * s, s, s))
            x += ADVANCE * s
        return out

    def draw(self, canvas: Canvas) -> None:
        canvas.fill(0, 0, self.width, self.height, BANNER)
        canvas.fill(0, 0, self.scale, self.height, ACCENT)          # keyline on the left edge
        for x, y, w, h in self.lit_pixels():
            canvas.fill(x, y, w, h, INK)

    def truth(self) -> dict:
        return {"text": self.text, "region": dict(self.region),
                "ink": {"y": INK.y}, "background": {"y": BANNER.y}}


def stamp(target: Canvas, source: Canvas, label: Label) -> None:
    """Copy the label rows of ``source`` (a canvas with the label drawn) over ``target``: moving content
    drawn after the background always passes behind the label."""
    w = target.width
    for row in range(label.height):
        base = row * w
        target.y[base: base + label.width] = source.y[base: base + label.width]
    cw = w // 2
    for row in range((label.height + 1) // 2):
        base = row * cw
        end = base + (label.width + 1) // 2
        target.cb[base: end] = source.cb[base: end]
        target.cr[base: end] = source.cr[base: end]
