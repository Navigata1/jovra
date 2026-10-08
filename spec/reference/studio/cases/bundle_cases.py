"""Implementation-states sample truth for the sample project, and its checker. Module page:
spec/studio/modules/bundle.md.
"""

from __future__ import annotations

from fractions import Fraction

from studio import syncfit
from studio.core import delta_pp_display, pct, round_half_up


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
