"""RenderJob transition vectors, render-job invalid cases and checkers. Module page:
spec/studio/modules/jobstate.md.
"""

from __future__ import annotations

from studio import bundle as studio_bundle
from studio import jobstate
from studio.cases.patches import bad, invalid_docs, rep


# ----- job transitions ----------------------------------------------------------------------------

def job_vectors():
    def case(cid, frm, to, expect, **flags):
        c = {"id": cid, "from": frm, "to": to, "expect": expect}
        c.update(flags)
        return c
    cases = [
        case("draft-to-quoted", {"state": "draft"}, "quoted", {"state": "quoted", "resumeStage": None}),
        case("draft-to-ready", {"state": "draft"}, "ready", {"rejectCode": "illegalTransition"}),
        case("quote-expires", {"state": "quoted"}, "quote_expired", {"state": "quote_expired"}),
        case("expired-never-auto-accepted", {"state": "quote_expired"}, "consented", {"rejectCode": "illegalTransition"}),
        case("expired-requoted", {"state": "quote_expired"}, "quoted", {"state": "quoted", "resumeStage": None}),
        case("no-spend-without-reservation", {"state": "consented"}, "upload_pending",
             {"rejectCode": "reservationRequired"}, hasReservation=False),
        case("upload-paused", {"state": "uploading"}, "paused", {"state": "paused", "resumeStage": "uploading"}),
        case("pause-resumes-same-stage", {"state": "paused", "resumeStage": "uploading"}, "uploading",
             {"state": "uploading", "resumeStage": None, "attempt": 1}),
        case("pause-cannot-skip-ahead", {"state": "paused", "resumeStage": "uploading"}, "queued",
             {"rejectCode": "illegalTransition"}),
        case("render-fails-retryably", {"state": "final_rendering"}, "failed_retryable",
             {"state": "failed_retryable", "resumeStage": "final_rendering"}),
        case("retry-counts-attempt", {"state": "failed_retryable", "resumeStage": "final_rendering", "attempt": 1},
             "final_rendering", {"state": "final_rendering", "attempt": 2, "resumeStage": None}),
        case("retries-exhausted", {"state": "failed_retryable", "resumeStage": "final_rendering", "attempt": 3},
             "final_rendering", {"rejectCode": "retriesExhausted"}),
        case("retryable-to-terminal", {"state": "failed_retryable", "resumeStage": "verifying"}, "failed_terminal",
             {"state": "failed_terminal", "resumeStage": None}),
        case("ready-needs-verification", {"state": "verifying"}, "ready", {"rejectCode": "unverifiedReady"}),
        case("ready-after-verification", {"state": "verifying"}, "ready", {"state": "ready"}, verifiedArtifact=True),
        case("ready-is-terminal", {"state": "ready"}, "canceled", {"rejectCode": "terminalState"}),
        case("ready-can-be-deleted", {"state": "ready"}, "deleted", {"state": "deleted"}),
        case("deleted-is-final", {"state": "deleted"}, "deleted", {"rejectCode": "terminalState"}),
        case("budget-stops-stage", {"state": "normalizing"}, "budget_exceeded",
             {"state": "budget_exceeded", "resumeStage": "normalizing"}),
        case("budget-never-auto-raised", {"state": "budget_exceeded", "resumeStage": "normalizing"}, "normalizing",
             {"rejectCode": "illegalTransition"}),
        case("budget-requote", {"state": "budget_exceeded", "resumeStage": "normalizing"}, "quoted",
             {"state": "quoted", "resumeStage": None}),
        case("draft-cannot-pause", {"state": "draft"}, "paused", {"rejectCode": "illegalTransition"}),
        case("queued-cancel", {"state": "queued"}, "canceled", {"state": "canceled"}),
        case("review-is-not-retryable", {"state": "awaiting_review"}, "failed_retryable",
             {"rejectCode": "illegalTransition"}),
        case("analysis-unavailable-fallback", {"state": "syncing"}, "planning", {"state": "planning"}),
        case("sources-already-verified", {"state": "upload_pending"}, "queued", {"state": "queued"}),
        case("no-budget-check-at-upload", {"state": "uploading"}, "budget_exceeded", {"rejectCode": "illegalTransition"}),
        case("unknown-state", {"state": "draft"}, "published", {"rejectCode": "unknownState"}),
        case("paused-resume-to-ready-refused", {"state": "paused", "resumeStage": "ready"}, "ready",
             {"rejectCode": "badResumeStage"}, verifiedArtifact=True),
        case("retry-resume-to-ready-refused", {"state": "failed_retryable", "resumeStage": "ready"}, "ready",
             {"rejectCode": "badResumeStage"}, verifiedArtifact=True),
        case("retry-resume-to-deleted-refused", {"state": "failed_retryable", "resumeStage": "deleted"}, "canceled",
             {"rejectCode": "badResumeStage"}),
        case("stray-resume-stage-refused", {"state": "queued", "resumeStage": "normalizing"}, "normalizing",
             {"rejectCode": "badResumeStage"}),
    ]
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "job-transitions",
            "status": "hand-written expectations from the backend brief's state machine; defaults: resumeStage null, "
                      "attempt 1, maxAttempts 3, hasReservation true, verifiedArtifact false", "cases": cases}



# ----- invalid cases ------------------------------------------------------------------------------

def invalid_sets(P, plans):
    sets = {}
    sets["render-job.ready"] = [
        bad("state-not-from-history", "The stored state must be where the history leads", [rep("/state", "verifying")],
            "stateMismatch"),
        bad("ready-without-artifact", "Ready needs a verified delivered artifact", [rep("/deliveredArtifactIds", [])],
            "unverifiedReady"),
        bad("spend-without-reservation", "Paid stages need a reservation", [rep("/reservationId", None)], "reservationRequired"),
        bad("retry-not-counted", "A retry consumes an attempt", [rep("/attempt", 1)], "stateMismatch"),
        bad("ghost-artifact", "An artifact id that resolves to no verified film is not a verified film",
            [rep("/deliveredArtifactIds", ["ghost-film"])], "unverifiedReady"),
        bad("resume-to-ready", "A stored resume stage can never be ready", [rep("/resumeStage", "ready")]),
    ]
    sets["render-job.queue-sample"] = [
        bad("progress-for-other-stage", "Progress is reported for the active stage only",
            [rep("/stageProgress/stage", "final_rendering")], "stateMismatch"),
        bad("skip-to-final", "syncing -> final_rendering skips planning and preview", [rep("/history/8/to", "final_rendering")],
            "illegalTransition"),
    ]
    return invalid_docs(sets)


# ----- what this module declares and registers ----------------------------------------------------

def fixtures(sample):
    docs = {"vectors/job-transitions.json": job_vectors()}
    for name, doc in invalid_sets(sample.P, sample.plans).items():
        docs[f"invalid/{name}.invalid.json"] = doc
    return docs


def check_job_vector(ctx, case, report, where) -> None:
    jobstate.run_vector(ctx.machine, case)
    report.ok("job-transition vectors")


def check_render_job(ctx, doc):
    # resolved against the delivered artifacts: a non-empty id list is not a verified film
    return ctx.machine.replay(doc, verified_artifact=studio_bundle.verified_artifact_for(doc, ctx.bundle["artifacts"]))


VECTOR_CHECKERS = {"job-transitions": check_job_vector}
SCHEMAS = {"jovra.render-job/1": "render-job.schema.json",
           "jovra.render-job-transitions/1": "contracts.schema.json"}
RECORD_RULES = {"jovra.render-job/1": check_render_job}
