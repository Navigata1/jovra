"""Reference integrity for 1.1 records: every id a field holds names a record that exists, every time range runs
forwards, 1.1 times fall inside the recording, consent fields agree, and a stored serve speed (value and range) is
computed from its own mark in mph or km/h (CLAUDE.md hard rule 1).

The schema cannot express these rules, so both platforms' decoders (T03) and scripts/spec/validate.py apply them.
Each function returns a list of problems; an empty list means the document is consistent.
"""

from __future__ import annotations

import math
from datetime import datetime
from fractions import Fraction

from .log import LogError, resolve
from .units import UNITS, round_half_up

BASELINE_Y = 11.885  # metres from the net to a baseline (ITF); court origin is the centre of the net (common.point2)
METRES_PER_SECOND_PER_MPH = UNITS["mph"][1]  # 0.44704, exact
SERVE_SPEED_KEY = "serveSpeed.estimate"
SERVE_SPEED_UNITS = ("mph", "km/h")  # S20 unit preference; UnitConverter factors (units.UNITS), never relabelled
# screens.md S12: "Range = ±10% (technical-feasibility §10 error budget) widened when fps < 60" ("Lower frame rate:
# ±15%"). The range is taken around the displayed whole-unit value: 104 mph -> (94–114).
RANGE_PCT, LOW_FPS_RANGE_PCT, LOW_FPS = 10, 15, 60


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


def _ms(media_time: dict) -> Fraction:
    return _seconds(media_time) * 1000


def serve_speed(mark: dict, unit: str = "mph") -> int | None:
    """Average ground speed contact→bounce, in whole `unit` (half-up): the distance on the court plane from the
    server's position to the bounce over the time between the two marked frames (technical-feasibility §10, screens.md
    S12), converted from m/s by the exact factor of `unit` (mph or km/h). None when the mark is incomplete or its
    frames do not run forwards."""
    needed = ("contactFrame", "bounceFrame", "bounceCourt", "serverPosition")
    if any(key not in mark for key in needed):
        return None
    seconds = _seconds(mark["bounceFrame"]) - _seconds(mark["contactFrame"])
    if seconds <= 0:
        return None
    a, b = mark["serverPosition"], mark["bounceCourt"]
    metres = math.hypot(b["x"] - a["x"], b["y"] - a["y"])
    speed = metres / float(seconds) / float(UNITS[unit][1])
    return math.floor(speed + 0.5)


def serve_speed_mph(mark: dict) -> int | None:
    return serve_speed(mark, "mph")


def estimate_range(value: int, pct: int) -> dict:
    """The displayed range of a ±pct% estimate: each bound half-up to a whole unit (104 at 10% -> 94–114)."""
    low = round_half_up(Fraction(value * (100 - pct), 100), Fraction(1))
    high = round_half_up(Fraction(value * (100 + pct), 100), Fraction(1))
    return {"low": int(low), "high": int(high), "pct": pct}


def frame_rate_at(session: dict, ms) -> Fraction | None:
    """Frames per second at a session time: the covering segment's rate, replaced by the latest frameRateChange
    capture event inside that segment at or before the time. None when no segment covers it."""
    recording = session.get("recording", {})
    segment = next((s for s in recording.get("segments", [])
                    if s["startMs"] <= ms <= s["startMs"] + s["durationMs"]), None)
    if segment is None:
        return None
    rate = Fraction(segment["frameRate"]["num"], segment["frameRate"]["den"])
    changes = sorted((e for e in recording.get("captureEvents", []) if e["kind"] == "frameRateChange"
                      and "frameRate" in e and segment["startMs"] <= e["tMs"] <= ms), key=lambda e: e["tMs"])
    if changes:
        rate = Fraction(changes[-1]["frameRate"]["num"], changes[-1]["frameRate"]["den"])
    return rate


def serve_range_pct(session: dict, mark: dict) -> int | None:
    """±10%, widened to ±15% when the frame rate at contact is below 60 fps (screens.md S12)."""
    if "contactFrame" not in mark:
        return None
    rate = frame_rate_at(session, _ms(mark["contactFrame"]))
    if rate is None:
        return None
    return RANGE_PCT if rate >= LOW_FPS else LOW_FPS_RANGE_PCT


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
        if value["key"] == SERVE_SPEED_KEY:
            problems += _serve_speed_problems(f"$.derivedValues[{i}]", value, marks, doc)
    return problems


def _serve_speed_problems(where: str, value: dict, marks: dict, doc: dict) -> list[str]:
    """A stored serve speed names its mark and that mark's calibration, and its value and range are recomputed."""
    unit, mark_id = value.get("unit"), value.get("scope", {}).get("serveMarkId")
    calibration_id = value["provenance"].get("calibrationId")
    if unit not in SERVE_SPEED_UNITS:
        return [f"{where}: serve speed unit {unit!r} is not one of {', '.join(SERVE_SPEED_UNITS)}"]
    if mark_id is None:
        return [f"{where}: serve speed {value['value']} {unit} names no serve mark, so it cannot be computed"]
    if calibration_id is None:
        return [f"{where}: serve speed names no calibration"]
    mark = marks.get(mark_id)
    if mark is None:
        return []  # reported as a dangling scope.serveMarkId
    problems = []
    if calibration_id != mark.get("calibrationId"):
        problems.append(f"{where}: provenance.calibrationId {calibration_id!r} is not the calibration of serve mark "
                        f"{mark_id} ({mark.get('calibrationId')!r})")
    computed = serve_speed(mark, unit)
    if computed is None:
        return problems + [f"{where}: serve mark {mark_id} is incomplete, so no speed can be computed from it"]
    if computed != value["value"]:
        problems.append(f"{where}: serve speed {value['value']} {unit} is not computed from serve mark {mark_id} "
                        f"({computed} {unit})")
    pct = serve_range_pct(doc, mark)
    if pct is None:
        return problems + [f"{where}: no recording segment covers serve mark {mark_id}'s contact, so its range has "
                           "no frame rate"]
    expected = estimate_range(computed, pct)
    if value.get("range") != expected:
        problems.append(f"{where}: range {value.get('range')} is not ±{pct}% of {computed} {unit} ({expected})")
    return problems


def _parent_problems(log: list) -> list[str]:
    """A point's parentIds name earlier point events, other than itself, that the log voids (split or merge)."""
    try:
        voided = set(resolve(log)[2]["voided"])
    except LogError as exc:
        return [f"$.match.log: {exc}"]
    events = {e["id"]: e for e in log}
    problems = []
    for i, event in enumerate(log):
        for j, parent_id in enumerate(event.get("parentIds", [])):
            where = f"$.match.log[{i}].parentIds[{j}] {parent_id!r}"
            parent = events.get(parent_id)
            if parent_id == event["id"]:
                problems.append(f"{where} names the point itself")
            elif parent is None or parent["type"] != "point":
                problems.append(f"{where} names no point event")
            elif parent["seq"] >= event["seq"]:
                problems.append(f"{where} is not earlier than the point (seq {parent['seq']} >= {event['seq']})")
            elif parent_id not in voided:
                problems.append(f"{where} is not voided: a split or merged point's parents are voided")
    return problems


def _instant(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def _consent_problems(consent: dict) -> list[str]:
    problems = []
    if consent.get("juniorPlayerIds") and consent["status"] == "notRequired":
        problems.append("$.consent.status is notRequired but juniorPlayerIds is not empty (junior consent is "
                        "required)")
    # Schema `format` is intentionally an annotation. Check these instants before comparing them:
    # an impossible calendar date must produce a refusal, never crash an import/validation pass.
    withdrawn = None
    if "withdrawnAt" in consent:
        try:
            withdrawn = _instant(consent["withdrawnAt"])
        except ValueError:
            problems.append("$.consent.withdrawnAt is not a valid calendar timestamp")
    for i, written in enumerate(consent.get("writtenConsents", [])):
        try:
            attached = _instant(written["attachedAt"])
        except ValueError:
            problems.append(f"$.consent.writtenConsents[{i}].attachedAt is not a valid calendar timestamp")
            continue
        if withdrawn is not None and withdrawn < attached:
            problems.append(f"$.consent.withdrawnAt {consent['withdrawnAt']} is before writtenConsents[{i}]"
                            f".attachedAt {written['attachedAt']}")
    return problems


def _bounds_problems(doc: dict, log: list) -> list[str]:
    """1.1 times fall inside the recording (when its duration is known) and key moments inside their swing clip."""
    problems = []
    for i, swing in enumerate(doc.get("swings", [])):
        clip = swing.get("clip")
        for j, moment in enumerate(swing["keyMoments"]):
            t = _ms(moment["time"])
            if clip is not None and not clip["fromMs"] <= t <= clip["toMs"]:
                problems.append(f"$.swings[{i}].keyMoments[{j}] at {float(t):.0f} ms is outside the swing clip "
                                f"{clip['fromMs']}-{clip['toMs']} ms")
    duration = doc.get("recording", {}).get("durationMs")
    if duration is None:
        return problems
    times = []
    for i, swing in enumerate(doc.get("swings", [])):
        if "clip" in swing:
            times.append((f"$.swings[{i}].clip.toMs", swing["clip"]["toMs"]))
        times += [(f"$.swings[{i}].keyMoments[{j}].time", _ms(m["time"])) for j, m in enumerate(swing["keyMoments"])]
    for i, mark in enumerate(doc.get("serveMarks", [])):
        times += [(f"$.serveMarks[{i}].{key}", _ms(mark[key])) for key in ("contactFrame", "bounceFrame") if key in mark]
    times += [(f"$.calibrations[{i}].staleFromMs", c["staleFromMs"])
              for i, c in enumerate(doc.get("calibrations", [])) if "staleFromMs" in c]
    times += [(f"$.recording.captureEvents[{i}].tMs", e["tMs"])
              for i, e in enumerate(doc.get("recording", {}).get("captureEvents", []))]
    times += [(f"$.exports[{i}].range.toMs", e["range"]["toMs"])
              for i, e in enumerate(doc.get("exports", [])) if "range" in e]
    targets = {e["id"]: [e.get("tStartMs"), e.get("tEndMs")] for e in log if e["type"] == "point"}
    targets.update({m["id"]: [m.get("tMs"), m.get("tEndMs")] for m in doc.get("marks", [])})
    for i, clip in enumerate(doc.get("rallyPlayback", {}).get("clips", [])):
        times += [(f"$.rallyPlayback.clips[{i}] target {clip['targetId']!r}", t)
                  for t in targets.get(clip["targetId"], []) if t is not None]
    for where, t in times:
        if t > duration:
            problems.append(f"{where} at {float(t):.0f} ms is past the end of the recording ({duration} ms)")
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
    problems += _parent_problems(log) + _consent_problems(consent) + _bounds_problems(doc, log)
    for i, swing in enumerate(doc.get("swings", [])):
        for key, known, what in (("shotId", shots, "shot"), ("serveMarkId", serve_marks, "serve mark"),
                                 ("markId", marks, "mark")):
            if key in swing:
                problems += _missing(f"$.swings[{i}].{key}", swing[key], known, what)
    targets = set()
    for i, clip in enumerate(doc.get("rallyPlayback", {}).get("clips", [])):
        problems += _missing(f"$.rallyPlayback.clips[{i}].targetId", clip["targetId"], points | marks,
                             "point or mark")
        if clip["targetId"] in targets:
            problems.append(f"$.rallyPlayback.clips[{i}].targetId {clip['targetId']!r} already has a clip override")
        targets.add(clip["targetId"])
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
