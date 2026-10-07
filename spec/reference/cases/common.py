"""Shared setups for the conformance cases (formats from tennis-rules-and-stats.md §1.5)."""

from __future__ import annotations

import copy


def tb_set(games=6, at=6, points=7, sudden=None, end_change=None, sudden_side=None):
    tb = {"points": points}
    if sudden is not None:
        tb["suddenDeathAt"] = sudden
    if end_change is not None:
        tb["endChange"] = end_change
    if sudden_side is not None:
        tb["suddenDeathSide"] = sudden_side
    return {"kind": "tiebreakSet", "games": games, "tiebreakAt": at, "tiebreak": tb}


def mtb(points=10):
    return {"kind": "matchTiebreak", "tiebreak": {"points": points}}


def fmt(preset, sets_to_win, scoring="ad", set_rule=None, final=None, lets="let", status=None):
    f = {"presetId": preset, "setsToWin": sets_to_win, "gameScoring": scoring, "set": set_rule or tb_set()}
    if final is not None:
        f["finalSet"] = final
    f["lets"] = lets
    if status is not None:
        f["ruleStatus"] = status
    return f


CLUB_BO3 = fmt("club_bo3", 2)
USTA_MTB = fmt("usta_mtb", 2, final=mtb(10))
NOAD_MTB = fmt("noad_mtb", 2, "noAd", final=mtb(10))
SLAM_BO3 = fmt("slam_bo3", 2, final=tb_set(points=10))
SLAM_BO5 = fmt("slam_bo5", 3, final=tb_set(points=10))
BEST_OF_1 = fmt("best_of_1", 1)
ADV_SET_BO1 = fmt("custom", 1, set_rule={"kind": "advantageSet", "games": 6})
ADV_FINAL_BO3 = fmt("custom", 2, final={"kind": "advantageSet", "games": 6})
PRO_SET_8 = fmt("pro_set_8", 1, set_rule=tb_set(8, 8, 7))
SHORT_SETS = fmt("short_sets", 2, "noAd", set_rule=tb_set(4, 4, 7), final=mtb(10))
SHORT_3_3_BO1 = fmt("custom", 1, set_rule=tb_set(4, 3, 7))
SHORT_TB5_BO1 = fmt("custom", 1, set_rule=tb_set(4, 4, 5, sudden=4, end_change="after4"))
FAST4 = fmt("fast4", 2, "noAd", set_rule=tb_set(4, 3, 5, sudden=4, end_change="after4"),
            final=tb_set(4, 3, 5, sudden=4, end_change="after4"),
            lets="noLet", status="unverified")
# The App VI.2 short-set tie-break with the 4-4 deciding point read as a No-Ad deciding point (decision 22).
SHORT_SETS_TB5_RC = fmt("custom", 2, "noAd",
                        set_rule=tb_set(4, 3, 5, sudden=4, end_change="after4", sudden_side="receiverChooses"),
                        final=tb_set(4, 3, 5, sudden=4, end_change="after4", sudden_side="receiverChooses"))
TB_ONLY_10 = fmt("tb_only_10", 1, set_rule=mtb(10))
COMAN_BO3 = fmt("custom", 2, set_rule=tb_set(end_change="coman"))

SINGLES_PLAYERS = [
    {"id": "jon", "displayName": "Jon", "handedness": "right", "backhand": "twoHanded", "isSelf": True},
    {"id": "alex", "displayName": "Alex", "handedness": "left", "backhand": "oneHanded", "isSelf": False},
]
SINGLES_SIDES = {"A": ["jon"], "B": ["alex"]}
DOUBLES_PLAYERS = [
    {"id": "ann", "displayName": "Ann", "handedness": "right", "backhand": "twoHanded", "isSelf": True},
    {"id": "amy", "displayName": "Amy", "handedness": "left", "backhand": "twoHanded", "isSelf": False},
    {"id": "ben", "displayName": "Ben", "handedness": "right", "backhand": "oneHanded", "isSelf": False},
    {"id": "bob", "displayName": "Bob", "handedness": "right", "backhand": "twoHanded", "isSelf": False},
]
DOUBLES_SIDES = {"A": ["ann", "amy"], "B": ["ben", "bob"]}


def singles(fmt_, first="jon", ends=("near", "far")):
    return {
        "format": copy.deepcopy(fmt_),
        "players": copy.deepcopy(SINGLES_PLAYERS),
        "sides": copy.deepcopy(SINGLES_SIDES),
        "toss": {"firstServer": first, "startingEnds": {"A": ends[0], "B": ends[1]}},
    }


def doubles(fmt_, first="ann"):
    return {
        "format": copy.deepcopy(fmt_),
        "players": copy.deepcopy(DOUBLES_PLAYERS),
        "sides": copy.deepcopy(DOUBLES_SIDES),
        "toss": {"firstServer": first, "startingEnds": {"A": "near", "B": "far"}},
    }


def holds(n_games: int, start_game: int = 0, first_side: str = "A") -> str:
    """n love service holds, starting at match game ``start_game`` (server alternates by game)."""
    out = []
    for g in range(start_game, start_game + n_games):
        side = first_side if g % 2 == 0 else ("B" if first_side == "A" else "A")
        out.append(side * 4)
    return "".join(out)


def pts(server: str, receiver: str) -> dict:
    return {"kind": "points", "server": server, "receiver": receiver}


def tbcall(server: int, receiver: int) -> dict:
    return {"kind": "tiebreak", "server": server, "receiver": receiver}


def pressure(game=(), bp=False, set_=(), match=()) -> dict:
    return {"gamePointFor": list(game), "breakPoint": bp, "setPointFor": list(set_), "matchPointFor": list(match)}


def ratio(n: int, d: int, p) -> dict:
    return {"n": n, "d": d, "pct": p, "display": "—" if p is None else f"{p}%"}
