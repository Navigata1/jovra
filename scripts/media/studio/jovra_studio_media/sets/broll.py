"""Short B-roll clips marked "Sample video (synthetic)": the court between points, for B-roll windows in Court
Memories and for the B-roll operation's barcode tests.

Three 6 s clips, H.264 640x360 at 30 fps, drawn with T11's court primitives (``jovra_media.court3d``) and no players:

* ``broll-court-push``: the camera glides 6 m toward the court from behind the near baseline;
* ``broll-ball-drop``: a ball dropped on the near baseline bounces to rest; each bounce is a 1 kHz click (contact
  times from free fall under g = 9.81 m/s^2 with a restitution of 0.7, rounded to the nearest 48 kHz sample);
* ``broll-sideline-pan``: from the side of the net, the view turns from the near court to the far court.

Each carries the T11 label top-left, a 40-bit barcode strip in the bottom 20 px (sources 32-34) and an AAC click
track (the push and the pan are the quiet noise floor only).
"""

from __future__ import annotations

from math import sqrt

from jovra_media import court3d as c3
from jovra_media.canvas import Canvas
from jovra_media.clip import ClipSpec, EncodeOptions, Rate
from jovra_media.label import Label

from ..badge import sample_label_truth
from ..model import StudioClip, with_barcode

SET = "broll"
WIDTH, HEIGHT, GRID = 640, 360, (8, 4)
RATE = Rate(30)
SECONDS = 6
FRAMES = SECONDS * RATE.num
BARCODE_RECT = (0, 340, 640, 20)
G, RESTITUTION, DROP_M, BALL_R = 9.81, 0.7, 1.6, 0.0335
MIN_FLIGHT_S = 0.15        # bounces closer than this are left out (the ball is all but at rest)


def lerp(a, b, k: float):
    return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))


def ball_drop() -> tuple[list[float], callable]:
    """Bounce contact times (s) and the ball centre at time t, for a ball dropped at t = 0.5 s."""
    t0 = 0.5
    h = DROP_M - BALL_R
    contacts = [t0 + sqrt(2 * h / G)]
    v = sqrt(2 * G * h) * RESTITUTION
    while 2 * v / G >= MIN_FLIGHT_S:
        contacts.append(contacts[-1] + 2 * v / G)
        v *= RESTITUTION

    def centre(t: float):
        x, y = 0.6, 0.0
        if t < t0:
            return x, y, DROP_M
        if t < contacts[0]:
            dt = t - t0
            return x, y, DROP_M - G * dt * dt / 2
        speed = sqrt(2 * G * h) * RESTITUTION
        for k in range(len(contacts) - 1):
            if t < contacts[k + 1]:
                dt = t - contacts[k]
                return x, y, BALL_R + speed * dt - G * dt * dt / 2
            speed *= RESTITUTION
        return x, y, BALL_R
    return contacts, centre


def _court_painter(camera_at, label: Label, ball=None):
    def paint(n: int) -> Canvas:
        t = n * RATE.den / RATE.num
        canvas = Canvas(WIDTH, HEIGHT)
        cam = camera_at(n / (FRAMES - 1))
        c3.draw_court(canvas, cam)
        if ball is not None:
            c3.draw_ball(canvas, cam, ball(t))
        label.draw(canvas)
        return canvas
    return paint


def _camera(eye, target, focal: float = 1.0):
    return c3.Camera.looking(eye, target, focal * WIDTH, WIDTH, HEIGHT)


def clips() -> list[StudioClip]:
    label = Label(WIDTH, HEIGHT, HEIGHT // GRID[1])
    contacts, centre = ball_drop()
    specs = (
        ("broll-court-push", 32, "the camera glides toward the court from behind the near baseline",
         lambda k: _camera(lerp((0.0, -20.0, 6.0), (0.0, -14.0, 5.0), k), (0.0, 10.0, 0.0)), None, []),
        ("broll-ball-drop", 33, "a ball dropped on the near baseline bounces to rest",
         lambda k: _camera((3.5, -7.0, 2.6), (0.6, 0.0, 0.6), 1.1), centre, [round(t * 48_000) for t in contacts]),
        ("broll-sideline-pan", 34, "from the side of the net, the view turns from the near court to the far court",
         lambda k: _camera((-15.0, c3.HALF, 5.0), lerp((0.0, 3.0, 0.0), (0.0, 20.0, 0.0), k), 0.95), None, []),
    )
    out = []
    for clip_id, source, what, camera_at, ball, clicks in specs:
        core = ClipSpec(id=clip_id, file=f"{clip_id}.mp4", description=f"Sample video (synthetic), B-roll: {what}.",
                        codec="h264", width=WIDTH, height=HEIGHT, rate=RATE, frame_count=FRAMES,
                        paint=with_barcode(_court_painter(camera_at, label, ball), source, 0, 0, BARCODE_RECT),
                        grid=GRID, seed=source, frame_code=False, encode=EncodeOptions(crf=24, keyint=30))
        extra = {"broll": {"what": what, "bounces": [{"sample": s} for s in clicks]}} if clicks else {"broll": {"what": what}}
        out.append(StudioClip(core=core, role="broll", source_id=source, barcode_rect=BARCODE_RECT,
                              clicks=tuple(clicks), audio_seed=source,
                              labels=(sample_label_truth(WIDTH, HEIGHT, HEIGHT // GRID[1]),), extra=extra))
    return out
