"""KeeperSelector: keeper candidates from the core fold, Marks and lesson clips, and the per-profile ranking.

Standard library only; integer microseconds on the session (match) clock, exact frame conversion through the sync
transform. Module page: spec/studio/modules/keepers.md.

candidates(project) -> {"keepers": [...], "unplaced": [...]}
    One keeper per effective point (the core fold's point slots, voided and superseded events already resolved), per
    Mark that falls outside every point, and per lesson clip with its own window. A point listed by several angles is
    one keeper (deduplicated by session event id): the second angle is a view, never a second point (story 107).
    Windows are the point plus the default pre-roll 1.5 s and post-roll 2.5 s (story 104), widened to cover every
    contact's protected window, and clamped to the session. A view is offered only by a source whose sync piece is a
    reference or reviewed one and whose recording covers the whole window. Contacts come from reviewed or manual shots;
    an estimated hit is labelled "Estimated", and one inside a reviewed contact's window is absorbed, so it never
    narrows or moves what the reviewed contact protects.

rank(profileId, keepers, options) -> {"profileId", "order": [{kind, id, chapter}], "label", "fallback", "missing"}
    Deterministic per profile (see the module page for the rules).
"""

from __future__ import annotations

from fractions import Fraction

from studio.core import US_PER_S, Reject, frame_at_us, require

PRE_ROLL_US = 1_500_000
POST_ROLL_US = 2_500_000
CONTACT_PAD_US = 250_000          # each side of a contact (15 frames at 60 fps, as the Sample plans protect)
USABLE_SYNC_STATES = ("reference", "reviewed")
REAL_PROVENANCE = ("manual", "reviewed", "validated")      # a rally length or contact a person entered or checked
PROVENANCE_RANK = {"estimated": 0, "manual": 1, "reviewed": 2, "validated": 3}
ESTIMATED_LABEL = "Estimated"
CHOSEN_LABEL = "Examples you chose"
ORIGIN_ORDER = {"point": 0, "mark": 1, "lesson-clip": 2}
PROFILES = ("rally-pulse", "coach-cut", "match-broadcast", "progress-story", "court-memories")


# ----- core fold -> point inputs ----------------------------------------------------------------------------------

def points_from_fold(result: dict, session_start_us: int = 0) -> list:
    """The effective points of a core fold (jovra_ref.scoring.fold) as candidate inputs. Penalty points (no play) and
    points after the match ended are not keepers; a point with no recorded time cannot be placed and stays timeless."""
    out = []
    for p in result["points"]:
        if p["kind"] != "point" or p["afterMatchEnd"]:
            continue
        pressure = p["pressure"] or {}
        timed = "tStartMs" in p and "tEndMs" in p
        out.append({
            "eventId": p["id"], "index": p["index"],
            "startUs": session_start_us + p["tStartMs"] * 1000 if timed else None,
            "endUs": session_start_us + p["tEndMs"] * 1000 if timed else None,
            "rallyLength": p["rallyLength"], "provenance": p["provenance"],
            "breakPoint": bool(pressure.get("breakPoint")), "setPoint": bool(pressure.get("setPointFor")),
            "matchPoint": bool(pressure.get("matchPointFor")), "sourceId": None})
    return out


# ----- candidates -------------------------------------------------------------------------------------------------

def _int(value, what: str) -> int:
    require(type(value) is int, "badInput", f"{what} must be an integer")
    return value


def _source_frame(src: dict, session_us: int):
    """(exact source time in us, frame) for a session time through the source's sync transform."""
    t = src["transform"]
    rate = Fraction(t["rate"]["num"], t["rate"]["den"])
    src_us = (Fraction(session_us) - t["offsetUs"]) / rate
    return src_us, frame_at_us(src_us, src["fps"])


def _view(src: dict, start_us: int, end_us: int):
    """A view of [start, end) on one source, or None when its recording does not cover the whole window."""
    a_us, a = _source_frame(src, start_us)
    b_us, b = _source_frame(src, end_us)
    length_us = Fraction(src["frameCount"] * US_PER_S * src["fps"]["den"], src["fps"]["num"])
    if a_us < 0 or b_us > length_us or a >= b:
        return None
    return {"sourceId": src["sourceId"], "window": {"inFrame": a, "outFrame": b}}


def _contacts(shots: list) -> list:
    """Reviewed and manual contacts protect [t - pad, t + pad); an estimated hit inside one of those windows is
    absorbed; any other estimated hit is kept, labelled, with the same pad (never a narrower window)."""
    real = sorted((s for s in shots if s["provenance"] in REAL_PROVENANCE), key=lambda s: s["atUs"])
    out = [{"atUs": s["atUs"], "provenance": s["provenance"], "label": None,
            "protect": {"startUs": s["atUs"] - CONTACT_PAD_US, "endUs": s["atUs"] + CONTACT_PAD_US}} for s in real]
    for s in sorted((s for s in shots if s["provenance"] == "estimated"), key=lambda s: s["atUs"]):
        if any(c["protect"]["startUs"] <= s["atUs"] < c["protect"]["endUs"] for c in out if c["label"] is None):
            continue
        out.append({"atUs": s["atUs"], "provenance": "estimated", "label": ESTIMATED_LABEL,
                    "protect": {"startUs": s["atUs"] - CONTACT_PAD_US, "endUs": s["atUs"] + CONTACT_PAD_US}})
    return sorted(out, key=lambda c: (c["atUs"], c["label"] is not None))


def _merge_points(points: list) -> tuple[list, list]:
    """Deduplicate by session event id: one entry per event, its window the union of every angle's window, its facts
    from the strongest provenance (the first listed on a tie)."""
    merged: dict = {}
    order = []
    unplaced = []
    for p in points:
        require(isinstance(p.get("eventId"), str) and p["eventId"], "badInput", "a point needs an event id")
        if p["startUs"] is None or p["endUs"] is None:
            unplaced.append({"id": p["eventId"], "origin": "point", "reason": "noTime"})
            continue
        require(_int(p["startUs"], "startUs") < _int(p["endUs"], "endUs"), "badInterval",
                f"point {p['eventId']} ends before it starts")
        m = merged.get(p["eventId"])
        if m is None:
            merged[p["eventId"]] = dict(p, seenFrom=[p["sourceId"]] if p.get("sourceId") else [])
            order.append(p["eventId"])
            continue
        if PROVENANCE_RANK[p["provenance"]] > PROVENANCE_RANK[m["provenance"]]:
            keep = dict(p, startUs=m["startUs"], endUs=m["endUs"], seenFrom=m["seenFrom"])
            merged[p["eventId"]] = m = keep
        m["startUs"], m["endUs"] = min(m["startUs"], p["startUs"]), max(m["endUs"], p["endUs"])
        if p.get("sourceId") and p["sourceId"] not in m["seenFrom"]:
            m["seenFrom"].append(p["sourceId"])
    return [merged[e] for e in order], unplaced


def _window(start_us: int, end_us: int, contacts: list, duration_us: int) -> dict:
    lo = min([start_us] + [c["protect"]["startUs"] for c in contacts])
    hi = max([end_us] + [c["protect"]["endUs"] for c in contacts])
    return {"startUs": max(0, lo - PRE_ROLL_US), "endUs": min(duration_us, hi + POST_ROLL_US)}


def _views(sources: list, session: dict) -> list:
    views = []
    for src in sources:
        if src["syncState"] not in USABLE_SYNC_STATES:
            continue
        v = _view(src, session["startUs"], session["endUs"])
        if v is not None:
            views.append(dict(v, primary=False))
    if views:
        primary = next((v for v in views if any(s["sourceId"] == v["sourceId"] and s["isPrimary"] for s in sources)),
                       views[0])
        primary["primary"] = True
    return views


def _keeper(kid, origin, event_refs, session, sources, contacts, facts) -> dict:
    views = _views(sources, session)
    for c in contacts:
        c["frames"] = {v["sourceId"]: _source_frame(next(s for s in sources if s["sourceId"] == v["sourceId"]),
                                                    c["atUs"])[1] for v in views}
    return {"keeperId": kid, "origin": origin, "eventRefs": list(event_refs), "markIds": [], "lessonClipIds": [],
            "session": session, "views": views, "contacts": contacts, "facts": facts}


def _facts(point=None) -> dict:
    if point is None:
        return {"index": None, "rallyLength": None, "rallyReal": False, "breakPoint": False, "setPoint": False,
                "matchPoint": False, "provenance": "manual"}
    real = point["rallyLength"] is not None and point["provenance"] in REAL_PROVENANCE
    return {"index": point["index"], "rallyLength": point["rallyLength"], "rallyReal": real,
            "breakPoint": point["breakPoint"], "setPoint": point["setPoint"], "matchPoint": point["matchPoint"],
            "provenance": point["provenance"]}


def candidates(project: dict) -> dict:
    """project = {sessionDurationUs, sources, points, shots, marks, lessonClips} (see the module page)."""
    duration = _int(project["sessionDurationUs"], "sessionDurationUs")
    sources = project["sources"]
    require(len({s["sourceId"] for s in sources}) == len(sources), "duplicateId", "one entry per source")
    points, unplaced = _merge_points(project["points"])
    shots_by_event: dict = {}
    for s in project["shots"]:
        require(s["provenance"] in PROVENANCE_RANK, "badInput", f"shot provenance {s['provenance']!r}")
        shots_by_event.setdefault(s["eventId"], []).append(s)
    known = {p["eventId"] for p in points}
    for event_id in sorted(set(shots_by_event) - known):
        unplaced.append({"id": event_id, "origin": "shot", "reason": "unknownEvent"})
    keepers = []
    by_event = {}
    for p in points:
        contacts = _contacts(shots_by_event.get(p["eventId"], []))
        k = _keeper("k-" + p["eventId"], "point", [p["eventId"]], _window(p["startUs"], p["endUs"], contacts, duration),
                    sources, contacts, _facts(p))
        k["seenFrom"] = p["seenFrom"]
        keepers.append(k)
        by_event[p["eventId"]] = (p, k)
    for mark in project["marks"]:
        at = _int(mark["atUs"], "mark atUs")
        home = next((k for p, k in sorted(by_event.values(), key=lambda pk: pk[0]["index"])
                     if p["startUs"] <= at < p["endUs"]), None)
        if home is not None:
            home["markIds"].append(mark["markId"])   # the same moment, counted once
            continue
        k = _keeper("k-" + mark["markId"], "mark", [mark["markId"]], _window(at, at, [], duration), sources, [],
                    _facts())
        k["markIds"].append(mark["markId"])
        k["seenFrom"] = []
        keepers.append(k)
    for clip in project["lessonClips"]:
        if clip.get("eventId"):
            if clip["eventId"] not in by_event:
                unplaced.append({"id": clip["clipId"], "origin": "lesson-clip", "reason": "unknownEvent"})
                continue
            by_event[clip["eventId"]][1]["lessonClipIds"].append(clip["clipId"])
            continue
        if not clip.get("window"):
            unplaced.append({"id": clip["clipId"], "origin": "lesson-clip", "reason": "noWindow"})
            continue
        w = clip["window"]
        require(_int(w["startUs"], "clip start") < _int(w["endUs"], "clip end"), "badInterval",
                f"lesson clip {clip['clipId']}")
        k = _keeper("k-" + clip["clipId"], "lesson-clip", [clip["clipId"]], _window(w["startUs"], w["endUs"], [],
                                                                                    duration), sources, [], _facts())
        k["lessonClipIds"].append(clip["clipId"])
        k["seenFrom"] = []
        keepers.append(k)
    keepers.sort(key=lambda k: (k["session"]["startUs"], ORIGIN_ORDER[k["origin"]], k["keeperId"]))
    return {"keepers": keepers, "unplaced": unplaced}


# ----- ranking ----------------------------------------------------------------------------------------------------

class SplitMix64:
    """The core sample generator's PRNG (jovra_ref.sample_match.SplitMix64), so a seeded random selection is the same
    on every platform."""
    MASK = (1 << 64) - 1

    def __init__(self, seed: int):
        self.state = seed & self.MASK

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & self.MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & self.MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & self.MASK
        return z ^ (z >> 31)

    def shuffled(self, items: list) -> list:
        out = list(items)
        for i in range(len(out) - 1, 0, -1):
            j = self.next() % (i + 1)
            out[i], out[j] = out[j], out[i]
        return out


def _pressure(k: dict) -> bool:
    f = k["facts"]
    return f["breakPoint"] or f["setPoint"] or f["matchPoint"]


def _item(kid: str, chapter=None, kind="keeper") -> dict:
    return {"kind": kind, "id": kid, "chapter": chapter}


def _rally_pulse(keepers, options) -> dict:
    eligible = [k for k in keepers if k["origin"] == "point" and (_pressure(k) or k["facts"]["rallyReal"])]
    eligible.sort(key=lambda k: (0 if _pressure(k) else 1,
                                 -(k["facts"]["rallyLength"] if k["facts"]["rallyReal"] else 0), k["facts"]["index"]))
    return {"order": [_item(k["keeperId"]) for k in eligible]}


def _coach_cut(keepers, options) -> dict:
    reviewed = {c["keeperId"] for c in options.get("cues", []) if c["provenance"] in ("reviewed", "validated")}
    eligible = [k for k in keepers if k["keeperId"] in reviewed or k["lessonClipIds"]]
    eligible.sort(key=lambda k: (0 if k["keeperId"] in reviewed else 1, k["session"]["startUs"], k["keeperId"]))
    return {"order": [_item(k["keeperId"]) for k in eligible]}


def _match_broadcast(keepers, options) -> dict:
    points = sorted((k for k in keepers if k["origin"] == "point"), key=lambda k: k["facts"]["index"])
    return {"order": [_item(k["keeperId"]) for k in points]}


def _progress_story(keepers, options) -> dict:
    dates = options.get("dates", {})
    dated = sorted((k for k in keepers if k["keeperId"] in dates),
                   key=lambda k: (dates[k["keeperId"]], k["session"]["startUs"], k["keeperId"]))
    if not options.get("comparable", True):
        # no comparable evidence: the film becomes a lesson chronology (story 137)
        lessons = [k for k in dated if k["lessonClipIds"]]
        return {"order": [_item(k["keeperId"]) for k in lessons], "fallback": "lesson-chronology"}
    rule = options.get("selectionRule")
    require(rule in ("all", "seeded-random", "user-chosen"), "badOptions", f"selection rule {rule!r}")
    if rule == "all":
        picked = dated
    elif rule == "seeded-random":
        count = _int(options.get("count"), "count")
        require(0 < count <= len(dated), "badOptions", f"count {count} of {len(dated)} dated examples")
        chosen = set(k["keeperId"] for k in SplitMix64(_int(options.get("seed"), "seed")).shuffled(dated)[:count])
        picked = [k for k in dated if k["keeperId"] in chosen]
    else:
        chosen = options.get("chosen", [])
        ids = {k["keeperId"] for k in dated}
        require(chosen and all(c in ids for c in chosen), "unknownKeeper", "a chosen example is not a dated keeper")
        picked = [k for k in dated if k["keeperId"] in set(chosen)]
    return {"order": [_item(k["keeperId"]) for k in picked],
            "label": CHOSEN_LABEL if rule == "user-chosen" else None}


def _court_memories(keepers, options) -> dict:
    excluded = set(options.get("excluded", []))
    brolls = [b for b in options.get("brolls", []) if b["brollId"] not in excluded]
    moments = [k for k in keepers if k["markIds"] or k["lessonClipIds"] or _pressure(k)]
    moments.sort(key=lambda k: (k["session"]["startUs"], k["keeperId"]))
    order = [_item(b["brollId"], "arrival", "broll") for b in brolls if b["chapter"] == "arrival"]
    order += [_item(k["keeperId"], "match") for k in moments]
    order += [_item(b["brollId"], "after", "broll") for b in brolls if b["chapter"] == "after"]
    missing = [name for name, present in (("arrival-broll", any(b["chapter"] == "arrival" for b in brolls)),
                                          ("match-moments", bool(moments)),
                                          ("after-broll", any(b["chapter"] == "after" for b in brolls))) if not present]
    return {"order": order, "missing": missing}


RANKERS = {"rally-pulse": _rally_pulse, "coach-cut": _coach_cut, "match-broadcast": _match_broadcast,
           "progress-story": _progress_story, "court-memories": _court_memories}


def rank(profile_id: str, keepers: list, options: dict) -> dict:
    require(profile_id in RANKERS, "unknownProfile", f"profile {profile_id!r}")
    excluded = set(options.get("excluded", []))
    kept = [k for k in keepers if k["keeperId"] not in excluded]   # an excluded keeper is never offered
    got = RANKERS[profile_id](kept, options)
    limit = options.get("limit")
    order = got["order"] if limit is None else got["order"][:_int(limit, "limit")]
    return {"profileId": profile_id, "order": order, "label": got.get("label"), "fallback": got.get("fallback"),
            "missing": got.get("missing", [])}


# ----- vectors ----------------------------------------------------------------------------------------------------

def run_vector(case: dict, project: dict) -> dict:
    """A keepers vector case (op candidates or rank) over its resolved project input -> the result, or
    {"rejectCode": code}."""
    try:
        found = candidates(project)
        if case["op"] == "candidates":
            return found
        return rank(case["input"]["profileId"], found["keepers"], case["input"]["options"])
    except Reject as exc:
        return {"rejectCode": exc.code}
