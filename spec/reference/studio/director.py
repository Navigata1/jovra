"""StoryDirector: the StoryBrief for one profile and the player's options, the card text catalog, and the grammar lint.

Standard library only. The profiles and their machine grammar come from spec/studio/contracts/story-profiles.v1.json
(`load_profiles`). A planning context is plain data the app assembles from its stores (spec/studio/modules/planner.md
lists every field); nothing here reads media. Module page: spec/studio/modules/planner.md.

brief(profiles, context, profileId, options) -> {"brief": StoryBrief header, "directions": {...}} | {"refusal": {...}}
    The jovra.story-brief/1 header (beats, comparisons, omitted and unresolved still empty) plus the planner
    directions the contract does not carry. Lengths: 3 min = 180 s, 5 min = 300 s, Full = the profile maximum bounded
    by the recorded coverage. A length outside the profile's range or the recording is a refusal with the ST29 copy,
    and a context with no keepers is the refusal "Mark a few moments first".

lint(profiles, plan, context) -> [finding]
    The machine-checkable (bold) grammar rules of film-engine section 6 for a brief or a planned StoryPlan. Every
    finding has code grammarViolation and a rule id; an empty list passes.
"""

from __future__ import annotations

import json
from fractions import Fraction
from pathlib import Path

from studio.core import Reject, require, round_half_up

PROFILES_PATH = "spec/studio/contracts/story-profiles.v1.json"
LENGTHS = {"3min": 180, "5min": 300}
LENGTH_KEYS = ("3min", "5min", "full")
OPTION_KEYS = ("length", "aspect", "effects", "shake", "keepFullRallies", "caption", "dedication", "venueVisible",
               "blurBystanders", "audience", "music", "narration")
ASPECTS = ("16:9", "9:16")
EFFECTS = {"subtle": "low", "medium": "medium"}
AUDIENCES = ("self", "coach", "family", "private-share")
FEELING = {"coach-cut": "feeling.next-action", "match-broadcast": "feeling.relive-match",
           "rally-pulse": "feeling.worth-keeping", "progress-story": "feeling.growing-game",
           "court-memories": "feeling.day-mattered"}
DEFAULT_AUDIENCE = {"court-memories": "family"}
CLEAN_ALTERNATE = ("rally-pulse", "court-memories")       # motion-forward profiles render a Reduce Motion version
EFFECT_OPTION_PROFILES = ("rally-pulse",)                 # only Rally Pulse offers an effects choice (ST29-ST33)
WIDE_ANGLE_PROFILES = ("match-broadcast",)                # live play stays on the selected wide angle
PLANNER = {"kind": "heuristic", "modelId": None, "adapterVersion": "jovra-planner@0.1.0"}
NO_KEEPERS = "Mark a few moments first"
AT_LEAST_REVIEWED = ("reviewed", "validated")

# The card text catalog (story 157): the planner picks a template id and at most one stored note; code fills every
# other slot from stored data. `note` is the use the note must have, or None when the card takes no note.
CARD_TEMPLATES = {
    "card.goal": {"profiles": ["coach-cut", "progress-story"], "note": "goal", "slots": ["note", "date"]},
    "card.examples": {"profiles": ["coach-cut"], "note": None, "slots": [], "text": "Your examples"},
    "card.drill": {"profiles": ["coach-cut"], "note": "drill", "slots": ["note"]},
    "card.next-checkpoint": {"profiles": ["coach-cut"], "note": "next", "slots": ["note"]},
    "card.match-intro": {"profiles": ["match-broadcast"], "note": "players", "slots": ["note", "date", "format"]},
    "card.final-score": {"profiles": ["match-broadcast"], "note": None, "slots": ["score"]},
    "card.accent": {"profiles": ["rally-pulse"], "note": None, "slots": ["date"]},
    "card.lesson": {"profiles": ["progress-story"], "note": "lesson", "slots": ["note", "date"]},
    "card.what-changed": {"profiles": ["progress-story"], "note": None, "slots": ["comparison"]},
    "card.method-change": {"profiles": ["progress-story"], "note": None, "slots": ["dates"],
                           "text": "These sessions were counted differently, so they are not compared."},
    "card.not-compared": {"profiles": ["progress-story"], "note": None, "slots": ["dates", "reason"]},
    "card.next-goal": {"profiles": ["progress-story"], "note": "next", "slots": ["note"]},
    "card.date": {"profiles": ["court-memories"], "note": None, "slots": ["date"]},
    "card.dedication": {"profiles": ["court-memories"], "note": "dedication", "slots": ["note"]},
}
INSTRUCTION_TEMPLATES = ("card.drill", "card.next-checkpoint")   # Coach's Cut cards that instruct


def load_profiles(root) -> dict:
    doc = json.loads((Path(root) / PROFILES_PATH).read_text(encoding="utf-8"))
    return {p["id"]: p for p in doc["profiles"]}


# ----- copy helpers -----------------------------------------------------------------------------------------------

def length_label(seconds: int) -> str:
    """180 -> '3 min', 200 -> '3 min 20 s'."""
    m, s = divmod(seconds, 60)
    return f"{m} min" if s == 0 else f"{m} min {s} s"


def estimate_label(ms: int) -> str:
    """An estimate in whole seconds, rounded half up: 184500 -> '3 min 5 s'."""
    return length_label(round_half_up(Fraction(ms, 1000)))


def _profile(profiles: dict, profile_id) -> dict:
    require(profile_id in profiles, "unknownProfile", f"profile {profile_id!r}")
    return profiles[profile_id]


# ----- options ----------------------------------------------------------------------------------------------------

def _note(context: dict, note_id, use: str, what: str):
    if note_id is None:
        return None
    note = next((n for n in context["notes"] if n["noteId"] == note_id), None)
    require(note is not None and note["use"] == use, "untrustedReference", f"{what} {note_id!r} is not a stored {use} note")
    return note_id


def _bool(options: dict, key: str, default: bool) -> bool:
    value = options.get(key, default)
    require(type(value) is bool, "badOptions", f"{key} must be true or false")
    return value


def resolve_options(profile: dict, context: dict, options: dict) -> dict:
    """The player's choices, checked against the profile; a choice the profile does not offer is refused."""
    require(isinstance(options, dict), "badOptions", "options must be an object")
    extra = sorted(set(options) - set(OPTION_KEYS))
    require(not extra, "unknownField", f"unknown option(s) {extra}")
    pid, g = profile["id"], profile["grammar"]
    aspect = options.get("aspect", "16:9")
    require(aspect in ASPECTS, "badOptions", f"aspect {aspect!r}")
    effects = options.get("effects", "subtle")
    require(effects in ("subtle", "medium", "high"), "badOptions", f"effects {effects!r}")
    require(effects == "subtle" or pid in EFFECT_OPTION_PROFILES, "optionUnavailable",
            f"{profile['name']} has no effects choice")
    require(effects != "high", "optionUnavailable", "High effects are not available yet")
    require(not _bool(options, "shake", False), "optionUnavailable", "shake stays off in this version")
    require(_bool(options, "keepFullRallies", True), "optionUnavailable", "rallies are always kept whole")
    audience = options.get("audience", DEFAULT_AUDIENCE.get(pid, "self"))
    require(audience in AUDIENCES, "badOptions", f"audience {audience!r}")
    length = options.get("length")
    require(length is None or length in LENGTH_KEYS, "badOptions", f"length {length!r}")
    music = options.get("music")
    music_doc, music_unavailable = None, None
    if music is not None:
        require(isinstance(music, dict) and set(music) == {"assetId"}, "badOptions", "music is {assetId}")
        require(g["music"], "optionUnavailable", f"{profile['name']} uses court sound only")
        rights = next((r for r in context["rights"] if r["assetId"] == music["assetId"]), None)
        if rights is None:
            music_unavailable = music["assetId"]   # never played without a rights record: court sound instead
        else:
            music_doc = {"assetId": music["assetId"], "rightsRecordId": rights["rightsRecordId"]}
    narration = options.get("narration")
    if narration is not None:
        require(isinstance(narration, dict) and set(narration) == {"voice", "consentRecordId"}
                and narration["voice"] in ("user-recorded", "generated"), "badOptions", "narration is {voice, consentRecordId}")
        require(g["narration"], "optionUnavailable", f"{profile['name']} has no narration")
        consent = next((c for c in context["consents"] if c["consentRecordId"] == narration["consentRecordId"]), None)
        require(consent is not None and consent["granted"] and "narration-voice" in consent["scope"], "noConsent",
                "narration needs a granted voice consent")
        narration = {"voice": narration["voice"], "consentRecordId": narration["consentRecordId"]}
    return {"length": length, "aspect": aspect, "effectIntensity": EFFECTS[effects], "audience": audience,
            "caption": _note(context, options.get("caption"), "caption", "caption"),
            "dedication": _note(context, options.get("dedication"), "dedication", "dedication"),
            "venueVisible": _bool(options, "venueVisible", False),
            "blurBystanders": _bool(options, "blurBystanders", False),
            "music": music_doc, "musicUnavailable": music_unavailable, "narration": narration}


def _length_refusal(profile: dict, seconds: int, coverage: int):
    """None when `seconds` is a length this profile and this recording allow, else the refusal copy (ST29)."""
    lo, hi = profile["grammar"]["durationSeconds"]["min"], profile["grammar"]["durationSeconds"]["max"]
    if seconds < lo:
        return f"{profile['name']} needs at least {length_label(lo)}."
    if seconds > hi:
        return f"{profile['name']} films are up to {length_label(hi)}."
    if seconds > coverage:
        return f"The recording is shorter than {length_label(seconds)}."
    return None


def target_seconds(profile: dict, length: str, coverage: int):
    """(seconds, None) or (None, refusal message) for 3min, 5min or full."""
    hi = profile["grammar"]["durationSeconds"]["max"]
    seconds = min(hi, coverage) if length == "full" else LENGTHS[length]
    refusal = _length_refusal(profile, seconds, coverage)
    return (None, refusal) if refusal else (seconds, None)


def default_length(profile: dict, coverage: int) -> str:
    """5 min when the profile allows it (ST29), else 3 min, else Full."""
    for key in ("5min", "3min"):
        if target_seconds(profile, key, coverage)[1] is None:
            return key
    return "full"


# ----- brief ------------------------------------------------------------------------------------------------------

def brief(profiles: dict, context: dict, profile_id: str, options: dict) -> dict:
    profile = _profile(profiles, profile_id)
    opts = resolve_options(profile, context, options)
    if not context["keepers"]:
        return {"refusal": {"code": "noKeepers", "message": NO_KEEPERS}}
    coverage = context["coverageSeconds"]
    length = opts["length"] or default_length(profile, coverage)
    seconds, refusal = target_seconds(profile, length, coverage)
    if refusal:
        return {"refusal": {"code": "lengthUnavailable", "message": refusal}}
    silent = context["juniorMode"] or not context["primaryHasAudio"]
    header = {
        "schemaVersion": "jovra.story-brief/1", "briefId": f"brief-{profile_id}-{length}",
        "projectId": context["projectId"], "revision": 1, "sample": context["sample"],
        "profile": {"id": profile_id, "revision": profile["revision"]}, "bindings": dict(context["bindings"]),
        "planner": dict(PLANNER), "feelingKey": FEELING[profile_id], "audience": opts["audience"],
        "durationTargetSeconds": seconds, "aspect": opts["aspect"],
        "primaryAudioPolicy": "no-audio" if silent else "continuous-primary-court-audio",
        "effectIntensity": opts["effectIntensity"], "cleanAlternate": profile_id in CLEAN_ALTERNATE,
        "privacy": {"venueVisible": opts["venueVisible"], "faces": "blur-bystanders" if opts["blurBystanders"] else "show"},
        "music": opts["music"], "narration": opts["narration"],
        "beats": [], "comparisons": [], "omitted": [], "unresolved": [],
    }
    directions = {"length": length, "framing": "letterbox" if opts["aspect"] == "9:16" else "fill",
                  "shake": False, "keepFullRallies": True, "caption": opts["caption"],
                  "dedication": opts["dedication"], "musicUnavailable": opts["musicUnavailable"]}
    return {"brief": header, "directions": directions}


# ----- grammar lint -----------------------------------------------------------------------------------------------

def lint(profiles: dict, plan: dict, context: dict) -> list:
    """Bold grammar rules for the plan's profile. Ids that do not resolve are planner.check's concern (it rejects them
    first); the lint skips them rather than guess."""
    pid = plan["profile"]["id"]
    profile = _profile(profiles, pid)
    g = profile["grammar"]
    refs = {r["refId"]: r for r in context["references"]}
    keepers = {k["keeperId"]: k for k in context["keepers"]}
    brolls = {b["brollId"]: b for b in context["brolls"]}
    found = []

    def hit(rule, beat=None):
        found.append({"code": "grammarViolation", "rule": rule, "beatId": beat["beatId"] if beat else None})

    if not g["durationSeconds"]["min"] <= plan["durationTargetSeconds"] <= g["durationSeconds"]["max"]:
        hit("duration-range")
    if plan["effectIntensity"] != "low" and pid not in EFFECT_OPTION_PROFILES:
        hit("effect-intensity")
    music = plan["music"]
    if music is not None and not (g["music"] and any(r["rightsRecordId"] == music["rightsRecordId"]
                                                     and r["assetId"] == music["assetId"] for r in context["rights"])):
        hit("music")
    narration = plan["narration"]
    if narration is not None and not (g["narration"] and any(
            c["consentRecordId"] == narration["consentRecordId"] and c["granted"] and "narration-voice" in c["scope"]
            for c in context["consents"])):
        hit("narration")
    strict = g["chronology"] == "strict"
    live_seen: set = set()
    last_start = None
    previous = None
    reviewed_cue = any(o["kind"] == "cue" and refs.get(o["refId"], {}).get("provenance") in AT_LEAST_REVIEWED
                       for b in plan["beats"] for o in b["overlays"])
    for beat in plan["beats"]:
        t, kid = beat["treatment"], beat["keeperId"]
        if t not in g["ops"]:
            hit("op-not-in-profile", beat)
        if t == "replay":
            if beat["replaySpeedDen"] not in g["replaySpeedDens"]:
                hit("replay-speed", beat)
            if kid not in live_seen:
                hit("replay-before-live", beat)
            if strict and not (previous and previous["keeperId"] == kid and previous["treatment"] in ("live", "replay")):
                hit("strict-chronology", beat)   # a replay ends before the next point's serve
        elif beat["replaySpeedDen"] is not None:
            hit("replay-speed", beat)
        if t == "live" and kid in keepers:
            if kid in live_seen:
                hit("one-live-showing", beat)
            live_seen.add(kid)
            start = keepers[kid]["session"]["startUs"]
            if strict and last_start is not None and start < last_start:
                hit("strict-chronology", beat)
            last_start = start if last_start is None else max(last_start, start)
            if pid in WIDE_ANGLE_PROFILES and beat["angle"] not in (None, keepers[kid]["slots"][0]):
                hit("wide-angle-only", beat)
        for o in beat["overlays"]:
            ref = refs.get(o["refId"])
            if ref is not None and ref["provenance"] not in g["overlays"].get(o["kind"], []):
                hit("overlay-not-allowed", beat)
        if t == "title-card":
            tmpl = CARD_TEMPLATES.get(beat["templateId"])
            if tmpl is not None and pid not in tmpl["profiles"]:
                hit("card-template", beat)
            if beat["templateId"] == "card.final-score" and not context["pointCoverageComplete"]:
                hit("final-score-incomplete", beat)
            if pid == "coach-cut" and beat["templateId"] in INSTRUCTION_TEMPLATES and not reviewed_cue:
                hit("instruction-without-cue", beat)
        if t == "broll" and beat["brollId"] in brolls:
            b = brolls[beat["brollId"]]
            if not b["depictsThisMatch"]:
                hit("broll-not-this-match", beat)
            if b["revealsLocation"] and not plan["privacy"]["venueVisible"]:
                hit("hidden-location", beat)
        previous = beat
    for c in plan["comparisons"]:
        shown = " ".join(c["display"].values()).lower()
        if "improv" in shown or "%" in c["display"]["delta"]:
            hit("comparison-claim")
        elif c["claim"] == "change" and not (c["before"]["provenance"] in AT_LEAST_REVIEWED
                                             and c["after"]["provenance"] in AT_LEAST_REVIEWED):
            hit("comparison-claim")
    return found


# ----- vectors ----------------------------------------------------------------------------------------------------

def run_vector(profiles: dict, case: dict) -> dict:
    """A director vector case (op brief, lint or templates) -> its result, or {"rejectCode": code}."""
    inp = case["input"]
    try:
        if case["op"] == "brief":
            return brief(profiles, inp["context"], inp["profileId"], inp["options"])
        if case["op"] == "lint":
            return {"findings": lint(profiles, inp["plan"], inp["context"])}
        if case["op"] == "templates":
            return {"templates": CARD_TEMPLATES, "instructionTemplates": list(INSTRUCTION_TEMPLATES)}
        raise Reject("badOp", f"op {case['op']!r}")
    except Reject as exc:
        return {"rejectCode": exc.code}
