"""Ballistic ball paths, keyframed players and a scene painter for the perspective court (court3d.py).

The ball flies in arcs under gravity (no drag, no spin): each arc joins two exactly known points at two
exactly known times, so a hit, a bounce and the next hit are all on the path by construction, and the
ground truth (bounce positions, serve contact and bounce, true speeds) is read straight from the arcs
that are drawn. Times are seconds as floats derived from exact 48 kHz sample or frame indices.
"""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass, field
from math import sqrt

from . import court3d as c3
from .canvas import Canvas
from .label import Label, stamp

G = 9.81


@dataclass(frozen=True)
class Arc:
    t0: float
    t1: float
    p0: tuple
    p1: tuple

    def at(self, t: float) -> tuple:
        span = self.t1 - self.t0
        u = t - self.t0
        k = u / span
        vz = (self.p1[2] - self.p0[2] + G / 2 * span * span) / span
        return (self.p0[0] + (self.p1[0] - self.p0[0]) * k, self.p0[1] + (self.p1[1] - self.p0[1]) * k,
                max(0.0, self.p0[2] + vz * u - G / 2 * u * u))

    def apex_ok(self, net_y: float = c3.HALF, net_h: float = c3.NET_CENTRE) -> bool:
        """True when the arc does not cross the net plane, or clears the tape where it does."""
        y0, y1 = self.p0[1], self.p1[1]
        if (y0 - net_y) * (y1 - net_y) >= 0:
            return True
        k = (net_y - y0) / (y1 - y0)
        return self.at(self.t0 + k * (self.t1 - self.t0))[2] > net_h + 0.05

    def speed_at_start(self) -> float:
        span = self.t1 - self.t0
        vx, vy = (self.p1[0] - self.p0[0]) / span, (self.p1[1] - self.p0[1]) / span
        vz = (self.p1[2] - self.p0[2] + G / 2 * span * span) / span
        return sqrt(vx * vx + vy * vy + vz * vz)

    def chord_speed(self) -> float:
        d = c3.sub(self.p1, self.p0)
        return sqrt(c3.dot(d, d)) / (self.t1 - self.t0)


class BallPath:
    """Arcs in time order; between arcs (and before the first) there is no ball in play."""

    def __init__(self) -> None:
        self.arcs: list[Arc] = []
        self._starts: list[float] = []

    def add(self, arc: Arc) -> Arc:
        if self.arcs and arc.t0 < self.arcs[-1].t1 - 1e-9:
            raise ValueError("arcs must not overlap")
        if arc.t1 <= arc.t0:
            raise ValueError("an arc must take time")
        self.arcs.append(arc)
        self._starts.append(arc.t0)
        return arc

    def at(self, t: float):
        i = bisect_right(self._starts, t) - 1
        if i < 0:
            return None
        arc = self.arcs[i]
        return arc.at(t) if t <= arc.t1 else None


@dataclass
class Track:
    """One player's feet, keyframed as (time, x, y) and interpolated linearly, plus the moments the player
    hits the ball (for the racket animation). ``end`` is where the player starts; ``kit`` their colours.
    The player faces the far end while on the near half and the camera while on the far half."""
    end: str
    kit: str = ""
    keys: list = field(default_factory=list)
    hits: list = field(default_factory=list)       # (time, kind) with kind "serve" | "stroke"
    serve_toss: float = 0.9

    def key(self, t: float, x: float, y: float) -> None:
        self.keys.append((t, x, y))

    def finish(self) -> None:
        if not self.kit:
            self.kit = self.end
        self.keys.sort()
        self.hits.sort()
        self._kt = [k[0] for k in self.keys]
        self._ht = [h[0] for h in self.hits]

    def pose(self, t: float) -> c3.Pose:
        i = bisect_right(self._kt, t)
        if i == 0:
            _, x, y = self.keys[0]
        elif i == len(self.keys):
            _, x, y = self.keys[-1]
        else:
            (ta, xa, ya), (tb, xb, yb) = self.keys[i - 1], self.keys[i]
            k = 0.0 if tb == ta else (t - ta) / (tb - ta)
            x, y = xa + (xb - xa) * k, ya + (yb - ya) * k
        facing = 1 if y < c3.HALF else -1
        swing = overhead = 0.0
        j = bisect_right(self._ht, t)
        for th, kind in self.hits[max(0, j - 1): j + 1]:
            d = t - th
            if kind == "serve" and -self.serve_toss <= d <= 0.25:
                overhead = max(overhead, 1.0 - abs(d) / self.serve_toss if d < 0 else 1.0 - d / 0.25)
            elif kind == "stroke" and -0.35 <= d <= 0.35:
                swing = d / 0.35
        return c3.Pose(x, y, facing, swing=swing, overhead=overhead)


class Scene:
    """Paints frame ``n`` of a court clip: the static court for the current camera (cached), the players
    and the ball in depth order, then the label rows restored on top."""

    def __init__(self, width: int, height: int, rate, camera: c3.Camera, grid: tuple[int, int],
                 tracks: list[Track], ball: BallPath, label: bool = True, camera_moves: list | None = None,
                 side_on: "SideOnSwing | None" = None):
        self.width, self.height, self.rate, self.grid = width, height, rate, grid
        self.tracks, self.ball, self.side_on = tracks, ball, side_on
        self.cameras = [(0, camera)] + sorted(camera_moves or [], key=lambda m: m[0])
        self.label = Label(width, height, height // grid[1]) if label else None
        self._bases: dict[int, Canvas] = {}
        for t in tracks:
            t.finish()

    def camera_at(self, n: int) -> tuple[int, c3.Camera]:
        index = 0
        for i, (frame, _) in enumerate(self.cameras):
            if n >= frame:
                index = i
        return index, self.cameras[index][1]

    def base(self, index: int) -> Canvas:
        if index not in self._bases:
            canvas = Canvas(self.width, self.height)
            c3.draw_court(canvas, self.cameras[index][1])
            if self.label:
                self.label.draw(canvas)
            self._bases[index] = canvas
        return self._bases[index]

    def paint(self, n: int) -> Canvas:
        index, cam = self.camera_at(n)
        base = self.base(index)
        canvas = base.copy()
        t = n * self.rate.den / self.rate.num
        items = []
        for track in self.tracks:
            pose = track.pose(t)
            items.append((cam.project((pose.x, pose.y, 0.0))[2], "player", track, pose))
        p = self.ball.at(t)
        if p is not None:
            items.append((cam.project(p)[2], "ball", None, p))
        for _, kind, track, value in sorted(items, key=lambda item: -item[0]):
            if kind == "ball":
                c3.draw_ball(canvas, cam, value)
            elif self.side_on is not None:
                self.side_on.draw(canvas, cam, value, t)
            else:
                c3.draw_player(canvas, cam, value, track.kit)
        if self.label:
            stamp(canvas, base, self.label)
        return canvas


# ----- side-on forehands -----------------------------------------------------------------------

# Racket head relative to the shoulder, in metres (forward toward the net, up), at each key moment.
# Interpolated linearly and renormalised to the arm-plus-racket length, so the head sweeps an arc.
KEY_POSES = (("ready", -0.90, (0.50, -0.50)), ("unitTurn", -0.60, (-0.70, 0.25)),
             ("racketDrop", -0.20, (-0.55, -0.55)), ("contact", 0.0, (0.70, -0.45)),
             ("finish", 0.35, (-0.25, 0.72)), ("recover", 0.95, (0.50, -0.50)))
REACH = 0.80


@dataclass
class SideOnSwing:
    """Forehands seen side-on: contact times (seconds) and the key-moment schedule above."""
    contacts: list

    def racket(self, t: float) -> tuple[float, float]:
        ready = KEY_POSES[0][2]
        best = None
        for tc in self.contacts:
            if KEY_POSES[0][1] <= t - tc <= KEY_POSES[-1][1]:
                best = tc
        if best is None:
            return ready
        d = t - best
        for (_, ta, va), (_, tb, vb) in zip(KEY_POSES, KEY_POSES[1:]):
            if ta <= d <= tb:
                k = (d - ta) / (tb - ta)
                v = (va[0] + (vb[0] - va[0]) * k, va[1] + (vb[1] - va[1]) * k)
                n = sqrt(v[0] * v[0] + v[1] * v[1]) or 1.0
                return (v[0] / n * REACH, v[1] / n * REACH)
        return ready

    def key_moments(self, tc: float) -> dict[str, float]:
        return {name: tc + offset for name, offset, _ in KEY_POSES if name != "recover"}

    def draw(self, canvas: Canvas, cam: c3.Camera, pose: c3.Pose, t: float) -> None:
        x, y = pose.x, pose.y
        legs = [(x, y - 0.22, 0.0), (x, y + 0.22, 0.0)]
        hip, shoulder, head = (x, y, 0.95), (x, y + 0.02, 1.42), (x, y + 0.03, 1.66)
        def seg(a, b, w, colour):                                                    # noqa: E306
            world = [(a[0], a[1] - w / 2, a[2]), (a[0], a[1] + w / 2, a[2]), (b[0], b[1] + w / 2, b[2]),
                     (b[0], b[1] - w / 2, b[2])]
            c3.world_quad(canvas, cam, world, colour)
        for foot in legs:
            seg(foot, (x, y + (foot[1] - y) * 0.3, 0.80), 0.13, c3.LEGS)
        c3.world_quad(canvas, cam, [(x, y - 0.17, 0.78), (x, y + 0.17, 0.78), (x, y + 0.17, 1.0), (x, y - 0.17, 1.0)], c3.SHORTS)
        c3.world_quad(canvas, cam, [(x, y - 0.15, 0.98), (x, y + 0.17, 0.98), (x, y + 0.19, 1.50), (x, y - 0.13, 1.50)], c3.KIT["near"])
        hx, hy = cam.px(head)
        r = max(1, int(round(0.11 * c3.scale_at(cam, head))))
        c3.ellipse(canvas, hx, hy, r, r, c3.HEAD["near"])
        dx, dz = self.racket(t)
        hand = (x, shoulder[1] + dx * 0.55, shoulder[2] + dz * 0.55)
        tip = (x, shoulder[1] + dx, shoulder[2] + dz)
        seg(shoulder, hand, 0.08, c3.KIT["near"])
        seg(hand, tip, 0.03, c3.RACKET)
        tx, ty = cam.px(tip)
        s = c3.scale_at(cam, tip)
        c3.ellipse(canvas, tx, ty, max(1, int(round(0.12 * s))), max(1, int(round(0.15 * s))), c3.RACKET)
        _ = hip
