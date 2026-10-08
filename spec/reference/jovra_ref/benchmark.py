"""Reference scoring for benchmark records (the Swift harness in JovraBenchmark must agree exactly).

Task ``eventTimes`` 1.0.0: an estimator returns event times per clip; they are matched to the clip's
ground-truth events and pooled over all clips.

Matching, per clip: predictions sorted ascending (ties keep their order). For each truth event in time order,
take the unmatched prediction with the smallest |p - t| <= tolerance; on equal distance the earlier one.
That pair is consumed. All arithmetic is exact (rationals).

Metrics, pooled: ``precision`` = matched / predictions, ``recall`` = matched / truth events (both undefined
when the denominator is 0), ``onset MAE`` = mean |p - t| over matched pairs in milliseconds (undefined with no
match). Values are shown rounded half-up to 4 places (ratios) or 3 places (ms); verdicts compare the exact
values. An undefined metric fails any floor.
"""

from __future__ import annotations

import bisect
import hashlib
from decimal import Decimal
from fractions import Fraction

TASK_EVENT_TIMES = "eventTimes"


def rt(obj: dict) -> Fraction:
    return Fraction(obj["value"], obj["timescale"])


def truth_events_sha256(truth: dict) -> str:
    text = "".join(f"{e['time']['value']}/{e['time']['timescale']}\n" for e in truth.get("events", []))
    return hashlib.sha256(text.encode("ascii")).hexdigest()


def match(truth_times: list[Fraction], predictions: list[Fraction], tolerance: Fraction) -> list[Fraction]:
    """Return |p - t| for every matched pair."""
    preds = sorted(predictions)
    used = [False] * len(preds)
    deltas = []
    for t in truth_times:
        lo = bisect.bisect_left(preds, t - tolerance)
        hi = bisect.bisect_right(preds, t + tolerance)
        best, best_d = None, None
        for j in range(lo, hi):
            if used[j]:
                continue
            d = abs(preds[j] - t)
            if best is None or d < best_d:
                best, best_d = j, d
        if best is not None:
            used[best] = True
            deltas.append(best_d)
    return deltas


def _fraction(value: Fraction | None):
    return None if value is None else {"n": value.numerator, "d": value.denominator}


def half_up(value: Fraction, places: int) -> str:
    scale = 10 ** places
    q = (value.numerator * scale * 2 + value.denominator) // (2 * value.denominator)
    whole, frac = divmod(q, scale)
    return f"{whole}.{frac:0{places}d}"


def score_event_times(record: dict, truths: dict[str, dict]) -> list[dict]:
    tolerance = rt(record["task"]["tolerance"])
    matched = predicted = expected = 0
    total = Fraction(0)
    for clip in record["clips"]:
        truth = truths[clip["truthId"]]
        times = [rt(e["time"]) for e in truth.get("events", [])]
        preds = [rt(o) for o in clip["outputs"]]
        deltas = match(times, preds, tolerance)
        matched += len(deltas)
        predicted += len(preds)
        expected += len(times)
        total += sum(deltas, Fraction(0))
    precision = Fraction(matched, predicted) if predicted else None
    recall = Fraction(matched, expected) if expected else None
    mae = total * 1000 / matched if matched else None
    return [
        {"name": "precision", "exact": _fraction(precision), "value": None if precision is None else half_up(precision, 4)},
        {"name": "recall", "exact": _fraction(recall), "value": None if recall is None else half_up(recall, 4)},
        {"name": "onset MAE", "unit": "ms", "exact": _fraction(mae), "value": None if mae is None else half_up(mae, 3)},
    ]


SCORERS = {TASK_EVENT_TIMES: score_event_times}


def verdict(metrics: list[dict], floor: dict) -> dict:
    by_name = {m["name"]: m for m in metrics}
    checks = []
    for f in floor["metrics"]:
        m = by_name.get(f["name"])
        exact = None if m is None or m["exact"] is None else Fraction(m["exact"]["n"], m["exact"]["d"])
        threshold = Fraction(Decimal(f["threshold"]))
        ok = exact is not None and (exact >= threshold if f["comparator"] == ">=" else exact <= threshold)
        check = {"name": f["name"], "comparator": f["comparator"], "threshold": f["threshold"],
                 "value": None if m is None else m["value"], "passed": ok}
        if "unit" in f:
            check["unit"] = f["unit"]
        checks.append(check)
    return {"passed": all(c["passed"] for c in checks), "checks": checks}
