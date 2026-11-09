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


# ----- the sample analysis content (T40) --------------------------------------------------------------
# Every number the Shot map, Serve Lab, Stroke Lab and Compare demo screens show is computed from these records,
# never typed into a view. They ship as one overlay per session under spec/fixtures/sample/analysis/sessions (so no
# byte of the library or the shipped match changes) and SampleContent applies them when it installs the library.
#
# Sources, in order of authority:
# * The rendered ground truth (spec/fixtures/media/sample/*.truth.json, T11): every hit, bounce, serve contact and
#   bounce frame and swing key moment comes from it. Calibration corners are the four singles corners projected
#   through the renderer's behind-baseline camera (scripts/media/jovra_media/sets/sample.py behind_baseline); the
#   generator then re-projects every rendered bounce and serve contact and refuses corners more than 1 px from the
#   truth's own pixels, so a renderer change cannot leave a stale calibration behind.
# * The shipped match log (who served, which serve went in, the stroke count) for stroke tags and placements.
# * The brief (screens.md §0.6): forehand placements 31 deep / 12 short / 7 out of 50 placed and "50 forehands of
#   133"; the rest of the brief's serve literals cannot be met by the rendered data and are recorded in the oracle's
#   `reference.brief` list with the computed value and why (see BRIEF below).
#
# Deterministic choices are pinned: ANALYSIS_SEED drives which shots the player placed, Alex's forehand/backhand
# tags, the out taps and the serve-mark offsets. A player jogging by hand marks contact on the true frame or the one
# before it (never after the ball has left the strings) and the bounce on the true frame or the one after it (the
# first frame they can see the ball down), so each offset is 0 or 1 frame and an estimate errs slow, never fast.
# Changing any of them changes the oracle.

from fractions import Fraction  # noqa: E402

ANALYSIS_GENERATOR = "sample:analysis@1.0.0"
ANALYSIS_SEED = 20261040
ANALYSIS_SLUGS = ("jon-vs-alex", "2026-10-04-serve-practice", "2026-10-02-forehand-session")
SINGLES_HALF_WIDTH = 4.115   # m, centre line to singles sideline (ITF)
SERVICE_LINE = 6.40          # m from the net
# Placement bins (S11): far-half landings beyond the service line are Deep, inside it Short; an Out tap is Out.
# Serve zones (S12): the receiver's box split into equal thirds from the centre service line: T, Body, Wide.
FOREHAND_PLAN = {"deep": 31, "short": 12, "out": 7}        # screens.md §0.6 / S11: 62% / 24% / 14% of 50
# S11 "50 forehands of 133" and "14 / 133 forehands": Jon hits exactly 133 shots after the serve in Jon vs Alex, so
# every one carries a forehand tag (he has no backhand tags in the sample; Alex's rally shots are a seeded mix).
FOREHAND_TAGGED = 133
# The brief's 13 / 8 / 4 of 25 deuce first serves cannot exist: Jon vs Alex has 20 deuce first serves in. The
# player placed the subset of the rendered deuce first serves whose split is nearest the brief's 52 / 32 / 16
# (7 / 4 / 2 of 13 reads 54 / 31 / 15); every ad first serve in is placed.
DEUCE_FIRST_SERVE_PLAN = {"wide": 7, "body": 4, "t": 2}
ALEX_FOREHAND_PER_100 = 58
COMPARISON_POINT = 47        # Jon's wide deuce first serve from the near end, like the Sep 28 clip's serve
COMPARISON_NOTE = "Keep the toss position consistent."
CAMERA_TOLERANCE_PX = 1.0
# The renderer's behind-baseline camera: eye 15 m behind the near baseline and 7.5 m up, aimed at the far service
# line (y 9 m from the near baseline), focal 1.05 x width. World metres: x across (+ to the near player's right),
# y from the near baseline, z up (scripts/media/jovra_media/court3d.py).
CAMERA_EYE, CAMERA_TARGET, CAMERA_FOCAL = (0.0, -15.0, 7.5), (0.0, 9.0, 0.0), 1.05
# The renderer's toss (play.py Play.toss): the ball leaves the hand 0.85 s before contact at 1.45 m, 0.15 m behind
# the contact point, and flies a ballistic arc to the contact at 2.75 m (G 9.81).
TOSS_LEAD_S, TOSS_RELEASE_Z, TOSS_BACK, CONTACT_Z, GRAVITY = 0.85, 1.45, 0.15, 2.75, 9.81
SWING_PAD_MS = 1000          # S13: the swing clip is -1.0 / +1.0 s around contact
BRIEF_SERVE = {"fastestMph": 104, "deuce": (13, 8, 4)}
MANUAL = {"status": "manual", "source": "user", "sample": True}
BASELINE_HALF = 11.885       # m from the net to a baseline


def _sec(t: dict) -> Fraction:
    return Fraction(t["value"], t["timescale"])


def _ms_half_up(seconds) -> int:
    return int((Fraction(seconds) * 1000 + Fraction(1, 2)) // 1)


def _frame_ms(frame: int, fps: int) -> Fraction:
    return Fraction(frame * 1000, fps)


def _swing_clip(contact_ms: Fraction) -> dict:
    """The padded swing clip around a contact, widened to whole milliseconds."""
    return {"fromMs": int(contact_ms // 1) - SWING_PAD_MS, "toMs": int(-(-contact_ms // 1)) + SWING_PAD_MS}


def _court(mm: dict) -> dict:
    """Ground-truth millimetres (origin the near baseline centre) as court metres (origin the net centre)."""
    return {"x": round(mm["x"] / 1000, 3), "y": round(mm["y"] / 1000 - BASELINE_HALF, 3)}


def _vec(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _unit(a):
    import math
    n = math.sqrt(_dot(a, a))
    return (a[0] / n, a[1] / n, a[2] / n)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def project(world: tuple, width: int, height: int) -> tuple[float, float]:
    """Pixel position of a world point (metres, renderer axes) in a width x height behind-baseline frame."""
    f = _unit(_vec(CAMERA_TARGET, CAMERA_EYE))
    r = _unit(_cross(f, (0.0, 0.0, 1.0)))
    u = _cross(r, f)
    d = _vec(world, CAMERA_EYE)
    z = _dot(d, f)
    focal = CAMERA_FOCAL * width
    return width / 2 + focal * _dot(d, r) / z, height / 2 - focal * _dot(d, u) / z


def _normalized(px: tuple, width: int, height: int) -> dict:
    return {"x": round(px[0] / width, 6), "y": round(px[1] / height, 6)}


def homography(court_points: list[dict], image_points: list[dict]) -> list[float]:
    """The 3x3 court-plane -> normalized-image homography through four point pairs (h33 = 1), row major."""
    rows, rhs = [], []
    for c, i in zip(court_points, image_points):
        X, Y, u, v = c["x"], c["y"], i["x"], i["y"]
        rows.append([X, Y, 1, 0, 0, 0, -u * X, -u * Y]); rhs.append(u)
        rows.append([0, 0, 0, X, Y, 1, -v * X, -v * Y]); rhs.append(v)
    n = 8
    m = [row[:] + [b] for row, b in zip(rows, rhs)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda k: abs(m[k][col]))
        m[col], m[pivot] = m[pivot], m[col]
        for k in range(n):
            if k != col:
                factor = m[k][col] / m[col][col]
                m[k] = [a - factor * b for a, b in zip(m[k], m[col])]
    return [m[k][n] / m[k][k] for k in range(n)] + [1.0]


def apply_homography(h: list[float], court: dict) -> tuple[float, float]:
    x, y = court["x"], court["y"]
    w = h[6] * x + h[7] * y + h[8]
    return (h[0] * x + h[1] * y + h[2]) / w, (h[3] * x + h[4] * y + h[5]) / w


SINGLES_CORNERS = [(-SINGLES_HALF_WIDTH, -BASELINE_HALF), (SINGLES_HALF_WIDTH, -BASELINE_HALF),
                   (SINGLES_HALF_WIDTH, BASELINE_HALF), (-SINGLES_HALF_WIDTH, BASELINE_HALF)]


def calibration(slug: str, frame_ms: int, media: dict) -> dict:
    """A 4-tap calibration on the singles corners as the renderer's camera sees them in that media."""
    w, h = media["width"], media["height"]
    court = [{"x": x, "y": y} for x, y in SINGLES_CORNERS]
    image = [_normalized(project((x, y + BASELINE_HALF, 0.0), w, h), w, h) for x, y in SINGLES_CORNERS]
    return {
        "id": uid(f"{slug}/calibration/1"), "method": "fourTap", "frameMs": frame_ms, "imagePoints": image,
        "courtPoints": court, "status": "valid",
        "camera": {"lens": "wide", "width": w, "height": h, "frameRate": media["frameRate"], "zoomFactor": "1.0"},
        "provenance": dict(MANUAL),
    }


def calibration_error_px(cal: dict, truth: dict) -> float:
    """Largest distance, in the truth's pixels, between a rendered bounce (and serve contact) and where the
    calibration (or, for contacts above the ground, the camera it was taken from) puts it."""
    import math
    w, h = truth["video"]["displayWidth"], truth["video"]["displayHeight"]
    hom = homography(cal["courtPoints"], cal["imagePoints"])
    worst = 0.0
    for serve in truth.get("serves", []):
        u, v = apply_homography(hom, _court(serve["bounce"]["courtMm"]))
        p = serve["bounce"]["pixel"]
        worst = max(worst, math.hypot(u * w - p["x"], v * h - p["y"]))
        c = serve["contact"]["courtMm"]
        cu, cv = project((c["x"] / 1000, c["y"] / 1000, c["z"] / 1000), w, h)
        q = serve["contact"]["pixel"]
        worst = max(worst, math.hypot(cu - q["x"], cv - q["y"]))
    return worst


def _ratio(n: int, d: int) -> dict:
    value = stats.pct(n, d)
    return {"n": n, "d": d, "pct": value, "display": f"{value}%" if value is not None else "—"}


def _media(manifest: dict, media_slug: str) -> dict:
    return next(m for m in manifest["media"] if m["mediaId"] == f"sample-media.{media_slug}")


def _bin(court: dict) -> str:
    return "deep" if abs(court["y"]) > SERVICE_LINE else "short"


def serve_zone(court: dict) -> str:
    third = abs(court["x"]) / SINGLES_HALF_WIDTH
    return "t" if third < 1 / 3 else ("body" if third < 2 / 3 else "wide")


def served_to(court: dict) -> str:
    """The receiver's box a serve landed in: the deuce box is the receiver's right, so x and y differ in sign."""
    return "deuce" if court["x"] * court["y"] < 0 else "ad"


def _match_hits(session: dict, truth: dict) -> list[dict]:
    """Per point of the match log: the fold's point, the rendered hit time of every shot and the rendered first
    bounce after each shot (faults are hits in the render but not shots; lets are not rendered)."""
    inp = {**{k: session["match"][k] for k in ("format", "toss")}, "players": session["players"],
           "sides": session["sides"], "log": session["match"]["log"]}
    points = scoring.fold(inp, inp["log"])["points"]
    hits = sorted(_sec(e["time"]) for e in truth["events"] if e["type"] == "hit")
    bounces = sorted(((_sec(b["time"]), b) for b in truth["bounces"]), key=lambda x: x[0])
    out = []
    for point, rally in zip(points, truth["rallies"]):
        assert rally["pointNumber"] == point["index"] + 1
        start, end = _sec(rally["start"]), _sec(rally["end"])
        rally_hits = [t for t in hits if start <= t <= end]
        n = point["strokeCount"]
        faults = point["serveNumber"] - 1 if n else 2
        assert len(rally_hits) == faults + n == rally["hits"], (point["index"], len(rally_hits), faults, n)
        shots = []
        for k in range(n):
            t = rally_hits[faults + k]
            nxt = rally_hits[faults + k + 1] if faults + k + 1 < len(rally_hits) else end + 10
            bounce = next(b for tb, b in bounces if t < tb < nxt)
            shots.append({"time": t, "bounce": _court(bounce["courtMm"])})
        out.append({"point": point, "shots": shots})
    return out


def _shot(slug: str, point: dict, k: int, hitter: str, stroke: str, t_ms: int, placement: dict | None) -> dict:
    shot = {"id": uid(f"{slug}/shot/{point['index'] + 1}/{k}"), "pointId": point["id"], "tMs": t_ms,
            "hitter": hitter, "shotIndex": k, "stroke": stroke}
    if placement is not None:
        shot["placement"] = placement
    shot["provenance"] = dict(MANUAL)
    return shot


def _out_tap(rng: SplitMix64, landed: dict) -> dict:
    """An Out tap for a shot the log says Jon missed: the render keeps every ball in play, so the tap lands past
    the baseline or the singles sideline of the half the rendered ball reached."""
    sign_y = 1 if landed["y"] > 0 else -1
    if rng.below(2) == 0:
        x = max(-3.9, min(3.9, landed["x"]))
        return {"x": round(x, 3), "y": round(sign_y * (BASELINE_HALF + 0.20 + rng.below(80) / 100), 3)}
    sign_x = 1 if landed["x"] >= 0 else -1
    y = sign_y * max(1.0, min(11.0, abs(landed["y"])))
    return {"x": round(sign_x * (SINGLES_HALF_WIDTH + 0.15 + rng.below(60) / 100), 3), "y": round(y, 3)}


def _line_distance(court: dict) -> float:
    return min(abs(BASELINE_HALF - abs(court["y"])), abs(SINGLES_HALF_WIDTH - abs(court["x"])))


def match_analysis(session: dict, truth: dict, media: dict) -> dict:
    """Jon vs Alex: a stroke tag on all 386 shots, 50 placed forehands of Jon's 133, Jon's first-serve placements,
    the match calibration and the Oct 6 vs Sep 28 comparison (added by analysis_records)."""
    slug = "jon-vs-alex"
    rng = SplitMix64(ANALYSIS_SEED)
    rows = _match_hits(session, truth)
    forehands, errors, deuce, ad = [], [], {"wide": [], "body": [], "t": []}, []
    for row in rows:
        p = row["point"]
        for k, shot in enumerate(row["shots"], start=1):
            hitter = p["server"] if k % 2 == 1 else p["receiver"]
            if hitter != JON:
                continue
            if k == 1:
                if p["serveNumber"] == 1:
                    (deuce[serve_zone(shot["bounce"])] if served_to(shot["bounce"]) == "deuce" else ad).append((p, k))
                continue
            jon_side = p["serverSide"] if p["server"] == JON else ("B" if p["serverSide"] == "A" else "A")
            last_and_lost = k == len(row["shots"]) and p["winner"] != jon_side
            if last_and_lost and p["endType"] in ("unforcedError", "forcedError"):
                errors.append((p, k))
            elif not last_and_lost:
                forehands.append((p, k, shot["bounce"]))
    tagged = sum(1 for row in rows for k in range(2, len(row["shots"]) + 1)
                 if (row["point"]["server"] if k % 2 == 1 else row["point"]["receiver"]) == JON)
    assert tagged == FOREHAND_TAGGED, tagged
    placed: dict[tuple, dict] = {}
    for zone in ("deep", "short"):
        pool = rng.shuffled([f for f in forehands if _bin(f[2]) == zone and abs(f[2]["x"]) <= SINGLES_HALF_WIDTH
                             and abs(f[2]["y"]) <= BASELINE_HALF])
        assert len(pool) >= FOREHAND_PLAN[zone], (zone, len(pool))
        for p, k, landed in pool[: FOREHAND_PLAN[zone]]:
            placed[(p["index"], k)] = {"court": landed, "inOut": "in"}
    unsure = min((key for key, v in placed.items() if _bin(v["court"]) == "deep"),
                 key=lambda key: (_line_distance(placed[key]["court"]), key))
    placed[unsure] = {**placed[unsure], "inOut": "needsReview"}
    assert len(errors) >= FOREHAND_PLAN["out"]
    landed_at = {(row["point"]["index"], k): s["bounce"] for row in rows for k, s in enumerate(row["shots"], 1)}
    for p, k in rng.shuffled(errors)[: FOREHAND_PLAN["out"]]:
        placed[(p["index"], k)] = {"court": _out_tap(rng, landed_at[(p["index"], k)]), "inOut": "out"}
    for zone, count in DEUCE_FIRST_SERVE_PLAN.items():
        assert len(deuce[zone]) >= count, (zone, len(deuce[zone]))
        for p, k in rng.shuffled(deuce[zone])[:count]:
            placed[(p["index"], k)] = {"court": landed_at[(p["index"], k)], "inOut": "in"}
    for p, k in ad:
        placed[(p["index"], k)] = {"court": landed_at[(p["index"], k)], "inOut": "in"}
    shots = []
    for row in rows:
        p = row["point"]
        for k, shot in enumerate(row["shots"], start=1):
            hitter = p["server"] if k % 2 == 1 else p["receiver"]
            if k == 1:
                stroke = "serve"
            elif hitter == JON:
                stroke = "forehand"
            else:
                stroke = "forehand" if rng.below(100) < ALEX_FOREHAND_PER_100 else "backhand"
            shots.append(_shot(slug, p, k, hitter, stroke, _ms_half_up(shot["time"]), placed.get((p["index"], k))))
    assert len(shots) == SHOTS
    return {"shots": shots, "calibrations": [calibration(slug, 0, media)], "serveMarks": [], "swings": [],
            "comparisons": []}


def _toss_peak(contact_s, contact_mm: dict, fps: int) -> tuple[int, tuple]:
    """The frame the toss is highest (the player's mark) and the ball's world position on that frame."""
    lead = Fraction(TOSS_LEAD_S).limit_denominator(1000)
    rise = (CONTACT_Z - TOSS_RELEASE_Z + GRAVITY / 2 * float(lead) ** 2) / float(lead)
    peak_s = float(contact_s - lead) + rise / GRAVITY
    frame = int(peak_s * fps + 0.5)
    u = frame / fps - float(contact_s - lead)
    x, y_contact = contact_mm["x"] / 1000, contact_mm["y"] / 1000
    y0 = y_contact - TOSS_BACK
    k = u / float(lead)
    z = TOSS_RELEASE_Z + rise * u - GRAVITY / 2 * u * u
    return frame, (x, y0 + (y_contact - y0) * k, z)


def serve_practice_analysis(truth: dict, media: dict) -> tuple[dict, list[dict]]:
    """Oct 4: the calibration on the 12-serve clip, 12 complete serve marks (true frames with pinned -1/0/+1
    offsets) and one serve swing per mark with its contact and marked toss peak. Returns the record and, per mark,
    its truth frames and offsets for the oracle."""
    slug = "2026-10-04-serve-practice"
    rng = SplitMix64(ANALYSIS_SEED ^ 0x5E4E)
    fps = media["frameRate"]["num"] // media["frameRate"]["den"]
    base_frames = media["coversSessionMs"]["fromMs"] * fps // 1000
    cal = calibration(slug, media["coversSessionMs"]["fromMs"], media)
    w, h = media["width"], media["height"]
    marks, swings, audit = [], [], []
    for serve in truth["serves"]:
        k = serve["index"] + 1
        contact_off, bounce_off = -rng.below(2), rng.below(2)
        contact = {"value": base_frames + serve["contact"]["frame"] + contact_off, "timescale": fps}
        bounce = {"value": base_frames + serve["bounce"]["frame"] + bounce_off, "timescale": fps}
        c = serve["contact"]["courtMm"]
        mark = {
            "id": uid(f"{slug}/serveMark/{k}"), "contactFrame": contact, "bounceFrame": bounce,
            "bounceCourt": _court(serve["bounce"]["courtMm"]),
            "bounceImage": _normalized((serve["bounce"]["pixel"]["x"], serve["bounce"]["pixel"]["y"]),
                                       truth["video"]["displayWidth"], truth["video"]["displayHeight"]),
            "serverPosition": _court({"x": c["x"], "y": c["y"]}), "contactDefaulted": False,
            "servedTo": serve["side"], "calibrationId": cal["id"], "provenance": dict(MANUAL),
        }
        assert served_to(mark["bounceCourt"]) == serve["side"]
        marks.append(mark)
        peak_frame, peak_world = _toss_peak(_sec(serve["contact"]["time"]), c, fps)
        peak = {"value": base_frames + peak_frame, "timescale": fps}
        swings.append({
            "id": uid(f"{slug}/swing/{k}"), "kind": "serve", "stroke": "serve", "serveMarkId": mark["id"],
            "clip": _swing_clip(_sec(contact) * 1000),
            "keyMoments": [
                {"name": "tossPeak", "time": peak, "imagePoint": _normalized(project(peak_world, w, h), w, h),
                 "provenance": dict(MANUAL)},
                {"name": "contact", "time": contact, "provenance": dict(MANUAL)},
            ],
        })
        audit.append({"serveMarkId": mark["id"], "truthServe": serve["index"],
                      "truthFrames": {"contact": serve["contact"]["frame"], "bounce": serve["bounce"]["frame"]},
                      "offsetFrames": {"contact": contact_off, "bounce": bounce_off}})
    return {"shots": [], "calibrations": [cal], "serveMarks": marks, "swings": swings, "comparisons": []}, audit


def forehand_analysis(truth: dict, media: dict) -> dict:
    """Oct 2: one forehand stroke tag and one studied swing per rendered side-on forehand, with the five key
    moments (Ready, Unit turn, Racket drop, Contact, Finish) on the renderer's frames."""
    slug = "2026-10-02-forehand-session"
    fps = media["frameRate"]["num"] // media["frameRate"]["den"]
    base_frames = media["coversSessionMs"]["fromMs"] * fps // 1000
    shots, swings = [], []
    for swing in truth["swings"]:
        k = swing["index"] + 1
        moments = swing["keyMoments"]
        contact_ms = media["coversSessionMs"]["fromMs"] + _frame_ms(moments["contact"]["frame"], fps)
        shot_id = uid(f"{slug}/shot/{k}")
        shots.append({"id": shot_id, "tMs": _ms_half_up(contact_ms / 1000), "hitter": JON, "stroke": "forehand",
                      "provenance": dict(MANUAL)})
        swings.append({
            "id": uid(f"{slug}/swing/{k}"), "kind": "stroke", "stroke": "forehand", "shotId": shot_id,
            "clip": _swing_clip(contact_ms),
            "keyMoments": [{"name": name, "time": {"value": base_frames + moments[name]["frame"], "timescale": fps},
                            "provenance": dict(MANUAL)}
                           for name in ("ready", "unitTurn", "racketDrop", "contact", "finish")],
        })
    return {"shots": shots, "calibrations": [], "serveMarks": [], "swings": swings, "comparisons": []}


def comparison(match_record: dict, truths: dict, manifest: dict) -> dict:
    """Compare (S14): Jon's wide deuce first serve on Oct 6 against the Sep 28 serve clip, synced at contact."""
    serve = next(s for s in match_record["shots"] if s["shotIndex"] == 1
                 and s["pointId"] == uid_point(COMPARISON_POINT))
    clip = _media(manifest, "2026-09-28-serve-clip")
    clip_truth = truths["2026-09-28-serve-clip"]
    (contact,) = [s["contact"] for s in clip_truth["serves"]]
    right_ms = clip["coversSessionMs"]["fromMs"] + _ms_half_up(_sec(contact["time"]))
    return {
        "id": uid("jon-vs-alex/comparison/sep-28-serve"), "title": "Serve · Oct 6 and Sep 28",
        "left": {"sessionId": uid("session/jon-vs-alex"), "syncTimeMs": serve["tMs"]},
        "right": {"sessionId": clip["sessionId"], "syncTimeMs": right_ms},
        "syncedAt": "contact", "createdAt": LIBRARY_UPDATED_AT, "note": COMPARISON_NOTE,
    }


def uid_point(number: int) -> str:
    shipped, _ = build()
    return [e for e in shipped["match"]["log"] if e["type"] == "point"][number - 1]["id"]


def analysis_records(sessions: dict, truths: dict, manifest: dict) -> tuple[dict, list[dict]]:
    """(slug -> overlay record, serve-mark audit) for the three sessions the lab screens read."""
    jva = sessions["jon-vs-alex"]
    assert jva["id"] == uid("session/jon-vs-alex")
    match = match_analysis(jva, truths["jon-vs-alex"], _media(manifest, "jon-vs-alex"))
    match["comparisons"] = [comparison(match, truths, manifest)]
    serves, audit = serve_practice_analysis(truths["2026-10-04-behind-baseline-12-serves"],
                                            _media(manifest, "2026-10-04-behind-baseline-12-serves"))
    forehand = forehand_analysis(truths["2026-10-02-side-on-forehands"],
                                 _media(manifest, "2026-10-02-side-on-forehands"))
    records = {}
    for slug, body in (("jon-vs-alex", match), ("2026-10-04-serve-practice", serves),
                       ("2026-10-02-forehand-session", forehand)):
        records[slug] = {"schemaVersion": "1.0.0", "kind": "jovra.sampleAnalysis", "sessionId": sessions[slug]["id"],
                         "sample": {"label": "Sample", "synthetic": True, "generator": ANALYSIS_GENERATOR},
                         **body}
    return records, audit


OVERLAY_FIELDS = ("shots", "calibrations", "serveMarks", "swings", "comparisons")


def apply_analysis(session: dict, record: dict) -> dict:
    """The session as SampleContent installs it: the overlay's records appended to the session's own."""
    assert record["sessionId"] == session["id"] and session.get("sample")
    out = copy.deepcopy(session)
    for key in OVERLAY_FIELDS:
        if not record[key] and key not in out:
            continue
        existing = out.get(key, [])
        ids = {x["id"] for x in existing}
        assert not ids & {x["id"] for x in record[key]}, f"{key} id already in {session['title']}"
        out[key] = existing + copy.deepcopy(record[key])
    return out


# ----- the analysis oracle: computed the way JovraCore's SampleAnalysisSummary computes it ----------------------

def _first_serve_points(doc: dict) -> set:
    inp = {**{k: doc["match"][k] for k in ("format", "toss")}, "players": doc["players"], "sides": doc["sides"],
           "log": doc["match"]["log"]}
    return {p["id"] for p in scoring.fold(inp, inp["log"])["points"] if p["serveNumber"] == 1 and p["strokeCount"]}


def shot_placement_summary(doc: dict) -> list[dict]:
    """S11: per hitter and (non-serve) stroke with any placement: tagged, placed, Deep / Short / Out of placed."""
    groups = {}
    for shot in doc.get("shots", []):
        if shot["stroke"] == "serve":
            continue
        g = groups.setdefault((shot["hitter"], shot["stroke"]), {"tagged": 0, "placed": [], "order": len(groups)})
        g["tagged"] += 1
        if "placement" in shot:
            g["placed"].append(shot["placement"])
    out = []
    for (hitter, stroke), g in sorted(groups.items(), key=lambda kv: kv[1]["order"]):
        placed = g["placed"]
        if not placed:
            continue
        outs = sum(1 for p in placed if p["inOut"] == "out")
        deep = sum(1 for p in placed if p["inOut"] != "out" and _bin(p["court"]) == "deep")
        short = len(placed) - outs - deep
        pcts = [stats.pct(v, len(placed)) for v in (deep, short, outs)]
        out.append({"sessionId": doc["id"], "hitter": hitter, "stroke": stroke, "tagged": g["tagged"],
                    "placed": len(placed), "deep": _ratio(deep, len(placed)), "short": _ratio(short, len(placed)),
                    "out": _ratio(outs, len(placed)),
                    "needsReview": sum(1 for p in placed if p["inOut"] == "needsReview"),
                    "percentagesRounded": sum(pcts) != 100})
    return out


def serve_placement_summary(doc: dict) -> list[dict]:
    """S12: per server, first serves in with a placement, split by the receiver's box into Wide / Body / T."""
    if "match" not in doc:
        return []
    firsts = _first_serve_points(doc)
    servers: dict[str, dict] = {}
    for shot in doc.get("shots", []):
        if shot["stroke"] != "serve" or "placement" not in shot or shot.get("pointId") not in firsts:
            continue
        side = servers.setdefault(shot["hitter"], {"deuce": [], "ad": []})
        side[served_to(shot["placement"]["court"])].append(serve_zone(shot["placement"]["court"]))
    out = []
    for server, sides in servers.items():
        entry = {"sessionId": doc["id"], "server": server, "serve": "first"}
        for name in ("deuce", "ad"):
            zones = sides[name]
            entry[name] = {"placed": len(zones), **{z: _ratio(zones.count(z), len(zones)) for z in ("wide", "body", "t")}}
        out.append(entry)
    return out


def serve_mark_summary(doc: dict) -> list[dict]:
    marks = doc.get("serveMarks", [])
    if not marks:
        return []
    needed = ("contactFrame", "bounceFrame", "bounceCourt", "serverPosition")
    return [{"sessionId": doc["id"], "marked": len(marks),
             "complete": sum(1 for m in marks if all(k in m for k in needed)),
             "deuce": sum(1 for m in marks if m.get("servedTo") == "deuce"),
             "ad": sum(1 for m in marks if m.get("servedTo") == "ad"),
             "calibrationIds": sorted({m["calibrationId"] for m in marks if "calibrationId" in m})}]


def key_moment_summary(doc: dict) -> list[dict]:
    swings = doc.get("swings", [])
    if not swings:
        return []
    rows = []
    for s in swings:
        anchor = {k: s[k] for k in ("shotId", "serveMarkId", "markId") if k in s}
        rows.append({"id": s["id"], "kind": s["kind"], "stroke": s.get("stroke", "unknown"), **anchor,
                     "moments": [{"name": m["name"], "time": m["time"]} for m in s["keyMoments"]]})
    return [{"sessionId": doc["id"], "swings": rows}]


def _covering(manifest: dict, session_id: str, t_ms: int) -> dict | None:
    """The sample media of a session that shows a session time: a purpose-made practice clip before the session
    video. None when no bundled media covers it."""
    found = [m for m in manifest["media"] if m["sessionId"] == session_id
             and m["coversSessionMs"]["fromMs"] <= t_ms < m["coversSessionMs"]["toMs"]]
    found.sort(key=lambda m: (m["role"] != "practiceClip", m["mediaId"]))
    return found[0] if found else None


def comparison_summary(doc: dict, dates: dict, manifest: dict) -> list[dict]:
    out = []
    for c in doc.get("comparisons", []):
        sides = {}
        for name in ("left", "right"):
            side = c[name]
            media = _covering(manifest, side["sessionId"], side["syncTimeMs"])
            sides[name] = {"sessionId": side["sessionId"], "date": dates[side["sessionId"]],
                           "syncTimeMs": side["syncTimeMs"],
                           "mediaId": media["mediaId"] if media else None,
                           "offsetMs": side["syncTimeMs"] - media["coversSessionMs"]["fromMs"] if media else None}
        out.append({"id": c["id"], "sessionId": doc["id"], "syncedAt": c["syncedAt"], "note": c.get("note"),
                    **sides})
    return out


def analysis_summary(sessions: list[dict], manifest: dict) -> dict:
    """The analysis oracle over installed sessions (overlays applied), newest session first."""
    dates = {d["id"]: _local_date(d) for d in sessions}
    ordered = sorted(sessions, key=lambda d: (dates[d["id"]], d["id"]), reverse=True)
    return {
        "sample": all(d.get("sample") for d in sessions),
        "shotPlacement": [x for d in ordered for x in shot_placement_summary(d)],
        "servePlacement": [x for d in ordered for x in serve_placement_summary(d)],
        "serveMarks": [x for d in ordered for x in serve_mark_summary(d)],
        "keyMoments": [x for d in ordered for x in key_moment_summary(d)],
        "comparisons": [x for d in ordered for x in comparison_summary(d, dates, manifest)],
    }


def serve_speed_reference(doc: dict, manifest: dict) -> dict:
    """What the manual-assisted estimator (references.serve_speed, S12) reads from the Oct 4 marks: each mark's
    whole mph and km/h with its ±10% range (the clip is 60 fps), and the fastest."""
    from . import references
    rows = []
    for m in doc["serveMarks"]:
        media = _covering(manifest, doc["id"], _ms_half_up(_sec(m["contactFrame"])))
        fps = media["frameRate"]["num"] / media["frameRate"]["den"]
        pct_range = references.RANGE_PCT if fps >= references.LOW_FPS else references.LOW_FPS_RANGE_PCT
        mph = references.serve_speed(m, "mph")
        rows.append({"serveMarkId": m["id"], "mph": mph, "kmh": references.serve_speed(m, "km/h"),
                     "range": references.estimate_range(mph, pct_range),
                     "frames": m["bounceFrame"]["value"] - m["contactFrame"]["value"]})
    fastest = max(rows, key=lambda r: (r["mph"], r["serveMarkId"]))
    return {"sessionId": doc["id"], "unit": "mph", "marks": rows,
            "fastest": {"serveMarkId": fastest["serveMarkId"], "value": fastest["mph"], "unit": "mph",
                        "range": fastest["range"], "of": len(rows)}}


def brief_reference(summary: dict, speeds: dict) -> list[dict]:
    """The brief's literals for these screens against the computed values; a literal the rendered data cannot
    produce stays a recorded difference, never a typed constant."""
    (fh,) = summary["shotPlacement"]
    (sp,) = summary["servePlacement"]
    deuce, fastest = sp["deuce"], speeds["fastest"]
    split = tuple(deuce[z]["n"] for z in ("wide", "body", "t"))
    rows = [
        {"screen": "S11", "literal": "62% deep / 24% short / 14% out, 50 forehands of 133",
         "computed": f"{fh['deep']['display']} deep / {fh['short']['display']} short / {fh['out']['display']} out, "
                     f"{fh['placed']} forehands of {fh['tagged']}",
         "equal": (fh["deep"]["n"], fh["short"]["n"], fh["out"]["n"], fh["placed"], fh["tagged"]) == (31, 12, 7, 50, 133)},
        {"screen": "S12", "literal": "13 / 8 / 4 of 25 deuce first serves (52% wide / 32% body / 16% T)",
         "computed": f"{split[0]} / {split[1]} / {split[2]} of {deuce['placed']} deuce first serves "
                     f"({deuce['wide']['display']} wide / {deuce['body']['display']} body / {deuce['t']['display']} T)",
         "equal": split + (deuce["placed"],) == BRIEF_SERVE["deuce"] + (25,),
         "why": "Jon vs Alex has 20 deuce first serves in, so 25 cannot be placed; the placed subset is the rendered "
                "deuce first serves nearest the brief's split."},
        {"screen": "S12", "literal": "104 mph (94–114), fastest of 12 marked serves",
         "computed": f"{fastest['value']} mph ({fastest['range']['low']}–{fastest['range']['high']}), fastest of "
                     f"{fastest['of']} marked serves",
         "equal": fastest["value"] == BRIEF_SERVE["fastestMph"] and fastest["of"] == 12,
         "why": "T11 rendered the 12 serves at 150-190 km/h; with every mark within 1 frame of the rendered contact "
                "and bounce the fastest cannot read 104 mph."},
    ]
    for row in rows:
        if row["equal"]:
            row.pop("why", None)
    return rows


def _check_analysis(summary: dict, speeds: dict, audit: list[dict]) -> None:
    (fh,) = summary["shotPlacement"]
    assert (fh["deep"]["n"], fh["short"]["n"], fh["out"]["n"], fh["placed"], fh["tagged"]) == (31, 12, 7, 50, 133)
    assert (fh["deep"]["pct"], fh["short"]["pct"], fh["out"]["pct"]) == (62, 24, 14)
    (sp,) = summary["servePlacement"]
    assert [sp["deuce"][z]["n"] for z in ("wide", "body", "t")] == list(DEUCE_FIRST_SERVE_PLAN.values())
    (marks,) = summary["serveMarks"]
    assert marks["marked"] == marks["complete"] == 12 and marks["deuce"] == marks["ad"] == 6
    assert all(abs(a["offsetFrames"]["contact"]) <= 1 and abs(a["offsetFrames"]["bounce"]) <= 1 for a in audit)
    assert len(speeds["marks"]) == 12 and all(r["mph"] is not None and r["mph"] <= 150 for r in speeds["marks"])
    (cmp,) = summary["comparisons"]
    assert (cmp["left"]["date"], cmp["right"]["date"]) == ("2026-10-06", "2026-09-28")
    assert cmp["left"]["mediaId"] and cmp["right"]["mediaId"] == "sample-media.2026-09-28-serve-clip"


TRUTH_SLUGS = ("jon-vs-alex", "2026-10-04-behind-baseline-12-serves", "2026-10-02-side-on-forehands",
               "2026-09-28-serve-clip")


def load_truths(spec_root) -> dict:
    import json
    folder = spec_root / "fixtures" / "media" / "sample"
    return {slug: json.loads((folder / f"{slug}.truth.json").read_text(encoding="utf-8")) for slug in TRUTH_SLUGS}


def write_analysis(out, write_json, manifest: dict, equipment_base: dict, truths: dict) -> int:
    """Writes spec/fixtures/sample/analysis: one overlay per lab session and the analysis oracle."""
    pairs = library_sessions(manifest)
    sessions = dict(pairs)
    records, audit = analysis_records(sessions, truths, manifest)
    installed = {slug: apply_analysis(doc, records[slug]) if slug in records else doc for slug, doc in pairs}
    summary = analysis_summary(list(installed.values()), manifest)
    speeds = serve_speed_reference(installed["2026-10-04-serve-practice"], manifest)
    _check_analysis(summary, speeds, audit)
    calibration_audit = []
    # The match truth carries no pixels; the match was filmed from the same behind-baseline rig, so its calibration is
    # checked against the serve clip's rendered pixels (normalized image points do not depend on the resolution).
    for slug, truth_slug in (("jon-vs-alex", "2026-10-04-behind-baseline-12-serves"),
                             ("2026-10-04-serve-practice", "2026-10-04-behind-baseline-12-serves")):
        (cal,) = records[slug]["calibrations"]
        error = calibration_error_px(cal, truths[truth_slug])
        assert error <= CAMERA_TOLERANCE_PX, (slug, error)
        calibration_audit.append({"calibrationId": cal["id"], "truth": f"sample/{truth_slug}",
                                  "maxErrorPx": round(error, 3)})
    files = []
    for slug in ANALYSIS_SLUGS:
        name = f"sessions/{slug}.analysis.json"
        write_json(out / name, records[slug])
        files.append(name)
    write_json(out / "analysis.expected.json", {
        "schemaVersion": "1.0.0",
        "kind": "jovra.fixture.sampleAnalysis",
        "id": "SAMPLE-analysis",
        "title": "Sample analysis content: stroke tags, placements, calibrations, serve marks, key moments and a "
                 "comparison (Sample, synthetic)",
        "covers": ["screen 11 Shot placement", "screen 12 Serve Lab", "screen 13 Stroke Lab",
                   "screen 14 Video comparison", "screens.md §0.6 sample literals"],
        "libraryFixture": "../library/library.expected.json",
        "analysisFiles": files,
        "mediaManifest": "../media-manifest.json",
        "seed": ANALYSIS_SEED,
        "expected": summary,
        "reference": {
            "serveSpeeds": speeds,
            "serveMarkTruth": audit,
            "calibrationTruth": calibration_audit,
            "brief": brief_reference(summary, speeds),
        },
    })
    return len(files) + 1
