"""Normalization vectors (original PTS -> render-proxy frame), the Sample PTS table, its invalid cases, checkers and
self-tests. Module page: spec/studio/modules/normalization.md.

Every vector's "expect" block comes from the reference (spec/reference/studio/normalization.py); every "assert" block
is hand-derived from the half-up rule on paper (multicam-sync research 5.2-5.5, 8.2-8.3) and is checked separately, so
a reference bug cannot pass its own vectors. The source descriptions are synthetic and explicit (every PTS is in the
input), so Swift and Kotlin need no generator: they build the synthetic coded clip, normalize it, decode the embedded
frame IDs and compare.
"""

from __future__ import annotations

import copy
from fractions import Fraction

from studio import normalization
from studio.core import Reject
from studio.cases.patches import bad, invalid_docs, rep

FPS24 = {"num": 24, "den": 1}
FPS25 = {"num": 25, "den": 1}
FPS30 = {"num": 30, "den": 1}
FPS60 = {"num": 60, "den": 1}
FPS120 = {"num": 120, "den": 1}
NTSC30 = {"num": 30000, "den": 1001}
NORMALIZER = "jovra-normalize@0.1.0"
ZSCALE = {"method": "ffmpeg-zscale-tonemap", "params": "transfer=linear,tonemap=hable,desat=0,transfer=bt709",
          "version": "ffmpeg@8.0.0"}
PLACEBO = {"method": "ffmpeg-libplacebo", "params": "tonemapping=bt.2390,peak_detect=0", "version": "ffmpeg@8.0.0"}
# Hand-written VFR jitter in original ticks (600 per second, 20 per 30 fps frame): never 10 or more, so no frame
# reaches a tie or the next slot on its own.
JITTER600 = (0, 2, -1, 3, -2, 1, -3, 0, 2, -1)
JITTER90K = (0, 450, -300, 600, -150, 300, -600, 150, -450, 0)   # ticks of 90 kHz, |j| < 1500 (half a 30 fps frame)
RECORD = "pts-table.sample-corner"


# ----- source descriptions --------------------------------------------------------------------------

def cfr(timescale: int, fps: dict, count: int, start: int = 0) -> list[int]:
    step = Fraction(timescale * fps["den"], fps["num"])
    assert step.denominator == 1, "a CFR helper needs an integer frame duration on the timescale"
    return [start + i * int(step) for i in range(count)]


def jittered(step: int, count: int, jitter, skip=()) -> list[int]:
    return [i * step + jitter[i % len(jitter)] for i in range(count) if i not in skip]


def original(pts, *, timescale, nominal, end, width=1920, height=1080, rotation=0, hdr=False, transfer="bt709"):
    return {"timescale": timescale, "nominalFps": nominal, "pts": normalization.compress_pts(pts), "endPts": end,
            "frameCount": len(pts), "width": width, "height": height, "rotationDegrees": rotation, "hdr": hdr,
            "transfer": transfer}


def source(cid, orig, out_fps, *, long_edge=1920, tone_map=None):
    return {"sourceId": f"sample-{cid}", "normalizerVersion": NORMALIZER, "original": orig,
            "proxy": {"fps": out_fps, "targetLongEdge": long_edge, "toneMap": tone_map}}


# ----- vectors ------------------------------------------------------------------------------------

def derive(cid, why, inp, assertions):
    table = normalization.derive_table(inp)
    return {"id": cid, "mode": "derive", "why": why, "input": inp,
            "expect": {"table": table, "sha256": normalization.table_sha256(table),
                       "proxyFrameOfOriginal": normalization.original_to_proxy(table)},
            "assert": assertions}


def nearest_slots(orig: dict, fps: dict) -> list[int]:
    """Mutation only: the original frame nearest each proxy instant (ties to the earlier frame). It is not the rule;
    the research observed it matching FFmpeg in only 137 of 184 slots."""
    pts = normalization.original_pts(orig)
    n = normalization.proxy_frame_count(orig, fps)
    times = [Fraction(p - pts[0], orig["timescale"]) for p in pts]
    out = []
    for k in range(n):
        instant = Fraction(k * fps["den"], fps["num"])
        out.append(min(range(len(times)), key=lambda i: (abs(times[i] - instant), i)))
    return out


def normalizer_output(inp: dict, rule: str) -> tuple[dict, list[int]]:
    """What a normalizer following `rule` emits (its table) and what its proxy decodes to (embedded frame IDs)."""
    orig, fps = inp["original"], inp["proxy"]["fps"]
    if rule == "nearest":
        slots = nearest_slots(orig, fps)
        table = normalization.derive_table(inp)
        return dict(table, runs=normalization.slot_runs(slots, normalization.original_pts(orig))), slots
    table = normalization.derive_table(inp, tie=rule)
    return table, normalization.expand_runs(table["runs"])


def mutation(cid, why, inp, *, emit, decode, assertions):
    """S4 and its relatives: a normalizer whose proxy shows other frames (or whose table lies) must be refused."""
    emitted, _ = normalizer_output(inp, emit)
    _, decoded = normalizer_output(inp, decode)
    try:
        normalization.check_conformance(inp["original"], inp["proxy"]["fps"], emitted, decoded)
        expect = {"accepted": True}
    except normalization.FrameSelectionMismatch as exc:
        expect = {"rejectCode": exc.code, "slot": exc.slot, "expectedFrame": exc.expected, "foundFrame": exc.found}
    except Reject as exc:
        expect = {"rejectCode": exc.code}
    return {"id": cid, "mode": "mutation", "why": why, "input": inp, "mutation": {"emit": emit, "decode": decode},
            "expect": expect, "assert": assertions}


def reject(cid, why, inp, code):
    try:
        normalization.derive_table(inp)
        expect = {"accepted": True}
    except Reject as exc:
        expect = {"rejectCode": exc.code}
    return {"id": cid, "mode": "reject", "why": why, "input": inp, "expect": expect, "assert": {"rejectCode": code}}


def check(cid, why, table, code):
    try:
        normalization.check_pts_table(table)
        expect = {"accepted": True}
    except Reject as exc:
        expect = {"rejectCode": exc.code}
    return {"id": cid, "mode": "check", "why": why, "table": table, "expect": expect, "assert": {"rejectCode": code}}


def corner_source() -> dict:
    """S12: VFR + rotation 90 + HDR (HLG) -> render proxy. Frame 30 sits exactly on a tie (610 = 30.5 frames)."""
    pts = jittered(20, 60, JITTER600)
    pts[30] = 610
    return source("corner-vfr", original(pts, timescale=600, nominal=FPS30, end=1200, width=3840, height=2160,
                                         rotation=90, hdr=True, transfer="hlg"), FPS30, tone_map=ZSCALE)


def ntsc_source() -> dict:
    return source("ntsc-in-30", original(cfr(30000, NTSC30, 600), timescale=30000, nominal=NTSC30, end=600 * 1001),
                  FPS30)


def tie_source() -> dict:
    pts = cfr(600, FPS30, 30)
    pts[10] = 210   # 10.5 frames: a tie between proxy frames 10 and 11
    return source("vfr-tie", original(pts, timescale=600, nominal=FPS30, end=600), FPS30)


def derive_vectors() -> list[dict]:
    v = []
    v.append(derive("cfr-30-to-30", "30 fps CFR at timescale 600 into a 30 fps proxy: the identity table",
                    source("cfr30", original(cfr(600, FPS30, 90), timescale=600, nominal=FPS30, end=1800), FPS30),
                    {"proxyFrameCount": 90, "trackTimescale": 3000, "frameDurationTicks": 100, "runCount": 1,
                     "slotShows": [[0, 0], [45, 45], [89, 89]], "originalAt": [[0, 0], [89, 89]]}))
    v.append(derive("cfr-60-to-30", "60 fps to 30: every odd frame sits on a tie (k + 1/2) and rounds up into the next "
                    "slot, so slot k keeps frame 2k, the one at its instant",
                    source("cfr60", original(cfr(600, FPS60, 120), timescale=600, nominal=FPS60, end=1200), FPS30),
                    {"proxyFrameCount": 60, "trackTimescale": 3000, "frameDurationTicks": 100, "runCount": 1,
                     "slotShows": [[0, 0], [1, 2], [29, 58], [59, 118]],
                     "originalAt": [[1, 1], [2, 1], [3, 2], [119, 60]]}))
    v.append(derive("cfr-120-to-30", "120 fps to 30: slot k shows the last frame rounding into it, 4k + 1, not the "
                    "nearest frame 4k (the observed FFmpeg rule; analysis keeps original PTS anyway)",
                    source("cfr120", original(cfr(600, FPS120, 240), timescale=600, nominal=FPS120, end=1200), FPS30),
                    {"proxyFrameCount": 60, "trackTimescale": 3000, "frameDurationTicks": 100, "runCount": 1,
                     "slotShows": [[0, 1], [1, 5], [59, 237]], "originalAt": [[1, 0], [2, 1], [5, 1], [6, 2]]}))
    v.append(derive("cfr-24-to-30", "24 fps into a 30 fps film: one slot in five holds the previous frame; even "
                    "frames land on ties (frame 2 at 2.5 slots rounds up to 3)",
                    source("cfr24", original(cfr(600, FPS24, 48), timescale=600, nominal=FPS24, end=1200), FPS30),
                    {"proxyFrameCount": 60, "trackTimescale": 3000, "frameDurationTicks": 100, "upconverted": True,
                     "slotShows": [[1, 1], [2, 1], [3, 2], [7, 5], [59, 47]], "originalAt": [[2, 3], [6, 8]]}))
    v.append(derive("cfr-25-to-30", "25 fps (PAL phone) into a 30 fps film: slots 3, 9, ... hold a frame; no ties",
                    source("cfr25", original(cfr(600, FPS25, 50), timescale=600, nominal=FPS25, end=1200), FPS30),
                    {"proxyFrameCount": 60, "trackTimescale": 3000, "frameDurationTicks": 100, "upconverted": True,
                     "slotShows": [[2, 2], [3, 2], [9, 7], [59, 49]], "originalAt": [[3, 4], [8, 10]]}))
    v.append(derive("cfr-30-to-60", "30 into a 60 fps film duplicates every frame, so the proxy is labelled upconverted "
                    "(the angle shows '30 fps source')",
                    source("up60", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600), FPS60),
                    {"proxyFrameCount": 60, "trackTimescale": 3000, "frameDurationTicks": 50, "upconverted": True,
                     "slotShows": [[0, 0], [1, 0], [2, 1], [59, 29]], "originalAt": [[1, 2], [29, 58]]}))
    v.append(derive("ntsc-2997-in-30-project", "Mixed rates: a 30000/1001 angle in a 30 fps film runs 1000 ppm slow; "
                    "frame 500 lands exactly on 500.5 and rounds up, so slot 500 holds frame 499",
                    ntsc_source(),
                    {"proxyFrameCount": 601, "trackTimescale": 3000, "frameDurationTicks": 100, "runCount": 2,
                     "slotShows": [[499, 499], [500, 499], [501, 500], [600, 599]],
                     "originalAt": [[499, 499], [500, 501], [599, 600]]}))
    v.append(derive("cfr-30-in-2997-project", "Mixed rates the other way: a 30 fps angle in a 30000/1001 film drops one "
                    "frame (500) in 600; track timescale 30000, 1001 ticks a frame",
                    source("cfr30-ntsc", original(cfr(600, FPS30, 600), timescale=600, nominal=FPS30, end=12000), NTSC30),
                    {"proxyFrameCount": 599, "trackTimescale": 30000, "frameDurationTicks": 1001, "upconverted": False,
                     "slotShows": [[499, 499], [500, 501], [598, 599]], "originalAt": [[500, 500], [501, 500]]}))
    v.append(derive("ntsc-2997-identity", "30000/1001 at timescale 30000 into a 30000/1001 proxy: the identity",
                    source("ntsc", original(cfr(30000, NTSC30, 300), timescale=30000, nominal=NTSC30, end=300 * 1001),
                           NTSC30),
                    {"proxyFrameCount": 300, "trackTimescale": 30000, "frameDurationTicks": 1001, "runCount": 1,
                     "slotShows": [[0, 0], [299, 299]], "originalAt": [[150, 150]]}))
    v.append(derive("cfr-25-project", "25 fps into a 25 fps film: track timescale lcm(25, 1000) = 1000, 40 ticks a frame",
                    source("pal", original(cfr(600, FPS25, 50), timescale=600, nominal=FPS25, end=1200), FPS25),
                    {"proxyFrameCount": 50, "trackTimescale": 1000, "frameDurationTicks": 40, "runCount": 1,
                     "slotShows": [[49, 49]], "originalAt": [[25, 25]]}))
    v.append(derive("vfr-jitter-30", "VFR: every PTS jitters by up to 3 ticks of 600 (5 ms); jitter under half a frame "
                    "never changes the selection",
                    source("vfr", original(jittered(20, 90, JITTER600), timescale=600, nominal=FPS30, end=1800), FPS30),
                    {"proxyFrameCount": 90, "trackTimescale": 3000, "frameDurationTicks": 100, "runCount": 1,
                     "slotShows": [[0, 0], [33, 33], [89, 89]], "originalAt": [[3, 3], [6, 6]]}))
    v.append(derive("vfr-dropped-burst", "VFR with a dropped-frame burst: six frames (nominal 40-45, 200 ms) never "
                    "arrived; slots 40-45 hold original frame 39 and the clock does not slip",
                    source("burst", original(jittered(20, 90, (0,), skip=range(40, 46)), timescale=600, nominal=FPS30,
                                             end=1800), FPS30),
                    {"proxyFrameCount": 90, "originalFrameCount": 84, "runCount": 3,
                     "slotShows": [[39, 39], [40, 39], [45, 39], [46, 40], [89, 83]],
                     "originalAt": [[39, 39], [40, 46], [83, 89]]}))
    v.append(derive("vfr-burst-90k", "Android-style 90 kHz timescale with jitter up to 600 ticks (6.7 ms) and eight "
                    "dropped frames (nominal 20-27)",
                    source("burst90k", original(jittered(3000, 60, JITTER90K, skip=range(20, 28)), timescale=90000,
                                                nominal=FPS30, end=180000), FPS30),
                    {"proxyFrameCount": 60, "originalFrameCount": 52,
                     "slotShows": [[19, 19], [20, 19], [27, 19], [28, 20], [59, 51]],
                     "originalAt": [[19, 19], [20, 28]]}))
    v.append(derive("vfr-tie-rounds-up", "One late frame lands exactly halfway (210 = 10.5 frames): it rounds up to slot "
                    "11, where frame 11 replaces it, so slot 10 holds frame 9 and frame 10 is never shown",
                    tie_source(),
                    {"proxyFrameCount": 30, "slotShows": [[9, 9], [10, 9], [11, 11], [29, 29]],
                     "originalAt": [[10, 11], [11, 11]]}))
    stall = cfr(600, FPS30, 15) + [355, 365, 375] + [20 * (i + 2) for i in range(18, 30)]
    v.append(derive("vfr-stall-catch-up", "A capture stall then a catch-up burst: frames 15-17 arrive 10 ms apart after "
                    "a gap, slots 15-17 hold frame 14, frame 15 is replaced by 16 in slot 18, and later frames shift by "
                    "two slots",
                    source("stall", original(stall, timescale=600, nominal=FPS30, end=640), FPS30),
                    {"proxyFrameCount": 32,
                     "slotShows": [[14, 14], [15, 14], [17, 14], [18, 16], [19, 17], [20, 18], [31, 29]],
                     "originalAt": [[15, 18], [16, 18], [17, 19], [18, 20]]}))
    v.append(derive("nonzero-start-pts", "An original whose first frame is at PTS 1200 (edit list): the proxy still "
                    "starts at zero and the run keeps the original PTS",
                    source("offset", original(cfr(600, FPS30, 30, start=1200), timescale=600, nominal=FPS30,
                                              end=1800), FPS30),
                    {"proxyFrameCount": 30, "runCount": 1, "runOriginalPts": [[0, 1200]],
                     "slotShows": [[0, 0], [29, 29]], "originalAt": [[0, 0], [29, 29]]}))
    v.append(derive("rotated-90-hdr-vfr", "S12: VFR + rotation 90 + HLG HDR: rotation baked once (3840x2160 shows as "
                    "1080x1920, no display rotation left), tone-mapped with the declared zscale method; frame 30 is on "
                    "a tie and slot 30 holds frame 29",
                    corner_source(),
                    {"proxyFrameCount": 60, "proxySize": [1080, 1920], "rotationAppliedDegrees": 90,
                     "toneMapMethod": "ffmpeg-zscale-tonemap",
                     "slotShows": [[29, 29], [30, 29], [31, 31], [59, 59]], "originalAt": [[30, 31]]}))
    v.append(derive("rotated-270-sdr", "Rotation 270 SDR 1920x1080: a portrait 1080x1920 proxy, no tone map",
                    source("r270", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600, rotation=270),
                           FPS30),
                    {"proxyFrameCount": 30, "proxySize": [1080, 1920], "rotationAppliedDegrees": 270,
                     "toneMapMethod": None, "slotShows": [[29, 29]], "originalAt": [[0, 0]]}))
    v.append(derive("rotated-180", "Rotation 180 keeps landscape: 1920x1080, rotation baked, no swap",
                    source("r180", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600, rotation=180),
                           FPS30),
                    {"proxyFrameCount": 30, "proxySize": [1920, 1080], "rotationAppliedDegrees": 180,
                     "toneMapMethod": None, "slotShows": [[0, 0]], "originalAt": [[29, 29]]}))
    v.append(derive("hdr-pq-landscape", "PQ HDR 3840x2160 into a 1920-wide SDR proxy with the libplacebo method declared",
                    source("pq", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600, width=3840,
                                          height=2160, hdr=True, transfer="pq"), FPS30, tone_map=PLACEBO),
                    {"proxyFrameCount": 30, "proxySize": [1920, 1080], "rotationAppliedDegrees": 0,
                     "toneMapMethod": "ffmpeg-libplacebo", "slotShows": [[15, 15]], "originalAt": [[15, 15]]}))
    v.append(derive("aspect-4-3", "A 4:3 1440x1080 source scaled to a 1920 long edge: 1920x1440, never cropped or padded",
                    source("four-three", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600,
                                                  width=1440, height=1080), FPS30),
                    {"proxyFrameCount": 30, "proxySize": [1920, 1440], "rotationAppliedDegrees": 0,
                     "slotShows": [[1, 1]], "originalAt": [[1, 1]]}))
    v.append(derive("aspect-even-rounding", "1366x768 to a 1920 long edge: 768 x 1920 / 1366 = 1079.47, rounded half-up "
                    "to the even 1080",
                    source("wxga", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600, width=1366,
                                            height=768), FPS30),
                    {"proxyFrameCount": 30, "proxySize": [1920, 1080], "slotShows": [[2, 2]], "originalAt": [[2, 2]]}))
    return v


def mutation_vectors() -> list[dict]:
    cfr60 = source("cfr60", original(cfr(600, FPS60, 120), timescale=600, nominal=FPS60, end=1200), FPS30)
    cfr24 = source("cfr24", original(cfr(600, FPS24, 48), timescale=600, nominal=FPS24, end=1200), FPS30)
    cfr120 = source("cfr120", original(cfr(600, FPS120, 240), timescale=600, nominal=FPS120, end=1200), FPS30)
    return [
        mutation("s4-half-even-ntsc-in-30", "S4: the mixed 29.97/30 case selected with half-even ties (Python round): "
                 "frame 500 rounds to slot 500, so slot 500 shows 500 instead of 499; the frame-selection test fails",
                 ntsc_source(), emit="half-even", decode="half-even",
                 assertions={"rejectCode": "frameSelectionMismatch", "slot": 500, "expectedFrame": 499,
                             "foundFrame": 500}),
        mutation("s4-half-even-60-to-30", "S4 at 60 to 30: half-even rounds frame 1 (0.5) down, so slot 0 shows frame 1",
                 cfr60, emit="half-even", decode="half-even",
                 assertions={"rejectCode": "frameSelectionMismatch", "slot": 0, "expectedFrame": 0, "foundFrame": 1}),
        mutation("s4-half-even-vfr-tie", "S4 on a VFR tie: half-even keeps frame 10 (10.5 to 10) in slot 10",
                 tie_source(), emit="half-even", decode="half-even",
                 assertions={"rejectCode": "frameSelectionMismatch", "slot": 10, "expectedFrame": 9, "foundFrame": 10}),
        mutation("half-down-24-to-30", "Ties down at 24 to 30: frame 2 (2.5) stays in slot 2, which should hold frame 1",
                 cfr24, emit="half-down", decode="half-down",
                 assertions={"rejectCode": "frameSelectionMismatch", "slot": 2, "expectedFrame": 1, "foundFrame": 2}),
        mutation("nearest-frame-120-to-30", "Choosing the nearest frame to each instant is not the rule: at 120 to 30 it "
                 "picks frame 0 for slot 0, where the rule (and FFmpeg) shows frame 1",
                 cfr120, emit="nearest", decode="nearest",
                 assertions={"rejectCode": "frameSelectionMismatch", "slot": 0, "expectedFrame": 1, "foundFrame": 0}),
        mutation("table-disagrees-with-frame-ids", "The proxy shows the right frames but the emitted table was computed "
                 "with half-even: the table no longer matches the decoded IDs 100% (slot 500 says 500, the ID is 499)",
                 ntsc_source(), emit="half-even", decode="half-up",
                 assertions={"rejectCode": "ptsTableMismatch"}),
    ]


def reject_vectors() -> list[dict]:
    hdr_no_map = source("hdr-no-map", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600, width=3840,
                                              height=2160, hdr=True, transfer="hlg"), FPS30)
    sdr_mapped = source("sdr-mapped", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600), FPS30,
                        tone_map=ZSCALE)
    back = cfr(600, FPS30, 30)
    back[12], back[13] = back[13], back[12]
    reversed_pts = source("reordered", original(back, timescale=600, nominal=FPS30, end=600), FPS30)
    hdr_709 = source("hdr-709", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600, hdr=True,
                                         transfer="bt709"), FPS30, tone_map=ZSCALE)
    early_end = source("early-end", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=580), FPS30)
    odd_edge = source("odd-edge", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600), FPS30,
                      long_edge=1919)
    corner = normalization.derive_table(corner_source())
    unswapped = copy.deepcopy(corner)
    unswapped["proxy"]["width"], unswapped["proxy"]["height"] = 1920, 1080
    coarse = copy.deepcopy(corner)
    coarse["proxy"]["timescale"], coarse["proxy"]["frameDurationTicks"] = 600, 20
    up = normalization.derive_table(source("up60", original(cfr(600, FPS30, 30), timescale=600, nominal=FPS30, end=600),
                                           FPS60))
    up["proxy"]["upconverted"] = False
    return [
        reject("hdr-without-tone-map", "An HDR original with no declared tone-map method is refused", hdr_no_map,
               "toneMapUndeclared"),
        reject("sdr-with-tone-map", "An SDR original is not tone-mapped", sdr_mapped, "toneMapOnSdr"),
        reject("pts-not-increasing", "Presentation timestamps out of order (decode order leaked in) are refused",
               reversed_pts, "badPtsIndex"),
        reject("hdr-with-bt709-transfer", "An HDR flag needs an HLG or PQ transfer", hdr_709, "colourMismatch"),
        reject("end-before-last-frame", "endPts must come after the last frame", early_end, "badPtsIndex"),
        reject("odd-long-edge", "A 4:2:0 proxy needs even dimensions", odd_edge, "badDimensions"),
        check("rotation-90-not-swapped", "A quarter-turn proxy left landscape (1920x1080) had its rotation dropped or "
              "applied as display metadata only", unswapped, "proxyRotation"),
        check("track-timescale-600", "A 600 track timescale is not lcm(30, 1000) = 3000", coarse, "badTimescale"),
        check("upconversion-unlabelled", "A 30 fps source in a 60 fps proxy must be labelled upconverted", up,
              "unlabelledUpconversion"),
    ]


def normalization_vectors() -> dict:
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "normalization",
            "status": "synthetic PTS indexes (Sample), not field evidence; 'assert' values are hand-derived from the "
                      "half-up rule in docs/research/studio/multicam-sync.md sections 5.2-5.5 and 8.2-8.3",
            "cases": derive_vectors() + mutation_vectors() + reject_vectors()}


# ----- the Sample record and its invalid cases ------------------------------------------------------

def sample_record() -> dict:
    return normalization.derive_table(corner_source())


def invalid_sets(record: dict) -> dict:
    half_even = normalization.derive_table(corner_source(), tie="half-even")["runs"]
    first = record["original"]["pts"][0]
    split = [{"value": first["value"], "step": 0, "count": 1},
             dict(first, value=first["value"] + first["step"], count=first["count"] - 1,
                  step=first["step"] if first["count"] > 2 else 0)]
    last_pts = normalization.expand_pts(record["original"]["pts"])[-1]
    return invalid_docs({RECORD: [
        bad("rotation-not-swapped", "A quarter-turn proxy keeps the display orientation (1080x1920), not the coded one",
            [rep("/proxy/width", 1920), rep("/proxy/height", 1080)], "proxyRotation"),
        bad("rotation-not-applied", "The rotation is baked into the pixels exactly once",
            [rep("/proxy/rotationAppliedDegrees", 0)], "proxyRotation"),
        bad("rotation-applied-twice", "Display rotation left in the container would be applied again by players",
            [rep("/proxy/displayRotationDegrees", 90)]),
        bad("hdr-tone-map-omitted", "An HDR original declares its tone-map method", [rep("/proxy/toneMap", None)],
            "toneMapUndeclared"),
        bad("tone-map-unknown-method", "Tone-map methods come from the closed list",
            [rep("/proxy/toneMap/method", "auto")]),
        bad("sdr-tone-mapped", "An SDR original is not tone-mapped",
            [rep("/original/hdr", False), rep("/original/transfer", "bt709")], "toneMapOnSdr"),
        bad("proxy-left-hdr", "A render proxy is 8-bit BT.709", [rep("/proxy/transfer", "hlg")]),
        bad("track-timescale-600", "The track timescale is lcm(fps num, 1000)",
            [rep("/proxy/timescale", 600), rep("/proxy/frameDurationTicks", 20)], "badTimescale"),
        bad("nonzero-start", "Render proxies start at zero", [rep("/proxy/startPts", 1001)]),
        bad("half-even-selection-forged", "Runs computed with half-even ties select frame 30 for slot 30",
            [rep("/runs", half_even)], "ptsTableMismatch"),
        bad("frame-count-off-by-one", "The proxy frame count follows the half-up rule",
            [rep("/proxy/frameCount", record["proxy"]["frameCount"] + 1)], "ptsTableMismatch"),
        bad("pts-runs-not-canonical", "An equivalent but non-canonical PTS index would hash differently",
            [rep("/original/pts", split + record["original"]["pts"][1:])], "badPtsIndex"),
        bad("pts-frame-count-wrong", "The PTS index counts the original's frames",
            [rep("/original/frameCount", record["original"]["frameCount"] + 1)], "badPtsIndex"),
        bad("end-before-last-frame", "endPts follows the last frame", [rep("/original/endPts", last_pts)], "badPtsIndex"),
        bad("upconversion-unlabelled", "A 60 fps proxy of a 30 fps source is labelled upconverted",
            [rep("/proxy/fps", {"num": 60, "den": 1}), rep("/proxy/frameDurationTicks", 50)], "unlabelledUpconversion"),
        bad("short-edge-not-even", "The proxy keeps the display aspect with an even short edge",
            [rep("/proxy/width", 1078)], "badDimensions"),
        bad("fps-as-float", "Rates are exact rationals, never floats", [rep("/proxy/fps", {"num": 29.97, "den": 1})]),
    ]})


# ----- what this module declares and registers ----------------------------------------------------

def fixtures(sample) -> dict:
    record = sample_record()
    docs = {"vectors/normalization.json": normalization_vectors(), f"records/{RECORD}.json": record}
    for name, doc in invalid_sets(record).items():
        docs[f"invalid/{name}.invalid.json"] = doc
    return docs


def _check_derive(ctx, case, report, where) -> None:
    table = case["expect"]["table"]
    errors = ctx.schemas.validate(table, "pts-table.schema.json")
    if errors:
        report.fail(where, "expected table fails pts-table.schema.json: " + "; ".join(errors[:3]))
        return
    if normalization.derive_table(case["input"]) != table:
        report.fail(where, "the reference derives a different table")
        return
    if normalization.table_sha256(table) != case["expect"]["sha256"]:
        report.fail(where, "stored sha256 is not the canonical hash of the table")
        return
    normalization.check_pts_table(table)
    normalization.check_conformance(case["input"]["original"], table["proxy"]["fps"], table,
                                    normalization.expand_runs(table["runs"]))
    ticks = case["expect"]["proxyFrameOfOriginal"]
    problems = [] if ticks == normalization.original_to_proxy(table) else ["proxyFrameOfOriginal differs from the reference"]
    problems += _hand_assertions(table, ticks, case["assert"])
    for problem in problems:
        report.fail(where, problem)
    if not problems:
        report.ok("normalization vectors (derive)")


def _hand_assertions(table: dict, ticks: list[int], a: dict) -> list[str]:
    """The hand-derived values, read straight off the stored table (no reference call)."""
    proxy, slots, problems = table["proxy"], [], []
    for r in table["runs"]:
        slots += [r["originalFrame"] + j * r["originalStep"] for j in range(r["count"])]
    simple = {"proxyFrameCount": proxy["frameCount"], "trackTimescale": proxy["timescale"],
              "frameDurationTicks": proxy["frameDurationTicks"], "runCount": len(table["runs"]),
              "upconverted": proxy["upconverted"], "originalFrameCount": table["original"]["frameCount"],
              "proxySize": [proxy["width"], proxy["height"]], "rotationAppliedDegrees": proxy["rotationAppliedDegrees"],
              "toneMapMethod": proxy["toneMap"]["method"] if proxy["toneMap"] else None}
    for key, value in a.items():
        if key in simple and simple[key] != value:
            problems.append(f"{key} is {simple[key]!r}, hand-derived {value!r}")
    if len(slots) != proxy["frameCount"]:
        problems.append(f"the runs cover {len(slots)} proxy frames, frameCount says {proxy['frameCount']}")
    for slot, frame in a.get("slotShows", []):
        if slot >= len(slots) or slots[slot] != frame:
            problems.append(f"proxy frame {slot} shows original {slots[slot] if slot < len(slots) else None}, "
                            f"hand-derived {frame}")
    for frame, proxy_frame in a.get("originalAt", []):
        if ticks[frame] != proxy_frame:
            problems.append(f"original frame {frame} maps to proxy frame {ticks[frame]}, hand-derived {proxy_frame}")
    for index, value in a.get("runOriginalPts", []):
        if table["runs"][index]["originalPts"] != value:
            problems.append(f"run {index} originalPts {table['runs'][index]['originalPts']}, hand-derived {value}")
    return problems


def _check_refusal(ctx, case, report, where, run) -> None:
    code = case["assert"]["rejectCode"]
    try:
        run()
    except Reject as exc:
        got = {"rejectCode": exc.code}
        if isinstance(exc, normalization.FrameSelectionMismatch):
            got.update(slot=exc.slot, expectedFrame=exc.expected, foundFrame=exc.found)
        if got != case["expect"]:
            report.fail(where, f"refused with {got}, stored expectation {case['expect']}")
        elif any(got.get(k) != v for k, v in case["assert"].items()):
            report.fail(where, f"refused with {got}, hand-derived {case['assert']}")
        else:
            report.ok(f"normalization vectors ({case['mode']}, refused)")
        return
    report.fail(where, f"accepted; expected {code}")


def check_normalization_vector(ctx, case, report, where) -> None:
    mode = case["mode"]
    if mode == "derive":
        _check_derive(ctx, case, report, where)
    elif mode == "mutation":
        inp = case["input"]

        def run():
            emitted, _ = normalizer_output(inp, case["mutation"]["emit"])
            _, decoded = normalizer_output(inp, case["mutation"]["decode"])
            normalization.check_conformance(inp["original"], inp["proxy"]["fps"], emitted, decoded)
        _check_refusal(ctx, case, report, where, run)
    elif mode == "reject":
        _check_refusal(ctx, case, report, where, lambda: normalization.derive_table(case["input"]))
    elif mode == "check":
        errors = ctx.schemas.validate(case["table"], "pts-table.schema.json")
        if errors:
            report.fail(where, "a check case must pass the schema so the reference is what refuses it: " + errors[0])
            return
        _check_refusal(ctx, case, report, where, lambda: normalization.check_pts_table(case["table"]))
    else:
        report.fail(where, f"unknown mode {mode!r}")


def check_pts_table_record(ctx, doc):
    return normalization.check_pts_table(doc)


VECTOR_CHECKERS = {"normalization": check_normalization_vector}
SCHEMAS = {"jovra.pts-table/1": "pts-table.schema.json"}
RECORD_RULES = {"jovra.pts-table/1": check_pts_table_record}


# ----- self-tests ---------------------------------------------------------------------------------

def check_tie_coverage(ctx, report) -> None:
    """The half-even mutation is not vacuous: enough derive vectors contain an exact tie whose half-even selection
    differs, so a platform port that rounds like Python's round() fails them; and every S4 mutation vector names a
    source that really has a tie."""
    doc = ctx.fixture("vectors/normalization.json")
    differing = 0
    for case in doc["cases"]:
        if case["mode"] != "derive":
            continue
        orig, fps = case["input"]["original"], case["input"]["proxy"]["fps"]
        if normalization.select_frames(orig, fps, "half-even") != normalization.select_frames(orig, fps):
            differing += 1
    if differing < 5:
        report.fail("self-test normalization-tie-coverage", f"only {differing} derive vectors separate half-up from "
                                                            "half-even (need at least 5)")
    else:
        report.ok("normalization tie-coverage self-tests")
    for case in doc["cases"]:
        if case["mode"] == "mutation" and "half-even" in case["mutation"].values():
            orig, fps = case["input"]["original"], case["input"]["proxy"]["fps"]
            pts = normalization.original_pts(orig)
            scale = Fraction(fps["num"], fps["den"] * orig["timescale"])
            if not any(normalization.is_tie((p - pts[0]) * scale) for p in pts):
                report.fail("self-test normalization-tie-coverage", f"{case['id']} has no tie to mutate")
            else:
                report.ok("normalization tie-coverage self-tests")


def check_pts_queries(ctx, report) -> None:
    """Analysis and sync map original PTS into the proxy with the same half-up rule: on the Sample record every
    original frame's PTS lands on its tick (None past the end), a PTS exactly between two slots goes up, and a PTS
    before the first frame is refused."""
    table = ctx.records[RECORD]
    pts = normalization.expand_pts(table["original"]["pts"])
    ticks = normalization.original_to_proxy(table)
    n = table["proxy"]["frameCount"]
    wrong = [i for i, p in enumerate(pts) if normalization.proxy_frame_of(table, p) != (ticks[i] if ticks[i] < n else None)]
    if wrong:
        report.fail("self-test normalization-pts-queries", f"original frames {wrong[:5]} map off their tick")
    elif normalization.proxy_frame_of(table, pts[0] + 10) != 1:   # 10 ticks of 600 = half a 30 fps frame
        report.fail("self-test normalization-pts-queries", "a PTS half a frame in does not round up to proxy frame 1")
    else:
        report.ok("normalization pts-query self-tests")
    try:
        normalization.proxy_frame_of(table, pts[0] - 1) if pts[0] > 0 else normalization.proxy_frame_of(table, -1)
    except Reject as exc:
        if exc.code == "badPtsIndex":
            report.ok("normalization pts-query self-tests")
            return
        report.fail("self-test normalization-pts-queries", f"refused with {exc.code}, expected badPtsIndex")
        return
    report.fail("self-test normalization-pts-queries", "a PTS before the first frame was accepted")


SELF_TESTS = {"normalization-tie-coverage": check_tie_coverage, "normalization-pts-queries": check_pts_queries}
