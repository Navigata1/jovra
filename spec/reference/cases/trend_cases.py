"""Trend fixtures (T05): pooled cross-session aggregation (rules §6.10, §7 rule 4; screens S03, S16).

Every assertion below was worked out by hand before the engine ran; the comment on each case shows the arithmetic.
pct(n, d) = (200n + d) div 2d. The generator refuses to write a case whose engine output disagrees with them, and
CHECKS re-runs the engine and the assertions from the committed file, so a hand edit to either side fails validation.
"""

from __future__ import annotations

from jovra_ref import conformance, trend

KIND = "jovra.fixture.trend"
ORDER = 25
FIXTURE_ID = "TR01-pooled-trends"


def _r(n: int, d: int, p: int | None) -> dict:
    return {"n": n, "d": d, "pct": p, "display": "—" if p is None else f"{p}%"}


def _s(sid: str, day: str, n: int, d: int, kind: str = "singlesMatch", sample: bool = False) -> dict:
    return {"id": sid, "date": day, "comparableKind": kind, "sample": sample, "n": n, "d": d}


def _case(name: str, title: str, range_: str, as_of: str, sessions: list[dict], assertions: list[tuple],
          scope: str = "real", kind: str = "singlesMatch") -> dict:
    return {"name": name, "title": title,
            "input": {"range": range_, "asOf": as_of, "comparableKind": kind, "scope": scope, "sessions": sessions},
            "assertions": [{"path": p, "equals": v} for p, v in assertions]}


# 4 weeks ending 2026-10-06 (the sample's last session): Sep 9-15, Sep 16-22, Sep 23-29, Sep 30-Oct 6.
CASES = [
    # 1/2 and 30/40 in the same week pool to 31/42: (6200 + 42) div 84 = 74. Averaging 50% and 75% would give 62.5.
    # One shown bucket only, so no comparison is drawn.
    _case("pool-not-average", "Pooling 1/2 with 30/40 gives 31/42 = 74%, not the 62.5% average",
          "4W", "2026-10-06", [_s("a", "2026-10-01", 1, 2), _s("b", "2026-10-05", 30, 40)], [
              ("buckets[3].ratio", _r(31, 42, 74)), ("buckets[3].sessionIds", ["a", "b"]),
              ("buckets[3].hidden", False), ("buckets[0].ratio", _r(0, 0, None)), ("buckets[0].hidden", True),
              ("state", "tooFewComparable"), ("headline", None), ("sessionCount", 2)]),
    # The Home / Progress fixture (screens.md S03, S16): 24/50, 33/60, 38/60, 40/60 -> 48, 55, 63, 67.
    # Delta from the displayed integers 67 - 63 = +4; the raw 66.67 - 63.33 = 3.33 would round to 3.
    # Pooled 135/230: (27000 + 230) div 460 = 59.
    _case("weekly-first-serves-in", "Weekly first serves in 48, 55, 63, 67 and +4 percentage points from displayed integers",
          "4W", "2026-10-06", [_s("w1", "2026-09-12", 24, 50), _s("w2", "2026-09-19", 33, 60),
                               _s("w3", "2026-09-26", 38, 60), _s("w4", "2026-10-06", 40, 60)], [
              ("buckets[0].from", "2026-09-09"), ("buckets[0].to", "2026-09-15"),
              ("buckets[3].from", "2026-09-30"), ("buckets[3].to", "2026-10-06"),
              ("buckets[0].ratio.pct", 48), ("buckets[1].ratio.pct", 55), ("buckets[2].ratio.pct", 63),
              ("buckets[3].ratio.pct", 67), ("headline.deltaPoints", 4),
              ("headline.deltaText", "+4 percentage points"), ("pooled", _r(135, 230, 59)), ("state", "ok")]),
    # W3 5/10 and W4 3/4 are below the 20-point bucket minimum: hidden, so the headline compares W2 67% (40/60)
    # with W1 60% (30/50): +7. Pooled 78/124 = (15600 + 124) div 248 = 63, at least the 100-point minimum.
    _case("hidden-small-buckets", "Buckets below the minimum denominator are hidden and skipped by the headline",
          "4W", "2026-10-06", [_s("w1", "2026-09-10", 30, 50), _s("w2", "2026-09-17", 40, 60),
                               _s("w3", "2026-09-24", 5, 10), _s("w4", "2026-10-02", 3, 4)], [
              ("buckets[2].hidden", True), ("buckets[3].hidden", True), ("buckets[2].ratio", _r(5, 10, 50)),
              ("headline.currentIndex", 1), ("headline.priorIndex", 0), ("headline.current", _r(40, 60, 67)),
              ("headline.prior", _r(30, 50, 60)), ("headline.deltaText", "+7 percentage points"),
              ("pooled", _r(78, 124, 63))]),
    # Real scope: the sample session (100/100) is excluded. W3 40/60 = 67, W4 45/60 = 75: +8.
    # Pooled 85/120 = (17000 + 120) div 240 = 71.
    _case("sample-excluded", "Sample sessions never enter a real trend",
          "4W", "2026-10-06", [_s("r3", "2026-09-25", 40, 60), _s("r4", "2026-10-03", 45, 60),
                               _s("demo", "2026-10-04", 100, 100, sample=True)], [
              ("excluded.otherScope", 1), ("buckets[3].sessionIds", ["r4"]), ("buckets[3].ratio", _r(45, 60, 75)),
              ("headline.deltaText", "+8 percentage points"), ("pooled", _r(85, 120, 71)), ("sessionCount", 2)]),
    # Sample scope over the same sessions: only the sample session, one bucket, no comparison.
    _case("sample-scope-alone", "A sample trend uses only sample sessions",
          "4W", "2026-10-06", [_s("r3", "2026-09-25", 40, 60), _s("r4", "2026-10-03", 45, 60),
                               _s("demo", "2026-10-04", 100, 100, sample=True)], [
              ("excluded.otherScope", 2), ("buckets[3].sessionIds", ["demo"]), ("pooled", _r(100, 100, 100)),
              ("state", "tooFewComparable"), ("headline", None)], scope="sample"),
    # 3 months ending Oct 6: Aug 1-31, Sep 1-30, Oct 1-6. Doubles session excluded (other kind).
    # Aug 30/50 = 60, Sep 33/60 = 55, Oct 40/60 = 67: headline Oct vs Sep +12. Pooled 103/170 = (20600+170) div 340 = 61.
    _case("months-and-comparable-kind", "Months for 3 months; only comparable sessions are pooled",
          "3M", "2026-10-06", [_s("aug", "2026-08-20", 30, 50), _s("sep", "2026-09-05", 33, 60),
                               _s("dbl", "2026-09-06", 60, 60, kind="doublesMatch"),
                               _s("oct", "2026-10-02", 40, 60)], [
              ("buckets[0].from", "2026-08-01"), ("buckets[0].to", "2026-08-31"), ("buckets[2].from", "2026-10-01"),
              ("buckets[2].to", "2026-10-06"), ("excluded.otherKind", 1), ("buckets[1].ratio", _r(33, 60, 55)),
              ("headline.deltaText", "+12 percentage points"), ("pooled", _r(103, 170, 61))]),
    # Year ending Oct 6 2026: Nov 2025 .. Oct 2026. Oct 31 2025 and Oct 7 2026 fall outside the window.
    # Aug 40/60 = 67, Sep 38/60 = 63: -4 (ASCII hyphen-minus). Pooled 78/120 = (15600 + 120) div 240 = 65.
    _case("year-negative-delta", "Year buckets by month; sessions outside the window are excluded; a fall reads -4",
          "Year", "2026-10-06", [_s("old", "2025-10-31", 60, 60), _s("aug", "2026-08-15", 40, 60),
                                 _s("sep", "2026-09-10", 38, 60), _s("late", "2026-10-07", 60, 60)], [
              ("buckets[0].from", "2025-11-01"), ("buckets[0].to", "2025-11-30"), ("buckets[11].to", "2026-10-06"),
              ("excluded.outsideWindow", 2), ("headline.currentIndex", 10), ("headline.priorIndex", 9),
              ("headline.deltaPoints", -4), ("headline.deltaText", "-4 percentage points"),
              ("pooled", _r(78, 120, 65))]),
    # Two shown buckets but only 25 + 25 = 50 pooled points: below the 100-point comparison minimum.
    _case("below-pooled-minimum", "Two buckets but fewer than 100 pooled points: too few comparable sessions",
          "4W", "2026-10-06", [_s("w1", "2026-09-10", 10, 25), _s("w4", "2026-10-05", 20, 25)], [
              ("buckets[0].hidden", False), ("buckets[3].hidden", False), ("pooled", _r(30, 50, 60)),
              ("state", "tooFewComparable"), ("headline", None)]),
    # No sessions at all: every bucket 0/0 shows "—", never a fake 0%.
    _case("no-data", "No sessions: every bucket is empty and shows an em dash",
          "4W", "2026-10-06", [], [
              ("state", "noData"), ("pooled", _r(0, 0, None)), ("buckets[1].ratio.display", "—"),
              ("sessionCount", 0), ("headline", None)]),
]


def run_case(case: dict) -> dict:
    i = case["input"]
    return trend.bucketed(i["sessions"], range_=i["range"], as_of=i["asOf"], comparable_kind=i["comparableKind"],
                          scope=i["scope"], minimums=i.get("minimums"))


def assertion_problems(case: dict, actual: dict) -> list[str]:
    problems = []
    for a in case["assertions"]:
        try:
            value = conformance.get_path(actual, a["path"])
        except (KeyError, IndexError, TypeError) as exc:
            problems.append(f"{case['name']} {a['path']}: path error {exc}")
            continue
        if value != a["equals"]:
            problems.append(f"{case['name']} {a['path']}: expected {a['equals']!r}, engine {value!r}")
    return problems


def generate(ctx) -> int:
    cases = []
    for case in CASES:
        actual = run_case(case)
        problems = assertion_problems(case, actual)
        if problems:
            raise SystemExit("trend case disagrees with its hand assertions: " + "; ".join(problems))
        cases.append({**case, "expected": actual})
    ctx.write_json(ctx.fixtures / "trend" / f"{FIXTURE_ID}.json", {
        "schemaVersion": "1.2.0", "kind": KIND, "id": FIXTURE_ID,
        "title": "Trends pool numerators and denominators per bucket, hide small buckets, take deltas from displayed "
                 "integers and keep sample sessions apart",
        "covers": ["§6.10", "§7 rule 4", "screens S03", "screens S16", "stories 32, 34, 280, 282"],
        "defaultMinimums": dict(trend.MINIMUMS), "cases": cases})
    return 1


def check(path, doc: dict, docs: dict) -> list[str]:
    problems = []
    if doc["defaultMinimums"] != trend.MINIMUMS:
        problems.append(f"defaultMinimums {doc['defaultMinimums']} differ from the reference {trend.MINIMUMS}")
    for case in doc["cases"]:
        actual = run_case(case)
        if actual != case["expected"]:
            problems.append(f"{case['name']}: committed expected output differs from the reference engine")
        problems += assertion_problems(case, case["expected"])
    return problems


CHECKS = {KIND: check}
