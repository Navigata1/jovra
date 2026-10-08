"""The Simulator fixture camera clip (D9, ADR-0012): what ``FixtureCamera`` streams through the real
segment pipeline on a device with no camera. 1280x720, 30 fps, 12 s, H.264 + AAC 48 kHz mono.

It carries everything a capture test needs to check the pipeline end to end: a frame code in the top row
(dropped or repeated frames show up as gaps), hit clicks in the audio with a matching flash cell
(audio/video sync), and a court whose four corners are exact (the framing guide's default corners).
"""

from __future__ import annotations

from ..clip import AudioSpec, ClipSpec, Rate
from ..scene import CourtScene, hit_schedule

SET = "fixtureCamera"
SEED = 7


def clips() -> list[ClipSpec]:
    rate, frames = Rate(30), 30 * 12
    events = hit_schedule(SEED, frames * 48_000 // 30)
    scene = CourtScene(1280, 720, rate, events)
    return [ClipSpec(
        id="fixture-camera",
        file="fixture-camera-720p30.mp4",
        description="Simulator fixture camera: court with exact corners, a ball turning at each hit, hit clicks "
                    "in the audio with a flash cell, and the frame code in the top row.",
        codec="h264", width=1280, height=720, rate=rate, frame_count=frames,
        paint=scene.painter(), grid=(16, 9), audio=AudioSpec(events=events), seed=SEED,
        extra={"court": scene.corners, "flashCell": {"column": 15, "row": 8}},
    )]
