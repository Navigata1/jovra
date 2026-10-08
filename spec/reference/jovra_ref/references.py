"""Reference integrity for 1.1 records: every id a field holds names a record that exists, every time range runs
forwards, and the contract example's serve speed is computed from its own mark (CLAUDE.md hard rule 1).

The schema cannot express these rules, so both platforms' decoders (T03) and scripts/spec/validate.py apply them.
Each function returns a list of problems; an empty list means the document is consistent.
"""

from __future__ import annotations

import math
from fractions import Fraction

from .units import UNITS

BASELINE_Y = 11.885  # metres from the net to a baseline (ITF); court origin is the centre of the net (common.point2)
METRES_PER_SECOND_PER_MPH = UNITS["mph"][1]  # 0.44704, exact


# ----- helpers --------------------------------------------------------------------------------------------------

def _ids(items) -> set:
    return {item["id"] for item in items or []}


def _missing(where: str, value, known: set, what: str) -> list[str]:
    return [] if value in known else [f"{where} {value!r} names no {what}"]


def _all_missing(where: str, values, known: set, what: str) -> list[str]:
    return [p for i, v in enumerate(values or []) for p in _missing(f"{where}[{i}]", v, known, what)]


def _objects(node, path="$"):
    if isinstance(node, dict):
        yield path, node
        for key, value in node.items():
            yield from _objects(value, f"{path}.{key}")
    elif isinstance(node, list):
        for i, value in enumerate(node):
            yield from _objects(value, f"{path}[{i}]")


def time_range_problems(doc) -> list[str]:
    """Every {fromMs, toMs} range in a document runs forwards (common.timeRange is half-open: empty is allowed)."""
    return [f"{path} runs backwards ({node['fromMs']} > {node['toMs']})"
            for path, node in _objects(doc)
            if isinstance(node.get("fromMs"), int) and isinstance(node.get("toMs"), int)
            and node["fromMs"] > node["toMs"]]


def event_log_version(session: dict) -> int:
    """common.eventLogVersion: the highest seq in the session's match log, 0 when the session has no log."""
    return max((e["seq"] for e in session.get("match", {}).get("log", [])), default=0)


def _seconds(media_time: dict) -> Fraction:
    return Fraction(media_time["value"], media_time["timescale"])


def serve_speed_mph(mark: dict) -> int | None:
    """Average ground speed contact→bounce, in whole mph (half-up): the distance on the court plane from the server's
    position to the bounce over the time between the two marked frames (technical-feasibility §10, screens.md S12).
    None when the mark is incomplete or its frames do not run forwards."""
    needed = ("contactFrame", "bounceFrame", "bounceCourt", "serverPosition")
    if any(key not in mark for key in needed):
        return None
    seconds = _seconds(mark["bounceFrame"]) - _seconds(mark["contactFrame"])
    if seconds <= 0:
        return None
    a, b = mark["serverPosition"], mark["bounceCourt"]
    metres = math.hypot(b["x"] - a["x"], b["y"] - a["y"])
    mph = metres / float(seconds) / float(METRES_PER_SECOND_PER_MPH)
    return math.floor(mph + 0.5)


# ----- session ----------------------------------------------------------------------------------------------------

def _sample_media_problems(doc: dict, manifest: dict | None) -> list[str]:
    media_ids = doc.get("sample", {}).get("mediaIds", [])
    if not media_ids:
        return []
    if manifest is None:
        return ["$.sample.mediaIds: no sample media manifest to resolve them against"]
    media = {m["mediaId"]: m for m in manifest["media"]}
    problems = _all_missing("$.sample.mediaIds", media_ids, set(media), "entry in the sample media manifest")
    if doc["id"] in {m["sessionId"] for m in media.values()}:
        for i, media_id in enumerate(media_ids):
            if media_id in media and media[media_id]["sessionId"] != doc["id"]:
                problems.append(f"$.sample.mediaIds[{i}] {media_id!r} belongs to another sample session")
    return problems


def _serve_problems(doc: dict, points: set, shots: set, calibrations: set) -> list[str]:
    problems = []
    for i, mark in enumerate(doc.get("serveMarks", [])):
        where = f"$.serveMarks[{i}]"
        for key, known, what in (("pointId", points, "point"), ("shotId", shots, "shot"),
                                 ("calibrationId", calibrations, "calibration")):
            if key in mark:
                problems += _missing(f"{where}.{key}", mark[key], known, what)
        position = mark.get("serverPosition")
        if mark.get("contactDefaulted") and position is not None \
                and (position["x"] != 0 or abs(position["y"]) != BASELINE_Y):
            problems.append(f"{where}: contactDefaulted but serverPosition {position} is not the centre mark of a "
                            f"baseline (x 0, y ±{BASELINE_Y})")
    marks = {m["id"]: m for m in doc.get("serveMarks", [])}
    for i, value in enumerate(doc.get("derivedValues", [])):
        mark = marks.get(value.get("scope", {}).get("serveMarkId"))
        if value["key"] != "serveSpeed.estimate" or mark is None or value.get("unit") != "mph":
            continue
        computed = serve_speed_mph(mark)
        if computed != value["value"]:
            problems.append(f"$.derivedValues[{i}]: serve speed {value['value']} mph is not computed from serve mark "
                            f"{mark['id']} ({computed} mph)")
    return problems


def session_problems(doc: dict, manifest: dict | None = None) -> list[str]:
    """Dangling references, backwards ranges and uncomputed speeds in one session document."""
    players = _ids(doc.get("players"))
    log = doc.get("match", {}).get("log", [])
    points = {e["id"] for e in log if e["type"] == "point"}
    shots, marks, calibrations = _ids(doc.get("shots")), _ids(doc.get("marks")), _ids(doc.get("calibrations"))
    serve_marks = _ids(doc.get("serveMarks"))
    segments = _ids(doc.get("recording", {}).get("segments"))
    version = event_log_version(doc)
    problems = time_range_problems(doc) + _sample_media_problems(doc, manifest)

    consent = doc.get("consent", {})
    problems += _all_missing("$.consent.juniorPlayerIds", consent.get("juniorPlayerIds"), players, "player")
    for i, written in enumerate(consent.get("writtenConsents", [])):
        problems += _all_missing(f"$.consent.writtenConsents[{i}].coversPlayerIds", written.get("coversPlayerIds"),
                                 players, "player")
    for i, shot in enumerate(doc.get("shots", [])):
        problems += _missing(f"$.shots[{i}].hitter", shot["hitter"], players, "player")
        if "pointId" in shot:
            problems += _missing(f"$.shots[{i}].pointId", shot["pointId"], points, "point")
        if "calibrationId" in shot.get("placement", {}):
            problems += _missing(f"$.shots[{i}].placement.calibrationId", shot["placement"]["calibrationId"],
                                 calibrations, "calibration")
    problems += _serve_problems(doc, points, shots, calibrations)
    for i, swing in enumerate(doc.get("swings", [])):
        for key, known, what in (("shotId", shots, "shot"), ("serveMarkId", serve_marks, "serve mark"),
                                 ("markId", marks, "mark")):
            if key in swing:
                problems += _missing(f"$.swings[{i}].{key}", swing[key], known, what)
    for i, clip in enumerate(doc.get("rallyPlayback", {}).get("clips", [])):
        problems += _missing(f"$.rallyPlayback.clips[{i}].targetId", clip["targetId"], points | marks,
                             "point or mark")
    for i, export in enumerate(doc.get("exports", [])):
        if export["eventLogVersion"] > version:
            problems.append(f"$.exports[{i}].eventLogVersion {export['eventLogVersion']} is later than the log "
                            f"(highest seq {version})")
        problems += _all_missing(f"$.exports[{i}].pointIds", export.get("pointIds"), points, "point")
    for i, value in enumerate(doc.get("derivedValues", [])):
        scope = value.get("scope", {})
        for key, known, what in (("pointId", points, "point"), ("shotId", shots, "shot"),
                                 ("serveMarkId", serve_marks, "serve mark")):
            if key in scope:
                problems += _missing(f"$.derivedValues[{i}].scope.{key}", scope[key], known, what)
        if "calibrationId" in value["provenance"]:
            problems += _missing(f"$.derivedValues[{i}].provenance.calibrationId",
                                 value["provenance"]["calibrationId"], calibrations, "calibration")
    recovery = doc.get("recording", {}).get("recovery", {})
    problems += _all_missing("$.recording.recovery.truncatedSegmentIds", recovery.get("truncatedSegmentIds"),
                             segments, "segment")
    return problems


# ----- other records -------------------------------------------------------------------------------------------

def practice_plan_problems(plan: dict) -> list[str]:
    items, goals = _ids(plan.get("items")), _ids(plan.get("goals"))
    problems = []
    for i, log in enumerate(plan.get("drillLogs", [])):
        problems += _missing(f"$.drillLogs[{i}].itemId", log["itemId"], items, "item of this plan")
        problems += _all_missing(f"$.drillLogs[{i}].goalIds", log.get("goalIds"), goals, "goal of this plan")
    return problems + time_range_problems(plan)


def export_problems(export: dict, sessions: dict) -> list[str]:
    """An export manifest's sessions and files agree, and no session claims a log version its document never had.
    `sessions` maps id -> session document for the sessions available to check against."""
    listed = {s["id"] for s in export.get("sessions", [])}
    problems = []
    for i, entry in enumerate(export.get("sessions", [])):
        session = sessions.get(entry["id"])
        if session is not None and entry.get("eventLogVersion", 0) > event_log_version(session):
            problems.append(f"$.sessions[{i}].eventLogVersion {entry['eventLogVersion']} is later than the log of "
                            f"{entry['id']} (highest seq {event_log_version(session)})")
    for i, entry in enumerate(export.get("files", [])):
        if "sessionId" in entry:
            problems += _missing(f"$.files[{i}].sessionId", entry["sessionId"], listed, "session of this export")
    return problems + time_range_problems(export)


def archive_problems(archive: dict, sessions: dict) -> list[str]:
    session = sessions.get(archive["sessionId"])
    problems = []
    for i, entry in enumerate(archive.get("files", [])):
        if session is not None and entry.get("eventLogVersion", 0) > event_log_version(session):
            problems.append(f"$.files[{i}].eventLogVersion {entry['eventLogVersion']} is later than the log of "
                            f"{archive['sessionId']} (highest seq {event_log_version(session)})")
    return problems + time_range_problems(archive)
