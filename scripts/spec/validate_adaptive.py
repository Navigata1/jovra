#!/usr/bin/env python3
"""Validate the shared pane-policy contract (spec/adaptive; ADR-0025 §8, gate G-PANE). Standard library only.

Separate from validate.py (core), validate_studio.py and validate_room.py: it imports none of them and reads nothing
under spec/ except spec/adaptive. It checks:

1. Shape: schemaVersion, unique ids, closed input/expected objects, every value inside the file's declared domains,
   and consistent hinge inputs (posture 'none' <=> no hinge; occluding or half-opened => separating).
2. Drift: the vectors' breakpoint table equals the reference's and the table in ADR-0025 §2.
3. Categories: every required tag has at least one vector; the matrix covers every width class x height class x task;
   a vector carries the 'posture' tag (and the 'posture-' id prefix) exactly when it has a posture or hinge input,
   so the iOS port can skip those by name (ADR-0025 §5).
4. Rule invariants on the golden data itself (independent of the reference): font-scale vectors have exactly one
   fewer pane than their named default-band baseline, never below 1, same navigation; at least one shows a reduction
   and one shows the floor of 1; compact-height vectors never exceed 2 panes and a player there has 1 unless a
   separating vertical hinge splits the window; input-mode groups cover touch, keyboard and pointer, differ only by
   input mode and expect the same output; separating, occluding and tabletop vectors have the matching arrangement
   and hinge bounds.
5. Conformance: the Python reference (spec/adaptive/reference/pane_policy.py) reproduces every vector and every
   text-scale band mapping exactly.

--mutations proves the checks can fail: it runs this validator against scratch copies with a rule removed from the
reference (font scale, compact height, hinge split, tabletop) or a vector broken, and requires each run to fail.

Usage:  python3 scripts/spec/validate_adaptive.py [-v] [--reference PATH] [--vectors PATH] [--mutations]
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTIVE = ROOT / "spec" / "adaptive"
VECTORS = ADAPTIVE / "pane-policy.vectors.json"
REFERENCE = ADAPTIVE / "reference" / "pane_policy.py"
ADR = ROOT / "docs" / "adr" / "0025-adaptive-layout-policy.md"

SCHEMA_VERSION = "jovra.adaptive.pane-policy-vectors/1"
INPUT_KEYS = {"widthDp", "heightDp", "posture", "hinge", "textScaleBand", "inputMode", "task"}
HINGE_KEYS = {"orientation", "separating", "occluding"}
EXPECTED_KEYS = {"widthClass", "heightClass", "panes", "navigation", "arrangement", "hingeBounds"}
VECTOR_KEYS = {"id", "tags", "note", "input", "expected"}
OPTIONAL_VECTOR_KEYS = {"baseline", "group"}
REQUIRED_TAGS = ("matrix", "boundary", "compactHeight", "fontScale", "inputMode", "posture", "separatingHinge",
                 "occludingHinge", "nonSeparatingFold", "tabletop")
WIDTH_CLASSES = ("compact", "medium", "expanded", "large", "extraLarge")
HEIGHT_CLASSES = ("compact", "medium", "expanded")
INPUT_MODES = {"touch", "keyboard", "pointer"}


def load_reference(path: Path):
    spec = importlib.util.spec_from_file_location("pane_policy_under_test", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load reference {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def adr_breakpoints(text: str) -> dict:
    """Parse ADR-0025 §2's table: '| Compact | < 600 | Compact | < 480 |' style rows."""
    section = text.split("**2. One breakpoint table", 1)[1].split("**3.", 1)[0]
    width, height = [], []

    def parse(name: str, rng: str):
        rng = rng.strip()
        cls = {"Compact": "compact", "Medium": "medium", "Expanded": "expanded", "Large": "large",
               "Extra-large": "extraLarge"}[name.strip()]
        if m := re.fullmatch(r"<\s*(\d+)", rng):
            return {"class": cls, "min": 0, "maxExclusive": int(m[1])}
        if m := re.fullmatch(r"(\d+)\s*[–-]\s*(\d+)", rng):
            return {"class": cls, "min": int(m[1]), "maxExclusive": int(m[2]) + 1}
        if m := re.fullmatch(r"≥\s*(\d+)", rng):
            return {"class": cls, "min": int(m[1]), "maxExclusive": None}
        raise ValueError(f"unparsed ADR range {rng!r}")

    for line in section.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 4 or cells[0] in ("Width", "") or set(cells[0]) <= {"-"}:
            continue
        width.append(parse(cells[0], cells[1]))
        if cells[2]:
            height.append(parse(cells[2], cells[3]))
    return {"width": width, "height": height}


class Report:
    def __init__(self, verbose: bool):
        self.problems: list[str] = []
        self.verbose = verbose

    def fail(self, msg: str):
        self.problems.append(msg)

    def note(self, msg: str):
        if self.verbose:
            print("  " + msg)


def check_shape(doc: dict, r: Report) -> dict:
    if doc.get("schemaVersion") != SCHEMA_VERSION:
        r.fail(f"schemaVersion must be {SCHEMA_VERSION!r}")
    dom = doc.get("domains", {})
    vectors = doc.get("vectors", [])
    by_id: dict = {}
    for v in vectors:
        vid = v.get("id", "<no id>")
        if vid in by_id:
            r.fail(f"{vid}: duplicate id")
        by_id[vid] = v
        keys = set(v)
        if not VECTOR_KEYS <= keys or keys - VECTOR_KEYS - OPTIONAL_VECTOR_KEYS:
            r.fail(f"{vid}: vector keys {sorted(keys)} must be {sorted(VECTOR_KEYS)} plus optional "
                   f"{sorted(OPTIONAL_VECTOR_KEYS)}")
            continue
        unknown_tags = set(v["tags"]) - set(doc.get("tags", {}))
        if not v["tags"] or unknown_tags:
            r.fail(f"{vid}: tags {v['tags']} must be non-empty and declared in 'tags' (unknown: {sorted(unknown_tags)})")
        i, e = v["input"], v["expected"]
        if set(i) != INPUT_KEYS:
            r.fail(f"{vid}: input keys {sorted(i)} != {sorted(INPUT_KEYS)}")
            continue
        if set(e) != EXPECTED_KEYS:
            r.fail(f"{vid}: expected keys {sorted(e)} != {sorted(EXPECTED_KEYS)}")
            continue
        for k in ("widthDp", "heightDp"):
            if not isinstance(i[k], (int, float)) or isinstance(i[k], bool) or i[k] <= 0:
                r.fail(f"{vid}: input.{k} must be a positive number")
        for k, d in (("posture", "posture"), ("textScaleBand", "textScaleBand"), ("inputMode", "inputMode"),
                     ("task", "task")):
            if i[k] not in dom.get(d, []):
                r.fail(f"{vid}: input.{k} {i[k]!r} not in domains.{d}")
        for k, d in (("navigation", "navigation"), ("arrangement", "arrangement"), ("hingeBounds", "hingeBounds")):
            if e[k] not in dom.get(d, []):
                r.fail(f"{vid}: expected.{k} {e[k]!r} not in domains.{d}")
        if e["widthClass"] not in WIDTH_CLASSES or e["heightClass"] not in HEIGHT_CLASSES:
            r.fail(f"{vid}: expected width/height class unknown")
        if not isinstance(e["panes"], int) or isinstance(e["panes"], bool) or not 1 <= e["panes"] <= 3:
            r.fail(f"{vid}: expected.panes must be an integer 1..3")
        h = i["hinge"]
        if (i["posture"] == "none") != (h is None):
            r.fail(f"{vid}: posture 'none' if and only if hinge is null")
        if h is not None:
            if not isinstance(h, dict) or set(h) != HINGE_KEYS:
                r.fail(f"{vid}: hinge keys must be {sorted(HINGE_KEYS)}")
                continue
            if h["orientation"] not in dom.get("hingeOrientation", []):
                r.fail(f"{vid}: hinge.orientation {h['orientation']!r} unknown")
            if not isinstance(h["separating"], bool) or not isinstance(h["occluding"], bool):
                r.fail(f"{vid}: hinge.separating and hinge.occluding must be booleans")
            if h["occluding"] and not h["separating"]:
                r.fail(f"{vid}: an occluding hinge is always separating (FoldingFeature.isSeparating)")
            if i["posture"] == "halfOpened" and not h["separating"]:
                r.fail(f"{vid}: a half-opened fold is always separating (FoldingFeature.isSeparating)")
        if "baseline" in v and "fontScale" not in v["tags"]:
            r.fail(f"{vid}: 'baseline' is only for fontScale vectors")
        if "group" in v and "inputMode" not in v["tags"]:
            r.fail(f"{vid}: 'group' is only for inputMode vectors")
    for b in doc.get("textScaleBands", []):
        bid = b.get("id", "<no id>")
        if bid in by_id:
            r.fail(f"{bid}: duplicate id")
        by_id[bid] = b
        if b.get("band") not in dom.get("textScaleBand", []) or b.get("platform") not in ("android", "ios"):
            r.fail(f"{bid}: band/platform invalid")
        if b.get("platform") == "android" and not isinstance(b.get("fontScale"), (int, float)):
            r.fail(f"{bid}: android band vectors carry a numeric fontScale")
        if b.get("platform") == "ios" and not isinstance(b.get("dynamicTypeSize"), str):
            r.fail(f"{bid}: ios band vectors carry a dynamicTypeSize name")
    return {v["id"]: v for v in vectors if "id" in v}


def check_drift(doc: dict, ref, r: Report):
    declared = doc.get("breakpoints")
    if declared != ref.BREAKPOINTS:
        r.fail("breakpoints in the vectors differ from the reference's BREAKPOINTS")
    try:
        from_adr = adr_breakpoints(ADR.read_text(encoding="utf-8"))
    except (OSError, IndexError, ValueError, KeyError) as exc:
        r.fail(f"cannot read the breakpoint table from {ADR.relative_to(ROOT)}: {exc}")
        return
    if declared != from_adr:
        r.fail(f"breakpoints in the vectors differ from ADR-0025 §2: {from_adr}")
    else:
        r.note("breakpoints match ADR-0025 §2")


def is_vertical_split(i: dict) -> bool:
    h = i["hinge"]
    return h is not None and h["separating"] and h["orientation"] == "vertical"


def check_categories(doc: dict, vectors: dict, r: Report):
    tagged = {t: [v for v in vectors.values() if t in v["tags"]] for t in doc.get("tags", {})}
    for t in REQUIRED_TAGS:
        if not tagged.get(t):
            r.fail(f"category {t!r} has no vector")
        else:
            r.note(f"{t}: {len(tagged[t])} vectors")
    tasks = doc.get("domains", {}).get("task", [])
    seen = {(v["expected"]["widthClass"], v["expected"]["heightClass"], v["input"]["task"])
            for v in tagged.get("matrix", [])}
    for wc in WIDTH_CLASSES:
        for hc in HEIGHT_CLASSES:
            for task in tasks:
                if (wc, hc, task) not in seen:
                    r.fail(f"matrix misses width {wc} x height {hc} x task {task}")
    for v in vectors.values():
        has_posture = v["input"]["posture"] != "none" or v["input"]["hinge"] is not None
        tag = "posture" in v["tags"]
        prefix = v["id"].startswith("posture-")
        if has_posture != tag or has_posture != prefix:
            r.fail(f"{v['id']}: a vector with a posture/hinge input must carry the 'posture' tag and the 'posture-' "
                   f"id prefix, and only such a vector may (input posture={has_posture}, tag={tag}, prefix={prefix})")
        if "matrix" in v["tags"] and has_posture:
            r.fail(f"{v['id']}: matrix vectors have no posture")


def check_invariants(vectors: dict, r: Report):
    floor_seen = reduction_seen = False
    for v in vectors.values():
        i, e, vid = v["input"], v["expected"], v["id"]
        if "fontScale" in v["tags"]:
            base = vectors.get(v.get("baseline", ""))
            if i["textScaleBand"] != "accessibility" or base is None:
                r.fail(f"{vid}: a fontScale vector uses the accessibility band and names an existing baseline")
                continue
            bi = dict(base["input"], textScaleBand="accessibility")
            if bi != i or base["input"]["textScaleBand"] != "default":
                r.fail(f"{vid}: baseline {base['id']} must be the same input in the default band")
            want = max(1, base["expected"]["panes"] - 1)
            if e["panes"] != want:
                r.fail(f"{vid}: accessibility text must give one fewer pane than {base['id']} "
                       f"({base['expected']['panes']}), never below 1: expected {want}, vector says {e['panes']}")
            if e["navigation"] != base["expected"]["navigation"]:
                r.fail(f"{vid}: accessibility text never changes navigation")
            floor_seen |= base["expected"]["panes"] == 1
            reduction_seen |= base["expected"]["panes"] > 1
        if e["heightClass"] == "compact":
            if e["panes"] > 2:
                r.fail(f"{vid}: compact height allows at most 2 panes")
            if i["task"] == "player" and not is_vertical_split(i) and e["panes"] != 1:
                r.fail(f"{vid}: at compact height the player keeps priority (1 pane, supporting panels as sheets)")
        if "separatingHinge" in v["tags"]:
            if not is_vertical_split(i):
                r.fail(f"{vid}: separatingHinge vectors have a separating vertical hinge")
            elif i["textScaleBand"] == "default" and (e["panes"], e["arrangement"]) != (2, "splitAtHinge"):
                r.fail(f"{vid}: a separating vertical hinge gives exactly 2 panes split at the hinge")
        if "occludingHinge" in v["tags"] and (not (i["hinge"] or {}).get("occluding") or e["hingeBounds"] != "noContent"):
            r.fail(f"{vid}: an occluding hinge means no content inside its bounds (hingeBounds noContent)")
        if "tabletop" in v["tags"]:
            h = i["hinge"] or {}
            if i["posture"] != "halfOpened" or h.get("orientation") != "horizontal":
                r.fail(f"{vid}: tabletop vectors are half-opened with a horizontal hinge")
            elif i["task"] == "player" and i["textScaleBand"] == "default" and e["arrangement"] != "tabletop":
                r.fail(f"{vid}: a player in tabletop puts the picture above the hinge (arrangement tabletop)")
            elif i["task"] != "player" and e["arrangement"] == "tabletop":
                r.fail(f"{vid}: only player screens use the tabletop arrangement")
        if i["hinge"] is not None and i["hinge"]["separating"] and e["hingeBounds"] == "ignore":
            r.fail(f"{vid}: a separating hinge is never ignored (no controls in or beside it)")
    if not floor_seen:
        r.fail("fontScale: no vector shows the floor of one pane (baseline already 1)")
    if not reduction_seen:
        r.fail("fontScale: no vector shows a pane being removed")
    groups: dict = {}
    for v in vectors.values():
        if "inputMode" in v["tags"]:
            if "group" not in v:
                r.fail(f"{v['id']}: inputMode vectors name a 'group'")
                continue
            groups.setdefault(v["group"], []).append(v)
    for g, members in groups.items():
        if {m["input"]["inputMode"] for m in members} != INPUT_MODES:
            r.fail(f"input-mode group {g}: must cover touch, keyboard and pointer")
        strip = [{k: x for k, x in m["input"].items() if k != "inputMode"} for m in members]
        if any(s != strip[0] for s in strip) or any(m["expected"] != members[0]["expected"] for m in members):
            r.fail(f"input-mode group {g}: members must differ only by inputMode and expect the same layout")


def check_conformance(doc: dict, vectors: dict, ref, r: Report) -> int:
    passed = 0
    for v in vectors.values():
        try:
            got = ref.decide(v["input"])
        except Exception as exc:  # the reference must not raise on a valid vector
            r.fail(f"{v['id']}: reference raised {type(exc).__name__}: {exc}")
            continue
        if got != v["expected"]:
            diff = {k: (v["expected"].get(k), got.get(k)) for k in EXPECTED_KEYS if v["expected"].get(k) != got.get(k)}
            r.fail(f"{v['id']}: reference disagrees (expected, got): {diff}")
        else:
            passed += 1
    for b in doc.get("textScaleBands", []):
        value = b.get("fontScale") if b["platform"] == "android" else b.get("dynamicTypeSize")
        try:
            got = ref.text_scale_band(b["platform"], value)
        except Exception as exc:
            r.fail(f"{b['id']}: reference raised {type(exc).__name__}: {exc}")
            continue
        if got != b["band"]:
            r.fail(f"{b['id']}: band expected {b['band']!r}, reference gives {got!r}")
        else:
            passed += 1
    return passed


def validate(vectors_path: Path, reference_path: Path, verbose: bool) -> int:
    r = Report(verbose)
    doc = json.loads(vectors_path.read_text(encoding="utf-8"))
    ref = load_reference(reference_path)
    vectors = check_shape(doc, r)
    if not r.problems:
        check_drift(doc, ref, r)
        check_categories(doc, vectors, r)
        check_invariants(vectors, r)
    passed = check_conformance(doc, vectors, ref, r)
    n_vec, n_band = len(doc.get("vectors", [])), len(doc.get("textScaleBands", []))
    n_posture = sum(1 for v in doc.get("vectors", []) if "posture" in v.get("tags", []))
    if r.problems:
        for p in r.problems:
            print("FAIL " + p)
        print(f"pane-policy: FAILED with {len(r.problems)} problem(s); {passed}/{n_vec + n_band} cases agree")
        return 1
    print(f"pane-policy: OK {n_vec} vectors ({n_posture} posture, Android only; {n_vec - n_posture} for both "
          f"platforms) and {n_band} text-scale band cases; reference agrees with all {passed}")
    return 0


# --- --mutations: prove each check can fail ---------------------------------------------------------------------

REFERENCE_MUTATIONS = {
    # name: (exact text in the reference, replacement, a vector id that must then fail)
    "font-scale rule removed": ('if text_scale_band == "accessibility":', "if False:", "font-scale-expanded-listDetail"),
    "compact-height cap removed (width alone)": ('if height_class == "compact":', "if False:",
                                                 "compact-height-landscape-phone-player"),
    "separating-hinge split removed": ("if vertical_split:", "if False:", "posture-separating-vertical-flat-listDetail"),
    "tabletop arrangement removed": ("elif tabletop:", "elif False:", "posture-tabletop-player"),
}


def vector_mutations(doc: dict) -> dict:
    def flip_panes(d):
        v = next(x for x in d["vectors"] if x["id"] == "matrix-large-medium-workspace")
        v["expected"]["panes"] = 2
        return "matrix-large-medium-workspace"

    def untag_posture(d):
        v = next(x for x in d["vectors"] if x["id"] == "posture-tabletop-player")
        v["tags"].remove("posture")
        return "posture-tabletop-player"

    def drop_tabletop(d):
        d["vectors"] = [x for x in d["vectors"] if "tabletop" not in x["tags"]]
        return "category 'tabletop' has no vector"

    def inconsistent_font(d):
        v = next(x for x in d["vectors"] if x["id"] == "font-scale-compact-never-below-one")
        v["expected"]["panes"] = 0
        return "font-scale-compact-never-below-one"

    return {"a broken vector (panes flipped)": flip_panes, "posture tag removed": untag_posture,
            "tabletop category emptied": drop_tabletop, "font-scale vector below one pane": inconsistent_font}


def run_child(vectors: Path, reference: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(Path(__file__).resolve()), "--vectors", str(vectors),
                           "--reference", str(reference)], capture_output=True, text=True, check=False)


def mutations() -> int:
    failures = []
    source = REFERENCE.read_text(encoding="utf-8")
    doc = json.loads(VECTORS.read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        baseline = run_child(VECTORS, REFERENCE)
        if baseline.returncode != 0:
            print(baseline.stdout)
            print("MUTATIONS: the unmutated contract must pass first")
            return 1
        for name, (old, new, must_fail) in REFERENCE_MUTATIONS.items():
            if source.count(old) != 1:
                failures.append(f"{name}: anchor {old!r} must occur exactly once in the reference")
                continue
            path = tmp / f"mutant_{len(failures)}_{abs(hash(name))}.py"
            path.write_text(source.replace(old, new), encoding="utf-8")
            res = run_child(VECTORS, path)
            ok = res.returncode != 0 and must_fail in res.stdout
            print(f"mutation [{name}]: {'caught' if ok else 'NOT CAUGHT'} (exit {res.returncode})")
            if not ok:
                failures.append(name)
        for name, mutate in vector_mutations(doc).items():
            d = json.loads(json.dumps(doc))
            must_fail = mutate(d)
            path = tmp / f"vectors_{abs(hash(name))}.json"
            path.write_text(json.dumps(d), encoding="utf-8")
            res = run_child(path, REFERENCE)
            ok = res.returncode != 0 and must_fail in res.stdout
            print(f"mutation [{name}]: {'caught' if ok else 'NOT CAUGHT'} (exit {res.returncode})")
            if not ok:
                failures.append(name)
    if failures:
        print(f"MUTATIONS: {len(failures)} not caught: {failures}")
        return 1
    print(f"MUTATIONS: all {len(REFERENCE_MUTATIONS) + len(vector_mutations(doc))} caught")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--vectors", type=Path, default=VECTORS)
    ap.add_argument("--reference", type=Path, default=REFERENCE)
    ap.add_argument("--mutations", action="store_true", help="prove the checks fail on known-bad inputs")
    args = ap.parse_args(argv)
    if args.mutations:
        return mutations()
    return validate(args.vectors, args.reference, args.verbose)


if __name__ == "__main__":
    sys.exit(main())
