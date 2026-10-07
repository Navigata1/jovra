"""A tiny builder for append-only logs, used by the fixture generator (not part of the contract)."""

from __future__ import annotations


class LogBuilder:
    def __init__(self, prefix: str = "e"):
        self.prefix = prefix
        self.events: list[dict] = []
        self.next_seq = 1
        self.point_count = 0

    def _add(self, event: dict, event_id: str | None = None) -> str:
        event_id = event_id or f"{self.prefix}{self.next_seq:03d}"
        full = {"id": event_id, "seq": self.next_seq}
        full.update(event)
        self.events.append(full)
        self.next_seq += 1
        return event_id

    @property
    def last_seq(self) -> int:
        return self.next_seq - 1

    def point(self, winner: str, end_type: str = "unknown", *, provenance: str = "manual",
              review_state: str | None = None, event_id: str | None = None, **extra) -> str:
        outcome = {"winner": winner, "endType": end_type}
        for key in ("serves", "strokeCount", "rallyLength", "errorDirection"):
            if key in extra:
                outcome[key] = extra.pop(key)
        outcome["provenance"] = provenance
        outcome["source"] = extra.pop("source", "user")
        event = {"type": "point"}
        for key in ("supersedes", "insertBefore", "recordedServer", "decidingPointSide", "tStartMs", "tEndMs"):
            if key in extra:
                event[key] = extra.pop(key)
        detected = extra.pop("detected", None)
        if detected is not None:
            event["detected"] = detected
        event["reviewed"] = outcome
        if review_state is not None:
            event["reviewState"] = review_state
        if extra:
            raise ValueError(f"unknown point fields {sorted(extra)}")
        return self._add(event, event_id)

    def points(self, winners: str, **kw) -> list[str]:
        return [self.point(w, **kw) for w in winners]

    def void(self, target: str) -> str:
        return self._add({"type": "void", "target": target})

    def checkpoint(self, set_index: int, a: int, b: int, **extra) -> str:
        event = {"type": "checkpoint", "setIndex": set_index, "games": {"A": a, "B": b}}
        event.update(extra)
        return self._add(event)

    def penalty(self, kind: str, player: str, reason: str = "codeViolation") -> str:
        return self._add({"type": "penalty", "kind": kind, "player": player, "reason": reason})

    def end(self, kind: str, player: str, reason: str | None = None) -> str:
        event = {"type": kind, "player": player}
        if reason:
            event["reason"] = reason
        return self._add(event)

    def rally_let(self) -> str:
        return self._add({"type": "rallyLet"})

    def doubles_order(self, set_index: int, first: str, second: str, deuce_a: str, deuce_b: str) -> str:
        return self._add(
            {
                "type": "doublesOrder",
                "setIndex": set_index,
                "firstServer": first,
                "secondServer": second,
                "deuceReceivers": {"A": deuce_a, "B": deuce_b},
            }
        )

