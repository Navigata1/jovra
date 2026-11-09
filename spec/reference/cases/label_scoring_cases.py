"""Label scoring fixtures (V01): jovra.fixture.labelScoring, spec/fixtures/labels/L*.json.

Each fixture is a synthetic label document, a stage's observations and the rows the label scorer must print
for the tuning and the held-out windows. Every expected value below was worked by hand from the rules in
jovra_ref/labels.py's docstring (the `worked` lines show the arithmetic); the generator refuses to write a
fixture the reference disagrees with, and CHECKS re-runs every fixture, label document and label set in
the validator. The recordings are SHA-256 hashes of fixed ASCII lines: no footage is involved.
"""
from __future__ import annotations

import copy
from pathlib import Path

from jovra_ref import labels as ref

ORDER = 40
VERSION = "1.0.0"
TOOL = "fixture-author@1.0.0"


def ms(value: int) -> dict:
    return {"value": value, "timescale": 1000}


def point(x: float, y: float) -> dict:
    return {"x": x, "y": y}


def recording(sha256: str, seconds: int) -> dict:
    return {"sha256": sha256, "byteSize": 1048576, "duration": {"value": seconds, "timescale": 1},
            "width": 1280, "height": 720, "frameRate": {"num": 30, "den": 1}, "variableFrameRate": False}


def hit(t: int, player: str, stroke: str | None = None) -> dict:
    return {"time": ms(t), "player": player, "stroke": stroke}


def seen_hit(t: int, player: str | None = None, stroke: str | None = None) -> dict:
    out = {"time": ms(t)}
    if player is not None:
        out["player"] = player
    if stroke is not None:
        out["stroke"] = stroke
    return out


def bounce(t: int, x: float, y: float, in_play: bool = True) -> dict:
    return {"time": ms(t), "imagePoint": point(x, y), "inPlay": in_play}


def seen_bounce(t: int, xy: tuple[float, float] | None = None) -> dict:
    out = {"time": ms(t)}
    if xy is not None:
        out["imagePoint"] = point(*xy)
    return out


def rally(start: int, end: int | None) -> dict:
    return {"start": ms(start), "end": None if end is None else ms(end)}


def corners(*points) -> dict:
    return {"court": "doubles", "order": ref.CORNER_ORDER, "points": [None if p is None else point(*p) for p in points]}


def count(group: str, name: str, value: int) -> dict:
    return {"group": group, "name": name, "value": str(value)}


def ratio(group: str, name: str, n: int | None, d: int | None, value: str | None) -> dict:
    return {"group": group, "name": name, "exact": None if n is None else {"n": n, "d": d}, "value": value}


def millis(group: str, name: str, n: int | None, d: int | None, value: str | None) -> dict:
    return {"group": group, "name": name, "unit": "ms", "exact": None if n is None else {"n": n, "d": d}, "value": value}


def px(group: str, name: str, value: str | None) -> dict:
    return {"group": group, "name": name, "unit": "px", "value": value}


TOLERANCES = {"hit": ms(100), "bounce": ms(100), "rallyBoundary": ms(1000)}

# ----- L01: every kind, both splits ------------------------------------------------------------------
# SHA-256 of the ASCII line "jovra synthetic recording 7". 120 s in 30 s windows is 4 windows; 4 x 300 / 1000
# = 1.2, so one window is held out, and this hash ranks window 1 (30-60 s) first.
L01_RECORDING = "d9db095691ae78dbfbbc8d3bed01cbe609b1c332c9b004658491817690f0b130"

L01_LABELS = {
    "schemaVersion": VERSION, "kind": "jovra.benchmarkLabels",
    "recording": recording(L01_RECORDING, 120),
    "labelledBy": {"method": "synthetic", "tool": TOOL},
    "split": {"method": "jovra.hashWindows.v1", "windowMs": 30000, "heldOutPermille": 300, "durationMs": 120000,
              "heldOutWindows": [1]},
    "hits": [
        hit(5000, "near", "forehand"), hit(6500, "far", "backhand"), hit(12000, "near", "serve"),
        hit(29980, "near", "volley"),
        hit(31000, "far", "forehand"), hit(40000, "near", "backhand"), hit(45000, "near"), hit(59950, "far", "forehand"),
        hit(61000, "near", "forehand"), hit(75000, "far"), hit(100000, "near", "overhead"),
    ],
    "bounces": [
        bounce(5500, 0.5, 0.4), bounce(7000, 0.25, 0.5), bounce(20000, 0.6, 0.7, in_play=False),
        bounce(32000, 0.4, 0.3), bounce(41000, 0.7, 0.6), bounce(62000, 0.5, 0.5), bounce(101000, 0.3, 0.35),
    ],
    "rallies": [rally(4000, 9000), rally(28000, 33000), rally(39000, 46000), rally(60500, 76000), rally(99000, 102000)],
    "cameraPositions": [
        {"from": ms(0), "corners": corners((0.3, 0.2), (0.7, 0.2), (0.95, 0.9), (0.05, 0.9))},
        {"from": ms(70000), "corners": corners((0.31, 0.21), (0.71, 0.21), (0.96, 0.91), (0.06, 0.91))},
    ],
}

L01_OBSERVATIONS = {
    "schemaVersion": VERSION, "kind": "jovra.benchmarkObservations", "recordingSha256": L01_RECORDING,
    "producer": "rule:fixture@1.0.0",
    "analysed": [{"start": ms(0), "end": ms(50000)}, {"start": ms(60000), "end": ms(120000)}],
    "hits": [
        seen_hit(5020, "near", "forehand"), seen_hit(6440, "far", "forehand"), seen_hit(12150),
        seen_hit(30040, "near", "volley"), seen_hit(31000, "far"), seen_hit(40090, "near", "backhand"),
        seen_hit(44890, "near"), seen_hit(50000), seen_hit(59900, "far", "forehand"),
        seen_hit(61030, "near", "backhand"), seen_hit(75100, "far", "forehand"),
        seen_hit(100010, "near", "overhead"), seen_hit(110000),
    ],
    "bounces": [
        seen_bounce(5530, (0.5125, 0.4)), seen_bounce(7080, (0.25, 0.525)), seen_bounce(20020, (0.61, 0.7)),
        seen_bounce(25000, (0.5, 0.5)), seen_bounce(32050, (0.42109375, 0.35)), seen_bounce(41000),
        seen_bounce(62090, (0.5, 0.5)), seen_bounce(115000, (0.1, 0.1)),
    ],
    "rallies": [rally(4500, 9200), rally(27200, 34500), rally(39000, 46900), rally(50000, 52000),
                rally(61000, 75500), rally(110000, 112000)],
    "courtCorners": [
        {"time": ms(10000), "points": [point(0.3, 0.225), point(0.7125, 0.2), point(0.95, 0.9), None]},
        {"time": ms(35000), "points": [point(0.32109375, 0.25), point(0.7, 0.2), point(0.95, 0.9), point(0.05, 0.9)]},
        {"time": ms(80000), "points": [point(0.31, 0.21), point(0.71, 0.21), point(0.96, 0.91), point(0.06, 0.935)]},
    ],
}

L01_WORKED = [
    "Windows: 0-30 s, 30-60 s, 60-90 s, 90-120 s. Held out: window 1. Tuning: windows 0, 2 and 3 (90 s).",
    "Hits, 100 ms. Pairs (label <- observation, offset): 5.000 <- 5.020 (+20), 6.500 <- 6.440 (-60), 29.980 <- 30.040 (+60), "
    "31.000 <- 31.000 (0), 40.000 <- 40.090 (+90), 59.950 <- 59.900 (-50), 61.000 <- 61.030 (+30), 75.000 <- 75.100 (+100, on the "
    "tolerance), 100.000 <- 100.010 (+10). 12.000 has only 12.150 (150 ms) and 45.000 only 44.890 (110 ms): both missed.",
    "Hits, tuning: 7 labels, 6 matched (30.040 lies in the held-out window but its label 29.980 is a tuning label, so the pair is "
    "tuning), unmatched 12.150 and 110.000. Precision 6/8, recall 6/7. Near 4/5 (12.000 missed), far 2/2. "
    "MAE (20+60+60+30+100+10)/6 = 280/6 = 46.667 ms; bias (20-60+60+30+100+10)/6 = 160/6 = +26.667 ms. "
    "Strokes compared 5 (75.000 has no labelled stroke): forehand=forehand, backhand/forehand, volley=volley, "
    "forehand/backhand, overhead=overhead, so 3/5.",
    "Hits, held out: 4 labels, 3 matched, unmatched 44.890 and 50.000. Precision 3/5, recall 3/4. Near 1/2, far 2/2. "
    "MAE (0+90+50)/3 = 46.667 ms; bias (0+90-50)/3 = +13.333 ms. Strokes compared 2 (31.000 observed without one): 2/2.",
    "Bounces, 100 ms, picture 1280 x 720. Pairs: 5.500 <- 5.530 (30 ms, 0.0125 x 1280 = 16 px), 7.000 <- 7.080 (80 ms, "
    "0.025 x 720 = 18 px), 20.000 <- 20.020 (label not in play: dropped), 32.000 <- 32.050 (50 ms, 27 px across and 36 px down "
    "= 45 px), 41.000 <- 41.000 (0 ms, no point), 62.000 <- 62.090 (90 ms, 0 px). 101.000 missed; 25.000 and 115.000 unmatched.",
    "Bounces, tuning: 4 in play, 1 not in play, 3 matched, 2 unmatched: precision 3/5, recall 3/4, MAE 200/3 = 66.667 ms, "
    "3 placed: median of 0, 16, 18 is 16.00 px, mean 34/3 = 11.33 px.",
    "Bounces, held out: 2 in play, 2 matched, none unmatched: precision 2/2, recall 2/2, MAE 50/2 = 25.000 ms, 1 placed: 45.00 px.",
    "Rally boundaries, 1 s. Starts: 4.0 <- 4.5, 28.0 <- 27.2, 39.0 <- 39.0, 60.5 <- 61.0; 99.0 missed; 50.0 and 110.0 unmatched. "
    "Ends: 9.0 <- 9.2, 46.0 <- 46.9, 76.0 <- 75.5; 33.0 (only 34.5, 1.5 s) and 102.0 missed; 34.5, 52.0 and 112.0 unmatched.",
    "Rally boundaries, tuning: labels 4.0, 9.0, 28.0, 60.5, 76.0, 99.0, 102.0 = 7; matched 5; unmatched 110.0 and 112.0. "
    "Precision 5/7, recall 5/7, F1 10/(10+2+2) = 5/7.",
    "Rally boundaries, held out: labels 33.0, 39.0, 46.0 = 3; matched 2; unmatched 34.5, 50.0, 52.0. "
    "Precision 2/5, recall 2/3, F1 4/(4+3+1) = 1/2.",
    "Court corners. 10 s (tuning, first position): 18, 16 and 0 px, fourth corner not observed. 35 s (held out, first position): "
    "45, 0, 0, 0 px. 80 s (tuning, second position from 70 s): 0, 0, 0, 18 px. Tuning: 7 corners, mean 52/7 = 7.43 px, max 18.00. "
    "Held out: 4 corners, mean 45/4 = 11.25 px, max 45.00.",
    "Coverage: analysed 0-50 s and 60-120 s. Tuning windows are fully inside: 90/90. Held-out window 30-60 s has 20 of 30 s: 2/3.",
]

L01_EXPECTED = {
    "tuning": {"windows": 3, "durationMs": 90000, "rows": [
        count("hits", "labels", 7), count("hits", "observations", 8), count("hits", "matched", 6),
        ratio("hits", "precision", 3, 4, "0.7500"), ratio("hits", "recall", 6, 7, "0.8571"),
        ratio("hits", "recall near", 4, 5, "0.8000"), ratio("hits", "recall far", 1, 1, "1.0000"),
        millis("hits", "timing MAE", 140, 3, "46.667"), millis("hits", "timing bias", 80, 3, "+26.667"),
        count("hits", "strokes compared", 5), ratio("hits", "stroke accuracy", 3, 5, "0.6000"),
        count("bounces", "labels in play", 4), count("bounces", "labels not in play", 1),
        count("bounces", "observations", 5), count("bounces", "matched", 3),
        count("bounces", "dropped on a label not in play", 1),
        ratio("bounces", "precision", 3, 5, "0.6000"), ratio("bounces", "recall", 3, 4, "0.7500"),
        millis("bounces", "timing MAE", 200, 3, "66.667"), count("bounces", "placed", 3),
        px("bounces", "placement error median", "16.00"), px("bounces", "placement error mean", "11.33"),
        count("rally boundaries", "labels", 7), count("rally boundaries", "observations", 7),
        count("rally boundaries", "matched", 5),
        ratio("rally boundaries", "precision", 5, 7, "0.7143"), ratio("rally boundaries", "recall", 5, 7, "0.7143"),
        ratio("rally boundaries", "F1", 5, 7, "0.7143"),
        count("court corners", "corners compared", 7),
        count("court corners", "observations before any labelled camera position", 0),
        px("court corners", "corner error mean", "7.43"), px("court corners", "corner error max", "18.00"),
        ratio("coverage", "analysed share", 1, 1, "1.0000"),
    ]},
    "heldOut": {"windows": 1, "durationMs": 30000, "rows": [
        count("hits", "labels", 4), count("hits", "observations", 5), count("hits", "matched", 3),
        ratio("hits", "precision", 3, 5, "0.6000"), ratio("hits", "recall", 3, 4, "0.7500"),
        ratio("hits", "recall near", 1, 2, "0.5000"), ratio("hits", "recall far", 1, 1, "1.0000"),
        millis("hits", "timing MAE", 140, 3, "46.667"), millis("hits", "timing bias", 40, 3, "+13.333"),
        count("hits", "strokes compared", 2), ratio("hits", "stroke accuracy", 1, 1, "1.0000"),
        count("bounces", "labels in play", 2), count("bounces", "labels not in play", 0),
        count("bounces", "observations", 2), count("bounces", "matched", 2),
        count("bounces", "dropped on a label not in play", 0),
        ratio("bounces", "precision", 1, 1, "1.0000"), ratio("bounces", "recall", 1, 1, "1.0000"),
        millis("bounces", "timing MAE", 25, 1, "25.000"), count("bounces", "placed", 1),
        px("bounces", "placement error median", "45.00"), px("bounces", "placement error mean", "45.00"),
        count("rally boundaries", "labels", 3), count("rally boundaries", "observations", 5),
        count("rally boundaries", "matched", 2),
        ratio("rally boundaries", "precision", 2, 5, "0.4000"), ratio("rally boundaries", "recall", 2, 3, "0.6667"),
        ratio("rally boundaries", "F1", 1, 2, "0.5000"),
        count("court corners", "corners compared", 4),
        count("court corners", "observations before any labelled camera position", 0),
        px("court corners", "corner error mean", "11.25"), px("court corners", "corner error max", "45.00"),
        ratio("coverage", "analysed share", 2, 3, "0.6667"),
    ]},
}

# ----- L02: undefined metrics, an open rally, a late bias, one window ---------------------------------
# SHA-256 of the ASCII line "jovra synthetic recording 2". 20 s is one window, so nothing is held out.
L02_RECORDING = "7c1ed98153475f6bfb58cbfbab66c33e5839bedc8db7aa4642743a4f2ba8323d"

L02_LABELS = {
    "schemaVersion": VERSION, "kind": "jovra.benchmarkLabels",
    "recording": recording(L02_RECORDING, 20),
    "labelledBy": {"method": "synthetic", "tool": TOOL},
    "split": {"method": "jovra.hashWindows.v1", "windowMs": 30000, "heldOutPermille": 300, "durationMs": 20000,
              "heldOutWindows": []},
    "hits": [hit(2000, "near", "serve"), hit(3000, "far", "forehand")],
    "bounces": [bounce(2500, 0.5, 0.5)],
    "rallies": [rally(2000, 6000), rally(15000, None)],
    "cameraPositions": [{"from": ms(5000), "corners": corners((0.3, 0.2), (0.7, 0.2), (0.95, 0.9), (0.05, 0.9))}],
}

L02_OBSERVATIONS = {
    "schemaVersion": VERSION, "kind": "jovra.benchmarkObservations", "recordingSha256": L02_RECORDING,
    "producer": "rule:fixture@1.0.0",
    "hits": [seen_hit(1960), seen_hit(2910)],
    "bounces": [],
    "rallies": [rally(15400, 19000)],
    "courtCorners": [{"time": ms(1000), "points": [point(0.3, 0.2), point(0.7, 0.2), point(0.95, 0.9), point(0.05, 0.9)]}],
}

L02_WORKED = [
    "20 s is a single 30 s window, so there is no held-out window: every label is a tuning label and the held-out side "
    "has no labels, no observations and only undefined ratios.",
    "Hits: 2.000 <- 1.960 (-40), 3.000 <- 2.910 (-90). Precision 2/2, recall 2/2, near 1/1, far 1/1. MAE 130/2 = 65.000 ms; "
    "bias -130/2 = -65.000 ms (the stage is early). No observation names a stroke: 0 compared, accuracy undefined.",
    "Bounces: the stage reports an empty list, so the kind is scored: 1 label, 0 observations, precision undefined (0/0), "
    "recall 0/1, MAE undefined, nothing placed.",
    "Rally boundaries: label starts 2.0 and 15.0, label end 6.0 (the second rally is open and has no end). Observed start 15.4 "
    "matches 15.0; observed end 19.0 is unmatched. 3 labels, 2 observations, 1 matched: precision 1/2, recall 1/3, "
    "F1 2/(2+1+2) = 2/5.",
    "Court corners: the only observation is at 1 s, before the first labelled camera position (5 s): nothing compared.",
    "No analysed ranges were given, so there is no coverage row.",
]

L02_EXPECTED = {
    "tuning": {"windows": 1, "durationMs": 20000, "rows": [
        count("hits", "labels", 2), count("hits", "observations", 2), count("hits", "matched", 2),
        ratio("hits", "precision", 1, 1, "1.0000"), ratio("hits", "recall", 1, 1, "1.0000"),
        ratio("hits", "recall near", 1, 1, "1.0000"), ratio("hits", "recall far", 1, 1, "1.0000"),
        millis("hits", "timing MAE", 65, 1, "65.000"), millis("hits", "timing bias", -65, 1, "-65.000"),
        count("hits", "strokes compared", 0), ratio("hits", "stroke accuracy", None, None, None),
        count("bounces", "labels in play", 1), count("bounces", "labels not in play", 0),
        count("bounces", "observations", 0), count("bounces", "matched", 0),
        count("bounces", "dropped on a label not in play", 0),
        ratio("bounces", "precision", None, None, None), ratio("bounces", "recall", 0, 1, "0.0000"),
        millis("bounces", "timing MAE", None, None, None), count("bounces", "placed", 0),
        px("bounces", "placement error median", None), px("bounces", "placement error mean", None),
        count("rally boundaries", "labels", 3), count("rally boundaries", "observations", 2),
        count("rally boundaries", "matched", 1),
        ratio("rally boundaries", "precision", 1, 2, "0.5000"), ratio("rally boundaries", "recall", 1, 3, "0.3333"),
        ratio("rally boundaries", "F1", 2, 5, "0.4000"),
        count("court corners", "corners compared", 0),
        count("court corners", "observations before any labelled camera position", 1),
        px("court corners", "corner error mean", None), px("court corners", "corner error max", None),
    ]},
    "heldOut": {"windows": 0, "durationMs": 0, "rows": [
        count("hits", "labels", 0), count("hits", "observations", 0), count("hits", "matched", 0),
        ratio("hits", "precision", None, None, None), ratio("hits", "recall", None, None, None),
        ratio("hits", "recall near", None, None, None), ratio("hits", "recall far", None, None, None),
        millis("hits", "timing MAE", None, None, None), millis("hits", "timing bias", None, None, None),
        count("hits", "strokes compared", 0), ratio("hits", "stroke accuracy", None, None, None),
        count("bounces", "labels in play", 0), count("bounces", "labels not in play", 0),
        count("bounces", "observations", 0), count("bounces", "matched", 0),
        count("bounces", "dropped on a label not in play", 0),
        ratio("bounces", "precision", None, None, None), ratio("bounces", "recall", None, None, None),
        millis("bounces", "timing MAE", None, None, None), count("bounces", "placed", 0),
        px("bounces", "placement error median", None), px("bounces", "placement error mean", None),
        count("rally boundaries", "labels", 0), count("rally boundaries", "observations", 0),
        count("rally boundaries", "matched", 0),
        ratio("rally boundaries", "precision", None, None, None), ratio("rally boundaries", "recall", None, None, None),
        ratio("rally boundaries", "F1", None, None, None),
        count("court corners", "corners compared", 0),
        count("court corners", "observations before any labelled camera position", 0),
        px("court corners", "corner error mean", None), px("court corners", "corner error max", None),
    ]},
}

FIXTURES = (
    ("L01-every-kind-both-splits", "Hits, bounces, rally boundaries, court corners and coverage over tuning and held-out windows",
     L01_LABELS, L01_OBSERVATIONS, L01_EXPECTED, L01_WORKED),
    ("L02-undefined-and-open", "One window: nothing held out, undefined ratios, an open rally and an early stage",
     L02_LABELS, L02_OBSERVATIONS, L02_EXPECTED, L02_WORKED),
)


def fixture_problems(doc: dict) -> list[str]:
    """Re-run one fixture through the reference and compare it with its hand-written rows."""
    problems = [f"labels: {p}" for p in ref.label_problems(doc["labels"])]
    problems += [f"observations: {p}" for p in ref.observation_problems(doc["observations"], doc["labels"])]
    if problems:
        return problems
    actual = ref.score(doc["labels"], doc["observations"], doc["tolerances"])
    for name in ref.SPLITS:
        want, got = doc["expected"][name], actual[name]
        if (want["windows"], want["durationMs"]) != (got["windows"], got["durationMs"]):
            problems.append(f"{name}: expected {want['windows']} windows / {want['durationMs']} ms, "
                            f"reference {got['windows']} / {got['durationMs']}")
        if len(want["rows"]) != len(got["rows"]):
            problems.append(f"{name}: expected {len(want['rows'])} rows, reference {len(got['rows'])}")
        for hand, engine in zip(want["rows"], got["rows"]):
            if hand != engine:
                problems.append(f"{name} {hand['group']} / {hand['name']}: expected {hand!r}, reference {engine!r}")
    return problems


def generate(ctx) -> int:
    for fixture_id, title, labels, observations, expected, worked in FIXTURES:
        doc = {"schemaVersion": VERSION, "kind": "jovra.fixture.labelScoring", "id": fixture_id, "title": title,
               "covers": ["V01", "ADR-0031", "docs/spec/vision-tickets.md"], "worked": list(worked),
               "tolerances": copy.deepcopy(TOLERANCES), "labels": copy.deepcopy(labels),
               "observations": copy.deepcopy(observations), "expected": copy.deepcopy(expected)}
        problems = fixture_problems(doc)
        if problems:
            raise ValueError(f"{fixture_id}: " + "; ".join(problems))
        ctx.write_json(ctx.fixtures / "labels" / f"{fixture_id}.json", doc)
    return len(FIXTURES)


# ----- checks the validator runs ---------------------------------------------------------------------

REPOSITORY = Path(__file__).resolve().parents[3]


def check_fixture(path, doc, docs) -> list[str]:
    return fixture_problems(doc)


def check_labels(path, doc, docs) -> list[str]:
    problems = ref.label_problems(doc)
    if doc["labelledBy"]["method"] == "human" and isinstance(path, Path) and path.is_file():
        expected = f"rec-{doc['recording']['sha256'][:12]}.labels.json"
        if path.name != expected:
            problems.append(f"a label file is named after its recording's hash: {expected}")
    return problems


def label_set_problems(doc: dict, root: Path = REPOSITORY) -> list[str]:
    """Each sealed label file still has the bytes, split and counts the set recorded for it."""
    import json

    problems = []
    roles = [r["role"] for r in doc["recordings"]]
    if len(set(roles)) != len(roles):
        problems.append("a recording role is listed twice")
    paths = [f["path"] for f in doc["labelFiles"]]
    if len(set(paths)) != len(paths):
        problems.append("a label file is listed twice")
    for entry in doc["labelFiles"]:
        file = root / entry["path"]
        if not file.is_file():
            problems.append(f"{entry['path']} is not committed")
            continue
        data = file.read_bytes()
        if ref.labels_sha256(data) != entry["labelsSha256"]:
            problems.append(f"{entry['path']} changed after it was sealed: its SHA-256 is not the recorded labelsSha256")
            continue
        labels = json.loads(data)
        if labels.get("kind") != "jovra.benchmarkLabels":
            problems.append(f"{entry['path']} is not a label document")
            continue
        if labels["recording"]["sha256"] != entry["recordingSha256"]:
            problems.append(f"{entry['path']} is for another recording than the set records")
        if labels["split"] != entry["split"]:
            problems.append(f"{entry['path']}: the recorded split is not the label file's split")
        if ref.counts(labels) != entry["counts"]:
            problems.append(f"{entry['path']}: recorded counts {entry['counts']} are not the file's {ref.counts(labels)}")
        if labels["labelledBy"]["method"] != "human":
            problems.append(f"{entry['path']}: only labels a person made enter the set")
        if any(r["end"] is None for r in labels["rallies"]):
            problems.append(f"{entry['path']} was sealed with an open rally")
    if not problems and doc["status"] != ref.label_set_status(doc):
        problems.append(f"status is {doc['status']} but the targets say {ref.label_set_status(doc)}")
    return problems


def check_label_set(path, doc, docs) -> list[str]:
    return label_set_problems(doc)


CHECKS = {"jovra.fixture.labelScoring": check_fixture, "jovra.benchmarkLabels": check_labels,
          "jovra.benchmarkLabelSet": check_label_set}
