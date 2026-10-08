"""Vectors and invalid cases for spec/studio/fixtures (imported by generate_studio_fixtures.py).

Vector "expect" blocks come from the reference; "assert" blocks are hand-derived from the research and
implementation-states.md and are checked independently by scripts/spec/validate_studio.py.
"""

from __future__ import annotations

from fractions import Fraction

import copy

from studio import edl, syncfit
from studio.core import Reject, apply_patch, round_half_up

import generate_studio_fixtures as g

HOUR = g.HOUR_US


# ----- sync-fit vectors ---------------------------------------------------------------------------

def _fit_case(cid, why, pieces, *, src, ref, assertions, hints=None, out_fps=None):
    out_fps = out_fps or g.FPS30
    inp = {"pieces": pieces, "sourcePosition": g.POS[src], "referencePosition": g.POS[ref], "mmPerSecond": 343_000,
           "outputFps": out_fps, "hints": hints or {}}
    expect = syncfit.fit_device(pieces, source_position=g.POS[src], reference_position=g.POS[ref],
                                c_mm_per_s=343_000, output_fps=out_fps, hints=hints)
    return {"id": cid, "why": why, "input": inp, "expect": expect, "assert": assertions}


def sync_vectors():
    cases = []
    ui = g.synth_anchors(offset=120_000, rate=Fraction(10003, 10000), events=g.camera2_events(), src_pos=g.POS["BN"],
                         ref_pos=g.POS["BS"], prefix="ui")
    cases.append(_fit_case("ui-sample-120ms-18ms-per-min",
                           "Screen 26 sample: Camera 2 +120 ms, 18 ms/min (300 ppm, a stress value), geometry-corrected",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": ui}], src="BN", ref="BS",
                           assertions={"state": ["estimated"], "offsetUsWithin": [[118_000, 122_000]],
                                       "driftPpbWithin": [298_000, 302_000], "driftMsPerMinRounded": 18,
                                       "residualMaxUsAtMost": 16_667, "reviewable": True}))
    exact = [(10_000_000 + i * 60_000_000, "visual", "serve-contact", None) for i in range(10)]
    a = g.synth_anchors(offset=500_000, rate=Fraction(1), events=exact, src_pos=g.POS["CSE"], ref_pos=g.POS["BS"],
                        prefix="s1", noise=False)
    cases.append(_fit_case("s1-offset-only-30fps", "Two views, offset only, exact visual anchors (research S1)",
                           [{"segmentId": "seg-0", "sourceDurationUs": 600_000_000, "anchors": a}], src="CSE", ref="BS",
                           assertions={"state": ["estimated"], "offsetUsWithin": [[500_000, 500_000]],
                                       "driftPpbWithin": [0, 0], "residualMaxUsAtMost": 0}))
    ev = [(30_000_000 + i * 290_000_000, "visual", "serve-contact", None) for i in range(12)]
    a = g.synth_anchors(offset=250_000, rate=Fraction(1_000_020, 1_000_000), events=ev, src_pos=g.POS["CSE"],
                        ref_pos=g.POS["BS"], prefix="s2")
    cases.append(_fit_case("s2-drift-20ppm-60min", "20 ppm over 60 min recovered within 3 ppm (research S2)",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="CSE", ref="BS",
                           assertions={"state": ["estimated"], "driftPpbWithin": [17_000, 23_000],
                                       "residualMaxUsAtMost": 16_667}))
    ev = [(40_000_000 + i * 280_000_000, "audio", "impact", g.SOUTH_BASELINE if i % 2 else g.NORTH_BASELINE)
          for i in range(12)]
    a = g.synth_anchors(offset=120_000, rate=Fraction(1), events=ev, src_pos=g.POS["BN"], ref_pos=g.POS["BS"],
                        prefix="s5", corrected=False)
    cases.append(_fit_case("s5-opposite-baselines-uncorrected",
                           "Audio only between opposite baselines without geometry: about +/-69 ms bias by hitter; "
                           "never auto-approved (research S5)",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="BN", ref="BS",
                           assertions={"state": ["needs-review"], "uncorrectedAudio": True,
                                       "residualMaxUsAtLeast": 30_000}))
    a = g.synth_anchors(offset=120_000, rate=Fraction(1), events=ev, src_pos=g.POS["BN"], ref_pos=g.POS["BS"],
                        prefix="s6")
    cases.append(_fit_case("s6-opposite-baselines-corrected",
                           "Same anchors with sound-travel correction from court positions (research S6)",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="BN", ref="BS",
                           assertions={"state": ["estimated"], "offsetUsWithin": [[119_000, 121_000]],
                                       "residualMaxUsAtMost": 1_000}))
    rate = Fraction(10003, 10000)
    seg0 = g.synth_anchors(offset=120_000, rate=rate, prefix="r0", src_pos=g.POS["CSE"], ref_pos=g.POS["BS"],
                           events=[(60_000_000 + i * 230_000_000, "visual", "serve-contact", None) for i in range(8)])
    seg1 = g.synth_anchors(offset=1_841_000_000, rate=rate, prefix="r1", src_pos=g.POS["CSE"], ref_pos=g.POS["BS"],
                           events=[(1_900_000_000 + i * 200_000_000, "visual", "serve-contact", None) for i in range(8)])
    cases.append(_fit_case("s8-restart-shared-slope",
                           "A restart after a 41 s gap: one rate per device, one offset per segment (research S8/S9)",
                           [{"segmentId": "seg-0", "sourceDurationUs": 1_800_000_000, "anchors": seg0},
                            {"segmentId": "seg-1", "sourceDurationUs": 1_700_000_000, "anchors": seg1}],
                           src="CSE", ref="BS",
                           assertions={"state": ["estimated", "estimated"], "sharedRate": True,
                                       "offsetUsWithin": [[118_000, 122_000], [1_839_000_000, 1_843_000_000]],
                                       "driftPpbWithin": [298_000, 302_000]}))
    a = g.synth_anchors(offset=900_000, rate=Fraction(1), src_pos=g.POS["CSE"], ref_pos=g.POS["BS"], prefix="s10",
                        events=[(100_000_000 + i * 700_000_000, "visual", "serve-contact", None) for i in range(5)])
    cases.append(_fit_case("s10-too-few-anchors", "Five anchors cannot be auto-approved",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="CSE", ref="BS",
                           assertions={"state": ["needs-review"], "reasonsInclude": "fewer than 8 inlier anchors"}))
    cases.append(_fit_case("hint-only", "No anchors: a capture hint gives a from-hints map, never estimated",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": []}], src="CSE", ref="BS",
                           hints={"seg-0": 3_000_000}, assertions={"state": ["from-hints"]}))
    cases.append(_fit_case("s14-no-anchors-no-hint", "No anchors and no hint (for example no shared coverage): the fit "
                           "fails and the angle is not offered; there is no separate no-overlap state",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": []}], src="CSE", ref="BS",
                           assertions={"state": ["failed"], "reviewable": False}))
    two = [{"id": "t-0", "kind": "serve-contact", "modality": "visual", "sourceTimeUs": 60_000_000,
            "referenceTimeUs": 60_250_000, "eventPositionMm": None},
           {"id": "t-1", "kind": "serve-contact", "modality": "visual", "sourceTimeUs": 3_540_000_000,
            "referenceTimeUs": 3_542_250_000, "eventPositionMm": None}]
    cases.append(_fit_case("two-anchors-outlier-undetectable",
                           "Two anchors over an hour, the second 2 s wrong: the line passes through both, so the error "
                           "is invisible; such a piece needs review and can never be marked reviewed",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": two}], src="CSE", ref="BS",
                           assertions={"state": ["needs-review"], "reasonsInclude": "fewer than 8 inlier anchors",
                                       "reviewable": False}))
    ev = [(50_000_000 + i * 340_000_000, "visual", "serve-contact", None) for i in range(10)]
    a = g.synth_anchors(offset=400_000, rate=Fraction(10_015, 10_000), events=ev, src_pos=g.POS["CSE"],
                        ref_pos=g.POS["BS"], prefix="hd", noise=False)
    cases.append(_fit_case("implausible-drift-1500ppm",
                           "1500 ppm is inside the 0.9-1.1 schema range but far beyond phone clocks (about 8 ppm): "
                           "flagged for review and never reviewable without re-anchoring",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="CSE", ref="BS",
                           assertions={"state": ["needs-review"], "driftPpbWithin": [1_499_000, 1_501_000],
                                       "reasonsInclude": "drift above 1000 ppm", "reviewable": False}))
    ev = [(50_000_000 + i * 340_000_000, "visual", "serve-contact", None) for i in range(10)]
    a = g.synth_anchors(offset=700_000, rate=Fraction(1_000_010, 1_000_000), events=ev, src_pos=g.POS["CSE"],
                        ref_pos=g.POS["BS"], prefix="s7")
    a.append({"id": "s7-mispaired", "kind": "serve-contact", "modality": "visual",
              "sourceTimeUs": a[4]["sourceTimeUs"] + 400_000, "referenceTimeUs": a[4]["referenceTimeUs"],
              "eventPositionMm": None})
    cases.append(_fit_case("s7-mispaired-anchor-trimmed",
                           "A rally-rhythm alias (+400 ms) is trimmed as an outlier and flagged for review",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="CSE", ref="BS",
                           assertions={"state": ["needs-review"], "nOutliers": 1,
                                       "offsetUsWithin": [[697_000, 703_000]]}))
    ev = [(30_000_000 + i * 290_000_000, "visual", "serve-contact", None) for i in range(12)]
    a = g.synth_anchors(offset=119_837, rate=Fraction(1_000_300_102, 1_000_000_000), events=ev, src_pos=g.POS["BN"],
                        ref_pos=g.POS["BS"], prefix="s5b")
    a[5] = dict(a[5], referenceTimeUs=a[5]["referenceTimeUs"] + 2_000_000)
    cases.append(_fit_case("s5b-gross-outlier-robust-start",
                           "One anchor 2 s off among 12 clean ones: the robust start trims only that anchor and keeps "
                           "the true offset (plain OLS first trimmed all 12 and still offered the map for review)",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="BN", ref="BS",
                           assertions={"state": ["needs-review"], "nOutliers": 1,
                                       "offsetUsWithin": [[117_837, 121_837]], "driftPpbWithin": [298_000, 302_000],
                                       "reasonsInclude": "outlier anchors were trimmed"}))
    clusters = [{"id": f"k-{i}", "kind": "serve-contact", "modality": "visual", "sourceTimeUs": x,
                 "referenceTimeUs": x + (5_000_000 if i >= 2 else 0), "eventPositionMm": None}
                for i, x in enumerate((100_000_000, 1_100_000_000, 2_100_000_000, 3_100_000_000))]
    cases.append(_fit_case("inconsistent-clusters-fail",
                           "Two anchor clusters 5 s apart (an unsplit restart): every anchor is trimmed, so the piece "
                           "fails with no transform and no statistics; it can never be marked reviewed",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": clusters}], src="CSE", ref="BS",
                           assertions={"state": ["failed"],
                                       "reasonsInclude": "fewer than 2 inlier anchors after trimming outliers"}))
    manual = [{"id": f"m-{i}", "kind": "manual-marker", "modality": "manual", "sourceTimeUs": 1_000_000 + i * 900_000_000,
               "referenceTimeUs": 1_400_000 + i * 900_000_000, "eventPositionMm": None} for i in range(3)]
    cases.append(_fit_case("manual-markers", "Markers only: the map is manual provenance",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": manual}], src="CSE", ref="BS",
                           assertions={"state": ["manual"], "offsetUsWithin": [[400_000, 400_000]]}))
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "sync-fit",
            "status": "synthetic anchors (Sample), not field evidence; tolerances in 'assert' are hand-set from "
                      "docs/research/studio/multicam-sync.md sections 4.6-4.10", "cases": cases}


# ----- sound delay vectors ------------------------------------------------------------------------

DOC_TABLE = {  # multicam-sync.md section 4.4, club fence, ms
    "south-baseline-centre": (g.SOUTH_BASELINE, [16.0, 85.3, 29.6, 29.6, 88.8, 88.8]),
    "south-baseline-wide": ({"xMm": 4115, "yMm": -11885, "zMm": 1000}, [20.0, 86.1, 40.2, 20.6, 92.9, 86.3]),
    "south-service-t": ({"xMm": 0, "yMm": -6400, "zMm": 1000}, [32.0, 69.3, 40.5, 40.5, 73.6, 73.6]),
    "net-centre": (g.NET_CENTRE, [50.6, 50.6, 56.4, 56.4, 56.4, 56.4]),
    "north-service-t": ({"xMm": 0, "yMm": 6400, "zMm": 1000}, [69.3, 32.0, 73.6, 73.6, 40.5, 40.5]),
    "north-baseline-centre": (g.NORTH_BASELINE, [85.3, 16.0, 88.8, 88.8, 29.6, 29.6]),
}
PLACEMENTS = ["BS", "BN", "CSW", "CSE", "CNW", "CNE"]
PAIR_TABLE = {  # (event, [BS-BN, BS-CSE, BS-CNE]) ms
    "south-baseline-centre": [-69.2, -13.6, -72.8],
    "net-centre": [0.0, -5.8, -5.8],
    "north-baseline-centre": [69.2, -3.6, 55.7],
}


def sound_vectors():
    cases = []
    for name, (event, row) in DOC_TABLE.items():
        for place, doc_ms in zip(PLACEMENTS, row):
            cases.append({"id": f"{name}-{place}", "event": event, "mic": g.POS[place], "mmPerSecond": 343_000,
                          "expectUs": syncfit.sound_delay_us(event, g.POS[place], 343_000),
                          "assert": {"docTableMs": str(doc_ms), "toleranceMs": "0.1"}})
    for name, row in PAIR_TABLE.items():
        event = DOC_TABLE[name][0]
        for other, doc_ms in zip(["BN", "CSE", "CNE"], row):
            d = syncfit.sound_delay_us(event, g.POS["BS"], 343_000) - syncfit.sound_delay_us(event, g.POS[other], 343_000)
            cases.append({"id": f"bias-{name}-BS-{other}", "event": event, "mic": g.POS["BS"], "otherMic": g.POS[other],
                          "mmPerSecond": 343_000, "expectUs": d,
                          "assert": {"docTableMs": str(doc_ms), "toleranceMs": "0.1"}})
    for temp, doc_ms in (("10", "70.5"), ("35", "67.6"), ("20", "69.3")):
        c = syncfit.speed_of_sound_mm_per_s(temp)
        cases.append({"id": f"speed-at-{temp}C", "temperatureC": temp, "expectMmPerSecond": c,
                      "assert": {"docMsOver23770mm": doc_ms, "toleranceMs": "0.1"}})
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "sound-delay",
            "status": "geometry from ITF dimensions (club fence); docTableMs copied from multicam-sync.md section 4.4",
            "cases": cases}


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


# ----- ledger and quote credits -------------------------------------------------------------------

H = "a" * 64
H2 = "b" * 64


def _quote(qid, rev=1, expires="2026-10-07T23:15:00Z", illustrative=False, est=1_290_000, cap=4, key=H):
    return {"quoteId": qid, "projectId": "p1", "planRevision": rev, "outputSpecSha256": key, "filmClass": "story-2-3",
            "estimatedMaxCostMicroUsd": est, "estimate": {"minCredits": 2, "maxCredits": 4}, "capCredits": cap,
            "expiresAt": expires, "status": "open", "illustrative": illustrative}


def _step(n, op, args, expect):
    return {"step": n, "op": op, "args": args, "expect": expect}


def _accept(n, q="q-1", at="2026-10-07T22:50:00Z", consent=True, expect=None):
    return _step(n, "accept", {"quoteId": q, "at": at, "consent": consent}, expect or {})


def _reserve(n, credits, expect, q="q-1", rev=1, key=H, at="2026-10-07T22:51:00Z"):
    return _step(n, "reserve", {"quoteId": q, "projectId": "p1", "planRevision": rev, "outputSpecSha256": key,
                                "credits": credits, "at": at}, expect)


def _consume(n, stage, credits, expect, attempt=1, rid="res-0001"):
    return _step(n, "consume", {"reservationId": rid, "jobId": "job-1", "stage": stage, "attempt": attempt,
                                "credits": credits}, expect)


def _release(n, outcome, expect, rid="res-0001"):
    return _step(n, "release", {"reservationId": rid, "outcome": outcome}, expect)


def _res(reserved, consumed, released, status):
    return {"reservedCredits": reserved, "consumedCredits": consumed, "releasedCredits": released, "status": status}


def ledger_vectors():
    ok4 = {"reservationId": "res-0001", "replayed": False, "balance": 6}
    cases = [
        {"id": "happy-path-idempotent", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, ok4), _reserve(3, 4, dict(ok4, replayed=True)),
            _consume(4, "normalizing", 1, {"consumedCredits": 1, "replayed": False}),
            _consume(5, "normalizing", 1, {"consumedCredits": 1, "replayed": True}),
            _consume(6, "final_rendering", 2, {"consumedCredits": 3, "replayed": False}),
            _release(7, "ready", {"releasedCredits": 1, "replayed": False, "balance": 7}),
            _release(8, "ready", {"releasedCredits": 1, "replayed": True, "balance": 7})],
         "final": {"balance": 7, "reservations": {"res-0001": _res(4, 3, 1, "settled")}}},
        {"id": "same-key-different-terms", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, ok4), _reserve(3, 3, {"rejectCode": "idempotencyConflict"}),
            _consume(4, "normalizing", 1, {"consumedCredits": 1}),
            _consume(5, "normalizing", 2, {"rejectCode": "idempotencyConflict"})],
         "final": {"balance": 6, "reservations": {"res-0001": _res(4, 1, 0, "held")}}},
        {"id": "budget-exceeded-then-failed", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 2, {"reservationId": "res-0001", "balance": 8}),
            _consume(3, "normalizing", 2, {"consumedCredits": 2}),
            _consume(4, "planning", 1, {"rejectCode": "budgetExceeded"}),
            _release(5, "failed", {"releasedCredits": 0, "balance": 8})],
         "final": {"balance": 8, "reservations": {"res-0001": _res(2, 2, 0, "released")}}},
        {"id": "failure-returns-unconsumed", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, ok4), _consume(3, "normalizing", 1, {"consumedCredits": 1}),
            _release(4, "failed", {"releasedCredits": 3, "balance": 9}),
            _consume(5, "planning", 1, {"rejectCode": "reservationClosed"})],
         "final": {"balance": 9, "reservations": {"res-0001": _res(4, 1, 3, "released")}}},
        {"id": "expired-quote", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1, at="2026-10-07T23:20:00Z", expect={"rejectCode": "quoteExpired"}),
            _reserve(2, 4, {"rejectCode": "quoteNotAccepted"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "no-consent", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1, consent=False, expect={"rejectCode": "consentMissing"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "illustrative-never-accepted", "environment": "demo", "startBalance": 10,
         "quotes": [_quote("q-1", illustrative=True)], "steps": [
             _accept(1, expect={"rejectCode": "illustrativeQuote"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "demo-never-reserves", "environment": "demo", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, {"rejectCode": "demoNeverReserves"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "live-not-activated", "environment": "live", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, {"rejectCode": "liveChargingNotActivated"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "new-revision-new-reservation", "environment": "test", "startBalance": 10,
         "quotes": [_quote("q-1"), _quote("q-2", rev=2)], "steps": [
             _accept(1), _accept(2, q="q-2"), _reserve(3, 4, ok4),
             _reserve(4, 4, {"reservationId": "res-0002", "replayed": False, "balance": 2}, q="q-2", rev=2, key=H)],
         "final": {"balance": 2, "reservations": {"res-0001": _res(4, 0, 0, "held"), "res-0002": _res(4, 0, 0, "held")}}},
        {"id": "cap-and-balance", "environment": "test", "startBalance": 3, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 5, {"rejectCode": "overCap"}), _reserve(3, 4, {"rejectCode": "insufficientCredits"}),
            _reserve(4, 3, {"reservationId": "res-0001", "balance": 0})],
         "final": {"balance": 0, "reservations": {"res-0001": _res(3, 0, 0, "held")}}},
        {"id": "quote-for-another-revision", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 4, {"rejectCode": "quoteMismatch"}, rev=2)],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "one-accepted-quote-one-hold", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 4, ok4),
                   _reserve(3, 4, {"rejectCode": "quoteMismatch"}, key=H2)],
         "final": {"balance": 6, "reservations": {"res-0001": _res(4, 0, 0, "held")}}},
        {"id": "budget-exceeded-topup-resumes", "environment": "test", "startBalance": 10,
         "quotes": [_quote("q-1"), _quote("q-2", est=4_000_000, cap=5)], "steps": [
             _accept(1), _reserve(2, 2, {"reservationId": "res-0001", "balance": 8}),
             _consume(3, "normalizing", 2, {"consumedCredits": 2}),
             _consume(4, "planning", 1, {"rejectCode": "budgetExceeded"}),
             _accept(5, q="q-2", at="2026-10-07T22:58:00Z"),
             _reserve(6, 5, {"rejectCode": "idempotencyConflict"}, q="q-2", at="2026-10-07T22:58:30Z"),
             _step(7, "topup", {"reservationId": "res-0001", "quoteId": "q-2", "credits": 5,
                                "at": "2026-10-07T22:58:30Z"}, {"reservationId": "res-0001", "reservedCredits": 5,
                                                                "balance": 5}),
             _consume(8, "planning", 1, {"consumedCredits": 3, "replayed": False}),
             _consume(9, "normalizing", 2, {"consumedCredits": 3, "replayed": True}, attempt=2),
             _release(10, "ready", {"releasedCredits": 2, "balance": 7})],
         "final": {"balance": 7, "reservations": {"res-0001": _res(5, 3, 2, "settled")}}},
        {"id": "retries-after-topup-replay", "environment": "test", "startBalance": 10,
         "quotes": [_quote("q-1"), _quote("q-2", est=4_000_000, cap=5)], "steps": [
             _accept(1), _reserve(2, 2, {"reservationId": "res-0001", "balance": 8}),
             _consume(3, "normalizing", 2, {"consumedCredits": 2}),
             _accept(4, q="q-2", at="2026-10-07T22:58:00Z"),
             _step(5, "topup", {"reservationId": "res-0001", "quoteId": "q-2", "credits": 5,
                                "at": "2026-10-07T22:58:30Z"}, {"reservedCredits": 5, "replayed": False, "balance": 5}),
             _reserve(6, 2, {"reservationId": "res-0001", "replayed": True, "balance": 5}, at="2026-10-07T22:59:00Z"),
             _step(7, "topup", {"reservationId": "res-0001", "quoteId": "q-2", "credits": 5,
                                "at": "2026-10-07T22:59:10Z"}, {"reservedCredits": 5, "replayed": True, "balance": 5}),
             _reserve(8, 5, {"rejectCode": "idempotencyConflict"}, q="q-2", at="2026-10-07T22:59:20Z")],
         "final": {"balance": 5, "reservations": {"res-0001": _res(5, 2, 0, "held")}}},
        {"id": "retry-not-charged-twice", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 4, ok4),
                   _consume(3, "final_rendering", 1, {"consumedCredits": 1, "replayed": False}),
                   _consume(4, "final_rendering", 1, {"consumedCredits": 1, "replayed": True}, attempt=2),
                   _consume(5, "final_rendering", 2, {"rejectCode": "idempotencyConflict"}, attempt=3)],
         "final": {"balance": 6, "reservations": {"res-0001": _res(4, 1, 0, "held")}}},
        {"id": "fractional-second-expiry", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1, at="2026-10-07T23:15:00.500Z", expect={"rejectCode": "quoteExpired"}),
                   _reserve(2, 4, {"rejectCode": "quoteNotAccepted"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "boolean-credits-refused", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, True, {"rejectCode": "badAmount"})],
         "final": {"balance": 10, "reservations": {}}},
    ]
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "ledger",
            "status": "hand-written ledger sequences in Studio Credits (Sample; no money moves). Quotes are bound "
                      "to one outputSpecSha256; consumption is keyed by (job, stage)", "cases": cases}


def quote_credit_vectors():
    rows = [("story-1-design-target", "story-1", 1_120_000, 2), ("story-1-zero", "story-1", 0, 2),
            ("story-1-worst-case", "story-1", 9_400_000, 12), ("broadcast-4-6-design", "broadcast-4-6", 2_320_000, 8),
            ("story-4-6-exact-boundary", "story-4-6", 4_800_000, 6), ("story-4-6-one-over", "story-4-6", 4_800_001, 7),
            ("revision", "revision", 400_000, 1), ("screen-37-class", "story-2-3", 1_290_000, 4)]
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "quote-credits",
            "status": "capCredits = max(class minimum, ceil(cost / 800000 micro-USD)); proposal, not a price",
            "cases": [{"id": i, "filmClass": c, "estimatedMaxCostMicroUsd": e, "expectCredits": x} for i, c, e, x in rows]}


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
                rep("/segments/4/protectedFrames", []), rep("/audio/bed/3/sourceInFrame", s_in), *extra]

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

def rep(path, value):
    return {"op": "replace", "path": path, "value": value}


def add(path, value):
    return {"op": "add", "path": path, "value": value}


def rm(path):
    return {"op": "remove", "path": path}


def bad(cid, why, patch, code=None):
    return {"id": cid, "why": why, "patch": patch,
            "expect": {"layer": "schema"} if code is None else {"layer": "reference", "code": code}}


def invalid_sets(P, plans):
    sb, cc, rp, mb = (plans[k] for k in ("storyboard", "coach", "rally", "broadcast"))
    s03_session = sb["segments"][2]["sessionInUs"]
    s02_bed = sb["audio"]["bed"][1]["sourceInFrame"]
    # coach: move c05 so it shows the session time the hold-bed plays under (1260-1271 s)
    c05_in = P.frame_for_session("camera-2", 1_262_000_000)
    c05_session = round_half_up(P.session("camera-2", c05_in))
    # coach: the primary-bed frame that would be in sync with c05 at output frame 4800
    c05_back = P.frame_for_session("camera-1", P.session("camera-2", 150000 + (4800 - 2250) * 2))
    # rally: an alternate bed from camera-2 in sync with r02 (camera-1 120000..), starting at r02's dissolve
    r02_alt = P.frame_for_session("camera-2", P.session("camera-1", 120000))
    sets = {}
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
        bad("hold-bed-over-live", "Hold-bed continues under live play",
            [rep("/audio/bed/2/outputOutFrame", 2300),
             rep("/audio/bed/3", {"route": "primary-bed", "sourceId": "camera-1", "sourceInFrame": 150000,
                                  "outputInFrame": 2300, "outputOutFrame": 5520, "fadeInMs": 20, "fadeOutMs": 20})],
            "holdBedOverLive"),
        bad("hold-bed-not-dead-time", "The held court audio is session time a later live segment shows",
            [rep("/segments/4/sourceInFrame", c05_in), rep("/segments/4/sourceOutFrame", c05_in + 6540),
             rep("/segments/4/sessionInUs", c05_session), rep("/segments/4/protectedFrames", [])], "holdBedNotDeadTime"),
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
    sets["edit-plan.rally-pulse-portrait"] = [
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
    sets["sync-map"] = [
        bad("forged-offset", "The stored offset is not what the anchors give",
            [rep("/sources/1/pieces/0/transform/offsetUs", plans["syncmap"]["sources"][1]["pieces"][0]["transform"]["offsetUs"] + 1000)],
            "syncFitMismatch"),
        bad("forged-residual", "A residual was edited",
            [rep("/sources/1/pieces/0/anchors/0/residualUs",
                 plans["syncmap"]["sources"][1]["pieces"][0]["anchors"][0]["residualUs"] + 5)], "syncFitMismatch"),
        bad("auto-approved", "Camera 3 has five anchors; it cannot be estimated", [rep("/sources/2/pieces/0/state", "estimated")],
            "syncStateMismatch"),
        bad("review-missing-middle", "Reviewed needs start, middle and end", [rep("/sources/1/pieces/0/checkpoints", ["start", "end"])],
            "reviewIncomplete"),
        bad("extrapolated-coverage", "Coverage beyond the recorded file",
            [rep("/sources/1/pieces/0/matchCoverage/endUs",
                 plans["syncmap"]["sources"][1]["pieces"][0]["matchCoverage"]["endUs"] + 60_000_000)], "badCoverage"),
        bad("validated-map", "A single map is never Validated", [rep("/provenance/status", "validated")]),
        bad("wrong-speed-of-sound", "Default is 343 m/s", [rep("/speedOfSound/mmPerSecond", 340_000)], "badSpeedOfSound"),
        bad("provenance-overclaim", "Camera 3 still needs review", [rep("/provenance/status", "reviewed")], "badProvenance"),
        bad("certainty-field", "No fake certainty percentages on anchors",
            [add("/sources/1/pieces/0/anchors/0/confidencePct", 99)]),
        bad("anchor-outside-piece", "An anchor 1 s past the end of its piece (another segment's) is never fitted",
            [add("/sources/1/pieces/0/anchors/-", {"id": "c2-stray", "kind": "serve-contact", "modality": "visual",
                                                   "sourceTimeUs": HOUR + 1_000_000, "referenceTimeUs": HOUR + 1_200_000,
                                                   "eventPositionMm": None, "sourceDelayUs": 0, "referenceDelayUs": 0,
                                                   "corrected": True, "residualUs": 0, "inlier": True,
                                                   "reviewed": True})], "badAnchor"),
        bad("fit-without-inliers", "A fit needs at least two inlier anchors",
            [rep("/sources/1/pieces/0/fit/nInliers", 0)]),
        bad("failed-piece-claims-coverage", "A failed piece (no transform) cannot carry match coverage",
            [add("/sources/2/pieces/-", {"segmentId": "seg-1", "sourceDurationUs": 600_000_000,
                                         "matchCoverage": {"startUs": 3_700_000_000, "endUs": 4_300_000_000},
                                         "transform": None, "fit": None, "anchors": [], "state": "failed",
                                         "reasons": ["too few anchors to fit"], "checkpoints": [], "reviewedAt": None})]),
        bad("reference-restart-invented", "A restarted reference segment with an invented offset and a 1.09 rate: its "
            "placement comes from the capture journal (from-hints, rate 1) or it has none",
            [add("/sources/0/pieces/-", {"segmentId": "seg-1", "sourceDurationUs": 600_000_000,
                                         "matchCoverage": {"startUs": 3_650_000_000, "endUs": 4_304_000_000},
                                         "transform": {"offsetUs": 3_650_000_000,
                                                       "rate": {"num": 1_090_000_000, "den": 1_000_000_000}},
                                         "fit": None, "anchors": [], "state": "reference", "reasons": [],
                                         "checkpoints": [], "reviewedAt": None}),
             add("/sources/0/gaps/-", {"match": {"startUs": HOUR, "endUs": 3_650_000_000}, "reason": "restart"})],
            "badReference"),
    ]
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
    sets["usage-reservation.settled"] = [
        bad("double-consume", "One consumption per stage attempt",
            [rep("/entries/3/key", "consume:job-film-01:normalizing:1")], "idempotencyConflict"),
        bad("totals-disagree", "Totals equal the entries", [rep("/releasedCredits", 2)], "ledgerMismatch"),
        bad("live-charge", "No live charging before its ADR", [rep("/environment", "live"), rep("/sample", False)],
            "liveChargingNotActivated"),
        bad("reserved-above-cap", "A reservation never exceeds the cap", [rep("/capCredits", 3)], "overCap"),
        bad("stage-charged-twice", "A retried stage is charged once, whatever the attempt",
            [rep("/entries/3/key", "consume:job-film-01:normalizing:2")], "idempotencyConflict"),
        bad("retried-reserve-second-key", "A retried reserve written under a second key is a double hold within the "
            "cap; a retry replays instead",
            [rep("/entries/0/credits", 2),
             add("/entries/1", {"entryId": "e-1b", "kind": "reserve", "credits": 2, "key": "reserve:sample-court-day:2:retry",
                                "at": "2026-10-07T22:50:06Z"})], "badEntryKey"),
        bad("reserve-key-of-another-output", "The reserve entry is keyed by this record's own output spec",
            [rep("/entries/0/key", "reserve:sample-court-day:2:" + "c" * 64)], "badEntryKey"),
        bad("consume-for-another-job", "Consumption is charged to this reservation's job only",
            [rep("/entries/3/key", "consume:other-job:final_rendering:2")], "badEntryKey"),
        bad("consume-unknown-stage", "Only the job contract's charged stages consume credits",
            [rep("/entries/3/key", "consume:job-film-01:not_a_stage:2")], "badEntryKey"),
        bad("consume-stage-case", "Stages are spelled exactly; Final_Rendering is not final_rendering",
            [rep("/entries/3/key", "consume:job-film-01:Final_Rendering:2")], "badEntryKey"),
        bad("reserve-keyed-as-consume", "An entry's key prefix is its kind",
            [rep("/entries/1/kind", "reserve"), rep("/reservedCredits", 5), rep("/capCredits", 5),
             rep("/consumedCredits", 2), rep("/releasedCredits", 3), rep("/entries/4/credits", 3)], "badEntryKey"),
        bad("release-outcome-mismatch", "A settled reservation was released as ready, not failed",
            [rep("/entries/4/key", "release:job-film-01:failed")], "badEntryKey"),
    ]
    sets["usage-reservation.held"] = [
        bad("demo-credits", "Demo identities never reserve", [rep("/environment", "demo")], "demoNeverReserves"),
    ]
    sets["quote.sample-illustrative"] = [
        bad("illustrative-accepted", "The screen-37 sample quote can never be accepted",
            [rep("/status", "accepted"), rep("/acceptedAt", "2026-10-07T22:50:00Z"),
             rep("/consent", {"consentRecordId": "consent-x", "uploadSelectedSources": True, "at": "2026-10-07T22:49:00Z"})],
            "illustrativeQuote"),
        bad("long-lived-quote", "Quotes expire within 30 minutes", [rep("/expiresAt", "2026-10-08T00:45:00Z")], "quoteLifetime"),
        bad("client-set-cap", "The cap follows the class minimum and estimate", [rep("/capCredits", 3)], "quoteCapMismatch"),
    ]
    sets["quote.accepted"] = [
        bad("money-on-a-real-quote", "Dollar amounts appear only as illustrative Sample UX",
            [rep("/displayAmounts", {"currency": "USD", "minMinor": 400, "maxMinor": 800, "capMinor": 1200,
                                     "illustrative": True})], "illustrativeQuote"),
        bad("accepted-after-expiry", "Never auto-accepted after expiry", [rep("/acceptedAt", "2026-10-07T23:20:00Z")],
            "quoteExpired"),
        bad("accepted-without-consent", "Acceptance records upload consent", [rep("/consent", None)], "consentMissing"),
        bad("accepted-half-second-late", "23:15:00.500Z is after 23:15:00Z (timestamps are parsed, not compared as text)",
            [rep("/acceptedAt", "2026-10-07T23:15:00.500Z")], "quoteExpired"),
        bad("unbound-quote", "A quote is bound to one output spec", [rm("/outputSpecSha256")]),
        bad("hash-trailing-newline", "A sha256 with a trailing newline is not a sha256 (ECMA-262 anchors)",
            [rep("/outputSpecSha256", "8" * 64 + "\n")]),
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
    return {name: {"schemaVersion": "jovra.studio-fixture.invalid-cases/1", "base": f"records/{name}.json", "cases": cases}
            for name, cases in sets.items()}
