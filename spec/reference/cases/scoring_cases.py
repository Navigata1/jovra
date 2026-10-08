"""Scoring conformance cases. Every assertion is hand-derived from the rules doc, not copied from engine
output; generate_fixtures.py refuses to write a case whose engine output disagrees with its assertions."""

from __future__ import annotations

from jovra_ref import conformance
from jovra_ref.dsl import LogBuilder

from .common import (ADV_FINAL_BO3, ADV_SET_BO1, BEST_OF_1, CLUB_BO3, COMAN_BO3, FAST4, NOAD_MTB, PRO_SET_8,
                     SHORT_3_3_BO1, SHORT_SETS, SHORT_SETS_TB5_RC, SHORT_TB5_BO1, SLAM_BO3, SLAM_BO5, TB_ONLY_10,
                     USTA_MTB,
                     doubles, holds, pressure, pts, ratio, singles, tbcall)

ORDER = 10
CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def make(cid, title, covers, setup, lb, checkpoints, assertions, expect_error=None):
    return {
        "id": cid,
        "title": title,
        "covers": covers,
        "setup": setup,
        "log": lb.events,
        "checkpoints": checkpoints,
        "assertions": assertions,
        "expectError": expect_error,
    }


@case
def s01():
    lb = LogBuilder()
    lb.points("AAAA")
    a = [
        (0, "fold.points[0].call", pts("0", "0")),
        (0, "fold.points[0].courtSide", "deuce"),
        (0, "fold.points[1].courtSide", "ad"),
        (0, "fold.points[3].call", pts("40", "0")),
        (0, "fold.points[3].pressure", pressure(game=["A"])),
        (0, "fold.points[3].after", {"gameWon": True, "setWon": False, "matchWon": False, "endChange": True,
                                     "rest": "changeoverNoRest"}),
        (0, "fold.next.server", "alex"),
        (0, "fold.next.before.games", {"A": 1, "B": 0}),
        (0, "fold.next.ends", {"A": "far", "B": "near"}),
    ]
    return make("S01-love-hold", "Love service hold: calls, sides, change of ends after game 1 without rest",
                ["§1.1", "§2.2 side(j)", "§2.5 ends"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s02():
    lb = LogBuilder()
    lb.points("AABBAA")
    a = [
        (0, "fold.points[3].call", pts("30", "15")),
        (0, "fold.points[4].call", pts("30", "30")),
        (0, "fold.points[5].call", pts("40", "30")),
        (0, "fold.points[5].pressure", pressure(game=["A"])),
        (0, "fold.games[0].points", {"A": 4, "B": 2}),
    ]
    return make("S02-hold-4-2", "Ad game won 4-2; server's score called first", ["§1.1"], singles(CLUB_BO3), lb,
                [lb.last_seq], a)


@case
def s03():
    lb = LogBuilder()
    lb.points("AAABBBABBAAA")
    a = [
        (0, "fold.points[4].call", pts("40", "15")),
        (0, "fold.points[5].call", pts("40", "30")),
        (0, "fold.points[6].call", {"kind": "deuce"}),
        (0, "fold.points[7].call", {"kind": "advantage", "side": "A"}),
        (0, "fold.points[8].call", {"kind": "deuce"}),
        (0, "fold.points[9].call", {"kind": "advantage", "side": "B"}),
        (0, "fold.points[9].pressure", pressure(game=["B"], bp=True)),
        (0, "fold.points[11].call", {"kind": "advantage", "side": "A"}),
        (0, "fold.games[0].points", {"A": 7, "B": 5}),
        (0, "fold.games[0].winner", "A"),
        (0, "stats.sides.A.breakPointsSaved", ratio(1, 1, 100)),
    ]
    return make("S03-deuce-chain", "Deuce chain: deuce, ad-in, deuce, ad-out (break point saved), ad-in, game 7-5",
                ["§1.1 deuce/advantage", "§6.3 break point"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s04():
    lb = LogBuilder()
    lb.points("ABBBAABB")
    a = [
        (0, "fold.points[4].call", pts("15", "40")),
        (0, "fold.points[4].pressure", pressure(game=["B"], bp=True)),
        (0, "fold.points[5].pressure.breakPoint", True),
        (0, "fold.points[6].call", {"kind": "deuce"}),
        (0, "fold.points[7].call", {"kind": "advantage", "side": "B"}),
        (0, "fold.games[0].break", True),
        (0, "fold.games[0].points", {"A": 3, "B": 5}),
        (0, "stats.sides.B.breakPointsConverted", ratio(1, 3, 33)),
        (0, "stats.sides.A.breakPointsSaved", ratio(2, 3, 67)),
        (0, "stats.sides.A.serviceGamesWon", ratio(0, 1, 0)),
        (0, "stats.sides.B.returnGamesWon", ratio(1, 1, 100)),
    ]
    return make("S04-break-ad-out", "Break of serve via ad-out; BP faced/saved/converted",
                ["§1.1", "§6.3 invariants"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s05():
    lb = LogBuilder()
    lb.points("AABBAB")
    lb.point("A", decidingPointSide="ad")
    a = [
        (0, "fold.points[6].call", {"kind": "decidingPoint"}),
        (0, "fold.points[6].pressure", pressure(game=["A", "B"], bp=True)),
        (0, "fold.points[6].courtSide", "ad"),
        (0, "fold.points[6].receiver", "alex"),
        (0, "fold.games[0].points", {"A": 4, "B": 3}),
        (0, "fold.games[0].break", False),
    ]
    return make("S05-noad-deciding-server", "No-Ad deciding point won by the server; receiver chose the ad court",
                ["§1.2 No-Ad", "§6.3 deciding point is a break point"], singles(NOAD_MTB), lb, [lb.last_seq], a)


@case
def s06():
    lb = LogBuilder()
    lb.points("ABABAB")
    before = lb.last_seq
    lb.point("B")
    a = [
        (0, "fold.next.call", {"kind": "decidingPoint"}),
        (0, "fold.next.courtSide", None),
        (0, "fold.next.receiver", "alex"),
        (1, "fold.points[6].courtSide", None),
        (1, "fold.games[0].break", True),
        (1, "fold.games[0].points", {"A": 3, "B": 4}),
        (1, "fold.next.server", "alex"),
    ]
    return make("S06-noad-deciding-receiver", "No-Ad deciding point won by the receiver; side not recorded stays null",
                ["§1.2 decidingPointSide is observed, never derived"], singles(NOAD_MTB), lb, [before, lb.last_seq], a)


@case
def s07():
    lb = LogBuilder()
    lb.points("A" * 24)
    first = lb.last_seq
    lb.points("BBBB")
    a = [
        (0, "fold.games[5].server", "alex"),
        (0, "fold.sets[0].games", {"A": 6, "B": 0}),
        (0, "fold.points[23].after", {"gameWon": True, "setWon": True, "matchWon": False, "endChange": False,
                                      "rest": "setBreak"}),
        (0, "fold.next.server", "jon"),
        (0, "fold.next.set", 1),
        (0, "fold.next.ends", {"A": "far", "B": "near"}),
        (1, "fold.games[6].break", True),
        (1, "fold.points[27].after.rest", "changeoverNoRest"),
        (1, "fold.next.server", "alex"),
        (1, "fold.next.ends", {"A": "near", "B": "far"}),
        (1, "fold.match.scoreline", "6-0 0-1"),
    ]
    return make("S07-serve-across-sets", "Service alternates across a 6-0 set; even set -> change after game 1 of next set",
                ["§2.2 server(g)", "§2.5 even set"], singles(CLUB_BO3), lb, [first, lb.last_seq], a)


@case
def s08():
    lb = LogBuilder()
    for g, w in enumerate("ABABAAABA"):
        lb.points(w * 4)
    first = lb.last_seq
    lb.points("BBBB")
    a = [
        (0, "fold.sets[0].games", {"A": 6, "B": 3}),
        (0, "fold.points[35].after", {"gameWon": True, "setWon": True, "matchWon": False, "endChange": True,
                                      "rest": "setBreak"}),
        (0, "fold.next.server", "alex"),
        (0, "fold.next.ends", {"A": "far", "B": "near"}),
        (1, "fold.points[39].after.endChange", True),
        (1, "fold.next.ends", {"A": "near", "B": "far"}),
    ]
    return make("S08-odd-set-ends", "6-3 set (odd games): ends change at the set end and after game 1 of the next set",
                ["§2.5 one-condition rule"], singles(CLUB_BO3), lb, [first, lb.last_seq], a)


@case
def s09():
    lb = LogBuilder()
    lb.points(holds(10))
    lb.points("AAAA")
    lb.points("AAAA")
    a = [
        (0, "fold.points[43].call", pts("40", "0")),
        (0, "fold.points[43].pressure", pressure(game=["A"])),
        (0, "fold.points[47].pressure", pressure(game=["A"], bp=True, set_=["A"])),
        (0, "fold.sets[0].games", {"A": 7, "B": 5}),
        (0, "fold.sets[0].tiebreak", None),
        (0, "fold.match.scoreline", "7-5"),
    ]
    return make("S09-seven-five", "7-5 set: 6-5 is not a set; break at 6-5 is a set point",
                ["§1.4 margin of two"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s10():
    lb = LogBuilder()
    lb.points(holds(12))
    lb.points("AABABABAABA")
    a = [
        (0, "fold.points[48].tiebreak", "set"),
        (0, "fold.points[48].server", "jon"),
        (0, "fold.points[48].courtSide", "deuce"),
        (0, "fold.points[48].call", tbcall(0, 0)),
        (0, "fold.points[49].server", "alex"),
        (0, "fold.points[49].courtSide", "ad"),
        (0, "fold.points[50].server", "alex"),
        (0, "fold.points[50].courtSide", "deuce"),
        (0, "fold.points[51].server", "jon"),
        (0, "fold.points[52].server", "jon"),
        (0, "fold.points[53].server", "alex"),
        (0, "fold.points[53].after.endChange", True),
        (0, "fold.points[53].after.rest", "changeoverNoRest"),
        (0, "fold.points[58].call", tbcall(4, 6)),
        (0, "fold.points[58].pressure", pressure(game=["A"], set_=["A"])),
        (0, "fold.points[58].after", {"gameWon": True, "setWon": True, "matchWon": False, "endChange": True,
                                      "rest": "setBreak"}),
        (0, "fold.sets[0].tiebreak", {"A": 7, "B": 4}),
        (0, "fold.match.scoreline", "7-6(4)"),
        (0, "fold.next.server", "alex"),
        (0, "fold.next.ends", {"A": "near", "B": "far"}),
    ]
    return make("S10-tiebreak-7-4", "Set tie-break at 6-6: 1-2-2 serve blocks, sides, ends every 6, 7-6(4), next set",
                ["§1.3", "§1.6 7-6(x)", "§2.3", "Rule 5b next-set first server"], singles(CLUB_BO3), lb,
                [lb.last_seq], a)


@case
def s11():
    lb = LogBuilder()
    lb.points(holds(12))
    lb.points("AB" * 6 + "BAAA")
    a = [
        (0, "fold.points[53].after.endChange", True),
        (0, "fold.points[59].after.endChange", True),
        (0, "fold.points[60].pressure.setPointFor", []),
        (0, "fold.points[61].pressure.setPointFor", ["B"]),
        (0, "fold.points[62].pressure.setPointFor", []),
        (0, "fold.points[63].pressure.setPointFor", ["A"]),
        (0, "fold.sets[0].tiebreak", {"A": 9, "B": 7}),
        (0, "fold.match.scoreline", "7-6(7)"),
        (0, "fold.next.ends", {"A": "far", "B": "near"}),
    ]
    return make("S11-tiebreak-extended", "Extended tie-break 9-7: no upper limit, ends after 6 and 12, recorded 7-6(7)",
                ["§1.3 margin of two", "§1.6"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s12():
    lb = LogBuilder()
    lb.points(holds(12))
    lb.points("AB" * 6 + "BB")
    a = [
        (0, "fold.match.status", "completed"),
        (0, "fold.match.winner", "B"),
        (0, "fold.match.scoreline", "7-6(6)"),
        (0, "fold.sets[0].games", {"A": 6, "B": 7}),
        (0, "fold.sets[0].tiebreak", {"A": 6, "B": 8}),
        (0, "fold.points[61].after", {"gameWon": True, "setWon": True, "matchWon": True, "endChange": False,
                                      "rest": "matchEnd"}),
        (0, "fold.next", None),
    ]
    return make("S12-best-of-1-tiebreak-loss", "Best of 1: side B wins the tie-break 8-6; winner-first scoreline 7-6(6)",
                ["§1.5 best of 1", "§1.6 x = loser's points"], singles(BEST_OF_1), lb, [lb.last_seq], a)


@case
def s13():
    lb = LogBuilder()
    lb.points(holds(12))
    lb.points("AAAA" + "AAAA")
    a = [
        (0, "fold.points[48].tiebreak", None),
        (0, "fold.points[48].call", pts("0", "0")),
        (0, "fold.sets[0].rule", "advantageSet"),
        (0, "fold.sets[0].games", {"A": 8, "B": 6}),
        (0, "fold.sets[0].tiebreak", None),
        (0, "fold.match.scoreline", "8-6"),
    ]
    return make("S13-advantage-set", "Advantage set: no tie-break at 6-6, won 8-6", ["§1.4 Rule 6a"],
                singles(ADV_SET_BO1), lb, [lb.last_seq], a)


@case
def s14():
    lb = LogBuilder()
    lb.points("A" * 24 + "B" * 24)
    lb.points(holds(14, start_game=12))
    lb.points("AAAA" + "AAAA")
    a = [
        (0, "fold.points[96].tiebreak", None),
        (0, "fold.points[96].gameInSet", 12),
        (0, "fold.sets[0].rule", "tiebreakSet"),
        (0, "fold.sets[2].rule", "advantageSet"),
        (0, "fold.sets[2].games", {"A": 9, "B": 7}),
        (0, "fold.match.scoreline", "6-0 0-6 9-7"),
    ]
    return make("S14-advantage-final-set", "Best of 3 with an advantage final set: 6-0 0-6 9-7",
                ["§1.4", "§1.5 final-set variants"], singles(ADV_FINAL_BO3), lb, [lb.last_seq], a)


@case
def s15():
    lb = LogBuilder()
    lb.points("A" * 24 + "B" * 24)
    lb.points("AB" * 8 + "AA")
    a = [
        (0, "fold.points[48].tiebreak", "match"),
        (0, "fold.points[48].server", "jon"),
        (0, "fold.points[49].server", "alex"),
        (0, "fold.points[53].after.endChange", True),
        (0, "fold.points[59].after.endChange", True),
        (0, "fold.points[64].pressure.matchPointFor", []),
        (0, "fold.points[65].pressure.matchPointFor", ["A"]),
        (0, "fold.points[65].after.rest", "matchEnd"),
        (0, "fold.sets[2].rule", "matchTiebreak"),
        (0, "fold.sets[2].games", {"A": 1, "B": 0}),
        (0, "fold.sets[2].tiebreak", {"A": 10, "B": 8}),
        (0, "fold.match.scoreline", "6-0 0-6 [10-8]"),
        (0, "fold.match.setsWon", {"A": 2, "B": 1}),
    ]
    return make("S15-match-tiebreak", "Match tie-break to 10 in lieu of the final set, recorded as a set [10-8]",
                ["§1.5 App VI.4", "§1.6 1-0(x) / [10-8]", "§2.3 original order continues"], singles(USTA_MTB), lb,
                [lb.last_seq], a)


@case
def s16():
    lb = LogBuilder()
    lb.points("A" * 24 + "B" * 24)
    lb.points("AB" * 9 + "ABBB")
    a = [
        (0, "fold.points[65].after.endChange", True),
        (0, "fold.sets[2].tiebreak", {"A": 10, "B": 12}),
        (0, "fold.match.winner", "B"),
        (0, "fold.match.scoreline", "0-6 6-0 [12-10]"),
    ]
    return make("S16-match-tiebreak-extended", "Match tie-break extended to 12-10; winner-first scoreline for side B",
                ["§1.5", "§1.6"], singles(USTA_MTB), lb, [lb.last_seq], a)


@case
def s17():
    lb = LogBuilder()
    lb.points("A" * 24 + "B" * 24)
    lb.points(holds(12, start_game=12))
    lb.points("AB" * 9 + "AA")
    a = [
        (0, "fold.points[96].tiebreak", "set"),
        (0, "fold.points[96].server", "jon"),
        (0, "fold.sets[2].games", {"A": 7, "B": 6}),
        (0, "fold.sets[2].tiebreak", {"A": 11, "B": 9}),
        (0, "fold.match.scoreline", "6-0 0-6 7-6(9)"),
    ]
    return make("S17-final-set-10pt-tiebreak", "Grand Slam rule: final-set 10-point tie-break at 6-6, recorded 7-6(9)",
                ["§1.5 App VI.5"], singles(SLAM_BO3), lb, [lb.last_seq], a)


@case
def s18():
    lb = LogBuilder()
    lb.points(holds(16))
    lb.points("AB" * 5 + "AA")
    a = [
        (0, "fold.points[48].tiebreak", None),
        (0, "fold.points[64].tiebreak", "set"),
        (0, "fold.points[64].server", "jon"),
        (0, "fold.sets[0].games", {"A": 9, "B": 8}),
        (0, "fold.sets[0].tiebreak", {"A": 7, "B": 5}),
        (0, "fold.match.scoreline", "9-8(5)"),
    ]
    return make("S18-pro-set", "Pro set to 8 games with a tie-break at 8-8, recorded 9-8(5)", ["§1.4 USTA I.E.4"],
                singles(PRO_SET_8), lb, [lb.last_seq], a)


@case
def s19():
    lb = LogBuilder()
    lb.points(holds(8))
    lb.points("ABAB" + "AAAAA")
    a = [
        (0, "fold.points[32].tiebreak", "set"),
        (0, "fold.sets[0].games", {"A": 5, "B": 4}),
        (0, "fold.sets[0].tiebreak", {"A": 7, "B": 2}),
        (0, "fold.match.scoreline", "5-4(2)"),
        (0, "fold.next.server", "alex"),
        (0, "fold.next.set", 1),
    ]
    return make("S19-short-set-4-4", "Short sets to 4 with a tie-break at 4-4, recorded 5-4(2)",
                ["§1.4 App VI.1"], singles(SHORT_SETS), lb, [lb.last_seq], a)


@case
def s20():
    lb = LogBuilder()
    lb.points(holds(6))
    lb.points("AB" * 5 + "AA")
    a = [
        (0, "fold.points[24].tiebreak", "set"),
        (0, "fold.sets[0].games", {"A": 4, "B": 3}),
        (0, "fold.match.scoreline", "4-3(5)"),
        (0, "fold.match.status", "completed"),
    ]
    return make("S20-short-set-3-3", "Short set with the tie-break at 3-3 (sanctioning-body option), recorded 4-3(5)",
                ["§1.4 USTA I.E.3"], singles(SHORT_3_3_BO1), lb, [lb.last_seq], a)


@case
def s21():
    lb = LogBuilder()
    lb.points(holds(6))
    lb.points("AB" * 4 + "B")
    a = [
        (0, "fold.points[32].call", tbcall(4, 4)),
        (0, "fold.points[32].pressure", pressure(game=["A", "B"], set_=["A", "B"])),
        (0, "fold.points[32].after.setWon", True),
        (0, "fold.sets[0].games", {"A": 3, "B": 4}),
        (0, "fold.sets[0].tiebreak", {"A": 4, "B": 5}),
        (0, "fold.match.scoreline", "3-4(4)"),
        (0, "fold.points[27].after.endChange", True),
        (0, "fold.points[29].after.endChange", False),
    ]
    return make("S21-fast4", "Fast4 (UNVERIFIED parameters): tie-break to 5 at 3-3, sudden death at 4-4, ends change "
                "only after tie-break point 4",
                ["§1.4 Fast4 (UNVERIFIED)", "sudden death gives both sides set point", "§2.3 short-set TB ends"], singles(FAST4), lb,
                [lb.last_seq], a)


@case
def s22():
    lb = LogBuilder()
    lb.points(holds(8))
    lb.points("ABABABAA")
    a = [
        (0, "fold.points[35].after.endChange", True),
        (0, "fold.points[37].after.endChange", False),
        (0, "fold.points[33].after.endChange", False),
        (0, "fold.sets[0].tiebreak", {"A": 5, "B": 3}),
        (0, "fold.match.scoreline", "5-4(3)"),
    ]
    return make("S22-short-set-tiebreak-to-5", "Short-set tie-break to 5: ends change only after the first 4 points",
                ["§1.4 App VI.2", "§2.3 short-set TB ends"], singles(SHORT_TB5_BO1), lb, [lb.last_seq], a)


@case
def s23():
    lb = LogBuilder()
    lb.points("A" * 48)
    two_sets = lb.last_seq
    lb.points("A" * 24)
    a = [
        (0, "fold.match.status", "inProgress"),
        (0, "fold.match.setsWon", {"A": 2, "B": 0}),
        (0, "fold.next.set", 2),
        (1, "fold.points[71].pressure.matchPointFor", ["A"]),
        (1, "fold.match.status", "completed"),
        (1, "fold.match.scoreline", "6-0 6-0 6-0"),
    ]
    return make("S23-best-of-5", "Best of 5: two sets is not a match; three sets is",
                ["§1.5 best of 5"], singles(SLAM_BO5), lb, [two_sets, lb.last_seq], a)


@case
def s24():
    lb = LogBuilder()
    lb.points("AABABAABABAAAA")
    a = [
        (0, "fold.points[0].tiebreak", "match"),
        (0, "fold.points[0].server", "jon"),
        (0, "fold.points[1].server", "alex"),
        (0, "fold.points[2].server", "alex"),
        (0, "fold.points[3].server", "jon"),
        (0, "fold.sets[0].rule", "matchTiebreak"),
        (0, "fold.match.scoreline", "[10-4]"),
    ]
    return make("S24-standalone-tiebreak", "Standalone 10-point tie-break session (community ask F13)",
                ["§1.5 tb_only_10"], singles(TB_ONLY_10), lb, [lb.last_seq], a)


@case
def s25():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    lb.points("AAABBBAA")
    lb.points("BBBB" + "AAAA" + "BBBB" + "AAAA")
    a = [
        (0, "fold.games[0].server", "ann"),
        (0, "fold.games[1].server", "ben"),
        (0, "fold.games[2].server", "amy"),
        (0, "fold.games[3].server", "bob"),
        (0, "fold.games[4].server", "ann"),
        (0, "fold.points[0].receiver", "bob"),
        (0, "fold.points[1].receiver", "ben"),
        (0, "fold.points[6].receiver", "bob"),
        (0, "fold.points[7].receiver", "ben"),
        (0, "fold.points[8].receiver", "amy"),
        (0, "fold.points[9].receiver", "ann"),
        (0, "stats.servers.ann.servicePoints", 12),
        (0, "stats.servers.ben.servicePoints", 4),
    ]
    return make("S25-doubles-rotation", "Doubles: rotation [s1, s2, partner(s1), partner(s2)], receivers alternate every point",
                ["§2.4 Rules 14-15"], doubles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s26():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    lb.points("A" * 24)
    lb.doubles_order(1, "amy", "bob", "ann", "ben")
    lb.points("AAAA" + "BBBB")
    a = [
        (0, "fold.games[6].server", "amy"),
        (0, "fold.games[7].server", "bob"),
        (0, "fold.points[24].receiver", "ben"),
        (0, "fold.points[25].receiver", "bob"),
        (0, "fold.points[28].receiver", "ann"),
        (0, "fold.points[29].receiver", "amy"),
    ]
    return make("S26-doubles-new-order-per-set", "Doubles: serving and receiving order changed at the start of set 2",
                ["§2.4 order may change at each set"], doubles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s27():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    lb.points(holds(12))
    lb.points("AAAAAAA")
    a = [
        (0, "fold.points[48].server", "ann"),
        (0, "fold.points[48].receiver", "bob"),
        (0, "fold.points[49].server", "ben"),
        (0, "fold.points[49].receiver", "ann"),
        (0, "fold.points[50].server", "ben"),
        (0, "fold.points[50].receiver", "amy"),
        (0, "fold.points[51].server", "amy"),
        (0, "fold.points[51].receiver", "ben"),
        (0, "fold.points[52].receiver", "bob"),
        (0, "fold.points[53].server", "bob"),
        (0, "fold.points[53].receiver", "ann"),
        (0, "fold.points[54].receiver", "amy"),
        (0, "fold.next.server", "ben"),
        (0, "fold.match.scoreline", "7-6(0)"),
    ]
    return make("S27-doubles-tiebreak", "Doubles tie-break continues the set rotation; next set carries the order over",
                ["§2.3 doubles TB", "§2.4"], doubles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s28():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    lb.points("AABBAB")
    before = lb.last_seq
    lb.point("A", decidingPointSide="ad")
    a = [
        (0, "fold.next.call", {"kind": "decidingPoint"}),
        (0, "fold.next.courtSide", None),
        (0, "fold.next.receiver", None),
        (1, "fold.points[6].courtSide", "ad"),
        (1, "fold.points[6].receiver", "ben"),
        (1, "fold.games[0].points", {"A": 4, "B": 3}),
    ]
    return make("S28-doubles-noad-deciding", "Doubles No-Ad deciding point: receiving team chose the ad court",
                ["§1.2 doubles"], doubles(NOAD_MTB), lb, [before, lb.last_seq], a)


@case
def s29():
    lb = LogBuilder()
    lb.point("A", "ace", serves=[{"result": "let"}, {"result": "in"}], strokeCount=1)
    lb.point("A", "winner", serves=[{"result": "fault", "faultType": "net"}, {"result": "let"}, {"result": "in"}],
             strokeCount=3)
    lb.point("A", "unforcedError", serves=[{"result": "let"}, {"result": "let"}, {"result": "fault", "faultType": "long"},
                                           {"result": "in"}], strokeCount=2)
    lb.point("B", "winner", serves=[{"result": "in"}], strokeCount=2)
    a = [
        (0, "fold.points[0].serveNumber", 1),
        (0, "fold.points[1].serveNumber", 2),
        (0, "fold.points[2].serveNumber", 2),
        (0, "fold.points[2].rallyLength", 1),
        (0, "fold.points[3].serveNumber", 1),
        (0, "stats.sides.A.firstServeIn", ratio(2, 4, 50)),
        (0, "stats.sides.A.firstServePointsWon", ratio(1, 2, 50)),
        (0, "stats.sides.A.secondServePointsWon", ratio(2, 2, 100)),
        (0, "stats.sides.A.aces", 1),
        (0, "stats.sides.A.winners", 1),
        (0, "stats.sides.B.winners", 1),
        (0, "stats.sides.B.unforcedErrors", 1),
        (0, "stats.shots", {"total": 8, "pointsWithStrokeCount": 4}),
        (0, "fold.conflicts", []),
    ]
    return make("S29-service-lets", "Service lets are not attempts and do not cancel an earlier fault",
                ["§3 Rule 22", "§6.1 first-serve attempts exclude lets"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s30():
    lb = LogBuilder()
    lb.point("B", "doubleFault", serves=[{"result": "fault", "faultType": "net"}, {"result": "fault", "faultType": "wide"}],
             strokeCount=0)
    lb.point("B", "doubleFault", serves=[{"result": "fault", "faultType": "footFault"},
                                         {"result": "fault", "faultType": "long"}], strokeCount=0)
    lb.point("A", "winner", serves=[{"result": "fault", "faultType": "net"}, {"result": "in"}], strokeCount=3)
    lb.point("B", "doubleFault", serves=[{"result": "fault", "cause": "timeViolation"},
                                         {"result": "fault", "faultType": "net"}], strokeCount=0)
    a = [
        (0, "fold.points[3].call", pts("15", "30")),
        (0, "fold.next.call", pts("15", "40")),
        (0, "stats.sides.A.doubleFaults", 3),
        (0, "stats.sides.A.secondServePointsWon", ratio(1, 4, 25)),
        (0, "stats.sides.A.secondServeIn", ratio(1, 4, 25)),
        (0, "stats.sides.A.firstServeIn", ratio(0, 4, 0)),
        (0, "stats.sides.A.firstServePointsWon", ratio(0, 0, None)),
        (0, "stats.rallyLength", {"0-4": 4, "5-8": 0, "9+": 0, "unknown": 0}),
    ]
    return make("S30-double-faults", "Double faults (incl. a time-violation fault) sit inside second-serve points; d = 0 shows '—'",
                ["§3 faults", "§6.1 2nd-serve points include DFs", "§7 d = 0"], singles(CLUB_BO3), lb,
                [lb.last_seq], a)


@case
def s31():
    lb = LogBuilder()
    lb.point("A")
    lb.rally_let()
    lb.point("A")
    a = [
        (0, "fold.points[1].pointInGame", 2),
        (0, "fold.points[1].courtSide", "ad"),
        (0, "fold.match.rallyLets", 1),
        (0, "fold.match.pointsPlayed", 2),
    ]
    return make("S31-rally-let", "Rally let: the whole point is replayed and consumes no point slot", ["§3 Rule 23"],
                singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s32():
    lb = LogBuilder()
    lb.points("AA")
    lb.penalty("point", "jon")
    lb.points("AA")
    a = [
        (0, "fold.points[2].kind", "penaltyPoint"),
        (0, "fold.points[2].endType", "penalty"),
        (0, "fold.points[2].winner", "B"),
        (0, "fold.points[2].courtSide", "deuce"),
        (0, "fold.points[3].call", pts("30", "15")),
        (0, "fold.points[3].courtSide", "ad"),
        (0, "stats.sides.B.penaltyPointsAwarded", 1),
        (0, "stats.sides.B.totalPointsWon", ratio(1, 5, 20)),
        (0, "stats.sides.A.servicePoints", 4),
        (0, "stats.sides.B.returnPointsWon", ratio(0, 4, 0)),
    ]
    return make("S32-point-penalty-mid-game", "Point penalty occupies a point slot; counts in total points only",
                ["§3 point penalty", "§6.2 TPW = SPW + RPW + penalties"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s33():
    lb = LogBuilder()
    lb.points("AAAA")
    lb.penalty("point", "alex")
    lb.points("BBBB")
    a = [
        (0, "fold.points[4].kind", "penaltyPoint"),
        (0, "fold.points[4].game", 1),
        (0, "fold.points[4].pointInGame", 1),
        (0, "fold.points[4].server", "alex"),
        (0, "fold.points[4].winner", "A"),
        (0, "fold.points[5].call", pts("0", "15")),
        (0, "fold.games[1].points", {"A": 1, "B": 4}),
        (0, "fold.games[1].winner", "B"),
        (0, "stats.sides.B.serviceGamesWon", ratio(1, 1, 100)),
    ]
    return make("S33-point-penalty-between-games", "Point penalty between games becomes the first point of the next game",
                ["§3 USTA IV.D.13-14"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s34():
    lb = LogBuilder()
    lb.points("AB")
    lb.penalty("game", "jon")
    a = [
        (0, "fold.games[0].winner", "B"),
        (0, "fold.games[0].byPenalty", True),
        (0, "fold.games[0].break", False),
        (0, "fold.games[0].points", {"A": 1, "B": 1}),
        (0, "fold.sets[0].games", {"A": 0, "B": 1}),
        (0, "fold.next.server", "alex"),
        (0, "fold.next.ends", {"A": "far", "B": "near"}),
        (0, "stats.sides.A.serviceGamesWon", ratio(0, 0, None)),
        (0, "stats.sides.B.returnGamesWon", ratio(0, 0, None)),
    ]
    return make("S34-game-penalty", "Game penalty: opponent awarded the game; excluded from service-game counts",
                ["§3 USTA Table 14", "§6.1 service games exclude penalty games"], singles(CLUB_BO3), lb,
                [lb.last_seq], a)


@case
def s35():
    lb = LogBuilder()
    lb.points(holds(12))
    lb.points("AB")
    lb.penalty("game", "jon")
    a = [
        (0, "fold.sets[0].games", {"A": 6, "B": 7}),
        (0, "fold.sets[0].tiebreak", {"A": 1, "B": 1}),
        (0, "fold.sets[0].winner", "B"),
        (0, "fold.sets[0].byPenalty", True),
        (0, "fold.match.scoreline", "6-7(1)"),
        (0, "fold.next.server", "alex"),
    ]
    return make("S35-game-penalty-in-tiebreak", "Game penalty during a set tie-break: the penalised side loses the set",
                ["§3 USTA Table 14"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s36():
    lb = LogBuilder()
    lb.points(holds(8) + "AAAA" + "AAAA")
    lb.points("AAAA" + "BBBB" + "AAAA" + "AAAA")
    lb.points("AB")
    lb.end("retirement", "alex", "injury")
    a = [
        (0, "fold.match.status", "retired"),
        (0, "fold.match.winner", "A"),
        (0, "fold.match.scoreline", "6-4 3-1 ret."),
        (0, "fold.sets[1].complete", False),
        (0, "fold.match.pointsPlayed", 58),
        (0, "stats.countedPoints", 58),
        (0, "fold.next", None),
    ]
    return make("S36-retirement", "Retirement mid-set: 6-4 3-1 ret.; stats over completed points",
                ["§1.6 terminations"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s37():
    lb = LogBuilder()
    lb.points("AB")
    lb.end("default", "jon", "pointPenaltySystem")
    a = [
        (0, "fold.match.status", "defaulted"),
        (0, "fold.match.winner", "B"),
        (0, "fold.match.scoreline", "0-0 def."),
    ]
    return make("S37-default", "Default under the point penalty system", ["§1.6 Def [pps]"], singles(CLUB_BO3), lb,
                [lb.last_seq], a)


@case
def s38():
    lb = LogBuilder()
    lb.end("walkover", "alex", "injury")
    a = [
        (0, "fold.match.status", "walkover"),
        (0, "fold.match.winner", "A"),
        (0, "fold.match.scoreline", "w/o"),
        (0, "stats.sides.A.totalPointsWon", ratio(0, 0, None)),
        (0, "stats.review.completion", ratio(0, 0, None)),
    ]
    return make("S38-walkover", "Walkover: no score, every denominator 0 shows '—'", ["§1.6 Wo", "§7 d = 0"],
                singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s39():
    lb = LogBuilder()
    for _ in range(3):
        lb.point("A", recordedServer="jon")
    p4 = lb.point("A", recordedServer="jon")
    for _ in range(4):
        lb.point("B", recordedServer="alex")
    for _ in range(2):
        lb.point("A", recordedServer="jon")
    before = lb.last_seq
    fix = lb.point("B", provenance="reviewed", recordedServer="jon", supersedes=p4, review_state="reviewed")
    a = [
        (0, "fold.conflicts", []),
        (0, "fold.games[0].points", {"A": 4, "B": 0}),
        (1, "fold.points[3].id", fix),
        (1, "fold.points[3].winner", "B"),
        (1, "fold.points[3].provenance", "reviewed"),
        (1, "fold.games[0].points", {"A": 3, "B": 5}),
        (1, "fold.games[0].break", True),
        (1, "fold.points[4].server", "jon"),
        (1, "fold.points[8].server", "alex"),
        (1, "fold.conflicts", [{"type": "serverMismatch", "pointId": f"e00{i}", "recorded": "alex", "derived": "jon"}
                               for i in range(5, 9)] +
         [{"type": "serverMismatch", "pointId": "e009", "recorded": "jon", "derived": "alex"},
          {"type": "serverMismatch", "pointId": "e010", "recorded": "jon", "derived": "alex"}]),
        (1, "fold.history.superseded", [{"id": p4, "by": fix}]),
        (1, "fold.changes.recalculatedPointIds", ["e005", "e006", "e007", "e008", "e009", "e010"]),
        (1, "stats.sides.A.serviceGamesWon", ratio(0, 1, 0)),
    ]
    return make("S39-correction-moves-service-game", "Correcting a game-winning point moves later points into a different service game",
                ["§0 rule 2", "§4.4 serverMismatch", "ADR-0003 supersede"], singles(CLUB_BO3), lb, [before, lb.last_seq], a)


def _tiebreak_flip_log(final_winner_first: str):
    lb = LogBuilder()
    lb.points(holds(10) + "AAAA")
    lb.points("BBAAA")
    flip = lb.point(final_winner_first)
    lb.points("BB" + "A" * 7)
    return lb, flip


@case
def s40():
    lb, flip = _tiebreak_flip_log("A")
    before = lb.last_seq
    lb.point("B", provenance="reviewed", supersedes=flip)
    a = [
        (0, "fold.match.scoreline", "7-5"),
        (0, "fold.conflicts", [{"type": "pointsAfterMatchEnd", "pointId": f"e0{i}"} for i in range(51, 60)]),
        (1, "fold.match.scoreline", "7-6(0)"),
        (1, "fold.conflicts", []),
        (1, "fold.points[52].tiebreak", "set"),
        (1, "fold.changes.tiebreakAppeared", [0]),
        (1, "fold.changes.matchIncomplete", False),
    ]
    return make("S40-correction-tiebreak-appears", "A correction turns 7-5 into 6-6: the tie-break appears and the points logged after the false match end count again",
                ["§4.4 tiebreakAppeared", "§4.4 pointsAfterMatchEnd"], singles(BEST_OF_1), lb, [before, lb.last_seq], a)


@case
def s41():
    lb, flip = _tiebreak_flip_log("B")
    before = lb.last_seq
    lb.point("A", provenance="reviewed", supersedes=flip)
    a = [
        (0, "fold.match.scoreline", "7-6(0)"),
        (1, "fold.match.scoreline", "7-5"),
        (1, "fold.points[50].afterMatchEnd", True),
        (1, "fold.changes.tiebreakVanished", [0]),
        (1, "fold.conflicts[0]", {"type": "pointsAfterMatchEnd", "pointId": "e051"}),
    ]
    return make("S41-correction-match-ends-earlier", "A correction ends the match earlier: later points are flagged, not deleted",
                ["§4.4 pointsAfterMatchEnd", "§4.4 tiebreakVanished"], singles(BEST_OF_1), lb, [before, lb.last_seq], a)


@case
def s42():
    lb = LogBuilder()
    lb.points(holds(8) + "AAAA" + "AAA")
    last = lb.point("A")
    before = lb.last_seq
    lb.point("B", provenance="reviewed", supersedes=last)
    a = [
        (0, "fold.match.status", "completed"),
        (0, "fold.match.scoreline", "6-4"),
        (1, "fold.match.status", "inProgress"),
        (1, "fold.changes.matchIncomplete", True),
        (1, "fold.next.call", pts("15", "40")),
        (1, "fold.match.scoreline", "5-4"),
    ]
    return make("S42-correction-match-incomplete", "A correction means the match no longer ends: result becomes in progress",
                ["§4.4 matchIncomplete"], singles(BEST_OF_1), lb, [before, lb.last_seq], a)


@case
def s43():
    lb = LogBuilder()
    ids = lb.points("AAAA")
    done = lb.last_seq
    undo = lb.void(ids[3])
    undone = lb.last_seq
    lb.void(undo)
    a = [
        (0, "fold.next.server", "alex"),
        (1, "fold.next.server", "jon"),
        (1, "fold.next.call", pts("40", "0")),
        (1, "fold.next.ends", {"A": "near", "B": "far"}),
        (1, "fold.games[0].complete", False),
        (1, "fold.history.voided", [ids[3]]),
        (2, "fold.next.server", "alex"),
        (2, "fold.history.voided", [undo]),
    ]
    return make("S43-undo-redo", "Undo (void) reopens the game and reverts server and ends; voiding the void redoes it",
                ["§4.3 undo"], singles(CLUB_BO3), lb, [done, undone, lb.last_seq], a)


@case
def s54():
    # Set 0 games 0-7 (servers A,B,A,B,...): A holds, B holds, A holds, A breaks, A holds, B holds, A holds, B holds.
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    lb.points("AAAA" "BBBB" "AAAA" "AAAA" "AAAA" "BBBB" "AAAA" "BBBB")
    lb.points("AAA" + "BBBBB")  # game 8: ann serves for 6-3 at 40-0 (set point), B breaks
    lb.points("BBBB" + "AAAA" + "AAAA")  # B holds (5-5), A holds, A breaks: 7-5 after 12 games
    prefix = lb.last_seq
    lb.doubles_order(1, "amy", "bob", "ann", "ben")  # team A is due (12 games: even parity)
    lb.points("AAAA")
    a = [
        (0, "fold.points[35].call", pts("40", "0")),
        (0, "fold.points[35].pressure.setPointFor", ["A"]),
        (0, "fold.sets[0].games", {"A": 7, "B": 5}),
        (0, "fold.next.server", "ann"),  # no set-1 order yet: team A carries ann forward
        (1, "fold.points[35].pressure.setPointFor", ["A"]),
        (1, "fold.sets[0].games", {"A": 7, "B": 5}),
        (1, "fold.games[12].server", "amy"),
        (1, "fold.points[52].receiver", "ben"),
        (1, "fold.next.server", "bob"),
        (1, "fold.conflicts", []),
    ]
    return make("S54-doubles-unconverted-set-point",
                "Doubles: a set point of the other parity goes unconverted; the hypothetical never opens a set, "
                "so a later per-set order still folds",
                ["§4.2 hypothetical folding", "§2.4 order may change at each set"], doubles(CLUB_BO3), lb,
                [prefix, lb.last_seq], a)


@case
def s55():
    # Set 0: A,A,B,A,B,A,B,A,A wins by game -> 6-3 after 9 games, so team B is due in set 1.
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    game8 = None
    for g, w in enumerate("AABABABAA"):
        ids = lb.points(w * 4)
        if g == 8:
            game8 = ids[0]
    lb.doubles_order(1, "ben", "ann", "amy", "bob")  # deuceReceivers are keyed by team: A amy, B bob
    order_id = lb.events[-1]["id"]
    lb.points("BBBB")
    before = lb.last_seq
    for _ in range(4):  # four missed B points before game 8: B breaks, 5-4; A then holds for 6-4 after 10 games
        lb.point("B", insertBefore=game8)
    a = [
        (0, "fold.sets[0].games", {"A": 6, "B": 3}),
        (0, "fold.games[9].server", "ben"),
        (0, "fold.conflicts", []),
        (1, "fold.sets[0].games", {"A": 6, "B": 4}),
        (1, "fold.games[10].server", "ann"),
        (1, "fold.conflicts", [{"type": "doublesOrderConflict", "eventId": order_id, "recorded": "ben",
                                "derived": "ann"}]),
    ]
    return make("S55-doubles-order-conflict-after-correction",
                "Doubles: a correction flips set-0 game parity; the stored set-1 order keeps each team's named server, "
                "the team order follows the rules, and a doublesOrderConflict is raised instead of stopping the fold",
                ["§2.4 Rule 14", "§4.4 corrections propagate", "decision 8"], doubles(CLUB_BO3), lb,
                [before, lb.last_seq], a)


@case
def s56():
    lb = LogBuilder()
    lb.points(holds(12))
    lb.points("AABA")
    lb.penalty("game", "jon")
    a = [
        (0, "fold.sets[0].tiebreak", {"A": 3, "B": 1}),
        (0, "fold.sets[0].winner", "B"),
        (0, "fold.match.scoreline", "6-7(3)"),
    ]
    return make("S56-game-penalty-ends-tiebreak-leader",
                "Game penalty against the tie-break leader: (x) is the loser's points even when the loser had more",
                ["§1.6 USTA I.E.1.d", "§3 USTA Table 14"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s57():
    lb = LogBuilder()
    lb.points("A" * 24 + "B" * 24)
    lb.points("AAAAAB")
    lb.penalty("game", "jon")
    a = [
        (0, "fold.sets[2].rule", "matchTiebreak"),
        (0, "fold.sets[2].tiebreak", {"A": 5, "B": 1}),
        (0, "fold.sets[2].byPenalty", True),
        (0, "fold.match.winner", "B"),
        (0, "fold.match.scoreline", "0-6 6-0 1-0(5)"),
    ]
    return make("S57-game-penalty-ends-match-tiebreak",
                "Game penalty ends a match tie-break: rendered 1-0(x) with the loser's points, not a bracket that "
                "would show the winner with fewer points",
                ["§1.6 USTA I.E.1.b", "§3 USTA Table 14"], singles(USTA_MTB), lb, [lb.last_seq], a)


@case
def s58():
    lb = LogBuilder()
    lb.points("BBB")
    lb.penalty("point", "jon")
    a = [
        (0, "fold.points[3].pressure.breakPoint", True),
        (0, "fold.games[0].break", True),
        (0, "stats.sides.B.returnGamesWon", ratio(1, 1, 100)),
        (0, "stats.sides.B.breakPointsConverted", ratio(1, 1, 100)),
        (0, "stats.sides.A.breakPointsSaved", ratio(0, 1, 0)),
        (0, "stats.sides.A.servicePoints", 3),
        (0, "stats.sides.B.returnPointsWon", ratio(3, 3, 100)),
    ]
    return make("S58-point-penalty-converts-break-point",
                "A point penalty on break point completes the break: it counts as a break point faced and converted "
                "(and nowhere else in serve or return stats)",
                ["§6.3 invariants", "§3 point penalty", "decision 4"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s59():
    lb = LogBuilder()
    lb.end("retirement", "alex", "injury")
    a = [
        (0, "fold.match.status", "walkover"),
        (0, "fold.match.winner", "A"),
        (0, "fold.match.scoreline", "w/o"),
        (0, "fold.sets", []),
        (0, "stats.sides.A.totalPointsWon", ratio(0, 0, None)),
    ]
    return make("S59-retirement-before-play", "Retirement logged before the first point is a walkover: Wo [inj], no score",
                ["§1.6 USTA Table 10"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s60():
    lb = LogBuilder()
    lb.point("A", "ace", serves=[{"result": "let"}, {"result": "in"}], strokeCount=1)
    a = [
        (0, "fold.conflicts", []),
        (0, "fold.points[0].serveNumber", 1),
        (0, "stats.sides.A.firstServeIn", ratio(1, 1, 100)),
    ]
    return make("S60-no-let-receiver-not-ready",
                "No-Let removes only the net-cord let (App VI, Rule 22.1.a); a receiver-not-ready let (22.1.b) "
                "is still a let, so a let serve in a No-Let format is not a conflict",
                ["§3 No-Let format", "§3 Rule 22"], singles(FAST4), lb, [lb.last_seq], a)


@case
def s61():
    lb = LogBuilder()
    first = lb.point("A")
    fixed = lb.point("B", supersedes=first)
    lb.point("A")
    corrected = lb.last_seq
    lb.void(first)
    voided = lb.last_seq
    added = lb.point("B", insertBefore=fixed)
    a = [
        (0, "fold.points[0].winner", "B"),
        (0, "fold.match.pointsPlayed", 2),
        (1, "fold.match.pointsPlayed", 1),
        (1, "fold.points[0].id", "e003"),
        (1, "fold.points[0].call", pts("0", "0")),
        (1, "fold.history.voided", [first]),
        (1, "fold.history.superseded", []),
        (2, "fold.points[0].id", added),
        (2, "fold.points[1].call", pts("0", "15")),
    ]
    return make("S61-void-corrected-original",
                "Voiding the first version of a corrected point removes the point (its correction is undone too); "
                "an insert aimed at the undone correction lands in the removed point's place",
                ["§4.3 undo", "ADR-0003 append-only log"], singles(CLUB_BO3), lb, [corrected, voided, lb.last_seq], a)


@case
def s44():
    lb = LogBuilder()
    lb.points("AA")
    detected = {"winner": "unknown", "endType": "unknown", "strokeCount": 5, "provenance": "estimated",
                "source": "model:rallySegmentation@0.1.0", "capabilityId": "rally.segmentation", "confidence": 0.62}
    unknown = lb._add({"type": "point", "detected": detected, "reviewState": "needsReview"})
    lb.points("AB")
    before = lb.last_seq
    lb.point("A", "winner", provenance="reviewed", supersedes=unknown, detected=detected, review_state="reviewed", strokeCount=5)
    a = [
        (0, "fold.match.provisional", True),
        (0, "fold.match.scoreline", None),
        (0, "fold.points[2].determined", True),
        (0, "fold.points[2].winner", None),
        (0, "fold.points[2].provenance", "estimated"),
        (0, "fold.points[3].determined", False),
        (0, "fold.points[3].before", None),
        (0, "fold.next", None),
        (0, "stats.provisional", True),
        (0, "stats.countedPoints", 2),
        (0, "stats.excludedPoints", 3),
        (1, "fold.match.provisional", False),
        (1, "fold.points[2].winner", "A"),
        (1, "fold.points[4].server", "alex"),
        (1, "stats.countedPoints", 5),
    ]
    return make("S44-unknown-outcome-provisional", "Unknown winner: later scores are provisional (never guessed) until reviewed",
                ["§0 rule 10", "D10 suggestions need review"], singles(CLUB_BO3), lb, [before, lb.last_seq], a)


@case
def s45():
    lb = LogBuilder()
    lb.points("AAAA")
    lb.checkpoint(0, 1, 0)
    lb.points("BBBB" + "AAAA")
    lb.checkpoint(0, 2, 1)
    a = [
        (0, "fold.checkpoints", [
            {"id": "e005", "set": 0, "called": {"A": 1, "B": 0}, "derived": {"A": 1, "B": 0}, "agrees": True},
            {"id": "e014", "set": 0, "called": {"A": 2, "B": 1}, "derived": {"A": 2, "B": 1}, "agrees": True}]),
        (0, "fold.conflicts", []),
    ]
    return make("S45-checkpoints-agree", "As-called changeover scores that agree with the rules-derived score",
                ["§4.5 checkpoint scoring"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s46():
    lb = LogBuilder()
    lb.points("AAAA")
    lb.checkpoint(0, 1, 0)
    lb.points("BBBB" + "AAAA")
    lb.checkpoint(0, 1, 2)
    a = [
        (0, "fold.checkpoints[1].agrees", False),
        (0, "fold.checkpoints[1].derived", {"A": 2, "B": 1}),
        (0, "fold.conflicts", [{"type": "checkpointConflict", "checkpointId": "e014",
                                "pointIds": [f"e{i:03d}" for i in range(6, 14)]}]),
        (0, "fold.sets[0].games", {"A": 2, "B": 1}),
    ]
    return make("S46-checkpoint-conflict", "An as-called score the log cannot reach flags only the stretch since the last checkpoint",
                ["§4.4 checkpointConflict", "§0 rule 3 as called vs derived"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s47():
    lb = LogBuilder()
    ids = lb.points("AAABA")
    lb.points("BBBB")
    before = lb.last_seq
    inserted = lb.point("A", insertBefore=ids[3])
    a = [
        (0, "fold.games[0].points", {"A": 4, "B": 1}),
        (1, "fold.points[3].id", inserted),
        (1, "fold.points[3].after.gameWon", True),
        (1, "fold.points[4].server", "alex"),
        (1, "fold.games[0].points", {"A": 4, "B": 0}),
        (1, "fold.games[1].points", {"A": 1, "B": 4}),
        (1, "fold.next.server", "jon"),
        (1, "fold.next.call", pts("0", "15")),
    ]
    return make("S47-insert-missed-point", "Adding a missed point shifts the game boundary for every later point",
                ["P0-10 add a missed point", "§0 rule 2"], singles(CLUB_BO3), lb, [before, lb.last_seq], a)


@case
def s48():
    lb = LogBuilder()
    det = {"winner": "A", "endType": "winner", "strokeCount": 3, "provenance": "estimated",
           "source": "model:pointOutcome@0.0.1", "capabilityId": "pointOutcome.auto", "confidence": 0.55}
    lb._add({"type": "point", "detected": det,
             "reviewed": {"winner": "B", "endType": "unforcedError", "strokeCount": 3, "provenance": "reviewed",
                          "source": "user"},
             "reviewState": "reviewed"})
    lb._add({"type": "point", "detected": det, "reviewState": "needsReview"})
    a = [
        (0, "fold.points[0].winner", "B"),
        (0, "fold.points[0].endType", "unforcedError"),
        (0, "fold.points[0].provenance", "reviewed"),
        (0, "fold.points[1].winner", "A"),
        (0, "fold.points[1].provenance", "estimated"),
        (0, "stats.review", {"reviewed": 1, "needsReview": 1, "unreviewed": 0, "completion": ratio(1, 2, 50)}),
    ]
    return make("S48-detected-vs-reviewed", "Effective outcome: the reviewed block wins; the detected block is kept",
                ["ADR-0003", "ADR-0004 provenance"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s49():
    lb = LogBuilder()
    lb.points(holds(8) + "AAAA" + "AABA" + "BBBB")
    a = [
        (0, "fold.points[40].call", pts("15", "40")),
        (0, "fold.points[40].pressure", pressure(game=["A"], bp=True, set_=["A"], match=["A"])),
        (0, "fold.points[42].call", {"kind": "deuce"}),
        (0, "fold.points[43].call", {"kind": "advantage", "side": "B"}),
        (0, "fold.points[43].pressure", pressure(game=["B"])),
        (0, "fold.sets[0].games", {"A": 5, "B": 5}),
    ]
    return make("S49-set-and-match-point", "Hypothetical folding: break point that is also set and match point",
                ["§4.2 hypothetical folding"], singles(BEST_OF_1), lb, [lb.last_seq], a)


@case
def s50():
    lb = LogBuilder()
    lb.points(holds(12))
    lb.points("AB" * 5 + "AA")
    a = [
        (0, "fold.points[48].after.endChange", True),
        (0, "fold.points[49].after.endChange", False),
        (0, "fold.points[52].after.endChange", True),
        (0, "fold.points[53].after.endChange", False),
        (0, "fold.points[56].after.endChange", True),
        (0, "fold.sets[0].tiebreak", {"A": 7, "B": 5}),
    ]
    return make("S50-coman-tiebreak", "Coman tie-break: ends change after point 1, then every 4 points",
                ["§2.3 Coman (App VI, USTA I.E.1.c)"], singles(COMAN_BO3), lb, [lb.last_seq], a)


@case
def s51():
    lb = LogBuilder()
    lb.points("A" * 24)
    lb.point("B")
    lb.end("retirement", "jon")
    a = [
        (0, "fold.match.scoreline", "6-0"),
        (0, "fold.points[24].afterMatchEnd", True),
        (0, "fold.conflicts", [{"type": "pointsAfterMatchEnd", "pointId": "e025"},
                               {"type": "eventAfterMatchEnd", "eventId": "e026"}]),
        (0, "stats.countedPoints", 24),
    ]
    return make("S51-points-after-match-end", "Points and events logged after the match end are flagged, not scored",
                ["§4.4 pointsAfterMatchEnd"], singles(BEST_OF_1), lb, [lb.last_seq], a)


@case
def s52():
    lb = LogBuilder()
    lb.point("A", "doubleFault", serves=[{"result": "fault"}, {"result": "fault"}], strokeCount=0)
    lb.point("A", "ace", strokeCount=3)
    lb.point("B", "winner", strokeCount=3)
    lb.point("A", "forcedError", strokeCount=2)
    a = [
        (0, "fold.conflicts", [{"type": "outcomeInconsistent", "pointId": "e001"},
                               {"type": "outcomeInconsistent", "pointId": "e002"},
                               {"type": "outcomeInconsistent", "pointId": "e003"}]),
        (0, "fold.points[3].rallyLength", 1),
        (0, "fold.next.call", pts("40", "15")),
    ]
    return make("S52-outcome-consistency", "End type must agree with the winner and stroke parity (C11); conflicts never stop the fold",
                ["§6.4 winner rule", "C11"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s53():
    lb = LogBuilder()
    lb.points(holds(3))
    lb.points("A")
    lb.points("ABBBB")
    a = [
        (0, "fold.games[3].server", "alex"),
        (0, "fold.games[3].points", {"A": 2, "B": 4}),
        (0, "stats.sides.A.longestPointStreak", 6),
        (0, "stats.sides.A.longestGameStreak", 1),
        (0, "stats.sides.B.longestPointStreak", 4),
        (0, "stats.momentum.series[9]", [6, 10]),
        (0, "stats.momentum.series[17]", [6, 10]),
    ]
    return make("S53-streaks-momentum", "Point and game streaks cross game boundaries; momentum prints window and denominator",
                ["§6.7 streaks and momentum"], singles(CLUB_BO3), lb, [lb.last_seq], a)


@case
def s62():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    ids = lb.points("AAAABB")
    before = lb.last_seq
    lb.doubles_order(0, "ann", "ben", "ann", "ben")  # re-entered: each team names its other partner to receive
    a = [
        (0, "fold.points[0].receiver", "bob"),
        (0, "fold.points[1].receiver", "ben"),
        (0, "fold.points[4].receiver", "amy"),
        (0, "fold.points[5].receiver", "ann"),
        (1, "fold.points[0].receiver", "ben"),
        (1, "fold.points[1].receiver", "bob"),
        (1, "fold.points[4].receiver", "ann"),
        (1, "fold.points[5].receiver", "amy"),
        (1, "fold.points[0].server", "ann"),
        (1, "fold.changes.recalculatedPointIds", ids),
        (1, "fold.conflicts", []),
    ]
    return make("S62-doubles-receivers-reentered",
                "Doubles: re-entering the set-0 receivers changes every point's receiver, and every one of them is "
                "reported as recalculated although score and server are unchanged",
                ["§2.4 Rule 15", "§4.4 recalculated: any flag or stat changed"], doubles(CLUB_BO3), lb,
                [before, lb.last_seq], a)


@case
def s63():
    lb = LogBuilder()
    lb.points(holds(6))
    lb.points("ABBAABBA")
    last = lb.point("B", decidingPointSide="ad")
    a = [
        (0, "fold.points[32].call", tbcall(4, 4)),
        (0, "fold.points[32].server", "jon"),
        (0, "fold.points[32].courtSide", "deuce"),
        (0, "fold.conflicts", [{"type": "decidingPointSideIgnored", "pointId": last, "recorded": "ad",
                                "derived": "deuce"}]),
        (0, "fold.sets[0].tiebreak", {"A": 4, "B": 5}),
    ]
    return make("S63-fast4-sudden-death-side-alternates",
                "Fast4 (UNVERIFIED, suddenDeathSide default alternate): the 4-4 point keeps the tie-break side parity; "
                "a recorded decidingPointSide is not used and is flagged, never silently dropped",
                ["§1.4 App VI.2", "decision 22"], singles(FAST4), lb, [lb.last_seq], a)


@case
def s64():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    lb.points(holds(6))
    lb.points("ABBAABBA")
    before = lb.last_seq
    lb.point("B", decidingPointSide="ad")
    a = [
        (0, "fold.next.call", tbcall(4, 4)),
        (0, "fold.next.server", "amy"),
        (0, "fold.next.courtSide", None),
        (0, "fold.next.receiver", None),
        (0, "fold.points[31].courtSide", "ad"),
        (1, "fold.points[32].server", "amy"),
        (1, "fold.points[32].courtSide", "ad"),
        (1, "fold.points[32].receiver", "ben"),
        (1, "fold.conflicts", []),
        (1, "fold.sets[0].games", {"A": 3, "B": 4}),
        (1, "fold.sets[0].tiebreak", {"A": 4, "B": 5}),
    ]
    return make("S64-short-set-tiebreak-receiver-chooses",
                "Short-set tie-break with suddenDeathSide receiverChooses: the 4-4 deciding point is served to the half "
                "the receiving team chose (null until recorded), like the No-Ad deciding point",
                ["§1.4 App VI.2", "§1.2 App VI No-Ad", "decision 22"], doubles(SHORT_SETS_TB5_RC), lb,
                [before, lb.last_seq], a)


# ----- invalid logs: platforms must reject them with the same code -----------------------------

@case
def e01():
    lb = LogBuilder()
    lb.points("AA")
    lb.events[1]["seq"] = 1
    return make("E01-seq-not-increasing", "Rejected: seq must strictly increase", ["log contract"], singles(CLUB_BO3),
                lb, [], [], {"code": "seqNotIncreasing"})


@case
def e02():
    lb = LogBuilder()
    lb.points("AA")
    lb.point("B", supersedes="missing")
    return make("E02-supersede-target-missing", "Rejected: supersedes an event that is not in the effective log",
                ["log contract"], singles(CLUB_BO3), lb, [], [], {"code": "supersedeTargetMissing"})


@case
def e03():
    lb = LogBuilder()
    lb.points("AA")
    return make("E03-doubles-order-missing", "Rejected: doubles needs a doublesOrder for set 0", ["§2.4"],
                doubles(CLUB_BO3), lb, [], [], {"code": "doublesOrderMissing"})


@case
def e04():
    lb = LogBuilder()
    lb.points("AA")
    lb.void("nope")
    return make("E04-void-target-missing", "Rejected: void of an unknown event", ["log contract"], singles(CLUB_BO3), lb,
                [], [], {"code": "voidTargetMissing"})


@case
def e05():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "ben", "amy")  # team A names ben (team B) and team B names amy (team A)
    lb.points("AA")
    return make("E05-doubles-receiver-wrong-team",
                "Rejected: under Rule 15 each team names one of its own players as deuce-court receiver",
                ["§2.4 Rule 15", "decision 21"], doubles(CLUB_BO3), lb, [], [], {"code": "doublesOrderInvalid"})


@case
def e06():
    lb = LogBuilder()
    lb.points("AA")
    lb.penalty("point", "zed")
    return make("E06-unknown-player-penalty", "Rejected: a penalty names a player who is not in sides",
                ["log contract", "decision 21"], singles(CLUB_BO3), lb, [], [], {"code": "unknownPlayer"})


@case
def e07():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "zed", "bob")
    lb.points("AA")
    return make("E07-unknown-player-doubles-receiver", "Rejected: a doubles order names a receiver who is not in sides",
                ["§2.4", "decision 21"], doubles(CLUB_BO3), lb, [], [], {"code": "unknownPlayer"})


@case
def e08():
    lb = LogBuilder()
    lb.points("AA")
    return make("E08-unknown-toss-first-server", "Rejected: toss.firstServer is not in sides",
                ["§2.1 Rule 9", "decision 21"], singles(CLUB_BO3, first="zed"), lb, [], [], {"code": "unknownPlayer"})


@case
def e09():
    lb = LogBuilder()
    lb.doubles_order(0, "ann", "ben", "amy", "bob")
    lb.points("AA")
    lb.doubles_order(1, "amy", "ann", "amy", "bob")
    return make("E09-doubles-order-invalid-unreached-set",
                "Rejected: every active doubles order is validated up front, even for a set the log has not reached, so "
                "a later correction can never make the log unfoldable",
                ["§2.4 Rule 14", "decision 13", "decision 21"], doubles(CLUB_BO3), lb, [], [],
                {"code": "doublesOrderInvalid"})


@case
def e10():
    lb = LogBuilder()
    lb.points("AA")
    bad = lb.end("retirement", "zed")
    lb.void(bad)
    return make("E10-unknown-player-voided-event",
                "Rejected: player fields are checked on every logged event, voided ones included (like unknownEventType)",
                ["log contract", "decision 21"], singles(CLUB_BO3), lb, [], [], {"code": "unknownPlayer"})


def generate(ctx) -> int:
    """Write spec/fixtures/scoring/<id>.json for every case; refuse all of them if any hand assertion disagrees."""
    out = ctx.fixtures / "scoring"
    failures = []
    for build in CASES:
        c = build()
        fixture_input = dict(c["setup"])
        fixture_input["log"] = c["log"]
        assertions = [{"checkpoint": cp, "path": path, "equals": value} for cp, path, value in c["assertions"]]
        doc = {
            "schemaVersion": ctx.version,
            "kind": "jovra.fixture.scoring",
            "id": c["id"],
            "title": c["title"],
            "covers": c["covers"],
            "input": fixture_input,
        }
        if c["expectError"] is not None:
            code = conformance.run_scoring_error(fixture_input)
            if code != c["expectError"]["code"]:
                failures.append(f"{c['id']}: expected error {c['expectError']['code']}, engine {code}")
                continue
            doc["expectError"] = c["expectError"]
        else:
            checkpoints = conformance.run_scoring(fixture_input, c["checkpoints"])
            problems = conformance.check_assertions(checkpoints, assertions)
            if problems:
                failures += [f"{c['id']}: {p}" for p in problems]
                continue
            doc["assertions"] = assertions
            doc["checkpoints"] = checkpoints
        ctx.write_json(out / f"{c['id']}.json", doc)
    if failures:
        raise SystemExit("\n".join(failures) + f"\n{len(failures)} hand assertion(s) disagree with the engine; "
                         "nothing trusted")
    return len(CASES)
