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
import re
from decimal import Decimal
from fractions import Fraction

TASK_EVENT_TIMES = "eventTimes"


def rt(obj: dict) -> Fraction:
    """A rational time; a non-positive or non-integer timescale is a ValueError, never a ZeroDivisionError."""
    value, timescale = obj["value"], obj["timescale"]
    if not isinstance(value, int) or not isinstance(timescale, int) or isinstance(timescale, bool) or timescale <= 0:
        raise ValueError(f"rational time {value!r}/{timescale!r} needs integers and a positive timescale")
    return Fraction(value, timescale)


def threshold(text) -> Fraction:
    """A floor threshold: a plain decimal such as "0.95" (no exponent, sign or spaces), else ValueError."""
    if not isinstance(text, str) or re.fullmatch(r"[0-9]+(\.[0-9]+)?", text) is None:
        raise ValueError(f"threshold {text!r} is not a plain decimal")
    return Fraction(Decimal(text))


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

# Each task's version and the (name, unit) of every metric its scorer emits, in order.
TASK_VERSIONS = {TASK_EVENT_TIMES: "1.0.0"}
TASK_METRICS = {TASK_EVENT_TIMES: [("precision", None), ("recall", None), ("onset MAE", "ms")]}


def gate_metrics(metrics: list[dict], binding: dict) -> list[dict]:
    """The task's metrics under a capability's gate names (spec/fixtures/media/benchmark-bindings.json), in the
    task's order. A metric the binding does not map is a ValueError."""
    names = {m["task"]: m["gate"] for m in binding["metrics"]}
    renamed = []
    for metric in metrics:
        if metric["name"] not in names:
            raise ValueError(f"the binding of {binding['capabilityId']} does not map task metric {metric['name']!r}")
        renamed.append({**metric, "name": names[metric["name"]]})
    return renamed


def verdict(metrics: list[dict], floor: dict) -> dict:
    by_name = {m["name"]: m for m in metrics}
    checks = []
    for f in floor["metrics"]:
        m = by_name.get(f["name"])
        exact = None if m is None or m["exact"] is None else Fraction(m["exact"]["n"], m["exact"]["d"])
        limit = threshold(f["threshold"])
        ok = exact is not None and (exact >= limit if f["comparator"] == ">=" else exact <= limit)
        check = {"name": f["name"], "comparator": f["comparator"], "threshold": f["threshold"],
                 "value": None if m is None else m["value"], "passed": ok}
        if "unit" in f:
            check["unit"] = f["unit"]
        checks.append(check)
    return {"passed": all(c["passed"] for c in checks), "checks": checks}
