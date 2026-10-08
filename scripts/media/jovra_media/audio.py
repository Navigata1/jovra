"""Deterministic PCM: a quiet seeded noise floor plus short 'hit' clicks at exact sample onsets."""

from __future__ import annotations

import math
import struct
import wave
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


def write_wav(path: Path, spec: AudioSpec, count: int, seed: int) -> None:
    pcm = samples(spec, count, seed)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(spec.channels)
        w.setsampwidth(2)
        w.setframerate(AUDIO_RATE)
        frames = b"".join(struct.pack("<" + "h" * spec.channels, *([s] * spec.channels)) for s in pcm)
        w.writeframes(frames)
