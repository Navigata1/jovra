"""Burned-in text banners for Studio fixtures, in T11's hand-drawn 5 x 9 pixel font (``jovra_media.label``).

``AngleBadge`` names the camera angle in the top-right corner ("Far baseline"), mirroring the "Sample video
(synthetic)" label T11 draws top-left. It adds the few capitals and lower-case letters angle names need; the
shared glyphs, colours and sizing come from the core label so both banners match. Like the core label, the banner is
shorter than a quarter of a signature cell, so it never enters a cell's central half and never moves the signature.

``banner_pixels`` turns a manifest label entry back into its lit and background pixels, which is what the reader
checks on decoded frames.
"""

from __future__ import annotations

from jovra_media import label as core_label
from jovra_media.canvas import Canvas
from jovra_media.label import ACCENT, ADVANCE, BANNER, GLYPH_H, INK, SPACE

_B = "....."
GLYPHS = dict(core_label.GLYPHS)
GLYPHS.update({
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####.", _B, _B],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#....", _B, _B],
    "N": ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#", _B, _B],
    "b": ["#....", "#....", "####.", "#...#", "#...#", "#...#", "####.", _B, _B],
    "f": ["..##.", ".#...", "####.", ".#...", ".#...", ".#...", ".#...", _B, _B],
    "g": [_B, _B, ".####", "#...#", "#...#", "#...#", ".####", "....#", ".###."],
    "r": [_B, _B, "#.##.", "##..#", "#....", "#....", "#....", _B, _B],
})


def text_width(text: str) -> int:
    return sum(SPACE if ch == " " else ADVANCE for ch in text) - 1


class AngleBadge:
    """The angle name, right-aligned in the top row: banner, a keyline on its right edge and the glyphs."""

    def __init__(self, width: int, height: int, cell_height: int, text: str):
        missing = sorted({ch for ch in text if ch != " " and ch not in GLYPHS})
        if missing:
            raise ValueError(f"no glyph for {missing}")
        limit = cell_height // 4
        self.text, self.cell_height = text, cell_height
        self.scale = max(1, min(height // 180, (limit - 2) // GLYPH_H))
        self.pad = max(1, self.scale)
        self.height = GLYPH_H * self.scale + self.pad
        if self.height > limit:
            raise ValueError(f"badge {self.height} px tall does not fit the top {limit} px of the frame")
        self.margin = 2 * self.scale
        self.width = text_width(text) * self.scale + 2 * self.margin + self.scale
        self.x = width - self.width
        if self.x < 0:
            raise ValueError("badge wider than the frame")

    def lit_pixels(self) -> list[tuple[int, int, int, int]]:
        out = []
        x, y, s = self.x + self.margin, self.pad // 2 + self.pad % 2, self.scale
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
        canvas.fill(self.x, 0, self.width, self.height, BANNER)
        canvas.fill(self.x + self.width - self.scale, 0, self.scale, self.height, ACCENT)
        for x, y, w, h in self.lit_pixels():
            canvas.fill(x, y, w, h, INK)

    def truth(self) -> dict:
        return {"kind": "angle", "text": self.text,
                "region": {"x": self.x, "y": 0, "width": self.width, "height": self.height},
                "cellHeight": self.cell_height, "ink": {"y": INK.y}, "background": {"y": BANNER.y}}


def sample_label_truth(width: int, height: int, cell_height: int) -> dict:
    """The core "Sample video (synthetic)" label's truth, with the fields the reader needs to redraw it."""
    lab = core_label.Label(width, height, cell_height)
    return dict(lab.truth(), kind="sample", cellHeight=cell_height)


def banner_pixels(entry: dict, width: int, height: int) -> tuple[set, list]:
    """(ink pixels, background pixels away from the ink) of a manifest label entry, redrawn from its text."""
    if entry["kind"] == "sample":
        drawn = core_label.Label(width, height, entry["cellHeight"], entry["text"])
        keyline = (0, drawn.scale)
        x0, banner_w = 0, drawn.width
    elif entry["kind"] == "angle":
        drawn = AngleBadge(width, height, entry["cellHeight"], entry["text"])
        keyline = (drawn.x + drawn.width - drawn.scale, drawn.scale)
        x0, banner_w = drawn.x, drawn.width
    else:
        raise ValueError(f"unknown label kind {entry['kind']}")
    region = entry["region"]
    if (x0, banner_w, drawn.height) != (region["x"], region["width"], region["height"]):
        raise ValueError(f"label {entry['text']!r} region {region} does not match its redraw")
    ink = {(x + i, y + j) for x, y, w, h in drawn.lit_pixels() for i in range(w) for j in range(h)}
    near = {(x + dx, y + dy) for x, y in ink for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    background = [(x, y) for y in range(drawn.height) for x in range(x0, x0 + banner_w)
                  if (x, y) not in near and not keyline[0] - 1 <= x < keyline[0] + keyline[1] + 1]
    return ink, background
