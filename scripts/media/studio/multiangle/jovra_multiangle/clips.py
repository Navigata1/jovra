"""One camera segment as an S08 ``StudioClip``: the painter that draws the scene at each frame's true match time, and
the click track at each heard arrival. The S08 pipeline encodes, muxes and verifies it (T10's renderer core under it).

The picture is T11's court scene (players, ball, court) from the placement's S08 angle camera, drawn at the frame's
match time (``t = a_k + rate * t_src(n)``), never at ``n / fps``: that is what makes drift, phase, restarts and VFR
visible in the picture. A shaken frame is drawn from the camera nudged by whole degrees. A covered lens is a flat
dark field. Every frame carries the "Sample video (synthetic)" label (top left) and the placement name (top right);
the coded variant adds the S08 frame barcode (source id, segment, frame index) in the bottom 20 px. An HLG camera's
frames are the same 8-bit picture scaled to 10 bits and tagged BT.2020 HLG: a format variant, not a graded picture.
"""

from __future__ import annotations

import sys
from array import array

from jovra_media import court3d as c3
from jovra_media.animation import Scene
from jovra_media.canvas import Canvas
from jovra_media.clip import ClipSpec, EncodeOptions
from jovra_media.label import Label, stamp
from jovra_studio_media import barcode as bc
from jovra_studio_media.badge import AngleBadge
from jovra_studio_media.model import StudioClip
from jovra_studio_media.sets.angles import CAMERAS as ANGLE_CAMERAS

from . import scene, truth
from .rig import BARCODE_RECT, GRID, HEIGHT, SHAKE_PATTERN, SHAKE_SETTLED, US, WIDTH, CameraSpec, half_up

COVERED = c3.FENCE        # a lens against the bag: a flat dark teal field (luma about 87, clear of every boundary)
_LO = bytes(((v << 2) & 0xFF) for v in range(256))
_HI = bytes((v >> 6) for v in range(256))


class TimedScene(Scene):
    """T11's Scene, painted at an arbitrary scene time from one of its cameras (``Scene.paint`` takes n / fps)."""

    def paint_at(self, t: float, index: int) -> Canvas:
        cam = self.cameras[index][1]
        base = self.base(index)
        canvas = base.copy()
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
            else:
                c3.draw_player(canvas, cam, value, track.kit)
        stamp(canvas, base, self.label)
        return canvas


def _ten_bit(plane: bytearray) -> array:
    """An 8-bit plane as 10-bit code values (v << 2), without a Python loop over pixels."""
    pairs = bytearray(2 * len(plane))
    pairs[0::2] = plane.translate(_LO)
    pairs[1::2] = plane.translate(_HI)
    out = array("H")
    out.frombytes(bytes(pairs))
    if sys.byteorder != "little":
        out.byteswap()
    return out


def to_ten_bit(canvas: Canvas) -> Canvas:
    out = Canvas.__new__(Canvas)
    out.width, out.height, out.bit_depth, out.shift = canvas.width, canvas.height, 10, 2
    out.y, out.cb, out.cr = _ten_bit(canvas.y), _ten_bit(canvas.cb), _ten_bit(canvas.cr)
    return out


def nudges(cam: CameraSpec) -> list[tuple[int, int]]:
    """Every distinct (yaw, pitch) the camera is drawn from, the unshaken pose first."""
    out = [(0, 0)]
    if cam.shake is not None:
        for n in (*SHAKE_PATTERN, SHAKE_SETTLED):
            if n not in out:
                out.append(n)
    return out


class Painter:
    """Draws file frame ``n`` of segment ``k``; records the match time it drew each frame at (``painted``)."""

    def __init__(self, cam: CameraSpec, k: int, coded: bool):
        self.cam, self.k, self.coded = cam, k, coded
        self.painted: list[int] = []
        cell_h = HEIGHT // GRID[1]
        self.badge = AngleBadge(WIDTH, HEIGHT, cell_h, cam.placement.name)
        self.poses = nudges(cam)
        if cam.view == "court":
            p, ends = scene.play()
            _, _, eye, target, focal = next(c for c in ANGLE_CAMERAS if c[0] == cam.placement.picture)
            base = c3.Camera.looking(eye, target, focal * WIDTH, WIDTH, HEIGHT)
            moves = [(i, base.nudged(*pose)) for i, pose in enumerate(self.poses) if i]
            self.scene = TimedScene(WIDTH, HEIGHT, cam.fps, base, GRID, [p.tracks[e] for e in ends], p.ball,
                                    camera_moves=moves)
            self.covered = None
        else:
            self.scene = None
            self.covered = Canvas(WIDTH, HEIGHT, fill=COVERED)
            Label(WIDTH, HEIGHT, cell_h).draw(self.covered)

    def __call__(self, n: int) -> Canvas:
        if n != len(self.painted):
            raise RuntimeError(f"{self.cam.id}: frame {n} painted out of order")
        t = self.cam.frame_match_us(self.k, n)
        self.painted.append(half_up(t))
        if self.scene is not None:
            canvas = self.scene.paint_at(float(t / US), self.poses.index(self.cam.nudge(self.k, n)))
        else:
            canvas = self.covered.copy()
        self.badge.draw(canvas)
        if self.coded:
            bc.draw(canvas, bc.Payload(self.cam.source_id, self.k, n), BARCODE_RECT)
        return to_ten_bit(canvas) if self.cam.hdr else canvas


def encode_options(cam: CameraSpec) -> EncodeOptions:
    return EncodeOptions(crf=28, preset="fast", keyint=2 * cam.fps.num // cam.fps.den)


def clip(cam: CameraSpec, k: int, variant: str, clicks: list[int], description: str) -> tuple[StudioClip, Painter]:
    coded = variant == "coded"
    painter = Painter(cam, k, coded)
    core = ClipSpec(id=f"{cam.id}-s{k}-{variant}", file=truth.file_name(cam.id, k, variant), description=description,
                    codec="hevc" if cam.hdr else "h264", width=WIDTH, height=HEIGHT, rate=cam.fps,
                    frame_count=cam.segments[k].frames, paint=painter, grid=GRID, bit_depth=10 if cam.hdr else 8,
                    rotation=cam.rotation, hdr=cam.hdr, seed=cam.source_id, frame_code=False,
                    encode=encode_options(cam), vfr_timescale=cam.vfr_timescale, vfr_cycle=cam.vfr_cycle)
    studio = StudioClip(core=core, role="angle", source_id=cam.source_id if coded else None, segment=k,
                        first_frame_id=0, barcode_rect=BARCODE_RECT if coded else None, audio=True,
                        clicks=tuple(clicks), audio_seed=truth.audio_seed(cam, k), labels=tuple(truth.labels(cam)))
    return studio, painter
