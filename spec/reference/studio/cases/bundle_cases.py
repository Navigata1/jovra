"""Implementation-states sample truth for the sample project, and its checker. Module page:
spec/studio/modules/bundle.md.
"""

from __future__ import annotations

import copy
from fractions import Fraction

from studio import bundle, syncfit
from studio.core import Reject, delta_pp_display, pct, round_half_up


def sample_truth_vectors():
    cases = [
        {"id": "sync-offset-drift", "kind": "sync", "record": "records/sync-map.json", "sourceId": "camera-2",
         "offsetMs": 120, "driftMsPerMin": 18, "driftPpm": 300},
        {"id": "progress-delta", "kind": "progress", "record": "records/story-brief.progress.json",
         "before": [12, 30], "after": [18, 30], "beforePct": 40, "afterPct": 60, "delta": "+20 percentage points"},
        {"id": "court-memories-length", "kind": "chapters", "record": "records/delivered-artifact.film.json",
         "chapterSeconds": [42, 141, 75], "totalSeconds": 258, "display": "04:18", "height": 1080,
         "sizeBytes": 412_000_000},
        {"id": "storyboard-window", "kind": "window", "record": "records/edit-plan.court-memories-storyboard.json",
         "segmentId": "s02", "sourceStartMs": 12_400, "sourceEndMs": 18_600, "outputStartMs": 12_000,
         "outputEndMs": 18_200, "durationMs": 6_200},
        {"id": "import-size", "kind": "import", "record": "records/source-manifest.json", "sources": 3, "minutes": 60,
         "megabitsPerSecond": 8, "perSourceBytes": 3_600_000_000, "totalBytes": 10_800_000_000},
        {"id": "six-angle-upload-time", "kind": "upload", "bytes": 21_600_000_000, "megabitsPerSecond": 20,
         "seconds": 8_640, "minutes": 144},
        {"id": "seven-day-raw-storage", "kind": "storage", "gigabytes": "21.6", "days": 7,
         "usdPerGbMonth": "0.015", "microUsd": 75_600},
        {"id": "queue-stage-progress", "kind": "queue", "record": "records/render-job.queue-sample.json",
         "stage": "preview_rendering", "percent": 42},
        {"id": "lesson-clip-counts", "kind": "lessons",
         "records": ["records/lesson.2026-09-09.json", "records/lesson.2026-09-23.json", "records/lesson.2026-10-07.json"],
         "clipCounts": [4, 2, 3], "practice": {"done": [10, 20], "pendingClipGoal": 5}},
        {"id": "illustrative-quote", "kind": "quote", "record": "records/quote.sample-illustrative.json",
         "minUsd": 4, "maxUsd": 8, "capUsd": 12},
    ]
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "sample-truth",
            "status": "numbers copied by hand from design-reference/studio/brief/implementation-states.md and "
                      "backend-media-design.md; all Sample, none measured", "cases": cases}




# ----- what this module declares and registers ----------------------------------------------------

def fixtures(sample):
    return {"vectors/sample-truth.json": sample_truth_vectors()}


def check_sample_truth(ctx, case, report, where) -> None:
    kind = case["kind"]
    rec = ctx.fixture(case["record"]) if "record" in case else None
    ok = True
    if kind == "sync":
        t = [s for s in rec["sources"] if s["sourceId"] == case["sourceId"]][0]["pieces"][0]["transform"]
        ok = (round_half_up(Fraction(t["offsetUs"], 1000)) == case["offsetMs"]
              and round_half_up(syncfit.drift_ms_per_min(t)) == case["driftMsPerMin"]
              and round_half_up(Fraction(t["rate"]["num"] - t["rate"]["den"], 1000)) == case["driftPpm"])
    elif kind == "progress":
        b, a = case["before"], case["after"]
        cmp = rec["comparisons"][0]
        ok = (pct(*b) == case["beforePct"] and pct(*a) == case["afterPct"]
              and delta_pp_display(pct(*b), pct(*a)) == case["delta"] == cmp["display"]["delta"]
              and [cmp["before"]["numerator"], cmp["before"]["denominator"]] == b
              and [cmp["after"]["numerator"], cmp["after"]["denominator"]] == a)
    elif kind == "chapters":
        fps = Fraction(rec["media"]["fps"]["num"], rec["media"]["fps"]["den"])
        secs = [Fraction(c["endFrame"] - c["startFrame"]) / fps for c in rec["chapters"]]
        total = sum(case["chapterSeconds"])
        ok = (secs == case["chapterSeconds"] and total == case["totalSeconds"]
              and f"{total // 60:02d}:{total % 60:02d}" == case["display"]
              and Fraction(rec["media"]["durationFrames"]) / fps == total
              and rec["media"]["height"] == case["height"] and rec["media"]["sizeBytes"] == case["sizeBytes"])
    elif kind == "window":
        seg = [s for s in rec["segments"] if s["id"] == case["segmentId"]][0]
        src = [s for s in rec["sources"] if s["id"] == seg["sourceId"]][0]["proxy"]["fps"]
        out = rec["output"]["fps"]

        def ms(frames, fps):
            return Fraction(frames * 1000 * fps["den"], fps["num"])
        ok = (ms(seg["sourceInFrame"], src) == case["sourceStartMs"] and ms(seg["sourceOutFrame"], src) == case["sourceEndMs"]
              and ms(seg["outputInFrame"], out) == case["outputStartMs"] and ms(seg["outputOutFrame"], out) == case["outputEndMs"]
              and case["sourceEndMs"] - case["sourceStartMs"] == case["durationMs"]
              == case["outputEndMs"] - case["outputStartMs"])
    elif kind == "import":
        per = case["megabitsPerSecond"] * 1_000_000 * case["minutes"] * 60 // 8
        match = [s for s in rec["sources"] if s["role"] == "match"]
        ok = (per == case["perSourceBytes"] and per * case["sources"] == case["totalBytes"]
              and len(match) == case["sources"] and sum(s["original"]["sizeBytes"] for s in match) == case["totalBytes"])
    elif kind == "upload":
        secs = Fraction(case["bytes"] * 8, case["megabitsPerSecond"] * 1_000_000)
        ok = secs == case["seconds"] and secs / 60 == case["minutes"]
    elif kind == "storage":
        usd = Fraction(case["gigabytes"]) * case["days"] / 30 * Fraction(case["usdPerGbMonth"])
        ok = usd * 1_000_000 == case["microUsd"]
    elif kind == "queue":
        ok = rec["stageProgress"] == {"stage": case["stage"], "percent": case["percent"], "sample": True}
    elif kind == "lessons":
        docs = [ctx.fixture(r) for r in case["records"]]
        last = docs[-1]["practice"]
        ok = ([len(d["clips"]) for d in docs] == case["clipCounts"]
              and [p["done"] for p in last[:2]] == case["practice"]["done"]
              and last[2]["target"] == case["practice"]["pendingClipGoal"] and last[2]["status"] == "pending")
    elif kind == "quote":
        d = rec["displayAmounts"]
        ok = (d["minMinor"], d["maxMinor"], d["capMinor"]) == (case["minUsd"] * 100, case["maxUsd"] * 100,
                                                              case["capUsd"] * 100) and rec["illustrative"]
    else:
        ok = False
    if ok:
        report.ok("sample-truth vectors")
    else:
        report.fail(where, f"sample truth '{case['id']}' does not hold")


VECTOR_CHECKERS = {"sample-truth": check_sample_truth}


# ----- self-tests: the cross-record rules, and deliberate mutations of the Sample project that must fail ---------

def _plan(b, plan_id):
    return [p for p in b["plans"] if p["planId"] == plan_id][0]


def _unmapped_restart(b):
    # camera-2 restarted (a second recorded segment) but the sync map keeps only its first piece: the one piece
    # must never stand for the whole recording (the lock is re-pinned so only the sync rule can refuse it)
    src = b["manifest"]["sources"][1]
    seg1 = copy.deepcopy(src["segments"][0])
    seg1.update(segmentId="seg-1", index=1, reason="restart")
    src["segments"].append(seg1)
    b["lock"]["sourceManifest"]["sha256"] = bundle.canonical_sha256(b["manifest"])


def _topup_from_initial_quote(b):
    # one accepted quote funding two holds: the initial reserve and a top-up keyed by the same quote
    res = b["reservations"]["res-0002"]
    e0 = res["entries"][0]
    e0["credits"] = 2
    top = dict(e0, entryId="e-1b", key=e0["key"] + ":topup:" + res["initialQuoteId"])
    res["entries"].insert(1, top)


def _topup_leaves_initial_accepted(b):
    # a real top-up by a second quote, but the initial quote is still 'accepted' rather than superseded
    res = b["reservations"]["res-0002"]
    e0 = res["entries"][0]
    e0["credits"] = 2
    res["entries"].insert(1, dict(e0, entryId="e-1b", key=e0["key"] + ":topup:quote-test-02"))
    b["quotes"]["quote-test-02"] = dict(copy.deepcopy(b["quotes"]["quote-test-01"]), quoteId="quote-test-02")
    res["quoteId"] = "quote-test-02"
    b["jobs"]["job-film-01"]["quoteId"] = "quote-test-02"


# (label, expected reject code, mutation of a deep copy of the Sample project's records by role)
MUTATIONS = [
    ("restart-segment-unmapped", "unmappedSegment", _unmapped_restart),
    ("model-film-from-rules-quote", "plannerMismatch",
     lambda b: b["artifacts"][0]["bindings"]["planner"].update(kind="model", modelId="claude-opus-5-5")),
    ("topup-from-initial-quote", "moneyMismatch", _topup_from_initial_quote),
    ("topup-leaves-initial-quote-accepted", "moneyMismatch", _topup_leaves_initial_accepted),
    ("coverage-rate-tampered", "coverageMismatch",
     lambda b: _plan(b, "coach-cut-serve")["sources"][1]["coverage"][0]["rate"].update(num=1_000_000_000)),
    ("sync-not-reviewed", "unreviewedSync",
     lambda b: b["syncMap"]["sources"][1]["pieces"][0].update(state="needs-review")),
    ("film-bound-to-missing-plan", "unknownPlan",
     lambda b: b["artifacts"][0]["bindings"].update(editPlanSha256="0" * 64)),
    ("lock-manifest-hash", "lockMismatch", lambda b: b["lock"]["sourceManifest"].update(sha256="1" * 64)),
    ("contact-unprotected", "contactUnprotected",
     lambda b: _plan(b, "court-memories-storyboard")["segments"][2].update(protectedFrames=[])),
    ("clean-alternate-drift", "cleanAlternateMismatch",
     lambda b: _plan(b, "rally-pulse-portrait-clean")["segments"][0].update(framing={"mode": "fill"})),
    ("reservation-of-other-plan", "moneyMismatch",
     lambda b: b["reservations"]["res-0002"]["idempotencyKey"].update(planRevision=1)),
    ("cue-provenance-laundered", "provenanceMismatch",
     lambda b: [x for x in b["lessons"] if x["lessonId"] == "lesson-1007"][0]["cues"][1].update(provenance="reviewed")),
    ("job-lists-ghost-artifact", "unknownArtifact",
     lambda b: b["jobs"]["job-film-01"].update(deliveredArtifactIds=["film-court-memories", "ghost-film"])),
    ("ready-film-unverified", "unverifiedReady",
     lambda b: b["artifacts"][0]["verification"].update(status="pending")),
    ("quote-bound-to-other-output", "moneyMismatch",
     lambda b: b["quotes"]["quote-test-01"].update(outputSpecSha256="c" * 64)),
    ("catalog-cue-laundered", "provenanceMismatch",
     lambda b: [r for r in b["references"]["references"] if r["refId"] == "cue-04"][0].update(provenance="reviewed")),
    ("consent-of-unknown-participant", "unknownParticipant",
     lambda b: b["references"]["consents"][0].update(participantId="nobody")),
    ("reservation-entry-of-other-job", "moneyMismatch",
     lambda b: b["reservations"]["res-0002"]["entries"][1].update(key="consume:job-queue-38:normalizing:1")),
    ("brief-overlay-unresolved", "untrustedReference",
     lambda b: [x for x in b["briefs"] if x["briefId"] == "brief-court-memories"][0]["beats"][2]["overlays"][0]
     .update(refId="6-4")),
]


def check_cross_record(ctx, report) -> None:
    """bundle.check_all accepts the Sample project, and refuses every mutation in MUTATIONS with its code."""
    try:
        counts = bundle.check_all(ctx.bundle)
        report.ok("cross-record checks")
        report.log(f"bundle {counts}")
    except Reject as exc:
        report.fail("bundle", str(exc))
        return
    for label, code, mutate in MUTATIONS:
        b = copy.deepcopy(ctx.bundle)
        mutate(b)
        try:
            bundle.expect_reject(lambda: bundle.check_all(b), code)
            report.ok("cross-record mutations rejected")
        except Reject as exc:
            report.fail(f"bundle mutation {label}", str(exc))


SELF_TESTS = {"bundle-cross-record": check_cross_record}
