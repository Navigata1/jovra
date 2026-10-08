"""How a phone or watch may present an analysis result envelope.

Delivered only when the room's active capability exists; an absent capability, an unsupported registry entry, a
missing calibration or a null value is an explicit 'unavailable' with its reason (no invented value). A result tied to
an earlier point is shown as 'previous' with its own point and timestamp, never as the current serve. A review-needed
hint is a bookmark for phone review and never changes the score.
"""

from __future__ import annotations

ROOM_CAPABILITY_FOR_KIND = {"serveSpeed": "serveSpeedResults", "bounceHint": "automatedLineCalls"}
CALIBRATED_KINDS = frozenset({"serveSpeed", "bounceHint"})


def present(result: dict, room_capabilities: dict, registry: dict, current_point_event_id) -> dict:
    base = {"resultId": result["resultId"], "scoreEffect": "none", "label": result["label"],
            "pointEventId": result["pointEventId"], "producedAt": result["producedAt"]}
    if not room_capabilities.get(ROOM_CAPABILITY_FOR_KIND[result["kind"]], False):
        return {**base, "show": "unavailable", "reason": "capabilityAbsent", "value": None}
    status = registry.get(result["capabilityId"])
    if status in (None, "unsupported", "disabled"):
        return {**base, "show": "unavailable", "reason": "capabilityUnsupported", "value": None}
    if result["value"] is None:
        return {**base, "show": "unavailable", "reason": result["unavailableReason"], "value": None}
    if result["kind"] in CALIBRATED_KINDS and result["calibrationId"] is None:
        return {**base, "show": "unavailable", "reason": "calibrationMissing", "value": None}
    if result["reviewState"] == "reviewNeeded":
        return {**base, "show": "reviewNeeded", "reason": None, "value": None}
    when = "current" if result["pointEventId"] is not None and result["pointEventId"] == current_point_event_id else "previous"
    return {**base, "show": when, "reason": None, "value": result["value"], "units": result["units"],
            "uncertainty": result["uncertainty"]}
