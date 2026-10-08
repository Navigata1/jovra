"""SplitMix64: a tiny seeded generator with a published algorithm, so Swift, Kotlin and Python can
reproduce the same schedule. Python's ``random`` is never used for fixtures."""

from __future__ import annotations

MASK = (1 << 64) - 1


class SplitMix64:
    def __init__(self, seed: int):
        self.state = seed & MASK

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        return z ^ (z >> 31)

    def between(self, lo: int, hi: int) -> int:
        """An integer in [lo, hi], inclusive."""
        return lo + self.next() % (hi - lo + 1)
