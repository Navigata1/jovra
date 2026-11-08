"""A perspective tennis court, simple player figures and a ball, drawn with flat primitives only.

World coordinates are metres: ``x`` across the court (0 on the centre line, positive to the near
player's right), ``y`` along it (0 on the near baseline, 23.77 on the far one) and ``z`` up. A pinhole
``Camera`` projects them to coded pixels. Only +, -, *, / and ``sqrt`` are used (correctly rounded in
IEEE-754 on every platform), never a transcendental function, so a Mac and a Linux runner draw the same
pixels. The 1-degree camera nudge uses literal sine and cosine constants for the same reason.

Nothing is loaded from disk: no image, font, photograph, likeness or logo. Players are kit-coloured
shapes (legs, shorts, shirt, a head disc and a racket), the ball is a disc with a ground shadow.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import sqrt

from .canvas import Canvas, Colour

# ----- colour ----------------------------------------------------------------------------------


def rgb(r: int, g: int, b: int) -> Colour:
    """An sRGB triple as 8-bit BT.709 video-range Y'CbCr (integer arithmetic, rounded half up)."""
    y = 2126 * r + 7152 * g + 722 * b                     # x 10000
    cb = (b * 10000 - y) * 10000 // 18556                 # Kb = 0.0722, 2(1-Kb) = 1.8556
    cr = (r * 10000 - y) * 10000 // 15748                 # Kr = 0.2126, 2(1-Kr) = 1.5748
    return Colour(16 + (219 * y + 1275000) // 2550000,
                  128 + (224 * cb + (1275000 if cb >= 0 else -1275000)) // 2550000,
                  128 + (224 * cr + (1275000 if cr >= 0 else -1275000)) // 2550000)


# Every large area keeps its luma between about 80 and 110 (8-bit video range), so any mixture of them in a
# signature cell sits far from the 64 and 128 level boundaries; hue, not brightness, tells them apart.
SKY = rgb(64, 78, 98)            # slate backdrop above the windscreens
FENCE = rgb(30, 98, 92)          # deep teal windscreen
RUNOFF = rgb(56, 118, 74)        # green run-off
SURFACE = rgb(52, 100, 160)      # blue hard court
LINE = rgb(236, 238, 232)
NET = rgb(44, 62, 84)            # dark mesh, read as see-through against the blue
NET_TAPE = rgb(222, 224, 220)
POST = rgb(60, 64, 70)
BALL = rgb(214, 238, 58)         # optic yellow
SHADOW = rgb(30, 54, 84)
RACKET = rgb(36, 36, 40)
SHORTS = rgb(34, 38, 52)
LEGS = rgb(120, 104, 92)
# Kit colours keep their luma near the court surface so a passing player never moves a cell's level.
KIT = {"near": rgb(214, 64, 72), "far": rgb(150, 96, 196)}
HEAD = {"near": rgb(176, 72, 80), "far": rgb(120, 92, 164)}

# ----- geometry --------------------------------------------------------------------------------

LENGTH = 23.77
HALF = 11.885
DOUBLES = 5.485
SINGLES = 4.115
SERVICE = 6.40
LINE_W = 0.10
NET_CENTRE, NET_POST, POST_X = 0.914, 1.07, 6.40
RUNOFF_X, RUNOFF_Y = 3.66, 6.40
FENCE_H = 3.0

SIN_1DEG = 0.017452406437283512     # sin(1 degree), as a literal so no libm call is involved
COS_1DEG = 0.9998476951563913


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    n = sqrt(dot(a, a))
    return (a[0] / n, a[1] / n, a[2] / n)


@dataclass(frozen=True)
class Camera:
    eye: tuple
    forward: tuple
    right: tuple
    up: tuple
    focal: float
    cx: float
    cy: float

    @staticmethod
    def looking(eye, target, focal: float, width: int, height: int) -> "Camera":
        f = norm(sub(target, eye))
        r = norm(cross(f, (0.0, 0.0, 1.0)))
        u = cross(r, f)
        return Camera(eye, f, r, u, focal, width / 2, height / 2)

    def project(self, p):
        """Pixel position and depth (metres along the view axis) of world point ``p``."""
        d = sub(p, self.eye)
        z = dot(d, self.forward)
        return (self.cx + self.focal * dot(d, self.right) / z, self.cy - self.focal * dot(d, self.up) / z, z)

    def px(self, p) -> tuple[int, int]:
        x, y, _ = self.project(p)
        return int(round(x)), int(round(y))

    def nudged(self, yaw: int = 0, pitch: int = 0) -> "Camera":
        """The camera turned by ``yaw`` and ``pitch`` whole degrees (each -1, 0 or +1): a knocked tripod."""
        f, r, u = self.forward, self.right, self.up
        for _ in range(abs(yaw)):
            s = SIN_1DEG if yaw > 0 else -SIN_1DEG
            rot = lambda v: (v[0] * COS_1DEG - v[1] * s, v[0] * s + v[1] * COS_1DEG, v[2])   # noqa: E731
            f, r, u = rot(f), rot(r), rot(u)
        for _ in range(abs(pitch)):
            s = SIN_1DEG if pitch > 0 else -SIN_1DEG
            f, u = (tuple(f[i] * COS_1DEG + u[i] * s for i in range(3)),
                    tuple(u[i] * COS_1DEG - f[i] * s for i in range(3)))
        return Camera(self.eye, f, r, u, self.focal, self.cx, self.cy)


def fill_polygon(canvas: Canvas, points, colour: Colour) -> None:
    """Fill a convex polygon given in (fractional) pixels with one horizontal span per row. A polygon
    thinner than a pixel still paints one row, so distant court lines never vanish."""
    ys = [p[1] for p in points]
    lo, hi = min(ys), max(ys)
    first, last = int(lo + 0.5), int(hi - 0.5)
    rows = range(first, last + 1) if last >= first else [int((lo + hi) / 2)]
    n = len(points)
    for row in rows:
        yc = min(max(row + 0.5, lo), hi)
        xs = []
        for i in range(n):
            (x0, y0), (x1, y1) = points[i][:2], points[(i + 1) % n][:2]
            if (y0 <= yc <= y1) or (y1 <= yc <= y0):
                xs.append(x0 if y1 == y0 else x0 + (x1 - x0) * (yc - y0) / (y1 - y0))
        if not xs:
            continue
        a, b = int(round(min(xs))), int(round(max(xs)))
        canvas.fill(a, row, max(1, b - a), 1, colour)


NEAR_PLANE = 0.2


def clip_near(cam: Camera, corners) -> list:
    """Clip a convex world polygon to the part in front of the camera (Sutherland-Hodgman against the
    near plane), so a surface the camera stands on is drawn up to the camera rather than dropped."""
    depth = [dot(sub(c, cam.eye), cam.forward) - NEAR_PLANE for c in corners]
    out = []
    n = len(corners)
    for i in range(n):
        a, b, da, db = corners[i], corners[(i + 1) % n], depth[i], depth[(i + 1) % n]
        if da >= 0:
            out.append(a)
        if (da >= 0) != (db >= 0):
            k = da / (da - db)
            out.append((a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k))
    return out


def world_quad(canvas: Canvas, cam: Camera, corners, colour: Colour) -> None:
    visible = clip_near(cam, corners)
    if len(visible) >= 3:
        fill_polygon(canvas, [cam.project(c) for c in visible], colour)


def ellipse(canvas: Canvas, cx: int, cy: int, rx: int, ry: int, colour: Colour) -> None:
    rx, ry = max(1, rx), max(1, ry)
    for dy in range(-ry, ry + 1):
        # half-width at this row: rx * sqrt(1 - (dy/ry)^2), integer-exact through isqrt-style search
        half = 0
        while (half + 1) * (half + 1) * ry * ry + dy * dy * rx * rx <= rx * rx * ry * ry:
            half += 1
        canvas.fill(cx - half, cy + dy, 2 * half + 1, 1, colour)


# ----- the static court ------------------------------------------------------------------------

def _ground_line(canvas, cam, x0, y0, x1, y1, w=LINE_W) -> None:
    if x0 == x1:   # along the court
        world_quad(canvas, cam, [(x0 - w / 2, y0, 0), (x0 + w / 2, y0, 0), (x1 + w / 2, y1, 0), (x1 - w / 2, y1, 0)], LINE)
    else:          # across the court
        world_quad(canvas, cam, [(x0, y0 - w / 2, 0), (x1, y0 - w / 2, 0), (x1, y1 + w / 2, 0), (x0, y1 + w / 2, 0)], LINE)


def draw_court(canvas: Canvas, cam: Camera, net: bool = True) -> None:
    """Backdrop, windscreens, run-off, court surface, every line and the net."""
    canvas.fill(0, 0, canvas.width, canvas.height, SKY)
    wx, near_y, far_y = DOUBLES + RUNOFF_X, -RUNOFF_Y, LENGTH + RUNOFF_Y
    world_quad(canvas, cam, [(-wx, far_y, 0), (wx, far_y, 0), (wx, far_y, FENCE_H), (-wx, far_y, FENCE_H)], FENCE)
    for side in (-1, 1):   # side windscreens, seen at an angle
        world_quad(canvas, cam, [(side * wx, near_y, 0), (side * wx, far_y, 0), (side * wx, far_y, FENCE_H),
                                 (side * wx, near_y, FENCE_H)], FENCE)
    world_quad(canvas, cam, [(-wx, near_y, 0), (wx, near_y, 0), (wx, far_y, 0), (-wx, far_y, 0)], RUNOFF)
    world_quad(canvas, cam, [(-DOUBLES, 0, 0), (DOUBLES, 0, 0), (DOUBLES, LENGTH, 0), (-DOUBLES, LENGTH, 0)], SURFACE)
    for x in (-DOUBLES, -SINGLES, SINGLES, DOUBLES):
        _ground_line(canvas, cam, x, 0, x, LENGTH)
    for y in (0.0, LENGTH):
        _ground_line(canvas, cam, -DOUBLES, y, DOUBLES, y)
        _ground_line(canvas, cam, 0, y if y == 0 else y - 0.2, 0, 0.2 if y == 0 else y)   # centre marks
    for y in (HALF - SERVICE, HALF + SERVICE):
        _ground_line(canvas, cam, -SINGLES, y, SINGLES, y)
    _ground_line(canvas, cam, 0, HALF - SERVICE, 0, HALF + SERVICE)
    if net:
        draw_net(canvas, cam)


def draw_net(canvas: Canvas, cam: Camera) -> None:
    for side in (-1, 1):
        x = side * POST_X
        world_quad(canvas, cam, [(x - 0.04, HALF, 0), (x + 0.04, HALF, 0), (x + 0.04, HALF, NET_POST),
                                 (x - 0.04, HALF, NET_POST)], POST)
    for side in (-1, 1):   # each half sags from the post to the centre strap
        world_quad(canvas, cam, [(0, HALF, 0), (side * POST_X, HALF, 0), (side * POST_X, HALF, NET_POST),
                                 (0, HALF, NET_CENTRE)], NET)
        world_quad(canvas, cam, [(0, HALF, NET_CENTRE - 0.05), (side * POST_X, HALF, NET_POST - 0.05),
                                 (side * POST_X, HALF, NET_POST), (0, HALF, NET_CENTRE)], NET_TAPE)


# ----- moving content --------------------------------------------------------------------------

def scale_at(cam: Camera, p) -> float:
    """Pixels per metre at world point ``p``."""
    return cam.focal / max(0.5, cam.project(p)[2])


def draw_ball(canvas: Canvas, cam: Camera, p, shadow: bool = True) -> None:
    s = scale_at(cam, p)
    r = max(2, int(round(0.054 * s)))     # radius 1.6 x life size, so the ball stays visible at low resolution
    if shadow:
        gx, gy = cam.px((p[0], p[1], 0.0))
        ellipse(canvas, gx, gy, r + 1, max(1, (r + 1) // 2), SHADOW)
    bx, by = cam.px(p)
    ellipse(canvas, bx, by, r, r, BALL)


@dataclass(frozen=True)
class Pose:
    """Where a figure stands and what its racket is doing. ``swing`` runs from -1 (back) to 1 (through);
    ``overhead`` raises the racket above the head (serve)."""
    x: float
    y: float
    facing: int            # +1 faces the far end (near player), -1 faces the camera (far player)
    swing: float = 0.0
    overhead: float = 0.0
    lean: float = 0.0


def _rot(t: float) -> tuple[float, float]:
    """(cos, sin) of the angle whose half-angle tangent is ``t``: a rational rotation, no libm."""
    d = 1 + t * t
    return (1 - t * t) / d, 2 * t / d


def draw_player(canvas: Canvas, cam: Camera, pose: Pose, kit_name: str) -> None:
    """A figure 1.80 m tall: legs, shorts, shirt, head and a racket, in screen space at the projected
    feet, scaled by depth. Right-handed; the racket side flips with the facing."""
    feet = (pose.x, pose.y, 0.0)
    fx, fy, depth = cam.project(feet)
    if depth <= 0.5:
        return
    s = cam.focal / depth
    px = lambda m: max(1, int(round(m * s)))                 # noqa: E731
    cx, base = int(round(fx)), int(round(fy))
    kit, head = KIT[kit_name], HEAD[kit_name]
    leg_h, shorts_h, shirt_h = px(0.80), px(0.22), px(0.46)
    hip_w, shirt_w, leg_w = px(0.34), px(0.44), px(0.12)
    lean = int(round(pose.lean * s * 0.15))
    # legs, slightly apart
    canvas.fill(cx - hip_w // 2, base - leg_h, leg_w, leg_h, LEGS)
    canvas.fill(cx + hip_w // 2 - leg_w, base - leg_h, leg_w, leg_h, LEGS)
    top_shorts = base - leg_h - shorts_h
    canvas.fill(cx - hip_w // 2, top_shorts, hip_w, shorts_h, SHORTS)
    top_shirt = top_shorts - shirt_h
    canvas.fill(cx - shirt_w // 2 + lean, top_shirt, shirt_w, shirt_h, kit)
    r_head = max(1, px(0.11))
    head_y = top_shirt - px(0.04) - r_head
    ellipse(canvas, cx + lean, head_y, r_head, r_head, head)
    # racket: an arm from the shoulder and an oval head; it sweeps with the swing
    side = 1 if pose.facing > 0 else -1
    shoulder = (cx + lean + side * (shirt_w // 2), top_shirt + px(0.06))
    if pose.overhead > 0:
        reach = px(0.55 + 0.35 * pose.overhead)
        hand = (shoulder[0] - side * px(0.05), shoulder[1] - reach)
    else:
        c, sn = _rot(0.9 * pose.swing)
        reach = px(0.62)
        hand = (shoulder[0] + int(round(side * reach * c)), shoulder[1] + int(round(reach * (0.35 - 0.6 * sn))))
    arm_w = max(1, px(0.07))
    x0, x1 = sorted((shoulder[0], hand[0]))
    y0, y1 = sorted((shoulder[1], hand[1]))
    canvas.fill(x0, y0, max(arm_w, x1 - x0), arm_w, kit)
    canvas.fill(hand[0] - arm_w // 2, y0, arm_w, max(arm_w, y1 - y0), kit)
    ellipse(canvas, hand[0] + side * px(0.12), hand[1] - px(0.12), max(1, px(0.13)), max(1, px(0.16)), RACKET)
