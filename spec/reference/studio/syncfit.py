"""Reference sync-map fitter: source clock -> match clock, per device, from paired anchors.

Model (docs/research/studio/multicam-sync.md section 4): t_match = offset_k + rate * t_src for segment k of one
device. All segments of a device share one rate (one oscillator); each segment has its own offset, so the map is
piecewise across restarts and gaps and never extends into them.

Audio anchors are corrected for sound travel from the event position to each phone before fitting:
x = t_src - d_src / c and y = t_ref - d_ref / c, so the map aligns light time, not arrival time.

Everything is exact: anchors are integer microseconds, the fit uses Fractions, the rate is rounded half-up to one part
per billion, offsets and residuals to whole microseconds, and distances / RMS use integer square roots. Swift, Kotlin
and Python therefore produce identical numbers.

Fit method "robust-trimmed-ols/1":
1. a robust start: the pooled within-piece Theil-Sen slope (the exact median of every pairwise slope inside a piece)
   and a per-piece median intercept, so one gross outlier cannot drag the line onto itself;
2. one trim of anchors whose residual from that robust line exceeds three output frames;
3. a final exact OLS on the inliers (pooled slope, per-piece intercepts).
A piece is fitted only when it keeps at least two inlier anchors; otherwise it is "failed" with no transform and no
statistics (a fit never reports zero residuals over an empty inlier set). A fitted rate outside 0.9-1.1 (the schema
range) fails the device. Inside that range, a drift above 1000 ppm is physically implausible for phone clocks (about
8 ppm measured; 300 ppm is the stress fixture, multicam-sync.md section 4.6), so it adds a needs-review reason. A
person may mark a piece reviewed only with at least three inlier anchors (with two, an outlier cannot be detected)
and a plausible drift. Every anchor must lie inside its piece (0 <= sourceTimeUs < sourceDurationUs): an anchor from
another restart segment or a mis-assigned file is rejected (badAnchor), never used as a high-leverage inlier.
(The first method id, "trimmed-ols/1", started from plain OLS and is retired: one +2 s outlier among 12 clean anchors
could trim every anchor and still leave a reviewable map.)
"""

from __future__ import annotations

from fractions import Fraction
from math import isqrt

from .core import Reject, US_PER_S, frame_duration_us, require, round_half_up, sqrt_half_up

METHOD = "robust-trimmed-ols/1"
RATE_DEN = 1_000_000_000
DEFAULT_SPEED_MM_PER_S = 343_000         # 343 m/s at about 20 degrees C
MIN_INLIERS_FOR_ESTIMATED = 8
MIN_INLIERS_FOR_FIT = 2                  # below this a piece has no transform at all
RATE_MIN, RATE_MAX = 900_000_000, 1_100_000_000   # the schema's rate range, in ppb units
OUTLIER_FRAMES = 3                       # residuals beyond three output frames are trimmed
MAX_PLAUSIBLE_DRIFT_PPB = 1_000_000      # 1000 ppm; real phones drift about 8 ppm, the stress fixture is 300 ppm
MIN_INLIERS_FOR_REVIEW = 3               # with two anchors an outlier is indistinguishable from the line


def speed_of_sound_mm_per_s(temperature_c: str | None) -> int:
    """c(T) = 331.3 m/s * sqrt(1 + T / 273.15), rounded half-up to whole mm/s. None gives the 343 m/s default."""
    if temperature_c is None:
        return DEFAULT_SPEED_MM_PER_S
    t = Fraction(temperature_c)
    require(Fraction(-30) <= t <= Fraction(50), "badTemperature", "temperature outside -30..50 C")
    c_squared = Fraction(331_300) ** 2 * (Fraction(27315, 100) + t) / Fraction(27315, 100)
    return sqrt_half_up(c_squared)


def distance_squared_mm2(a: dict, b: dict) -> int:
    return (a["xMm"] - b["xMm"]) ** 2 + (a["yMm"] - b["yMm"]) ** 2 + (a["zMm"] - b["zMm"]) ** 2


def sound_delay_us(event: dict, mic: dict, c_mm_per_s: int) -> int:
    """Sound travel time from event to microphone, half-up to whole microseconds, without floating point:
    delay = sqrt(S) * 1e6 / c; floor(delay + 1/2) = (isqrt(4 * P^2 * S) + Q) // (2Q) with P/Q = 1e6 / c."""
    s = distance_squared_mm2(event, mic)
    ratio = Fraction(US_PER_S, c_mm_per_s)
    p, q = ratio.numerator, ratio.denominator
    return (isqrt(4 * p * p * s) + q) // (2 * q)


def _ols(points_by_piece: dict) -> Fraction | None:
    """Pooled within-piece slope: sum (x - xbar_k)(y - ybar_k) / sum (x - xbar_k)^2."""
    sxy = Fraction(0)
    sxx = Fraction(0)
    for pts in points_by_piece.values():
        if len(pts) < 2:
            continue
        xbar = Fraction(sum(x for x, _ in pts), len(pts))
        ybar = Fraction(sum(y for _, y in pts), len(pts))
        sxy += sum((x - xbar) * (y - ybar) for x, y in pts)
        sxx += sum((x - xbar) ** 2 for x, _ in pts)
    if sxx == 0:
        return None
    return sxy / sxx


def _intercepts(points_by_piece: dict, rate: Fraction) -> dict:
    out = {}
    for key, pts in points_by_piece.items():
        if pts:
            out[key] = round_half_up(Fraction(sum(y - rate * x for x, y in pts), len(pts)))
    return out


def _median(values: list) -> Fraction:
    """Exact median; for an even count, the mean of the two middle values."""
    ordered = sorted(values)
    n = len(ordered)
    mid = n // 2
    return Fraction(ordered[mid]) if n % 2 else (Fraction(ordered[mid - 1]) + Fraction(ordered[mid])) / 2


def _robust_start(points_by_piece: dict):
    """Pooled within-piece Theil-Sen slope and per-piece median intercepts, exactly. None when no piece has two
    anchors at different source times."""
    slopes = []
    for pts in points_by_piece.values():
        for i in range(len(pts)):
            for j in range(i + 1, len(pts)):
                (x0, y0), (x1, y1) = pts[i], pts[j]
                if x1 != x0:
                    slopes.append(Fraction(y1 - y0, x1 - x0))
    if not slopes:
        return None, {}
    slope = _median(slopes)
    return slope, {k: _median([y - slope * x for x, y in pts]) for k, pts in points_by_piece.items() if pts}


def fit_device(pieces: list, *, source_position: dict | None, reference_position: dict | None,
               c_mm_per_s: int, output_fps: dict, hints: dict | None = None) -> list:
    """Fit one non-reference device.

    pieces: [{"segmentId", "sourceDurationUs", "anchors": [{"id", "kind", "modality", "sourceTimeUs",
             "referenceTimeUs", "eventPositionMm" | None}]}]
    hints:  optional {segmentId: offsetUs} capture hints, used only when a piece has no anchors.
    Returns one fitted piece per input piece (same order) with transform, fit statistics, per-anchor delays,
    residuals and inlier flags, and the review state the rules allow (never "reviewed": only a person does that).
    """
    half_frame = frame_duration_us(output_fps) / 2
    outlier_us = 2 * half_frame * OUTLIER_FRAMES
    prepared = {}
    for piece in pieces:
        duration = piece["sourceDurationUs"]
        require(type(duration) is int and duration > 0, "badCoverage", "sourceDurationUs must be positive")
        rows = []
        for a in piece["anchors"]:
            require(a["modality"] in ("visual", "audio", "manual"), "badEnum", "anchor modality")
            require(type(a["sourceTimeUs"]) is int and 0 <= a["sourceTimeUs"] < duration, "badAnchor",
                    f"anchor {a['id']} lies outside its piece {piece['segmentId']} (0 <= sourceTimeUs < "
                    f"{duration}); an anchor from another segment is never fitted")
            require(type(a["referenceTimeUs"]) is int and a["referenceTimeUs"] >= 0, "badAnchor",
                    f"anchor {a['id']}: referenceTimeUs must be a non-negative integer")
            src_delay = ref_delay = 0
            corrected = True
            if a["modality"] == "audio":
                if a.get("eventPositionMm") and source_position and reference_position:
                    src_delay = sound_delay_us(a["eventPositionMm"], source_position, c_mm_per_s)
                    ref_delay = sound_delay_us(a["eventPositionMm"], reference_position, c_mm_per_s)
                else:
                    corrected = False
            rows.append({"anchor": a, "x": a["sourceTimeUs"] - src_delay, "y": a["referenceTimeUs"] - ref_delay,
                         "sourceDelayUs": src_delay, "referenceDelayUs": ref_delay, "corrected": corrected,
                         "inlier": True})
        prepared[piece["segmentId"]] = rows

    def points(inliers_only: bool) -> dict:
        return {k: [(r["x"], r["y"]) for r in rows if r["inlier"] or not inliers_only] for k, rows in prepared.items()}

    rate_num = None
    offsets = {}
    failure = "too few anchors to fit"
    slope, starts = _robust_start(points(False))
    if slope is not None:
        # one trim against the robust line, then the final OLS on the inliers
        for key, rows in prepared.items():
            for r in rows:
                r["inlier"] = key in starts and abs(r["y"] - starts[key] - slope * r["x"]) <= outlier_us
        usable = {k: pts for k, pts in points(True).items() if len(pts) >= MIN_INLIERS_FOR_FIT}
        final = _ols(usable)
        if final is None:
            failure = f"fewer than {MIN_INLIERS_FOR_FIT} inlier anchors after trimming outliers"
        else:
            rate_num = round_half_up(final * RATE_DEN)
            if RATE_MIN <= rate_num <= RATE_MAX:
                offsets = _intercepts(usable, Fraction(rate_num, RATE_DEN))
            else:
                failure = "fitted rate outside 0.9-1.1; the anchors are inconsistent"
                rate_num = None
    results = []
    for piece in pieces:
        key = piece["segmentId"]
        rows = prepared[key]
        offset = offsets.get(key)
        reason = failure
        if rate_num is not None and offset is None:
            reason = f"fewer than {MIN_INLIERS_FOR_FIT} inlier anchors in this piece"
        if offset is None:
            for r in rows:
                r["inlier"] = False
        results.append(_piece_result(piece, rows, rate_num, offset, half_frame, hints or {}, reason))
    return results


def _piece_result(piece, rows, rate_num, offset, half_frame, hints, failure) -> dict:
    duration = piece["sourceDurationUs"]
    anchors_out = []
    inlier_res = []
    for r in rows:
        residual = None
        if offset is not None and rate_num is not None:
            residual = round_half_up(r["y"] - offset - Fraction(rate_num, RATE_DEN) * r["x"])
            if r["inlier"]:
                inlier_res.append(residual)
        anchors_out.append({"id": r["anchor"]["id"], "sourceDelayUs": r["sourceDelayUs"],
                            "referenceDelayUs": r["referenceDelayUs"], "corrected": r["corrected"],
                            "residualUs": residual, "inlier": r["inlier"] if residual is not None else False})
    thirds = [False, False, False]
    for r in rows:
        if r["inlier"] and 0 <= r["anchor"]["sourceTimeUs"] < duration:
            thirds[min(2, r["anchor"]["sourceTimeUs"] * 3 // duration)] = True
    n_in = len(inlier_res)
    n_out = sum(1 for a in anchors_out if a["residualUs"] is not None and not a["inlier"])
    reasons = []
    if offset is None or rate_num is None:
        if not rows and piece["segmentId"] in hints:
            state = "from-hints"
            transform = {"offsetUs": hints[piece["segmentId"]], "rate": {"num": RATE_DEN, "den": RATE_DEN}}
            reasons.append("no anchors; capture hint only")
        else:
            state = "failed"
            transform = None
            reasons.append(failure)
        return {"segmentId": piece["segmentId"], "transform": transform, "fit": None, "anchors": anchors_out,
                "state": state, "reasons": reasons}
    res_max = max((abs(r) for r in inlier_res), default=0)
    rms = sqrt_half_up(Fraction(sum(r * r for r in inlier_res), n_in)) if n_in else 0
    uncorrected = any(not r["corrected"] and r["inlier"] for r in rows)
    manual_only = all(r["anchor"]["modality"] == "manual" for r in rows)
    if uncorrected:
        reasons.append("audio anchors without sound-travel correction")
    if n_in < MIN_INLIERS_FOR_ESTIMATED:
        reasons.append(f"fewer than {MIN_INLIERS_FOR_ESTIMATED} inlier anchors")
    if not all(thirds):
        reasons.append("anchors do not cover the first, middle and last thirds")
    if res_max > half_frame:
        reasons.append("an inlier residual exceeds half an output frame")
    if n_out:
        reasons.append("outlier anchors were trimmed")
    if abs(rate_num - RATE_DEN) > MAX_PLAUSIBLE_DRIFT_PPB:
        reasons.append("drift above 1000 ppm is implausible for phone clocks")
    if manual_only:
        state = "manual"
    elif reasons:
        state = "needs-review"
    else:
        state = "estimated"
    return {
        "segmentId": piece["segmentId"],
        "transform": {"offsetUs": offset, "rate": {"num": rate_num, "den": RATE_DEN}},
        "fit": {"method": METHOD, "nInliers": n_in, "nOutliers": n_out, "residualRmsUs": rms,
                "residualMaxUs": res_max, "driftPpb": rate_num - RATE_DEN, "thirdsCovered": thirds,
                "uncorrectedAudio": uncorrected},
        "anchors": anchors_out,
        "state": state,
        "reasons": reasons,
    }


def map_us(transform: dict, source_us: int) -> int:
    """Match-clock time of a source time under a fitted transform, half-up to whole microseconds."""
    return round_half_up(transform["offsetUs"] + Fraction(transform["rate"]["num"], transform["rate"]["den"]) * source_us)


def drift_ms_per_min(transform: dict) -> Fraction:
    """Drift expressed as the UI shows it: milliseconds gained per minute of source time."""
    return (Fraction(transform["rate"]["num"], transform["rate"]["den"]) - 1) * 60_000


def check_review_state(stored_state: str, fitted_state: str, checkpoints: list, fit: dict | None = None) -> None:
    """A stored state is acceptable when it equals the fitted one, or is 'reviewed' after a person confirmed the
    start, middle and end checkpoints of a fit that did not fail, keeps at least three inlier anchors and has a
    plausible drift."""
    if stored_state == fitted_state:
        return
    if stored_state == "reviewed":
        require(fitted_state in ("estimated", "needs-review", "manual"), "reviewOfFailedFit",
                "a failed or hint-only map cannot be marked reviewed")
        require(fit is not None and fit["nInliers"] >= MIN_INLIERS_FOR_REVIEW, "reviewOfWeakFit",
                f"a map with fewer than {MIN_INLIERS_FOR_REVIEW} inlier anchors cannot be marked reviewed "
                "(an outlier cannot be detected)")
        require(abs(fit["driftPpb"]) <= MAX_PLAUSIBLE_DRIFT_PPB, "reviewOfWeakFit",
                "a map with a drift above 1000 ppm cannot be marked reviewed; re-anchor it")
        require({"start", "middle", "end"} <= set(checkpoints), "reviewIncomplete",
                "reviewed needs the start, middle and end checkpoints")
        return
    raise Reject("syncStateMismatch", f"stored state {stored_state!r} but the rules give {fitted_state!r}")
