"""RulesPlanner (contract planner kind `heuristic`): a deterministic StoryPlan from a director brief and the context.

Standard library only. The StoryPlan is the jovra.story-brief/1 document with its beats, comparisons, omitted ideas and
unresolved notes filled in. Beats are made only of keeper, B-roll, note, overlay and card-template ids from the context
and the director's card catalog; no beat carries text that reaches the picture (story 157). Compilation to an EDL is
the compiler's job (S07). Module page: spec/studio/modules/planner.md.

plan(profiles, briefed, context) -> {"plan", "estimate", "fallback", "belowMinimum"} | {"refusal": {...}}
    `briefed` is director.brief's output. The keeper ranking (keepers.rank) chooses the evidence; each profile's
    structure and documented fallback place it; a duration estimate fills toward the brief's target without padding.

check(profiles, plan, context) -> {"beats": n}
    The trust check every plan passes before compile, whichever planner wrote it: strict fields (unknownField,
    missingField), ids that resolve in the context (untrustedReference), card templates with typed slots
    (badTemplateSlot), treatment/field agreement (treatmentMismatch), project and revision bindings.
"""

from __future__ import annotations

from studio import director, progress
from studio import keepers as keeper_rules
from studio.core import Reject, require
from studio.edl import fields

BRIEF_FIELDS = ("schemaVersion briefId projectId revision sample profile bindings planner feelingKey audience "
                "durationTargetSeconds aspect primaryAudioPolicy effectIntensity cleanAlternate privacy music "
                "narration beats comparisons omitted unresolved")
BEAT_FIELDS = "beatId role treatment keeperId brollId angle replaySpeedDen overlays noteId templateId reasonForReview"
KEEPER_TREATMENTS = ("live", "replay", "freeze")
CARD_MS = 4000          # a card's proposed hold, clamped to the profile's cardMs range
FREEZE_MS = 2000        # a freeze's proposed hold, clamped to the profile's freezeMs range
BROLL_MAX_MS = 6000     # Court Memories B-roll shots run 2-6 s (film-engine 6.5)
MAX_EXAMPLES = 3        # Coach's Cut shows two or three examples (film-engine 6.1)
REASON_TEXT = {
    "statDefinitionChange": "The two sessions count different stats, so they are not compared.",
    "methodChange": "The two sessions were counted differently, so they are not compared.",
    "sessionKindChange": "One session is a match and one is a practice, so they are not compared.",
    "differingSelection": "The examples were chosen differently, so they are not compared.",
    "notReviewed": "One side is not reviewed yet, so they are not compared.",
    "emptySample": "One session has nothing counted, so they are not compared.",
}
MISSING_TEXT = {
    "arrival-broll": ("Arrival footage", "No B-roll is marked for the arrival."),
    "after-broll": ("After the match", "No B-roll is marked for after the match."),
    "match-moments": ("Match moments", "No marked, lesson-linked or pressure point is kept."),
}


# ----- plan building helpers --------------------------------------------------------------------------------------

class Draft:
    """Everything one profile proposes: groups of beats (each atomic), omitted ideas and header changes."""

    def __init__(self, profile: dict, context: dict, briefed: dict):
        self.profile = profile
        self.g = profile["grammar"]
        self.context = context
        self.directions = briefed["directions"]
        self.brief = briefed["brief"]
        self.keepers = {k["keeperId"]: k for k in context["keepers"]}
        self.refs = {r["refId"]: r for r in context["references"]}
        self.notes = {n["noteId"]: n for n in context["notes"]}
        self.groups: list = []
        self.omitted: list = []
        self.comparisons: list = []
        self.fallback = None
        self.header: dict = {}
        self.finalize = None

    # durations (ms): the planner's estimate; the compiler binds exact frames
    def live_ms(self, kid: str) -> int:
        s = self.keepers[kid]["session"]
        return (s["endUs"] - s["startUs"]) // 1000

    def ms(self, beat: dict) -> int:
        t = beat["treatment"]
        if t == "live":
            return self.live_ms(beat["keeperId"])
        if t == "replay":
            return min(self.g["replayMaxMs"], self.live_ms(beat["keeperId"]) * beat["replaySpeedDen"])
        if t == "freeze":
            return min(max(FREEZE_MS, self.g["freezeMs"]["min"]), self.g["freezeMs"]["max"])
        if t == "title-card":
            return min(max(CARD_MS, self.g["cardMs"]["min"]), self.g["cardMs"]["max"])
        broll = next(b for b in self.context["brolls"] if b["brollId"] == beat["brollId"])
        return min(broll["durationMs"], BROLL_MAX_MS)

    def allowed(self, kind: str, ref_id: str) -> bool:
        ref = self.refs.get(ref_id)
        return ref is not None and ref["kind"] == kind and ref["provenance"] in self.g["overlays"].get(kind, [])

    def scores(self, kid: str) -> list:
        return [{"kind": "score", "refId": e} for e in self.keepers[kid]["eventRefs"] if self.allowed("score", e)]

    def note(self, use: str):
        """The first stored note with this use (notes keep context order), or None."""
        return next((n["noteId"] for n in self.context["notes"] if n["use"] == use), None)

    def primary(self, kid: str) -> str:
        return self.keepers[kid]["slots"][0]

    def add(self, key: tuple, required: bool, *beats) -> None:
        self.groups.append({"key": key, "required": required, "beats": list(beats),
                            "ms": sum(self.ms(b) for b in beats)})

    def omit(self, idea: str, missing: str) -> None:
        self.omitted.append({"idea": idea, "missingEvidence": missing})


def beat(role, treatment, reason, keeper=None, broll=None, angle=None, den=None, overlays=(), note=None, template=None):
    return {"beatId": None, "role": role, "treatment": treatment, "keeperId": keeper, "brollId": broll,
            "angle": angle, "replaySpeedDen": den, "overlays": [dict(o) for o in overlays], "noteId": note,
            "templateId": template, "reasonForReview": reason}


def card(role, template, reason, note=None, overlays=()):
    return beat(role, "title-card", reason, note=note, template=template, overlays=overlays)


def _ranked(d: Draft, options: dict) -> list:
    got = keeper_rules.rank(d.profile["id"], d.context["keepers"], options)
    return got


# ----- the five profiles ------------------------------------------------------------------------------------------

def _coach_cut(d: Draft) -> None:
    cues = [{"cueId": c["cueId"], "keeperId": c["keeperId"], "provenance": c["provenance"]}
            for c in d.context["cues"] if c["keeperId"] in d.keepers]
    reviewed = {}
    for c in sorted(cues, key=lambda c: c["cueId"]):
        if c["provenance"] in director.AT_LEAST_REVIEWED and d.allowed("cue", c["cueId"]):
            reviewed.setdefault(c["keeperId"], c["cueId"])
    order = [i["id"] for i in _ranked(d, {"cues": cues})["order"]]
    chosen = sorted((k for k in d.context["keepers"] if k["selection"] == "manual" and k["keeperId"] not in order),
                    key=lambda k: (k["session"]["startUs"], k["keeperId"]))
    examples = (order + [k["keeperId"] for k in chosen])[:MAX_EXAMPLES]
    if reviewed:
        goal = d.note("goal")
        if goal:
            d.add((0,), True, card("goal", "card.goal", "The player's goal note opens the film.", note=goal))
        else:
            d.omit("Goal card", "No goal note is stored.")
    else:
        d.fallback = "your-examples"
        d.add((0,), True, card("context", "card.examples",
                               "No reviewed cue: the film shows your examples and gives no instruction."))
    den = d.g["replaySpeedDens"][0]
    for i, kid in enumerate(examples):
        angle = d.primary(kid)
        cue = reviewed.get(kid)
        beats = [beat("example", "live", f"{kid} at original speed" + (f"; reviewed cue {cue}." if cue else "."),
                      keeper=kid, angle=angle, overlays=d.scores(kid))]
        if cue:
            notes = sorted(a["refId"] for a in d.context["annotations"]
                           if a["keeperId"] == kid and d.allowed("annotation", a["refId"]))
            if notes:
                beats.append(beat("cue", "freeze", f"Paused on {kid} with annotation {notes[0]} and cue {cue}.",
                                  keeper=kid, angle=angle,
                                  overlays=[{"kind": "annotation", "refId": notes[0]}, {"kind": "cue", "refId": cue}]))
                replay_overlays = []
            else:
                replay_overlays = [{"kind": "cue", "refId": cue}]
            beats.append(beat("replay", "replay", f"Labelled replay of {kid} at 1/{den} speed.", keeper=kid,
                              angle=angle, den=den, overlays=replay_overlays))
        d.add((1, i), i == 0, *beats)
    if not examples:
        return
    if reviewed:
        for n, (use, template, idea, role) in enumerate((("drill", "card.drill", "Practice drill", "drill"),
                                                         ("next", "card.next-checkpoint", "Next checkpoint",
                                                          "checkpoint"))):
            note = d.note(use)
            if note:
                d.add((2, n), True, card(role, template, f"The player's {idea.lower()} note.", note=note))
            else:
                d.omit(idea, f"No {idea.lower()} note is stored.")
    else:
        d.omit("Reviewed cue", "No reviewed cue links to these keepers.")
        d.omit("Practice drill and next checkpoint", "Without a reviewed cue the film gives no instruction.")


def _match_broadcast(d: Draft) -> None:
    players = d.note("players")
    if players:
        d.add((0,), True, card("intro", "card.match-intro", "Players as entered open the match.", note=players))
    else:
        d.omit("Match introduction", "No players note is stored.")
    order = [i["id"] for i in _ranked(d, {})["order"]]
    den = d.g["replaySpeedDens"][0]
    replays = []
    for i, kid in enumerate(order):
        d.add((1, i, 0), True, beat("point", "live", f"{kid} in match order.", keeper=kid, angle=d.primary(kid),
                                     overlays=d.scores(kid)))
        slots = d.keepers[kid]["slots"]
        if len(slots) > 1:
            replays.append(((1, i, 1), beat("replay", "replay", f"Replay of {kid} from the {slots[1]} angle after "
                                            "the point.", keeper=kid, angle=slots[1], den=den)))
    for key, b in replays:
        d.add(key, False, b)
    if order and not replays:
        d.fallback = "one-angle-match"
        d.omit("Replays from another angle", "No second camera covers these points.")
    if d.context["pointCoverageComplete"]:
        d.add((2,), True, card("final-score", "card.final-score", "Every point is recorded, so the final score shows."))
    else:
        d.omit("Final score", "The recorded points do not cover the whole match.")


def _rally_pulse(d: Draft) -> None:
    order = [i["id"] for i in _ranked(d, {})["order"]]
    if d.directions["musicUnavailable"]:
        d.fallback = "court-sound-highlights"
        d.header["effectIntensity"] = "low"
        d.omit("Licensed music", f"No rights record for {d.directions['musicUnavailable']}.")
    if not order:
        return

    def rally(kid):
        return beat("build", "live", f"{kid}: a whole rally.", keeper=kid, angle=d.primary(kid),
                    overlays=d.scores(kid))

    d.add((0, d.keepers[order[0]]["session"]["startUs"], order[0]), True, rally(order[0]))
    d.add((1,), False, card("close", "card.accent", "A quiet static close on court sound."))
    for kid in order[1:]:
        d.add((0, d.keepers[kid]["session"]["startUs"], kid), False, rally(kid))
    top = order[0]

    def roles(beats):
        rallies = [b for b in beats if b["treatment"] == "live"]
        for n, b in enumerate(rallies):
            if n == 0:
                b["role"] = "opening"
            elif n == len(rallies) - 1:
                b["role"] = "payoff"
            elif b["keeperId"] == top:
                b["role"] = "key-exchange"
    d.finalize = roles


def _comparison(p: dict, got: dict) -> dict:
    def side(scope):
        return {"date": scope["date"], "sessionIds": list(scope["sessionIds"]), "numerator": scope["numerator"],
                "denominator": scope["denominator"], "provenance": scope["provenance"]}
    return {"comparisonId": f"cmp-{p['statDefinitionId']}", "statId": p["statId"],
            "metricDefinitionId": p["statDefinitionId"], "methodId": p["earlier"]["methodId"],
            "selectionRule": p["earlier"]["selectionRule"], "claim": "change",
            "before": side(p["earlier"]), "after": side(p["later"]),
            "display": {"before": got["earlier"]["display"], "after": got["later"]["display"],
                        "delta": got["deltaDisplay"]}}


def _progress_story(d: Draft) -> None:
    p = d.context["progress"]
    got = progress.compare(p["statDefinitionId"], p["earlier"], p["later"]) if p else None
    comparable = bool(got and got["comparable"])
    options = {"dates": p["dates"] if p else {}, "selectionRule": p["selectionRule"] if p else "all",
               "comparable": comparable}
    for key in ("chosen", "seed", "count"):
        if p and key in p:
            options[key] = p[key]
    order = [i["id"] for i in _ranked(d, options)["order"]]
    dates = options["dates"]
    goal, nxt = d.note("goal"), d.note("next")
    if goal:
        d.add((0,), True, card("goal", "card.goal", "The dated starting goal.", note=goal))
    else:
        d.omit("Starting goal", "No goal note is stored.")
    lessons = []
    for lesson in sorted(d.context["lessons"], key=lambda x: (x["date"], x["lessonId"])):
        note = next((n for n in lesson["noteIds"] if n in d.notes and d.notes[n]["use"] == "lesson"), None)
        if note:
            lessons.append((lesson, note))
    metric = [{"kind": "metric", "refId": p["statId"]}] if p and d.allowed("metric", p["statId"]) else []

    def lesson_card(lesson, note):
        return card("lesson", "card.lesson", f"Lesson of {lesson['date']}.", note=note)

    if comparable and order:
        early, recent = order[0], order[-1]
        d.add((1,), True, beat("early-evidence", "live", f"Earliest dated example ({dates[early]}).", keeper=early,
                               angle=d.primary(early), overlays=metric))
        if recent != early:
            d.add((3, 0), True, beat("recent-evidence", "live", f"Latest dated example ({dates[recent]}).",
                                     keeper=recent, angle=d.primary(recent)))
        d.add((4,), True, card("what-changed", "card.what-changed", "The stored before and after comparison.",
                               overlays=metric))
        if nxt:
            d.add((5,), True, card("next-goal", "card.next-goal", "The next practice goal.", note=nxt))
        for lesson, note in lessons:
            if dates[early] <= lesson["date"] <= dates[recent]:
                d.add((2, lesson["date"], lesson["lessonId"]), False, lesson_card(lesson, note))
        den = d.g["replaySpeedDens"][0]
        d.add((3, 1), False, beat("replay", "replay", f"Labelled replay of {recent} at 1/{den} speed.",
                                  keeper=recent, angle=d.primary(recent), den=den))
        d.comparisons.append(_comparison(p, got))
    else:
        d.fallback = "lesson-chronology"
        for n, kid in enumerate(order):
            d.add((1, dates[kid], 0, kid), True, beat("early-evidence" if n == 0 else "recent-evidence", "live",
                                                      f"Dated example ({dates[kid]}).", keeper=kid,
                                                      angle=d.primary(kid)))
        for lesson, note in lessons:
            d.add((1, lesson["date"], 1, lesson["lessonId"]), True, lesson_card(lesson, note))
        if got:
            template = "card.method-change" if "methodChange" in got["reasons"] else "card.not-compared"
            d.add((4,), True, card("what-changed", template, REASON_TEXT[got["reasons"][0]]))
            d.omit("Before and after comparison", REASON_TEXT[got["reasons"][0]])
        else:
            d.omit("Before and after comparison", "No stat is stored for two dated sessions.")
        if nxt:
            d.add((5,), True, card("next-goal", "card.next-goal", "The next practice goal.", note=nxt))
    if not nxt:
        d.omit("Next practice goal", "No next-goal note is stored.")


def _court_memories(d: Draft) -> None:
    venue = d.brief["privacy"]["venueVisible"]
    usable = [b for b in d.context["brolls"] if b["depictsThisMatch"] and (venue or not b["revealsLocation"])]
    got = _ranked(d, {"brolls": [{"brollId": b["brollId"], "chapter": b["chapter"]} for b in usable]})
    caption = d.directions["caption"]
    caption_overlay = [{"kind": "note", "refId": caption}] if caption and d.allowed("note", caption) else []
    moments = [i["id"] for i in got["order"] if i["kind"] == "keeper"]
    arrival = [i["id"] for i in got["order"] if i["kind"] == "broll" and i["chapter"] == "arrival"]
    after = [i["id"] for i in got["order"] if i["kind"] == "broll" and i["chapter"] == "after"]
    for n, bid in enumerate(arrival):
        d.add((0, n), True, beat("arrival", "broll", f"B-roll {bid} for the arrival.", broll=bid,
                                 overlays=caption_overlay if n == 0 else ()))
    if not arrival:
        d.add((0, 0), True, card("arrival", "card.date", "No arrival footage: a date card opens the day.",
                                 overlays=caption_overlay))
    if not usable:
        d.fallback = "one-camera-excerpts"
    for idea in got["missing"]:
        d.omit(*MISSING_TEXT[idea])

    def moment(kid, role):
        return beat(role, "live", f"{kid}, " + ("the top-ranked moment." if role == "highlight"
                                                 else "a real moment of the day."), keeper=kid, angle=d.primary(kid))
    for n, kid in enumerate(moments):
        d.add((1, d.keepers[kid]["session"]["startUs"], kid), n == 0, moment(kid, "highlight" if n == 0 else
                                                                             "match-moment"))
    for n, bid in enumerate(after):
        d.add((2, n), True, beat("after", "broll", f"B-roll {bid} for after the match.", broll=bid))
    chosen = sorted((k for k in d.context["keepers"] if k["selection"] == "manual" and k["keeperId"] not in moments),
                    key=lambda k: (k["session"]["startUs"], k["keeperId"]))
    for k in chosen:
        d.add((1, k["session"]["startUs"], k["keeperId"]), False, moment(k["keeperId"], "match-moment"))
    if d.directions["dedication"]:
        d.add((3,), True, card("dedication", "card.dedication", "The player's dedication.",
                               note=d.directions["dedication"]))


PROFILE_PLANNERS = {"coach-cut": _coach_cut, "match-broadcast": _match_broadcast, "rally-pulse": _rally_pulse,
                    "progress-story": _progress_story, "court-memories": _court_memories}


# ----- fill, number, finish ---------------------------------------------------------------------------------------

def fill(groups: list, target_ms: int, min_ms: int, max_ms: int) -> list:
    """Required groups always; optional groups in priority (list) order while the estimate stays within the target;
    then, only if the estimate is under the profile minimum, more optional groups while it stays within the profile
    maximum, until the minimum is reached. Real material only: nothing is repeated or stretched to fill time."""
    chosen = [g for g in groups if g["required"]]
    total = sum(g["ms"] for g in chosen)
    optional = [g for g in groups if not g["required"]]
    for g in optional:
        if total + g["ms"] <= target_ms:
            chosen.append(g)
            total += g["ms"]
    for g in optional:
        if total >= min_ms:
            break
        if g not in chosen and total + g["ms"] <= max_ms:
            chosen.append(g)
            total += g["ms"]
    return sorted(chosen, key=lambda g: g["key"])


def plan(profiles: dict, briefed: dict, context: dict) -> dict:
    if "refusal" in briefed:
        return {"refusal": dict(briefed["refusal"])}
    brief = briefed["brief"]
    profile = profiles[brief["profile"]["id"]]
    require(not director.lint(profiles, brief, context), "grammarViolation", "the brief breaks its profile grammar")
    if not context["keepers"]:
        return {"refusal": {"code": "noKeepers", "message": director.NO_KEEPERS}}
    d = Draft(profile, context, briefed)
    PROFILE_PLANNERS[profile["id"]](d)
    g = profile["grammar"]["durationSeconds"]
    target_ms = brief["durationTargetSeconds"] * 1000
    chosen = fill(d.groups, target_ms, g["min"] * 1000, g["max"] * 1000)
    beats = [dict(b, overlays=[dict(o) for o in b["overlays"]]) for grp in chosen for b in grp["beats"]]
    if not any(b["treatment"] in ("live", "broll") for b in beats):
        return {"refusal": {"code": "noRelevantKeepers", "message": director.NO_KEEPERS}}
    if d.finalize:
        d.finalize(beats)
    per_beat = []
    for n, b in enumerate(beats, start=1):
        b["beatId"] = f"b{n:02d}"
        per_beat.append({"beatId": b["beatId"], "ms": d.ms(b)})
    total = sum(x["ms"] for x in per_beat)
    unresolved = []
    below = total < g["min"] * 1000
    if below:
        unresolved.append(f"About {director.estimate_label(total)} of real material; {profile['name']} needs at least "
                          f"{director.length_label(g['min'])}. Mark more moments for a longer film.")
    elif total < target_ms:
        unresolved.append(f"About {director.estimate_label(total)} of real material, so this film is shorter than "
                          f"{director.length_label(brief['durationTargetSeconds'])}. Nothing is padded.")
    doc = dict(brief, **d.header)
    doc.update(beats=beats, comparisons=d.comparisons, omitted=d.omitted, unresolved=unresolved,
               bindings=dict(brief["bindings"]), profile=dict(brief["profile"]), planner=dict(brief["planner"]),
               privacy=dict(brief["privacy"]))
    check(profiles, doc, context)
    findings = director.lint(profiles, doc, context)
    require(not findings, "grammarViolation", f"the planner broke its own grammar: {findings}")
    return {"plan": doc, "estimate": {"totalMs": total, "beats": per_beat}, "fallback": d.fallback,
            "belowMinimum": below}


# ----- trust check ------------------------------------------------------------------------------------------------

def _beat(beat: dict, label: str, keepers: dict, brolls: dict, notes: dict, refs: dict) -> None:
    fields(beat, BEAT_FIELDS, label)
    t = beat["treatment"]
    if t in KEEPER_TREATMENTS:
        require(beat["keeperId"] is not None and beat["brollId"] is None and beat["templateId"] is None
                and beat["noteId"] is None, "treatmentMismatch", f"{label}: a {t} beat names one keeper only")
        k = keepers.get(beat["keeperId"])
        require(k is not None, "untrustedReference", f"{label}: keeper {beat['keeperId']!r} is not in the catalog")
        require(beat["angle"] is None or beat["angle"] in k["slots"], "untrustedReference",
                f"{label}: {beat['keeperId']} has no view from {beat['angle']}")
    elif t == "broll":
        require(beat["brollId"] is not None and beat["keeperId"] is None and beat["templateId"] is None
                and beat["noteId"] is None and beat["angle"] is None, "treatmentMismatch",
                f"{label}: a B-roll beat names one B-roll item only")
        require(beat["brollId"] in brolls, "untrustedReference", f"{label}: B-roll {beat['brollId']!r} is not in the catalog")
    elif t == "title-card":
        require(beat["templateId"] is not None and beat["keeperId"] is None and beat["brollId"] is None
                and beat["angle"] is None and beat["replaySpeedDen"] is None, "treatmentMismatch",
                f"{label}: a card names a template and at most a note")
        tmpl = director.CARD_TEMPLATES.get(beat["templateId"])
        require(tmpl is not None, "untrustedReference", f"{label}: {beat['templateId']!r} is not a catalog card")
        if tmpl["note"] is None:
            require(beat["noteId"] is None, "badTemplateSlot", f"{label}: {beat['templateId']} takes no note")
        else:
            require(beat["noteId"] is not None, "badTemplateSlot", f"{label}: {beat['templateId']} needs a note")
            note = notes.get(beat["noteId"])
            require(note is not None, "untrustedReference", f"{label}: note {beat['noteId']!r} is not stored")
            require(note["use"] == tmpl["note"], "badTemplateSlot",
                    f"{label}: {beat['templateId']} needs a {tmpl['note']} note, not a {note['use']} note")
    else:
        raise Reject("treatmentMismatch", f"{label}: treatment {t!r}")
    for o in beat["overlays"]:
        fields(o, "kind refId", f"{label} overlay")
        ref = refs.get(o["refId"])
        require(ref is not None and ref["kind"] == o["kind"], "untrustedReference",
                f"{label}: overlay {o['refId']!r} is not a stored {o['kind']}")


def check(profiles: dict, plan_doc: dict, context: dict) -> dict:
    fields(plan_doc, BRIEF_FIELDS, "story plan")
    require(plan_doc["schemaVersion"] == "jovra.story-brief/1", "badVersion", "not a jovra.story-brief/1")
    require(plan_doc["projectId"] == context["projectId"], "projectMismatch", "plan of another project")
    require(plan_doc["bindings"] == context["bindings"], "staleRevision", "plan bound to other revisions")
    profile = profiles.get(plan_doc["profile"]["id"])
    require(profile is not None and plan_doc["profile"]["revision"] == profile["revision"], "profileMismatch",
            "unknown profile or revision")
    keepers = {k["keeperId"]: k for k in context["keepers"]}
    brolls = {b["brollId"]: b for b in context["brolls"]}
    notes = {n["noteId"]: n for n in context["notes"]}
    refs = {r["refId"]: r for r in context["references"]}
    ids = [b.get("beatId") for b in plan_doc["beats"]]
    require(len(set(ids)) == len(ids), "duplicateId", "beat ids must be unique")
    for n, b in enumerate(plan_doc["beats"]):
        _beat(b, f"beat {n}", keepers, brolls, notes, refs)
    music = plan_doc["music"]
    require(music is None or any(r["rightsRecordId"] == music["rightsRecordId"] and r["assetId"] == music["assetId"]
                                 for r in context["rights"]), "untrustedReference", "music without its rights record")
    narration = plan_doc["narration"]
    require(narration is None or any(c["consentRecordId"] == narration["consentRecordId"] for c in context["consents"]),
            "untrustedReference", "narration without its consent record")
    for c in plan_doc["comparisons"]:
        ref = refs.get(c["statId"])
        require(ref is not None and ref["kind"] == "metric", "untrustedReference", f"comparison stat {c['statId']!r}")
    return {"beats": len(plan_doc["beats"])}


# ----- vectors ----------------------------------------------------------------------------------------------------

def run_vector(profiles: dict, case: dict) -> dict:
    """A planner vector case (op plan or check) -> its result, or {"rejectCode": code}."""
    inp = case["input"]
    try:
        if case["op"] == "plan":
            briefed = director.brief(profiles, inp["context"], inp["profileId"], inp["options"])
            out = plan(profiles, briefed, inp["context"])
            return dict(out, directions=briefed.get("directions"))
        if case["op"] == "check":
            return check(profiles, inp["plan"], inp["context"])
        raise Reject("badOp", f"op {case['op']!r}")
    except Reject as exc:
        return {"rejectCode": exc.code}
