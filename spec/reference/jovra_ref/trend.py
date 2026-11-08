"""Pooled cross-session trends (tennis-rules-and-stats.md §6.10; ios-v1-spec ProgressAggregator; screens S03, S16).

A trend never averages percentages. Each bucket pools the numerators and denominators of the comparable sessions
that fall inside it, and the headline compares the latest shown bucket with the previous shown one using the two
DISPLAYED integers (§7 rule 4). Buckets below the minimum denominator are hidden: they keep their pooled fraction
(the table fallback and a hollow chart marker may show it) but never feed the headline. A comparison needs at least
two shown buckets and a pooled denominator at the minimum, else the state is "tooFewComparable".

Real trends exclude sample sessions; a sample trend (the demo) uses only sample sessions. The two never mix.
Dates are local calendar dates ("YYYY-MM-DD"); converting a timestamp to the player's day is the caller's job.
"""

from __future__ import annotations

from datetime import date, timedelta

from .stats import delta_text, pool, ratio

# The progress windows and their buckets (S16: weeks for 4 weeks, months for 3 months and Year).
RANGES = {"4W": ("week", 4), "3M": ("month", 3), "Year": ("month", 12)}
# One constants block so tuning on hardware is a one-line change (screens.md open question 5).
MINIMUMS = {"bucketDenominator": 20, "pooledDenominator": 100, "bucketsWithData": 2}
SCOPES = ("real", "sample")


def _month_start(day: date, back: int) -> date:
    months = day.year * 12 + (day.month - 1) - back
    return date(months // 12, months % 12 + 1, 1)


def bucket_bounds(range_: str, as_of: date) -> list[tuple[date, date]]:
    """Inclusive [from, to] calendar dates for each bucket, oldest first; the last bucket ends on as_of."""
    unit, count = RANGES[range_]
    if unit == "week":
        return [(as_of - timedelta(days=7 * (count - i) - 1), as_of - timedelta(days=7 * (count - 1 - i)))
                for i in range(count)]
    bounds = []
    for back in range(count - 1, -1, -1):
        start = _month_start(as_of, back)
        end = as_of if back == 0 else _month_start(as_of, back - 1) - timedelta(days=1)
        bounds.append((start, end))
    return bounds


def bucketed(sessions: list[dict], *, range_: str, as_of: str, comparable_kind: str, scope: str = "real",
             minimums: dict | None = None) -> dict:
    """The trend series for one stat. Each session carries id, date, comparableKind, sample, n, d."""
    if range_ not in RANGES:
        raise ValueError(f"unknown range {range_!r}")
    if scope not in SCOPES:
        raise ValueError(f"unknown scope {scope!r}")
    limits = {**MINIMUMS, **(minimums or {})}
    end = date.fromisoformat(as_of)
    bounds = bucket_bounds(range_, end)
    window_start = bounds[0][0]
    excluded = {"otherScope": 0, "otherKind": 0, "outsideWindow": 0}
    used: list[dict] = []
    for s in sorted(sessions, key=lambda s: (s["date"], s["id"])):
        ratio(s["n"], s["d"])  # domain check: 0 <= n <= d
        if s["sample"] != (scope == "sample"):
            excluded["otherScope"] += 1
        elif s["comparableKind"] != comparable_kind:
            excluded["otherKind"] += 1
        elif not window_start <= date.fromisoformat(s["date"]) <= end:
            excluded["outsideWindow"] += 1
        else:
            used.append(s)
    buckets = []
    for index, (start, stop) in enumerate(bounds):
        inside = [s for s in used if start <= date.fromisoformat(s["date"]) <= stop]
        pooled = pool([ratio(s["n"], s["d"]) for s in inside])
        buckets.append({"index": index, "from": start.isoformat(), "to": stop.isoformat(),
                        "sessionIds": [s["id"] for s in inside], "ratio": pooled,
                        "hidden": pooled["d"] < limits["bucketDenominator"]})
    total = pool([b["ratio"] for b in buckets])
    shown = [b for b in buckets if not b["hidden"]]
    comparable = len(shown) >= limits["bucketsWithData"] and total["d"] >= limits["pooledDenominator"]
    if not used:
        state = "noData"
    elif comparable:
        state = "ok"
    else:
        state = "tooFewComparable"
    headline = None
    if comparable:
        current, prior = shown[-1], shown[-2]
        headline = {"currentIndex": current["index"], "priorIndex": prior["index"],
                    "current": current["ratio"], "prior": prior["ratio"],
                    "deltaPoints": current["ratio"]["pct"] - prior["ratio"]["pct"],
                    "deltaText": delta_text(current["ratio"], prior["ratio"])}
    return {"state": state, "buckets": buckets, "pooled": total, "sessionCount": len(used),
            "excluded": excluded, "headline": headline}
