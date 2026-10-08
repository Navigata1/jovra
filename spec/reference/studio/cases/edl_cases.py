"""EDL (jovra.edit-plan/2) vectors, invalid cases and checkers. Module page: spec/studio/modules/edl.md.

Vector "expect" blocks come from the reference; "assert" blocks are hand-derived and checked independently by
scripts/spec/validate_studio.py.
"""

from __future__ import annotations

from fractions import Fraction

from studio import edl
from studio.core import Reject, apply_patch, round_half_up
from studio.cases.patches import add, bad, invalid_docs, rep, rm


# ----- EDL vectors against a modified trusted context ---------------------------------------------

def _edl_case(cid, why, plan_name, plans_by_name, context, context_patch, plan_patch, assertions):
    plan = apply_patch(plans_by_name[plan_name], plan_patch)
    ctx = apply_patch(context, context_patch)
    try:
        got = edl.validate(plan, PROFILES_FOR_VECTORS, ctx)
        expect = {"status": got["status"]}
    except Reject as exc:
        expect = {"rejectCode": exc.code}
    return {"id": cid, "why": why, "plan": f"records/edit-plan.{plan_name}.json", "contextPatch": context_patch,
            "planPatch": plan_patch, "expect": expect, "assert": assertions}


PROFILES_FOR_VECTORS: dict = {}


def edl_context_vectors(P, plans_by_name, context, profiles):
    """Piecewise coverage: Camera 2's proxy split into two adjacent intervals, as after a restart (frames 0-108000
    and 108000-216000, the second at an unrelated session start). The trusted bundle offers only single-segment
    sources today, so these vectors patch the trusted context directly."""
    PROFILES_FOR_VECTORS.clear()
    PROFILES_FOR_VECTORS.update(profiles)
    cov = context["sources"]["camera-2"]["coverage"][0]
    restart = 2_000_000_000
    first = {"inFrame": 0, "outFrame": 108000, "sessionStartUs": cov["sessionStartUs"], "rate": cov["rate"]}
    second = {"inFrame": 108000, "outFrame": 216000, "sessionStartUs": restart, "rate": cov["rate"]}
    ctx_patch = [rep("/sources/camera-2/coverage", [first, second])]
    n = 6540   # c05: 3270 output frames at 30 fps from a 60 fps source

    def c05_at(s_in, session, extra=()):
        return [rep("/sources/1/coverage", [first, second]),
                rep("/segments/4/sourceInFrame", s_in), rep("/segments/4/sourceOutFrame", s_in + n),
                rep("/segments/4/sessionInUs", session), rep("/segments/4/keeperId", None),
                rep("/segments/4/protectedFrames", []), rep("/segments/4/overlayRefs", []),
                rep("/audio/bed/3/sourceInFrame", s_in), *extra]

    src = edl.Source(dict(plans_by_name["coach-cut-serve"]["sources"][1], coverage=[first, second]),
                     Fraction(30))
    extrapolated = round_half_up(src.session_us(108000, src.coverage[0]))
    end_first = 108000 - n
    end_first_session = round_half_up(src.session_us(end_first))
    cases = [
        _edl_case("restart-first-frame", "A live segment starting on the first frame of the restarted interval maps "
                  "through that interval: sessionInUs is the interval's session start", "coach-cut-serve",
                  plans_by_name, context, ctx_patch, c05_at(108000, restart), {"sessionInUs": restart}),
        _edl_case("restart-extrapolated-session", "The previous interval's extrapolated end is not the session time "
                  "of the restarted interval's first frame", "coach-cut-serve", plans_by_name, context, ctx_patch,
                  c05_at(108000, extrapolated), {"sessionInUs": extrapolated}),
        _edl_case("window-ends-at-restart", "A window may end exactly on the restart frame (the exclusive end of the "
                  "first interval)", "coach-cut-serve", plans_by_name, context, ctx_patch,
                  c05_at(end_first, end_first_session), {"sessionInUs": end_first_session}),
        _edl_case("dissolve-across-restart", "A dissolve into the restarted interval's first frame would need handles "
                  "from the other interval", "coach-cut-serve", plans_by_name, context, ctx_patch,
                  c05_at(108000, restart, [rep("/segments/4/transitionIn", {"type": "dissolve", "frames": 4})]),
                  {"handlesCrossRestart": True}),
    ]
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "edl-context",
            "status": "Sample: the trusted context is patched to give Camera 2 two adjacent coverage intervals "
                      "(a restart); expectations come from the reference, assertions are hand-derived",
            "cases": cases}



# ----- invalid cases ------------------------------------------------------------------------------

def invalid_sets(P, plans):
    sets = {}
    sb = plans["storyboard"]
    s03_session = sb["segments"][2]["sessionInUs"]
    s02_bed = sb["audio"]["bed"][1]["sourceInFrame"]
    # coach: move c05 so it shows the session time the hold-bed plays under (1260-1271 s)
    c05_in = P.frame_for_session("camera-2", 1_262_000_000)
    c05_session = round_half_up(P.session("camera-2", c05_in))
    # coach: the primary-bed frame that would be in sync with c05 at output frame 4800
    c05_back = P.frame_for_session("camera-1", P.session("camera-2", 150000 + (4800 - 2250) * 2))
    # rally: an alternate bed from camera-2 in sync with r02 (camera-1 120000..), starting at r02's dissolve
    r02_alt = P.frame_for_session("camera-2", P.session("camera-1", 120000))
    sets["edit-plan.court-memories-storyboard"] = [
        bad("executable-command", "An EDL never carries a command", [add("/command", "ffmpeg -i x")]),
        bad("approval-in-plan", "Approval lives in the job/reservation, never the plan", [add("/approved", True)]),
        bad("signed-url-source", "No URL or path in a source snapshot", [add("/sources/0/url", "https://example.invalid/x")]),
        bad("unlabelled-speed", "1.25x is not an allowed speed", [rep("/segments/1/speed", {"num": 5, "den": 4})]),
        bad("wipe-transition", "Transitions come from cut/dissolve/dip only", [rep("/segments/1/transitionIn/type", "wipe")]),
        bad("copied-score-digits", "Overlays reference records; the plan never carries the value",
            [add("/segments/2/overlayRefs/0/value", 7)]),
        bad("aspect-21-9", "Unsupported output aspect", [rep("/output/aspect", "21:9")]),
        bad("model-guessed-reframe", "Reframe only from a reviewed action-safe box",
            [rep("/segments/1/framing", {"mode": "reframe", "basis": "model-guess",
                                         "windows": [{"atFrame": 0, "x": 0, "y": 0, "w": 10000, "h": 10000}]})]),
        bad("stale-overlay", "A score overlay bound to an older event revision", [rep("/segments/2/overlayRefs/0/eventRevision", 2)],
            "staleRevision"),
        bad("stale-event-revision", "The plan predates a point correction", [rep("/bindings/eventRevision", 2)], "staleRevision"),
        bad("stale-sync-revision", "The plan predates the reviewed sync map", [rep("/bindings/syncRevision", 1)], "staleRevision"),
        bad("output-gap", "Output frames 360-361 are uncovered", [rep("/segments/1/outputInFrame", 361)], "outputGap"),
        bad("incomplete-timeline", "The last frame is uncovered", [rep("/output/totalFrames", 7741)], "incompleteCoverage"),
        bad("source-overrun", "Window past the end of Camera 2's coverage",
            [rep("/segments/4/sourceInFrame", 213000), rep("/segments/4/sourceOutFrame", 217608)], "outsideCoverage"),
        bad("duration-mismatch", "Source and output durations disagree at 1x", [rep("/segments/1/sourceOutFrame", 1118)],
            "durationMismatch"),
        bad("forged-session-time", "sessionInUs does not follow the sync map",
            [rep("/segments/2/sessionInUs", s03_session + 1000)], "sessionTimeMismatch"),
        bad("integral-float-frame", "Frames are integers; 744.0 is refused by the reference",
            [rep("/segments/1/sourceInFrame", 744.0)], "badInteger"),
        bad("transition-too-long", "16 frames = 533 ms > Court Memories' 500 ms", [rep("/segments/1/transitionIn/frames", 16)],
            "transitionTooLong"),
        bad("dissolve-without-handles", "B-roll 1 has no frames after its end for the dissolve",
            [rep("/segments/0/sourceInFrame", 1440), rep("/segments/0/sourceOutFrame", 1800)], "transitionHandle"),
        bad("dissolve-over-contact", "The dissolve would blend a protected contact window",
            [add("/segments/1/protectedFrames/-", {"inFrame": 746, "outFrame": 760})], "contactProtected"),
        bad("court-audio-out-of-sync", "The primary bed starts 20 frames (333 ms) late",
            [rep("/audio/bed/1/sourceInFrame", s02_bed + 20)], "bedOutOfSync"),
        bad("silent-live-play", "Live play under silence while the film has court audio",
            [rep("/audio/bed/2", {"route": "silence", "sourceId": None, "sourceInFrame": None, "outputInFrame": 546,
                                  "outputOutFrame": 2346, "fadeInMs": 10, "fadeOutMs": 10})], "liveWithoutCourtAudio"),
        bad("bed-gap", "An output span with no audio route", [rm("/audio/bed/3")], "bedCoverage"),
        bad("clean-alternate-with-motion", "A clean alternate cannot keep dissolves", [rep("/cleanAlternate", True)],
            "motionInCleanAlternate"),
        bad("unknown-source", "Camera 9 is not in the plan", [rep("/segments/4/sourceId", "camera-9")], "unknownSource"),
        bad("duplicate-segment-id", "Segment ids are unique", [rep("/segments/3/id", "s03")], "duplicateId"),
        bad("untrusted-hash", "The source hash differs from the trusted manifest", [rep("/sources/0/sha256", "0" * 64)],
            "untrustedSource"),
        bad("upscale-to-4k", "A 4K film from 1080p proxies invents no detail",
            [rep("/output/width", 3840), rep("/output/height", 2160)], "upscaleRefused"),
        bad("chapters-out-of-order", "Chapters strictly increase", [rep("/chapters/1/outputInFrame", 7100)], "badChapters"),
        bad("contact-unprotected-without-keeper", "Naming no keeper does not switch contact protection off: s03 "
            "still contains the stored k-02 contacts",
            [rep("/segments/2/keeperId", None), rep("/segments/2/protectedFrames", [])], "contactUnprotected"),
        bad("forged-coverage-start", "Camera 2's session start shifted 500 ms together with sessionInUs: coverage comes "
            "from the reviewed sync map, never from the plan",
            [rep("/sources/1/coverage/0/sessionStartUs", sb["sources"][1]["coverage"][0]["sessionStartUs"] + 500_000),
             rep("/segments/1/sessionInUs", sb["segments"][1]["sessionInUs"] + 500_000)], "coverageMismatch"),
    ]
    sets["edit-plan.coach-cut-serve"] = [
        bad("free-text-card", "Card text comes from records and templates, never free text",
            [rep("/segments/0/templateId", "Your goal: win")]),
        bad("interpolated-quarter-speed", "60 fps x 1/4 = 15 fps < 30 fps output: would need invented frames",
            [rep("/segments/3/speed", {"num": 1, "den": 4}), rep("/segments/3/sourceOutFrame", 73100)], "cleanFrameRule"),
        bad("replay-before-original", "A replay follows the live segment it re-shows", [rep("/segments/3/replayOf", "c05")],
            "replayBeforeOriginal"),
        bad("replay-of-unshown-time", "The replay shows session time c02 never showed",
            [rep("/segments/3/sourceInFrame", 75700), rep("/segments/3/sourceOutFrame", 75940)], "replayOutsideOriginal"),
        bad("freeze-too-long", "A 5 s freeze exceeds Coach's Cut's 3 s",
            [rep("/segments/2/outputOutFrame", 2070), rep("/segments/3/outputInFrame", 2070),
             rep("/segments/3/sourceOutFrame", 73160)], "freezeDuration"),
        bad("grade-not-in-profile", "Coach's Cut uses no look preset", [rep("/grade/presetId", "warm-court-1")], "opNotAllowed"),
        bad("dip-not-in-profile", "Coach's Cut allows dissolves only", [rep("/segments/4/transitionIn", {"type": "dip", "frames": 6})],
            "transitionNotAllowed"),
        bad("estimated-cue-as-instruction", "An estimated cue is never shown as instruction",
            [rep("/segments/2/overlayRefs/1/provenance", "estimated")], "provenanceNotAllowed"),
        bad("two-annotations", "At most one annotation at a time",
            [add("/segments/2/overlayRefs/-", {"kind": "annotation", "refId": "ann-02", "eventRevision": 3,
                                               "provenance": "reviewed"})], "badOverlays"),
        bad("hold-bed-over-live", "Hold-bed continues under live play (c05)",
            [rep("/audio/bed/2/outputOutFrame", 5520), rm("/audio/bed/3")], "holdBedOverLive"),
        bad("primary-bed-under-replay", "The replay of k-02 soundtracked by camera-1 court audio from k-03's contact "
            "(frame 121000), starting with a 0 ms jump: primary court audio plays only under live play",
            [rep("/audio/bed/2/outputOutFrame", 2010),
             add("/audio/bed/3", {"route": "primary-bed", "sourceId": "camera-1", "sourceInFrame": 120900,
                                  "outputInFrame": 2010, "outputOutFrame": 2250, "fadeInMs": 0, "fadeOutMs": 20})],
            "courtBedOffLive"),
        bad("alt-court-bed-under-replay", "Another angle's court audio under the replay is unchecked court audio too",
            [rep("/audio/bed/2/outputOutFrame", 2010),
             add("/audio/bed/3", {"route": "alt-bed", "sourceId": "camera-2", "sourceInFrame": 149000,
                                  "outputInFrame": 2010, "outputOutFrame": 2250, "fadeInMs": 20, "fadeOutMs": 20})],
            "courtBedOffLive"),
        bad("score-of-another-point", "The score of p-090 (keeper k-04) over k-02's rally (point p-041)",
            [rep("/segments/1/overlayRefs/0", {"kind": "score", "refId": "p-090", "eventRevision": 3,
                                               "provenance": "manual"})], "overlayOutsideMoment"),
        bad("score-over-another-rally", "The score of p-041 (keeper k-02) over the k-04 rally on camera-2",
            [rep("/segments/4/overlayRefs/0", {"kind": "score", "refId": "p-041", "eventRevision": 3,
                                               "provenance": "reviewed"})], "overlayOutsideMoment"),
        bad("hold-bed-not-dead-time", "The held court audio is session time a later live segment shows",
            [rep("/segments/4/sourceInFrame", c05_in), rep("/segments/4/sourceOutFrame", c05_in + 6540),
             rep("/segments/4/sessionInUs", c05_session), rep("/segments/4/protectedFrames", []),
             rep("/segments/4/overlayRefs", [])], "holdBedNotDeadTime"),
        bad("hold-bed-jump", "Hold-bed must continue the primary bed without a jump", [rep("/audio/bed/2/sourceInFrame", 75000)],
            "holdBedNotContinuous"),
        bad("alt-bed-mid-segment", "Switching angle audio only at a segment boundary",
            [rep("/audio/bed/2/outputOutFrame", 2260), rep("/audio/bed/3/outputInFrame", 2260)], "bedSwitchNotAtBoundary"),
        bad("bed-returns-mid-segment", "The return from an alternate bed to the primary is a switch too: never inside "
            "live segment c05, and never with a 0 ms fade",
            [rep("/audio/bed/3/outputOutFrame", 4800),
             add("/audio/bed/4", {"route": "primary-bed", "sourceId": "camera-1", "sourceInFrame": c05_back,
                                  "outputInFrame": 4800, "outputOutFrame": 5520, "fadeInMs": 0, "fadeOutMs": 20})],
            "bedSwitchNotAtBoundary"),
        bad("replay-as-unlabelled-live", "Re-showing c02's moment as a second 1x live segment is a replay without the "
            "Replay label",
            [rep("/segments/3", {"id": "c04", "op": "live", "outputInFrame": 2010, "outputOutFrame": 2250,
                                 "transitionIn": {"type": "cut", "frames": 0}, "sourceId": "camera-1",
                                 "sourceInFrame": 72980, "sourceOutFrame": 73460, "speed": {"num": 1, "den": 1},
                                 "sessionInUs": round_half_up(P.session("camera-1", 72980)), "keeperId": None,
                                 "protectedFrames": P.protected("k-02", "camera-1", 72980, 73460),
                                 "overlayRefs": [], "framing": {"mode": "fill"}}),
             rep("/audio/bed/2/outputOutFrame", 2010),
             add("/audio/bed/3", {"route": "primary-bed", "sourceId": "camera-1", "sourceInFrame": 72980,
                                  "outputInFrame": 2010, "outputOutFrame": 2250, "fadeInMs": 20, "fadeOutMs": 20})],
            "replayWithoutLabel"),
        bad("plan-for-another-project", "A plan is checked only against its own project's records",
            [rep("/projectId", "someone-elses-project")], "projectMismatch"),
        bad("narration-without-consent", "Narration needs recorded consent", [rep("/audio/narration/consent/granted", False)],
            "consentMissing"),
        bad("generated-narration-undisclosed", "Generated narration is labelled", [rep("/audio/narration/voice", "generated")],
            "disclosureMissing"),
        bad("music-in-coach-cut", "Coach's Cut has no music",
            [rep("/audio/music", {"assetId": "track-01", "rightsRecordId": "rights-track-01", "rightsScope": ["private-film"],
                                  "windows": [{"outputInFrame": 0, "outputOutFrame": 120}]})], "opNotAllowed"),
        bad("wrong-profile-length", "192 s is too long for Rally Pulse (30-180 s)", [rep("/bindings/profileId", "rally-pulse")],
            "durationOutsideProfile"),
        bad("score-digits-as-ref", "Score digits used as an id resolve to no stored record",
            [rep("/segments/1/overlayRefs/0/refId", "6-4_3-2")], "untrustedReference"),
        bad("unknown-overlay-ref", "An overlay must point at a stored record", [rep("/segments/1/overlayRefs/0/refId", "no-such-point")],
            "untrustedReference"),
        bad("overlay-kind-relabelled", "A stored stat cannot be shown as a note", [rep("/segments/1/overlayRefs/1/kind", "note")],
            "kindMismatch"),
        bad("cue-overlay-laundered", "Re-pointing the cue overlay at the estimated cue while keeping 'reviewed'",
            [rep("/segments/2/overlayRefs/1/refId", "cue-04")], "provenanceMismatch"),
        bad("card-text-unresolved", "Card text comes only from stored notes", [rep("/segments/0/textRefs", ["40-15"])],
            "untrustedReference"),
        bad("card-text-not-a-note", "A score record is not card text", [rep("/segments/0/textRefs", ["p-041"])], "kindMismatch"),
        bad("narration-script-unresolved", "A narration script is grounded in stored notes",
            [rep("/audio/narration/scriptNoteIds", ["invented-note"])], "untrustedReference"),
        bad("self-attested-consent", "A plan cannot attest its own consent", [rep("/audio/narration/consent/consentRecordId", "i-say-yes")],
            "consentMissing"),
        bad("generated-voice-without-consent", "Consent to record narration is not consent to a generated voice",
            [rep("/audio/narration/voice", "generated"), rep("/audio/narration/disclosureTemplateId", "label.narration-generated")],
            "consentMissing"),
    ]
    r04_primary = P.frame_for_session("camera-1", P.session("camera-2", 150700))
    sets["edit-plan.rally-pulse-portrait"] = [
        bad("primary-returns-hard-at-cut", "The primary bed returning at another position of camera-1 (in sync with "
            "r04) after the held bed is a switch: it fades in for at least 20 ms even at a cut",
            [rep("/audio/bed/3", {"route": "primary-bed", "sourceId": "camera-1", "sourceInFrame": r04_primary,
                                  "outputInFrame": 945, "outputOutFrame": 1350, "fadeInMs": 0, "fadeOutMs": 20})],
            "fadeTooShort"),
        bad("same-source-jump-at-dissolve", "r01 -> r02 jumps to another moment of camera-1 at a dissolve: a switch, "
            "so the fades must span the picture transition (100 ms each way at 6 frames)",
            [rep("/audio/bed/0/fadeOutMs", 20), rep("/audio/bed/1/fadeInMs", 20)], "fadeTooShort"),
        bad("blind-portrait-crop", "Fill would blindly crop a landscape source into 9:16",
            [rep("/segments/3/framing", {"mode": "fill"})], "framingAspect"),
        bad("pan-too-fast", "1082 units in 10 frames", [rep("/segments/0/framing/windows/1",
                                                            {"atFrame": 10, "x": 4500, "y": 0, "w": 3164, "h": 10000})],
            "panTooFast"),
        bad("window-leaves-frame", "The crop window leaves the source frame",
            [rep("/segments/0/framing/windows/0/x", 7000)], "badReframe"),
        bad("aspect-dimension-mismatch", "1080x1080 is not 9:16", [rep("/output/height", 1080)], "badOutput"),
        bad("music-without-private-rights", "Music needs rights for the private film",
            [rep("/audio/music/rightsScope", ["youtube"])], "rightsMissing"),
        bad("self-attested-rights", "A plan cannot attest its own rights", [rep("/audio/music/rightsRecordId", "trust-me")],
            "rightsMissing"),
        bad("rights-scope-overclaim", "The stored rights cover the private film only",
            [rep("/audio/music/rightsScope", ["private-film", "youtube"])], "rightsMissing"),
        bad("rights-for-another-asset", "A rights record covers one asset", [rep("/audio/music/assetId", "track-02")],
            "rightsMissing"),
        bad("alt-bed-at-dissolve", "An alternate bed starting at r02's 6-frame dissolve with 20 ms fades would switch "
            "hard in the middle of the blend; it needs 100 ms fades on both sides (an audio dip)",
            [rep("/audio/bed/1", {"route": "alt-bed", "sourceId": "camera-2", "sourceInFrame": r02_alt,
                                  "outputInFrame": 420, "outputOutFrame": 900, "fadeInMs": 20, "fadeOutMs": 20}),
             rep("/audio/bed/2", {"route": "silence", "sourceId": None, "sourceInFrame": None, "outputInFrame": 900,
                                  "outputOutFrame": 945, "fadeInMs": 10, "fadeOutMs": 10})], "fadeTooShort"),
    ]
    sets["edit-plan.match-broadcast-set-1"] = [
        bad("out-of-order-points", "Match Broadcast keeps strict session order",
            [rep("/segments/3/sourceInFrame", 3000), rep("/segments/3/sourceOutFrame", 11220),
             rep("/segments/3/sessionInUs", 50_000_000)], "chronology"),
        bad("broadcast-reframe", "Match Broadcast letterboxes instead of reframing",
            [rep("/segments/1/framing", {"mode": "reframe", "basis": "reviewed-action-box",
                                         "windows": [{"atFrame": 0, "x": 0, "y": 0, "w": 10000, "h": 10000}]})],
            "opNotAllowed"),
        bad("metric-in-broadcast", "Match Broadcast shows score and notes only",
            [add("/segments/1/overlayRefs/-", {"kind": "metric", "refId": "stat-aces", "eventRevision": 3,
                                               "provenance": "reviewed"})], "overlayNotAllowed"),
        bad("quarter-speed-replay", "Match Broadcast replays at 1/2 only", [rep("/segments/2/speed", {"num": 1, "den": 4})],
            "badSpeed"),
    ]
    return invalid_docs(sets)


# ----- what this module declares and registers ----------------------------------------------------

def fixtures(sample):
    docs = {"vectors/edl-context.json": edl_context_vectors(sample.P, {"coach-cut-serve": sample.plans["coach"]},
                                                            sample.trusted, sample.profiles)}
    for name, doc in invalid_sets(sample.P, sample.plans).items():
        docs[f"invalid/{name}.invalid.json"] = doc
    return docs


def check_edl_context_vector(ctx, case, report, where) -> None:
    """An EDL validated against a patched trusted context (e.g. a source with two adjacent coverage intervals)."""
    plan = apply_patch(ctx.fixture(case["plan"]), case["planPatch"])
    context = apply_patch(ctx.edl_context, case["contextPatch"])
    errors = ctx.schemas.validate(plan, "edit-plan.schema.json")
    if errors:
        report.fail(where, "patched plan fails the schema: " + "; ".join(errors[:2]))
        return
    try:
        got = {"status": edl.validate(plan, ctx.profiles, context)["status"]}
    except Reject as exc:
        got = {"rejectCode": exc.code}
    if got != case["expect"]:
        report.fail(where, f"reference gives {got}, stored {case['expect']}")
        return
    a = case["assert"]
    seg = plan["segments"][4]
    cov = context["sources"][seg["sourceId"]]["coverage"]
    problems = []
    if "sessionInUs" in a:
        # hand rule: the interval holding the first frame is the half-open one with inFrame <= frame < outFrame
        holder = [c for c in cov if c["inFrame"] <= seg["sourceInFrame"] < c["outFrame"]][0]
        valid = got == {"status": "valid-plan"}
        if holder["inFrame"] == seg["sourceInFrame"] and valid != (a["sessionInUs"] == holder["sessionStartUs"]):
            problems.append("the first frame of an interval must map to that interval's sessionStartUs")
    if a.get("handlesCrossRestart") and got.get("rejectCode") != "transitionHandle":
        problems.append("a dissolve across a restart must be refused for its handles")
    if problems:
        report.fail(where, "hand assertions: " + ", ".join(problems))
    else:
        report.ok("edl-context vectors")


def check_edit_plan(ctx, doc):
    return edl.validate(doc, ctx.profiles, ctx.edl_context)


VECTOR_CHECKERS = {"edl-context": check_edl_context_vector}
SCHEMAS = {"jovra.edit-plan/2": "edit-plan.schema.json"}
RECORD_RULES = {"jovra.edit-plan/2": check_edit_plan}
