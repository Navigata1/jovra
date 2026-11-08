"""Unit tests of the two codecs every Studio fixture carries, with no ffmpeg: the frame barcode and the 1 kHz click.

    python3 -m unittest discover -s scripts/media/studio -p 'test_*.py' -v
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from jovra_media.canvas import COURT, Canvas  # noqa: E402
from jovra_studio_media import barcode, clicks  # noqa: E402


def gray(canvas: Canvas) -> bytes:
    return bytes(canvas.y)


class CrcTests(unittest.TestCase):
    def test_crc8_matches_the_published_check_value(self):
        # CRC-8 (poly 0x07, init 0, no reflection, no xorout): the catalogue check value of "123456789" is 0xF4.
        self.assertEqual(barcode.crc8(b"123456789"), 0xF4)


class BarcodeTests(unittest.TestCase):
    RECT = (0, 640, 1280, 80)

    def paint(self, payload: barcode.Payload) -> Canvas:
        canvas = Canvas(1280, 720, fill=COURT)
        barcode.draw(canvas, payload, self.RECT)
        return canvas

    def test_reads_back_the_payload_it_drew(self):
        for payload in (barcode.Payload(1, 0, 0), barcode.Payload(3, 0, 599), barcode.Payload(127, 7, (1 << 20) - 1),
                        barcode.Payload(16, 1, 97_199)):
            with self.subTest(payload):
                self.assertEqual(barcode.read(gray(self.paint(payload)), 1280, 720, self.RECT), payload)

    def test_the_bit_layout_is_start_source_segment_frame_crc_stop(self):
        # Source 5, segment 2, frame 1234: 1 | 0000101 | 010 | 00000000010011010010 | crc | 0 (40 bits, MSB first).
        bits = barcode.bits(barcode.Payload(5, 2, 1234))
        self.assertEqual(len(bits), 40)
        self.assertEqual("".join(map(str, bits[:31])), "1" + "0000101" + "010" + "00000000010011010010")
        self.assertEqual(bits[39], 0)

    def test_flipping_any_single_bit_is_reported_as_a_mismatch(self):
        canvas = self.paint(barcode.Payload(3, 0, 421))
        x0, y0, w, h = self.RECT
        bit_w = w // barcode.BITS
        for i in range(barcode.BITS):
            with self.subTest(bit=i):
                scratch = canvas.copy()
                luma = bytearray(scratch.y)
                value = luma[(y0 + h // 2) * 1280 + x0 + i * bit_w + bit_w // 2]
                flipped = 16 if value > 128 else 235
                for row in range(y0, y0 + h):
                    luma[row * 1280 + x0 + i * bit_w: row * 1280 + x0 + (i + 1) * bit_w] = bytes([flipped]) * bit_w
                with self.assertRaises(barcode.BarcodeError):
                    barcode.read(bytes(luma), 1280, 720, self.RECT)

    def test_reads_a_scaled_and_letterboxed_copy_through_the_mapped_rectangle(self):
        # A 1280x720 source placed in a 1080x1920 portrait frame (9:16 letterbox): picture 1080x608 at y 656.
        src = gray(self.paint(barcode.Payload(2, 0, 77)))
        out_w, out_h, pic = 1080, 1920, (0, 656, 1080, 608)
        out = bytearray([16]) * (out_w * out_h)
        for y in range(pic[3]):
            sy = y * 720 // pic[3]
            for x in range(pic[2]):
                out[(pic[1] + y) * out_w + x] = src[sy * 1280 + x * 1280 // pic[2]]
        rect = barcode.map_rect(self.RECT, (1280, 720), pic)
        self.assertEqual(barcode.read(bytes(out), out_w, out_h, rect), barcode.Payload(2, 0, 77))

    def test_a_frame_without_a_barcode_is_refused(self):
        with self.assertRaises(barcode.BarcodeError):
            barcode.read(gray(Canvas(1280, 720, fill=COURT)), 1280, 720, self.RECT)

    def test_payload_fields_are_range_checked(self):
        for bad in ((0, 0, 0), (128, 0, 0), (1, 8, 0), (1, 0, 1 << 20)):
            with self.subTest(bad), self.assertRaises(ValueError):
                barcode.bits(barcode.Payload(*bad))


class ClickTests(unittest.TestCase):
    def test_click_is_a_one_kilohertz_burst(self):
        shape = clicks.CLICK
        self.assertEqual(len(shape), 480)                      # 10 ms at 48 kHz
        rising = [n for n in range(1, len(shape)) if shape[n - 1] < 0 <= shape[n]]
        # A rising zero crossing every 48 samples (1 ms at 48 kHz): 1 kHz; the burst starts on one, so nine follow.
        self.assertEqual(rising, [48 * k for k in range(1, 10)])

    def test_detects_every_click_at_its_onset_and_nothing_else(self):
        onsets = [4_800, 30_000, 31_200 + 4_800, 90_001]
        pcm = clicks.pcm(onsets, 96_000 + 48_000, seed=7)
        found = clicks.detect(pcm)
        self.assertEqual(len(found), len(onsets))
        for got, want in zip(found, onsets):
            self.assertLessEqual(abs(got - want), 2, f"onset {want} found at {got}")

    def test_streaming_detection_across_chunk_boundaries_finds_the_same_clicks(self):
        # Onsets straddling 1000-sample chunk edges, including one whose threshold crossing is the next chunk.
        onsets = [995, 9_999, 20_500, 47_996, 60_001]
        samples = clicks.pcm(onsets, 72_000, seed=3)
        detector = clicks.Detector()
        for start in range(0, len(samples), 1000):
            detector.feed(samples[start:start + 1000])
        self.assertEqual(detector.finish(), clicks.detect(samples))
        self.assertEqual(len(detector.found), len(onsets))

    def test_written_track_is_the_same_pcm_streamed_or_whole(self):
        import hashlib
        import tempfile
        onsets = [10_000, 47_900, 100_000]
        with tempfile.TemporaryDirectory() as tmp:
            digest = clicks.write_wav(Path(tmp) / "c.wav", onsets, 150_000, seed=5)
        whole = clicks.pcm(onsets, 150_000, seed=5)
        if sys.byteorder != "little":
            whole.byteswap()
        self.assertEqual(digest, hashlib.sha256(whole.tobytes()).hexdigest())

    def test_noise_floor_alone_has_no_clicks(self):
        self.assertEqual(clicks.detect(clicks.pcm([], 48_000 * 3, seed=11)), [])


if __name__ == "__main__":
    unittest.main()
