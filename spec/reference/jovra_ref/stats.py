"""Stats over a fold result (tennis-rules-and-stats.md §6) and the shared integer percentage rule (§7)."""

from __future__ import annotations

from .scoring import SIDES, other

MOMENTUM_WINDOW = 10
RALLY_BUCKETS = (("0-4", 0, 4), ("5-8", 5, 8), ("9+", 9, None))


def pct(n: int, d: int) -> int | None:
    """Half-up integer percentage with no floating point: (200n + d) div 2d. d = 0 -> None ("—")."""
    if n < 0 or d < 0 or n > d:
        raise ValueError(f"pct domain is 0 <= n <= d, got {n}/{d}")
    if d == 0:
        return None
    return (200 * n + d) // (2 * d)


def ratio(n: int, d: int) -> dict:
    p = pct(n, d)
    return {"n": n, "d": d, "pct": p, "display": "—" if p is None else f"{p}%"}


def pool(ratios: list[dict]) -> dict:
    """Cross-session aggregation (§6.10): pool numerators and denominators; never average percentages."""
    return ratio(sum(r["n"] for r in ratios), sum(r["d"] for r in ratios))


def delta_text(current: dict, prior: dict) -> str:
    """Rate change in percentage points, from the two DISPLAYED integers (§7 rule 4)."""
    if current["pct"] is None or prior["pct"] is None:
        return "—"
    d = current["pct"] - prior["pct"]
    unit = "percentage point" if abs(d) == 1 else "percentage points"
    if d == 0:
        return f"0 {unit}"
    return f"{'+' if d > 0 else '-'}{abs(d)} {unit}"


def _longest_streak(winners: list[str], side: str) -> int:
    best = run = 0
    for w in winners:
        run = run + 1 if w == side else 0
        best = max(best, run)
    return best


def _serve_block(points: list[dict]) -> dict:
    """Serve counts for the points one server (side or player) served. Penalty slots are excluded."""
    sp = len(points)
    known = [p for p in points if p["serveNumber"] is not None]
    first_in = [p for p in known if p["serveNumber"] == 1]
    second = [p for p in known if p["serveNumber"] == 2]
    server = points[0]["serverSide"] if points else None
    first_won = sum(1 for p in first_in if p["winner"] == server)
    second_won = sum(1 for p in second if p["winner"] == server)
    dfs = sum(1 for p in points if p["endType"] == "doubleFault")
    return {
        "servicePoints": sp,
        "firstServeIn": ratio(len(first_in), len(known)),
        "firstServePointsWon": ratio(first_won, len(first_in)),
        "secondServePointsWon": ratio(second_won, len(second)),
        "secondServeIn": ratio(len(second) - dfs, len(second)),
        "aces": sum(1 for p in points if p["endType"] == "ace"),
        "doubleFaults": dfs,
        "serviceWinners": sum(1 for p in points if p["endType"] == "serviceWinner"),
        "servicePointsWon": ratio(sum(1 for p in points if p["winner"] == server), sp),
    }


def compute(result: dict) -> dict:
    """Every stat is a pure function of the fold. Undetermined points (after an unknown winner) are
    excluded and the stats are marked provisional; points after the match end are excluded."""
    counted = [p for p in result["points"] if p["determined"] and p["winner"] is not None]
    excluded = sum(1 for p in result["points"] if not p["afterMatchEnd"]) - len(counted)
    played = [p for p in counted if p["kind"] == "point"]
    games = [g for g in result["games"] if g["complete"]]
    sides = {}
    for s in SIDES:
        o = other(s)
        served = [p for p in played if p["serverSide"] == s]
        returned = [p for p in played if p["serverSide"] == o]
        serve = _serve_block(served)
        opp = _serve_block(returned)
        opp_first_in = opp["firstServeIn"]["n"]
        opp_first_won = opp["firstServePointsWon"]["n"]
        opp_second = opp["secondServePointsWon"]["d"]
        opp_second_won = opp["secondServePointsWon"]["n"]
        service_games = [g for g in games if g["kind"] == "standard" and not g["byPenalty"] and g["serverSide"] == s]
        return_games = [g for g in games if g["kind"] == "standard" and not g["byPenalty"] and g["serverSide"] == o]
        # Break points count every point slot, penalty slots included (decision 4): a break completed by a
        # point penalty is a break point faced and converted, so BPconverted = breaks holds (§6.3).
        bp_faced = [p for p in counted if p["serverSide"] == s and p["pressure"]["breakPoint"]]
        bp_chances = [p for p in counted if p["serverSide"] == o and p["pressure"]["breakPoint"]]
        block = {
            "totalPointsWon": ratio(sum(1 for p in counted if p["winner"] == s), len(counted)),
            "penaltyPointsAwarded": sum(1 for p in counted if p["kind"] == "penaltyPoint" and p["winner"] == s),
        }
        block.update(serve)
        block.update(
            {
                "serviceGamesWon": ratio(sum(1 for g in service_games if g["winner"] == s), len(service_games)),
                "returnPointsWon": ratio(sum(1 for p in returned if p["winner"] == s), len(returned)),
                "returnFirstServePointsWon": ratio(opp_first_in - opp_first_won, opp_first_in),
                "returnSecondServePointsWon": ratio(opp_second - opp_second_won, opp_second),
                "returnGamesWon": ratio(sum(1 for g in return_games if g["winner"] == s), len(return_games)),
                "breakPointsSaved": ratio(sum(1 for p in bp_faced if p["winner"] == s), len(bp_faced)),
                "breakPointsConverted": ratio(sum(1 for p in bp_chances if p["winner"] == s), len(bp_chances)),
                "winners": sum(1 for p in played if p["endType"] == "winner" and p["winner"] == s),
                "forcedErrors": sum(1 for p in played if p["endType"] == "forcedError" and p["winner"] == o),
                "unforcedErrors": sum(1 for p in played if p["endType"] == "unforcedError" and p["winner"] == o),
                "longestPointStreak": _longest_streak([p["winner"] for p in counted], s),
                "longestGameStreak": _longest_streak([g["winner"] for g in games], s),
            }
        )
        sides[s] = block

    servers = {}
    if result["match"]["doubles"]:  # doubles: serve stats also per server (§6.8)
        by_server: dict[str, list] = {}
        for p in played:
            by_server.setdefault(p["server"], []).append(p)
        servers = {pid: _serve_block(pts) for pid, pts in sorted(by_server.items())}

    shots = [p["strokeCount"] for p in played if p["strokeCount"] is not None]
    rally = [p["rallyLength"] for p in played]
    buckets = {}
    for label, lo, hi in RALLY_BUCKETS:
        buckets[label] = sum(1 for r in rally if r is not None and r >= lo and (hi is None or r <= hi))
    buckets["unknown"] = sum(1 for r in rally if r is None)

    review_points = [p for p in result["points"] if p["kind"] == "point" and not p["afterMatchEnd"]]
    reviewed = sum(1 for p in review_points if p["reviewState"] == "reviewed")
    timed = [p for p in counted if "tStartMs" in p and "tEndMs" in p]
    duration = None
    if timed and len(timed) == len(counted):
        duration = max(p["tEndMs"] for p in timed) - min(p["tStartMs"] for p in timed)

    momentum = []
    winners = [p["winner"] for p in counted]
    for i in range(len(winners)):
        window = winners[max(0, i - MOMENTUM_WINDOW + 1): i + 1]
        momentum.append([sum(1 for w in window if w == "A"), len(window)])

    return {
        "provisional": result["match"]["provisional"],
        "countedPoints": len(counted),
        "excludedPoints": excluded,
        "sides": sides,
        "servers": servers,
        "shots": {"total": sum(shots), "pointsWithStrokeCount": len(shots)},
        "rallyLength": buckets,
        "review": {
            "reviewed": reviewed,
            "needsReview": sum(1 for p in review_points if p["reviewState"] == "needsReview"),
            "unreviewed": sum(1 for p in review_points if p["reviewState"] == "unreviewed"),
            "completion": ratio(reviewed, len(review_points)),
        },
        "durationMs": duration,
        "momentum": {"window": MOMENTUM_WINDOW, "side": "A", "series": momentum},
    }
