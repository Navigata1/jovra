"""Sync-fit and sound-delay vectors, sync-map invalid cases and checkers. Module page:
spec/studio/modules/sync.md.

Vector "expect" blocks come from the reference; "assert" blocks are hand-derived from the research and are checked
independently by scripts/spec/validate_studio.py.
"""

from __future__ import annotations

import copy
import json
from fractions import Fraction

from studio import bundle as studio_bundle
from studio import records, syncfit
from studio.core import Reject, round_half_up

import generate_studio_fixtures as g
from studio.cases.patches import add, bad, invalid_docs, rep

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
                           "1500 ppm is inside the 0.9-1.1 schema range but far beyond phone clocks (about 8 ppm) and "
                           "above 1000 ppm (30 vs 29.97 fps): flagged as a likely timebase mislabel; a person may confirm "
                           "it at the checkpoints (reviewable reason, not a rejection)",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="CSE", ref="BS",
                           assertions={"state": ["needs-review"], "driftPpbWithin": [1_499_000, 1_501_000],
                                       "reasonsInclude": "drift above 1000 ppm", "reviewable": True}))
    a = g.synth_anchors(offset=400_000, rate=Fraction(10_004, 10_000), events=ev, src_pos=g.POS["CSE"],
                        ref_pos=g.POS["BS"], prefix="d4", noise=False)
    cases.append(_fit_case("drift-400ppm-above-stress-ceiling",
                           "400 ppm with ten exact anchors over the hour: everything else would be estimated, but the "
                           "drift is above the 300 ppm stress fixture plus the 3 ppm S2 tolerance (multicam-sync.md 4.6), "
                           "so it needs review; a person may confirm it (the old 1000 ppm gate let it through as "
                           "estimated)",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="CSE", ref="BS",
                           assertions={"state": ["needs-review"], "driftPpbWithin": [399_000, 401_000],
                                       "reasonsInclude": "drift above the 300 ppm stress ceiling", "reviewable": True}))
    a = g.synth_anchors(offset=400_000, rate=Fraction(1_000_303, 1_000_000), events=ev, src_pos=g.POS["CSE"],
                        ref_pos=g.POS["BS"], prefix="d3", noise=False)
    cases.append(_fit_case("drift-303ppm-at-ceiling",
                           "Exactly 303 ppm (the stress fixture plus the S2 tolerance) is still plausible: estimated",
                           [{"segmentId": "seg-0", "sourceDurationUs": HOUR, "anchors": a}], src="CSE", ref="BS",
                           assertions={"state": ["estimated"], "driftPpbWithin": [303_000, 303_000],
                                       "reviewable": True}))
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



# ----- invalid cases ------------------------------------------------------------------------------

def _hint_piece(plans, offset):
    """Camera 3's piece with no anchors, placed from a capture hint at offset (stored from-hints)."""
    piece = copy.deepcopy(plans["syncmap"]["sources"][2]["pieces"][0])
    t = {"offsetUs": offset, "rate": {"num": syncfit.RATE_DEN, "den": syncfit.RATE_DEN}}
    piece.update(anchors=[], fit=None, transform=t, state="from-hints", reasons=["no anchors; capture hint only"],
                 matchCoverage={"startUs": syncfit.map_us(t, 0), "endUs": syncfit.map_us(t, piece["sourceDurationUs"])})
    return piece


def _drift_piece(plans, rate):
    """Camera 3 re-anchored with ten exact visual anchors at the given rate, stored as 'estimated' with no reasons."""
    smap = plans["syncmap"]
    piece = smap["sources"][2]["pieces"][0]
    pos = {p["sourceId"]: p["positionMm"] for p in smap["placements"]}
    ev = [(50_000_000 + i * 340_000_000, "visual", "serve-contact", None) for i in range(10)]
    raw = g.synth_anchors(offset=2_350_000, rate=rate, events=ev, src_pos=pos["camera-3"], ref_pos=pos["camera-1"],
                          prefix="c3d", noise=False)
    fitted = syncfit.fit_device([{"segmentId": piece["segmentId"], "sourceDurationUs": piece["sourceDurationUs"],
                                  "anchors": raw}], source_position=pos["camera-3"], reference_position=pos["camera-1"],
                                c_mm_per_s=smap["speedOfSound"]["mmPerSecond"], output_fps=smap["outputFps"])[0]
    stored = g.stored_piece(piece["segmentId"], piece["sourceDurationUs"], fitted, raw, state="estimated")
    stored["reasons"] = []
    return stored


def invalid_sets(P, plans):
    sets = {}
    cam3_hint = studio_bundle.capture_hints(plans["manifest"], plans["syncmap"])["camera-3"]["seg-0"]
    drift400_estimated = _drift_piece(plans, Fraction(10_004, 10_000))
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
        bad("no-overlap-state", "There is no no-overlap state: no shared coverage is a failed piece",
            [rep("/sources/2/pieces/0/state", "no-overlap")]),
        bad("hint-offset-invented", "A from-hints piece must carry the capture hint the SourceManifest journal gives, "
            "never an offset of its own",
            [rep("/sources/2/pieces/0", _hint_piece(plans, cam3_hint + 1000))], "syncFitMismatch"),
        bad("implausible-drift-stored-estimated", "Ten exact anchors at 400 ppm stored as estimated (what the old "
            "1000 ppm gate gave): above the 303 ppm plausibility ceiling the fitter says needs-review",
            [rep("/sources/2/pieces/0", drift400_estimated)], "syncStateMismatch"),
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
    return invalid_docs(sets)


# ----- what this module declares and registers ----------------------------------------------------

def fixtures(sample):
    docs = {"vectors/sync-fit.json": sync_vectors(), "vectors/sound-delay.json": sound_vectors()}
    for name, doc in invalid_sets(sample.P, sample.plans).items():
        docs[f"invalid/{name}.invalid.json"] = doc
    return docs


def within(value, bounds) -> bool:
    return bounds[0] <= value <= bounds[1]


def check_sync_vector(ctx, case, report, where) -> None:
    inp = case["input"]
    got = syncfit.fit_device(inp["pieces"], source_position=inp["sourcePosition"],
                             reference_position=inp["referencePosition"], c_mm_per_s=inp["mmPerSecond"],
                             output_fps=inp["outputFps"], hints=inp["hints"])
    if got != case["expect"]:
        report.fail(where, "fitter output differs from the stored expectation")
        return
    a = case["assert"]
    fitted = [p for p in got if p["fit"] is not None]
    problems = []
    if "state" in a and [p["state"] for p in got] != a["state"]:
        problems.append(f"states {[p['state'] for p in got]}")
    for p, bounds in zip(got, a.get("offsetUsWithin", [])):
        if p["transform"] is None or not within(p["transform"]["offsetUs"], bounds):
            problems.append(f"offset {p['transform']} outside {bounds}")
    if "driftPpbWithin" in a and not all(within(p["fit"]["driftPpb"], a["driftPpbWithin"]) for p in fitted):
        problems.append("drift outside bounds")
    if "driftMsPerMinRounded" in a and round_half_up(syncfit.drift_ms_per_min(got[0]["transform"])) != a["driftMsPerMinRounded"]:
        problems.append("drift ms/min")
    if "residualMaxUsAtMost" in a and max(p["fit"]["residualMaxUs"] for p in fitted) > a["residualMaxUsAtMost"]:
        problems.append("residual too large")
    if "residualMaxUsAtLeast" in a and max(p["fit"]["residualMaxUs"] for p in fitted) < a["residualMaxUsAtLeast"]:
        problems.append("residual unexpectedly small (bias not visible)")
    if "uncorrectedAudio" in a and any(p["fit"]["uncorrectedAudio"] != a["uncorrectedAudio"] for p in fitted):
        problems.append("uncorrectedAudio flag")
    if a.get("sharedRate") and len({json.dumps(p["transform"]["rate"]) for p in fitted}) != 1:
        problems.append("pieces of one device must share one rate")
    if "nOutliers" in a and sum(p["fit"]["nOutliers"] for p in fitted) != a["nOutliers"]:
        problems.append("outlier count")
    if "reasonsInclude" in a and not any(a["reasonsInclude"] in r for p in got for r in p["reasons"]):
        problems.append("missing review reason")
    if "reviewable" in a:
        # can a person mark the first piece reviewed after confirming start, middle and end?
        try:
            syncfit.check_review_state("reviewed", got[0]["state"], ["start", "middle", "end"], got[0]["fit"])
            reviewable = True
        except Reject:
            reviewable = False
        if reviewable != a["reviewable"]:
            problems.append(f"reviewable is {reviewable}")
    if problems:
        report.fail(where, "hand assertions: " + ", ".join(problems))
    else:
        report.ok("sync-fit vectors")


def check_sound_vector(ctx, case, report, where) -> None:
    tol = Fraction(case["assert"]["toleranceMs"])
    if "temperatureC" in case:
        c = syncfit.speed_of_sound_mm_per_s(case["temperatureC"])
        ms = Fraction(23_770 * 1000, c)
        ok = c == case["expectMmPerSecond"] and abs(ms - Fraction(case["assert"]["docMsOver23770mm"])) <= tol
    else:
        got = syncfit.sound_delay_us(case["event"], case["mic"], case["mmPerSecond"])
        if "otherMic" in case:
            got -= syncfit.sound_delay_us(case["event"], case["otherMic"], case["mmPerSecond"])
        ok = got == case["expectUs"] and abs(Fraction(got, 1000) - Fraction(case["assert"]["docTableMs"])) <= tol
    if ok:
        report.ok("sound-delay vectors")
    else:
        report.fail(where, "differs from the reference or from the research table")


def check_sync_map(ctx, doc):
    # capture hints come from the stored SourceManifest, so a from-hints piece is checked, never trusted
    return records.check_sync_map(doc, hints=studio_bundle.capture_hints(ctx.bundle["manifest"], doc))


VECTOR_CHECKERS = {"sync-fit": check_sync_vector, "sound-delay": check_sound_vector}
SCHEMAS = {"jovra.sync-map/1": "sync-map.schema.json"}
RECORD_RULES = {"jovra.sync-map/1": check_sync_map}


# ----- self-tests: from-hints at the record layer ---------------------------------------------------------------

def check_hint_states(ctx, report) -> None:
    """from-hints is reachable at the record layer, and only with the hint the SourceManifest gives: a camera piece
    with no anchors, and a restarted segment of the reference device placed from its own capture journal."""
    manifest = copy.deepcopy(ctx.records["source-manifest"])
    base = ctx.records["sync-map"]
    hour = base["sources"][0]["pieces"][0]["sourceDurationUs"]
    restart_us = hour + 50_000_000
    cam1 = manifest["sources"][0]
    first = cam1["segments"][0]
    cam1["segments"].append(dict(first, segmentId="seg-1", index=1, reason="restart", durationUs=600_000_000,
                                 fileZeroHostNs=first["fileZeroHostNs"] + restart_us * 1000))

    def doc_with(offset):
        d = copy.deepcopy(base)
        t = {"offsetUs": offset, "rate": {"num": 1_000_000_000, "den": 1_000_000_000}}
        d["sources"][0]["pieces"].append({
            "segmentId": "seg-1", "sourceDurationUs": 600_000_000,
            "matchCoverage": {"startUs": syncfit.map_us(t, 0), "endUs": syncfit.map_us(t, 600_000_000)},
            "transform": t, "fit": None, "anchors": [], "state": "from-hints", "reasons": [], "checkpoints": [],
            "reviewedAt": None})
        d["sources"][0]["gaps"] = [{"match": {"startUs": hour, "endUs": syncfit.map_us(t, 0)}, "reason": "restart"}]
        return d

    def no_anchor_camera3(offset):
        d = copy.deepcopy(base)
        t = {"offsetUs": offset, "rate": {"num": 1_000_000_000, "den": 1_000_000_000}}
        piece = d["sources"][2]["pieces"][0]
        piece.update(anchors=[], fit=None, transform=t, state="from-hints", reasons=["no anchors; capture hint only"],
                     matchCoverage={"startUs": syncfit.map_us(t, 0), "endUs": syncfit.map_us(t, piece["sourceDurationUs"])})
        return d

    hints = studio_bundle.capture_hints(manifest, base)
    tests = [
        ("reference restart from its journal", doc_with(restart_us), hints, None),
        ("reference restart, offset not the journal's", doc_with(restart_us + 1000), hints, "badReference"),
        ("camera without anchors placed from its hint", no_anchor_camera3(hints["camera-3"]["seg-0"]), hints, None),
        ("hint-only piece without the manifest hints", no_anchor_camera3(hints["camera-3"]["seg-0"]), {},
         "syncFitMismatch"),
    ]
    for label, doc, h, code in tests:
        errors = ctx.schemas.validate(doc, "sync-map.schema.json")
        if errors:
            report.fail(f"hint self-test {label}", "schema: " + "; ".join(errors[:2]))
            continue
        try:
            records.check_sync_map(doc, hints=h)
            got = None
        except Reject as exc:
            got = exc.code
        if got != code:
            report.fail(f"hint self-test {label}", f"got {got}, expected {code}")
        else:
            report.ok("hint self-tests")


SELF_TESTS = {"sync-capture-hints": check_hint_states}
