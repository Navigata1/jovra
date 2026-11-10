"""Court geometry and calibration fixtures (T13; jovra.fixture.calibration, spec/fixtures/calibration/C*.json).

Engine: jovra_ref/court.py (normalized DLT, project/unproject, the reprojection check, validity, tap mapping,
depth bins, zones and placement words). The synthetic calibrated frame is the renderer's behind-baseline camera
(scripts/media/jovra_media/court3d.py, mirrored in jovra_ref.sample_match.project) at 1920 x 1080: every court
point's true pixel comes from that pinhole camera, never from the homography under test, so the fits are checked
against an independent source. Jittered taps come from a seeded SplitMix64 in whole millipixels inside a 2 px disc.

Floats are rounded to 9 decimal places so the bytes are the same on every machine; each case states the tolerance
a platform compares with. The generator refuses to write a case whose hand-stated facts do not hold (an exact
four-point solve reproduces its taps within 1e-6 px; a perturbed fit reads poor; a twisted fit reads poor with or
without measured lines and a fit stated untwisted is not; past staleFromMs reads stale), and CHECKS re-runs every
case in the validator.
"""

from __future__ import annotations

import math

from jovra_ref import court, sample_match

ORDER = 60
VERSION = "1.0.0"
WIDTH, HEIGHT = 1920, 1080
TOL_PX, TOL_M, TOL_H = 1e-6, 1e-6, 1e-7
JITTER_SEED = 20261113
JITTER_MAX_MILLIPX = 2000


def r9(v: float) -> float:
    return round(v, 9)


def pt(p) -> dict | None:
    return None if p is None else {"x": r9(p[0]), "y": r9(p[1])}


def tup(d: dict) -> tuple[float, float]:
    return d["x"], d["y"]


def camera(p, width: int = WIDTH, height: int = HEIGHT) -> tuple[float, float]:
    """True pixel of a court point (net-centre metres) in the synthetic behind-baseline frame."""
    return sample_match.project((p[0], p[1] + court.HALF_LENGTH, 0.0), width, height)


def taps(names: list[str], jitter: list[tuple[int, int]] | None = None) -> list[dict]:
    out = []
    for i, n in enumerate(names):
        u, v = camera(court.POINTS[n])
        if jitter:
            u, v = u + jitter[i][0] / 1000, v + jitter[i][1] / 1000
        out.append(pt((u, v)))
    return out


def jitters(rng: sample_match.SplitMix64) -> list[tuple[int, int]]:
    """Four offsets in whole millipixels, each inside the 2 px disc (rejection sampling)."""
    out = []
    while len(out) < 4:
        dx = rng.between(-JITTER_MAX_MILLIPX, JITTER_MAX_MILLIPX)
        dy = rng.between(-JITTER_MAX_MILLIPX, JITTER_MAX_MILLIPX)
        if dx * dx + dy * dy <= JITTER_MAX_MILLIPX * JITTER_MAX_MILLIPX:
            out.append((dx, dy))
    return out


# ----- fit cases ----------------------------------------------------------------------------------

def fit_case(name: str, image: list[dict], court_names: list[str] | None = None, court_pts: list[dict] | None = None,
             frame=(WIDTH, HEIGHT), record: dict | None = None, untapped_truth: bool = True) -> dict:
    cpts = court_pts or [pt(court.POINTS[n]) for n in court_names]
    h = court.fit([tup(p) for p in image], [tup(p) for p in cpts])
    for c, i in zip(cpts, image):
        if len(image) == 4:
            p = court.project(h, tup(c))
            if math.sqrt((p[0] - i["x"]) ** 2 + (p[1] - i["y"]) ** 2) > TOL_PX:
                raise ValueError(f"{name}: an exact four-point solve must reproduce its taps within {TOL_PX} px")
    tapped = {(c["x"], c["y"]) for c in cpts}
    project = [{"id": n, "court": pt(p), "pixel": pt(court.project(h, p))} for n, p in court.INTERSECTIONS]
    unproject = []
    for n, p in court.INTERSECTIONS:
        if (r9(p[0]), r9(p[1])) in tapped or not untapped_truth:
            continue
        seen = camera(p, *frame)
        est = court.unproject(h, seen)
        err = math.sqrt((est[0] - p[0]) ** 2 + (est[1] - p[1]) ** 2)
        unproject.append({"id": n, "pixel": pt(seen), "court": pt(est), "truth": pt(p), "errorM": r9(err),
                          "withinTenCm": err <= 0.10})
    case = {"op": "fit", "name": name}
    if record is not None:
        case["record"] = record
    else:
        case.update({"imagePoints": image, "courtPoints": cpts})
    case["expected"] = {"homography": [r9(v) for row in h for v in row], "project": project, "unproject": unproject}
    case["tolerance"] = {"px": TOL_PX, "m": TOL_M, "homographyRelative": TOL_H}
    return case


def error_case(name: str, image: list[dict], cpts: list[dict], code: str) -> dict:
    try:
        court.fit([tup(p) for p in image], [tup(p) for p in cpts])
    except court.CalibrationError as e:
        if e.code != code:
            raise ValueError(f"{name}: expected {code}, engine says {e.code}")
        return {"op": "fit", "name": name, "imagePoints": image, "courtPoints": cpts, "expectedError": code}
    raise ValueError(f"{name}: expected {code}, engine fitted")


def sample_record() -> dict:
    """The T40 serve-practice calibration (720p, singles corners, normalized image points)."""
    import json
    from pathlib import Path
    path = Path(__file__).resolve().parents[2] / "fixtures/sample/analysis/sessions/2026-10-04-serve-practice.analysis.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    return doc["calibrations"][0]


def record_points(record: dict) -> tuple[list[dict], list[dict]]:
    w, h = record["camera"]["width"], record["camera"]["height"]
    return [pt((p["x"] * w, p["y"] * h)) for p in record["imagePoints"]], record["courtPoints"]


def c01() -> tuple:
    rec = sample_record()
    image, cpts = record_points(rec)
    sample = fit_case("the T40 sample serve-practice calibration (720p, singles corners, normalized points)",
                      image, court_pts=cpts, frame=(rec["camera"]["width"], rec["camera"]["height"]), record=rec)
    return ("C01-exact-four-point", "Exact four-point solve: taps reproduced, every line intersection projected", [
        fit_case("doubles corners on the synthetic 1080p behind-baseline frame", taps(court.DOUBLES_CORNERS),
                 court.DOUBLES_CORNERS),
        fit_case("singles corners on the synthetic 1080p behind-baseline frame", taps(court.SINGLES_CORNERS),
                 court.SINGLES_CORNERS),
        fit_case("taps given in another order fit the same homography",
                 taps([court.DOUBLES_CORNERS[i] for i in (2, 0, 3, 1)]), [court.DOUBLES_CORNERS[i] for i in (2, 0, 3, 1)]),
        sample,
    ])


def c02() -> tuple:
    eight = court.DOUBLES_CORNERS + ["nearLeftService", "nearRightService", "farRightService", "farLeftService"]
    rng = sample_match.SplitMix64(JITTER_SEED + 2)
    every = [n for n, _ in court.INTERSECTIONS]
    noise = [(rng.between(-1500, 1500), rng.between(-1500, 1500)) for _ in every]
    noisy = []
    for (u, v), (dx, dy) in zip([camera(court.POINTS[n]) for n in every], noise):
        noisy.append(pt((u + dx / 1000, v + dy / 1000)))
    return ("C02-least-squares", "More than four points: least squares (exact data recovers the camera)", [
        fit_case("eight exact points recover the same homography as four", taps(eight), eight),
        fit_case("all sixteen intersections with up to 1.5 px of noise each: the least-squares fit", noisy, every,
                 untapped_truth=False),
    ])


def c03() -> tuple:
    rng = sample_match.SplitMix64(JITTER_SEED)
    cases = []
    for k in range(6):
        j = jitters(rng)
        cases.append(fit_case(f"doubles corners jittered inside a 2 px disc, draw {k + 1}", taps(court.DOUBLES_CORNERS, j),
                              court.DOUBLES_CORNERS))
    return ("C03-jittered-corners", "Corners tapped up to 2 px off: where the untapped intersections land on court",
            cases)


def check_case(name: str, image: list[dict], cpts_names: list[str], observed: list[str], height: int,
               expect: str, scale_from: int = HEIGHT, twisted: bool = False) -> dict:
    """`twisted` states by hand that the taps are a quad no camera can produce (two sides cross, or one corner lies
    inside the triangle of the other three). The generator refuses the case when the engine disagrees in either
    direction: `court.is_twisted`, the fit failing to project one of its own tapped corners, and a poor verdict
    all have to hold for a twisted case, with or without measured lines."""
    cpts = [court.POINTS[n] for n in cpts_names]
    h = court.fit([tup(p) for p in image], cpts)
    obs = [(court.POINTS[n], tuple(v * height / scale_from for v in camera(court.POINTS[n]))) for n in observed]
    result = court.fit_check(h, obs, height, cpts)
    if result["verdict"] != expect:
        raise ValueError(f"{name}: expected {expect}, engine says {result['verdict']} ({result['rmsePx']})")
    if twisted != court.is_twisted(h, cpts) or twisted != any(court.project(h, c) is None for c in cpts):
        raise ValueError(f"{name}: twisted is stated {twisted}, the engine's projections of the tapped corners disagree")
    if twisted and result["verdict"] != "poor":
        raise ValueError(f"{name}: a twisted fit must read poor, measured or not, got {result}")
    if not obs and result["rmsePx"] is not None:
        raise ValueError(f"{name}: nothing was measured, so there is no RMSE to state, got {result}")
    return {"op": "check", "name": name, "imagePoints": image, "courtPoints": [pt(c) for c in cpts],
            "frameHeight": height,
            "observations": [{"court": pt(c), "pixel": pt(p)} for c, p in obs],
            "expected": {"verdict": result["verdict"],
                         "rmsePx": None if result["rmsePx"] is None else r9(result["rmsePx"]),
                         "thresholdPx": r9(result["thresholdPx"]),
                         "twisted": twisted},
            "tolerance": {"px": TOL_PX}}


UNTAPPED = [n for n, _ in court.INTERSECTIONS if n not in court.DOUBLES_CORNERS]
# The doubles corners with the two far (or near) brackets on each other's corner: the taps cross, a bow tie.
FAR_SWAPPED = [court.DOUBLES_CORNERS[i] for i in (0, 1, 3, 2)]
NEAR_SWAPPED = [court.DOUBLES_CORNERS[i] for i in (1, 0, 2, 3)]
# Wrong corners that still make a convex quad: every bracket one corner round, and left swapped with right at both
# ends. These fix a homography that places every court point, so only measured lines tell them from a true fit.
ROTATED = [court.DOUBLES_CORNERS[i] for i in (1, 2, 3, 0)]
MIRRORED = [court.DOUBLES_CORNERS[i] for i in (1, 0, 3, 2)]


def scaled_taps(names: list[str], height: int, offsets: dict | None = None, moved: dict | None = None) -> list[dict]:
    """Taps on the true pixels of `names`. `offsets` nudges a tap by 1080p pixels; `moved` puts it at an absolute
    1080p pixel instead (a bracket dragged somewhere else entirely)."""
    out = []
    for n in names:
        u, v = (moved or {}).get(n) or camera(court.POINTS[n])
        du, dv = (offsets or {}).get(n, (0, 0))
        out.append(pt(((u + du) * height / HEIGHT, (v + dv) * height / HEIGHT)))
    return out


def c04() -> tuple:
    off = {"farRightDoubles": (9.0, -7.0)}
    return ("C04-fit-check", "The check that can fail: reprojection RMSE of untapped lines, 3 px at 1080p", [
        check_case("exact taps: the untapped lines match", scaled_taps(court.DOUBLES_CORNERS, 1080),
                   court.DOUBLES_CORNERS, UNTAPPED, 1080, "good"),
        check_case("one far corner tapped 11 px off: a poor fit", scaled_taps(court.DOUBLES_CORNERS, 1080, off),
                   court.DOUBLES_CORNERS, UNTAPPED, 1080, "poor"),
        check_case("the same taps scaled to 720p: the threshold is 2 px", scaled_taps(court.DOUBLES_CORNERS, 720, off),
                   court.DOUBLES_CORNERS, UNTAPPED, 720, "poor"),
        check_case("a far corner 2 px off at 1080p stays a good fit",
                   scaled_taps(court.DOUBLES_CORNERS, 1080, {"farRightDoubles": (2.0, 0.0)}),
                   court.DOUBLES_CORNERS, UNTAPPED, 1080, "good"),
        check_case("no line pixels measured: not measurable, never a pass", scaled_taps(court.DOUBLES_CORNERS, 1080),
                   court.DOUBLES_CORNERS, [], 1080, "notMeasurable"),
        # Story 66, the grossly wrong fits: a bracket dragged across the court twists the quad until measured lines
        # fall on or beyond the fit's own horizon. They were measured, so the fit is poor (and so invalid, C05); no
        # RMSE is invented for a line the fit puts nowhere.
        check_case("the far right bracket dragged to the middle of the court: measured lines beyond the horizon, poor",
                   scaled_taps(court.DOUBLES_CORNERS, 1080, moved={"farRightDoubles": (960.0, 600.0)}),
                   court.DOUBLES_CORNERS, UNTAPPED, 1080, "poor", twisted=True),
        check_case("the far brackets swapped (a self-intersecting quad): poor",
                   scaled_taps(FAR_SWAPPED, 1080), court.DOUBLES_CORNERS, UNTAPPED, 1080, "poor", twisted=True),
        check_case("the far right bracket dragged below the near baseline: poor",
                   scaled_taps(court.DOUBLES_CORNERS, 1080,
                               moved={"farRightDoubles": (camera(court.POINTS["farRightDoubles"])[0], 1000.0)}),
                   court.DOUBLES_CORNERS, UNTAPPED, 1080, "poor", twisted=True),
        check_case("the same twisted taps at 720p: poor at every frame size",
                   scaled_taps(FAR_SWAPPED, 720), court.DOUBLES_CORNERS, UNTAPPED, 720, "poor", twisted=True),
        # No line detector exists until V02, so the app measures nothing today. A twisted quad is caught from the
        # taps alone: the fit puts its own tapped corners beyond its horizon, and that is poor before any line is seen.
        check_case("the far brackets swapped with no line pixels measured: poor, nothing needs measuring",
                   scaled_taps(FAR_SWAPPED, 1080), court.DOUBLES_CORNERS, [], 1080, "poor", twisted=True),
        check_case("the near brackets swapped with no line pixels measured: poor",
                   scaled_taps(NEAR_SWAPPED, 1080), court.DOUBLES_CORNERS, [], 1080, "poor", twisted=True),
        check_case("the far right bracket dragged to the middle of the court with no line pixels measured: poor",
                   scaled_taps(court.DOUBLES_CORNERS, 1080, moved={"farRightDoubles": (960.0, 600.0)}),
                   court.DOUBLES_CORNERS, [], 1080, "poor", twisted=True),
        check_case("the far right bracket dragged below the near baseline with no line pixels measured: poor",
                   scaled_taps(court.DOUBLES_CORNERS, 1080,
                               moved={"farRightDoubles": (camera(court.POINTS["farRightDoubles"])[0], 1000.0)}),
                   court.DOUBLES_CORNERS, [], 1080, "poor", twisted=True),
        # The limit of the twist rule, stated: wrong corners in a convex order are a homography like any other.
        check_case("every bracket one corner round (a convex quad) with no line pixels measured: not twisted, not measurable",
                   scaled_taps(ROTATED, 1080), court.DOUBLES_CORNERS, [], 1080, "notMeasurable"),
        check_case("every bracket one corner round with the lines measured: poor by its residual",
                   scaled_taps(ROTATED, 1080), court.DOUBLES_CORNERS, UNTAPPED, 1080, "poor"),
        check_case("left and right brackets swapped at both ends (a mirrored quad), nothing measured: not twisted, not measurable",
                   scaled_taps(MIRRORED, 1080), court.DOUBLES_CORNERS, [], 1080, "notMeasurable"),
    ])


def validity_case(name: str, current: dict | None = None, stale: int | None = None, at: int = 60_000,
                  check: str | None = None, expect: dict | None = None, recorded: str | None = None,
                  twisted: bool = False) -> dict:
    """`twisted` is the fact C04 states per fit (`expected.twisted`); a twisted fit never pairs with a check that is
    good or not measurable, because the check reads poor for it (`court.fit_check`), except for a reopened record,
    whose stored residual was measured by whoever wrote it."""
    binding = {"lens": "wide", "width": 1920, "height": 1080, "zoomFactor": "1.0"}
    cur = {**binding, **(current or {})}
    chk = None if check is None else {"verdict": check}
    if twisted and check in ("good", "notMeasurable") and recorded is None:
        raise ValueError(f"{name}: a twisted fit's own check is poor, never {check}")
    got = court.validity(binding, cur, stale, at, chk, recorded, twisted)
    if got != expect:
        raise ValueError(f"{name}: expected {expect}, engine says {got}")
    case = {"op": "validity", "name": name, "binding": binding, "current": cur, "staleFromMs": stale, "atMs": at,
            "check": chk, "expected": got}
    if recorded is not None:
        case["recordedStatus"] = recorded
    if twisted:
        case["twisted"] = True
    return case


def c05() -> tuple:
    return ("C05-validity", "Validity is bound to lens, format, zoom and the stale-from time", [
        validity_case("same camera, good fit, no camera move: valid", check="good", expect={"status": "valid"}),
        validity_case("an untwisted fit with nothing measured is still usable (the check reports it)",
                      check="notMeasurable", expect={"status": "valid"}),
        # A twisted fit needs no measurement to be unusable (C04 states which fits are twisted).
        validity_case("a twisted fit that was never checked is a poor fit", twisted=True,
                      expect={"status": "invalid", "reason": "poorFit"}),
        validity_case("a twisted fit checked with nothing measured is a poor fit", check="poor", twisted=True,
                      expect={"status": "invalid", "reason": "poorFit"}),
        validity_case("a twisted fit is a poor fit before the camera moved, too", stale=120_000, at=0, twisted=True,
                      expect={"status": "invalid", "reason": "poorFit"}),
        validity_case("a camera reason is reported before a twisted fit", {"lens": "ultraWide"}, twisted=True,
                      expect={"status": "invalid", "reason": "lensChanged"}),
        validity_case("before the camera moved: valid", stale=120_000, at=119_999, expect={"status": "valid"}),
        validity_case("from the moment the camera moved: stale", stale=120_000, at=120_000,
                      expect={"status": "invalid", "reason": "stale", "staleFromMs": 120_000}),
        validity_case("a poor fit is invalid", check="poor", expect={"status": "invalid", "reason": "poorFit"}),
        validity_case("another lens", {"lens": "ultraWide"}, expect={"status": "invalid", "reason": "lensChanged"}),
        validity_case("another format", {"width": 3840, "height": 2160},
                      expect={"status": "invalid", "reason": "formatChanged"}),
        validity_case("another zoom", {"zoomFactor": "2.0"}, expect={"status": "invalid", "reason": "zoomChanged"}),
        validity_case("the same zoom written differently", {"zoomFactor": "1.00"}, expect={"status": "valid"}),
        validity_case("lens is reported before a stale time", {"lens": "telephoto"}, stale=0, check="poor",
                      expect={"status": "invalid", "reason": "lensChanged"}),
        # A reopened record: refitting its taps always succeeds, so the status it was stored with is carried.
        validity_case("a record stored valid reopens valid", check="good", recorded="valid", expect={"status": "valid"}),
        validity_case("a record stored invalid stays invalid", recorded="invalid",
                      expect={"status": "invalid", "reason": "recordedInvalid"}),
        validity_case("a record stored needing review stays unusable", check="good", recorded="needsReview",
                      expect={"status": "invalid", "reason": "needsReview"}),
        validity_case("a record stored camera-moved with no time is unusable throughout", at=0, recorded="cameraMoved",
                      expect={"status": "invalid", "reason": "cameraMoved"}),
        validity_case("a record stored camera-moved with a time is valid before it", stale=120_000, at=119_999,
                      recorded="cameraMoved", expect={"status": "valid"}),
        validity_case("and stale from that time", stale=120_000, at=120_000, recorded="cameraMoved",
                      expect={"status": "invalid", "reason": "stale", "staleFromMs": 120_000}),
        validity_case("a stored poor fit is reported before the stored status", check="poor", recorded="needsReview",
                      expect={"status": "invalid", "reason": "poorFit"}),
        validity_case("a record stored valid with twisted taps reopens as a poor fit", recorded="valid", twisted=True,
                      expect={"status": "invalid", "reason": "poorFit"}),
        validity_case("a good stored residual does not outrank twisted taps", check="good", recorded="valid",
                      twisted=True, expect={"status": "invalid", "reason": "poorFit"}),
    ])


def map_case(name: str, op: str, point: tuple, view: tuple, video: tuple, gravity: str, expect) -> dict:
    fn = court.view_to_video if op == "viewToVideo" else court.video_to_view
    got = fn(point, view, video, gravity)
    if (got is None) != (expect is None) or (got and max(abs(a - b) for a, b in zip(got, expect)) > 1e-9):
        raise ValueError(f"{name}: expected {expect}, engine says {got}")
    return {"op": op, "name": name, "gravity": gravity, "view": {"width": view[0], "height": view[1]},
            "video": {"width": video[0], "height": video[1]}, "point": pt(point), "expected": pt(got),
            "tolerance": {"px": TOL_PX}}


def c06() -> tuple:
    # A 1920 x 1080 video in a 393 x 852 pt portrait view: scale 393/1920, letterbox bars 426 - 110.53... above.
    s = 393 / 1920
    top = (852 - 1080 * s) / 2
    return ("C06-tap-mapping", "Taps become video pixels before fitting (aspect fit and fill)", [
        map_case("portrait phone, landscape video: the centre", "viewToVideo", (196.5, 426.0), (393, 852), (1920, 1080),
                 "resizeAspect", (960.0, 540.0)),
        map_case("portrait phone: the top-left video corner sits below the letterbox bar", "viewToVideo", (0.0, top),
                 (393, 852), (1920, 1080), "resizeAspect", (0.0, 0.0)),
        map_case("a tap on the letterbox bar is no video pixel", "viewToVideo", (100.0, 20.0), (393, 852), (1920, 1080),
                 "resizeAspect", None),
        map_case("landscape phone, landscape video: pillarbox", "viewToVideo", (852 / 2 + 100.0, 196.5), (852, 393),
                 (1920, 1080), "resizeAspect", (960 + 100 * 1080 / 393, 540.0)),
        map_case("aspect fill crops the sides", "viewToVideo", (0.0, 0.0), (393, 852), (1920, 1080), "resizeAspectFill",
                 ((1920 - 393 * 1080 / 852) / 2, 0.0)),
        map_case("video pixels back to the view (drawing the guide)", "videoToView", (1920.0, 1080.0), (393, 852),
                 (1920, 1080), "resizeAspect", (393.0, top + 1080 * s)),
    ])


def c07() -> tuple:
    four = taps(court.DOUBLES_CORNERS)
    cpts = [pt(court.POINTS[n]) for n in court.DOUBLES_CORNERS]
    collinear = [{"x": 100.0, "y": 100.0}, {"x": 200.0, "y": 200.0}, {"x": 300.0, "y": 300.0}, {"x": 900.0, "y": 100.0}]
    return ("C07-refused", "Inputs that do not fix a homography are refused with a shared code", [
        error_case("three taps", four[:3], cpts[:3], "tooFewPoints"),
        error_case("four taps, three court points", four, cpts[:3], "countMismatch"),
        error_case("three taps on one line", collinear, cpts, "degenerate"),
        error_case("the same tap four times", [four[0]] * 4, cpts, "degenerate"),
    ])


def c08() -> tuple:
    geometry = {
        "lines": [{"id": i, "kind": k, "from": pt(a), "to": pt(b)} for i, k, a, b in court.LINES],
        "intersections": [{"id": n, "point": pt(p)} for n, p in court.INTERSECTIONS],
        "tappedCorners": {"doubles": court.DOUBLES_CORNERS, "singles": court.SINGLES_CORNERS},
        "depthBins": [{"id": i, "fromM": r9(a), "toM": r9(b)} for i, a, b in court.DEPTH_BINS],
    }
    if not any(i == "centreServiceLine" and abs(a[1]) == court.SERVICE_LINE and abs(b[1]) == court.SERVICE_LINE
               for i, _, a, b in court.LINES):
        raise ValueError("the centre service line must run only between the service lines")
    cases = [{"op": "geometry", "name": "the ITF court model in metres", "expected": geometry}]
    for x, y in [(0.5, 3.0), (-2.0, 6.4), (3.9, 6.41), (-1.2, 11.885), (0.0, 12.5), (-5.0, -8.0), (4.2, 2.0),
                 (1.0, -5.0), (-1.0, 5.0), (2.0, 5.0), (-3.5, 4.0), (5.485, 11.885)]:
        cases.append({"op": "classify", "name": f"landing at ({x}, {y})", "point": pt((x, y)), "expected": {
            "depth": court.depth_bin(y), "serviceZone": court.service_zone(x), "serviceBox": court.service_box(x, y),
            "inSingles": court.inside(x, y, False), "inDoubles": court.inside(x, y, True)}})
    return ("C08-geometry", "CourtGeometry: lines, intersections, depth bins and service zones", cases)


def describe_case(name: str, landing: tuple, hitter_x: float | None, result: str, doubles: bool, english: str) -> dict:
    words = court.placement_words({"x": landing[0], "y": landing[1]}, hitter_x, result, doubles)
    said = court.english(words)
    if said != english:
        raise ValueError(f"{name}: expected {english!r}, engine says {said!r}")
    return {"op": "describe", "name": name, "landing": pt(landing), "hitterX": hitter_x, "result": result,
            "doubles": doubles, "expected": {**words, "english": said}}


def c09() -> tuple:
    return ("C09-placement-words", "What VoiceOver says about a placement (story 364)", [
        describe_case("the story's example", (-3.0, 10.0), 2.0, "in", False, "Deep cross-court, in"),
        describe_case("down the line, short", (3.0, 4.0), 2.0, "in", False, "Short down the line, in"),
        describe_case("middle third", (0.8, 9.0), -2.5, "needsReview", False, "Deep middle, needs review"),
        describe_case("no hitter position: sides as seen from the hitter's end", (-3.0, 9.0), None, "in", False,
                      "Deep left, in"),
        describe_case("beyond the baseline", (1.0, 12.4), None, "out", False, "Long middle, out"),
        describe_case("singles: the alley is wide", (4.6, 8.0), -1.0, "out", False, "Deep cross-court, wide, out"),
        describe_case("doubles: the alley is in", (4.6, 8.0), -1.0, "in", True, "Deep cross-court, in"),
        describe_case("on the service line is short", (-2.0, 6.4), None, "in", False, "Short left, in"),
    ])


FIXTURES = [c01, c02, c03, c04, c05, c06, c07, c08, c09]


def generate(ctx) -> int:
    out = ctx.fixtures / "calibration"
    for make in FIXTURES:
        fid, title, cases = make()
        ctx.write_json(out / f"{fid}.json", {"schemaVersion": VERSION, "kind": "jovra.fixture.calibration", "id": fid,
                                             "title": title, "cases": cases})
    return len(FIXTURES)


# ----- validator re-run ---------------------------------------------------------------------------

def _close(a, b, tol: float) -> bool:
    if a is None or b is None:
        return a is b
    return abs(a - b) <= tol


def _rerun(case: dict) -> list[str]:
    op, problems = case["op"], []
    if op == "fit":
        if "record" in case:
            image, cpts = record_points(case["record"])
        else:
            image, cpts = case["imagePoints"], case["courtPoints"]
        try:
            h = court.fit([tup(p) for p in image], [tup(p) for p in cpts])
        except court.CalibrationError as e:
            return [] if case.get("expectedError") == e.code else [f"{case['name']}: refused {e.code}"]
        if "expectedError" in case:
            return [f"{case['name']}: expected {case['expectedError']}, fitted"]
        for p in case["expected"]["project"]:
            got = court.project(h, tup(p["court"]))
            if not all(_close(a, b, TOL_PX) for a, b in zip(got, tup(p["pixel"]))):
                problems.append(f"{case['name']}: {p['id']} projects to {got}")
        for p in case["expected"]["unproject"]:
            got = court.unproject(h, tup(p["pixel"]))
            if not all(_close(a, b, TOL_M) for a, b in zip(got, tup(p["court"]))):
                problems.append(f"{case['name']}: {p['id']} unprojects to {got}")
    elif op == "check":
        h = court.fit([tup(p) for p in case["imagePoints"]], [tup(p) for p in case["courtPoints"]])
        cpts = [tup(p) for p in case["courtPoints"]]
        got = court.fit_check(h, [(tup(o["court"]), tup(o["pixel"])) for o in case["observations"]], case["frameHeight"],
                              cpts)
        exp = case["expected"]
        if got["verdict"] != exp["verdict"] or not _close(got["rmsePx"], exp["rmsePx"], TOL_PX):
            problems.append(f"{case['name']}: check {got}")
        if court.is_twisted(h, cpts) != exp["twisted"]:
            problems.append(f"{case['name']}: twisted is stated {exp['twisted']}")
        if exp["twisted"] and exp["verdict"] != "poor":
            problems.append(f"{case['name']}: a twisted fit is stated {exp['verdict']}")
    elif op == "validity":
        got = court.validity(case["binding"], case["current"], case["staleFromMs"], case["atMs"], case["check"],
                             case.get("recordedStatus"), case.get("twisted", False))
        if got != case["expected"]:
            problems.append(f"{case['name']}: validity {got}")
        if case.get("twisted") and got["status"] == "valid":
            problems.append(f"{case['name']}: a twisted fit is stated valid")
    elif op in ("viewToVideo", "videoToView"):
        fn = court.view_to_video if op == "viewToVideo" else court.video_to_view
        v, s = case["view"], case["video"]
        got = fn(tup(case["point"]), (v["width"], v["height"]), (s["width"], s["height"]), case["gravity"])
        exp = case["expected"]
        if (got is None) != (exp is None) or (got and not all(_close(a, b, TOL_PX) for a, b in zip(got, tup(exp)))):
            problems.append(f"{case['name']}: maps to {got}")
    elif op == "geometry":
        if case["expected"] != c08()[2][0]["expected"]:
            problems.append("geometry differs from jovra_ref.court")
    elif op == "classify":
        x, y = tup(case["point"])
        got = {"depth": court.depth_bin(y), "serviceZone": court.service_zone(x), "serviceBox": court.service_box(x, y),
               "inSingles": court.inside(x, y, False), "inDoubles": court.inside(x, y, True)}
        if got != case["expected"]:
            problems.append(f"{case['name']}: {got}")
    elif op == "describe":
        words = court.placement_words(case["landing"], case["hitterX"], case["result"], case["doubles"])
        if {**words, "english": court.english(words)} != case["expected"]:
            problems.append(f"{case['name']}: {words}")
    return problems


def check(path, doc, docs) -> list[str]:
    return [p for case in doc["cases"] for p in _rerun(case)]


CHECKS = {"jovra.fixture.calibration": check}
