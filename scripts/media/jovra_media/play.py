"""Tennis play on the perspective court: serves, rallies and side-on forehands, with their ground truth.

A ``Play`` collects ball arcs (animation.BallPath), both players' tracks, the hit onsets (exact 48 kHz
samples, which become the audio clicks and the ``events`` of the ground truth), bounces, serves and rally
boundaries. Every random choice comes from a seeded SplitMix64, so a seed always plays the same tennis.
"""

from __future__ import annotations

from fractions import Fraction
from math import sqrt

from . import court3d as c3
from .animation import Arc, BallPath, SideOnSwing, Track
from .clip import AUDIO_RATE, Event, Rate
from .prng import SplitMix64

CONTACT_Z = 2.75          # serve contact height (m)
STROKE_Z = (0.70, 1.10)   # groundstroke contact heights (m)
MAX_SERVE_TRIES = 64


def uniform(rng: SplitMix64, lo: float, hi: float) -> float:
    """A float in [lo, hi] on a 1/10000 grid (integer draw, so every platform agrees)."""
    return lo + (hi - lo) * rng.between(0, 10000) / 10000


def rational(sample: int) -> dict:
    t = Fraction(sample, AUDIO_RATE)
    return {"value": t.numerator, "timescale": t.denominator}


def mm(v: float) -> int:
    return int(round(v * 1000))


def facing(end: str) -> int:
    return 1 if end == "near" else -1


def baseline_y(end: str, behind: float) -> float:
    return -behind if end == "near" else c3.LENGTH + behind


def other(end: str) -> str:
    return "far" if end == "near" else "near"


def serve_x_sign(end: str, side: str) -> int:
    """Which side of the centre mark (x sign) a server stands on: the deuce court is the server's right."""
    right = 1 if end == "near" else -1
    return right if side == "deuce" else -right


class Play:
    def __init__(self, rate: Rate, seed: int):
        self.rate = rate
        self.rng = SplitMix64(seed)
        self.ball = BallPath()
        self.tracks = {"near": Track("near"), "far": Track("far")}
        self.hits: list[int] = []
        self.bounces: list[dict] = []
        self.serves: list[dict] = []
        self.rallies: list[dict] = []
        self.net_faults = 0

    # ----- helpers -------------------------------------------------------------------------------

    def t(self, sample: int) -> float:
        return sample / AUDIO_RATE

    def frame_of(self, sample: int) -> int:
        return int(Fraction(sample, AUDIO_RATE) * self.rate.fraction)

    def sample_of_frame(self, frame: int) -> int:
        s = Fraction(frame) / self.rate.fraction * AUDIO_RATE
        if s.denominator != 1:
            raise ValueError(f"frame {frame} at {self.rate.ffmpeg()} fps is not on a 48 kHz sample")
        return int(s)

    def _bounce(self, sample: int, p: tuple, cam: c3.Camera | None = None) -> dict:
        b = {"time": rational(sample), "sample": sample, "frame": self.frame_of(sample),
             "courtMm": {"x": mm(p[0]), "y": mm(p[1])},
             "inCourt": abs(p[0]) <= c3.SINGLES + 0.05 and -0.05 <= p[1] <= c3.LENGTH + 0.05}
        self.bounces.append(b)
        return b

    def _hit(self, sample: int, end: str, kind: str) -> None:
        self.hits.append(sample)
        self.tracks[end].hits.append((self.t(sample), kind))

    def _body(self, end: str, contact: tuple) -> tuple[float, float]:
        """Where a right-handed player's feet are when the racket meets the ball at ``contact``."""
        return contact[0] - 0.45 * facing(end), contact[1] - 0.15 * facing(end)

    def _arc(self, t0, p0, t1, p1) -> Arc:
        return self.ball.add(Arc(t0, t1, p0, p1))

    def _clear_arc(self, t0: float, p0: tuple, t1: float, p1: tuple) -> tuple:
        """An arc from p0 to the bounce p1 that clears the net: if the flight is too short for the
        requested landing, the landing moves deeper (and finally the contact higher) until it clears."""
        target = p1
        for step in range(40):
            arc = Arc(t0, t1, p0, target)
            if arc.apex_ok():
                return target, p0
            deeper = 0.25 if target[1] > c3.HALF else -0.25
            if abs(target[1] - c3.HALF) < c3.HALF - 0.3:
                target = (target[0], target[1] + deeper, 0.0)
            else:
                p0 = (p0[0], p0[1], min(2.6, p0[2] + 0.1))
        self.net_faults += 1
        return target, p0

    # ----- serves --------------------------------------------------------------------------------

    def toss(self, contact_sample: int, contact: tuple, lead: float = 0.85) -> None:
        t1 = self.t(contact_sample)
        start = max(0.0, t1 - lead)
        if self.ball.arcs and start < self.ball.arcs[-1].t1:
            start = self.ball.arcs[-1].t1
        if t1 - start > 0.2:
            self._arc(start, (contact[0], contact[1] - 0.15 * (1 if contact[1] < c3.HALF else -1), 1.45), t1, contact)

    def serve(self, contact_sample: int, end: str, side: str, speed_kmh: float, *, fault: bool = False,
              bounce_frame_aligned: bool = False, record: bool = True, next_hit: int | None = None,
              cam: c3.Camera | None = None) -> dict:
        """A serve from ``end`` on the ``side`` court with an average contact-to-bounce speed close to
        ``speed_kmh``. The flight time is a whole number of frames when ``bounce_frame_aligned`` (serve
        clips, whose truth names the bounce frame). Returns the serve's truth."""
        rng = self.rng
        sx = serve_x_sign(end, side)
        contact = (sx * uniform(rng, 0.35, 1.05), baseline_y(end, 0.25), CONTACT_Z)
        far = end == "near"
        sign_box = -sx          # crosscourt
        for _ in range(MAX_SERVE_TRIES):
            bx = sign_box * uniform(rng, 0.35, c3.SINGLES - 0.35)
            depth = uniform(rng, 0.6, c3.SERVICE - 0.25) if not fault else c3.SERVICE + uniform(rng, 0.3, 1.0)
            by = c3.HALF + depth if far else c3.HALF - depth
            bounce = (bx, by, 0.0)
            d = c3.sub(bounce, contact)
            dist = sqrt(c3.dot(d, d))
            t0 = self.t(contact_sample)
            flight = dist / (speed_kmh / 3.6)
            if bounce_frame_aligned:
                frames = max(1, int(round(flight * self.rate.fraction)))
                flight = frames / self.rate.fraction
                b_sample = self.sample_of_frame(self.frame_of(contact_sample) + frames)
            else:
                b_sample = contact_sample + int(round(flight * AUDIO_RATE))
            arc = Arc(t0, self.t(b_sample), contact, bounce)
            if arc.apex_ok():
                break
        else:
            raise ValueError("no serve clears the net")
        self.toss(contact_sample, contact)
        self._arc(arc.t0, contact, arc.t1, bounce)
        self._hit(contact_sample, end, "serve")
        server = self.tracks[end]
        bx_body, by_body = contact[0] - 0.2 * facing(end), contact[1] - 0.1 * facing(end)
        server.key(arc.t0 - 1.2, bx_body, by_body)
        server.key(arc.t0, bx_body, by_body)
        b = self._bounce(b_sample, bounce)
        truth = None
        if record:
            truth = {
                "index": len(self.serves), "end": end, "side": side, "fault": fault,
                "contact": self._moment(contact_sample, contact, cam),
                "bounce": self._moment(b_sample, bounce, cam),
                "flightFrames": self.frame_of(b_sample) - self.frame_of(contact_sample),
                "averageSpeedKmh": f"{arc.chord_speed() * 3.6:.1f}",
                "contactSpeedKmh": f"{arc.speed_at_start() * 3.6:.1f}",
            }
            self.serves.append(truth)
        self._last = (b_sample, bounce, contact)
        return truth or {"bounce": b}

    def _moment(self, sample: int, p: tuple, cam: c3.Camera | None) -> dict:
        m = {"frame": self.frame_of(sample), "time": rational(sample),
             "courtMm": {"x": mm(p[0]), "y": mm(p[1]), "z": mm(p[2])}}
        if cam is not None:
            x, y = cam.px(p)
            m["pixel"] = {"x": x, "y": y}
        return m

    def run_out(self, after: float, duration: float = 0.7) -> None:
        """After the last bounce of a ball, it carries on to the back of the court and is gone."""
        b_sample, bounce, contact = self._last
        t0 = self.t(b_sample)
        direction = 1 if bounce[1] > contact[1] else -1
        end_y = c3.LENGTH + 4.5 if direction > 0 else -4.5
        span = min(duration, max(0.2, after - t0))
        k = (end_y - bounce[1]) / max(0.1, abs(bounce[1] - contact[1])) * direction
        end_x = bounce[0] + (bounce[0] - contact[0]) * min(0.6, abs(k) * 0.3)
        self._arc(t0, bounce, t0 + span, (end_x, bounce[1] + (end_y - bounce[1]) * 0.5, 0.0))

    # ----- rallies -------------------------------------------------------------------------------

    def stroke(self, hit_sample: int, end: str, contact: tuple, next_sample: int, last: bool) -> tuple:
        """A groundstroke from ``contact`` toward the other end; returns the next contact point."""
        rng = self.rng
        t0, t1 = self.t(hit_sample), self.t(next_sample)
        frac = 0.62
        b_sample = hit_sample + int(round((next_sample - hit_sample) * frac))
        far = end == "near"
        bx = uniform(rng, -c3.SINGLES + 0.6, c3.SINGLES - 0.6)
        depth = uniform(rng, 3.0, c3.HALF - 0.8)
        bounce = (bx, c3.HALF + depth if far else c3.HALF - depth, 0.0)
        bounce, contact = self._clear_arc(t0, contact, self.t(b_sample), bounce)
        self._arc(t0, contact, self.t(b_sample), bounce)
        self._hit(hit_sample, end, "stroke")
        self.tracks[end].key(t0, *self._body(end, contact))
        self._bounce(b_sample, bounce)
        self._last = (b_sample, bounce, contact)
        if last:
            return bounce
        nxt = (max(-c3.DOUBLES, min(c3.DOUBLES, bounce[0] + (bounce[0] - contact[0]) * 0.18)),
               baseline_y(other(end), uniform(rng, 0.3, 1.4)), uniform(rng, *STROKE_Z))
        self._arc(self.t(b_sample), bounce, t1, nxt)
        return nxt

    def point(self, number: int, start_ms: int, end_ms: int, server_end: str, side: str, strokes: int,
              second_serve: bool) -> dict:
        """One point of the sample match inside [start_ms, end_ms): the serve (and a fault before it when
        the point was played on a second serve, or two faults for a double fault), then the rally."""
        rng = self.rng
        kinds: list[str] = []
        if strokes == 0:
            kinds = ["fault", "fault"]
        else:
            if second_serve:
                kinds.append("fault")
            kinds += ["serve"] + ["stroke"] * (strokes - 1)
        gaps = []
        for i in range(1, len(kinds)):
            if kinds[i - 1] == "fault":
                gaps.append(2.2)
            elif kinds[i - 1] == "serve":
                gaps.append(uniform(rng, 0.95, 1.10))
            else:
                gaps.append(uniform(rng, 1.10, 1.40))
        lead, tail = 0.9, 0.8
        window = (end_ms - start_ms) / 1000
        room = window - lead - tail
        if gaps and sum(gaps) > room:
            factor = max(0.0, room) / sum(gaps)
            gaps = [g * factor for g in gaps]
            lead = min(lead, max(0.15, (window - sum(gaps)) / 2))
        elif not gaps:
            lead = min(lead, max(0.15, window / 3))
        first = start_ms * 48 + int(round(lead * AUDIO_RATE))
        samples = [first]
        for g in gaps:
            samples.append(samples[-1] + int(round(g * AUDIO_RATE)))
        end_sample = end_ms * 48
        if samples[-1] >= end_sample:
            raise ValueError(f"point {number}: hits do not fit its window")
        hitter = server_end
        receiver = other(server_end)
        # receiver waits diagonally, server walks to the mark
        rx = -serve_x_sign(server_end, side) * 1.9
        self.tracks[receiver].key(self.t(samples[0]) - 1.2, rx, baseline_y(receiver, 0.9))
        self.tracks[receiver].key(self.t(samples[0]), rx, baseline_y(receiver, 0.9))
        contact = None
        speed = uniform(rng, 150, 182)
        for i, kind in enumerate(kinds):
            last = i == len(kinds) - 1
            nxt = samples[i + 1] if not last else min(end_sample - 1, samples[i] + int(1.3 * AUDIO_RATE))
            if kind == "fault":
                self.serve(samples[i], server_end, side, speed, fault=True, record=False)
                self.run_out(self.t(nxt) - 0.05)
                speed = uniform(rng, 125, 150)
                continue
            if kind == "serve":
                self.serve(samples[i], server_end, side, speed, record=False)
                b_sample, bounce, sc = self._last
                if last:
                    self.run_out(self.t(nxt))
                    break
                contact = (max(-c3.DOUBLES, min(c3.DOUBLES, bounce[0] + (bounce[0] - sc[0]) * 0.2)),
                           baseline_y(receiver, uniform(rng, 0.4, 1.2)), uniform(rng, *STROKE_Z))
                self._arc(self.t(b_sample), bounce, self.t(nxt), contact)
                hitter = receiver
                continue
            hit_at = contact
            contact = self.stroke(samples[i], hitter, contact, nxt, last)
            if last:
                self.run_out(self.t(end_sample - 1))
            else:
                mid = self.t(samples[i]) + 0.55 * (self.t(nxt) - self.t(samples[i]))
                self.tracks[hitter].key(mid, 0.3 * hit_at[0], baseline_y(hitter, 0.9))   # recover to the middle
                hitter = other(hitter)
        rally_end = min(end_sample - 1, samples[-1] + int(1.2 * AUDIO_RATE))
        rally = {"pointNumber": number, "start": rational(samples[0]), "end": rational(rally_end),
                 "hits": len(samples)}
        self.rallies.append(rally)
        return rally

    def events(self) -> tuple[Event, ...]:
        return tuple(Event("hit", s) for s in sorted(self.hits))


def side_on_forehands(rate: Rate, first_s: float, every_s: float, count: int, play: Play) -> SideOnSwing:
    """Forehands at a fixed rhythm, seen side-on: a fed ball bounces once and meets the racket at the
    contact frame, then flies back toward the net. The contact click is the hit event."""
    contacts = []
    track = play.tracks["near"]
    track.key(0.0, 0.0, -0.4)
    track.key(1e6, 0.0, -0.4)
    rng = play.rng
    for k in range(count):
        frame = int(round((first_s + every_s * k) * rate.fraction))
        sample = play.sample_of_frame(frame)
        tc = play.t(sample)
        contact = (0.0, 0.30, uniform(rng, 0.95, 1.02))     # where the racket head is at Contact
        feed_from = (0.0, c3.HALF - 1.0, 1.0)
        bounce = (0.0, uniform(rng, 3.2, 4.4), 0.0)
        b_sample = sample - int(round(uniform(rng, 0.38, 0.46) * AUDIO_RATE))
        t_feed = tc - 1.25
        play._arc(t_feed, feed_from, play.t(b_sample), bounce)
        play._bounce(b_sample, bounce)
        play._arc(play.t(b_sample), bounce, tc, contact)
        out = (0.0, c3.HALF + uniform(rng, 3.0, 7.0), 0.0)
        play._arc(tc, contact, tc + 0.85, out)
        play._hit(sample, "near", "stroke")
        contacts.append(tc)
    return SideOnSwing(contacts)
