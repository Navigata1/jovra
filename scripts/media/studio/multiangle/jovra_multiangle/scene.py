"""The scene: the first two minutes of T11's Jon vs Alex sample play (points 1-6 of the core sample match, the
rules-coherent point log the coherent S08 match is built on), with its racket contacts and bounces as events.

Light times are exact: every event sits on a 48 kHz sample of the scene clock (``sceneSample``), and the scene clock
is the match clock (the reference camera records from scene time 0 at rate 1). Positions come straight from the ball
arcs T11 draws (contact = the start of the arc a hit launches; bounce = where an arc lands), converted to the Studio
court frame in whole millimetres. Racket contacts are heard (the 1 kHz click stands in for the impact sound);
bounces are visual events only.
"""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
from functools import lru_cache

from jovra_media import court3d as c3
from jovra_media.clip import Rate
from jovra_media.play import mm
from jovra_media.sets import sample as t11

from .rig import AUDIO_RATE, US, half_up

SCENE_US = 120 * US
INPUTS = (t11.MANIFEST, t11.POINTS)
HALF_MM = mm(c3.HALF)


@dataclass(frozen=True)
class Event:
    id: str
    kind: str              # "serveContact" | "hit" | "bounce"
    scene_sample: int      # light time, 48 kHz samples from the scene start
    position_mm: dict      # Studio court frame
    end: str               # "south" | "north": the half of the court it happens on

    @property
    def light_us(self) -> Fraction:
        return Fraction(self.scene_sample * US, AUDIO_RATE)

    @property
    def audible(self) -> bool:
        return self.kind != "bounce"


def play():
    """T11's sample play and the order of its two player tracks (built fresh: Scene.finish sorts the tracks)."""
    return t11.jon_vs_alex(Rate(30))


def _studio_mm(x: float, y: float, z: float) -> dict:
    return {"xMm": mm(x), "yMm": mm(y) - HALF_MM, "zMm": mm(z)}


@lru_cache(maxsize=1)
def events() -> tuple[Event, ...]:
    p, _ = play()
    launch = {}
    for arc in p.ball.arcs:
        launch.setdefault(arc.t0, arc.p0)
    kinds = {t: kind for track in p.tracks.values() for t, kind in track.hits}
    raw = []
    for sample in p.hits:
        t = sample / AUDIO_RATE
        if sample * US >= SCENE_US * AUDIO_RATE:
            continue
        x, y, z = launch[t]
        raw.append((sample, "serveContact" if kinds[t] == "serve" else "hit", _studio_mm(x, y, z)))
    for b in p.bounces:
        if b["sample"] * US < SCENE_US * AUDIO_RATE:
            raw.append((b["sample"], "bounce", {"xMm": b["courtMm"]["x"], "yMm": b["courtMm"]["y"] - HALF_MM, "zMm": 0}))
    raw.sort(key=lambda e: (e[0], e[1]))
    return tuple(Event(f"ev-{i:03d}", kind, sample, pos, "south" if pos["yMm"] < 0 else "north")
                 for i, (sample, kind, pos) in enumerate(raw, start=1))


def as_dicts() -> list[dict]:
    return [{"id": e.id, "kind": e.kind, "sceneSample": e.scene_sample,
             "lightTimeUs": half_up(e.light_us), "positionMm": e.position_mm, "end": e.end,
             "audible": e.audible} for e in events()]
