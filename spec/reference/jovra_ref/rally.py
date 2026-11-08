"""Rally segmentation and the rally-only plan (T32; ios-v1-spec RallySegmenter, screens.md N7). Pure integer maths.

segment(hits, marks, params)
  * Hits are HitDetector candidates {id, tMs, kind, side?}. Only kind "hit" counts (bounces and other sounds are
    dropped as notHit); a hit whose side equals params.excludedSide is dropped as excludedSide (story 200). A hit
    with no side is kept.
  * Kept hits are ordered by (tMs, id). Consecutive hits less than rallyGapMs apart (default 3000) are one rally; a
    gap of more than pointGapMs (default 5000) starts a new point candidate. A gap from rallyGapMs to pointGapMs
    ends the rally but not the point, so a candidate can hold several rallies (a fault, then the second serve).
  * hits is None when the session has no audio: every point mark is then a candidate on its own (story 192). With
    audio, a point mark joins the first hit candidate whose clip holds it, and otherwise stands alone. Marks of
    other kinds are dropped as notPointMark. User marks are never masked by the excluded side.
  * A candidate's clip is [startMs - preRoll, endMs + postRoll) clamped to [0, durationMs] (defaults 1500 / 2500).
    Hit candidates are estimated and need review; mark candidates are manual. Candidates are ordered by
    (startMs, endMs, first id).

plan(targets, rolls, duration_ms)
  * Targets are points or marks {targetId, startMs, endMs}; rolls is the session's rallyPlayback or None (defaults).
    A clip entry overrides the session roll for its target, and excluded leaves the target out (story 195, N7).
  * Each kept target becomes [startMs - pre, endMs + post) clamped to the recording; ranges are ordered by
    (fromMs, toMs, targetId) and merged when they overlap or touch. Gaps are the skipped stretches, including the
    lead-in and the tail, each with its duration and its GapChip label (+m:ss, +h:mm:ss from one hour, whole
    seconds truncated). keptMs + skippedMs == durationMs.

Errors (RallyError.code) are checked in this order: parameters and rolls, then each hit, mark or target in input
order: a repeated id (duplicateId), a backwards range (rangeBackwards), a time outside [0, durationMs]
(timeOutsideRecording).

The session writers (set_session_rolls, set_clip_rolls, set_clip_excluded) return a new document; the Swift writer
in JovraCore must make the same edits byte for byte.
"""

from __future__ import annotations

import copy

DEFAULT_RALLY_GAP_MS = 3_000
DEFAULT_POINT_GAP_MS = 5_000
DEFAULT_PRE_ROLL_MS = 1_500
DEFAULT_POST_ROLL_MS = 2_500
MAX_ROLL_MS = 10_000
SESSION_ROLL_MAX_MS = 5_000
SESSION_ROLL_STEP_MS = 500
ROLLS_SINCE = (1, 1, 0)


class RallyError(ValueError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _value(params: dict, key: str, default):
    value = params.get(key)
    return default if value is None else value


def _check_roll(value: int) -> int:
    if not 0 <= value <= MAX_ROLL_MS:
        raise RallyError("rollOutOfRange")
    return value


def _clip(start: int, end: int, pre: int, post: int, duration: int) -> dict:
    return {"fromMs": max(0, start - pre), "toMs": min(duration, end + post)}


def _check_time(t: int, duration: int) -> None:
    if not 0 <= t <= duration:
        raise RallyError("timeOutsideRecording")


def segment(hits: list | None, marks: list, params: dict) -> dict:
    duration = params["durationMs"]
    rally_gap = _value(params, "rallyGapMs", DEFAULT_RALLY_GAP_MS)
    point_gap = _value(params, "pointGapMs", DEFAULT_POINT_GAP_MS)
    if rally_gap <= 0:
        raise RallyError("rallyGapNotPositive")
    if point_gap < rally_gap:
        raise RallyError("pointGapBelowRallyGap")
    pre = _check_roll(_value(params, "preRollMs", DEFAULT_PRE_ROLL_MS))
    post = _check_roll(_value(params, "postRollMs", DEFAULT_POST_ROLL_MS))
    excluded_side = params.get("excludedSide")

    seen: set[str] = set()
    for item in list(hits or []) + list(marks):
        if item["id"] in seen:
            raise RallyError("duplicateId")
        seen.add(item["id"])
        _check_time(item["tMs"], duration)

    def by_time(items):
        return sorted(items, key=lambda x: (x["tMs"], x["id"]))

    dropped = {"excludedSide": [], "notHit": [], "notPointMark": []}
    kept = []
    for h in by_time(hits or []):
        if h["kind"] != "hit":
            dropped["notHit"].append(h["id"])
        elif excluded_side is not None and h.get("side") == excluded_side:
            dropped["excludedSide"].append(h["id"])
        else:
            kept.append(h)

    candidates = []
    for h in kept:
        current = candidates[-1] if candidates else None
        gap = h["tMs"] - current["endMs"] if current else None
        if current is None or gap > point_gap:
            candidates.append({"source": "hits", "startMs": h["tMs"], "endMs": h["tMs"], "hitIds": [h["id"]],
                               "markIds": [], "rallies": [{"startMs": h["tMs"], "endMs": h["tMs"], "hitCount": 1}],
                               "provenance": "estimated", "needsReview": True})
            continue
        current["endMs"] = h["tMs"]
        current["hitIds"].append(h["id"])
        if gap < rally_gap:
            current["rallies"][-1]["endMs"] = h["tMs"]
            current["rallies"][-1]["hitCount"] += 1
        else:
            current["rallies"].append({"startMs": h["tMs"], "endMs": h["tMs"], "hitCount": 1})
    for c in candidates:
        c["clip"] = _clip(c["startMs"], c["endMs"], pre, post, duration)

    hit_candidates = list(candidates)
    for m in by_time(marks):
        if m["kind"] != "point":
            dropped["notPointMark"].append(m["id"])
            continue
        home = next((c for c in hit_candidates if c["clip"]["fromMs"] <= m["tMs"] < c["clip"]["toMs"]), None)
        if hits is not None and home is not None:
            home["markIds"].append(m["id"])
        else:
            candidates.append({"source": "mark", "startMs": m["tMs"], "endMs": m["tMs"],
                               "clip": _clip(m["tMs"], m["tMs"], pre, post, duration), "hitIds": [],
                               "markIds": [m["id"]], "rallies": [], "provenance": "manual", "needsReview": False})

    def first_id(c):
        return (c["hitIds"] or c["markIds"])[0]

    candidates.sort(key=lambda c: (c["startMs"], c["endMs"], first_id(c)))
    return {"candidates": candidates, "dropped": dropped}


def gap_label(duration_ms: int) -> str:
    seconds = duration_ms // 1000
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return f"+{hours}:{minutes:02d}:{secs:02d}"
    return f"+{minutes}:{secs:02d}"


def plan(targets: list, rolls: dict | None, duration_ms: int) -> dict:
    session_pre = _check_roll(rolls["preRollMs"]) if rolls else DEFAULT_PRE_ROLL_MS
    session_post = _check_roll(rolls["postRollMs"]) if rolls else DEFAULT_POST_ROLL_MS
    overrides = {}
    for clip in (rolls or {}).get("clips", []):
        for key in ("preRollMs", "postRollMs"):
            if key in clip:
                _check_roll(clip[key])
        overrides[clip["targetId"]] = clip

    seen: set[str] = set()
    for t in targets:
        if t["targetId"] in seen:
            raise RallyError("duplicateId")
        seen.add(t["targetId"])
        if t["endMs"] < t["startMs"]:
            raise RallyError("rangeBackwards")
        _check_time(t["startMs"], duration_ms)
        _check_time(t["endMs"], duration_ms)

    excluded, pieces = [], []
    for t in targets:
        override = overrides.get(t["targetId"], {})
        if override.get("excluded"):
            excluded.append(t["targetId"])
            continue
        pre = override.get("preRollMs", session_pre)
        post = override.get("postRollMs", session_post)
        pieces.append((_clip(t["startMs"], t["endMs"], pre, post, duration_ms), t["targetId"]))
    pieces.sort(key=lambda p: (p[0]["fromMs"], p[0]["toMs"], p[1]))

    merged: list[dict] = []
    for span, tid in pieces:
        if merged and span["fromMs"] <= merged[-1]["range"]["toMs"]:
            last = merged[-1]
            last["range"]["toMs"] = max(last["range"]["toMs"], span["toMs"])
            last["targetIds"].append(tid)
        else:
            merged.append({"range": dict(span), "targetIds": [tid]})
    for r in merged:
        r["durationMs"] = r["range"]["toMs"] - r["range"]["fromMs"]

    gaps, cursor = [], 0
    for r in merged + [{"range": {"fromMs": duration_ms, "toMs": duration_ms}}]:
        if r["range"]["fromMs"] > cursor:
            length = r["range"]["fromMs"] - cursor
            gaps.append({"range": {"fromMs": cursor, "toMs": r["range"]["fromMs"]}, "durationMs": length,
                         "label": gap_label(length)})
        cursor = max(cursor, r["range"]["toMs"])
    kept = sum(r["durationMs"] for r in merged)
    return {"ranges": [{"range": r["range"], "durationMs": r["durationMs"], "targetIds": r["targetIds"]}
                       for r in merged],
            "gaps": gaps, "excludedTargetIds": sorted(excluded), "keptMs": kept,
            "skippedMs": sum(g["durationMs"] for g in gaps), "durationMs": duration_ms}


def _outcome(run) -> dict:
    try:
        return {"result": run()}
    except RallyError as exc:
        return {"error": exc.code}


def run_segment_case(case: dict) -> dict:
    return _outcome(lambda: segment(case["hits"], case["marks"], case["params"]))


def run_plan_case(case: dict) -> dict:
    return _outcome(lambda: plan(case["targets"], case["rolls"], case["durationMs"]))


# ----- session writers ---------------------------------------------------------------------------------------

def _version_tuple(text: str) -> tuple:
    return tuple(int(p) for p in text.split("."))


def _with_rolls(doc: dict) -> tuple[dict, dict]:
    out = copy.deepcopy(doc)
    if _version_tuple(out["schemaVersion"]) < ROLLS_SINCE:
        out["schemaVersion"] = "1.1.0"  # rallyPlayback is a 1.1.0 field ($defs/v1_0)
    rolls = out.setdefault("rallyPlayback", {"preRollMs": DEFAULT_PRE_ROLL_MS, "postRollMs": DEFAULT_POST_ROLL_MS})
    return out, rolls


def set_session_rolls(doc: dict, pre_roll_ms: int, post_roll_ms: int) -> dict:
    """Playback settings: 0-5 s in 0.5 s steps (N7)."""
    for value in (pre_roll_ms, post_roll_ms):
        if not 0 <= value <= SESSION_ROLL_MAX_MS or value % SESSION_ROLL_STEP_MS:
            raise RallyError("rollOutOfRange")
    out, rolls = _with_rolls(doc)
    rolls["preRollMs"], rolls["postRollMs"] = pre_roll_ms, post_roll_ms
    return out


def _target_ids(doc: dict) -> set[str]:
    points = {e["id"] for e in doc.get("match", {}).get("log", []) if e["type"] == "point"}
    return points | {m["id"] for m in doc.get("marks", [])}


def _clip_entry(doc: dict, target_id: str) -> tuple[dict, dict]:
    if target_id not in _target_ids(doc):
        raise RallyError("unknownTarget")
    out, rolls = _with_rolls(doc)
    clips = rolls.setdefault("clips", [])
    entry = next((c for c in clips if c["targetId"] == target_id), None)
    if entry is None:
        entry = {"targetId": target_id}
        clips.append(entry)
    return out, entry


def set_clip_rolls(doc: dict, target_id: str, pre_roll_ms: int | None = None, post_roll_ms: int | None = None) -> dict:
    """A clip's own rolls (the clip range sheet's In/Out handles): 0-10 s; None leaves that side unchanged."""
    for value in (pre_roll_ms, post_roll_ms):
        if value is not None:
            _check_roll(value)
    out, entry = _clip_entry(doc, target_id)
    if pre_roll_ms is not None:
        entry["preRollMs"] = pre_roll_ms
    if post_roll_ms is not None:
        entry["postRollMs"] = post_roll_ms
    return out


def set_clip_excluded(doc: dict, target_id: str, excluded: bool) -> dict:
    """The Rallies list checkbox: deselecting leaves the clip out of rally-only playback, never out of the session."""
    out, entry = _clip_entry(doc, target_id)
    if excluded:
        entry["excluded"] = True
    else:
        entry.pop("excluded", None)
    return out
