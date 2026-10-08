"""The sample project's records, their invalid cases and reference rules. Module page:
spec/studio/modules/records.md.
"""

from __future__ import annotations

from studio import records
from studio.cases.patches import add, bad, invalid_docs, rep


# ----- invalid cases ------------------------------------------------------------------------------

def invalid_sets(P, plans):
    sets = {}
    sets["source-manifest"] = [
        bad("two-primaries", "Exactly one primary angle", [rep("/sources/1/isPrimary", True)], "primaryCount"),
        bad("hdr-without-hdr-transfer", "HDR declares HLG or PQ", [rep("/sources/2/original/colour/transfer", "bt709")],
            "colourMismatch"),
        bad("proxy-not-rotated", "A render proxy bakes rotation in", [rep("/sources/2/proxies/0/rotationApplied", False)],
            "proxyRotation"),
        bad("shared-slot", "Two cameras in one placement", [rep("/sources/2/slot", "far-baseline")], "slotTaken"),
        bad("file-path", "No local paths in a manifest", [add("/sources/0/original/path", "/var/mobile/x.mov")]),
        bad("segment-frames", "Segment frames must add up", [rep("/sources/0/segments/0/frameCount", 215999)], "badSegments"),
    ]
    sets["project-lock"] = [
        bad("demo-with-quote", "The local demo never authorizes spend",
            [rep("/quoteAuthorization", {"quoteId": "quote-test-01", "reservationId": "res-0002"})], "demoNeverReserves"),
        bad("recoloured-brand", "Brand tokens are fixed", [rep("/brand/chartreuse", "#00FF00")]),
        bad("demo-upload", "The local demo never uploads", [rep("/sourceRights/0/cloudConsent", True)], "demoNoUpload"),
        bad("hidden-but-visible", "A hidden location cannot show the venue", [rep("/privacy/venueVisible", True)],
            "privacyConflict"),
    ]
    sets["observation.estimated-cue"] = [
        bad("estimate-without-confidence", "Estimated values name their confidence", [rep("/provenance/confidence", None)],
            "provenanceMismatch"),
        bad("accepted-estimate", "Accepting an estimate makes it reviewed", [rep("/status", "accepted")], "provenanceMismatch"),
        bad("validated-without-benchmark", "Validated needs the capability benchmark", [rep("/provenance/status", "validated")],
            "provenanceMismatch"),
        bad("certainty-over-one", "Confidence lies in [0, 1]", [rep("/provenance/confidence", 1.5)]),
    ]
    sets["observation.calibrated-bounce"] = [
        bad("uncalibrated-bounce", "A bounce location needs a court calibration", [rep("/provenance/calibrationId", None)],
            "calibrationMissing"),
    ]
    sets["keeper-catalog"] = [
        bad("same-point-twice", "A second angle is a view, not another event", [rep("/keepers/1/eventRefs", ["p-003"])],
            "duplicateEvent"),
        bad("two-primary-views", "One primary view per keeper", [rep("/keepers/0/views/1/primary", True)], "primaryCount"),
        bad("contact-outside-view", "A contact lies inside a view", [rep("/keepers/1/contacts/0/frame", 80000)], "badContact"),
    ]
    sets["broll-catalog"] = [
        bad("generated-as-match", "Generated material never depicts this match", [rep("/items/0/origin", "generated")],
            "brollMisrepresented"),
    ]
    sets["story-brief.progress"] = [
        bad("percent-improvement", "Proportions change in percentage points, never '% improvement'",
            [rep("/comparisons/0/display/delta", "+50% improvement")], "displayMismatch"),
        bad("estimated-change-claim", "A change claim needs reviewed evidence on both sides",
            [rep("/comparisons/0/before/provenance", "estimated")], "weakEvidence"),
        bad("cherry-picked", "User-chosen examples cannot claim a change", [rep("/comparisons/0/selectionRule", "user-chosen")],
            "selectionBias"),
        bad("live-without-keeper", "No narrative beat without source evidence", [rep("/beats/1/keeperId", None)],
            "beatWithoutEvidence"),
        bad("score-text-in-brief", "The planner never writes score digits", [add("/beats/1/scoreText", "6-4")]),
    ]
    sets["story-brief.court-memories"] = [
        bad("replay-in-memories", "Court Memories has no replays",
            [rep("/beats/1/treatment", "replay"), rep("/beats/1/replaySpeedDen", 2)], "opNotAllowed"),
    ]
    sets["delivered-artifact.film"] = [
        bad("chapters-short", "Chapters cover the whole film", [rep("/chapters/2/endFrame", 7700)], "badChapters"),
        bad("ready-without-full-decode", "A finished export is not a verified film", [rep("/verification/fullDecode", "pending")],
            "unverifiedReady"),
        bad("two-day-link", "Share links last at most 24 hours", [rep("/delivery/shareLink/expiresAt", "2026-10-09T23:50:00Z")],
            "shareLinkLifetime"),
        bad("auto-published", "Prepare for YouTube never publishes", [rep("/youtubePrep/published", True)]),
        bad("public-film", "Delivery is private", [rep("/delivery/visibility", "public")]),
        bad("plan-hash-trailing-newline", "ECMA-262 anchors: the bound plan hash has no trailing newline",
            [rep("/bindings/editPlanSha256", "8" * 64 + "\n")]),
    ]
    sets["lesson.2026-10-07"] = [
        bad("over-done", "Done cannot exceed the target", [rep("/practice/0/done", 12)], "badPractice"),
        bad("pending-marked-done", "Five-clip review is still pending", [rep("/practice/2/status", "done")], "badPractice"),
        bad("cue-on-unknown-clip", "Cues anchor to this lesson's clips", [rep("/cues/0/clipId", "l9-clip")], "unknownClip"),
        bad("id-trailing-newline", "ECMA-262 '$' does not match before a trailing newline", [rep("/lessonId", "lesson-1007\n")]),
        bad("estimate-marked-reviewed", "An estimated cue is not reviewed", [rep("/cues/1/reviewedBy", "coach")],
            "provenanceMismatch"),
    ]
    sets["lesson.2026-09-23"] = [
        bad("unattributed-coach-note", "A coach note needs the lesson's coach", [rep("/coach", None)], "unattributedCoach"),
    ]
    sets["camera-invite"] = [
        bad("long-invite", "Invitations expire within 10 minutes", [rep("/invites/1/expiresAt", "2026-10-07T21:25:00Z")],
            "inviteLifetime"),
        bad("second-primary", "One primary camera", [rep("/roles/1/role", "primary")], "primaryCount"),
        bad("camera-escalation", "A camera never gets host controls",
            [add("/roles/1/permissions/-", "host-controls")], "permissionEscalation"),
        bad("coach-invite", "Camera invitations are for cameras", [rep("/invites/1/role", "coach")]),
        bad("invite-to-filled-slot", "An open invite cannot target a filled slot", [rep("/invites/1/slot", "far-baseline")],
            "slotTaken"),
        bad("invite-accepted-half-second-late", "21:00:00.500Z is after the 21:00:00Z expiry",
            [rep("/invites/0/acceptedAt", "2026-10-07T21:00:00.500Z")], "inviteExpired"),
    ]
    sets["reference-catalog"] = [
        bad("duplicate-reference", "One stored record per id", [rep("/references/1/refId", "p-041")], "duplicateId"),
        bad("stat-shown-as-score", "A stat is a metric, never a score", [rep("/references/4/kind", "score")], "kindMismatch"),
        bad("stale-reference", "Resolved at an older event revision", [rep("/references/0/eventRevision", 2)], "staleRevision"),
        bad("value-in-catalog", "The catalog indexes records; it never carries their values",
            [add("/references/0/value", "6-4")]),
    ]
    sets["storage-providers"] = [
        bad("planned-claims-export", "A planned provider does nothing yet", [rep("/providers/3/operations/exportFiles", True)],
            "capabilityOverclaim"),
        bad("icloud-on-android", "iCloud Drive is not an Android provider", [rep("/providers/1/platforms/android", True)],
            "badProvider"),
        bad("drive-active-unverified", "Active needs a verified OAuth integration and credential",
            [rep("/providers/2/status", "active")], "capabilityOverclaim"),
        bad("provider-as-compute", "Archives never process video", [rep("/providers/0/processing", True)]),
        bad("token-for-unconnected", "No credential for a provider that is not connected",
            [rep("/providers/2/credentialRef", "kc-drive")], "capabilityOverclaim"),
    ]
    return invalid_docs(sets)


# ----- what this module declares and registers ----------------------------------------------------

def fixtures(sample):
    """Every record of the sample project (spec/reference/studio/generate_studio_fixtures.py builds them), plus the
    invalid cases of the records no other module owns."""
    docs = dict(sample.records)
    for name, doc in invalid_sets(sample.P, sample.plans).items():
        docs[f"invalid/{name}.invalid.json"] = doc
    return docs


def check_story_brief(ctx, doc):
    return records.check_story_brief(doc, ctx.profiles)


def _plain(rule):
    def check(ctx, doc):
        return rule(doc)
    return check


SCHEMAS = {
    "jovra.project-lock/1": "project-lock.schema.json",
    "jovra.source-manifest/1": "source-manifest.schema.json",
    "jovra.observation/1": "observation.schema.json",
    "jovra.keeper-catalog/1": "keeper-catalog.schema.json",
    "jovra.broll-catalog/1": "broll-catalog.schema.json",
    "jovra.story-profile-catalog/1": "story-profile.schema.json",
    "jovra.story-brief/1": "story-brief.schema.json",
    "jovra.delivered-artifact/1": "delivered-artifact.schema.json",
    "jovra.lesson/1": "lesson.schema.json",
    "jovra.camera-invite/1": "camera-invite.schema.json",
    "jovra.storage-providers/1": "storage-provider-capability.schema.json",
    "jovra.reference-catalog/1": "reference-catalog.schema.json",
}
RECORD_RULES = {
    "jovra.story-brief/1": check_story_brief,
    "jovra.project-lock/1": _plain(records.check_project_lock),
    "jovra.source-manifest/1": _plain(records.check_source_manifest),
    "jovra.observation/1": _plain(records.check_observation),
    "jovra.keeper-catalog/1": _plain(records.check_keeper_catalog),
    "jovra.broll-catalog/1": _plain(records.check_broll_catalog),
    "jovra.delivered-artifact/1": _plain(records.check_artifact),
    "jovra.lesson/1": _plain(records.check_lesson),
    "jovra.camera-invite/1": _plain(records.check_camera_invites),
    "jovra.storage-providers/1": _plain(records.check_storage_providers),
    "jovra.reference-catalog/1": _plain(records.check_reference_catalog),
}
