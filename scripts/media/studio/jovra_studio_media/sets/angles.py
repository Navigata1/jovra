"""Six angle-labelled synthetic renders of the match sample, for the ST27 Match Broadcast demo (the bundled subset).

Each is a visibly different synthetic view of the same timeline: T11's Jon vs Alex play (the 124 points of the
sample match, ``jovra_media.sets.sample.jon_vs_alex``) drawn by T11's court scene from one of six cameras, with the
"Sample video (synthetic)" label top-left and the angle's name top-right. Frame N of every angle shows the same match
instant, ``N / fps`` seconds into the match, so switching angles at the same match time shows the same moment.

They are demo renders, not a multi-camera simulation (that is S58: no drift, restart, late start or shake here, and
no claim about where real phones would stand). No barcode (it is picture for people) and no audio track (the demo's
sound is the core sample video's, and audio would cost the bundle about 1 MB per angle-minute at any useful rate).

H.264 at a reduced size and rate so all six cover the whole 54:00 match inside the bundle budget.
"""

from __future__ import annotations

from jovra_media import court3d as c3
from jovra_media.animation import Scene
from jovra_media.clip import ClipSpec, EncodeOptions, Rate
from jovra_media.sets import sample as t11

from ..badge import AngleBadge, sample_label_truth
from ..model import StudioClip

SET = "angles"
INPUTS = (t11.MANIFEST, t11.POINTS)
WIDTH, HEIGHT, GRID = 640, 360, t11.GRID
RATE = Rate(12)
DURATION_MS = 3_240_000
ENCODE = EncodeOptions(crf=38, preset="medium", keyint=360)   # 30 s GOP: the six angles fit the 25 MB bundle

MID_Y = c3.HALF
FAR = c3.LENGTH
# (slug, display name, eye, target, focal as a fraction of the width). "Left" and "right" are as seen from the
# Baseline camera (negative x is left).
CAMERAS = (
    ("baseline", "Baseline", (0.0, -15.0, 7.5), (0.0, 9.0, 0.0), 1.05),
    ("far-baseline", "Far baseline", (0.0, FAR + 15.0, 7.5), (0.0, FAR - 9.0, 0.0), 1.05),
    ("near-left", "Near left", (-12.0, -10.0, 6.5), (0.0, MID_Y - 2.0, 0.0), 0.95),
    ("near-right", "Near right", (12.0, -10.0, 6.5), (0.0, MID_Y - 2.0, 0.0), 0.95),
    ("far-left", "Far left", (-12.0, FAR + 10.0, 6.5), (0.0, MID_Y + 2.0, 0.0), 0.95),
    ("far-right", "Far right", (12.0, FAR + 10.0, 6.5), (0.0, MID_Y + 2.0, 0.0), 0.95),
)


def _painter(scene: Scene, badge: AngleBadge):
    def paint(n: int):
        canvas = scene.paint(n)
        badge.draw(canvas)   # drawn last: a lobbed ball passes behind the name, as it does behind the Sample label
        return canvas
    return paint


def clips() -> list[StudioClip]:
    frames = DURATION_MS * RATE.num // (1000 * RATE.den)
    cell_h = HEIGHT // GRID[1]
    out = []
    for slot, (slug, name, eye, target, focal) in enumerate(CAMERAS, start=1):
        play, ends = t11.jon_vs_alex(RATE)
        cam = c3.Camera.looking(eye, target, focal * WIDTH, WIDTH, HEIGHT)
        scene = Scene(WIDTH, HEIGHT, RATE, cam, GRID, [play.tracks[e] for e in ends], play.ball)
        badge = AngleBadge(WIDTH, HEIGHT, cell_h, name)
        core = ClipSpec(id=f"angle-{slug}", file=f"studio-angle-{slug}.mp4",
                        description=f"Sample video (synthetic): the Jon vs Alex sample match seen from the {name} "
                                    f"angle (slot {slot} of 6), 54:00, picture only.",
                        codec="h264", width=WIDTH, height=HEIGHT, rate=RATE, frame_count=frames,
                        paint=_painter(scene, badge), grid=GRID, seed=t11.SEED, frame_code=False, encode=ENCODE)
        out.append(StudioClip(
            core=core, role="angle", audio=False, bundled=True,
            labels=(sample_label_truth(WIDTH, HEIGHT, cell_h), badge.truth()),
            extra={"angle": {"name": name, "slot": slot, "camera": {"eyeM": list(eye), "targetM": list(target),
                                                                    "focalPx": focal * WIDTH},
                             "matchWindow": {"fromMs": 0, "toMs": DURATION_MS},
                             "basedOn": {"mediaId": "sample-media.jon-vs-alex", "points": t11.POINTS}}}))
    return out
