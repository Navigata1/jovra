"""Deterministic PCM: a quiet seeded noise floor plus short 'hit' clicks at exact sample onsets."""

from __future__ import annotations

import math
import struct
import sys
import wave
from array import array
from pathlib import Path

from .clip import AUDIO_RATE, AudioSpec
from .prng import SplitMix64

NOISE_AMPLITUDE = 60          # of 32767, about -55 dBFS
CLICK_AMPLITUDE = 20_000
CLICK_HZ = 2_500
CLICK_SAMPLES = 480           # 10 ms
CLICK_DECAY_SAMPLES = 96      # 2 ms time constant

# One click, computed once with integer rounding so every platform writes the same samples.
_CLICK = [int(round(CLICK_AMPLITUDE * math.exp(-n / CLICK_DECAY_SAMPLES) * math.sin(2 * math.pi * CLICK_HZ * n / AUDIO_RATE)))
          for n in range(CLICK_SAMPLES)]


def samples(spec: AudioSpec, count: int, seed: int) -> list[int]:
    rng = SplitMix64(seed ^ 0xA0D10)
    pcm = [rng.between(-NOISE_AMPLITUDE, NOISE_AMPLITUDE) for _ in range(count)]
    for event in spec.events:
        for n, value in enumerate(_CLICK):
            i = event.sample + n
            if i < count:
                pcm[i] = max(-32768, min(32767, pcm[i] + value))
    return pcm


# A neighbouring court's hit: 12 dB quieter and lower, so it sounds like a hit one court away.
DISTRACTOR_AMPLITUDE = 5_000
DISTRACTOR_HZ = 1_600
_DISTRACTOR = [int(round(DISTRACTOR_AMPLITUDE * math.exp(-n / (CLICK_DECAY_SAMPLES * 2))
                         * math.sin(2 * math.pi * DISTRACTOR_HZ * n / AUDIO_RATE))) for n in range(CLICK_SAMPLES)]


def _write_tiled(path: Path, spec: AudioSpec, count: int, seed: int) -> None:
    """Stream ``count`` samples: the seeded one-second noise block repeated, plus every click."""
    rng = SplitMix64(seed ^ 0xA0D10)
    block = array("h", (rng.between(-NOISE_AMPLITUDE, NOISE_AMPLITUDE) for _ in range(AUDIO_RATE)))
    clicks = sorted([(e.sample, _CLICK) for e in spec.events] + [(e.sample, _DISTRACTOR) for e in spec.distractors])
    k = 0
    with wave.open(str(path), "wb") as w:
        w.setnchannels(spec.channels)
        w.setsampwidth(2)
        w.setframerate(AUDIO_RATE)
        for start in range(0, count, AUDIO_RATE):
            n = min(AUDIO_RATE, count - start)
            chunk = array("h", block[:n])
            while k < len(clicks) and clicks[k][0] < start:
                k += 1
            j = k
            while j > 0 and clicks[j - 1][0] + CLICK_SAMPLES > start:   # a click that began in the last chunk
                j -= 1
            while j < len(clicks) and clicks[j][0] < start + n:
                onset, shape = clicks[j]
                for i, value in enumerate(shape):
                    at = onset + i - start
                    if 0 <= at < n:
                        chunk[at] = max(-32768, min(32767, chunk[at] + value))
                j += 1
            if spec.channels > 1:
                chunk = array("h", (v for v in chunk for _ in range(spec.channels)))
            if sys.byteorder != "little":
                chunk.byteswap()
            w.writeframes(chunk.tobytes())


def write_wav(path: Path, spec: AudioSpec, count: int, seed: int) -> None:
    if spec.tiled_noise:
        _write_tiled(path, spec, count, seed)
        return
    if spec.distractors:
        raise ValueError("distractor clicks need tiled_noise audio")
    pcm = samples(spec, count, seed)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(spec.channels)
        w.setsampwidth(2)
        w.setframerate(AUDIO_RATE)
        frames = b"".join(struct.pack("<" + "h" * spec.channels, *([s] * spec.channels)) for s in pcm)
        w.writeframes(frames)
