"""The scoring fold: a pure function from (setup, event log) to every derived match state.

Rules: docs/research/tennis-rules-and-stats.md §0-§4. Nothing here reads a clock or a random source;
the same input always yields the same output, which is what the conformance fixtures pin.
"""

from __future__ import annotations

import copy
from typing import Any

from .log import LogError, resolve

SIDES = ("A", "B")
POINT_LABELS = ("0", "15", "30", "40")
END_TYPES_SERVER_ONLY = ("ace", "serviceWinner")
ERROR_END_TYPES = ("forcedError", "unforcedError")


def other(side: str) -> str:
    return "B" if side == "A" else "A"


def _ab(a: int = 0, b: int = 0) -> dict:
    return {"A": a, "B": b}


class Match:
    """Mutable match state. Only ``fold`` drives it; ``clone`` supports hypothetical folding."""

    def __init__(self, setup: dict, doubles_orders: dict):
        self.fmt = setup["format"]
        self.sides = setup["sides"]
        self.side_of = {pid: s for s in SIDES for pid in self.sides[s]}
        self.doubles = len(self.sides["A"]) == 2
        toss = setup["toss"]
        self.first_server = toss["firstServer"]
        self.first_side = self.side_of[self.first_server]
        self.ends = dict(toss["startingEnds"])
        self.doubles_orders = doubles_orders
        self.sets: list[dict] = []
        self.sets_won = _ab()
        self.set_index = 0
        self.match_game = 0
        self.game_in_set = 0
        self.games = _ab()
        self.pts = _ab()
        self.point_in_game = 0
        self.tb: dict | None = None
        self.set_rule: dict = {}
        self.over = False
        self.status = "notStarted"
        self.winner: str | None = None
        self.rotation: list[str] = []
        self.deuce_receivers: dict = {}
        self.game_records: list[dict] = []
        self.game_start_server: str | None = None
        self.game_has_penalty = False
        self.hypothetical = False  # a pressure probe: never opens the next set
        self.pending_conflicts: list[dict] = []  # raised while starting a set; the fold drains them
        self._start_set()

    def clone(self) -> "Match":
        return copy.deepcopy(self)

    # ----- format helpers -------------------------------------------------------------------
    def _rule_for_set(self) -> dict:
        deciding = self.sets_won["A"] == self.sets_won["B"] == self.fmt["setsToWin"] - 1
        if deciding and "finalSet" in self.fmt:
            return self.fmt["finalSet"]
        return self.fmt["set"]

    def _tb_config(self, rule: dict, kind: str) -> dict:
        tb = rule["tiebreak"]
        return {
            "kind": kind,
            "points": tb["points"],
            "suddenDeathAt": tb.get("suddenDeathAt"),
            "endChange": tb.get("endChange", "every6"),
            "suddenDeathSide": tb.get("suddenDeathSide", "alternate"),
        }

    def _start_set(self) -> None:
        self.set_rule = self._rule_for_set()
        self.games = _ab()
        self.game_in_set = 0
        self.tb = None
        if self.set_rule["kind"] == "matchTiebreak":
            self.tb = self._tb_config(self.set_rule, "match")
        if self.doubles:
            self._start_doubles_set()

    def _team_serving_first_in_set(self) -> str:
        return self.first_side if self.match_game % 2 == 0 else other(self.first_side)

    def _start_doubles_set(self) -> None:
        """Rule 14: each team names its own server for the set; which team serves first follows from
        match-game parity. A stored order naming the other team first (a correction changed the parity)
        keeps each team's named server, takes the team order from the rules and raises a
        ``doublesOrderConflict`` instead of stopping the fold (decision 8). Every active order was
        already validated by ``validate_log`` before the fold started."""
        team = self._team_serving_first_in_set()
        order = self.doubles_orders.get(self.set_index)
        if order is not None:
            first, second = order["firstServer"], order["secondServer"]
            receivers = dict(order["deuceReceivers"])
            if self.side_of[first] != team:
                first, second = second, first
                self.pending_conflicts.append(
                    {"type": "doublesOrderConflict", "eventId": order["id"], "recorded": second, "derived": first}
                )
        else:
            if self.set_index == 0:
                raise LogError("doublesOrderMissing", "set 0 needs a doublesOrder event")
            prev = self.rotation
            first = next(p for p in prev if self.side_of[p] == team)
            second = next(p for p in prev if self.side_of[p] == other(team))
            receivers = dict(self.deuce_receivers)
        self.rotation = [first, second, self.partner(first), self.partner(second)]
        self.deuce_receivers = receivers

    def partner(self, pid: str) -> str:
        team = self.sides[self.side_of[pid]]
        return team[1] if team[0] == pid else team[0]

    # ----- derived per-point facts ------------------------------------------------------------
    def server(self) -> str:
        n = self.point_in_game + 1
        offset = n // 2 if self.tb else 0
        if not self.doubles:
            side = self.first_side if (self.match_game + offset) % 2 == 0 else other(self.first_side)
            return self.sides[side][0]
        return self.rotation[(self.game_in_set + offset) % 4]

    def is_deciding_point(self) -> bool:
        return (
            self.tb is None
            and self.fmt["gameScoring"] == "noAd"
            and self.pts["A"] == 3
            and self.pts["B"] == 3
        )

    def side_is_chosen(self) -> bool:
        """True when the receiver(s) choose the half: the No-Ad deciding point (App VI), and the
        sudden-death point of a tie-break whose format says ``suddenDeathSide: receiverChooses``
        (App VI.2 leaves serve order to the sanctioning body, so the default is ``alternate``;
        decision 22)."""
        if self.is_deciding_point():
            return True
        tb = self.tb
        return (
            tb is not None
            and tb["suddenDeathSide"] == "receiverChooses"
            and tb["suddenDeathAt"] is not None
            and self.pts["A"] == self.pts["B"] == tb["suddenDeathAt"]
        )

    def court_side(self, deciding_point_side: str | None) -> str | None:
        if self.side_is_chosen():
            return deciding_point_side
        return "deuce" if (self.point_in_game + 1) % 2 == 1 else "ad"

    def receiver(self, server: str, court_side: str | None) -> str | None:
        team = other(self.side_of[server])
        if not self.doubles:
            return self.sides[team][0]
        if court_side is None:
            return None
        deuce = self.deuce_receivers[team]
        return deuce if court_side == "deuce" else self.partner(deuce)

    def call(self, server_side: str) -> dict:
        s, r = self.pts[server_side], self.pts[other(server_side)]
        if self.tb:
            return {"kind": "tiebreak", "server": s, "receiver": r}
        if self.is_deciding_point():
            return {"kind": "decidingPoint"}
        if s >= 3 and r >= 3:
            if s == r:
                return {"kind": "deuce"}
            return {"kind": "advantage", "side": server_side if s > r else other(server_side)}
        return {"kind": "points", "server": POINT_LABELS[s], "receiver": POINT_LABELS[r]}

    def score_before(self) -> dict:
        return {"sets": dict(self.sets_won), "games": dict(self.games), "points": dict(self.pts)}

    def pressure(self, server_side: str) -> dict:
        game_for, set_for, match_for = [], [], []
        for side in SIDES:
            probe = self.clone()
            probe.hypothetical = True
            result = probe.apply_point(side)
            if result["gameWon"]:
                game_for.append(side)
            if result["setWon"]:
                set_for.append(side)
            if result["matchWon"]:
                match_for.append(side)
        return {
            "gamePointFor": game_for,
            "breakPoint": self.tb is None and other(server_side) in game_for,
            "setPointFor": set_for,
            "matchPointFor": match_for,
        }

    def tiebreak_kind(self) -> str | None:
        return self.tb["kind"] if self.tb else None

    # ----- transitions ------------------------------------------------------------------------
    def _game_won_by(self, w: str) -> bool:
        p, q = self.pts[w], self.pts[other(w)]
        if self.tb:
            target, sd = self.tb["points"], self.tb["suddenDeathAt"]
            if p < target:
                return False
            return p - q >= 2 or (sd is not None and p == sd + 1 and q == sd)
        if self.fmt["gameScoring"] == "noAd":
            return p >= 4
        return p >= 4 and p - q >= 2

    def _tb_end_change(self, n: int) -> bool:
        rule = self.tb["endChange"]
        if rule == "coman":
            return n == 1 or (n > 1 and (n - 1) % 4 == 0)
        if rule == "after4":
            return n == 4
        return n % 6 == 0

    def _flip_ends(self) -> None:
        self.ends = {"A": self.ends["B"], "B": self.ends["A"]}

    def apply_point(self, w: str, penalty: bool = False, observed_server: str | None = None) -> dict:
        """Apply one point slot won by side ``w``. Returns what closed and the rest that follows."""
        if self.status == "notStarted":
            self.status = "inProgress"
        if self.point_in_game == 0:
            self.game_start_server = observed_server or self.server()
            self.game_has_penalty = False
        self.game_has_penalty = self.game_has_penalty or penalty
        self.pts[w] += 1
        self.point_in_game += 1
        if self._game_won_by(w):
            return self._complete_game(w, by_penalty=False)
        end_change = False
        if self.tb and self._tb_end_change(self.point_in_game):
            self._flip_ends()
            end_change = True
        return {
            "gameWon": False,
            "setWon": False,
            "matchWon": False,
            "endChange": end_change,
            "rest": "changeoverNoRest" if end_change else "point",
        }

    def award_game(self, w: str) -> dict:
        """Game penalty: side ``w`` is awarded the current (or next) game."""
        if self.status == "notStarted":
            self.status = "inProgress"
        if self.point_in_game == 0:
            self.game_start_server = self.server()
        return self._complete_game(w, by_penalty=True)

    def _complete_game(self, w: str, by_penalty: bool) -> dict:
        tb = self.tb
        kind = "standard" if tb is None else ("matchTiebreak" if tb["kind"] == "match" else "tiebreak")
        record = {
            "index": self.match_game,
            "set": self.set_index,
            "gameInSet": self.game_in_set,
            "kind": kind,
            "server": self.game_start_server,
            "serverSide": self.side_of[self.game_start_server],
            "winner": w,
            "points": dict(self.pts),
            "byPenalty": by_penalty,
            "complete": True,
        }
        record["break"] = kind == "standard" and not by_penalty and w != record["serverSide"]
        self.game_records.append(record)
        game_number = self.game_in_set + 1
        self.games[w] += 1
        rule = self.set_rule
        if tb is not None:
            set_won = True
        else:  # tie-break set and advantage set share the win condition; only the 6-6 trigger differs
            set_won = self.games[w] >= rule["games"] and self.games[w] - self.games[other(w)] >= 2
        tb_points = dict(self.pts) if tb is not None else None
        self.match_game += 1
        self.game_in_set += 1
        self.pts = _ab()
        self.point_in_game = 0
        self.tb = None
        end_change = game_number % 2 == 1
        result = {"gameWon": True, "setWon": False, "matchWon": False}
        if set_won:
            self.sets.append(
                {
                    "index": self.set_index,
                    "rule": rule["kind"],
                    "games": dict(self.games),
                    "tiebreak": tb_points,
                    "winner": w,
                    "complete": True,
                    "byPenalty": by_penalty,
                }
            )
            self.sets_won[w] += 1
            result["setWon"] = True
            if self.sets_won[w] == self.fmt["setsToWin"]:
                self.over = True
                self.status = "completed"
                self.winner = w
                result["matchWon"] = True
                result["endChange"] = False
                result["rest"] = "matchEnd"
                return result
            self.set_index += 1
            if end_change:
                self._flip_ends()
            if not self.hypothetical:
                self._start_set()
            result["endChange"] = end_change
            result["rest"] = "setBreak"
            return result
        if (
            rule["kind"] == "tiebreakSet"
            and self.games["A"] == rule["tiebreakAt"]
            and self.games["B"] == rule["tiebreakAt"]
        ):
            self.tb = self._tb_config(rule, "set")
        if end_change:
            self._flip_ends()
        result["endChange"] = end_change
        if not end_change:
            result["rest"] = "point"
        else:
            result["rest"] = "changeoverNoRest" if game_number == 1 else "changeover"
        return result

    def end_by(self, status: str, losing_player: str) -> None:
        self.over = True
        self.status = status
        self.winner = other(self.side_of[losing_player])

    def current_set_record(self) -> dict | None:
        if self.status == "completed" or (self.games == _ab() and self.point_in_game == 0):
            return None
        return {
            "index": self.set_index,
            "rule": self.set_rule["kind"],
            "games": dict(self.games),
            "tiebreak": dict(self.pts) if self.tb else None,
            "winner": None,
            "complete": False,
            "byPenalty": False,
        }

    def current_game_record(self) -> dict | None:
        if self.point_in_game == 0:
            return None
        tb = self.tb
        kind = "standard" if tb is None else ("matchTiebreak" if tb["kind"] == "match" else "tiebreak")
        return {
            "index": self.match_game,
            "set": self.set_index,
            "gameInSet": self.game_in_set,
            "kind": kind,
            "server": self.game_start_server,
            "serverSide": self.side_of[self.game_start_server],
            "winner": None,
            "points": dict(self.pts),
            "byPenalty": False,
            "complete": False,
            "break": False,
        }


# ----- outcome interpretation ---------------------------------------------------------------------

def effective_outcome(event: dict) -> dict:
    """ADR-0003: the reviewed block wins when present; otherwise the detected block. Whole-block rule."""
    if "reviewed" in event:
        return event["reviewed"]
    return event["detected"]


def serve_number(outcome: dict) -> tuple[int | None, bool]:
    """Return ``(serveNumber, consistent)``. Lets are never attempts (Rule 22)."""
    end_type = outcome.get("endType", "unknown")
    attempts = [s["result"] for s in outcome.get("serves", []) if s["result"] != "let"]
    if end_type == "doubleFault":
        return 2, attempts in ([], ["fault", "fault"])
    if not attempts:
        return None, True
    if attempts == ["in"]:
        return 1, True
    if attempts in (["fault"], ["fault", "in"]):
        return 2, True
    return None, False


def derived_rally_length(outcome: dict) -> int | None:
    if "rallyLength" in outcome:
        return outcome["rallyLength"]
    n = outcome.get("strokeCount")
    end_type = outcome.get("endType", "unknown")
    if end_type == "doubleFault":
        return 0
    if n is None:
        return None
    if end_type in ERROR_END_TYPES or (end_type == "serviceWinner" and n == 2):
        return n - 1
    if end_type in ("winner", "ace", "serviceWinner"):
        return n
    return None


def outcome_consistent(outcome: dict, winner: str, server_side: str) -> bool:
    """Exactly one end type per point, consistent with its winner and stroke parity (C11)."""
    end_type = outcome.get("endType", "unknown")
    n = outcome.get("strokeCount")
    if end_type == "doubleFault":
        return winner != server_side and n in (None, 0)
    if end_type == "ace":
        return winner == server_side and n in (None, 1)
    if end_type == "serviceWinner":
        return winner == server_side and n in (None, 1, 2)
    if end_type == "penalty":
        return False  # penalty points come only from penalty events
    if n is not None and end_type in ("winner",) + ERROR_END_TYPES:
        if n < 2:
            return False
        last_hitter = server_side if n % 2 == 1 else other(server_side)
        if end_type == "winner":
            return last_hitter == winner
        return last_hitter != winner
    return True


# ----- the fold ---------------------------------------------------------------------------------

PLAYER_FIELDS = {
    "penalty": ("player",),
    "retirement": ("player",),
    "default": ("player",),
    "walkover": ("player",),
    "point": ("recordedServer",),
    "doublesOrder": ("firstServer", "secondServer"),
}


def validate_log(setup: dict, log: list[dict], doubles_orders: dict) -> None:
    """Structural checks that need the setup (decision 21). Run once, before the fold, over the whole log
    (voided events included, like ``unknownEventType``), so no correction, insert or void can make a
    foldable log unfoldable later and no port ever indexes a player that does not exist.

    * ``unknownPlayer``: ``toss.firstServer`` or any player field of any event names nobody in ``sides``.
    * ``doublesOrderInvalid`` (doubles, every active order, reached or not): the two servers are on one
      team; a team's deuce-court receiver is not one of its own players (Rule 15: each team decides which
      of ITS players receives); set 0's first server is not the toss first server.
    """
    sides = setup["sides"]
    side_of = {pid: s for s in SIDES for pid in sides[s]}
    if setup["toss"]["firstServer"] not in side_of:
        raise LogError("unknownPlayer", f"toss.firstServer {setup['toss']['firstServer']!r}")
    for e in log:
        names = [e[k] for k in PLAYER_FIELDS.get(e["type"], ()) if k in e]
        if e["type"] == "doublesOrder":
            names += [e["deuceReceivers"][s] for s in SIDES]
        for pid in names:
            if pid not in side_of:
                raise LogError("unknownPlayer", f"{e['id']} names {pid!r}")
    if len(sides["A"]) != 2:
        return
    for set_index, order in sorted(doubles_orders.items()):
        first, second = order["firstServer"], order["secondServer"]
        if side_of[first] == side_of[second]:
            raise LogError("doublesOrderInvalid", f"set {set_index} servers must be on different teams")
        for s in SIDES:
            if side_of[order["deuceReceivers"][s]] != s:
                raise LogError("doublesOrderInvalid", f"set {set_index} team {s} receiver is not on team {s}")
        if set_index == 0 and first != setup["toss"]["firstServer"]:
            raise LogError("doublesOrderInvalid", "set 0 firstServer must equal toss.firstServer")


def fold(setup: dict, log: list[dict], mode: str | None = None) -> dict:
    if mode is not None: setup = {**setup, "resolutionMode": mode}
    placed, doubles_orders, history = resolve(log)
    validate_log(setup, log, doubles_orders)
    from .order_overrides import OrderOverrides
    overrides = OrderOverrides(setup, log, placed)
    m = Match(setup, doubles_orders)
    points: list[dict] = []
    conflicts: list[dict] = []
    checkpoints: list[dict] = []
    rally_lets: list[str] = []
    determined = True
    stretch: list[str] = []

    for event in placed:
        etype = event["type"]
        if etype in ("serverOverride", "receiverOverride"): continue
        if etype == "rallyLet":
            rally_lets.append(event["id"])
            continue
        if etype == "checkpoint":
            checkpoints.append(_checkpoint(m, event, determined, stretch, conflicts))
            stretch = []
            continue
        if etype in ("retirement", "default", "walkover"):
            if m.over:
                conflicts.append({"type": "eventAfterMatchEnd", "eventId": event["id"]})
                continue
            if etype == "walkover" and m.status != "notStarted":
                conflicts.append({"type": "walkoverAfterPlay", "eventId": event["id"]})
                continue
            status = {"retirement": "retired", "default": "defaulted", "walkover": "walkover"}[etype]
            if etype == "retirement" and m.status == "notStarted":
                status = "walkover"  # USTA Table 10: unable to start the match is Wo [inj/ill/pc], no score
            m.end_by(status, event["player"])
            continue
        if etype == "penalty" and event["kind"] == "game":
            if m.over:
                conflicts.append({"type": "eventAfterMatchEnd", "eventId": event["id"]})
                continue
            if determined:
                m.award_game(other(m.side_of[event["player"]]))
                conflicts.extend(m.pending_conflicts)
                m.pending_conflicts = []
            continue

        # A point slot: a played point or a point penalty.
        is_penalty = etype == "penalty"
        record = {"id": event["id"], "index": len(points), "kind": "penaltyPoint" if is_penalty else "point"}
        if is_penalty:
            outcome = {"endType": "penalty", "provenance": event.get("provenance", "manual")}
            winner = other(m.side_of[event["player"]])
        else:
            outcome = effective_outcome(event)
            winner = outcome["winner"] if outcome["winner"] in SIDES else None
        stretch.append(event["id"])

        if m.over:
            record.update(_undetermined(event, outcome, winner))
            record["afterMatchEnd"] = True
            conflicts.append({"type": "pointsAfterMatchEnd", "pointId": event["id"]})
            points.append(record)
            continue
        if not determined:
            record.update(_undetermined(event, outcome, winner))
            points.append(record)
            continue

        server = overrides.before_point(m, event, winner, conflicts)
        server_side = m.side_of[server]
        side = m.court_side(event.get("decidingPointSide"))
        record.update(
            {
                "determined": True,
                "afterMatchEnd": False,
                "set": m.set_index,
                "game": m.match_game,
                "gameInSet": m.game_in_set,
                "tiebreak": m.tiebreak_kind(),
                "pointInGame": m.point_in_game + 1,
                "server": server,
                "receiver": overrides.receiver(m, server, side),
                "serverSide": server_side,
                "courtSide": side,
                "ends": dict(m.ends),
                "before": m.score_before(),
                "call": m.call(server_side),
                "pressure": m.pressure(server_side),
            }
        )
        if "decidingPointSide" in event and not m.side_is_chosen():
            conflicts.append(
                {
                    "type": "decidingPointSideIgnored",
                    "pointId": event["id"],
                    "recorded": event["decidingPointSide"],
                    "derived": side,
                }
            )
        if event["id"] not in overrides.servers and "recordedServer" in event and event["recordedServer"] != server:
            conflicts.append(
                {
                    "type": "serverMismatch",
                    "pointId": event["id"],
                    "recorded": event["recordedServer"],
                    "derived": server,
                }
            )
        record.update(_outcome_fields(event, outcome, winner, is_penalty))
        if winner is None:
            determined = False
            record["after"] = None
            points.append(record)
            continue
        if not is_penalty:
            _, ok = serve_number(outcome)
            if not ok or not outcome_consistent(outcome, winner, server_side):
                conflicts.append({"type": "outcomeInconsistent", "pointId": event["id"]})
        result = m.apply_point(winner, penalty=is_penalty, observed_server=server)
        conflicts.extend(m.pending_conflicts)
        m.pending_conflicts = []
        record["after"] = {
            "gameWon": result["gameWon"],
            "setWon": result["setWon"],
            "matchWon": result["matchWon"],
            "endChange": result["endChange"],
            "rest": result["rest"],
        }
        points.append(record)

    sets = list(m.sets)
    if determined:
        current = m.current_set_record()
        if current is not None:
            sets.append(current)
    games = list(m.game_records)
    if determined:
        current_game = m.current_game_record()
        if current_game is not None:
            games.append(current_game)

    match = {
        "status": m.status,
        "doubles": m.doubles,
        "winner": m.winner,
        "provisional": not determined,
        "setsWon": dict(m.sets_won),
        "scoreline": scoreline(sets, m.status, m.winner) if determined else None,
        "pointsPlayed": sum(1 for p in points if not p["afterMatchEnd"]),
        "rallyLets": len(rally_lets),
    }
    nxt = None
    if determined and not m.over:
        server = m.server()
        server_side = m.side_of[server]
        side = m.court_side(None)
        nxt = {
            "set": m.set_index,
            "game": m.match_game,
            "gameInSet": m.game_in_set,
            "tiebreak": m.tiebreak_kind(),
            "pointInGame": m.point_in_game + 1,
            "server": server,
            "receiver": overrides.receiver(m, server, side),
            "serverSide": server_side,
            "courtSide": side,
            "ends": dict(m.ends),
            "before": m.score_before(),
            "call": m.call(server_side),
            "pressure": m.pressure(server_side),
        }
    return {
        "match": match,
        "sets": sets,
        "games": games,
        "points": points,
        "next": nxt,
        "checkpoints": checkpoints,
        "conflicts": conflicts,
        "history": history,
    }


def _outcome_fields(event: dict, outcome: dict, winner: str | None, is_penalty: bool) -> dict:
    number = None if is_penalty else serve_number(outcome)[0]
    fields = {
        "winner": winner,
        "endType": outcome.get("endType", "unknown"),
        "serveNumber": number,
        "strokeCount": None if is_penalty else outcome.get("strokeCount"),
        "rallyLength": None if is_penalty else derived_rally_length(outcome),
        "provenance": outcome.get("provenance", "manual"),
        "reviewState": event.get("reviewState", "unreviewed") if not is_penalty else "reviewed",
    }
    if "tStartMs" in event:
        fields["tStartMs"] = event["tStartMs"]
    if "tEndMs" in event:
        fields["tEndMs"] = event["tEndMs"]
    return fields


def _undetermined(event: dict, outcome: dict, winner: str | None) -> dict:
    record = {
        "determined": False,
        "afterMatchEnd": False,
        "set": None,
        "game": None,
        "gameInSet": None,
        "tiebreak": None,
        "pointInGame": None,
        "server": None,
        "receiver": None,
        "serverSide": None,
        "courtSide": None,
        "ends": None,
        "before": None,
        "call": None,
        "pressure": None,
    }
    record.update(_outcome_fields(event, outcome, winner, event["type"] == "penalty"))
    record["after"] = None
    return record


def _checkpoint(m: Match, event: dict, determined: bool, stretch: list[str], conflicts: list) -> dict:
    set_index = event["setIndex"]
    called = event["games"]
    derived = None
    if determined:
        if set_index < len(m.sets):
            derived = dict(m.sets[set_index]["games"])
        elif set_index == m.set_index and not m.over:
            derived = dict(m.games)
    agrees = None if not determined else derived == called
    if agrees is False:
        conflicts.append(
            {"type": "checkpointConflict", "checkpointId": event["id"], "pointIds": list(stretch)}
        )
    return {"id": event["id"], "set": set_index, "called": dict(called), "derived": derived, "agrees": agrees}


# ----- display ----------------------------------------------------------------------------------

def set_text(s: dict, first: str) -> str:
    """USTA I.E.1.d: ``(x)`` is the tie-break LOSER's points, which a game penalty can make the larger
    total. A match tie-break renders ``[10-8]``; one ended by a game penalty renders ``1-0(x)`` (USTA
    I.E.1.b's other form), because brackets would show the winner with fewer points."""
    a, b = s["games"][first], s["games"][other(first)]
    tb = s["tiebreak"]
    if s["rule"] == "matchTiebreak" and tb is not None and not (s["complete"] and s["byPenalty"]):
        return f"[{tb[first]}-{tb[other(first)]}]"
    text = f"{a}-{b}"
    if tb is not None and s["complete"]:
        text += f"({tb[other(s['winner'])]})"
    return text


def scoreline(sets: list[dict], status: str, winner: str | None) -> str:
    """Winner first when there is a winner, otherwise side A first (USTA recording conventions)."""
    if status == "walkover":
        return "w/o"
    first = winner or "A"
    parts = [set_text(s, first) for s in sets]
    if status == "retired":
        parts.append("ret.")
    elif status == "defaulted":
        parts.append("def.")
    return " ".join(parts)


def call_text(call: dict | None, server_side: str | None) -> str:
    """Language-neutral score call, server first: "30-15", "40-40" (deuce / deciding point), "AD-40"."""
    if call is None:
        return ""
    kind = call["kind"]
    if kind == "points":
        return f"{call['server']}-{call['receiver']}"
    if kind in ("deuce", "decidingPoint"):
        return "40-40"
    if kind == "advantage":
        return "AD-40" if call["side"] == server_side else "40-AD"
    return f"{call['server']}-{call['receiver']}"


# Every rules-derived field of a point record (rules §4.4 "recalculated: any flag or stat changed").
# The outcome fields are not here: a point id always names the same stored outcome.
DERIVED_POINT_KEYS = (
    "determined", "afterMatchEnd", "set", "game", "gameInSet", "tiebreak", "pointInGame", "server",
    "receiver", "serverSide", "courtSide", "ends", "before", "call", "pressure", "after",
)


def diff(previous: dict, current: dict) -> dict:
    """What a correction changed between two folds (§4.4 conflict types that need a baseline).
    ``recalculatedPointIds`` lists every surviving point whose derived state differs in any field."""

    def tiebreak_sets(result: dict) -> set:
        return {g["set"] for g in result["games"] if g["kind"] == "tiebreak"}

    prev_tb, cur_tb = tiebreak_sets(previous), tiebreak_sets(current)
    prev_points = {p["id"]: p for p in previous["points"]}
    recalculated = []
    for p in current["points"]:
        q = prev_points.get(p["id"])
        if q is None:
            continue
        if any(p[k] != q[k] for k in DERIVED_POINT_KEYS):
            recalculated.append(p["id"])
    was_complete = previous["match"]["status"] == "completed"
    return {
        "tiebreakAppeared": sorted(cur_tb - prev_tb),
        "tiebreakVanished": sorted(prev_tb - cur_tb),
        "matchIncomplete": was_complete and current["match"]["status"] == "inProgress",
        "recalculatedPointIds": recalculated,
    }


def fold_checkpoints(setup: dict, log: list[dict], after_seqs: list[int]) -> list[dict[str, Any]]:
    """Fold the log prefix ending at each ``afterSeq`` and attach ``changes`` against the previous one."""
    out = []
    previous = None
    for seq in after_seqs:
        prefix = [e for e in log if e["seq"] <= seq]
        result = fold(setup, prefix)
        result["changes"] = diff(previous, result) if previous is not None else None
        out.append(result)
        previous = result
    return out
