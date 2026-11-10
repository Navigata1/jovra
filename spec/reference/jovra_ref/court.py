"""Court geometry and the 4-tap court calibration (T13; ios-v1-spec "CourtCalibration", technical-feasibility §8).

Court model (GLOSSARY "Court model", common.schema.json point2): metres from ITF dimensions, origin at the centre of
the net, x across the court (positive to the right of a player at the near end), y along it towards the far baseline.
Lines are idealized at their nominal positions (zero width).

Calibration: a plane-to-plane homography H from court metres to video pixels (origin top-left, x right, y down), fitted
by the normalized DLT of Hartley & Zisserman (Multiple View Geometry, 2nd ed., algorithm 4.2) with the inhomogeneous
solution h33 = 1 in the normalized frames:

1. Each point set is moved to its centroid and scaled so its mean distance from the origin is sqrt(2).
2. Every correspondence gives two rows of A h = b in the 8 unknowns. Exactly four points: the 8 x 8 system is solved
   directly (Gaussian elimination, partial pivoting), so the four taps are reproduced exactly. More points: the least
   squares solution of the normal equations (A^T A) h = A^T b.
3. H = T_image^-1 Hn T_court, scaled so H[2][2] = 1.

A pivot below PIVOT_EPSILON (relative to the largest entry of its column) means the points do not fix a homography:
`degenerate` (three collinear taps, repeated taps). With exactly four pairs no three points of either set may be
collinear (twice the triangle area in normalized coordinates at most COLLINEAR_EPSILON); with more, they may not
all be collinear. Fewer than four pairs is `tooFewPoints`; unequal lists
`countMismatch`.

The check that can fail: `reprojection_rmse` projects court points the player did not tap (line intersections) and
compares them with where those lines are seen; a fit is poor above 3 px at 1080p, scaled by the frame height
(2 px at 720p). A measured court point the fit puts on or beyond its horizon has no residual to state and makes
the fit poor too.

Twisted fits need no measurement. A camera looking at a flat court sees every court point in front of it, so the
four tapped corners, taken in the court points' order, make a convex quad. Brackets dragged across each other (a
bow tie) or inside the triangle of the other three still fix a homography, but one that puts some of its own
tapped court points on or beyond its horizon (w <= 0), where they have no pixel. `is_twisted` is that test, extended to every
line intersection of the court, so a fit that cannot place a painted line is caught whatever was tapped. A twisted
fit is poor with nothing measured, and invalid (`poorFit`) even when it was never checked. Out of reach: brackets
on the corners one place round, or mirrored left to right, make a convex quad and a homography that places every
court point; only measured lines catch those. With an untwisted fit and nothing measured the check is
`notMeasurable`, and that is never a pass.

Validity binds a calibration to one lens, format (width x height) and zoom, and to the time the camera moved
("stale from mm:ss"). Reasons are reported in this order: lensChanged, formatChanged, zoomChanged, poorFit (a
twisted fit or a poor check), stale, then the status a reopened record was stored with (recordedInvalid,
needsReview, cameraMoved).

Taps are converted to video pixels before fitting, never fitted in view points: `view_to_video` undoes the
aspect-fit (or aspect-fill) placement of the video in its view.
"""

from __future__ import annotations

import math
from decimal import Decimal

# ----- ITF dimensions (metres) -------------------------------------------------------------------

HALF_LENGTH = 11.885          # net to baseline
DOUBLES_HALF_WIDTH = 5.485    # centre line to doubles sideline (court 10.97 m wide)
SINGLES_HALF_WIDTH = 4.115    # centre line to singles sideline (8.23 m)
SERVICE_LINE = 6.40           # net to service line
CENTRE_MARK = 0.10            # length of the centre mark inside the baseline
NET_POST_HALF_WIDTH = 6.40    # net posts 0.914 m outside the doubles sidelines (5.485 + 0.914, rounded)

PIVOT_EPSILON = 1e-10
POOR_FIT_PX_AT_1080P = 3.0    # accept at most 3 px reprojection RMSE at 1080p

# ----- lines, intersections, bins and zones -------------------------------------------------------

D, S, L, SV = DOUBLES_HALF_WIDTH, SINGLES_HALF_WIDTH, HALF_LENGTH, SERVICE_LINE

# (id, kind, (x0, y0), (x1, y1)), near end first, left before right.
LINES = [
    ("nearBaseline", "baseline", (-D, -L), (D, -L)),
    ("farBaseline", "baseline", (-D, L), (D, L)),
    ("leftDoublesSideline", "doublesSideline", (-D, -L), (-D, L)),
    ("rightDoublesSideline", "doublesSideline", (D, -L), (D, L)),
    ("leftSinglesSideline", "singlesSideline", (-S, -L), (-S, L)),
    ("rightSinglesSideline", "singlesSideline", (S, -L), (S, L)),
    ("nearServiceLine", "serviceLine", (-S, -SV), (S, -SV)),
    ("farServiceLine", "serviceLine", (-S, SV), (S, SV)),
    # The centre service line runs only between the service lines, through the service boxes.
    ("centreServiceLine", "centreServiceLine", (0.0, -SV), (0.0, SV)),
    ("nearCentreMark", "centreMark", (0.0, -L), (0.0, -L + CENTRE_MARK)),
    ("farCentreMark", "centreMark", (0.0, L - CENTRE_MARK), (0.0, L)),
    ("net", "net", (-NET_POST_HALF_WIDTH, 0.0), (NET_POST_HALF_WIDTH, 0.0)),
]

# Named ground points where painted lines meet: what a player can tap and what the check projects.
INTERSECTIONS = [
    ("nearLeftDoubles", (-D, -L)), ("nearRightDoubles", (D, -L)),
    ("farRightDoubles", (D, L)), ("farLeftDoubles", (-D, L)),
    ("nearLeftSingles", (-S, -L)), ("nearRightSingles", (S, -L)),
    ("farRightSingles", (S, L)), ("farLeftSingles", (-S, L)),
    ("nearLeftService", (-S, -SV)), ("nearRightService", (S, -SV)),
    ("farRightService", (S, SV)), ("farLeftService", (-S, SV)),
    ("nearServiceT", (0.0, -SV)), ("farServiceT", (0.0, SV)),
    ("nearCentreMark", (0.0, -L)), ("farCentreMark", (0.0, L)),
]
POINTS = dict(INTERSECTIONS)

# The four corners a player taps (S05: brackets on the doubles corners), near left first, clockwise as seen from
# behind the near baseline: near left, near right, far right, far left.
DOUBLES_CORNERS = ["nearLeftDoubles", "nearRightDoubles", "farRightDoubles", "farLeftDoubles"]
SINGLES_CORNERS = ["nearLeftSingles", "nearRightSingles", "farRightSingles", "farLeftSingles"]

# Depth bins on one half (S11): Short inside the service line, Deep between it and the baseline.
DEPTH_BINS = [("short", 0.0, SV), ("deep", SV, L)]


def depth_bin(y: float) -> str:
    """Depth of a landing on either half by its distance from the net: short, deep, or long beyond the baseline."""
    d = abs(y)
    if d <= SV:
        return "short"
    if d <= L:
        return "deep"
    return "long"


def service_zone(x: float) -> str:
    """Serve zone across a service box (S12): thirds from the centre service line, T, body, wide."""
    third = abs(x) / S
    return "t" if third < 1 / 3 else ("body" if third < 2 / 3 else "wide")


def service_box(x: float, y: float) -> str:
    """The receiver's box a serve landed in: the deuce box is the receiver's right, so x and y differ in sign."""
    return "deuce" if x * y < 0 else "ad"


def inside(x: float, y: float, doubles: bool) -> bool:
    half = D if doubles else S
    return abs(x) <= half and abs(y) <= L


def placement_words(landing: dict, hitter_x: float | None, result: str, doubles: bool = False) -> dict:
    """What VoiceOver says about a placement (story 364, "Deep cross-court, in"), as values the app localizes.

    depth: short | deep | long (beyond the baseline). direction: with the hitter's x known, middle when the
    landing is within the central third of the singles court, else crossCourt when it lands on the other side of
    the centre line from the hitter, downTheLine on the same side. Without the hitter: left | middle | right as
    seen from the hitter's end (the bottom of the diagram, landings normalized onto the far half).
    wide: the landing is beyond the sideline that counts (singles or doubles). result: in | out | needsReview.
    """
    x, y = landing["x"], landing["y"]
    depth = depth_bin(y)
    if abs(x) < S / 3:
        direction = "middle"
    elif hitter_x is None or hitter_x == 0:
        direction = "right" if x > 0 else "left"
    else:
        direction = "downTheLine" if (x > 0) == (hitter_x > 0) else "crossCourt"
    return {"depth": depth, "direction": direction, "wide": abs(x) > (D if doubles else S), "result": result}


ENGLISH = {
    "short": "Short", "deep": "Deep", "long": "Long",
    "crossCourt": "cross-court", "downTheLine": "down the line", "middle": "middle", "left": "left", "right": "right",
    "in": "in", "out": "out", "needsReview": "needs review",
}


def english(words: dict) -> str:
    """The English sentence the app's String Catalog renders: "Deep cross-court, in", "Long middle, wide, out"."""
    parts = f"{ENGLISH[words['depth']]} {ENGLISH[words['direction']]}"
    if words["wide"]:
        parts += ", wide"
    return f"{parts}, {ENGLISH[words['result']]}"


# ----- linear algebra ----------------------------------------------------------------------------

class CalibrationError(ValueError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _solve(m: list[list[float]], rhs: list[float]) -> list[float]:
    """Gaussian elimination with partial pivoting; a pivot below PIVOT_EPSILON x its column's scale is degenerate."""
    n = len(m)
    a = [row[:] + [b] for row, b in zip(m, rhs)]
    for col in range(n):
        scale = max(abs(a[k][col]) for k in range(n))
        pivot = max(range(col, n), key=lambda k: abs(a[k][col]))
        if scale == 0 or abs(a[pivot][col]) <= PIVOT_EPSILON * scale:
            raise CalibrationError("degenerate")
        a[col], a[pivot] = a[pivot], a[col]
        for k in range(col + 1, n):
            f = a[k][col] / a[col][col]
            if f != 0:
                for j in range(col, n + 1):
                    a[k][j] -= f * a[col][j]
    x = [0.0] * n
    for i in range(n - 1, -1, -1):
        s = a[i][n] - sum(a[i][j] * x[j] for j in range(i + 1, n))
        x[i] = s / a[i][i]
    return x


def _normalizer(points: list[tuple[float, float]]) -> list[list[float]]:
    """Similarity moving the centroid to the origin with mean distance sqrt(2) (Hartley normalization)."""
    n = len(points)
    cx = sum(p[0] for p in points) / n
    cy = sum(p[1] for p in points) / n
    mean = sum(math.sqrt((p[0] - cx) ** 2 + (p[1] - cy) ** 2) for p in points) / n
    if mean == 0:
        raise CalibrationError("degenerate")
    s = math.sqrt(2) / mean
    return [[s, 0.0, -s * cx], [0.0, s, -s * cy], [0.0, 0.0, 1.0]]


COLLINEAR_EPSILON = 1e-9


def _has_collinear_triple(points: list[tuple[float, float]], every: bool) -> bool:
    """With exactly four points no three may be collinear (in normalized coordinates, mean distance sqrt(2));
    with more, the points may not all lie on one line."""
    def area(a, b, c) -> float:
        return abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
    n = len(points)
    triples = [(i, j, k) for i in range(n) for j in range(i + 1, n) for k in range(j + 1, n)]
    flat = [area(points[i], points[j], points[k]) <= COLLINEAR_EPSILON for i, j, k in triples]
    return any(flat) if every else all(flat)


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def _apply(m, x: float, y: float) -> tuple[float, float, float]:
    return (m[0][0] * x + m[0][1] * y + m[0][2], m[1][0] * x + m[1][1] * y + m[1][2], m[2][0] * x + m[2][1] * y + m[2][2])


def inverse(m):
    a, b, c = m[0]
    d, e, f = m[1]
    g, h, i = m[2]
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if det == 0:
        raise CalibrationError("degenerate")
    adj = [[e * i - f * h, c * h - b * i, b * f - c * e],
           [f * g - d * i, a * i - c * g, c * d - a * f],
           [d * h - e * g, b * g - a * h, a * e - b * d]]
    return [[v / det for v in row] for row in adj]


# ----- calibration --------------------------------------------------------------------------------

def fit(image_points: list[tuple[float, float]], court_points: list[tuple[float, float]]) -> list[list[float]]:
    """Court metres -> video pixels, H[2][2] = 1. Exact through four points; least squares through more."""
    if len(image_points) != len(court_points):
        raise CalibrationError("countMismatch")
    if len(image_points) < 4:
        raise CalibrationError("tooFewPoints")
    tc, ti = _normalizer(court_points), _normalizer(image_points)
    for t, pts in ((tc, court_points), (ti, image_points)):
        if _has_collinear_triple([_apply(t, x, y)[:2] for x, y in pts], every=len(pts) == 4):
            raise CalibrationError("degenerate")
    rows, rhs = [], []
    for (u, v), (x, y) in zip(image_points, court_points):
        X, Y, _ = _apply(tc, x, y)
        U, V, _ = _apply(ti, u, v)
        rows.append([X, Y, 1.0, 0.0, 0.0, 0.0, -U * X, -U * Y]); rhs.append(U)
        rows.append([0.0, 0.0, 0.0, X, Y, 1.0, -V * X, -V * Y]); rhs.append(V)
    if len(image_points) == 4:
        h = _solve(rows, rhs)
    else:
        ata = [[sum(r[i] * r[j] for r in rows) for j in range(8)] for i in range(8)]
        atb = [sum(r[i] * b for r, b in zip(rows, rhs)) for i in range(8)]
        h = _solve(ata, atb)
    hn = [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1.0]]
    m = _mul(inverse(ti), _mul(hn, tc))
    if abs(m[2][2]) <= PIVOT_EPSILON * max(abs(v) for row in m for v in row):
        raise CalibrationError("degenerate")
    return [[v / m[2][2] for v in row] for row in m]


def project(h, point: tuple[float, float]) -> tuple[float, float] | None:
    """Court metres -> video pixels; None for a point on or beyond the horizon (w <= 0)."""
    u, v, w = _apply(h, point[0], point[1])
    if w <= PIVOT_EPSILON:
        return None
    return u / w, v / w


def unproject(h, pixel: tuple[float, float]) -> tuple[float, float] | None:
    """Video pixels -> court metres on the ground plane; None above the horizon (no ground point)."""
    x, y, w = _apply(inverse(h), pixel[0], pixel[1])
    if w <= PIVOT_EPSILON:
        return None
    return x / w, y / w


def reprojection_rmse(h, observations: list[tuple[tuple[float, float], tuple[float, float]]]) -> float | None:
    """Root mean square pixel distance between projected court points and where they are seen; None with no
    observations (nothing measured) or when a court point projects beyond the horizon."""
    if not observations:
        return None
    total = 0.0
    for court, pixel in observations:
        p = project(h, court)
        if p is None:
            return None
        total += (p[0] - pixel[0]) ** 2 + (p[1] - pixel[1]) ** 2
    return math.sqrt(total / len(observations))


def poor_fit_threshold_px(frame_height: int) -> float:
    return POOR_FIT_PX_AT_1080P * frame_height / 1080


def is_twisted(h, tapped: list[tuple[float, float]]) -> bool:
    """True when the fit puts a court point it was fitted through, or a line intersection of the court, on or
    beyond its own horizon (`project` is None). For four taps that is exactly a tapped quad that is not convex
    when taken in the court points' order; no camera looking at a flat court produces one."""
    return any(project(h, p) is None for p in [*tapped, *(p for _, p in INTERSECTIONS)])


def fit_check(h, observations, frame_height: int, tapped: list[tuple[float, float]] | None = None) -> dict:
    """The verdict on a fit through the court points `tapped`. A twisted fit is poor whatever was measured, even
    nothing. With measurements, a court point the fit cannot project (on or beyond its horizon) makes the fit poor
    with no RMSE: the line was seen in the frame and the fit puts it nowhere, which is worse than any pixel
    distance. No residual is invented for it. `notMeasurable` only for an untwisted fit with nothing measured."""
    rmse = reprojection_rmse(h, observations)
    threshold = poor_fit_threshold_px(frame_height)
    if is_twisted(h, tapped or []):
        return {"verdict": "poor", "rmsePx": rmse, "thresholdPx": threshold}
    if not observations:
        return {"verdict": "notMeasurable", "rmsePx": None, "thresholdPx": threshold}
    if rmse is None:
        return {"verdict": "poor", "rmsePx": None, "thresholdPx": threshold}
    return {"verdict": "good" if rmse <= threshold else "poor", "rmsePx": rmse, "thresholdPx": threshold}


# What a stored calibration's status means when the record is reopened. Refitting stored taps always succeeds, so a
# status the record carries is reported, never re-derived from the fit.
RECORDED_STATUS_REASONS = {"invalid": "recordedInvalid", "needsReview": "needsReview", "cameraMoved": "cameraMoved"}


def validity(binding: dict, current: dict, stale_from_ms: int | None, at_ms: int, check: dict | None,
             recorded_status: str | None = None, twisted: bool = False) -> dict:
    """Is a calibration usable at `at_ms` with the camera configured as `current`? First failing reason wins.

    `twisted` is `is_twisted` of the calibration's own fit and taps. It needs no measurement, so a twisted
    calibration is a poor fit even when it was never checked, and a stored status or residual does not outrank it.

    `recorded_status` is the status a reopened session record carries (session.schema.json calibration.status).
    After the camera, fit and stale-time reasons, a record stored `invalid` or `needsReview` stays unusable, and one
    stored `cameraMoved` without a stale-from time is unusable throughout; with a time it is valid before it.
    """
    if binding["lens"] != current["lens"]:
        return {"status": "invalid", "reason": "lensChanged"}
    if (binding["width"], binding["height"]) != (current["width"], current["height"]):
        return {"status": "invalid", "reason": "formatChanged"}
    if Decimal(binding["zoomFactor"]) != Decimal(current["zoomFactor"]):
        return {"status": "invalid", "reason": "zoomChanged"}
    if twisted or (check is not None and check["verdict"] == "poor"):
        return {"status": "invalid", "reason": "poorFit"}
    if stale_from_ms is not None and at_ms >= stale_from_ms:
        return {"status": "invalid", "reason": "stale", "staleFromMs": stale_from_ms}
    if recorded_status == "cameraMoved" and stale_from_ms is not None:
        return {"status": "valid"}
    if recorded_status in RECORDED_STATUS_REASONS:
        return {"status": "invalid", "reason": RECORDED_STATUS_REASONS[recorded_status]}
    return {"status": "valid"}


def view_to_video(point: tuple[float, float], view: tuple[float, float], video: tuple[int, int],
                  gravity: str = "resizeAspect") -> tuple[float, float] | None:
    """A tap in view points -> video pixels, undoing the aspect-fit (resizeAspect) or aspect-fill
    (resizeAspectFill) placement of the video centred in its view. None for a tap on a letterbox bar."""
    vw, vh = view
    w, h = video
    scale = min(vw / w, vh / h) if gravity == "resizeAspect" else max(vw / w, vh / h)
    ox, oy = (vw - w * scale) / 2, (vh - h * scale) / 2
    x, y = (point[0] - ox) / scale, (point[1] - oy) / scale
    if x < 0 or y < 0 or x > w or y > h:
        return None
    return x, y


def video_to_view(pixel: tuple[float, float], view: tuple[float, float], video: tuple[int, int],
                  gravity: str = "resizeAspect") -> tuple[float, float]:
    vw, vh = view
    w, h = video
    scale = min(vw / w, vh / h) if gravity == "resizeAspect" else max(vw / w, vh / h)
    return (vw - w * scale) / 2 + pixel[0] * scale, (vh - h * scale) / 2 + pixel[1] * scale
