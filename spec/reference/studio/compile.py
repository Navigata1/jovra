"""EDLCompiler: a StoryPlan plus the trusted context -> a jovra.edit-plan/2 that edl.validate accepts.

Standard library only. Pure and deterministic: the same plan, context and request give byte-identical canonical JSON
and the same sha256. Module page: spec/studio/modules/compile.md.

compile_plan(profiles, plan, context, request) -> {"edl", "sha256", "omitted", "notInThisBuild", "gaps", "validation"}
                                                 | {"refusal": {"code", "message"}}
    `plan` is a jovra.story-brief/1 StoryPlan (any planner). It first passes planner.check and the grammar lint (an
    untrusted or stale plan is a typed rejection, story 148). `context` is the planning context plus the compile keys
    (`edl`, `media`, `stage`, `renderer`); every one comes from stored records, never from the plan. `request` holds
    the player's output choices: `fps`, `width`/`height`, `planId` and storyboard `trims`.

The compiler never invents material. A beat it cannot make honestly is omitted and listed with its reason (an operation
the stage has not enabled, one the renderer does not support, a replay that would need interpolated frames, a final
score card over a recording gap); a film whose real material then falls outside the profile range is refused.
"""

from __future__ import annotations

from fractions import Fraction
from math import lcm

from studio import director, planner
from studio.core import Reject, US_PER_S, canonical_sha256, frame_at_us, require, round_half_up
from studio.edl import ASPECTS, Source, fps_of, validate

VERSION = "jovra.edit-plan/2"
# SD6b operation names (the edit-plan/2 fields they map to are listed on the module page).
OPS = ("live", "broll", "replay", "freeze", "card", "transition", "overlay", "grade", "primary-bed", "hold-bed",
       "silence", "alt-bed", "reframe", "music", "narration")
S1_OPS = ("live", "broll", "replay", "freeze", "card", "transition", "overlay", "grade", "primary-bed", "hold-bed",
          "silence")
STAGES = {
    "S1": {"ops": S1_OPS, "gradePresets": ("none",), "multiAngle": False},
    "S2": {"ops": S1_OPS + ("alt-bed",), "gradePresets": ("none", "warm-court-1"), "multiAngle": True},
}
REQUIRED_OPS = ("live", "silence")                 # a build without these cannot render any film
TREATMENT_OP = {"live": "live", "replay": "replay", "freeze": "freeze", "title-card": "card", "broll": "broll"}
REQUEST_KEYS = ("fps", "width", "height", "planId", "trims")
CONTEXT_KEYS = ("edl", "media", "stage", "renderer")
GAP_TEMPLATE = "card.recording-gap"                # slot: the gap's length, derived from the coverage
FINAL_TEMPLATE = "card.final-score"
PROFILE_GRADE = {"court-memories": "warm-court-1"}   # film-engine 6.5: one catalog preset, where the stage allows it
CONTACT_PAD_MS = 250                               # contact protection, +/- 0.25 s (film-engine 2.3 rule 6)
FADE_MS = 20                                       # every bed piece fades 20 ms (the minimum at a switching cut)
LABELS = {"replay": "label.replay", "freeze": "label.paused"}
CUT = {"type": "cut", "frames": 0}
# Chapters: a beat role opens the named chapter; None continues the open one. NEW_EACH roles open a chapter every time.
CHAPTERS = {
    "coach-cut": {"goal": "chapter.goal", "context": "chapter.goal", "example": "chapter.example", "cue": None,
                  "replay": None, "drill": "chapter.practice", "checkpoint": "chapter.practice"},
    "match-broadcast": {"intro": "chapter.intro", "point": "chapter.games", "replay": None, "gap": None,
                        "final-score": "chapter.final"},
    "rally-pulse": {},
    "progress-story": {"goal": "chapter.goal", "early-evidence": "chapter.before", "lesson": "chapter.lessons",
                       "recent-evidence": "chapter.recent", "replay": None, "what-changed": "chapter.what-changed",
                       "next-goal": "chapter.next"},
    "court-memories": {"arrival": "chapter.arrival", "match-moment": "chapter.match", "highlight": "chapter.match",
                       "after": "chapter.after", "dedication": "chapter.dedication"},
}
NEW_EACH = ("example",)


# ----- small exact helpers -------------------------------------------------------------------------------------------

def frames_for_ms(ms: int, fps: Fraction) -> int:
    return round_half_up(Fraction(ms) * fps / 1000)


def clamp_frames(ms: int, lo_ms: int, hi_ms: int, fps: Fraction) -> int:
    """A hold of `ms` on the output clock (half-up), kept inside [lo_ms, hi_ms] after rounding."""
    lo = (Fraction(lo_ms) * fps / 1000).__ceil__()
    hi = (Fraction(hi_ms) * fps / 1000).__floor__()
    return min(max(frames_for_ms(ms, fps), lo), hi)


def floor_multiple(n: int, q: int) -> int:
    return n - n % q


def label_mmss(us: int) -> str:
    """Whole seconds, half up, as m:ss (h:mm:ss from an hour)."""
    s = round_half_up(Fraction(max(us, 0), US_PER_S))
    h, rest = divmod(s, 3600)
    m, s = divmod(rest, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def position(src: Source, session_us) -> Fraction | None:
    """The exact (fractional) proxy-frame position that shows a session time, through the coverage interval whose
    session span holds it; None off the coverage. The inverse of Source.session_us."""
    for lo, hi, start, rate in src.coverage:
        if start is None:
            continue
        pos = lo + (Fraction(session_us) - start) / (rate * Fraction(US_PER_S) / src.fps)
        if lo <= pos <= hi:
            return pos
    return None


def interval_index(src: Source, lo: int, hi: int):
    for n, c in enumerate(src.coverage):
        if c[0] <= lo and hi <= c[1]:
            return n
    return None


# ----- context ---------------------------------------------------------------------------------------------------

class Ctx:
    """The trusted compile context, checked and indexed once."""

    def __init__(self, profiles: dict, plan: dict, context: dict, request: dict):
        require(isinstance(context, dict) and all(k in context for k in CONTEXT_KEYS), "contextMissing",
                f"compile needs the trusted context keys {', '.join(CONTEXT_KEYS)}")
        require(context["stage"] in STAGES, "badContext", f"unknown stage {context['stage']!r}")
        supported = context["renderer"]["supportedOps"]
        require(isinstance(supported, list) and set(supported) <= set(OPS), "badContext",
                "the renderer's supported operations are SD6b operation names")
        require(isinstance(request, dict) and not set(request) - set(REQUEST_KEYS), "unknownField",
                f"request keys are {', '.join(REQUEST_KEYS)}")
        self.profile = profiles[plan["profile"]["id"]]
        self.g = self.profile["grammar"]
        self.plan, self.context, self.request = plan, context, request
        self.stage = STAGES[context["stage"]]
        self.supported = set(supported)
        self.edl = context["edl"]
        self.media = context["media"]
        self.primary_id = self.media["primarySourceId"]
        require(self.primary_id in self.edl["sources"], "untrustedSource",
                f"the primary {self.primary_id!r} is not offered by the trusted manifest and sync map")
        self.sources = {sid: Source(dict(raw, id=sid), Fraction(1)) for sid, raw in self.edl["sources"].items()}
        self.primary = self.sources[self.primary_id]
        self.keepers = {k["keeperId"]: k for k in context["keepers"]}
        current = self.edl["current"]
        require(all(current[k] == plan["bindings"][k] for k in plan["bindings"]), "staleRevision",
                "the plan is bound to other revisions than the stored records")

    def available(self, op: str):
        """None when the stage enables `op` and the renderer supports it, else the omission reason."""
        if op not in self.stage["ops"]:
            return "notInThisStage"
        if op not in self.supported:
            return "notInThisBuild"
        return None

    def source_for(self, beat: dict) -> str:
        slot = beat["angle"] if beat["angle"] is not None else self.keepers[beat["keeperId"]]["slots"][0]
        sid = self.media["slots"].get(slot)
        require(sid in self.edl["sources"], "untrustedSource",
                f"{beat['beatId']}: the {slot} angle is not offered for cutting (no reviewed sync)")
        return sid

    def recording_gap(self) -> bool:
        return len(self.primary.coverage) > 1


# ----- the compiler ----------------------------------------------------------------------------------------------

def compile_plan(profiles: dict, plan: dict, context: dict, request: dict) -> dict:
    planner.check(profiles, plan, context)
    require(not director.lint(profiles, plan, context), "grammarViolation", "the plan breaks its profile grammar")
    c = Ctx(profiles, plan, context, request)
    missing = [op for op in REQUIRED_OPS if c.available(op)]
    if missing:
        return _refusal("rendererIncomplete", f"This build cannot render a film yet (no {', '.join(missing)}).")
    omitted: list = []
    chosen = _choose(c, omitted)
    fps, size, refusal = _output(c, chosen)
    if refusal:
        return {"refusal": refusal}
    items = _build(c, chosen, fps, omitted)
    items, gaps, refusal = _gap_cards(c, items, fps)
    if refusal:
        return {"refusal": refusal}
    if not any(i["op"] in ("live", "broll") for i in items):
        return _refusal("noRelevantKeepers", director.NO_KEEPERS)
    total = sum(i["n"] for i in items)
    refusal = _range_refusal(c, total, fps)
    if refusal:
        return {"refusal": refusal}
    doc = _assemble(c, items, fps, size, total, omitted)
    result = validate(doc, profiles, c.edl)
    return {"edl": doc, "sha256": canonical_sha256(doc), "omitted": omitted,
            "notInThisBuild": sorted({o["op"] for o in omitted if o["reason"] == "notInThisBuild"}),
            "gaps": [{"segment": g["item"]["id"], "gapUs": g["gapUs"], "display": g["display"]} for g in gaps],
            "validation": {k: result[k] for k in ("status", "segments", "frames", "durationSeconds", "motionEffects",
                                                  "needsCleanAlternate")}}


def _refusal(code: str, message: str) -> dict:
    return {"refusal": {"code": code, "message": message}}


def _omit(omitted: list, beat, op: str, reason: str, **extra) -> None:
    omitted.append(dict({"beatId": beat["beatId"] if beat else None, "op": op, "reason": reason}, **extra))


def _choose(c: Ctx, omitted: list) -> list:
    """The beats that can be made at this stage with this renderer, each with its source; the rest are listed."""
    chosen, live_kept = [], set()
    for beat in c.plan["beats"]:
        t, op = beat["treatment"], TREATMENT_OP[beat["treatment"]]
        entry = {"beat": beat, "op": op, "sid": None}
        if t in ("live", "replay", "freeze"):
            entry["sid"] = c.source_for(beat)
        elif t == "broll":
            item = c.media["brolls"].get(beat["brollId"])
            require(item is not None and item["sourceId"] in c.edl["sources"], "untrustedSource",
                    f"{beat['beatId']}: B-roll {beat['brollId']!r} has no trusted source")
            entry["sid"] = item["sourceId"]
        reason = c.available(op)
        if reason is None and entry["sid"] not in (None, c.primary_id) and c.sources[entry["sid"]].role == "match" \
                and not c.stage["multiAngle"]:
            op, reason = "multi-angle", "notInThisStage"
        if reason is None and t == "replay" and beat["keeperId"] not in live_kept:
            reason = "originalOmitted"
        if reason is None and beat["templateId"] == FINAL_TEMPLATE and c.recording_gap():
            reason = "coverageIncomplete"
        if reason:
            _omit(omitted, beat, op, reason)
            continue
        if t == "live":
            live_kept.add(beat["keeperId"])
        overlays = []
        for o in beat["overlays"]:
            stored = c.edl["references"].get(o["refId"])
            require(stored is not None and stored["kind"] == o["kind"], "untrustedReference",
                    f"{beat['beatId']}: overlay {o['refId']!r} is not a stored {o['kind']}")
            require(stored["eventRevision"] == c.edl["current"]["eventRevision"], "staleRevision",
                    f"{beat['beatId']}: overlay {o['refId']!r} was stored at another event revision")
            why = c.available("overlay")
            if why:
                _omit(omitted, beat, "overlay", why, overlay=f"{o['kind']}:{o['refId']}")
                continue
            overlays.append({"kind": o["kind"], "refId": o["refId"], "eventRevision": stored["eventRevision"],
                             "provenance": stored["provenance"]})
        entry["overlays"] = overlays
        chosen.append(entry)
    for lane in ("music", "narration"):
        if c.plan[lane] is not None:
            _omit(omitted, None, lane, c.available(lane) or "notInThisStage")
    return chosen


# ----- output clock and size ---------------------------------------------------------------------------------------

def _moving(c: Ctx, chosen: list) -> list:
    return sorted({e["sid"] for e in chosen if e["op"] in ("live", "replay", "broll")} | {c.primary_id})


def _output(c: Ctx, chosen: list):
    """(fps, (width, height), None) or (None, None, refusal). The default clock is the primary's capture rate, never
    above any source the film moves through; a requested rate above a source's is refused (no repeated frames)."""
    used = _moving(c, chosen)
    want = c.request.get("fps")
    if want is not None:
        fps = fps_of(want, "requested fps")
        slow = [s for s in used if c.sources[s].fps < fps]
        if slow:
            s = c.sources[slow[0]]
            return None, None, {"code": "fpsAboveSource", "message":
                                f"A {_fps_label(fps)} fps film would repeat frames: {slow[0]} was recorded at "
                                f"{_fps_label(s.fps)} fps."}
    else:
        fps = min([c.primary.fps] + [c.sources[s].fps for s in used])
    aw, ah = ASPECTS[c.plan["aspect"]]
    default = _default_size(c.primary, aw, ah)
    w, h = c.request.get("width"), c.request.get("height")
    if w is None and h is None:
        size = default
    else:
        require(type(w) is int and type(h) is int and w > 0 and h > 0 and w % 2 == 0 and h % 2 == 0
                and w * ah == h * aw, "badRequest", f"{w}x{h} is not an even {c.plan['aspect']} size")
        size = (w, h)
    video = sorted({e["sid"] for e in chosen if e["sid"] is not None} | {c.primary_id})
    for sid in video:
        if _upscales(c.sources[sid], size):
            s = c.sources[sid]
            return None, None, {"code": "upscaleRefused", "message":
                                f"A {size[0]}x{size[1]} film from a {s.width}x{s.height} recording would only enlarge "
                                f"it, which adds no detail. The film can be at most {default[0]}x{default[1]}."}
    return fps, size, None


def _fps_label(fps: Fraction) -> str:
    return str(fps.numerator) if fps.denominator == 1 else f"{float(fps):.2f}"


def _default_size(src: Source, aw: int, ah: int) -> tuple:
    """Landscape: the primary's own size when it is 16:9, else the 16:9 frame of its height. Portrait (9:16): that
    landscape size turned on its side, so the landscape picture is letterboxed without enlarging it (SD15)."""
    if src.width * 9 == src.height * 16:
        w, h = src.width, src.height
    else:
        h = src.height - src.height % 2
        w = floor_multiple(h * 16 // 9, 2)
    return (w, h) if aw > ah else (h, w)


def _fills(src: Source, size: tuple) -> bool:
    return src.width * size[1] == src.height * size[0]


def _upscales(src: Source, size: tuple) -> bool:
    ow, oh = size
    if _fills(src, size):
        return src.height < oh
    return ow > src.width and oh > src.height


# ----- segments ----------------------------------------------------------------------------------------------------

def _k(src_fps: Fraction, speed: Fraction, out_fps: Fraction) -> Fraction:
    """Source frames per output frame."""
    return src_fps * speed / out_fps


def _snap(n_src: int, k: Fraction, q: int) -> int:
    """The most whole output frames whose source span is a whole number of frames and fits in n_src source frames."""
    return floor_multiple((Fraction(n_src) / k).__floor__(), q)


def _keeper_window(c: Ctx, kid: str, sid: str) -> tuple:
    """The trusted cut window of a keeper on one source: its stored view there, inside the keeper's session window
    mapped onto that source with the one half-up time -> frame rule."""
    view = next((v["window"] for v in c.media["views"].get(kid, []) if v["sourceId"] == sid), None)
    require(view is not None, "outsideKeeper", f"keeper {kid} has no view on {sid}")
    src, s = c.sources[sid], c.keepers[kid]["session"]
    a, b = position(src, s["startUs"]), position(src, s["endUs"])
    a = view["inFrame"] if a is None else max(view["inFrame"], round_half_up(a))
    b = view["outFrame"] if b is None else min(view["outFrame"], round_half_up(b))
    require(a < b, "outsideCoverage", f"keeper {kid} has no frames on {sid}")
    return a, b


def _trimmed(c: Ctx, beat: dict, window: tuple) -> tuple:
    trim = (c.request.get("trims") or {}).get(beat["beatId"])
    if trim is None:
        return window
    require(isinstance(trim, dict) and set(trim) == {"inFrame", "outFrame"}, "badRequest", "a trim is {inFrame, outFrame}")
    require(window[0] <= trim["inFrame"] < trim["outFrame"] <= window[1], "trimOutsideWindow",
            f"{beat['beatId']}: trim {trim} leaves the trusted window {list(window)}")
    return trim["inFrame"], trim["outFrame"]


def _contacts(c: Ctx, kid: str, sid: str, lo: int, hi: int) -> list:
    return [f for f in c.edl["contacts"].get(sid, []) if lo <= f < hi]


def _anchor(c: Ctx, kid: str, sid: str, lo: int, hi: int) -> int:
    """The frame a pause or replay centres on: the middle stored contact in the window, else the window's middle."""
    found = _contacts(c, kid, sid, lo, hi)
    return found[len(found) // 2] if found else (lo + hi) // 2


def _covered(src: Source, lo: int, hi: int, beat: dict) -> int:
    n = interval_index(src, lo, hi)
    require(n is not None, "outsideCoverage", f"{beat['beatId']}: {src.id} frames {lo}-{hi} cross a recording gap")
    return n


def _build(c: Ctx, chosen: list, fps: Fraction, omitted: list) -> list:
    items = []
    lives = {}
    court = _court_bed_wanted(c)
    q_bed = _k(c.primary.fps, Fraction(1), fps).denominator if court else 1
    for e in chosen:
        beat, op = e["beat"], e["op"]
        item = {"beat": beat, "op": op, "role": beat["role"], "overlays": e["overlays"], "sid": e["sid"]}
        if op == "card":
            item["n"] = clamp_frames(planner.CARD_MS, c.g["cardMs"]["min"], c.g["cardMs"]["max"], fps)
            item["template"] = beat["templateId"]
            item["textRefs"] = [beat["noteId"]] if beat["noteId"] else []
        elif op == "live":
            src = c.sources[e["sid"]]
            a, b = _trimmed(c, beat, _keeper_window(c, beat["keeperId"], e["sid"]))
            k = _k(src.fps, Fraction(1), fps)
            n = _snap(b - a, k, lcm(k.denominator, q_bed))
            require(n > 0, "outsideKeeper", f"{beat['beatId']}: the window is shorter than one output frame")
            item.update(n=n, s_in=a, s_out=a + int(n * k), speed=1, interval=_covered(src, a, a + int(n * k), beat))
            lives[beat["keeperId"]] = item
        elif op == "replay":
            if not _replay(c, item, lives[beat["keeperId"]], fps, omitted):
                continue
        elif op == "freeze":
            src = c.sources[e["sid"]]
            lo, hi = _keeper_window(c, beat["keeperId"], e["sid"])
            frame = _anchor(c, beat["keeperId"], e["sid"], lo, hi)
            _covered(src, frame, frame + 1, beat)
            item.update(n=clamp_frames(planner.FREEZE_MS, c.g["freezeMs"]["min"], c.g["freezeMs"]["max"], fps),
                        frame=frame)
        else:  # broll
            src = c.sources[e["sid"]]
            w = c.media["brolls"][beat["brollId"]]["window"]
            a, b = _trimmed(c, beat, (w["inFrame"], w["outFrame"]))
            if (a, b) == (w["inFrame"], w["outFrame"]):   # untrimmed: the middle of the item, at most 6 s
                n_src = min(b - a, frames_for_ms(planner.BROLL_MAX_MS, src.fps))
                a += (b - a - n_src) // 2
                b = a + n_src
            k = _k(src.fps, Fraction(1), fps)
            n = _snap(b - a, k, k.denominator)
            require(n > 0, "outsideBroll", f"{beat['beatId']}: the B-roll window is shorter than one output frame")
            item.update(n=n, s_in=a, s_out=a + int(n * k), speed=1, interval=_covered(src, a, a + int(n * k), beat))
        items.append(item)
    return items


def _replay(c: Ctx, item: dict, live: dict, fps: Fraction, omitted: list) -> bool:
    """A labelled slow replay inside the session time its live original showed; False (listed) when the clean-frame
    rule forbids it: the moment then plays at original speed only (originalSpeedFallback)."""
    beat = item["beat"]
    src, den = c.sources[item["sid"]], beat["replaySpeedDen"]
    k = _k(src.fps, Fraction(1, den), fps)
    if k < 1:
        _omit(omitted, beat, "replay", "cleanFrame", fallback="originalSpeedFallback")
        return False
    lsrc = c.sources[live["sid"]]
    l0 = lsrc.session_us(live["s_in"], lsrc.coverage[live["interval"]])
    l1 = lsrc.session_us(live["s_out"], lsrc.coverage[live["interval"]])
    p0, p1 = position(src, l0), position(src, l1)
    require(p0 is not None and p1 is not None, "outsideCoverage",
            f"{beat['beatId']}: {src.id} does not cover the moment its live original shows")
    v0, v1 = _keeper_window(c, beat["keeperId"], item["sid"])
    lo, hi = max(p0.__ceil__(), v0), min(p1.__floor__(), v1)
    n = _snap(hi - lo, k, k.denominator)
    n = min(n, floor_multiple((Fraction(c.g["replayMaxMs"]) * fps / 1000).__floor__(), k.denominator))
    require(n > 0, "outsideKeeper", f"{beat['beatId']}: no replay window inside the original")
    span = int(n * k)
    anchor = _anchor(c, beat["keeperId"], live["sid"], live["s_in"], live["s_out"])
    centre = round_half_up(position(src, lsrc.session_us(anchor)))
    start = min(max(centre - span // 2, lo), hi - span)
    item.update(n=n, s_in=start, s_out=start + span, speed=den, of=live,
                interval=_covered(src, start, start + span, beat))
    return True


# ----- recording gaps ----------------------------------------------------------------------------------------------

def _gap_cards(c: Ctx, items: list, fps: Fraction):
    """Strict-chronology profiles show a recording gap as a card ("Recording gap · m:ss") between the live segments it
    separates; a gap is never closed up (film-engine 6.2). Without cards in this build the film is refused."""
    if c.g["chronology"] != "strict":
        return items, [], None
    out, gaps, prev = [], [], None
    for item in items:
        if item["op"] == "live" and prev is not None and item["sid"] == prev["sid"] \
                and item["interval"] > prev["interval"]:
            for n in range(prev["interval"], item["interval"]):
                if c.available("card"):
                    return None, None, {"code": "gapNotShown", "message":
                                        "The recording has a gap and this build cannot show it, so the film is not made."}
                src = c.sources[item["sid"]]
                end = src.session_us(src.coverage[n][1], src.coverage[n])
                gap_us = round_half_up(src.coverage[n + 1][2] - end)
                card = {"beat": None, "op": "card", "role": "gap", "overlays": [], "sid": None, "template": GAP_TEMPLATE,
                        "textRefs": [], "n": clamp_frames(planner.CARD_MS, c.g["cardMs"]["min"],
                                                          c.g["cardMs"]["max"], fps)}
                out.append(card)
                gaps.append({"item": card, "gapUs": gap_us, "display": f"Recording gap · {label_mmss(gap_us)}"})
        if item["op"] == "live":
            prev = item
        out.append(item)
    return out, gaps, None


def _range_refusal(c: Ctx, total: int, fps: Fraction):
    lo, hi = c.g["durationSeconds"]["min"], c.g["durationSeconds"]["max"]
    seconds = Fraction(total) / fps
    ms = round_half_up(seconds * 1000)
    if seconds < lo:
        return {"code": "belowProfileMinimum", "message":
                f"About {director.estimate_label(ms)} of real material; {c.profile['name']} needs at least "
                f"{director.length_label(lo)}. Mark more moments for a longer film."}
    if seconds > hi:
        return {"code": "aboveProfileMaximum", "message":
                f"About {director.estimate_label(ms)} of material; {c.profile['name']} films are up to "
                f"{director.length_label(hi)}."}
    return None


# ----- the document ------------------------------------------------------------------------------------------------

def _court_bed_wanted(c: Ctx) -> bool:
    return c.plan["primaryAudioPolicy"] == "continuous-primary-court-audio" and c.primary.has_audio


def _assemble(c: Ctx, items: list, fps: Fraction, size: tuple, total: int, omitted: list) -> dict:
    cursor = 0
    for n, item in enumerate(items, start=1):
        item.update(id=f"s{n:02d}", o_in=cursor, o_out=cursor + item["n"])
        cursor += item["n"]
    segments = [_segment(c, item, size) for item in items]
    grade = PROFILE_GRADE.get(c.profile["id"], "none")
    if grade != "none":
        why = None if grade in c.stage["gradePresets"] else "notInThisStage"
        why = why or c.available("grade")
        if why:
            _omit(omitted, None, "grade", why, preset=grade)
            grade = "none"
    audio = _audio(c, items, fps, omitted)
    used = {s["sourceId"] for s in segments if "sourceId" in s} | {p["sourceId"] for p in audio["bed"] if p["sourceId"]}
    order = sorted(used, key=lambda s: (s != c.primary_id, c.sources[s].role != "match", s))
    current = c.edl["current"]
    fps_doc = {"num": fps.numerator, "den": fps.denominator}
    return {
        "schemaVersion": VERSION, "projectId": c.plan["projectId"],
        "planId": c.request.get("planId") or ("film-" + c.plan["briefId"].removeprefix("brief-"))[:64],
        "planRevision": c.plan["revision"], "sample": c.plan["sample"], "cleanAlternate": False,
        "bindings": {"sourceManifestRevision": current["sourceManifestRevision"],
                     "syncRevision": current["syncRevision"], "eventRevision": current["eventRevision"],
                     "profileId": c.profile["id"], "profileRevision": c.profile["revision"],
                     "keeperCatalogRevision": current["keeperCatalogRevision"],
                     "brollCatalogRevision": current["brollCatalogRevision"]},
        "output": {"fps": fps_doc, "width": size[0], "height": size[1], "aspect": c.plan["aspect"],
                   "totalFrames": total, "container": "mp4", "videoCodec": "h264", "audioCodec": "aac",
                   "audioSampleRate": 48000},
        "grade": {"presetId": grade},
        "sources": [dict({"id": sid}, **c.edl["sources"][sid]) for sid in order],
        "segments": segments, "chapters": _chapters(c, items), "audio": audio,
    }


def _segment(c: Ctx, item: dict, size: tuple) -> dict:
    head = {"id": item["id"], "op": "title-card" if item["op"] == "card" else item["op"],
            "outputInFrame": item["o_in"], "outputOutFrame": item["o_out"], "transitionIn": dict(CUT)}
    if item["op"] == "card":
        return dict(head, templateId=item["template"], textRefs=list(item["textRefs"]), overlayRefs=item["overlays"])
    src = c.sources[item["sid"]]
    framing = {"mode": "fill" if _fills(src, size) else "letterbox"}
    if item["op"] == "freeze":
        return dict(head, sourceId=item["sid"], sourceFrame=item["frame"], labelTemplateId=LABELS["freeze"],
                    overlayRefs=item["overlays"], framing=framing)
    body = dict(head, sourceId=item["sid"], sourceInFrame=item["s_in"], sourceOutFrame=item["s_out"],
                speed={"num": 1, "den": item["speed"]})
    if item["op"] == "live":
        pad = frames_for_ms(CONTACT_PAD_MS, src.fps)
        protected = [{"inFrame": max(item["s_in"], f - pad), "outFrame": min(item["s_out"], f + pad + 1)}
                     for f in _contacts(c, item["beat"]["keeperId"], item["sid"], item["s_in"], item["s_out"])]
        session = src.session_us(item["s_in"], src.coverage[item["interval"]])
        return dict(body, sessionInUs=round_half_up(session), keeperId=item["beat"]["keeperId"],
                    protectedFrames=protected, overlayRefs=item["overlays"], framing=framing)
    if item["op"] == "replay":
        return dict(body, replayOf=item["of"]["id"], labelTemplateId=LABELS["replay"], overlayRefs=item["overlays"],
                    framing=framing)
    return dict(body, brollId=item["beat"]["brollId"], overlayRefs=item["overlays"], framing=framing)


def _chapters(c: Ctx, items: list) -> list:
    roles = CHAPTERS.get(c.profile["id"], {})
    out, seen, current = [], {}, None
    for item in items:
        template = roles.get(item["role"])
        if template is None or (template == current and item["role"] not in NEW_EACH):
            continue
        current = template
        name = template.removeprefix("chapter.")
        seen[name] = seen.get(name, 0) + 1
        cid = f"ch-{name}" if seen[name] == 1 else f"ch-{name}-{seen[name]}"
        out.append({"id": cid, "outputInFrame": item["o_in"], "templateId": template})
    if out:
        out[0]["outputInFrame"] = 0   # the first chapter starts the film
    return out


# ----- the audio bed -----------------------------------------------------------------------------------------------

def _audio(c: Ctx, items: list, fps: Fraction, omitted: list) -> dict:
    """One route per output frame. primary-bed only under live play, in sync through the session clock; hold-bed
    continues it without a jump under a replay, pause or card over real dead time; alt-bed (B-roll's own sound, or a
    reviewed angle where the primary does not cover a live moment) only where the stage enables it; silence otherwise.
    Every change of source sits on a segment boundary (all cuts) with 20 ms fades."""
    court = _court_bed_wanted(c)
    if court and c.available("primary-bed"):
        _omit(omitted, None, "primary-bed", c.available("primary-bed"))
        court = False
    if court and c.available("hold-bed") and any(i["op"] in ("replay", "freeze", "card") for i in items):
        # those pieces play over silence instead of holding the court sound; list the missing operation honestly
        _omit(omitted, None, "hold-bed", c.available("hold-bed"))
    pieces = []
    for item in items:
        piece = _court_piece(c, item, items, pieces, fps) if court else None
        if piece is None and item["op"] == "broll" and court and not c.available("alt-bed") \
                and c.sources[item["sid"]].has_audio:
            piece = _piece("alt-bed", item["sid"], item["s_in"], item)
        if piece is None:
            piece = _piece("silence", None, None, item)
        if piece["route"] == "silence" and pieces and pieces[-1]["route"] == "silence":
            pieces[-1]["outputOutFrame"] = item["o_out"]
            continue
        pieces.append(piece)
    sounding = any(p["route"] != "silence" for p in pieces)
    return {"primarySourceId": c.primary_id if sounding else None, "bed": [_strip(p) for p in pieces],
            "narration": None, "music": None}


def _piece(route, sid, s_in, item) -> dict:
    return {"route": route, "sourceId": sid, "sourceInFrame": s_in, "outputInFrame": item["o_in"],
            "outputOutFrame": item["o_out"], "fadeInMs": FADE_MS, "fadeOutMs": FADE_MS}


def _strip(p: dict) -> dict:
    return {k: p[k] for k in ("route", "sourceId", "sourceInFrame", "outputInFrame", "outputOutFrame", "fadeInMs",
                              "fadeOutMs")}


def _court_piece(c: Ctx, item: dict, items: list, pieces: list, fps: Fraction):
    p = c.primary
    n = Fraction(item["n"]) * p.fps / fps
    if item["op"] == "live":
        src = c.sources[item["sid"]]
        at = position(p, src.session_us(item["s_in"], src.coverage[item["interval"]]))
        if at is not None and n.denominator == 1:
            f = round_half_up(at)
            if interval_index(p, f, f + int(n)) is not None:
                return _piece("primary-bed", c.primary_id, f, item)
        if not c.available("alt-bed") and src.has_audio and item["sid"] != c.primary_id:
            return _piece("alt-bed", item["sid"], item["s_in"], item)
        raise Reject("noCourtAudio", f"{item['beat']['beatId']}: no reviewed court sound covers this live moment")
    if item["op"] == "broll" or c.available("hold-bed") or not pieces or n.denominator != 1:
        return None
    prev = pieces[-1]
    if prev["route"] not in ("primary-bed", "hold-bed"):
        return None
    start = prev["sourceInFrame"] + int(Fraction(prev["outputOutFrame"] - prev["outputInFrame"]) * p.fps / fps)
    end = start + int(n)
    cov = interval_index(p, start, end)
    if cov is None:
        return None
    b0, b1 = p.session_us(start, p.coverage[cov]), p.session_us(end, p.coverage[cov])
    shown = _last_live_keeper(items, item)
    for other in items:
        if other["op"] == "live":
            src = c.sources[other["sid"]]
            cv = src.coverage[other["interval"]]
            if src.session_us(other["s_in"], cv) < b1 and b0 < src.session_us(other["s_out"], cv):
                return None
    for k in c.keepers.values():   # the only play the context knows: another kept point is never dead time
        if k["keeperId"] != shown and k["session"]["startUs"] < b1 and b0 < k["session"]["endUs"]:
            return None
    return _piece("hold-bed", c.primary_id, start, item)


def _last_live_keeper(items: list, item: dict):
    last = None
    for other in items:
        if other is item:
            return last
        if other["op"] == "live":
            last = other["beat"]["keeperId"]
    return last


# ----- vectors -----------------------------------------------------------------------------------------------------

def run_vector(profiles: dict, case: dict) -> dict:
    """A compile vector case (op compile) -> its result, or {"rejectCode": code}."""
    inp = case["input"]
    try:
        if case["op"] == "compile":
            return compile_plan(profiles, inp["plan"], inp["context"], inp["request"])
        raise Reject("badOp", f"op {case['op']!r}")
    except Reject as exc:
        return {"rejectCode": exc.code}
