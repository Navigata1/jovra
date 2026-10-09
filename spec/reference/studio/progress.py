"""ProgressStoryBuilder.compare: is a change between two dated scopes of one stat honest to state?

Standard library only. `compare(stat_definition_id, earlier, later)` returns both fractions with the core integer
`pct`, the percentage-point delta taken from the two displayed integers (never from the exact difference), whether the
two scopes are comparable and every reason they are not. Not comparable means the film drops the comparison and
becomes a chronology; it never claims a change. A percentage "improvement" on a proportion is never produced.
Module page: spec/studio/modules/progress.md.
"""

from __future__ import annotations

from datetime import date

from studio.core import Reject, delta_pp_display, pct, require

SCOPE_FIELDS = ("date", "sessionIds", "sessionKind", "statDefinitionId", "methodId", "methodVersion",
                "capabilityVersion", "selectionRule", "numerator", "denominator", "provenance")
SELECTION_RULES = ("all", "seeded-random", "user-chosen")
PROVENANCE = ("manual", "estimated", "reviewed", "validated")
AT_LEAST_REVIEWED = ("reviewed", "validated")
CHOSEN_LABEL = "Examples you chose"

# The reasons a comparison is dropped, in the order they are reported.
REASONS = ("statDefinitionChange", "methodChange", "sessionKindChange", "differingSelection", "notReviewed",
           "emptySample")


def _integer(value, what: str) -> int:
    require(type(value) is int, "badScope", f"{what} must be an integer")
    return value


def _scope(scope, side: str) -> dict:
    require(isinstance(scope, dict), "badScope", f"{side} scope must be an object")
    missing = [k for k in SCOPE_FIELDS if k not in scope]
    extra = sorted(set(scope) - set(SCOPE_FIELDS))
    require(not missing and not extra, "badScope", f"{side} scope fields: missing {missing}, unknown {extra}")
    try:
        day = date.fromisoformat(scope["date"]) if type(scope["date"]) is str else None
    except ValueError:
        day = None
    require(day is not None, "badScope", f"{side} date {scope['date']!r} is not YYYY-MM-DD")
    require(isinstance(scope["sessionIds"], list) and scope["sessionIds"], "badScope", f"{side} needs a session")
    require(scope["selectionRule"] in SELECTION_RULES, "badScope", f"{side} selection rule {scope['selectionRule']!r}")
    require(scope["provenance"] in PROVENANCE, "badScope", f"{side} provenance {scope['provenance']!r}")
    n = _integer(scope["numerator"], f"{side} numerator")
    d = _integer(scope["denominator"], f"{side} denominator")
    require(0 <= n <= d, "badFraction", f"{side} fraction {n} / {d}")
    return dict(scope, day=day)


def _side(scope: dict) -> dict:
    n, d = scope["numerator"], scope["denominator"]
    shown = pct(n, d)
    return {"date": scope["date"], "sessionIds": list(scope["sessionIds"]), "numerator": n, "denominator": d,
            "pct": shown, "display": f"{n} / {d} · {'—' if shown is None else f'{shown}%'}",
            "selectionLabel": CHOSEN_LABEL if scope["selectionRule"] == "user-chosen" else None}


def compare(stat_definition_id: str, earlier: dict, later: dict) -> dict:
    """earlier/later scope -> {statDefinitionId, earlier, later, comparable, reasons, deltaPercentagePoints,
    deltaDisplay, summary, claim}. Raises Reject for malformed or out-of-order scopes."""
    e, l = _scope(earlier, "earlier"), _scope(later, "later")
    require(e["day"] < l["day"], "notChronological", f"earlier {e['date']} is not before later {l['date']}")
    found = set()
    if e["statDefinitionId"] != stat_definition_id or l["statDefinitionId"] != stat_definition_id:
        found.add("statDefinitionChange")
    if (e["methodId"], e["methodVersion"], e["capabilityVersion"]) != (l["methodId"], l["methodVersion"],
                                                                       l["capabilityVersion"]):
        found.add("methodChange")
    if e["sessionKind"] != l["sessionKind"]:
        found.add("sessionKindChange")
    if e["selectionRule"] != l["selectionRule"]:
        found.add("differingSelection")
    if e["provenance"] not in AT_LEAST_REVIEWED or l["provenance"] not in AT_LEAST_REVIEWED:
        found.add("notReviewed")
    if e["denominator"] == 0 or l["denominator"] == 0:
        found.add("emptySample")
    reasons = [r for r in REASONS if r in found]
    before, after = _side(e), _side(l)
    comparable = not reasons
    out = {"statDefinitionId": stat_definition_id, "earlier": before, "later": after, "comparable": comparable,
           "reasons": reasons, "deltaPercentagePoints": None, "deltaDisplay": None, "summary": None,
           "claim": "chronology"}
    if comparable:
        delta = after["pct"] - before["pct"]   # from the displayed integers, never the exact difference
        out.update(deltaPercentagePoints=delta, deltaDisplay=delta_pp_display(before["pct"], after["pct"]),
                   summary=f"{before['display']} → {after['display']}, {delta_pp_display(before['pct'], after['pct'])}",
                   claim="change" if delta else "no-change")
    return out


def run_vector(case: dict) -> dict:
    """A progress-comparison vector case -> the result, or {"rejectCode": code} when the reference refuses it."""
    inp = case["input"]
    try:
        return compare(inp["statDefinitionId"], inp["earlier"], inp["later"])
    except Reject as exc:
        return {"rejectCode": exc.code}
