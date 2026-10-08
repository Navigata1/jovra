"""The decoded-frame signature ``jovra.cellLuma.v1``.

Encoders are not byte-reproducible across versions and machines (x264 on a Mac and on Ubuntu differ), but
H.264/HEVC *decoding* is bit-exact. So the committed hash is not over raw pixels; it is over a coarse
signature that every conformant encode of the same source keeps:

* The coded picture (before any rotation) is split into ``columns`` x ``rows`` equal cells.
* For each cell, take the mean of the luma code values in its central half
  (x from ``cw // 4`` to ``3 * cw // 4``, same for y), as ``floor(sum / count)``.
* Reduce that mean to 8 bits (``mean >> (bitDepth - 8)``) and quantize: ``level = min(mean8 // 64, 3)``.
* A frame's signature is one byte per cell (its level), row-major. The clip hash is the SHA-256 of all
  frame signatures concatenated in presentation order.

The renderer only draws content whose source cell means sit at least ``MIN_MARGIN`` code values away from
every quantization boundary (64, 128, 192), and it checks that the decoded signature equals the source
signature before it accepts an encode. Swift computes the same signature from AVFoundation's decode
(JovraBenchmark ``FrameSignature``), which is how the tests prove both decoders see the same frames.
"""

from __future__ import annotations

import hashlib

METHOD = "jovra.cellLuma.v1"
BOUNDARIES = (64, 128, 192)
MIN_MARGIN = 12
LEVELS = 4


def cell_regions(width: int, height: int, columns: int, rows: int):
    if width % columns or height % rows:
        raise ValueError(f"{width}x{height} does not split into {columns}x{rows} equal cells")
    cw, ch = width // columns, height // rows
    for r in range(rows):
        for c in range(columns):
            yield (c * cw + cw // 4, c * cw + (3 * cw) // 4, r * ch + ch // 4, r * ch + (3 * ch) // 4)


def cell_means(luma, width: int, height: int, columns: int, rows: int) -> list[int]:
    """Mean code value of each cell's central half. ``luma`` is a row-major sequence of code values
    (``bytes``/``bytearray`` for 8-bit, ``array('H')`` for 10-bit)."""
    means = []
    for x0, x1, y0, y1 in cell_regions(width, height, columns, rows):
        total = 0
        for y in range(y0, y1):
            base = y * width
            total += sum(luma[base + x0: base + x1])
        means.append(total // ((x1 - x0) * (y1 - y0)))
    return means


def levels(means: list[int], bit_depth: int) -> bytes:
    shift = bit_depth - 8
    return bytes(min((m >> shift) // 64, LEVELS - 1) for m in means)


def margin(means: list[int], bit_depth: int) -> int:
    shift = bit_depth - 8
    return min(abs((m >> shift) - b) for m in means for b in BOUNDARIES)


class ClipHasher:
    def __init__(self) -> None:
        self._sha = hashlib.sha256()
        self.frames = 0

    def add(self, frame_levels: bytes) -> None:
        self._sha.update(frame_levels)
        self.frames += 1

    def hexdigest(self) -> str:
        return self._sha.hexdigest()
