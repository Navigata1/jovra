"""Reference for benchmark labels (V01): the hash-fixed tuning / held-out split and the label scorer.

The Swift twin is JovraBenchmark (``Labels/LabelSplit.swift``, ``Labels/LabelScorer.swift``); both must
reproduce ``spec/fixtures/labels/L*.json`` exactly.

Split ``jovra.hashWindows.v1``. The recording's timeline is cut into windows of ``windowMs`` (the last one
may be shorter): n = ceil(durationMs / windowMs). Window i has the key SHA-256("jovra.hashWindows.v1\n" +
recordingSha256 + "\n" + i + "\n"). The held-out windows are the k windows with the smallest keys, where
k = n * heldOutPermille / 1000 rounded half-up, at least 1 and at most n - 1; a recording of one window has
no held-out window and cannot gate anything. Nobody chooses the windows: they follow from the recording's
bytes, so the split is fixed before the first label exists, and tuning and held-out windows never overlap.
A time t belongs to window min(floor(t / windowMs), n - 1).

Task ``labelScoring`` 1.0.0. Each kind of observation a stage produced is matched to the labels over the
whole recording, then every count is attributed to a split:

* Matching (hits, bounces, rally starts, rally ends) is the eventTimes rule of ``benchmark.py``: for each
  label in time order, the unmatched observation with the smallest |o - t| <= tolerance, the earlier one on a
  tie. A matched pair belongs to the split of its **label**; an unmatched observation to the split of its own
  time. So precision = matched / (matched + unmatched observations) and recall = matched / labels never mix
  windows, and an observation just across a window boundary from its label is not counted twice.
* Hits: precision, recall, recall for the near and the far player (by the label's player), timing MAE and
  timing bias (mean of observation - label, positive when the stage is late) in ms, and stroke accuracy over
  matched pairs where both sides name a stroke type.
* Bounces: a label with ``inPlay`` false (a dead ball) is matched like any other, but the pair is dropped: it
  is neither a hit nor a false alarm. Precision and recall count in-play labels only. Placement error is the
  distance in display pixels between matched in-play image points (median and mean, 2 places).
* Rally boundaries: starts and ends are matched separately and pooled; F1 = 2 * matched /
  (2 * matched + unmatched observations + unmatched labels). An open rally (``end`` null) has a start only.
* Court corners: each observation is compared with the labelled camera position in force at its time (the
  last one whose ``from`` is not later); corners either side leaves null are skipped. Mean and maximum
  corner distance in display pixels.
* Coverage: the share of each split's windows inside the ranges the stage says it analysed. A label outside
  them still counts against recall: a stage never gets credit for what it did not look at.

A kind the observations document omits is not scored (no rows); an empty list is scored (recall 0).
Ratios and millisecond values are exact rationals shown half-up (4 and 3 places); pixel values use IEEE
doubles (subtract, scale, square, add, sqrt, in that order) shown as floor(x * 100 + 0.5) / 100.
"""

from __future__ import annotations

import hashlib
import math
from fractions import Fraction

from . import benchmark

SPLIT_METHOD = "jovra.hashWindows.v1"
DEFAULT_WINDOW_MS = 30_000
DEFAULT_HELD_OUT_PERMILLE = 300
TASK_ID = "labelScoring"
TASK_VERSION = "1.0.0"
SPLITS = ("tuning", "heldOut")
STROKES = ("serve", "forehand", "backhand", "volley", "overhead", "other")
CORNER_ORDER = "farLeft,farRight,nearRight,nearLeft"


# ----- split ---------------------------------------------------------------------------------------

def duration_ms(recording: dict) -> int:
    """Whole milliseconds of the recording's duration (floor)."""
    return math.floor(benchmark.rt(recording["duration"]) * 1000)


def window_count(total_ms: int, window_ms: int) -> int:
    return -(-total_ms // window_ms) if total_ms > 0 else 0


def window_key(recording_sha256: str, index: int) -> str:
    return hashlib.sha256(f"{SPLIT_METHOD}\n{recording_sha256}\n{index}\n".encode("ascii")).hexdigest()


def held_out_windows(recording_sha256: str, total_ms: int, window_ms: int, permille: int) -> list[int]:
    n = window_count(total_ms, window_ms)
    if n < 2:
        return []
    count = min(max((n * permille + 500) // 1000, 1), n - 1)
    ranked = sorted(range(n), key=lambda i: (window_key(recording_sha256, i), i))
    return sorted(ranked[:count])


def make_split(recording: dict, window_ms: int = DEFAULT_WINDOW_MS, permille: int = DEFAULT_HELD_OUT_PERMILLE) -> dict:
    total = duration_ms(recording)
    return {"method": SPLIT_METHOD, "windowMs": window_ms, "heldOutPermille": permille, "durationMs": total,
            "heldOutWindows": held_out_windows(recording["sha256"], total, window_ms, permille)}


def window_of(time: Fraction, split: dict) -> int:
    n = window_count(split["durationMs"], split["windowMs"])
    return max(min(math.floor(time * 1000 / split["windowMs"]), n - 1), 0)


def split_of(time: Fraction, split: dict) -> str:
    return "heldOut" if window_of(time, split) in set(split["heldOutWindows"]) else "tuning"


def window_range(index: int, split: dict) -> tuple[Fraction, Fraction]:
    start = index * split["windowMs"]
    return Fraction(start, 1000), Fraction(min(start + split["windowMs"], split["durationMs"]), 1000)


def windows_in(name: str, split: dict) -> list[int]:
    held = set(split["heldOutWindows"])
    n = window_count(split["durationMs"], split["windowMs"])
    return [i for i in range(n) if (i in held) == (name == "heldOut")]


# ----- label documents -----------------------------------------------------------------------------

def labels_sha256(data: bytes) -> str:
    """A label file's hash is the SHA-256 of its bytes as committed."""
    return hashlib.sha256(data).hexdigest()


def counts(labels: dict) -> dict:
    return {"hits": len(labels["hits"]),
            "strokes": sum(1 for h in labels["hits"] if h.get("stroke") is not None),
            "bounces": len(labels["bounces"]),
            "rallies": sum(1 for r in labels["rallies"] if r["end"] is not None),
            "cameraPositions": len(labels["cameraPositions"])}


def label_problems(labels: dict) -> list[str]:
    """What the schema cannot say about one label document."""
    problems: list[str] = []
    recording = labels["recording"]
    try:
        end = benchmark.rt(recording["duration"])
        expected = make_split(recording, labels["split"]["windowMs"], labels["split"]["heldOutPermille"])
    except (ValueError, ZeroDivisionError) as exc:
        return [f"recording duration or split: {exc}"]
    if labels["split"] != expected:
        problems.append(f"split is not the hash-fixed split of this recording: expected {expected}")

    def times(name: str, items: list, key: str = "time") -> list[Fraction]:
        out = [benchmark.rt(i[key]) for i in items]
        if any(b < a for a, b in zip(out, out[1:])):
            problems.append(f"{name} are not in time order")
        if any(t > end for t in out):
            problems.append(f"{name} hold a time after the recording ends")
        return out

    hit_times = times("hits", labels["hits"])
    seen = set()
    for t, h in zip(hit_times, labels["hits"]):
        if (t, h["player"]) in seen:
            problems.append(f"two hits by the {h['player']} player at {t} s")
        seen.add((t, h["player"]))
    times("bounces", labels["bounces"])
    starts = times("rally starts", labels["rallies"], "start")
    previous_end = None
    for index, (start, rally) in enumerate(zip(starts, labels["rallies"])):
        if previous_end is not None and start < previous_end:
            problems.append(f"rally {index + 1} starts before the previous rally ends")
        if rally["end"] is None:
            if index != len(labels["rallies"]) - 1:
                problems.append(f"rally {index + 1} is open but is not the last rally")
            continue
        finish = benchmark.rt(rally["end"])
        if finish <= start:
            problems.append(f"rally {index + 1} does not run forwards")
        if finish > end:
            problems.append(f"rally {index + 1} ends after the recording")
        previous_end = finish
    froms = times("camera positions", labels["cameraPositions"], "from")
    if len(set(froms)) != len(froms):
        problems.append("two camera positions start at the same time")
    if "hitCandidates" in labels:
        candidate_times = times("hit candidates", labels["hitCandidates"]["items"])
        if len(set(candidate_times)) != len(candidate_times):
            problems.append("two hit candidates share a time")
    return problems


def observation_problems(observations: dict, labels: dict) -> list[str]:
    problems = []
    if observations["recordingSha256"] != labels["recording"]["sha256"]:
        problems.append("observations are for a different recording than the labels")
    previous = None
    for r in observations.get("analysed", []):
        start, finish = benchmark.rt(r["start"]), benchmark.rt(r["end"])
        if finish <= start or (previous is not None and start < previous):
            problems.append("analysed ranges must run forwards, in order and without overlap")
        previous = finish
    for rally in observations.get("rallies", []):
        if benchmark.rt(rally["end"]) <= benchmark.rt(rally["start"]):
            problems.append("an observed rally does not run forwards")
    return problems


# ----- scoring -------------------------------------------------------------------------------------

def match_pairs(label_times: list[Fraction], observed: list[Fraction], tolerance: Fraction):
    """(pairs, unmatched): pairs are (label index, observation index) in label order; observation indexes are
    positions in ``observed``. Labels must be in time order (label documents are)."""
    order = sorted(range(len(observed)), key=lambda j: (observed[j], j))
    used = [False] * len(order)
    pairs = []
    for i, t in enumerate(label_times):
        best, best_d = None, None
        for k, j in enumerate(order):
            if used[k]:
                continue
            d = abs(observed[j] - t)
            if d <= tolerance and (best is None or d < best_d):
                best, best_d = k, d
        if best is not None:
            used[best] = True
            pairs.append((i, order[best]))
    unmatched = [order[k] for k in range(len(order)) if not used[k]]
    return pairs, unmatched


def _count(group: str, name: str, value: int) -> dict:
    return {"group": group, "name": name, "value": str(value)}


def _ratio(group: str, name: str, n: int, d: int) -> dict:
    exact = Fraction(n, d) if d else None
    return {"group": group, "name": name, "exact": _exact(exact),
            "value": None if exact is None else benchmark.half_up(exact, 4)}


def _ms(group: str, name: str, total: Fraction, n: int, signed: bool = False) -> dict:
    exact = total * 1000 / n if n else None
    if exact is None:
        value = None
    elif signed:
        value = ("-" if exact < 0 else "+") + benchmark.half_up(abs(exact), 3)
    else:
        value = benchmark.half_up(exact, 3)
    return {"group": group, "name": name, "unit": "ms", "exact": _exact(exact), "value": value}


def _exact(value: Fraction | None):
    return None if value is None else {"n": value.numerator, "d": value.denominator}


def pixels_text(value: float | None) -> str | None:
    if value is None:
        return None
    q = math.floor(value * 100 + 0.5)
    return f"{q // 100}.{q % 100:02d}"


def _px(group: str, name: str, value: float | None) -> dict:
    return {"group": group, "name": name, "unit": "px", "value": pixels_text(value)}


def distance_px(a: dict, b: dict, width: int, height: int) -> float:
    dx = (a["x"] - b["x"]) * width
    dy = (a["y"] - b["y"]) * height
    return math.sqrt(dx * dx + dy * dy)


def median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    mid = len(ordered) // 2
    return ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2


def mean(values: list[float]) -> float | None:
    if not values:
        return None
    total = 0.0
    for v in values:
        total += v
    return total / len(values)


def score(labels: dict, observations: dict, tolerances: dict) -> dict:
    """{"tuning": {...}, "heldOut": {...}}: each split's window count, duration and metric rows."""
    split = labels["split"]
    width, height = labels["recording"]["width"], labels["recording"]["height"]
    rows = {name: [] for name in SPLITS}

    def where(time: Fraction) -> str:
        return split_of(time, split)

    if "hits" in observations:
        tolerance = benchmark.rt(tolerances["hit"])
        label_times = [benchmark.rt(h["time"]) for h in labels["hits"]]
        observed = [benchmark.rt(o["time"]) for o in observations["hits"]]
        pairs, unmatched = match_pairs(label_times, observed, tolerance)
        for name in SPLITS:
            mine = [(i, j) for i, j in pairs if where(label_times[i]) == name]
            in_split = [i for i, t in enumerate(label_times) if where(t) == name]
            extra = sum(1 for j in unmatched if where(observed[j]) == name)
            deltas = [observed[j] - label_times[i] for i, j in mine]
            compared = [(labels["hits"][i]["stroke"], observations["hits"][j].get("stroke")) for i, j in mine]
            compared = [(a, b) for a, b in compared if a is not None and b is not None]
            g = "hits"
            out = [_count(g, "labels", len(in_split)), _count(g, "observations", len(mine) + extra),
                   _count(g, "matched", len(mine)),
                   _ratio(g, "precision", len(mine), len(mine) + extra), _ratio(g, "recall", len(mine), len(in_split))]
            for player in ("near", "far"):
                total = sum(1 for i in in_split if labels["hits"][i]["player"] == player)
                found = sum(1 for i, _ in mine if labels["hits"][i]["player"] == player)
                out.append(_ratio(g, f"recall {player}", found, total))
            out += [_ms(g, "timing MAE", sum((abs(d) for d in deltas), Fraction(0)), len(deltas)),
                    _ms(g, "timing bias", sum(deltas, Fraction(0)), len(deltas), signed=True),
                    _count(g, "strokes compared", len(compared)),
                    _ratio(g, "stroke accuracy", sum(1 for a, b in compared if a == b), len(compared))]
            rows[name] += out

    if "bounces" in observations:
        tolerance = benchmark.rt(tolerances["bounce"])
        label_times = [benchmark.rt(b["time"]) for b in labels["bounces"]]
        observed = [benchmark.rt(o["time"]) for o in observations["bounces"]]
        pairs, unmatched = match_pairs(label_times, observed, tolerance)
        for name in SPLITS:
            in_split = [i for i, t in enumerate(label_times) if where(t) == name]
            in_play = [i for i in in_split if labels["bounces"][i]["inPlay"]]
            mine = [(i, j) for i, j in pairs if where(label_times[i]) == name]
            scored = [(i, j) for i, j in mine if labels["bounces"][i]["inPlay"]]
            extra = sum(1 for j in unmatched if where(observed[j]) == name)
            deltas = [abs(observed[j] - label_times[i]) for i, j in scored]
            distances = [distance_px(observations["bounces"][j]["imagePoint"], labels["bounces"][i]["imagePoint"], width, height)
                         for i, j in scored if observations["bounces"][j].get("imagePoint") is not None]
            g = "bounces"
            rows[name] += [
                _count(g, "labels in play", len(in_play)), _count(g, "labels not in play", len(in_split) - len(in_play)),
                _count(g, "observations", len(scored) + extra), _count(g, "matched", len(scored)),
                _count(g, "dropped on a label not in play", len(mine) - len(scored)),
                _ratio(g, "precision", len(scored), len(scored) + extra), _ratio(g, "recall", len(scored), len(in_play)),
                _ms(g, "timing MAE", sum(deltas, Fraction(0)), len(deltas)),
                _count(g, "placed", len(distances)),
                _px(g, "placement error median", median(distances)), _px(g, "placement error mean", mean(distances))]

    if "rallies" in observations:
        tolerance = benchmark.rt(tolerances["rallyBoundary"])
        tally = {name: {"labels": 0, "matched": 0, "extra": 0} for name in SPLITS}
        for key in ("start", "end"):
            label_times = [benchmark.rt(r[key]) for r in labels["rallies"] if r[key] is not None]
            observed = [benchmark.rt(r[key]) for r in observations["rallies"]]
            pairs, unmatched = match_pairs(label_times, observed, tolerance)
            for t in label_times:
                tally[where(t)]["labels"] += 1
            for i, _ in pairs:
                tally[where(label_times[i])]["matched"] += 1
            for j in unmatched:
                tally[where(observed[j])]["extra"] += 1
        for name in SPLITS:
            t, g = tally[name], "rally boundaries"
            missed = t["labels"] - t["matched"]
            rows[name] += [
                _count(g, "labels", t["labels"]), _count(g, "observations", t["matched"] + t["extra"]),
                _count(g, "matched", t["matched"]),
                _ratio(g, "precision", t["matched"], t["matched"] + t["extra"]), _ratio(g, "recall", t["matched"], t["labels"]),
                _ratio(g, "F1", 2 * t["matched"], 2 * t["matched"] + t["extra"] + missed)]

    if "courtCorners" in observations:
        positions = [(benchmark.rt(p["from"]), p["corners"]["points"]) for p in labels["cameraPositions"]]
        found = {name: {"errors": [], "unlabelled": 0} for name in SPLITS}
        for o in observations["courtCorners"]:
            time = benchmark.rt(o["time"])
            current = [points for start, points in positions if start <= time]
            if not current:
                found[where(time)]["unlabelled"] += 1
                continue
            for mine, theirs in zip(current[-1], o["points"]):
                if mine is not None and theirs is not None:
                    found[where(time)]["errors"].append(distance_px(theirs, mine, width, height))
        for name in SPLITS:
            errors, g = found[name]["errors"], "court corners"
            rows[name] += [_count(g, "corners compared", len(errors)),
                           _count(g, "observations before any labelled camera position", found[name]["unlabelled"]),
                           _px(g, "corner error mean", mean(errors)), _px(g, "corner error max", max(errors) if errors else None)]

    result = {}
    for name in SPLITS:
        indexes = windows_in(name, split)
        ranges = [window_range(i, split) for i in indexes]
        total = sum((b - a for a, b in ranges), Fraction(0))
        if "analysed" in observations:
            analysed = [(benchmark.rt(r["start"]), benchmark.rt(r["end"])) for r in observations["analysed"]]
            covered = sum((max(Fraction(0), min(b, d) - max(a, c)) for a, b in ranges for c, d in analysed), Fraction(0))
            exact = covered / total if total else None
            rows[name].append({"group": "coverage", "name": "analysed share", "exact": _exact(exact),
                               "value": None if exact is None else benchmark.half_up(exact, 4)})
        result[name] = {"windows": len(indexes), "durationMs": int(total * 1000), "rows": rows[name]}
    return result


# ----- the label set (spec/benchmarks/labels/manifest.json) ----------------------------------------

def targets_met(recording: dict, files: list[dict]) -> bool:
    """A recording's targets count the label files made on that recording itself (never an excerpt)."""
    mine = [f for f in files if f["recordingSha256"] == recording["sha256"]]
    return all(sum(f["counts"][key] for f in mine) >= wanted for key, wanted in recording["targets"].items())


def label_set_status(doc: dict) -> str:
    return "complete" if all(targets_met(r, doc["labelFiles"]) for r in doc["recordings"]) else "founderPending"
