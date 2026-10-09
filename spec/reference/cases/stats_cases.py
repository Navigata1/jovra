"""Stat-engine fixtures: integer-percentage vectors (hand values from tennis-rules-and-stats.md §7) and
stat lines over small logs whose every number was worked out by hand before running the engine."""

from __future__ import annotations

from jovra_ref import conformance, scoring, stats
from jovra_ref.dsl import LogBuilder

from .common import CLUB_BO3, doubles, holds, singles

# (n, d, expected pct) -- §7 conformance table plus boundary vectors. None = "—".
PCT_VECTORS = [
    (72, 124, 58), (40, 60, 67), (28, 40, 70), (116, 124, 94),
    (1, 8, 13), (5, 8, 63), (3, 8, 38), (0, 0, None),
    (0, 5, 0), (5, 5, 100), (1, 3, 33), (2, 3, 67),
    (1, 200, 1), (1, 201, 0), (199, 200, 100), (38, 60, 63),
    (31, 50, 62), (12, 50, 24), (7, 50, 14), (52, 124, 42),
    (20, 60, 33), (13, 21, 62), (5, 21, 24), (3, 21, 14),
]

DELTAS = [
    ((40, 60), (38, 60), "+4 percentage points"),
    ((38, 60), (40, 60), "-4 percentage points"),
    ((1, 8), (12, 100), "+1 percentage point"),
    ((3, 8), (38, 100), "0 percentage points"),
    ((3, 8), (0, 0), "—"),
]

POOLS = [
    ([(1, 8), (30, 40)], (31, 48, 65)),
    ([(0, 0), (3, 4)], (3, 4, 75)),
    ([(0, 0), (0, 0)], (0, 0, None)),
]


def _ratio(n, d, p):
    return {"n": n, "d": d, "pct": p, "display": "—" if p is None else f"{p}%"}


def pct_fixture(version: str) -> dict:
    cases = []
    for n, d, p in PCT_VECTORS:
        cases.append({"op": "ratio", "n": n, "d": d, "expected": _ratio(n, d, p)})
    for cur, prior, text in DELTAS:
        cases.append({"op": "delta", "current": list(cur), "prior": list(prior), "expected": {"text": text}})
    for parts, (n, d, p) in POOLS:
        cases.append({"op": "pool", "parts": [list(x) for x in parts], "expected": _ratio(n, d, p)})
    for c in cases:
        actual = conformance.run_pct_case(c)
        if actual != c["expected"]:
            raise SystemExit(f"pct vector disagrees: {c} -> {actual}")
    return {
        "schemaVersion": version,
        "kind": "jovra.fixture.pct",
        "id": "T01-integer-percentages",
        "title": "pct(n, d) = (200n + d) div 2d, half-up, integers only; d = 0 shows '—'; deltas from displayed integers; pooling",
        "covers": ["§0 rule 4", "§7 rules 1-4", "§6.10 pooling"],
        "cases": cases,
    }


def mixed_log():
    lb = LogBuilder()
    S = lambda *r: [{"result": x} for x in r]  # noqa: E731
    lb.point("A", "ace", serves=S("in"), strokeCount=1)
    lb.point("B", "doubleFault", serves=S("fault", "fault"), strokeCount=0)
    lb.point("A", "winner", serves=S("fault", "in"), strokeCount=3)
    lb.point("A", "forcedError", serves=S("in"), strokeCount=4)
    lb.point("B", "unforcedError", serves=S("in"), strokeCount=5)
    lb.point("A", "serviceWinner", serves=S("in"), strokeCount=2)
    lb.point("B", "ace", serves=S("in"), strokeCount=1)
    lb.point("A", "winner", serves=S("fault", "in"), strokeCount=2)
    lb.point("A", "hindrance", serves=S("in"), strokeCount=3)
    lb.point("B", "unforcedError", serves=S("in"), strokeCount=6)
    lb.point("A", "doubleFault", serves=S("fault", "fault"), strokeCount=0)
    lb.point("B", "winner", serves=S("in"), strokeCount=9)
    lb.point("B", "forcedError", serves=S("in"), strokeCount=2)
    lb.point("B", "winner", serves=S("fault", "in"), strokeCount=5)
    lb.point("A", "unknown", serves=S("in"))  # game 3, Jon serving: winner known, ending not reviewed
    return lb


MIXED_EXPECT = {
    "sides.A.totalPointsWon": _ratio(8, 15, 53),
    "sides.A.servicePoints": 7,
    "sides.A.firstServeIn": _ratio(5, 7, 71),
    "sides.A.firstServePointsWon": _ratio(4, 5, 80),
    "sides.A.secondServePointsWon": _ratio(1, 2, 50),
    "sides.A.secondServeIn": _ratio(1, 2, 50),
    "sides.A.aces": 1,
    "sides.A.doubleFaults": 1,
    "sides.A.serviceWinners": 1,
    "sides.A.servicePointsWon": _ratio(5, 7, 71),
    "sides.A.serviceGamesWon": _ratio(1, 1, 100),
    "sides.B.firstServeIn": _ratio(5, 8, 63),
    "sides.B.firstServePointsWon": _ratio(4, 5, 80),
    "sides.B.secondServePointsWon": _ratio(1, 3, 33),
    "sides.B.secondServeIn": _ratio(2, 3, 67),
    "sides.B.servicePointsWon": _ratio(5, 8, 63),
    "sides.A.returnPointsWon": _ratio(3, 8, 38),
    "sides.A.returnFirstServePointsWon": _ratio(1, 5, 20),
    "sides.A.returnSecondServePointsWon": _ratio(2, 3, 67),
    "sides.B.returnPointsWon": _ratio(2, 7, 29),
    "sides.A.winners": 2,
    "sides.B.winners": 2,
    "sides.A.forcedErrors": 1,
    "sides.B.forcedErrors": 1,
    "sides.A.unforcedErrors": 2,
    "sides.B.unforcedErrors": 0,
    "sides.A.breakPointsConverted": _ratio(0, 1, 0),
    "sides.B.breakPointsSaved": _ratio(1, 1, 100),
    "sides.A.longestPointStreak": 2,
    "sides.B.longestPointStreak": 3,
    "shots": {"total": 43, "pointsWithStrokeCount": 14},
    "rallyLength": {"0-4": 10, "5-8": 2, "9+": 1, "unknown": 2},
}


def tiebreak_log():
    """Twelve love holds to 6-6, then Jon wins the tie-break 7-0 (Jon serves TB points 1, 4, 5; Alex 2, 3, 6, 7)."""
    lb = LogBuilder()
    lb.points(holds(12))
    lb.points("A" * 7)
    return lb


TIEBREAK_EXPECT = {
    "sides.A.serviceGamesWon": _ratio(6, 6, 100),
    "sides.B.serviceGamesWon": _ratio(6, 6, 100),
    "sides.A.returnGamesWon": _ratio(0, 6, 0),
    "sides.B.returnGamesWon": _ratio(0, 6, 0),
    "sides.A.servicePoints": 27,
    "sides.B.servicePoints": 28,
    "sides.A.returnPointsWon": _ratio(4, 28, 14),
    "sides.A.totalPointsWon": _ratio(31, 55, 56),
    "sides.A.breakPointsSaved": _ratio(0, 0, None),
    "sides.B.breakPointsConverted": _ratio(0, 0, None),
    "sides.A.longestPointStreak": 7,
    "sides.A.longestGameStreak": 1,
}


def doubles_log():
    lb = LogBuilder()
    S = lambda *r: [{"result": x} for x in r]  # noqa: E731
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    lb.point("A", "ace", serves=S("in"), strokeCount=1)
    lb.point("B", "doubleFault", serves=S("fault", "fault"), strokeCount=0)
    lb.point("A", "winner", serves=S("in"), strokeCount=3)
    lb.point("A", "winner", serves=S("fault", "in"), strokeCount=3)
    lb.point("A", "ace", serves=S("in"), strokeCount=1)
    for _ in range(4):
        lb.point("B", "ace", serves=S("in"), strokeCount=1)
    return lb


DOUBLES_EXPECT = {
    "servers.ann.servicePoints": 5,
    "servers.ann.firstServeIn": _ratio(3, 5, 60),
    "servers.ann.firstServePointsWon": _ratio(3, 3, 100),
    "servers.ann.secondServePointsWon": _ratio(1, 2, 50),
    "servers.ann.aces": 2,
    "servers.ann.doubleFaults": 1,
    "servers.ben.servicePoints": 4,
    "servers.ben.aces": 4,
    "servers.ben.servicePointsWon": _ratio(4, 4, 100),
    "sides.B.aces": 4,
}


def _stats_fixture(fid, title, covers, setup, lb, expect, version):
    fixture_input = dict(setup)
    fixture_input["log"] = lb.events
    result = scoring.fold(fixture_input, lb.events)
    computed = stats.compute(result)
    assertions = [{"path": p, "equals": v} for p, v in expect.items()]
    for a in assertions:
        actual = conformance.get_path(computed, a["path"])
        if actual != a["equals"]:
            raise SystemExit(f"{fid}: {a['path']} expected {a['equals']!r}, engine {actual!r}")
    return {
        "schemaVersion": version,
        "kind": "jovra.fixture.stats",
        "id": fid,
        "title": title,
        "covers": covers,
        "input": fixture_input,
        "assertions": assertions,
        "expected": computed,
    }


def write(out, write_json, version) -> int:
    docs = [
        pct_fixture(version),
        _stats_fixture("T02-every-end-type", "Every end type, unknown included, over two and a bit games: serve, return, "
                       "winners, errors, BP, shots, rally buckets",
                       ["§4.1 end types", "§6.1", "§6.2", "§6.3", "§6.4 winners exclude aces", "§6.6", "§6.9"],
                       singles(CLUB_BO3),
                       mixed_log(), MIXED_EXPECT, version),
        _stats_fixture("T03-doubles-per-server", "Doubles: serve stats per server as well as per team",
                       ["§6.8"], doubles(CLUB_BO3), doubles_log(), DOUBLES_EXPECT, version),
        _stats_fixture("T04-tiebreak-not-a-service-game", "A set tie-break is excluded from service and return games "
                       "(6 per side at 7-6), its points count as service points, and it holds no break points",
                       ["§6.1 service games exclude tie-breaks", "§6.3 tie-break points are never break points"],
                       singles(CLUB_BO3), tiebreak_log(), TIEBREAK_EXPECT, version),
    ]
    for d in docs:
        write_json(out / f"{d['id']}.json", d)
    return len(docs)


ORDER = 20


def generate(ctx) -> int:
    return write(ctx.fixtures / "stats", ctx.write_json, ctx.version)
