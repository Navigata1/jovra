"""Record builders for the sample project (imported by generate_studio_fixtures.py): lock, briefs, observations,
lessons, camera roster, storage providers, quotes, reservations, jobs and the delivered film. All fictional Sample data
following design-reference/studio/brief/implementation-states.md.
"""

from __future__ import annotations

from studio.bundle import output_spec_hash
from studio.core import canonical_sha256

from generate_studio_fixtures import (BROLL_REVISION, EVENT_REVISION, FPS30, KEEPER_REVISION, MANIFEST_REVISION,
                                      PROJECT, SYNC_REVISION, fake_sha)


# ----- other records ------------------------------------------------------------------------------

def project_lock(manifest):
    return {
        "schemaVersion": "jovra.project-lock/1", "projectId": PROJECT, "revision": 1, "sample": True,
        "environment": "demo", "identity": {"mode": "demo-profile", "accountRef": None},
        "createdAt": "2026-10-07T22:30:00Z",
        "sourceManifest": {"revision": MANIFEST_REVISION, "sha256": canonical_sha256(manifest)},
        "eventRevision": EVENT_REVISION, "syncRevision": SYNC_REVISION,
        "profile": {"id": "court-memories", "revision": 1},
        "output": {"aspect": "16:9", "height": 1080, "durationTargetSeconds": 258},
        "participants": [
            {"participantId": "jon", "displayName": "Jon", "role": "player", "recordingAcknowledged": True, "appearance": "show"},
            {"participantId": "alex", "displayName": "Alex", "role": "player", "recordingAcknowledged": True, "appearance": "show"},
        ],
        "sourceRights": [
            {"sourceId": "camera-1", "ownerParticipantId": "jon", "cloudConsent": False, "consentRecordId": None},
            {"sourceId": "camera-2", "ownerParticipantId": "alex", "cloudConsent": False, "consentRecordId": None},
            {"sourceId": "camera-3", "ownerParticipantId": "jon", "cloudConsent": False, "consentRecordId": None},
        ],
        "privacy": {"venueVisible": False, "locationHidden": True},
        "quoteAuthorization": None,
        "brand": {"wordmark": "JOVRA", "mark": "court-arc", "ivory": "#F4F1E8", "forest": "#092A25", "panel": "#123C33",
                  "chartreuse": "#D7F56A", "clay": "#C47752"},
    }


def beat(bid, role, treatment, *, keeper=None, broll_id=None, angle=None, den=None, overlays=(), note=None,
         template=None, reason):
    return {"beatId": bid, "role": role, "treatment": treatment, "keeperId": keeper, "brollId": broll_id,
            "angle": angle, "replaySpeedDen": den, "overlays": [{"kind": k, "refId": r} for k, r in overlays],
            "noteId": note, "templateId": template, "reasonForReview": reason}


def brief_common(bid, profile, duration, aspect):
    return {"schemaVersion": "jovra.story-brief/1", "briefId": bid, "projectId": PROJECT, "revision": 1,
            "sample": True, "profile": {"id": profile, "revision": 1},
            "bindings": {"eventRevision": EVENT_REVISION, "syncRevision": SYNC_REVISION,
                         "keeperCatalogRevision": KEEPER_REVISION, "brollCatalogRevision": BROLL_REVISION},
            "planner": {"kind": "heuristic", "modelId": None, "adapterVersion": "jovra-planner@0.1.0"},
            "durationTargetSeconds": duration, "aspect": aspect, "primaryAudioPolicy": "continuous-primary-court-audio",
            "effectIntensity": "low", "privacy": {"venueVisible": False, "faces": "show"}, "music": None,
            "narration": None, "comparisons": [], "omitted": [], "unresolved": []}


def court_memories_brief():
    b = brief_common("brief-court-memories", "court-memories", 258, "16:9")
    b.update(feelingKey="feeling.day-mattered", audience="family", cleanAlternate=True, beats=[
        beat("b01", "arrival", "broll", broll_id="b-01", overlays=[("note", "note-caption")],
             reason="Real arrival footage opens the day."),
        beat("b02", "match-moment", "live", keeper="k-01", angle="far-baseline",
             reason="The far-baseline view of the first long rally."),
        beat("b03", "highlight", "live", keeper="k-02", angle="near-baseline", overlays=[("score", "p-041")],
             reason="Jon's favourite point, reviewed."),
        beat("b04", "after", "broll", broll_id="b-02", reason="Packing up after the match closes the film."),
    ], omitted=[{"idea": "A reaction shot of Alex after the final point", "missingEvidence": "No angle covers it."}])
    return b


def progress_brief():
    b = brief_common("brief-progress", "progress-story", 180, "16:9")
    b.update(feelingKey="feeling.growing-game", audience="self", cleanAlternate=False, beats=[
        beat("b01", "goal", "title-card", template="card.goal", note="note-goal", reason="Dated starting goal."),
        beat("b02", "early-evidence", "live", keeper="k-02", overlays=[("metric", "stat-first-serve-in")],
             reason="September evidence, reviewed."),
        beat("b03", "lesson", "title-card", template="card.lesson", note="note-lesson-2",
             reason="Lesson 2 milestone from the journal."),
        beat("b04", "recent-evidence", "replay", keeper="k-04", den=2, reason="October serve at half speed."),
        beat("b05", "next-goal", "title-card", template="card.next-goal", note="note-next", reason="Next practice goal."),
    ], comparisons=[{
        "comparisonId": "cmp-first-serve", "statId": "stat-first-serve-in", "metricDefinitionId": "first-serve-in-pct",
        "methodId": "manual-tagging-v1", "selectionRule": "all", "claim": "change",
        "before": {"date": "2026-09-09", "sessionIds": ["session-0909"], "numerator": 12, "denominator": 30,
                   "provenance": "reviewed"},
        "after": {"date": "2026-10-07", "sessionIds": ["session-1007"], "numerator": 18, "denominator": 30,
                  "provenance": "reviewed"},
        "display": {"before": "12 / 30 · 40%", "after": "18 / 30 · 60%", "delta": "+20 percentage points"},
    }])
    return b


def observations():
    base = {"schemaVersion": "jovra.observation/1", "projectId": PROJECT, "sample": True, "eventRevision": EVENT_REVISION}
    return {
        "observation.estimated-cue": dict(base, observationId="obs-01", kind="cue", sourceId="camera-1",
                                          sourceTime={"startUs": 1_216_000_000, "endUs": 1_218_500_000},
                                          sessionTimeUs=1_216_000_000, syncRevision=SYNC_REVISION, eventRef="p-041",
                                          capabilityId="analysis.serveRhythm", capabilityVersion="0.1.0",
                                          provenance={"status": "estimated", "producer": "model:serve-rhythm@0.1.0",
                                                      "confidence": 0.62, "calibrationRequired": False,
                                                      "calibrationId": None, "benchmarkRef": None},
                                          status="proposed", reviewedBy=None, textRef="text-obs-01"),
        "observation.reviewed-cue": dict(base, observationId="obs-02", kind="cue", sourceId="camera-1",
                                         sourceTime={"startUs": 1_217_000_000, "endUs": 1_219_000_000},
                                         sessionTimeUs=1_217_000_000, syncRevision=SYNC_REVISION, eventRef="p-041",
                                         capabilityId=None, capabilityVersion=None,
                                         provenance={"status": "reviewed", "producer": "coach", "confidence": None,
                                                     "calibrationRequired": False, "calibrationId": None,
                                                     "benchmarkRef": None},
                                         status="accepted", reviewedBy="coach", textRef="cue-03"),
        "observation.calibrated-bounce": dict(base, observationId="obs-03", kind="bounce", sourceId="camera-1",
                                              sourceTime={"startUs": 1_218_200_000, "endUs": 1_218_216_667},
                                              sessionTimeUs=None, syncRevision=None, eventRef="p-041",
                                              capabilityId="court.bounceLocation", capabilityVersion="0.1.0",
                                              provenance={"status": "estimated", "producer": "rule:homography-bounce@0.1.0",
                                                          "confidence": 0.4, "calibrationRequired": True,
                                                          "calibrationId": "cal-01", "benchmarkRef": None},
                                              status="proposed", reviewedBy=None, textRef=None),
    }


def lessons():
    def clip(cid, keeper=None, session="session-0909", label=None, status="available"):
        return {"clipId": cid, "sourceId": "camera-1", "sessionId": session, "keeperId": keeper, "window": None,
                "status": status, "label": label}

    def lesson(lid, date, title, focus, clips, notes, cues, practice, goal, films=()):
        return {"schemaVersion": "jovra.lesson/1", "lessonId": lid, "sample": True, "date": date, "title": title,
                "focus": focus, "coach": {"displayName": "Coach (Sample)"}, "sessionIds": sorted({c["sessionId"] for c in clips}),
                "notes": notes, "clips": clips, "cues": cues, "practice": practice, "nextGoal": goal,
                "filmIds": list(films), "share": {"mode": "private", "grantIds": []}}
    l1 = lesson("lesson-0909", "2026-09-09", "First serve foundation", "Find the rhythm",
                [clip(f"l1-clip-{i}") for i in range(1, 5)],
                [{"noteId": "l1-note-1", "author": "user", "text": "Toss drifted right on most serves.",
                  "provenance": "manual", "clipIds": ["l1-clip-1", "l1-clip-2"], "createdAt": "2026-09-09T18:00:00Z"}],
                [], [{"itemId": "l1-p1", "label": "Shadow serves", "unit": "reps", "target": 10, "done": 10,
                      "status": "done"}], "Repeat the routine")
    l2 = lesson("lesson-0923", "2026-09-23", "Recovery step", "Repeat the routine",
                [clip("l2-clip-1", session="session-0923"), clip("l2-clip-2", session="session-0923")],
                [{"noteId": "note-lesson-2", "author": "coach", "text": "Split step as the ball crosses the net.",
                  "provenance": "manual", "clipIds": ["l2-clip-1"], "createdAt": "2026-09-23T18:00:00Z"}],
                [], [], "Trust the motion")
    l3 = lesson("lesson-1007", "2026-10-07", "Serve rhythm", "Same toss. Calm finish.",
                [clip("l3-clip-1", keeper="k-02", session="session-1007"),
                 clip("l3-clip-2", session="session-1007"),
                 clip("l3-clip-3", session="session-1007", label="Clip 3")],
                [{"noteId": "l3-note-1", "author": "coach", "text": "Calm setup", "provenance": "reviewed",
                  "clipIds": ["l3-clip-3"], "createdAt": "2026-10-07T18:00:00Z"},
                 {"noteId": "l3-note-2", "author": "coach", "text": "Finish balanced", "provenance": "reviewed",
                  "clipIds": ["l3-clip-3"], "createdAt": "2026-10-07T18:01:00Z"}],
                [{"cueId": "cue-03", "text": "Calm setup", "clipId": "l3-clip-3", "observationId": "obs-02",
                  "provenance": "reviewed", "reviewedBy": "coach"},
                 {"cueId": "cue-04", "text": "Toss slightly in front", "clipId": "l3-clip-1", "observationId": "obs-01",
                  "provenance": "estimated", "reviewedBy": None}],
                [{"itemId": "l3-p1", "label": "Shadow serves", "unit": "reps", "target": 10, "done": 10, "status": "done"},
                 {"itemId": "l3-p2", "label": "Target serves", "unit": "reps", "target": 20, "done": 20, "status": "done"},
                 {"itemId": "l3-p3", "label": "Review clips", "unit": "clips", "target": 5, "done": 0, "status": "pending"}],
                "Keep the toss in front for a full set")
    return {"lesson.2026-09-09": l1, "lesson.2026-09-23": l2, "lesson.2026-10-07": l3}


def camera_invites():
    fp = fake_sha("host-tls-key")
    return {
        "schemaVersion": "jovra.camera-invite/1", "projectId": PROJECT, "sample": True, "environment": "test",
        "hostDeviceId": "device-jon", "maxCameras": 6,
        "roles": [
            {"slot": "near-baseline", "role": "primary", "deviceId": "device-jon", "deviceLabel": "Jon's iPhone",
             "status": "ready", "recordingAcknowledged": True,
             "permissions": ["record-local", "upload-own-source", "view-own-preview", "host-controls"]},
            {"slot": "far-baseline", "role": "camera", "deviceId": "device-alex", "deviceLabel": "Alex's phone",
             "status": "ready", "recordingAcknowledged": True,
             "permissions": ["record-local", "upload-own-source", "view-own-preview"]},
            {"slot": "near-left-corner", "role": "camera", "deviceId": None, "deviceLabel": "Corner left",
             "status": "waiting", "recordingAcknowledged": False, "permissions": ["record-local", "upload-own-source"]},
        ],
        "invites": [
            {"inviteId": "inv-2", "displayCode": "JVR-417", "slot": "far-baseline", "role": "camera",
             "issuedAt": "2026-10-07T20:50:00Z", "expiresAt": "2026-10-07T21:00:00Z", "singleUse": True,
             "hostApprovalRequired": True, "tlsFingerprintSha256": fp, "status": "accepted",
             "acceptedAt": "2026-10-07T20:52:10Z", "deviceId": "device-alex"},
            {"inviteId": "inv-3", "displayCode": "JVR-482", "slot": "near-left-corner", "role": "camera",
             "issuedAt": "2026-10-07T20:55:00Z", "expiresAt": "2026-10-07T21:05:00Z", "singleUse": True,
             "hostApprovalRequired": True, "tlsFingerprintSha256": fp, "status": "issued", "acceptedAt": None,
             "deviceId": None},
        ],
    }


def storage_providers():
    none_ops = {"exportFiles": False, "importFiles": False, "archiveSidecar": False, "resume": False, "quota": False}

    def prov(name, status, integration, ios, android, ops):
        return {"provider": name, "status": status, "integration": integration,
                "platforms": {"ios": ios, "android": android}, "operations": ops, "credentialRef": None,
                "folderRef": None, "processing": False, "lastVerifiedAt": None}
    return {"schemaVersion": "jovra.storage-providers/1", "sample": True, "environment": "demo", "providers": [
        prov("device", "active", "local", True, True,
             {"exportFiles": True, "importFiles": True, "archiveSidecar": True, "resume": True, "quota": True}),
        prov("icloud-drive-files", "choose-folder", "files-picker", True, False,
             {"exportFiles": True, "importFiles": True, "archiveSidecar": True, "resume": False, "quota": False}),
        prov("google-drive", "not-connected", "oauth-planned", True, True, dict(none_ops)),
        prov("box", "planned", "oauth-planned", True, True, dict(none_ops)),
        prov("dropbox", "planned", "oauth-planned", True, True, dict(none_ops)),
    ]}


def reference_catalog():
    """The trusted index the EDLs and briefs resolve their ids against (a projection of event log, lessons, notes,
    consents and rights; fictional Sample data)."""
    def ref(rid, kind, prov, record_kind, record_id=None):
        return {"refId": rid, "kind": kind, "provenance": prov, "eventRevision": EVENT_REVISION,
                "origin": {"recordKind": record_kind, "recordId": record_id or rid}}
    return {
        "schemaVersion": "jovra.reference-catalog/1", "projectId": PROJECT, "revision": 1, "sample": True,
        "eventRevision": EVENT_REVISION,
        "references": [
            ref("p-041", "score", "reviewed", "point-event"),
            ref("p-090", "score", "manual", "point-event"),
            ref("game-07", "score", "reviewed", "score-state"),
            ref("game-08", "score", "reviewed", "score-state"),
            ref("stat-first-serve-in", "metric", "reviewed", "stat"),
            ref("note-caption", "note", "manual", "user-note"),
            ref("note-goal", "note", "manual", "user-note"),
            ref("note-drill", "note", "manual", "user-note"),
            ref("note-next", "note", "manual", "user-note"),
            ref("note-players", "note", "manual", "user-note"),
            ref("note-lesson-2", "note", "manual", "lesson-note"),
            ref("l3-note-1", "note", "reviewed", "lesson-note"),
            ref("l3-note-2", "note", "reviewed", "lesson-note"),
            ref("ann-01", "annotation", "reviewed", "annotation"),
            ref("cue-03", "cue", "reviewed", "lesson-cue"),
            ref("cue-04", "cue", "estimated", "lesson-cue"),
        ],
        "consents": [{"consentRecordId": "consent-voice-jon", "participantId": "jon", "scope": ["narration-voice"],
                      "granted": True, "at": "2026-10-07T22:20:00Z"}],
        "rights": [{"rightsRecordId": "rights-track-01", "assetId": "track-01", "holder": "licensor",
                    "scope": ["private-film"]}],
    }


def quotes(final_plan, queue_plan):
    sample_quote = {
        "schemaVersion": "jovra.quote/1", "quoteId": "quote-sample-37", "projectId": PROJECT, "environment": "demo",
        "sample": True, "illustrative": True, "planRevision": 1, "outputSpecSha256": output_spec_hash(queue_plan),
        "inputsSha256": fake_sha("quote-37-inputs"),
        "filmClass": "story-2-3", "estimate": {"minCredits": 2, "maxCredits": 4}, "capCredits": 4,
        "estimatedMaxCostMicroUsd": 1_290_000, "creditCostBudgetMicroUsd": 800_000,
        "lineItems": {"sourceCount": 3, "uploadBytes": 10_800_000_000, "storageDays": 7, "outputSeconds": 300,
                      "renderMinutesEstimate": 30, "plannerTokensEstimate": 120_000},
        "retentionDays": 7,
        "displayAmounts": {"currency": "USD", "minMinor": 400, "maxMinor": 800, "capMinor": 1200, "illustrative": True},
        "createdAt": "2026-10-07T22:45:00Z", "expiresAt": "2026-10-07T23:15:00Z", "status": "open",
        "acceptedAt": None, "consent": None,
    }
    accepted = dict(sample_quote, quoteId="quote-test-01", environment="test", illustrative=False,
                    displayAmounts=None, inputsSha256=fake_sha("quote-01-inputs"), planRevision=2,
                    outputSpecSha256=output_spec_hash(final_plan),
                    lineItems=dict(sample_quote["lineItems"], outputSeconds=258), status="accepted",
                    acceptedAt="2026-10-07T22:50:00Z",
                    consent={"consentRecordId": "consent-upload-01", "uploadSelectedSources": True,
                             "at": "2026-10-07T22:49:30Z"})
    queue = dict(accepted, quoteId="quote-test-00", planRevision=1, inputsSha256=fake_sha("quote-00-inputs"),
                 outputSpecSha256=output_spec_hash(queue_plan),
                 acceptedAt="2026-10-07T22:49:50Z",
                 consent=dict(accepted["consent"], consentRecordId="consent-upload-00"))
    return {"quote.sample-illustrative": sample_quote, "quote.accepted": accepted, "quote.accepted-storyboard": queue}


def reservations(final_plan, queue_plan):
    settled = {
        "schemaVersion": "jovra.usage-reservation/1", "reservationId": "res-0002", "projectId": PROJECT,
        "jobId": "job-film-01", "quoteId": "quote-test-01", "environment": "test", "sample": True,
        "idempotencyKey": {"projectId": PROJECT, "planRevision": 2, "outputSpecSha256": output_spec_hash(final_plan)},
        "capCredits": 4, "reservedCredits": 4, "consumedCredits": 3, "releasedCredits": 1, "status": "settled",
        "entries": [
            {"entryId": "e-1", "kind": "reserve", "credits": 4, "key": f"reserve:{PROJECT}:2:{output_spec_hash(final_plan)}",
             "at": "2026-10-07T22:50:05Z"},
            {"entryId": "e-2", "kind": "consume", "credits": 1, "key": "consume:job-film-01:normalizing:1", "at": "2026-10-07T23:05:00Z"},
            {"entryId": "e-3", "kind": "consume", "credits": 1, "key": "consume:job-film-01:preview_rendering:1", "at": "2026-10-07T23:20:00Z"},
            {"entryId": "e-4", "kind": "consume", "credits": 1, "key": "consume:job-film-01:final_rendering:2", "at": "2026-10-07T23:40:00Z"},
            {"entryId": "e-5", "kind": "release", "credits": 1, "key": "release:job-film-01:ready", "at": "2026-10-07T23:50:00Z"},
        ],
        "createdAt": "2026-10-07T22:50:05Z",
    }
    held = {
        "schemaVersion": "jovra.usage-reservation/1", "reservationId": "res-0001", "projectId": PROJECT,
        "jobId": "job-queue-38", "quoteId": "quote-test-00", "environment": "test", "sample": True,
        "idempotencyKey": {"projectId": PROJECT, "planRevision": queue_plan["planRevision"],
                           "outputSpecSha256": output_spec_hash(queue_plan)},
        "capCredits": 4, "reservedCredits": 4, "consumedCredits": 2, "releasedCredits": 0, "status": "held",
        "entries": [
            {"entryId": "e-1", "kind": "reserve", "credits": 4,
             "key": f"reserve:{PROJECT}:{queue_plan['planRevision']}:{output_spec_hash(queue_plan)}",
             "at": "2026-10-07T22:50:05Z"},
            {"entryId": "e-2", "kind": "consume", "credits": 1, "key": "consume:job-queue-38:normalizing:1", "at": "2026-10-07T23:05:00Z"},
            {"entryId": "e-3", "kind": "consume", "credits": 1, "key": "consume:job-queue-38:syncing:1", "at": "2026-10-07T23:09:00Z"},
        ],
        "createdAt": "2026-10-07T22:50:05Z",
    }
    return {"usage-reservation.settled": settled, "usage-reservation.held": held}


def history(steps):
    out = [{"seq": 0, "from": None, "to": "draft", "at": "2026-10-07T22:44:00Z", "reason": "created"}]
    prev = "draft"
    for i, (to, at, reason) in enumerate(steps, start=1):
        out.append({"seq": i, "from": prev, "to": to, "at": at, "reason": reason})
        prev = to
    return out


def render_jobs(final_plan, queue_plan):
    queue = {
        "schemaVersion": "jovra.render-job/1", "jobId": "job-queue-38", "projectId": PROJECT, "environment": "test",
        "sample": True, "planId": queue_plan["planId"], "planRevision": queue_plan["planRevision"],
        "quoteId": "quote-test-00", "reservationId": "res-0001", "idempotencyKey": output_spec_hash(queue_plan),
        "state": "preview_rendering", "resumeStage": None, "attempt": 1, "maxAttempts": 3,
        "stageProgress": {"stage": "preview_rendering", "percent": 42, "sample": True},
        "deliveredArtifactIds": [],
        "history": history([
            ("quoted", "2026-10-07T22:45:00Z", "preflight"), ("consented", "2026-10-07T22:50:00Z", "owner-accepted"),
            ("upload_pending", "2026-10-07T22:50:05Z", "reserved"), ("uploading", "2026-10-07T22:51:00Z", "upload-started"),
            ("queued", "2026-10-07T23:03:00Z", "sources-verified"), ("normalizing", "2026-10-07T23:04:00Z", "stage-start"),
            ("syncing", "2026-10-07T23:08:00Z", "stage-start"),
            ("planning", "2026-10-07T23:12:00Z", "analysis-unavailable-manual-fallback"),
            ("preview_rendering", "2026-10-07T23:13:00Z", "plan-valid"),
        ]),
    }
    done = {
        "schemaVersion": "jovra.render-job/1", "jobId": "job-film-01", "projectId": PROJECT, "environment": "test",
        "sample": True, "planId": final_plan["planId"], "planRevision": final_plan["planRevision"],
        "quoteId": "quote-test-01", "reservationId": "res-0002", "idempotencyKey": output_spec_hash(final_plan),
        "state": "ready", "resumeStage": None, "attempt": 2, "maxAttempts": 3, "stageProgress": None,
        "deliveredArtifactIds": ["film-court-memories"],
        "history": history([
            ("quoted", "2026-10-07T22:45:00Z", "preflight"), ("consented", "2026-10-07T22:50:00Z", "owner-accepted"),
            ("upload_pending", "2026-10-07T22:50:05Z", "reserved"), ("uploading", "2026-10-07T22:51:00Z", "upload-started"),
            ("paused", "2026-10-07T22:55:00Z", "owner-paused"), ("uploading", "2026-10-07T22:58:00Z", "owner-resumed"),
            ("queued", "2026-10-07T23:03:00Z", "sources-verified"), ("normalizing", "2026-10-07T23:04:00Z", "stage-start"),
            ("syncing", "2026-10-07T23:08:00Z", "stage-start"), ("analyzing", "2026-10-07T23:10:00Z", "stage-start"),
            ("planning", "2026-10-07T23:14:00Z", "stage-start"), ("preview_rendering", "2026-10-07T23:15:00Z", "plan-valid"),
            ("awaiting_review", "2026-10-07T23:22:00Z", "preview-ready"),
            ("final_rendering", "2026-10-07T23:30:00Z", "owner-approved"),
            ("failed_retryable", "2026-10-07T23:33:00Z", "lease-lost"),
            ("final_rendering", "2026-10-07T23:34:00Z", "retry"), ("verifying", "2026-10-07T23:44:00Z", "render-done"),
            ("ready", "2026-10-07T23:49:00Z", "verification-passed"),
        ]),
    }
    return {"render-job.queue-sample": queue, "render-job.ready": done}


def delivered_artifact(final_plan):
    total = final_plan["output"]["totalFrames"]
    chapters = final_plan["chapters"]
    bounds = [c["outputInFrame"] for c in chapters] + [total]
    return {
        "schemaVersion": "jovra.delivered-artifact/1", "artifactId": "film-court-memories", "projectId": PROJECT,
        "jobId": "job-film-01", "environment": "test", "sample": True, "kind": "film", "variant": "primary",
        "titleText": "A good day on court",
        "renderer": {"kind": "ffmpeg", "version": "jovra-render-ffmpeg@0.1.0"},
        "media": {"container": "mp4", "videoCodec": "h264", "audioCodec": "aac", "width": 1920, "height": 1080,
                  "fps": FPS30, "durationFrames": total, "audioSampleCount": total * 48000 // 30,
                  "sizeBytes": 412_000_000, "sha256": fake_sha("film-court-memories")},
        "chapters": [{"id": c["id"], "templateId": c["templateId"], "startFrame": a, "endFrame": b}
                     for c, a, b in zip(chapters, bounds, bounds[1:])],
        "captions": None,
        "bindings": {"sourceSha256s": [s["sha256"] for s in final_plan["sources"]],
                     "sourceManifestRevision": MANIFEST_REVISION, "syncRevision": SYNC_REVISION,
                     "eventRevision": EVENT_REVISION, "profile": {"id": "court-memories", "revision": 1},
                     "planner": {"kind": "heuristic", "modelId": None},
                     "editPlanSha256": canonical_sha256(final_plan), "storyBriefRevision": 1},
        "verification": {"status": "passed", "probe": "passed", "fullDecode": "passed", "frameCount": "passed",
                         "audio": "passed", "overlayProvenance": "passed", "checkedAt": "2026-10-07T23:48:30Z"},
        "delivery": {"visibility": "private",
                     "shareLink": {"grantId": "grant-01", "issuedAt": "2026-10-07T23:50:00Z",
                                   "expiresAt": "2026-10-08T23:50:00Z"},
                     "retention": {"policy": "keep-until-deleted", "days": None}},
        "youtubePrep": {"prepared": True, "published": False},
        "stale": None,
    }
