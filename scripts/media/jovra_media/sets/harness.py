"""Benchmark-harness clips: the same court scene rendered from two seeds, one for tuning and one held
out. The harness refuses to gate on the tuning seed; gates run on held-out seeds only."""

from __future__ import annotations

from ..clip import AudioSpec, ClipSpec, Rate
from ..scene import CourtScene, hit_schedule

SET = "harness"
SEEDS = ((11, "tuning"), (23, "heldOut"))


def clips() -> list[ClipSpec]:
    rate, frames = Rate(30), 30 * 10
    out = []
    for seed, split in SEEDS:
        events = hit_schedule(seed, frames * 48_000 // 30)
        scene = CourtScene(640, 360, rate, events)
        out.append(ClipSpec(
            id=f"events-s{seed}",
            file=f"events-seed{seed}.mp4",
            description=f"Harness clip, seed {seed} ({split}): hit clicks with exact onsets and a flash cell.",
            codec="h264", width=640, height=360, rate=rate, frame_count=frames,
            paint=scene.painter(), grid=(16, 9), audio=AudioSpec(events=events), seed=seed, split=split,
            extra={"court": scene.corners, "flashCell": {"column": 15, "row": 8}},
        ))
    return out
