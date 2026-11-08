"""The Studio frame barcode (``jovra.frame-barcode/1``): a 40-bit strip that names the source and the frame.

Layout, left to right, most significant bit first, one equal-width block per bit across the barcode rectangle:

    bit 0       start, always 1
    bits 1-7    source id (1-127): which fixture file family
    bits 8-10   segment (0-7): the recorded segment of a restarted capture
    bits 11-30  frame id (0-1,048,575): the frame index on the source's session clock
    bits 31-38  CRC-8 (polynomial 0x07, init 0) over the 30 payload bits packed big-endian into 4 bytes
    bit 39      stop, always 0

A 1 is white (Y' 235) and a 0 is black (Y' 16), video range. Blocks are large (at least 16 x 20 px), so they
survive lossy encoding and scaling: the reader averages the central half of each block and thresholds at Y' 128.
Every single-bit error is caught: the start/stop bits and the CRC-8 (which detects all single-bit errors) make the
reader raise ``BarcodeError`` rather than return a wrong frame id.

The rectangle is in source pixels. ``map_rect`` carries it into an output frame that shows the source scaled or
letterboxed, so a renderer test reads output frames with the same code.
"""

from __future__ import annotations

from dataclasses import dataclass

from jovra_media.canvas import BLACK, WHITE, Canvas

METHOD = "jovra.frame-barcode/1"
BITS = 40
SOURCE_BITS, SEGMENT_BITS, FRAME_BITS, CRC_BITS = 7, 3, 20, 8
THRESHOLD = 128
MIN_CONTRAST = 40   # a block whose mean is within this of the threshold is unreadable, not guessed


class BarcodeError(ValueError):
    """The rectangle holds no valid barcode: a start/stop bit, the CRC or the contrast failed."""


@dataclass(frozen=True)
class Payload:
    source: int
    segment: int
    frame: int

    def as_dict(self) -> dict:
        return {"source": self.source, "segment": self.segment, "frame": self.frame}


def crc8(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def _packed(source: int, segment: int, frame: int) -> int:
    return (source << (SEGMENT_BITS + FRAME_BITS)) | (segment << FRAME_BITS) | frame


def _field_bits(value: int, width: int) -> list[int]:
    return [(value >> (width - 1 - i)) & 1 for i in range(width)]


def bits(payload: Payload) -> list[int]:
    if not 1 <= payload.source < 1 << SOURCE_BITS:
        raise ValueError(f"source id {payload.source} is outside 1-{(1 << SOURCE_BITS) - 1}")
    if not 0 <= payload.segment < 1 << SEGMENT_BITS:
        raise ValueError(f"segment {payload.segment} is outside 0-{(1 << SEGMENT_BITS) - 1}")
    if not 0 <= payload.frame < 1 << FRAME_BITS:
        raise ValueError(f"frame id {payload.frame} does not fit {FRAME_BITS} bits")
    packed = _packed(payload.source, payload.segment, payload.frame)
    return ([1] + _field_bits(packed, SOURCE_BITS + SEGMENT_BITS + FRAME_BITS)
            + _field_bits(crc8(packed.to_bytes(4, "big")), CRC_BITS) + [0])


def block(rect: tuple[int, int, int, int], i: int) -> tuple[int, int, int, int]:
    """Bit ``i``'s block (x, y, w, h); block edges are rounded so the blocks tile the rectangle exactly."""
    x, y, w, h = rect
    x0, x1 = x + i * w // BITS, x + (i + 1) * w // BITS
    return x0, y, x1 - x0, h


def draw(canvas: Canvas, payload: Payload, rect: tuple[int, int, int, int]) -> None:
    for i, bit in enumerate(bits(payload)):
        bx, by, bw, bh = block(rect, i)
        canvas.fill(bx, by, bw, bh, WHITE if bit else BLACK)


def block_means(luma, width: int, rect: tuple[int, int, int, int]) -> list[int]:
    """Mean luma (8-bit) of the central half of every bit block."""
    means = []
    for i in range(BITS):
        bx, by, bw, bh = block(rect, i)
        x0, x1 = bx + bw // 4, bx + max(bw // 4 + 1, (3 * bw) // 4)
        y0, y1 = by + bh // 4, by + max(bh // 4 + 1, (3 * bh) // 4)
        total = 0
        for row in range(y0, y1):
            base = row * width
            total += sum(luma[base + x0: base + x1])
        means.append(total // ((x1 - x0) * (y1 - y0)))
    return means


def read(luma, width: int, height: int, rect: tuple[int, int, int, int]) -> Payload:
    """Decode the barcode in ``rect`` of an 8-bit luma plane (row-major, ``width`` x ``height``)."""
    x, y, w, h = rect
    if x < 0 or y < 0 or x + w > width or y + h > height or w < BITS or h < 1:
        raise BarcodeError(f"barcode rectangle {rect} does not fit a {width}x{height} frame")
    means = block_means(luma, width, rect)
    weak = [i for i, m in enumerate(means) if abs(m - THRESHOLD) < MIN_CONTRAST]
    if weak:
        raise BarcodeError(f"bits {weak[:5]} are unreadable (block means {[means[i] for i in weak[:5]]})")
    got = [1 if m > THRESHOLD else 0 for m in means]
    if got[0] != 1 or got[-1] != 0:
        raise BarcodeError("start or stop bit is wrong")
    packed = 0
    for bit in got[1:1 + SOURCE_BITS + SEGMENT_BITS + FRAME_BITS]:
        packed = (packed << 1) | bit
    crc = 0
    for bit in got[1 + SOURCE_BITS + SEGMENT_BITS + FRAME_BITS: BITS - 1]:
        crc = (crc << 1) | bit
    if crc != crc8(packed.to_bytes(4, "big")):
        raise BarcodeError("CRC mismatch: the barcode was altered or misread")
    source = packed >> (SEGMENT_BITS + FRAME_BITS)
    if source == 0:
        raise BarcodeError("source id 0 is reserved")
    return Payload(source, (packed >> FRAME_BITS) & ((1 << SEGMENT_BITS) - 1), packed & ((1 << FRAME_BITS) - 1))


def map_rect(rect: tuple[int, int, int, int], source_size: tuple[int, int],
             picture: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """The barcode rectangle of a source frame of ``source_size`` shown scaled into ``picture`` (x, y, w, h) of an
    output frame (a scaled copy, or the active picture of a letterboxed one)."""
    sw, sh = source_size
    px, py, pw, ph = picture
    x, y, w, h = rect
    x0, y0 = px + x * pw // sw, py + y * ph // sh
    x1, y1 = px + (x + w) * pw // sw, py + (y + h) * ph // sh
    return x0, y0, x1 - x0, y1 - y0


def layout(rect: tuple[int, int, int, int]) -> dict:
    """The barcode block a manifest records."""
    x, y, w, h = rect
    return {"method": METHOD, "bits": BITS, "rect": {"x": x, "y": y, "width": w, "height": h},
            "fields": {"start": 1, "source": SOURCE_BITS, "segment": SEGMENT_BITS, "frame": FRAME_BITS,
                       "crc8": CRC_BITS, "stop": 1},
            "one": {"y": WHITE.y}, "zero": {"y": BLACK.y}, "threshold": {"y": THRESHOLD}}
