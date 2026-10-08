"""Reference validator for jovra.edit-plan/2 (the Studio edit decision list).

Extends tools/studio-plan/scripts/validate_edit_plan.py (jovra.edit-plan/1): the same strict unknown-field
rejection, contiguous output coverage, revision binding and allowlists, plus labelled replays at bounded speeds,
freezes, title cards, B-roll, overlay references bound to the event revision, allowlisted transitions with source
handles and contact protection, an audio bed (exactly one route per output frame, primary court audio in sync during
live play), optional consented and ducked narration, rights-bound music, output aspect with letterbox or reviewed
reframe windows, chapters and a clean-alternate flag.

Everything the plan names by id is resolved against a trusted context that the caller builds from stored records
(bundle.edl_context): source snapshots and their reviewed coverage, keepers, B-roll items, overlay targets and notes
with their stored kind and provenance, consents and rights. The context is required; validate() refuses to run
without it, so a renderer can never accept a plan's self-declared coverage, provenance, consent or rights.

A valid plan is a checked proposal only. It proves nothing about real footage, alignment quality, rights or
editorial truth, and it is never spending permission (an EDL has no approval, price, path, URL or secret field).
"""

from __future__ import annotations

import copy
import re
from fractions import Fraction

from .core import (canonical_sha256, fps_fraction, frame_duration_us, rate_fraction, require,
                   round_half_up, seconds)

VERSION = "jovra.edit-plan/2"
MAX_MATCH_SOURCES = 6          # one primary + up to five more phones
MAX_BROLL_SOURCES = 12
MAX_SEGMENTS = 128             # the founder editor's draft bound (production_preview.py MAX_SEGMENTS)
MAX_OUTPUT_SECONDS = 14400     # four hours, as the starter
MAX_OVERLAYS = 8
MAX_DIMENSION = 3840
FRAME_UNITS = 10000            # reframe windows are in 1/10 000 of the source frame
MAX_PAN_UNITS_PER_FRAME = 50   # proposal: at most 0.5% of the frame per output frame
MAX_REFRAME_UPSCALE = 2
ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}")
TEMPLATE = re.compile(r"[a-z][a-z0-9-]{0,31}(\.[a-z0-9][a-z0-9-]{0,31}){0,3}")
HEX64 = re.compile(r"[0-9a-f]{64}")
ASPECTS = {"16:9": (16, 9), "9:16": (9, 16), "1:1": (1, 1), "4:5": (4, 5)}
PROVENANCE = {"manual", "estimated", "reviewed", "validated"}
OVERLAY_KINDS = {"score", "metric", "note", "cue", "annotation"}
FORBIDDEN_KEYS = {"command", "cmd", "shell", "script", "path", "localpath", "file", "url", "uri", "href",
                  "endpoint", "secret", "token", "apikey", "password", "credential", "signedurl", "filter",
                  "filtergraph", "approved", "paid", "renderallowed", "price", "amount", "cost"}

SEGMENT_FIELDS = {
    "live": ("id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
             "sessionInUs keeperId protectedFrames overlayRefs framing"),
    "broll": ("id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
              "brollId overlayRefs framing"),
    "replay": ("id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
               "replayOf labelTemplateId overlayRefs framing"),
    "freeze": ("id op outputInFrame outputOutFrame transitionIn sourceId sourceFrame labelTemplateId "
               "overlayRefs framing"),
    "title-card": "id op outputInFrame outputOutFrame transitionIn templateId textRefs overlayRefs",
}
LABELS = {"replay": "label.replay", "freeze": "label.paused"}
VIDEO_OPS = {"live", "broll", "replay", "freeze"}
MOVING_OPS = {"live", "broll", "replay"}


# ----- small strict helpers -----------------------------------------------------------------------

def fields(obj, names: str, label: str) -> None:
    require(type(obj) is dict, "notObject", f"{label} must be an object")
    want = set(names.split())
    have = set(obj)
    require(not (have - want), "unknownField", f"{label}: unknown field(s) {sorted(have - want)}")
    require(not (want - have), "missingField", f"{label}: missing field(s) {sorted(want - have)}")


def integer(value, label: str, minimum: int = 0) -> int:
    require(type(value) is int and value >= minimum, "badInteger", f"{label} must be an integer >= {minimum}")
    return value


def identifier(value, label: str) -> str:
    require(type(value) is str and ID.fullmatch(value) is not None, "badIdentifier", f"{label}: invalid id")
    return value


def template(value, label: str, prefix: str = "") -> str:
    require(type(value) is str and TEMPLATE.fullmatch(value) is not None and value.startswith(prefix),
            "badTemplate", f"{label}: invalid template id")
    return value


def fps_of(value, label: str) -> Fraction:
    fields(value, "num den", label)
    rate = Fraction(integer(value["num"], label + ".num", 1), integer(value["den"], label + ".den", 1))
    require(1 <= rate <= 240, "badFps", f"{label} outside 1-240 fps")
    return rate


def scan_forbidden(value, where: str = "$") -> None:
    """Defense in depth: executable, location, credential and spend fields are refused by name anywhere."""
    if isinstance(value, dict):
        for key, item in value.items():
            require(key.lower() not in FORBIDDEN_KEYS, "forbiddenField", f"{where}.{key} is never allowed in an EDL")
            scan_forbidden(item, f"{where}.{key}")
    elif isinstance(value, list):
        for i, item in enumerate(value):
            scan_forbidden(item, f"{where}[{i}]")
    elif isinstance(value, str):
        require("://" not in value and not value.startswith(("/", "~", "\\")) and ".." not in value,
                "forbiddenValue", f"{where}: looks like a path or URL")


# ----- sources and coverage -----------------------------------------------------------------------

class Source:
    def __init__(self, raw: dict, out_fps: Fraction):
        fields(raw, "id role sha256 proxy hasAudio coverage", "source")
        self.id = identifier(raw["id"], "source id")
        require(raw["role"] in ("match", "broll"), "badEnum", "source role must be match or broll")
        self.role = raw["role"]
        require(type(raw["sha256"]) is str and HEX64.fullmatch(raw["sha256"]) is not None, "badHash",
                "source sha256 must be 64 lowercase hex")
        self.sha256 = raw["sha256"]
        proxy = raw["proxy"]
        fields(proxy, "fps width height frameCount ptsTableSha256", "source proxy")
        self.fps = fps_of(proxy["fps"], "proxy fps")
        self.fps_raw = proxy["fps"]
        self.width = integer(proxy["width"], "proxy width", 2)
        self.height = integer(proxy["height"], "proxy height", 2)
        self.frames = integer(proxy["frameCount"], "proxy frameCount", 1)
        require(seconds(self.frames, proxy["fps"]) <= MAX_OUTPUT_SECONDS, "sourceTooLong", "source exceeds four hours")
        require(type(proxy["ptsTableSha256"]) is str and HEX64.fullmatch(proxy["ptsTableSha256"]) is not None,
                "badHash", "proxy ptsTableSha256 must be 64 lowercase hex")
        require(type(raw["hasAudio"]) is bool, "badBoolean", "hasAudio must be boolean")
        self.has_audio = raw["hasAudio"]
        require(type(raw["coverage"]) is list and 1 <= len(raw["coverage"]) <= 64, "badCoverage",
                "coverage needs 1-64 intervals")
        self.coverage = []
        cursor = 0
        for c in raw["coverage"]:
            fields(c, "inFrame outFrame sessionStartUs rate", "coverage interval")
            lo = integer(c["inFrame"], "coverage inFrame")
            hi = integer(c["outFrame"], "coverage outFrame", 1)
            require(cursor <= lo < hi <= self.frames, "badCoverage", "coverage intervals must be ordered, "
                    "disjoint and inside the proxy")
            cursor = hi
            if self.role == "broll":
                require(c["sessionStartUs"] is None and c["rate"] is None, "badCoverage",
                        "B-roll is not on the session clock (sessionStartUs and rate are null)")
                self.coverage.append((lo, hi, None, None))
            else:
                start = integer(c["sessionStartUs"], "coverage sessionStartUs")
                fields(c["rate"], "num den", "coverage rate")
                require(type(c["rate"]["den"]) is int and c["rate"]["den"] == 1_000_000_000 and type(c["rate"]["num"]) is int
                        and 900_000_000 <= c["rate"]["num"] <= 1_100_000_000, "badRate",
                        "rate must be num/1000000000 within 0.9-1.1")
                self.coverage.append((lo, hi, start, rate_fraction(c["rate"])))

    def interval(self, lo, hi):
        """The coverage interval containing the source-frame range [lo, hi), else None (gap or outside)."""
        for c in self.coverage:
            if c[0] <= lo and hi <= c[1]:
                return c
        return None

    def session_us(self, frame: Fraction, cov=None):
        """Exact session time of a (possibly fractional) proxy frame position, or None off the session clock.

        Coverage intervals are half-open [inFrame, outFrame) and may be adjacent (a restart: the next interval starts
        on the frame where the previous one ends, at an unrelated session time). Without `cov` the lookup is
        half-open, so the first frame of a restarted interval maps through that interval, never through the previous
        interval's extrapolated end; the exclusive end of the last interval is allowed. With `cov` (the interval a
        window was already found inside) the position may equal that interval's exclusive end, which is how a
        window's end time is computed."""
        if cov is None:
            cov = next((c for c in self.coverage if c[0] <= frame < c[1]), None)
            if cov is None and self.coverage and frame == self.coverage[-1][1]:
                cov = self.coverage[-1]
            if cov is None:
                return None
        lo, hi, start, rate = cov
        if not lo <= frame <= hi or start is None:
            return None
        return start + (Fraction(frame) - lo) * frame_duration_us(self.fps_raw) * rate


# ----- the validator ------------------------------------------------------------------------------

CONTEXT_KEYS = ("projectId", "current", "sources", "keepers", "contacts", "brolls", "references", "consents", "rights")


def validate(plan: dict, profiles: dict, context: dict) -> dict:
    """Validate a jovra.edit-plan/2 document. Raises Reject(code, message) on the first violation.

    profiles: {profileId: profile record} from the story-profile catalog (trusted, versioned).
    context (required, trusted, built by bundle.edl_context from stored records, never from the plan):
      "projectId":  the project whose stored records built this context (a plan for another project is refused)
      "current":    {binding: current revision}
      "sources":    {sourceId: {"sha256", "role", "proxy", "hasAudio", "coverage"}}; only sources offered for cutting
                    (a match source appears only with a reviewed or reference sync map, its coverage from that map)
      "keepers":    [keeperId], "brolls": [brollId]
      "contacts":   {sourceId: [proxy frame]} every stored keeper contact, whatever keeper a plan names (or none)
      "references": {refId: {"kind", "provenance", "eventRevision"}}  overlay targets and notes (textRefs, scripts)
      "consents":   {consentRecordId: {"participantId", "scope": [...], "granted"}}
      "rights":     {rightsRecordId: {"assetId", "scope": [...]}}
    """
    require(type(context) is dict and all(key in context for key in CONTEXT_KEYS), "contextMissing",
            f"validate() needs the trusted context ({', '.join(CONTEXT_KEYS)}); a plan is never checked against itself")
    scan_forbidden(plan)
    fields(plan, "schemaVersion projectId planId planRevision sample cleanAlternate bindings output grade "
                 "sources segments chapters audio", "plan")
    require(plan["schemaVersion"] == VERSION, "badVersion", f"schemaVersion must be {VERSION}")
    identifier(plan["projectId"], "projectId")
    require(plan["projectId"] == context["projectId"], "projectMismatch",
            "the plan names another project than the stored records it is checked against")
    identifier(plan["planId"], "planId")
    integer(plan["planRevision"], "planRevision", 1)
    require(type(plan["sample"]) is bool, "badBoolean", "sample must be boolean")
    require(type(plan["cleanAlternate"]) is bool, "badBoolean", "cleanAlternate must be boolean")

    bindings = plan["bindings"]
    fields(bindings, "sourceManifestRevision syncRevision eventRevision profileId profileRevision "
                     "keeperCatalogRevision brollCatalogRevision", "bindings")
    for key in ("sourceManifestRevision", "syncRevision", "eventRevision", "profileRevision",
                "keeperCatalogRevision", "brollCatalogRevision"):
        integer(bindings[key], key, 1)
    require(bindings["profileId"] in profiles, "unknownProfile", "unknown story profile")
    profile = profiles[bindings["profileId"]]
    grammar = profile["grammar"]
    require(bindings["profileRevision"] == profile["revision"], "staleRevision",
            "plan is bound to a different story-profile revision")
    for key, current in context["current"].items():
        require(bindings.get(key) == current, "staleRevision", f"{key} {bindings.get(key)} is not current ({current})")

    out = plan["output"]
    fields(out, "fps width height aspect totalFrames container videoCodec audioCodec audioSampleRate", "output")
    out_fps = fps_of(out["fps"], "output fps")
    width = integer(out["width"], "output width", 2)
    height = integer(out["height"], "output height", 2)
    require(width % 2 == 0 and height % 2 == 0 and width <= MAX_DIMENSION and height <= MAX_DIMENSION,
            "badOutput", "output dimensions must be even and at most 3840")
    require(out["aspect"] in ASPECTS, "badOutput", "unsupported aspect")
    aw, ah = ASPECTS[out["aspect"]]
    require(width * ah == height * aw, "badOutput", "width/height do not match the declared aspect")
    total = integer(out["totalFrames"], "totalFrames", 1)
    duration = seconds(total, out["fps"])
    require(duration <= MAX_OUTPUT_SECONDS, "outputTooLong", "output exceeds four hours")
    require(out["container"] == "mp4" and out["videoCodec"] in ("h264", "hevc") and out["audioCodec"] == "aac"
            and out["audioSampleRate"] == 48000, "badOutput", "output must be MP4, H.264/HEVC, AAC 48 kHz")
    lo_s, hi_s = grammar["durationSeconds"]["min"], grammar["durationSeconds"]["max"]
    require(lo_s <= duration <= hi_s, "durationOutsideProfile",
            f"{duration} s is outside the profile's {lo_s}-{hi_s} s")

    grade = plan["grade"]
    fields(grade, "presetId", "grade")
    require(grade["presetId"] in grammar["gradePresets"], "opNotAllowed", "grade preset not allowed for this profile")

    # sources
    require(type(plan["sources"]) is list and plan["sources"], "badSources", "at least one source")
    sources: dict[str, Source] = {}
    for raw in plan["sources"]:
        src = Source(raw, out_fps)
        require(src.id not in sources, "duplicateId", f"duplicate source {src.id}")
        trusted = context["sources"].get(src.id)
        require(trusted is not None and trusted["sha256"] == src.sha256, "untrustedSource",
                f"source {src.id} is not offered by the trusted manifest and sync map with this hash")
        require(raw["role"] == trusted["role"] and raw["proxy"] == trusted["proxy"]
                and raw["hasAudio"] is trusted["hasAudio"], "untrustedSource",
                f"source {src.id}: the plan's snapshot differs from the trusted manifest")
        require(raw["coverage"] == trusted["coverage"], "coverageMismatch",
                f"source {src.id}: coverage (session start, rate, frames) is not the reviewed sync map's")
        sources[src.id] = src
    n_match = sum(1 for s in sources.values() if s.role == "match")
    n_broll = len(sources) - n_match
    require(1 <= n_match <= MAX_MATCH_SOURCES and n_broll <= MAX_BROLL_SOURCES, "badSources",
            "one to six match sources and at most twelve B-roll sources")

    # segments
    segs = plan["segments"]
    require(type(segs) is list and 1 <= len(segs) <= MAX_SEGMENTS, "tooManySegments", "1-128 segments")
    seen: dict[str, dict] = {}
    order: list[dict] = []
    cursor = 0
    motion = False
    last_live_session = None
    shown_live: list[tuple] = []   # (session start, session end, source) of every live segment so far
    for index, seg in enumerate(segs):
        require(type(seg) is dict and seg.get("op") in SEGMENT_FIELDS, "badOp", "unknown segment op")
        op = seg["op"]
        fields(seg, SEGMENT_FIELDS[op], f"segment {index} ({op})")
        sid = identifier(seg["id"], "segment id")
        require(sid not in seen, "duplicateId", f"duplicate segment id {sid}")
        require(op in grammar["ops"], "opNotAllowed", f"{op} is not allowed in {profile['id']}")
        o_in = integer(seg["outputInFrame"], "outputInFrame")
        o_out = integer(seg["outputOutFrame"], "outputOutFrame", 1)
        require(o_in == cursor, "outputGap", f"segment {sid} must start at output frame {cursor}")
        require(o_in < o_out <= total, "badInterval", f"segment {sid} has an invalid output interval")
        cursor = o_out
        out_len = o_out - o_in
        seg_info = {"seg": seg, "op": op, "in": o_in, "out": o_out, "session": None}

        if op in MOVING_OPS:
            src = _source_for(seg, sources, op)
            s_in = integer(seg["sourceInFrame"], "sourceInFrame")
            s_out = integer(seg["sourceOutFrame"], "sourceOutFrame", 1)
            require(s_in < s_out, "badInterval", f"segment {sid} has an empty source window")
            speed = _speed(seg["speed"], op, grammar)
            # source seconds == output seconds x speed, exactly
            require(Fraction(s_out - s_in) / src.fps == Fraction(out_len) / out_fps * speed, "durationMismatch",
                    f"segment {sid}: source and output durations disagree at speed {speed}")
            # clean-frame rule: every output frame is a distinct real captured frame
            require(src.fps * speed >= out_fps, "cleanFrameRule",
                    f"segment {sid}: source fps x speed is below the output fps (no interpolated frames)")
            cov = src.interval(s_in, s_out)
            require(cov is not None, "outsideCoverage",
                    f"segment {sid}: source window leaves the reviewed coverage or crosses a gap")
            seg_info.update(src=src, s_in=s_in, s_out=s_out, speed=speed, cov=cov)
            if src.role == "match":
                seg_info["session"] = (src.session_us(s_in, cov), src.session_us(s_out, cov))
            if op == "live":
                require(src.role == "match", "badSourceRole", f"live segment {sid} needs a match source")
                require(seg["keeperId"] is None or ID.fullmatch(str(seg["keeperId"])) is not None, "badIdentifier",
                        "keeperId must be an id or null")
                if seg["keeperId"] is not None:
                    require(seg["keeperId"] in context["keepers"], "untrustedReference", "unknown keeper")
                expected = round_half_up(src.session_us(s_in, cov))
                require(seg["sessionInUs"] == expected, "sessionTimeMismatch",
                        f"segment {sid}: sessionInUs must be {expected} from the sync map")
                require(type(seg["protectedFrames"]) is list and len(seg["protectedFrames"]) <= 64, "badProtected",
                        "protectedFrames must be a list")
                prot = []
                for w in seg["protectedFrames"]:
                    fields(w, "inFrame outFrame", "protected window")
                    a, b = integer(w["inFrame"], "protected in"), integer(w["outFrame"], "protected out", 1)
                    require(s_in <= a < b <= s_out, "badProtected", "protected window must lie inside the segment")
                    prot.append((a, b))
                seg_info["protected"] = prot
                # every stored contact in the window is protected, whatever keeperId says (a plan cannot opt out of
                # contact protection by naming no keeper)
                for c in context["contacts"].get(src.id, []):
                    if s_in <= c < s_out:
                        require(any(a <= c < b for a, b in prot), "contactUnprotected",
                                f"segment {sid}: stored contact at frame {c} is not inside a protected window")
                if grammar["chronology"] == "strict":
                    require(last_live_session is None or seg["sessionInUs"] > last_live_session, "chronology",
                            f"segment {sid}: live segments must keep session order in {profile['id']}")
                last_live_session = seg["sessionInUs"]
                # a moment shown live is shown live once: showing it again is a replay and carries the Replay label.
                # Two angles cut at one instant may overlap by up to one source frame of the coarser angle.
                l0, l1 = seg_info["session"]
                for p0, p1, other in shown_live:
                    slack = max(frame_duration_us(src.fps_raw), frame_duration_us(other.fps_raw))
                    require(min(l1, p1) - max(l0, p0) <= slack, "replayWithoutLabel",
                            f"segment {sid} shows session time an earlier live segment already showed; "
                            "a repeat is a labelled replay")
                shown_live.append((l0, l1, src))
            elif op == "broll":
                require(src.role == "broll", "badSourceRole", f"broll segment {sid} needs a B-roll source")
                identifier(seg["brollId"], "brollId")
                require(seg["brollId"] in context["brolls"], "untrustedReference", "unknown B-roll item")
            elif op == "replay":
                _check_replay(seg, seg_info, seen, order, grammar, out_fps, out_len, profile)
        elif op == "freeze":
            src = _source_for(seg, sources, op)
            frame = integer(seg["sourceFrame"], "sourceFrame")
            require(src.interval(frame, frame + 1) is not None, "outsideCoverage", f"freeze {sid} frame not covered")
            require(seg["labelTemplateId"] == LABELS["freeze"], "labelMissing", "a freeze needs the Paused label")
            ms = Fraction(out_len) / out_fps * 1000
            require(grammar["freezeMs"]["min"] <= ms <= grammar["freezeMs"]["max"], "freezeDuration",
                    f"freeze {sid} lasts {ms} ms")
            seg_info.update(src=src)
        else:  # title-card
            template(seg["templateId"], "card templateId", "card.")
            require(type(seg["textRefs"]) is list and len(seg["textRefs"]) <= 4, "badTextRefs", "at most 4 text refs")
            for ref in seg["textRefs"]:
                identifier(ref, "textRef")
                _resolve_note(ref, context, f"card {sid} textRef")
            ms = Fraction(out_len) / out_fps * 1000
            require(grammar["cardMs"]["min"] <= ms <= grammar["cardMs"]["max"], "cardDuration",
                    f"card {sid} lasts {ms} ms")

        if op in VIDEO_OPS:
            motion |= _check_framing(seg["framing"], seg_info, sources[seg["sourceId"]], out, grammar, out_len)
        _check_overlays(seg["overlayRefs"], bindings, grammar, sid, context)
        motion |= _check_transition(seg["transitionIn"], seg_info, order, grammar, out["fps"], index, context)
        seen[sid] = seg_info
        order.append(seg_info)
    require(cursor == total, "incompleteCoverage", "segments must cover every output frame exactly once")

    _check_chapters(plan["chapters"], total)
    _check_audio(plan["audio"], sources, order, total, out_fps, out["fps"], grammar, context)

    if plan["cleanAlternate"]:
        require(not motion, "motionInCleanAlternate",
                "a clean alternate has no dissolves, dips or moving reframes")
    return {
        "status": "valid-plan",
        "sample": plan["sample"],
        "profileId": profile["id"],
        "segments": len(segs),
        "frames": total,
        "durationSeconds": str(duration),
        "motionEffects": motion,
        "needsCleanAlternate": motion and not plan["cleanAlternate"],
        "planSha256": canonical_sha256(plan),
        "actualMediaVerified": False,
        "rendered": False,
    }


def _source_for(seg, sources, op) -> Source:
    sid = identifier(seg["sourceId"], f"{op} sourceId")
    require(sid in sources, "unknownSource", f"unknown source {sid}")
    return sources[sid]


def _speed(raw, op, grammar) -> Fraction:
    fields(raw, "num den", "speed")
    require(type(raw["num"]) is int and raw["num"] == 1 and type(raw["den"]) is int and raw["den"] in (1, 2, 4, 8), "badSpeed",
            "speed must be 1, 1/2, 1/4 or 1/8")
    if op in ("live", "broll"):
        require(raw["den"] == 1, "badSpeed", "live action and B-roll stay at original speed")
    else:
        require(raw["den"] in grammar["replaySpeedDens"], "badSpeed", "replay speed not allowed by this profile")
    return Fraction(1, raw["den"])


def _check_replay(seg, info, seen, order, grammar, out_fps, out_len, profile) -> None:
    sid = seg["id"]
    require(seg["labelTemplateId"] == LABELS["replay"], "labelMissing", "a replay needs the Replay label")
    require(Fraction(out_len) / out_fps * 1000 <= grammar["replayMaxMs"], "replayTooLong",
            f"replay {sid} is longer than {grammar['replayMaxMs']} ms of output")
    target = seen.get(seg["replayOf"]) if isinstance(seg["replayOf"], str) else None
    require(target is not None and target["op"] == "live", "replayBeforeOriginal",
            f"replay {sid} must follow the live segment it re-shows")
    require(info["src"].role == "match", "badSourceRole", "a replay re-shows match footage")
    half = frame_duration_us({"num": out_fps.numerator, "den": out_fps.denominator}) / 2
    r0, r1 = info["session"]
    l0, l1 = target["session"]
    require(l0 - half <= r0 and r1 <= l1 + half, "replayOutsideOriginal",
            f"replay {sid} shows session time that its original live segment did not show")
    if grammar["chronology"] == "strict":
        later_live = [o for o in order[order.index(target) + 1:] if o["op"] == "live"]
        require(not later_live, "chronology", f"replay {sid} must come before the next live point")


def _check_framing(framing, info, src: Source, out, grammar, out_len) -> bool:
    """Returns True when the framing is a motion effect (a moving reframe)."""
    require(type(framing) is dict and framing.get("mode") in ("fill", "letterbox", "reframe"), "badFraming",
            "framing mode must be fill, letterbox or reframe")
    ow, oh = out["width"], out["height"]
    same_aspect = src.width * oh == src.height * ow
    mode = framing["mode"]
    if mode == "fill":
        fields(framing, "mode", "framing")
        require(same_aspect, "framingAspect", "fill needs the source aspect to equal the output aspect; "
                "letterbox or reframe instead of a blind crop")
        require(src.height >= oh, "upscaleRefused", "output resolution above the source does not create detail")
        return False
    if mode == "letterbox":
        fields(framing, "mode", "framing")
        require(Fraction(ow, src.width) <= 1 or Fraction(oh, src.height) <= 1, "upscaleRefused",
                "letterbox would upscale the source")
        return False
    fields(framing, "mode basis windows", "framing")
    require(grammar["reframe"] == "if-box-fits", "opNotAllowed", "this profile letterboxes instead of reframing")
    require(framing["basis"] == "reviewed-action-box", "reframeNotReviewed",
            "reframe windows come only from a reviewed action-safe box")
    windows = framing["windows"]
    require(type(windows) is list and 1 <= len(windows) <= 32, "badReframe", "1-32 reframe windows")
    prev = None
    tolerance = max(src.width * oh, src.height * ow)
    for w in windows:
        fields(w, "atFrame x y w h", "reframe window")
        at = integer(w["atFrame"], "atFrame")
        x, y = integer(w["x"], "x"), integer(w["y"], "y")
        cw, ch = integer(w["w"], "w", 1), integer(w["h"], "h", 1)
        require(x + cw <= FRAME_UNITS and y + ch <= FRAME_UNITS, "badReframe", "window leaves the source frame")
        require(abs(cw * src.width * oh - ch * src.height * ow) <= tolerance, "badReframe",
                "window aspect does not match the output aspect")
        require(oh * FRAME_UNITS <= MAX_REFRAME_UPSCALE * ch * src.height, "upscaleRefused",
                "reframe crop is upscaled more than 2x; letterbox instead")
        if prev is None:
            require(at == 0, "badReframe", "the first window starts at the segment's first frame")
        else:
            require(prev["atFrame"] < at < out_len, "badReframe", "reframe windows must be strictly increasing")
            step = at - prev["atFrame"]
            require(abs(x - prev["x"]) <= MAX_PAN_UNITS_PER_FRAME * step and
                    abs(y - prev["y"]) <= MAX_PAN_UNITS_PER_FRAME * step, "panTooFast", "reframe pans too fast")
        prev = w
    return any((w["x"], w["y"], w["w"], w["h"]) != (windows[0]["x"], windows[0]["y"], windows[0]["w"], windows[0]["h"])
               for w in windows)


def _resolve_note(ref, context, label) -> None:
    """Text on screen and narration scripts come only from stored notes in the trusted reference catalog."""
    stored = context["references"].get(ref)
    require(stored is not None, "untrustedReference", f"{label} {ref!r} is not a stored record")
    require(stored["kind"] == "note", "kindMismatch", f"{label} {ref!r} is a {stored['kind']}, not a note")


def _check_overlays(refs, bindings, grammar, sid, context) -> None:
    require(type(refs) is list and len(refs) <= MAX_OVERLAYS, "badOverlays", "at most 8 overlay refs")
    annotations = 0
    for ref in refs:
        fields(ref, "kind refId eventRevision provenance", "overlay")
        require(ref["kind"] in OVERLAY_KINDS, "overlayNotAllowed", "unsupported overlay kind")
        identifier(ref["refId"], "overlay refId")
        integer(ref["eventRevision"], "overlay eventRevision", 1)
        require(ref["eventRevision"] == bindings["eventRevision"], "staleRevision",
                f"segment {sid}: overlay bound to event revision {ref['eventRevision']}, plan uses "
                f"{bindings['eventRevision']}")
        require(ref["provenance"] in PROVENANCE, "badEnum", "invalid provenance")
        allowed = grammar["overlays"].get(ref["kind"])
        require(allowed is not None, "overlayNotAllowed", f"{ref['kind']} overlays are not used in this profile")
        require(ref["provenance"] in allowed, "provenanceNotAllowed",
                f"{ref['provenance']} {ref['kind']} overlays are not allowed in this profile")
        annotations += ref["kind"] == "annotation"
    require(annotations <= 1, "badOverlays", "at most one annotation at a time")
    for ref in refs:
        # an overlay is a reference to a stored record: it must resolve, and its kind and provenance are the stored
        # record's, never the plan's own claim (an estimated cue cannot be relabelled reviewed)
        stored = context["references"].get(ref["refId"])
        require(stored is not None, "untrustedReference",
                f"segment {sid}: overlay {ref['kind']} {ref['refId']!r} does not resolve to a stored record")
        require(stored["kind"] == ref["kind"], "kindMismatch",
                f"segment {sid}: {ref['refId']!r} is a stored {stored['kind']}, not a {ref['kind']}")
        require(stored["provenance"] == ref["provenance"], "provenanceMismatch",
                f"segment {sid}: {ref['refId']!r} is stored as {stored['provenance']}, the plan says {ref['provenance']}")
        require(stored["eventRevision"] == bindings["eventRevision"], "staleRevision",
                f"segment {sid}: {ref['refId']!r} was resolved at another event revision")


def _check_transition(tr, info, order, grammar, out_fps_raw, index, context) -> bool:
    fields(tr, "type frames", "transitionIn")
    kind = tr["type"]
    require(kind in ("cut", "dissolve", "dip"), "transitionNotAllowed", "transitions come from cut, dissolve, dip")
    n = integer(tr["frames"], "transition frames")
    if kind == "cut":
        require(n == 0, "badTransition", "a cut has 0 frames")
        return False
    require(index > 0, "badTransition", "the first segment starts with a cut")
    require(kind in grammar["transitions"], "transitionNotAllowed", f"{kind} is not allowed in this profile")
    require(n >= 2, "badTransition", "a dissolve or dip spans at least 2 frames")
    ms = Fraction(n * 1000) / fps_fraction(out_fps_raw)
    require(ms <= grammar["maxTransitionMs"], "transitionTooLong", f"{ms} ms exceeds {grammar['maxTransitionMs']} ms")
    prev = order[-1]
    h_out = n // 2               # output frames after the boundary that still show the outgoing source
    h_in = n - h_out             # output frames before the boundary that already show the incoming source
    require(prev["out"] - prev["in"] >= h_in and info["out"] - info["in"] >= h_out, "badTransition",
            "transition longer than an adjacent segment")
    for side, extra_before, extra_after, edge in ((prev, h_in, h_out, "s_out"), (info, h_in, h_out, "s_in")):
        if side["op"] not in MOVING_OPS:
            continue
        src = side["src"]
        k = src.fps * side["speed"] / fps_fraction(out_fps_raw)   # source frames per output frame
        lo = side[edge] - (Fraction(extra_before) * k).__ceil__()
        hi = side[edge] + (Fraction(extra_after) * k).__ceil__()
        require(lo >= 0 and src.interval(lo, hi) is side["cov"], "transitionHandle",
                f"transition needs source handles [{lo},{hi}) inside the same coverage (never across a gap)")
        for a, b in side.get("protected", []):
            require(hi <= a or b <= lo, "contactProtected",
                    "a transition may not touch a protected contact window")
        for c in context["contacts"].get(src.id, []):
            require(not lo <= c < hi, "contactProtected",
                    f"a transition may not blend the stored contact at frame {c} (live or replay)")
    return True


def _check_chapters(chapters, total) -> None:
    require(type(chapters) is list and len(chapters) <= 64, "badChapters", "chapters must be a list")
    prev = -1
    ids = set()
    for i, ch in enumerate(chapters):
        fields(ch, "id outputInFrame templateId", "chapter")
        identifier(ch["id"], "chapter id")
        require(ch["id"] not in ids, "duplicateId", "duplicate chapter id")
        ids.add(ch["id"])
        template(ch["templateId"], "chapter templateId", "chapter.")
        at = integer(ch["outputInFrame"], "chapter outputInFrame")
        require((i == 0 and at == 0) or (i > 0 and prev < at < total), "badChapters",
                "chapters start at frame 0 and strictly increase inside the film")
        prev = at


def _check_audio(audio, sources, order, total, out_fps, out_fps_raw, grammar, context) -> None:
    fields(audio, "primarySourceId bed narration music", "audio")
    bed = audio["bed"]
    require(type(bed) is list and 1 <= len(bed) <= 256, "bedCoverage", "the bed needs 1-256 pieces")
    all_silent = all(type(p) is dict and p.get("route") == "silence" for p in bed)
    primary = audio["primarySourceId"]
    if all_silent:
        require(primary is None, "primaryBedSource", "an all-silent plan names no primary audio source")
    else:
        identifier(primary, "primarySourceId")
        require(primary in sources and sources[primary].role == "match" and sources[primary].has_audio,
                "primaryBedSource", "the primary bed comes from a match source with audio")
    half = frame_duration_us(out_fps_raw) / 2
    cursor = 0
    pieces = []
    for p in bed:
        fields(p, "route sourceId sourceInFrame outputInFrame outputOutFrame fadeInMs fadeOutMs", "bed piece")
        route = p["route"]
        require(route in ("primary-bed", "alt-bed", "hold-bed", "silence"), "badEnum", "unknown audio route")
        o_in, o_out = integer(p["outputInFrame"], "bed outputInFrame"), integer(p["outputOutFrame"], "bed out", 1)
        require(o_in == cursor and o_in < o_out <= total, "bedCoverage",
                "exactly one bed route per output frame, contiguous from frame 0")
        cursor = o_out
        fin, fout = integer(p["fadeInMs"], "fadeInMs"), integer(p["fadeOutMs"], "fadeOutMs")
        require(fin <= 2000 and fout <= 2000, "badFade", "fades are at most 2000 ms")
        piece = {"route": route, "in": o_in, "out": o_out, "raw": p}
        if route == "silence":
            require(p["sourceId"] is None and p["sourceInFrame"] is None, "silenceBindsAudio",
                    "silence must not bind a source")
            require(fin >= 10 and fout >= 10, "fadeTooShort", "silence needs >= 10 ms fades")
            pieces.append(piece)
            continue
        src_id = identifier(p["sourceId"], "bed sourceId")
        require(src_id in sources and sources[src_id].has_audio, "bedSourceUnavailable", "bed source has no audio")
        src = sources[src_id]
        s_in = integer(p["sourceInFrame"], "bed sourceInFrame")
        n_src = Fraction(o_out - o_in) * src.fps / out_fps
        require(n_src.denominator == 1, "bedClock", "bed window is not a whole number of source frames")
        cov = src.interval(s_in, s_in + int(n_src))
        require(cov is not None, "outsideCoverage", "bed window leaves the source coverage or crosses a gap")
        piece.update(src=src, s_in=s_in, n=int(n_src), cov=cov)
        if route in ("primary-bed", "hold-bed"):
            require(src_id == primary, "primaryBedSource", f"{route} uses the designated primary source")
        if route == "alt-bed":
            require(src_id != primary, "badAltBed", "alt-bed switches to another source's audio")
            require(fin >= 20 and fout >= 20, "fadeTooShort", "alt-bed needs >= 20 ms fades")
        if route == "hold-bed":
            prev = pieces[-1] if pieces else None
            require(prev is not None and prev["route"] in ("primary-bed", "hold-bed") and prev["src"] is src
                    and prev["s_in"] + prev["n"] == s_in, "holdBedNotContinuous",
                    "hold-bed continues the primary bed without a jump")
        pieces.append(piece)
    require(cursor == total, "bedCoverage", "the bed must cover every output frame")
    _check_bed_switches(pieces, order, out_fps)

    lives = [o for o in order if o["op"] == "live"]
    for p in pieces:
        overlapping = [o for o in order if o["in"] < p["out"] and p["in"] < o["out"]]
        if p["route"] == "hold-bed":
            require(all(o["op"] != "live" for o in overlapping), "holdBedOverLive",
                    "hold-bed plays only under replays, freezes, cards or B-roll")
            b0 = p["src"].session_us(p["s_in"], p["cov"])
            b1 = p["src"].session_us(p["s_in"] + p["n"], p["cov"])
            require(b0 is not None and all(l["session"][1] <= b0 or b1 <= l["session"][0] for l in lives),
                    "holdBedNotDeadTime", "hold-bed must be real dead time that no live segment shows")
    if all_silent:
        return
    for live in lives:
        for p in pieces:
            lo, hi = max(live["in"], p["in"]), min(live["out"], p["out"])
            if lo >= hi:
                continue
            require(p["route"] in ("primary-bed", "alt-bed"), "liveWithoutCourtAudio",
                    "live play is under the primary (or a point-boundary alternate) court bed")
            for o in (lo, hi - 1):
                v = live["src"].session_us(live["s_in"] + Fraction(o - live["in"]) * live["src"].fps
                                           * live["speed"] / out_fps, live["cov"])
                a = p["src"].session_us(p["s_in"] + Fraction(o - p["in"]) * p["src"].fps / out_fps, p["cov"])
                require(a is not None and abs(v - a) <= half, "bedOutOfSync",
                        f"court audio is {None if a is None else float(a - v) / 1000:.3f} ms from the picture "
                        "(limit: half an output frame)")

    narration = audio["narration"]
    if narration is not None:
        fields(narration, "voice consent disclosureTemplateId duckDb scriptNoteIds windows", "narration")
        require(grammar["narration"], "opNotAllowed", "narration is not used in this profile")
        require(narration["voice"] in ("user-recorded", "generated"), "badEnum", "narration voice")
        fields(narration["consent"], "consentRecordId granted", "narration consent")
        identifier(narration["consent"]["consentRecordId"], "consentRecordId")
        require(narration["consent"]["granted"] is True, "consentMissing", "narration needs recorded consent")
        if narration["voice"] == "generated":
            require(narration["disclosureTemplateId"] == "label.narration-generated", "disclosureMissing",
                    "generated narration is labelled and disclosed")
        else:
            require(narration["disclosureTemplateId"] is None, "badNarration", "only generated narration is labelled")
        stored = context["consents"].get(narration["consent"]["consentRecordId"])
        need = "generated-voice" if narration["voice"] == "generated" else "narration-voice"
        require(stored is not None and stored["granted"] is True and need in stored["scope"], "consentMissing",
                f"narration needs a stored, granted {need} consent; a plan cannot attest its own consent")
        require(type(narration["duckDb"]) is int and -24 <= narration["duckDb"] <= -6, "badNarration",
                "court bed ducks by 6-24 dB under narration")
        require(type(narration["scriptNoteIds"]) is list and narration["scriptNoteIds"], "badNarration",
                "a narration script is grounded in stored notes")
        for nid in narration["scriptNoteIds"]:
            identifier(nid, "scriptNoteId")
            _resolve_note(nid, context, "narration scriptNoteId")
        _windows(narration["windows"], total, "narration")
    music = audio["music"]
    if music is not None:
        fields(music, "assetId rightsRecordId rightsScope windows", "music")
        require(grammar["music"], "opNotAllowed", "music is not used in this profile")
        identifier(music["assetId"], "music assetId")
        identifier(music["rightsRecordId"], "rightsRecordId")
        require(type(music["rightsScope"]) is list and all(type(x) is str for x in music["rightsScope"])
                and "private-film" in music["rightsScope"], "rightsMissing",
                "music needs rights for at least the private film")
        stored = context["rights"].get(music["rightsRecordId"])
        require(stored is not None and stored["assetId"] == music["assetId"]
                and set(music["rightsScope"]) <= set(stored["scope"]), "rightsMissing",
                "music needs a stored rights record for this asset covering every claimed scope; a plan cannot "
                "attest its own rights")
        _windows(music["windows"], total, "music")


def _check_bed_switches(pieces, order, out_fps) -> None:
    """Every change of bed source (another source, or to or from silence) sits on a segment boundary, never inside a
    segment. At a cut, each sounding side fades for at least 20 ms (silence keeps its own 10 ms minimum). At a dissolve
    or dip, the switch becomes an audio dip across the picture transition: the outgoing bed has faded out by the
    boundary over at least the frames before it that already show the incoming picture, and the incoming bed fades in
    over at least the frames after it, so two sources' court audio never play at once and nothing switches hard in
    the middle of a blend. The same source continuing (primary to hold-bed, or primary to primary at a cut between
    live segments) is not a switch."""
    starts = {o["in"]: o for o in order}
    for a, b in zip(pieces, pieces[1:]):
        src_a = None if a["route"] == "silence" else a["raw"]["sourceId"]
        src_b = None if b["route"] == "silence" else b["raw"]["sourceId"]
        if src_a == src_b:
            continue
        seg = starts.get(b["in"])
        require(seg is not None, "bedSwitchNotAtBoundary",
                f"the bed changes source at output frame {b['in']}, inside a segment; switch only at a boundary")
        tr = seg["seg"]["transitionIn"]
        if tr["type"] == "cut":
            need_out = 20 if src_a is not None else 0
            need_in = 20 if src_b is not None else 0
        else:
            h_out = tr["frames"] // 2
            h_in = tr["frames"] - h_out
            need_out = (Fraction(h_in * 1000) / out_fps).__ceil__()
            need_in = (Fraction(h_out * 1000) / out_fps).__ceil__()
        require(a["raw"]["fadeOutMs"] >= need_out and b["raw"]["fadeInMs"] >= need_in, "fadeTooShort",
                f"bed switch at output frame {b['in']} ({tr['type']}) needs fades of at least {need_out} ms out and "
                f"{need_in} ms in")


def _windows(windows, total, label) -> None:
    require(type(windows) is list and 1 <= len(windows) <= 64, "badWindows", f"{label} needs 1-64 windows")
    prev = 0
    for w in windows:
        fields(w, "outputInFrame outputOutFrame", f"{label} window")
        a, b = integer(w["outputInFrame"], "window in"), integer(w["outputOutFrame"], "window out", 1)
        require(prev <= a < b <= total, "badWindows", f"{label} windows must be ordered and inside the film")
        prev = b


# ----- clean alternate ----------------------------------------------------------------------------

def clean_alternate(plan: dict) -> dict:
    """The Reduce Motion / clean version: the same cut list, cuts instead of dissolves and dips, and a moving
    reframe replaced by letterbox. Pure function; the result must validate on its own."""
    alt = copy.deepcopy(plan)
    alt["cleanAlternate"] = True
    alt["planId"] = (plan["planId"] + "-clean")[:64]
    for seg in alt["segments"]:
        seg["transitionIn"] = {"type": "cut", "frames": 0}
        framing = seg.get("framing")
        if framing and framing["mode"] == "reframe":
            first = framing["windows"][0]
            moving = any((w["x"], w["y"], w["w"], w["h"]) != (first["x"], first["y"], first["w"], first["h"])
                         for w in framing["windows"])
            if moving:
                seg["framing"] = {"mode": "letterbox"}
    return alt
