"""Generator for the coherent Jon vs Alex sample match (tennis-rules-and-stats.md §8, constraints C1-C16).

Deterministic: a fixed seed drives a hand-rolled SplitMix64, so the output does not depend on Python's
``random`` implementation. Point winners are the verified construction in §8.4 (Case A, Jon serves first,
decision D4); every other free parameter (serve split, aces, double faults, end types, shot counts,
timestamps, flagged points) is pinned by the seed and then checked against C1-C16.
"""

from __future__ import annotations

import copy
import uuid

from . import csv_export, scoring, stats
from .dsl import LogBuilder

SEED = 20261006
GENERATOR = "sample:jonVsAlex@1.0.0"
NAMESPACE = uuid.UUID("6f9d3c2a-1b7e-4d5a-9c0e-7a1f2b3c4d5e")

CONSTRUCTION = ("JJJJ JJAAAA JJJJ JAAJAA JJAJJ AAJJAJAA JJAJJ JAJAJAJJ JAJJAAAA JJJJ "
                "JJAJJ AAJJAJAA JJAJJ JJAAJAJJ JJAAAJJJ JAJAAJAA AJAAJJAA JJAJAAJJ AAJJJAJJ")
MATCH_MS = 54 * 60 * 1000
SHOTS = 386
POINT_42 = 41  # 0-based index
REST_RANGES = {  # ms between the end of a point and the next first-serve strike (ITF ceilings in comments)
    "changeoverNoRest": (18000, 23000),  # <= 25 s
    "changeover": (70000, 85000),  # <= 90 s
    "setBreak": (105000, 115000),  # <= 120 s
}
REST_MAX = {"point": 25000, "changeoverNoRest": 25000, "changeover": 90000, "setBreak": 120000}
SERVE_PLAN = {  # per server: (won on 1st, won on 2nd, lost on 1st, lost on 2nd incl. DF), aces, DFs, service winners
    "A": {"won": (28, 12), "lost": (12, 8), "aces": 4, "dfs": 3, "serviceWinners": 3},
    "B": {"won": (21, 11), "lost": (17, 15), "aces": 2, "dfs": 5, "serviceWinners": 2},
}
STROKE_WEIGHTS = [(2, 30), (3, 25), (4, 16), (5, 11), (6, 7), (7, 5), (8, 3), (9, 2), (10, 1)]


class SplitMix64:
    MASK = (1 << 64) - 1

    def __init__(self, seed: int):
        self.state = seed & self.MASK

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & self.MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & self.MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & self.MASK
        return z ^ (z >> 31)

    def below(self, n: int) -> int:
        return self.next() % n

    def between(self, lo: int, hi: int) -> int:
        return lo + self.below(hi - lo + 1)

    def shuffled(self, items: list) -> list:
        out = list(items)
        for i in range(len(out) - 1, 0, -1):
            j = self.below(i + 1)
            out[i], out[j] = out[j], out[i]
        return out

    def weighted(self, pairs: list[tuple[int, int]]) -> int:
        total = sum(w for _, w in pairs)
        r = self.below(total)
        for value, w in pairs:
            if r < w:
                return value
            r -= w
        raise AssertionError


def uid(name: str) -> str:
    return str(uuid.uuid5(NAMESPACE, name))


JON, ALEX = uid("player/jon"), uid("player/alex")


def setup() -> dict:
    return {
        "format": {
            "presetId": "club_bo3",
            "setsToWin": 2,
            "gameScoring": "ad",
            "set": {"kind": "tiebreakSet", "games": 6, "tiebreakAt": 6, "tiebreak": {"points": 7}},
            "lets": "let",
        },
        "players": [
            {"id": JON, "displayName": "Jon", "handedness": "right", "backhand": "twoHanded", "isSelf": True},
            {"id": ALEX, "displayName": "Alex", "handedness": "right", "backhand": "oneHanded", "isSelf": False},
        ],
        "sides": {"A": [JON], "B": [ALEX]},
        "toss": {"firstServer": JON, "startingEnds": {"A": "near", "B": "far"}, "tossWinner": "A",
                 "tossChoice": "serve"},
    }


def winners() -> str:
    return "".join(CONSTRUCTION.split()).replace("A", "b").replace("J", "a").upper()


def _assign_serves(rng: SplitMix64, won_by: str, servers: list[str]) -> dict[int, dict]:
    facts: dict[int, dict] = {}
    for side, plan in SERVE_PLAN.items():
        won = [i for i, s in enumerate(servers) if s == side and won_by[i] == side]
        lost = [i for i, s in enumerate(servers) if s == side and won_by[i] != side]
        forced_first_won = [POINT_42] if side == "B" else []
        won = forced_first_won + rng.shuffled([i for i in won if i not in forced_first_won])
        lost = rng.shuffled(lost)
        first_won, second_won = won[: plan["won"][0]], won[plan["won"][0]:]
        first_lost, second_lost = lost[: plan["lost"][0]], lost[plan["lost"][0]:]
        assert len(second_won) == plan["won"][1] and len(second_lost) == plan["lost"][1]
        candidates = [i for i in first_won if i != POINT_42]
        aces = set(candidates[: plan["aces"]])
        service_winners = set(candidates[plan["aces"]: plan["aces"] + plan["serviceWinners"]])
        dfs = set(second_lost[: plan["dfs"]])
        for i in first_won + first_lost:
            facts[i] = {"serveNumber": 1, "end": "ace" if i in aces else ("serviceWinner" if i in service_winners else None)}
        for i in second_won + second_lost:
            facts[i] = {"serveNumber": 2, "end": "doubleFault" if i in dfs else None}
    return facts


def _fault(rng: SplitMix64) -> dict:
    return {"result": "fault", "faultType": ("net", "long", "wide", "net", "long", "footFault")[rng.below(6)]}


def _stroke_counts(rng: SplitMix64, facts: dict[int, dict]) -> dict[int, int]:
    counts = {}
    free = []
    for i, f in sorted(facts.items()):
        if f["end"] == "doubleFault":
            counts[i] = 0
        elif f["end"] == "ace":
            counts[i] = 1
        elif f["end"] == "serviceWinner":
            counts[i] = 2
        elif i == POINT_42:
            counts[i] = 8
        else:
            counts[i] = rng.weighted(STROKE_WEIGHTS)
            free.append(i)
    diff = SHOTS - sum(counts.values())
    while abs(diff) >= 2:
        i = free[rng.below(len(free))]
        if diff > 0 and counts[i] <= 13:
            counts[i] += 2
            diff -= 2
        elif diff < 0 and counts[i] >= 4:
            counts[i] -= 2
            diff += 2
    if diff != 0:
        pool = [i for i in free if counts[i] >= 3] if diff < 0 else free
        counts[pool[rng.below(len(pool))]] += diff
    return counts


def _end_type(rng: SplitMix64, fact: dict, n: int, winner: str, server: str) -> str:
    if fact["end"] is not None:
        return fact["end"]
    last_hitter = server if n % 2 == 1 else ("B" if server == "A" else "A")
    if last_hitter == winner:
        return "winner"
    return "forcedError" if rng.below(10) < 4 else "unforcedError"


def _durations(rng: SplitMix64, serves: list[list[dict]], counts: list[int]) -> list[int]:
    out = []
    for attempts, n in zip(serves, counts):
        ms = sum(4500 if a["result"] == "let" else 7000 for a in attempts[:-1])
        ms += 1200 if n == 0 else 900 + (n - 1) * 1150 + 700
        out.append(ms + rng.below(600))
    return out


def _gaps(rng: SplitMix64, rests: list[str], durations: list[int], total_ms: int = MATCH_MS) -> list[int]:
    gaps = [None] * (len(rests) - 1)
    for i, rest in enumerate(rests[:-1]):
        if rest in REST_RANGES:
            gaps[i] = rng.between(*REST_RANGES[rest])
    free = [i for i, g in enumerate(gaps) if g is None]
    remaining = total_ms - sum(durations) - sum(g for g in gaps if g is not None)
    jitter = [rng.between(-3000, 3000) for _ in free]
    mean = sum(jitter) // len(free)
    base = remaining // len(free)
    for k, i in enumerate(free):
        gaps[i] = base + jitter[k] - mean
    gaps[free[-1]] += remaining - sum(gaps[i] for i in free)
    return gaps


def build() -> tuple[dict, dict]:
    """Return (session document, fixture input for the engine)."""
    rng = SplitMix64(SEED)
    won_by = winners()
    s = setup()
    probe = LogBuilder()
    probe.points(won_by)
    base = scoring.fold(s, probe.events)
    servers = [p["serverSide"] for p in base["points"]]
    rests = [p["after"]["rest"] for p in base["points"]]
    server_ids = [p["server"] for p in base["points"]]

    facts = _assign_serves(rng, won_by, servers)
    counts_by_index = _stroke_counts(rng, facts)
    counts = [counts_by_index[i] for i in range(len(won_by))]
    serves = []
    for i in range(len(won_by)):
        f = facts[i]
        if f["end"] == "doubleFault":
            attempts = [_fault(rng), _fault(rng)]
        elif f["serveNumber"] == 2:
            attempts = [_fault(rng), {"result": "in"}]
        else:
            attempts = [{"result": "in"}]
        serves.append(attempts)
    for i in rng.shuffled([i for i in range(len(won_by)) if facts[i]["end"] != "doubleFault"])[:3]:
        serves[i] = [{"result": "let"}] + serves[i]
    end_types = [_end_type(rng, facts[i], counts[i], won_by[i], servers[i]) for i in range(len(won_by))]
    flagged = {POINT_42} | set(rng.shuffled([i for i in range(len(won_by)) if i != POINT_42])[:7])

    durations = _durations(rng, serves, counts)
    gaps = _gaps(rng, rests, durations)
    t = 0
    log = []
    for i in range(len(won_by)):
        start, end = t, t + durations[i]
        t = end + (gaps[i] if i < len(gaps) else 0)
        flagged_point = i in flagged
        log.append({
            "id": uid(f"point/{i + 1}"),
            "seq": i + 1,
            "type": "point",
            "recordedServer": server_ids[i],
            "tStartMs": start,
            "tEndMs": end,
            "reviewed": {
                "winner": won_by[i],
                "endType": end_types[i],
                "serves": serves[i],
                "strokeCount": counts[i],
                "provenance": "manual" if flagged_point else "reviewed",
                "source": "user",
            },
            "reviewState": "needsReview" if flagged_point else "reviewed",
        })
    fixture_input = copy.deepcopy(s)
    fixture_input["log"] = log
    session = {
        "schemaVersion": "1.0.0",
        "kind": "jovra.session",
        "id": uid("session/jon-vs-alex"),
        "sport": "tennis",
        "createdAt": "2026-10-06T22:00:00Z",
        "updatedAt": "2026-10-07T01:30:00Z",
        "title": "Jon vs Alex",
        "sample": {"label": "Sample", "synthetic": True, "generator": f"{GENERATOR} seed {SEED}"},
        "sessionKind": "match",
        "capturePurpose": "match",
        "players": s["players"],
        "sides": s["sides"],
        "match": {"format": s["format"], "toss": s["toss"], "log": log},
        "recording": {
            "mode": "none",
            "startedAt": "2026-10-06T22:00:00Z",
            "timeZone": "America/Chicago",
            "durationMs": MATCH_MS,
            "segments": [],
            "gaps": [],
            "microphone": "notRequested",
            "mediaAvailable": False,
        },
        "marks": [{
            "id": uid("mark/point-42"),
            "tMs": log[POINT_42]["tStartMs"],
            "kind": "note",
            "note": "Sample: check this point",
            "provenance": {"status": "manual", "source": "user", "sample": True},
        }],
        "shots": [],
        "calibrations": [],
        "annotations": [],
        "voiceNotes": [],
        "comparisons": [],
        "derivedValues": [],
        "analysis": {"state": "notRequested", "runs": []},
        "review": {"state": "inProgress", "updatedAt": "2026-10-07T01:30:00Z"},
        "archive": {"state": "localOnly"},
        "storage": {"originals": "none", "includeInDeviceBackup": False},
        "equipmentUse": [{
            "id": uid("equipmentUse/jon"),
            "playerId": JON,
            "racketId": uid("racket/head-prestige"),
            "stringJobId": uid("stringJob/2026-09-28"),
            "setupLabelSnapshot": "Head Prestige · Hyper-G 52 / Ghost Wire 50 lb",
            "activeMinutes": 54,
            "source": "manualLog",
        }],
        "consent": {"status": "informed", "competitionMode": False},
    }
    return session, fixture_input


# ----- constraints C1-C16 -------------------------------------------------------------------------

def constraints(session: dict, fold_result: dict, st: dict) -> list[dict]:
    pts = [p for p in fold_result["points"]]
    games = fold_result["games"]
    A, B = st["sides"]["A"], st["sides"]["B"]
    out = []

    def check(cid, ok, detail, kind="hard", waived=None):
        """``ok`` covers every clause that is checked. A clause set aside by a named lead decision is listed
        in ``waived`` with what the engine observed; the constraint is then ``partial``, never ``pass``."""
        status = "fail" if not ok else ("partial" if waived else "pass")
        entry = {"id": cid, "kind": kind, "status": status, "detail": detail}
        if waived:
            entry["waived"] = waived
        out.append(entry)

    f = session["match"]["format"]
    check("C1", f["setsToWin"] == 2 and f["gameScoring"] == "ad" and f["set"]["kind"] == "tiebreakSet"
          and f["set"]["tiebreakAt"] == 6 and f["lets"] == "let" and "finalSet" not in f
          and not any(g["kind"] != "standard" for g in games),
          "best of 3, ad games, tie-break at 6-6 (not triggered), lets on")
    sets = [(s_["games"]["A"], s_["games"]["B"]) for s_ in fold_result["sets"]]
    check("C2", sets == [(6, 4), (6, 3)] and fold_result["match"]["winner"] == "A"
          and pts[-1]["after"]["matchWon"] and not any(p["afterMatchEnd"] for p in pts),
          f"sets {sets}; match ends on point {len(pts)}; no point after it")
    g10, g19 = games[9], games[18]
    before10 = next(p for p in pts if p["game"] == 9)["before"]["games"]
    before19 = next(p for p in pts if p["game"] == 18)["before"]["games"]
    check("C3", before10 == {"A": 5, "B": 4} and g10["winner"] == "A" and before19 == {"A": 5, "B": 3}
          and g19["winner"] == "A", "set 1 is 5-4 before game 10, set 2 is 5-3 before game 9; Jon wins both")
    mismatch = [c for c in fold_result["conflicts"] if c["type"] == "serverMismatch"]
    check("C4", session["match"]["toss"]["firstServer"] == JON and not mismatch
          and all("recordedServer" in e for e in session["match"]["log"]),
          "firstServer declared; every recorded server equals the derived server")
    check("C5", A["servicePoints"] == 60 and B["servicePoints"] == 64, "Jon serves 60 points, Alex 64")
    legal = all(
        (max(g["points"].values()) == 4 and min(g["points"].values()) <= 2)
        or (min(g["points"].values()) >= 3 and max(g["points"].values()) - min(g["points"].values()) == 2)
        for g in games)
    check("C6", legal and not any(sum(g["points"].values()) == 7 for g in games),
          "every game ends 4-0, 4-1, 4-2 or (k+2)-k; no 7-point games")
    check("C7", A["totalPointsWon"]["n"] == 72 and B["totalPointsWon"]["n"] == 52
          and A["penaltyPointsAwarded"] == 0 and B["penaltyPointsAwarded"] == 0, "Jon 72, Alex 52, no penalties")
    y = A["secondServePointsWon"]["n"]
    check("C8", A["firstServeIn"]["n"] == 40 and A["firstServeIn"]["d"] == 60 and A["firstServePointsWon"]["n"] == 28
          and A["secondServePointsWon"]["d"] == 20 and A["servicePointsWon"]["n"] == 28 + y
          and A["returnPointsWon"] == {**A["returnPointsWon"], "n": 44 - y, "d": 64},
          f"60 attempts, 40 in, 28 won; 20 second-serve points, y = {y} won; RPW = 44 - y of 64")
    per_set = []
    for set_index in (0, 1):
        breaks = {s_: sum(1 for g in games if g["set"] == set_index and g["break"] and g["winner"] == s_) for s_ in "AB"}
        per_set.append(breaks["A"] - breaks["B"])
    check("C9", per_set == [1, 1] and A["breakPointsConverted"]["n"] == A["returnGamesWon"]["n"]
          and B["breakPointsConverted"]["n"] == B["returnGamesWon"]["n"],
          f"Jon breaks minus Alex breaks per set {per_set}; breaks = BP converted")
    shot_ok = all((p["strokeCount"] == 0) == (p["endType"] == "doubleFault") for p in pts) and all(
        p["strokeCount"] == 1 for p in pts if p["endType"] == "ace") and all(
        p["strokeCount"] >= 2 for p in pts if p["endType"] not in ("ace", "doubleFault"))
    check("C10", st["shots"]["total"] == SHOTS and shot_ok, "Σ strokeCount = 386; DF 0, ace 1, others ≥ 2")
    check("C11", not any(c["type"] == "outcomeInconsistent" for c in fold_result["conflicts"]),
          "one end type per point, consistent with its winner and stroke parity")
    timing_ok = pts[0]["tStartMs"] == 0 and pts[-1]["tEndMs"] == MATCH_MS
    for p, q in zip(pts, pts[1:]):
        gap = q["tStartMs"] - p["tEndMs"]
        timing_ok = timing_ok and p["tEndMs"] > p["tStartMs"] and 0 <= gap <= REST_MAX[p["after"]["rest"]]
    check("C12", timing_ok and st["durationMs"] == MATCH_MS,
          "54:00 from first serve to last point; no overlaps; gaps within ITF rest ceilings")
    check("C13", (A["totalPointsWon"]["pct"], A["firstServeIn"]["pct"], A["firstServePointsWon"]["pct"]) == (58, 67, 70),
          "58%, 67%, 70% via pct() on integer counts")
    check("C14", st["review"]["reviewed"] == 116 and st["review"]["needsReview"] == 8
          and st["review"]["completion"]["pct"] == 94, "116 reviewed + 8 flagged = 124; 116/124 -> 94%")
    p42 = pts[POINT_42]
    check("C15", p42["set"] == 0 and p42["game"] == 7 and p42["before"]["games"] == {"A": 4, "B": 3}
          and p42["before"]["points"] == {"A": 2, "B": 1} and p42["server"] == ALEX and p42["strokeCount"] == 8
          and p42["reviewState"] == "needsReview",
          "point 42: set 1 game 8, 4-3, Jon 30-15, Alex serving, 8 shots, needs review",
          "soft",
          waived=[{
              "clause": "starts at 766 s (12:46)",
              "decision": "D4",
              "reason": "12:46 is an illustrative moment on the synthetic sample video's clock (D8); the session has "
                        "no media and keeps even pacing",
              "observed": f"tStartMs {p42['tStartMs']} ({p42['tStartMs'] // 60000}:"
                          f"{p42['tStartMs'] % 60000 // 1000:02d}.{p42['tStartMs'] % 1000 // 100})",
              "met": p42["tStartMs"] == 766000,
          }])
    check("C16", not any(d["key"].startswith("serve") for d in session["derivedValues"]),
          "no serve speed derived from this match (104 mph belongs to a separate estimated serve subset)", "soft")
    return out


def write(out, write_json, version) -> int:
    session, fixture_input = build()
    result = scoring.fold(fixture_input, fixture_input["log"])
    st = stats.compute(result)
    checks = constraints(session, result, st)
    failed = [c for c in checks if c["status"] == "fail"]
    if failed:
        raise SystemExit(f"sample match violates {failed}")
    A = st["sides"]["A"]
    overview = {  # screen 9, hand-copied from the brief; validate.py compares them with the engine
        "scoreline": "6-4 6-3",
        "durationMs": MATCH_MS,
        "points": 124,
        "pointsWon": {"n": 72, "d": 124, "pct": 58, "display": "58%"},
        "firstServeIn": {"n": 40, "d": 60, "pct": 67, "display": "67%"},
        "firstServePointsWon": {"n": 28, "d": 40, "pct": 70, "display": "70%"},
        "shots": 386,
        "reviewed": 116,
        "flagged": 8,
        "reviewCompletion": {"n": 116, "d": 124, "pct": 94, "display": "94%"},
    }
    engine_overview = {
        "scoreline": result["match"]["scoreline"],
        "durationMs": st["durationMs"],
        "points": result["match"]["pointsPlayed"],
        "pointsWon": A["totalPointsWon"],
        "firstServeIn": A["firstServeIn"],
        "firstServePointsWon": A["firstServePointsWon"],
        "shots": st["shots"]["total"],
        "reviewed": st["review"]["reviewed"],
        "flagged": st["review"]["needsReview"],
        "reviewCompletion": st["review"]["completion"],
    }
    if engine_overview != overview:
        raise SystemExit(f"sample overview mismatch: {engine_overview}")
    write_json(out / "jon-vs-alex.session.json", session)
    (out / "jon-vs-alex.points.csv").write_text(csv_export.points_csv(fixture_input, result), encoding="utf-8")
    (out / "jon-vs-alex.stats.csv").write_text(csv_export.stats_csv(fixture_input, st), encoding="utf-8")
    write_json(out / "jon-vs-alex.expected.json", {
        "schemaVersion": version,
        "kind": "jovra.fixture.sample",
        "id": "SAMPLE-jon-vs-alex",
        "title": "Jon beats Alex 6-4 6-3: the coherent 124-point sample match (Sample, synthetic)",
        "covers": ["§8 constraints C1-C16", "screen 9 Match overview", "screen 16 review completion"],
        "sessionFile": "jon-vs-alex.session.json",
        "csv": {"points": "jon-vs-alex.points.csv", "stats": "jon-vs-alex.stats.csv"},
        "seed": SEED,
        "overview": overview,
        "constraints": checks,
        "expected": {"fold": result, "stats": st},
    })
    return 1


# ----- the sample library (T09) ---------------------------------------------------------------------
# The demo library every sample screen reads (screens.md §0.6): Jon vs Alex plus seven more sessions between
# Sep 9 and Oct 6, 2026, the sample equipment (one Head Prestige string job dated Sep 9, linked to all eight)
# and the sample practice plan. The library oracle (count, minutes, weekly pooled first serves, string-job
# links) is computed below from these documents, then checked against the brief's literals. Nothing under
# spec/fixtures/sample outside library/ is touched: the library carries its own copy of Jon vs Alex whose match
# log is the shipped fixture's, plus the library fields (schema 1.2.0, sample.mediaIds, the Sep 9 string-job
# link and the demo archive state).

LIBRARY_GENERATOR = "sample:library@1.0.0"
LIBRARY_SCHEMA = "1.2.0"
LIBRARY_UPDATED_AT = "2026-10-07T01:30:00Z"
TIME_ZONE = "America/Chicago"
STRING_JOB_NAME = "stringJob/2026-09-09"
SETUP_LABEL = "Head Prestige · Hyper-G 52 / Ghost Wire 50 lb"
WINDOW_DAYS = 28
LIBRARY_ORACLE = {  # the brief's literals (screens.md §0.6); the computed oracle must equal them
    "sessionCount": 8, "totalMinutes": 402, "olderMinutes": 288,
    "weeklyFirstServeIn": [(24, 50), (33, 60), (38, 60), (40, 60)], "delta": "+4 percentage points",
}
OPPONENTS = {
    "alex": ALEX,
    "sam": uid("player/sam"),
    "chris": uid("player/chris"),
}
# slug (as in the sample media manifest), date, local start, kind, title, minutes, and for matches: opponent
# key, the side that wins, Jon's service points, Jon's first serves in and the pinned seed (the first seed from
# 1 whose fold gives that winner and that many Jon service points: find_seed(); _older_match asserts both).
OLDER_SESSIONS = [
    ("2026-09-28-match", "2026-09-28", "17:30", "match", "Jon vs Chris", 63,
     {"opponent": "chris", "winner": "A", "servicePoints": 60, "firstServesIn": 38, "seed": 396}),
    ("2026-09-21-serve-practice", "2026-09-21", "08:00", "servePractice", "Serve practice", 55, None),
    ("2026-09-17-match", "2026-09-17", "18:00", "match", "Jon vs Alex", 58,
     {"opponent": "alex", "winner": "B", "servicePoints": 60, "firstServesIn": 33, "seed": 42}),
    ("2026-09-13-stroke-practice", "2026-09-13", "09:00", "strokePractice", "Stroke practice", 60, None),
    ("2026-09-09-match", "2026-09-09", "18:00", "match", "Jon vs Sam", 52,
     {"opponent": "sam", "winner": "A", "servicePoints": 50, "firstServesIn": 24, "seed": 131}),
]
RECENT_PRACTICE = [
    ("2026-10-04-serve-practice", "2026-10-04", "08:30", "servePractice", "Serve practice", 22, "notStarted",
     {"state": "queued", "provider": "googleDrive"}),
    ("2026-10-02-forehand-session", "2026-10-02", "17:00", "strokePractice", "Forehand session", 38, "inProgress",
     {"state": "failed", "provider": "googleDrive", "lastError": "Sample: the upload stopped. Retry backup."}),
]
OPPONENT_NAMES = {"alex": "Alex", "sam": "Sam", "chris": "Chris"}
SECOND_FAULT_PER_10 = 3  # of lost second-serve points, about 3 in 10 are double faults
OPPONENT_FIRST_IN_PER_100 = 60


def _utc(date: str, local: str) -> str:
    """Local wall time in America/Chicago (CDT, UTC-5, for every sample date) as a UTC timestamp."""
    hour, minute = (int(x) for x in local.split(":"))
    from datetime import datetime, timedelta, timezone
    t = datetime.fromisoformat(f"{date}T{hour:02d}:{minute:02d}:00") + timedelta(hours=5)
    return t.replace(tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _plus_ms(stamp: str, ms: int) -> str:
    from datetime import datetime, timedelta
    t = datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ") + timedelta(milliseconds=ms)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def _equipment_use(slug: str | None, minutes: int) -> dict:
    return {
        "id": uid(f"{slug}/equipmentUse/jon") if slug else uid("equipmentUse/jon"),
        "playerId": JON,
        "racketId": uid("racket/head-prestige"),
        "stringJobId": uid(STRING_JOB_NAME),
        "setupLabelSnapshot": SETUP_LABEL,
        "activeMinutes": minutes,
        "source": "manualLog",
    }


def _sample(media_ids: list[str], seed: int | None = None) -> dict:
    generator = LIBRARY_GENERATOR if seed is None else f"{LIBRARY_GENERATOR} seed {seed}"
    return {"label": "Sample", "synthetic": True, "generator": generator, "mediaIds": media_ids}


def _fold_winners(s: dict, won_by: str) -> dict:
    probe = LogBuilder()
    probe.points(won_by)
    return scoring.fold(s, probe.events)


def _match_winners(seed: int, s: dict) -> str:
    """A complete match from the seed: random point winners, cut at the point that wins the match."""
    rng = SplitMix64(seed)
    won_by = "".join("A" if rng.below(100) < 50 else "B" for _ in range(400))
    result = _fold_winners(s, won_by)
    end = next(i for i, p in enumerate(result["points"]) if p["after"]["matchWon"])
    return won_by[: end + 1]


def find_seed(s: dict, winner: str, service_points: int) -> int:
    """Re-pins a seed after a deliberate change to the match plan (run by hand, never at generation time)."""
    for seed in range(1, 5000):
        won_by = _match_winners(seed, s)
        result = _fold_winners(s, won_by)
        jon = sum(1 for p in result["points"] if p["serverSide"] == "A")
        if result["match"]["winner"] == winner and jon == service_points:
            return seed
    raise AssertionError("no seed")


def _older_setup(opponent: str) -> dict:
    s = setup()
    s["players"] = [s["players"][0], {"id": OPPONENTS[opponent], "displayName": OPPONENT_NAMES[opponent],
                                      "handedness": "right" if opponent != "sam" else "left",
                                      "backhand": "oneHanded" if opponent == "alex" else "twoHanded",
                                      "isSelf": False}]
    s["sides"] = {"A": [JON], "B": [OPPONENTS[opponent]]}
    return s


def _older_match(slug: str, plan: dict, total_ms: int) -> tuple[dict, list[dict], int]:
    """(setup, point log, seed) for one older singles match: every point reviewed, no lets, aces or placements."""
    s = _older_setup(plan["opponent"])
    seed = plan["seed"]
    won_by = _match_winners(seed, s)
    base = _fold_winners(s, won_by)
    servers = [p["serverSide"] for p in base["points"]]
    assert base["match"]["winner"] == plan["winner"]
    assert servers.count("A") == plan["servicePoints"]
    rng = SplitMix64(seed ^ 0x5A17)
    jon_points = [i for i, side in enumerate(servers) if side == "A"]
    first_in = set(rng.shuffled(jon_points)[: plan["firstServesIn"]])
    serves, counts, ends = [], [], []
    for i, side in enumerate(servers):
        receiver = "B" if side == "A" else "A"
        if side == "A":
            first = i in first_in
        else:
            first = rng.below(100) < OPPONENT_FIRST_IN_PER_100
        double_fault = not first and won_by[i] == receiver and rng.below(10) < SECOND_FAULT_PER_10
        if first:
            attempts = [{"result": "in"}]
        elif double_fault:
            attempts = [_fault(rng), _fault(rng)]
        else:
            attempts = [_fault(rng), {"result": "in"}]
        n = 0 if double_fault else rng.weighted(STROKE_WEIGHTS)
        if double_fault:
            end = "doubleFault"
        else:
            last_hitter = side if n % 2 == 1 else receiver
            end = "winner" if last_hitter == won_by[i] else ("forcedError" if rng.below(10) < 4 else "unforcedError")
        serves.append(attempts)
        counts.append(n)
        ends.append(end)
    durations = _durations(rng, serves, counts)
    rests = [p["after"]["rest"] for p in base["points"]]
    gaps = _gaps(rng, rests, durations, total_ms)
    log, t = [], 0
    for i in range(len(won_by)):
        start, end_ms = t, t + durations[i]
        t = end_ms + (gaps[i] if i < len(gaps) else 0)
        log.append({
            "id": uid(f"{slug}/point/{i + 1}"), "seq": i + 1, "type": "point",
            "recordedServer": base["points"][i]["server"], "tStartMs": start, "tEndMs": end_ms,
            "reviewed": {"winner": won_by[i], "endType": ends[i], "serves": serves[i], "strokeCount": counts[i],
                         "provenance": "reviewed", "source": "user"},
            "reviewState": "reviewed",
        })
    assert log[-1]["tEndMs"] == total_ms
    for p, q, rest in zip(log, log[1:], rests):
        gap = q["tStartMs"] - p["tEndMs"]
        assert 0 <= gap <= REST_MAX[rest], f"{slug}: a {rest} rest of {gap} ms"
    return s, log, seed


def _session_shell(slug: str, date: str, local: str, kind: str, title: str, minutes: int, media_ids: list[str],
                   archive: dict, review: str, seed: int | None = None) -> dict:
    started = _utc(date, local)
    duration = minutes * 60_000
    doc = {
        "schemaVersion": LIBRARY_SCHEMA, "kind": "jovra.session", "id": uid(f"session/{slug}"), "sport": "tennis",
        "createdAt": started, "updatedAt": _plus_ms(started, duration + 30 * 60_000), "title": title,
        "sample": _sample(media_ids, seed), "sessionKind": kind,
        "players": [setup()["players"][0]],
        "recording": {"mode": "none", "startedAt": started, "timeZone": TIME_ZONE, "durationMs": duration,
                      "segments": [], "gaps": [], "microphone": "notRequested", "mediaAvailable": False},
        "marks": [], "shots": [], "calibrations": [], "annotations": [], "voiceNotes": [], "comparisons": [],
        "derivedValues": [], "analysis": {"state": "notRequested", "runs": []},
        "review": {"state": review, "updatedAt": _plus_ms(started, duration + 30 * 60_000)},
        "archive": archive, "storage": {"originals": "none", "includeInDeviceBackup": False},
        "equipmentUse": [_equipment_use(slug, minutes)],
        "consent": {"status": "informed", "competitionMode": False},
    }
    if kind == "strokePractice":
        doc["capturePurpose"] = "sideOnTechnique"
    return doc


def _media_ids(manifest: dict, session_id: str) -> list[str]:
    ids = [m["mediaId"] for m in manifest["media"] if m["sessionId"] == session_id]
    assert ids, f"no sample media for session {session_id}"
    return ids


def library_sessions(manifest: dict) -> list[tuple[str, dict]]:
    """(slug, session document) for all eight sample sessions, newest first."""
    jon_vs_alex, _ = build()
    jon_vs_alex = copy.deepcopy(jon_vs_alex)
    jon_vs_alex["schemaVersion"] = LIBRARY_SCHEMA
    jon_vs_alex["sample"]["mediaIds"] = _media_ids(manifest, jon_vs_alex["id"])
    jon_vs_alex["archive"] = {"state": "uploading", "provider": "googleDrive"}
    jon_vs_alex["equipmentUse"] = [_equipment_use(None, MATCH_MS // 60_000)]
    out = [("jon-vs-alex", jon_vs_alex)]
    for slug, date, local, kind, title, minutes, review, archive in RECENT_PRACTICE:
        sid = uid(f"session/{slug}")
        out.append((slug, _session_shell(slug, date, local, kind, title, minutes, _media_ids(manifest, sid),
                                         archive, review)))
    for slug, date, local, kind, title, minutes, plan in OLDER_SESSIONS:
        sid = uid(f"session/{slug}")
        started = _utc(date, local)
        archive = {"state": "backedUp", "provider": "googleDrive",
                   "backedUpAt": _plus_ms(started, (minutes + 120) * 60_000)}
        if plan is None:
            out.append((slug, _session_shell(slug, date, local, kind, title, minutes, _media_ids(manifest, sid),
                                             archive, "complete")))
            continue
        s, log, seed = _older_match(slug, plan, minutes * 60_000)
        doc = _session_shell(slug, date, local, kind, title, minutes, _media_ids(manifest, sid), archive,
                             "complete", seed)
        doc["capturePurpose"] = "match"
        doc["players"] = s["players"]
        doc["sides"] = s["sides"]
        doc["match"] = {"format": s["format"], "toss": s["toss"], "log": log}
        out.append((slug, doc))
    return out


def library_equipment(base: dict) -> dict:
    """The library's equipment: the records example's user-entered text, restrung on Sep 9 (6h 42m ago)."""
    doc = copy.deepcopy(base)
    stamp = "2026-09-09T17:00:00Z"
    for key in ("frameModels", "rackets", "stringProducts", "stringInventory", "stringJobs", "setupRatings"):
        for entity in doc.get(key, []):
            entity["createdAt"] = entity["updatedAt"] = stamp
    old_job = doc["stringJobs"][0]["id"]
    assert len(doc["stringJobs"]) == 1
    doc["stringJobs"][0].update({"id": uid(STRING_JOB_NAME), "strungOn": "2026-09-09"})
    for rating in doc.get("setupRatings", []):
        assert rating["stringJobId"] == old_job
        rating["stringJobId"] = uid(STRING_JOB_NAME)
    doc["updatedAt"] = LIBRARY_UPDATED_AT
    return doc


def library_practice_plan(jon_vs_alex: dict) -> dict:
    """Screen 15's sample plan: one focus from Jon vs Alex (28 of 40 first-serve points won), three serve drills."""
    first_serve_points = [e["id"] for e in jon_vs_alex["match"]["log"] if e["recordedServer"] == JON
                          and [a["result"] for a in e["reviewed"]["serves"] if a["result"] != "let"][0] == "in"]
    assert len(first_serve_points) == 40
    evidence = [{
        "sessionId": jon_vs_alex["id"], "stat": "firstServePointsWon", "side": "A",
        "value": {"n": 28, "d": 40, "pct": 70, "display": "70%"}, "text": "28 of 40 first-serve points won",
        "pointIds": first_serve_points,
        "provenance": {"status": "reviewed", "source": "rule:practice.firstServePointsWon@1.0.0", "denominator": 40,
                       "sample": True},
        "availability": "available",
    }]
    origin = {"kind": "rule", "ruleId": "practice.firstServePointsWon", "ruleVersion": "1.0.0",
              "condition": "firstServePointsWon.pct < 75 over at least 30 service points"}
    drills = [
        ("toss", "Toss consistency", 8, 3, 10,
         "Toss without hitting and let the ball land on a racket laid in front of your front foot. Three sets of "
         "ten; a toss that misses the strings starts the set again."),
        ("wide", "Wide serve targets", 12, None, None,
         "Hit first serves to wide targets on both sides, deuce and ad. Focus on placement and margin over the "
         "net."),
        ("first-ball", "Serve + first ball", 15, None, None,
         "With a partner: serve, then play the first ball after the return into the open court. Count the points "
         "you finish within your first two shots."),
    ]
    items = []
    for key, title, minutes, sets, reps, text in drills:
        drill = {"title": title, "instructions": text, "durationMinutes": minutes}
        if sets is not None:
            drill.update({"sets": sets, "reps": reps})
        items.append({"id": uid(f"library/plan/{key}"), "focus": "A steadier first serve", "drill": drill,
                      "origin": origin, "evidence": evidence, "status": "planned", "userEdited": False})
    return {
        "schemaVersion": "1.1.0", "kind": "jovra.practicePlan", "id": uid("library/plan"),
        "createdAt": LIBRARY_UPDATED_AT, "updatedAt": LIBRARY_UPDATED_AT, "title": "This week: a steadier first serve",
        "label": "Suggested practice", "sample": True, "playerId": JON, "basedOnSessions": [jon_vs_alex["id"]],
        "items": items,
        "goals": [{"id": uid("library/goal/first-serve"), "stat": "firstServeIn", "target": 70,
                   "sessionKind": "match", "window": "fourWeeks", "createdAt": LIBRARY_UPDATED_AT}],
    }


def _local_date(doc: dict) -> str:
    from datetime import datetime
    from zoneinfo import ZoneInfo
    rec = doc["recording"]
    t = datetime.strptime(rec["startedAt"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=ZoneInfo("UTC"))
    return t.astimezone(ZoneInfo(rec["timeZone"])).date().isoformat()


def _self_side(doc: dict) -> str:
    me = next(p["id"] for p in doc["players"] if p["isSelf"])
    return "A" if me in doc["sides"]["A"] else "B"


def library_summary(sessions: list[dict], equipment: dict) -> dict:
    """The library oracle, computed the way the Swift LibrarySummary computes it (all-sample scope)."""
    from datetime import date, timedelta
    dates = {d["id"]: _local_date(d) for d in sessions}
    end = date.fromisoformat(max(dates.values()))
    start = end - timedelta(days=WINDOW_DAYS - 1)
    weeks = []
    for w in range(WINDOW_DAYS // 7):
        lo, hi = start + timedelta(days=7 * w), start + timedelta(days=7 * w + 6)
        n = d = 0
        ids = []
        for doc in sorted(sessions, key=lambda x: (dates[x["id"]], x["id"])):
            if doc["sessionKind"] != "match" or not lo <= date.fromisoformat(dates[doc["id"]]) <= hi:
                continue
            inp = {**{k: doc["match"][k] for k in ("format", "toss")}, "players": doc["players"],
                   "sides": doc["sides"], "log": doc["match"]["log"]}
            fraction = stats.compute(scoring.fold(inp, inp["log"]))["sides"][_self_side(doc)]["firstServeIn"]
            n, d = n + fraction["n"], d + fraction["d"]
            ids.append(doc["id"])
        pct = stats.pct(n, d) if d else None
        weeks.append({"week": w + 1, "from": lo.isoformat(), "to": hi.isoformat(), "sessionIds": ids,
                      "value": {"n": n, "d": d, "pct": pct, "display": f"{pct}%" if pct is not None else "—"}})
    jobs = []
    for job in equipment["stringJobs"]:
        linked = sorted(doc["id"] for doc in sessions
                        if any(u.get("stringJobId") == job["id"] for u in doc.get("equipmentUse", [])))
        ms = sum(doc["recording"]["durationMs"] for doc in sessions if doc["id"] in linked)
        jobs.append({"id": job["id"], "strungOn": job["strungOn"], "linkedSessionIds": linked,
                     "loggedMinutes": (ms + 30_000) // 60_000})
    last, prior = weeks[-1]["value"], weeks[-2]["value"]
    delta = last["pct"] - prior["pct"]
    rows = []
    for doc in sorted(sessions, key=lambda x: (dates[x["id"]], x["id"]), reverse=True):
        scoreline = None
        if "match" in doc:
            inp = {**{k: doc["match"][k] for k in ("format", "toss")}, "players": doc["players"],
                   "sides": doc["sides"], "log": doc["match"]["log"]}
            scoreline = scoring.fold(inp, inp["log"])["match"]["scoreline"]
        rows.append({"id": doc["id"], "title": doc["title"], "date": dates[doc["id"]], "kind": doc["sessionKind"],
                     "minutes": doc["recording"]["durationMs"] // 60_000, "mediaIds": doc["sample"]["mediaIds"],
                     "scoreline": scoreline})
    total_ms = sum(doc["recording"]["durationMs"] for doc in sessions)
    return {
        "sample": True,
        "sessionCount": len(sessions),
        "totalMinutes": (total_ms + 30_000) // 60_000,
        "window": {"from": start.isoformat(), "to": end.isoformat()},
        "weeklyFirstServeIn": weeks,
        "firstServeInDelta": f"{'+' if delta > 0 else ''}{delta} percentage point{'' if abs(delta) == 1 else 's'}",
        "stringJobs": jobs,
        "sessions": rows,
    }


def _check_library(summary: dict, sessions: list[dict], shipped: dict) -> None:
    o = LIBRARY_ORACLE
    assert summary["sessionCount"] == o["sessionCount"], summary["sessionCount"]
    assert summary["totalMinutes"] == o["totalMinutes"], summary["totalMinutes"]
    older = [d for d in sessions if _local_date(d) < "2026-09-30"]
    assert len(older) == 5 and sum(1 for d in older if d["sessionKind"] == "match") == 3
    assert sum(d["recording"]["durationMs"] for d in older) == o["olderMinutes"] * 60_000
    got = [(w["value"]["n"], w["value"]["d"]) for w in summary["weeklyFirstServeIn"]]
    assert got == o["weeklyFirstServeIn"], got
    assert [w["value"]["pct"] for w in summary["weeklyFirstServeIn"]] == [48, 55, 63, 67]
    assert all(len(w["sessionIds"]) == 1 for w in summary["weeklyFirstServeIn"]), "one singles match per week"
    assert summary["firstServeInDelta"] == o["delta"]
    (job,) = summary["stringJobs"]
    assert job["strungOn"] == "2026-09-09" and len(job["linkedSessionIds"]) == 8 and job["loggedMinutes"] == 402
    library_jva = next(d for d in sessions if d["id"] == shipped["id"])
    assert library_jva["match"] == shipped["match"], "the library's Jon vs Alex must keep the shipped match log"
    differs = sorted(k for k in set(library_jva) | set(shipped) if library_jva.get(k) != shipped.get(k))
    assert differs == ["archive", "equipmentUse", "sample", "schemaVersion"], differs
    for doc in sessions:
        if "match" in doc:
            inp = {**{k: doc["match"][k] for k in ("format", "toss")}, "players": doc["players"],
                   "sides": doc["sides"], "log": doc["match"]["log"]}
            result = scoring.fold(inp, inp["log"])
            assert result["match"]["status"] == "completed" and not result["conflicts"], (doc["title"], result["conflicts"])


def write_library(out, write_json, manifest: dict, equipment_base: dict) -> int:
    """Writes spec/fixtures/sample/library: eight sessions, equipment, practice plan and the library oracle."""
    shipped, _ = build()
    pairs = library_sessions(manifest)
    sessions = [doc for _, doc in pairs]
    equipment = library_equipment(equipment_base)
    plan = library_practice_plan(sessions[0])
    summary = library_summary(sessions, equipment)
    _check_library(summary, sessions, shipped)
    for slug, doc in pairs:
        write_json(out / "sessions" / f"{slug}.session.json", doc)
    write_json(out / "equipment.json", equipment)
    write_json(out / "practice-plan.json", plan)
    seeds = {"jon-vs-alex": SEED, **{row[0]: row[6]["seed"] for row in OLDER_SESSIONS if row[6] is not None}}
    write_json(out / "library.expected.json", {
        "schemaVersion": "1.0.0",
        "kind": "jovra.fixture.sampleLibrary",
        "id": "SAMPLE-library",
        "title": "The sample library: eight Sample sessions (402 min), the Sep 9 string job and the practice plan",
        "covers": ["screens.md §0.6 sample library rows", "screen 3 Home tiles", "screen 8 Session library",
                   "screen 15 Practice plan", "screen 16 Progress trends", "screen 18 String journal",
                   "the sample-scope rule"],
        "sessionFiles": [f"sessions/{slug}.session.json" for slug, _ in pairs],
        "equipmentFile": "equipment.json",
        "practicePlanFile": "practice-plan.json",
        "mediaManifest": "../media-manifest.json",
        "seeds": seeds,
        "expected": summary,
    })
    return len(pairs) + 3
