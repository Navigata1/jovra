"""Event-log resolution: voids, supersede links and placement.

The match log is append-only (ADR-0003). Nothing is ever edited in place:

* ``void`` events remove a target event (undo). Voiding a void restores its target (redo).
  Resolution walks the log backwards so the latest decision wins.
* An event with ``supersedes`` replaces its target *in the target's position*; the target is kept
  for history (and for benchmarking the automatic suggestion). Voiding the superseding event
  restores the original.
* An event with ``insertBefore`` is placed immediately before the referenced event (adding a
  missed point). Every other placeable event is appended in ``seq`` order.
* Voiding an event also voids every later correction of it: an event whose ``supersedes`` target is
  voided (directly or through its own target) is inert. Voiding the first version of a corrected
  point therefore removes the point, while voiding the latest correction restores the version before
  it. A voided event keeps its position as a tombstone, so an ``insertBefore`` aimed at it still has
  an anchor. The fold never sees tombstones.
* ``doublesOrder`` events are not placed; the last active one per ``setIndex`` applies.
"""

PLACEABLE = ("point", "checkpoint", "penalty", "retirement", "default", "walkover", "rallyLet")
UNPLACED = ("void", "doublesOrder")


class LogError(Exception):
    """A structurally invalid log. Platforms must reject the same logs with the same ``code``."""

    def __init__(self, code, detail):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


def resolve(events):
    """Return ``(placed_events, doubles_orders_by_set, history)``.

    ``history`` reports what the resolution did so platforms can show it: voided ids and the
    supersede chain (old id -> replacing id), both sorted for determinism.
    """
    seen = {}
    last_seq = -1
    for e in events:
        if e["id"] in seen:
            raise LogError("duplicateId", e["id"])
        if e["seq"] <= last_seq:
            raise LogError("seqNotIncreasing", e["id"])
        if e["type"] not in PLACEABLE + UNPLACED:
            raise LogError("unknownEventType", e["type"])
        last_seq = e["seq"]
        seen[e["id"]] = e

    for e in events:
        if e["type"] == "void":
            target = seen.get(e["target"])
            if target is None:
                raise LogError("voidTargetMissing", e["id"])
            if target["seq"] >= e["seq"]:
                raise LogError("voidTargetNotEarlier", e["id"])

    voided = set()
    for e in reversed(events):
        if e["id"] in voided:
            continue
        if e["type"] == "void":
            voided.add(e["target"])

    order = []
    replaced = {}
    by_id = {}
    doubles = {}
    inert = set(voided)  # voided events plus corrections of voided events (transitively)
    tombstones = set()

    def current(event_id):
        while event_id in replaced:
            event_id = replaced[event_id]
        return event_id

    def slot(event_id):
        """The placed id (or tombstone) holding ``event_id``'s position; an undone correction
        resolves to the version it tried to replace."""
        event_id = current(event_id)
        while event_id not in order and event_id in seen and "supersedes" in seen[event_id]:
            event_id = current(seen[event_id]["supersedes"])
        return event_id

    for e in events:
        if e["type"] == "void":
            continue
        if e["type"] == "doublesOrder":
            if e["id"] not in voided:
                doubles[e["setIndex"]] = e
            continue
        if "supersedes" in e:
            if e["id"] in voided:
                continue  # voided correction: the version it replaced stays in place
            target_id = current(e["supersedes"])
            if target_id in inert:
                inert.add(e["id"])  # a correction of something undone is undone too
                continue
            if target_id not in order:
                raise LogError("supersedeTargetMissing", e["id"])
            if by_id[target_id]["type"] != e["type"]:
                raise LogError("supersedeTypeMismatch", e["id"])
            order[order.index(target_id)] = e["id"]
            replaced[target_id] = e["id"]
        elif "insertBefore" in e:
            target_id = slot(e["insertBefore"])
            if target_id not in order:
                if e["id"] in voided:
                    continue  # a voided insert needs no anchor
                raise LogError("insertTargetMissing", e["id"])
            order.insert(order.index(target_id), e["id"])
        else:
            order.append(e["id"])
        by_id[e["id"]] = e
        if e["id"] in inert:
            tombstones.add(e["id"])

    history = {
        "voided": sorted(voided),
        "superseded": [{"id": old, "by": new} for old, new in sorted(replaced.items())],
    }
    return [by_id[i] for i in order if i not in tombstones], doubles, history
