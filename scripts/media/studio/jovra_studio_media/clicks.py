"""The Studio click track: 1 kHz clicks at exact 48 kHz sample onsets over a quiet seeded noise floor, and the
detector that finds them again in decoded audio.

A click is a 10 ms burst of a 1 kHz sine (ten cycles) with a 0.5 ms linear attack and a linear decay, peak 16000
of 32767 (about -6 dBFS). The noise floor is +/-60 (about -55 dBFS), so a click is 48 dB above it. The sine table
is rounded once with integer arithmetic, so every platform writes the same PCM (``write_wav`` returns its SHA-256).

The detector (``Detector``) takes a candidate where the absolute sample first exceeds ``THRESHOLD`` (half the peak)
after at least ``REFRACTORY`` samples below it, places the onset on the energy envelope's half-peak rising edge (so
the pre-echo an AAC encoder spreads ahead of a transient does not move it) and accepts it only when the 10 ms from
the onset hold about nine full swings past +/-1000 (a 1 kHz check with hysteresis, so a pop, a dropout or noise in
the click's quiet tail is not counted).
"""

from __future__ import annotations

import hashlib
import math
import sys
import wave
from array import array
from pathlib import Path

from jovra_media.prng import SplitMix64

RATE = 48_000
HZ = 1_000
PEAK = 16_000
SAMPLES = 480                 # 10 ms
ATTACK = 24                   # 0.5 ms
NOISE = 60
THRESHOLD = PEAK // 2           # half the click peak: above AAC pre-echo before a transient
REFRACTORY = 2_400            # 50 ms of quiet separates two clicks
MIN_SPACING = 4_800           # fixture clicks are at least 100 ms apart

_SINE = [int(round(32_767 * math.sin(2 * math.pi * n / (RATE // HZ)))) for n in range(RATE // HZ)]


def _envelope(n: int) -> tuple[int, int]:
    """Envelope as a fraction (numerator, denominator)."""
    if n < ATTACK:
        return n, ATTACK
    return SAMPLES - n, SAMPLES - ATTACK


CLICK = []
for _n in range(SAMPLES):
    num, den = _envelope(_n)
    CLICK.append(PEAK * num * _SINE[_n % len(_SINE)] // (den * 32_767))
del _n


def _noise_block(seed: int) -> array:
    rng = SplitMix64(seed ^ 0xC11C)
    return array("h", (rng.between(-NOISE, NOISE) for _ in range(RATE)))


def _checked(onsets: list[int], count: int) -> list[int]:
    ordered = sorted(onsets)
    if any(b - a < MIN_SPACING for a, b in zip(ordered, ordered[1:])):
        raise ValueError("clicks closer than 100 ms")
    if any(o < 0 or o + SAMPLES > count for o in ordered):
        raise ValueError("a click does not fit inside the audio")
    return ordered


def chunks(onsets: list[int], count: int, seed: int):
    """Yield ``count`` mono samples one second at a time: the seeded one-second noise block repeated, plus a click
    at every onset (an hour of audio never sits in memory)."""
    ordered = _checked(onsets, count)
    block = _noise_block(seed)
    k = 0
    for start in range(0, count, RATE):
        n = min(RATE, count - start)
        chunk = array("h", block[:n])
        while k > 0 and ordered[k - 1] + SAMPLES > start:   # a click that began in the previous second
            k -= 1
        while k < len(ordered) and ordered[k] < start + n:
            for i, value in enumerate(CLICK):
                at = ordered[k] + i - start
                if 0 <= at < n:
                    chunk[at] = max(-32_768, min(32_767, chunk[at] + value))
            k += 1
        yield chunk


def pcm(onsets: list[int], count: int, seed: int) -> array:
    """All ``count`` samples at once (short clips and tests)."""
    out = array("h")
    for chunk in chunks(onsets, count, seed):
        out.extend(chunk)
    return out


def write_wav(path: Path, onsets: list[int], count: int, seed: int) -> str:
    """Write the click track as mono 16-bit 48 kHz PCM; returns the SHA-256 of its little-endian samples."""
    sha = hashlib.sha256()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        for chunk in chunks(onsets, count, seed):
            if sys.byteorder != "little":
                chunk.byteswap()
            raw = chunk.tobytes()
            sha.update(raw)
            w.writeframes(raw)
    return sha.hexdigest()


HYSTERESIS = 1_000


def _is_one_kilohertz(window) -> bool:
    """About nine full swings (below -1000, then above +1000) in 10 ms: 1 kHz. The hysteresis ignores the noise and
    codec noise crossing zero in the click's quiet tail."""
    swings, low = 0, False
    for v in window:
        if v < -HYSTERESIS:
            low = True
        elif v > HYSTERESIS and low:
            swings += 1
            low = False
    return 7 <= swings <= 11


PERIOD = RATE // HZ


def _half_energy_index(window) -> int:
    """First index where the one-period moving sum of |x| reaches half its maximum over ``window``: the burst's
    rising edge, insensitive to the pre-echo a lossy codec spreads ahead of a transient."""
    sums = []
    running = sum(abs(v) for v in window[:PERIOD])
    sums.append(running)
    for k in range(PERIOD, len(window)):
        running += abs(window[k]) - abs(window[k - PERIOD])
        sums.append(running)
    half = max(sums) / 2
    return next(k for k, e in enumerate(sums) if e >= half)


# Where the clean click's own rising edge sits, so a detection maps back to the click's first sample.
EDGE = _half_energy_index([0] * SAMPLES + CLICK + [0] * SAMPLES) - SAMPLES


class Detector:
    """Streaming click detector: ``feed`` decoded samples in order, then ``finish``; ``found`` holds the onsets.

    A candidate is where the absolute sample first exceeds ``THRESHOLD`` after at least ``REFRACTORY`` samples below
    it. Its onset is located from the energy envelope (the half-peak rising edge in the 10 ms either side, minus the
    clean click's own ``EDGE``), and the 10 ms from the onset must be a 1 kHz burst. Quiet stretches are skipped a
    block at a time."""

    def __init__(self) -> None:
        self.found: list[int] = []
        self._buf = array("h")
        self._base = 0          # absolute index of _buf[0]
        self._pos = 0           # next absolute index to examine
        self._quiet = REFRACTORY

    def feed(self, samples) -> None:
        self._buf.extend(samples)
        self._scan(self._base + len(self._buf) - SAMPLES)

    def finish(self) -> list[int]:
        self._scan(self._base + len(self._buf))
        return self.found

    def _candidate(self, i: int) -> None:
        buf, base = self._buf, self._base
        lo = max(base, i - SAMPLES)
        window = buf[lo - base: i - base + SAMPLES]
        onset = max(base, lo + _half_energy_index(window) - EDGE)
        if _is_one_kilohertz(buf[onset - base: onset - base + SAMPLES]):
            self.found.append(onset)

    def _scan(self, stop: int) -> None:
        i = self._pos
        while i < stop:
            j = i - self._base
            block = self._buf[j: j + min(SAMPLES, stop - i)]
            if max(block) <= THRESHOLD and -min(block) <= THRESHOLD:
                self._quiet += len(block)
                i += len(block)
                continue
            for value in block:
                if abs(value) > THRESHOLD:
                    if self._quiet >= REFRACTORY:
                        self._candidate(i)
                    self._quiet = 0
                else:
                    self._quiet += 1
                i += 1
        self._pos = i
        keep = max(0, i - self._base - 2 * SAMPLES)
        if keep > RATE:
            del self._buf[:keep]
            self._base += keep


def detect(samples) -> list[int]:
    """Onset sample of every 1 kHz click in mono 16-bit samples."""
    d = Detector()
    d.feed(samples)
    return d.finish()


def frame_of(sample: int, num: int, den: int = 1) -> int:
    """The video frame on screen when ``sample`` plays: floor(sample / 48000 * fps)."""
    return sample * num // (RATE * den)
