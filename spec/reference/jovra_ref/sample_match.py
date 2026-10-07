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


def _gaps(rng: SplitMix64, rests: list[str], durations: list[int]) -> list[int]:
    gaps = [None] * (len(rests) - 1)
    for i, rest in enumerate(rests[:-1]):
        if rest in REST_RANGES:
            gaps[i] = rng.between(*REST_RANGES[rest])
    free = [i for i, g in enumerate(gaps) if g is None]
    remaining = MATCH_MS - sum(durations) - sum(g for g in gaps if g is not None)
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
