"""Render-proxy normalization: the PTS table from original presentation timestamps to proxy frames.

Standard library only, exact arithmetic. Module page: spec/studio/modules/normalization.md.

The one rule (multicam-sync research 5.2, observed against FFmpeg with embedded frame IDs):
  - every original frame i gets the proxy tick  tick_i = floor((pts_i - pts_0) * fps / timescale + 1/2)  (half-up);
  - proxy frame k (0 <= k < N) shows the last original frame whose tick is <= k;
  - N = floor((endPts - pts_0) * fps / timescale + 1/2), with the same half-up rounding.
The proxy starts at zero (proxy frame 0 shows original frame 0), runs at a constant rate on the track timescale
lcm(fps.num, 1000), bakes the rotation in exactly once and is SDR; an HDR original declares its tone-map method.

`tie` exists only so the conformance vectors can build the mutations that must fail (multicam-sync 8.3, S4): a
normalizer that rounds ties to even or down selects other frames, and check_conformance catches it.
"""

from __future__ import annotations

from fractions import Fraction
from math import lcm

from .core import Reject, canonical_sha256, require, round_half_up

SCHEMA_VERSION = "jovra.pts-table/1"
TIE_RULES = ("half-up", "half-even", "half-down")


# ----- rounding -----------------------------------------------------------------------------------

def _round(value: Fraction, tie: str) -> int:
    if tie == "half-up":
        return round_half_up(value)
    floor = value.__floor__()
    if value - floor != Fraction(1, 2):
        return round_half_up(value)
    if tie == "half-down":
        return floor
    if tie == "half-even":
        return floor if floor % 2 == 0 else floor + 1
    raise ValueError(f"unknown tie rule {tie!r}")


def is_tie(value: Fraction) -> bool:
    return Fraction(value) - Fraction(value).__floor__() == Fraction(1, 2)


# ----- run-length encodings (canonical greedy form) -----------------------------------------------

def _greedy(values: list[int]) -> list[tuple[int, int, int, int]]:
    """(start index, first value, step, count): a run takes the difference of its first two values as its step and
    extends while the difference holds; a final single value has step 0."""
    runs, i, n = [], 0, len(values)
    while i < n:
        if i + 1 == n:
            runs.append((i, values[i], 0, 1))
            break
        step = values[i + 1] - values[i]
        j = i + 1
        while j + 1 < n and values[j + 1] - values[j] == step:
            j += 1
        runs.append((i, values[i], step, j - i + 1))
        i = j + 1
    return runs


def compress_pts(pts: list[int]) -> list[dict]:
    return [{"value": v, "step": s, "count": c} for _, v, s, c in _greedy(list(pts))]


def expand_pts(runs: list[dict]) -> list[int]:
    out = []
    for r in runs:
        out += [r["value"] + j * r["step"] for j in range(r["count"])]
    return out


def expand_runs(runs: list[dict]) -> list[int]:
    """Proxy frame -> original frame, one entry per proxy frame (what an embedded-ID decode of the proxy reads)."""
    out = []
    for r in runs:
        out += [r["originalFrame"] + j * r["originalStep"] for j in range(r["count"])]
    return out


def slot_runs(slots: list[int], pts: list[int]) -> list[dict]:
    return [{"proxyFrame": k, "count": c, "originalFrame": f, "originalStep": s, "originalPts": pts[f]}
            for k, f, s, c in _greedy(slots)]


# ----- the original index -------------------------------------------------------------------------

def original_pts(original: dict) -> list[int]:
    """The decoded PTS index, checked: canonical runs, strictly increasing, counted, and ended after the last frame."""
    runs = original["pts"]
    require(compress_pts(expand_pts(runs)) == runs, "badPtsIndex", "the PTS index is not in canonical run form")
    pts = expand_pts(runs)
    require(all(b > a for a, b in zip(pts, pts[1:])), "badPtsIndex",
            "presentation timestamps must strictly increase in presentation order")
    require(len(pts) == original["frameCount"], "badPtsIndex",
            f"the index holds {len(pts)} frames, frameCount says {original['frameCount']}")
    require(original["endPts"] > pts[-1], "badPtsIndex", "endPts must come after the last frame's PTS")
    return pts


def ticks(original: dict, fps: dict, tie: str = "half-up") -> list[int]:
    """The proxy frame of every original frame: half-up of its zero-based time times the proxy rate."""
    pts = original_pts(original)
    scale = Fraction(fps["num"], fps["den"] * original["timescale"])
    return [_round((p - pts[0]) * scale, tie) for p in pts]


def proxy_frame_count(original: dict, fps: dict) -> int:
    pts = original_pts(original)
    return round_half_up((original["endPts"] - pts[0]) * Fraction(fps["num"], fps["den"] * original["timescale"]))


def select_frames(original: dict, fps: dict, tie: str = "half-up") -> list[int]:
    """Proxy frame k shows the last original frame whose tick is <= k (ticks never decrease)."""
    t = ticks(original, fps, tie)
    n = proxy_frame_count(original, fps)
    require(n >= 1, "badPtsIndex", "the original is shorter than half a proxy frame")
    slots, i = [], 0
    for k in range(n):
        while i + 1 < len(t) and t[i + 1] <= k:
            i += 1
        slots.append(i)
    return slots


# ----- geometry, colour and the proxy clock --------------------------------------------------------

def track_timescale(fps: dict) -> int:
    return lcm(fps["num"], 1000)


def frame_duration_ticks(fps: dict) -> int:
    return track_timescale(fps) * fps["den"] // fps["num"]


def display_size(original: dict) -> tuple[int, int]:
    w, h = original["width"], original["height"]
    return (h, w) if original["rotationDegrees"] in (90, 270) else (w, h)


def proxy_size(original: dict, long_edge: int) -> tuple[int, int]:
    """The display size (rotation applied once) scaled so its long edge is `long_edge`; the short edge is rounded
    half-up to an even number (4:2:0 chroma)."""
    require(long_edge % 2 == 0, "badDimensions", "the proxy long edge must be even")
    dw, dh = display_size(original)
    short = 2 * round_half_up(Fraction(min(dw, dh) * long_edge, 2 * max(dw, dh)))
    return (long_edge, short) if dw >= dh else (short, long_edge)


def _check_colour(original: dict, tone_map) -> None:
    if original["hdr"]:
        require(original["transfer"] in ("hlg", "pq"), "colourMismatch", "HDR originals declare an HLG or PQ transfer")
        require(tone_map is not None, "toneMapUndeclared",
                "an HDR original is tone-mapped to SDR with a declared method, parameters and version")
    else:
        require(tone_map is None, "toneMapOnSdr", "an SDR original is not tone-mapped")


# ----- derive and check ---------------------------------------------------------------------------

def derive_table(inp: dict, tie: str = "half-up") -> dict:
    """The PTS table a conforming normalizer emits for a source description:
    {sourceId, normalizerVersion, original, proxy: {fps, targetLongEdge, toneMap}}."""
    original, spec = inp["original"], inp["proxy"]
    fps = spec["fps"]
    _check_colour(original, spec["toneMap"])
    pts = original_pts(original)
    slots = select_frames(original, fps, tie)
    width, height = proxy_size(original, spec["targetLongEdge"])
    return {
        "schemaVersion": SCHEMA_VERSION,
        "sample": True,
        "sourceId": inp["sourceId"],
        "normalizerVersion": inp["normalizerVersion"],
        "original": original,
        "proxy": {"fps": fps, "timescale": track_timescale(fps), "frameDurationTicks": frame_duration_ticks(fps),
                  "startPts": 0, "frameCount": len(slots), "width": width, "height": height,
                  "rotationAppliedDegrees": original["rotationDegrees"], "displayRotationDegrees": 0,
                  "transfer": "bt709", "bitDepth": 8, "toneMap": spec["toneMap"],
                  "upconverted": Fraction(fps["num"], fps["den"]) > Fraction(original["nominalFps"]["num"],
                                                                             original["nominalFps"]["den"])},
        "runs": slot_runs(slots, pts),
    }


def check_pts_table(doc: dict) -> dict:
    """The record rule: rebuild everything derivable from the original index and require the stored values.
    Raises Reject with a stable code."""
    original, proxy = doc["original"], doc["proxy"]
    fps = proxy["fps"]
    pts = original_pts(original)
    require(proxy["timescale"] == track_timescale(fps), "badTimescale",
            f"the track timescale is lcm({fps['num']}, 1000) = {track_timescale(fps)}, not {proxy['timescale']}")
    require(proxy["frameDurationTicks"] == frame_duration_ticks(fps), "badTimescale",
            "frameDurationTicks is timescale * den / num")
    require(proxy["rotationAppliedDegrees"] == original["rotationDegrees"], "proxyRotation",
            "a render proxy bakes the original's rotation in exactly once")
    dw, dh = display_size(original)
    if dw != dh:
        require((proxy["width"] > proxy["height"]) == (dw > dh), "proxyRotation",
                "the proxy has the display orientation (a quarter turn swaps width and height)")
    require((proxy["width"], proxy["height"]) == proxy_size(original, max(proxy["width"], proxy["height"])),
            "badDimensions", "the proxy keeps the display aspect with an even short edge")
    _check_colour(original, proxy["toneMap"])
    upconverted = Fraction(fps["num"], fps["den"]) > Fraction(original["nominalFps"]["num"], original["nominalFps"]["den"])
    require(proxy["upconverted"] == upconverted, "unlabelledUpconversion",
            "upconverted is true exactly when the proxy rate is above the original's nominal rate")
    slots = select_frames(original, fps)
    require(proxy["frameCount"] == len(slots), "ptsTableMismatch",
            f"the proxy has {len(slots)} frames by the half-up rule, not {proxy['frameCount']}")
    require(doc["runs"] == slot_runs(slots, pts), "ptsTableMismatch",
            "the runs differ from the half-up selection of the original index (or are not in canonical form)")
    return {"frameCount": len(slots), "sha256": table_sha256(doc)}


def check_conformance(original: dict, fps: dict, emitted: dict, decoded_ids: list[int]) -> None:
    """The embedded-ID conformance check (multicam-sync 8.2): a normalizer's emitted table must match the frame IDs
    decoded from its proxy 100%, and those IDs must be the half-up selection."""
    emitted_ids = expand_runs(emitted["runs"])
    for k, (said, seen) in enumerate(zip(emitted_ids, decoded_ids)):
        require(said == seen, "ptsTableMismatch",
                f"proxy frame {k}: the emitted table says original {said}, the decoded frame ID is {seen}")
    require(len(emitted_ids) == len(decoded_ids), "ptsTableMismatch",
            f"the emitted table covers {len(emitted_ids)} proxy frames, the proxy decodes {len(decoded_ids)}")
    expected = select_frames(original, fps)
    for k, (want, seen) in enumerate(zip(expected, decoded_ids)):
        if want != seen:
            raise FrameSelectionMismatch(k, want, seen)
    require(len(expected) == len(decoded_ids), "frameSelectionMismatch",
            f"the proxy has {len(decoded_ids)} frames, the half-up rule gives {len(expected)}")


class FrameSelectionMismatch(Reject):
    def __init__(self, slot: int, expected: int, found: int):
        super().__init__("frameSelectionMismatch",
                         f"proxy frame {slot} shows original {found}; the half-up rule selects {expected}")
        self.slot, self.expected, self.found = slot, expected, found


def original_to_proxy(table: dict) -> list[int]:
    """The proxy frame of every original frame, in presentation order (its half-up tick). A value at or beyond the
    proxy frame count lies outside the proxy."""
    return ticks(table["original"], table["proxy"]["fps"])


def proxy_frame_of(table: dict, pts_value: int) -> int | None:
    """Analysis and sync use original PTS; this is where an original PTS lands in the proxy (None: outside it)."""
    original, fps = table["original"], table["proxy"]["fps"]
    first = expand_pts(original["pts"][:1])[0]
    require(pts_value >= first, "badPtsIndex", "a PTS before the original's first frame")
    k = round_half_up((pts_value - first) * Fraction(fps["num"], fps["den"] * original["timescale"]))
    return k if k < table["proxy"]["frameCount"] else None


def table_sha256(table: dict) -> str:
    """What a SourceManifest render proxy binds as ptsTableSha256."""
    return canonical_sha256(table)
