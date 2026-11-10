"""Studio media fixtures (S08): the ground-truth manifests under spec/studio/fixtures/media/. Module page:
spec/studio/modules/media-fixtures.md.

The media is generated at test time by scripts/media/studio/render_studio.py; only these manifests are committed.
This module declares every manifest so the fixture generator keeps it and the determinism pass checks it:

* the **plan** part is recomputed here from the generator's own set modules, without drawing a pixel or running
  ffmpeg, so any change to the generator that is not re-rendered shows up as a stale fixture;
* the **hashes** part is what only a render proves; it is carried over from the committed file, and the self-test
  below fails when it was rendered from a different generator source (``renderedWithSourceHash``).

The self-tests check each manifest against its schema and against rules written independently of the generator
(durations, sample counts, click frames, the frame map and its hash, labels, the restart's gap), and fold the
coherent match's point log through the core reference to the score the manifest states.
"""

from __future__ import annotations

import hashlib
import json
import sys
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
STUDIO_MEDIA = ROOT / "scripts" / "media" / "studio"
FIX = ROOT / "spec" / "studio" / "fixtures"
for _p in (STUDIO_MEDIA, STUDIO_MEDIA.parent, ROOT / "spec" / "reference"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

import render_studio  # noqa: E402
from jovra_studio_media import manifest  # noqa: E402
from jovra_studio_media.sets import discover  # noqa: E402

TRUTH = "jovra.studio-media-truth/1"
SUBSET = "jovra.studio-media-demo-subset/1"
SCHEMAS = {TRUTH: "studio-media-truth.schema.json", SUBSET: "studio-media-demo-subset.schema.json"}
ANGLES = ["Baseline", "Far baseline", "Near left", "Near right", "Far left", "Far right"]
# The Jon vs Alex sample match is 6-4 6-3 to Jon (side A): the core sample's stated result, hand-checked here.
MATCH_SCORELINE = "6-4 6-3"


def _committed_hashes(rel: str) -> dict | None:
    path = FIX / rel
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8")).get("hashes")


def fixtures(sample) -> dict:
    modules = discover()
    docs = {}
    for module in modules:
        src_hash = render_studio.set_hash(module)
        for clip in module.clips():
            rel = manifest.rel_path(module.SET, clip.id)
            docs[rel] = manifest.document(manifest.plan(module.SET, clip, src_hash), _committed_hashes(rel))
    docs[render_studio.DEMO_SUBSET] = render_studio.demo_subset(modules)
    return docs


def _manifests() -> list[tuple[str, dict]]:
    docs = [(p.relative_to(FIX).as_posix(), json.loads(p.read_text(encoding="utf-8")))
            for p in sorted((FIX / "media").rglob("*.json")) if p.name != "demo-subset.json"]
    return [(rel, d) for rel, d in docs if d.get("schemaVersion") == TRUTH]   # S58's multiangle/ has its own kinds


def _frame_map_sha256(doc: dict) -> str:
    b = doc["barcode"]
    sha = hashlib.sha256()
    for run in b["frameMap"]:
        for frame_id in range(run["frameId"], run["frameId"] + run["count"]):
            sha.update(bytes([b["sourceId"], b["segment"]]) + frame_id.to_bytes(3, "big"))
    return sha.hexdigest()


def _problems(doc: dict) -> list[str]:
    out = []
    v = doc["video"]
    fps = Fraction(v["frameRate"]["num"], v["frameRate"]["den"])
    duration = Fraction(v["frameCount"]) / fps
    if Fraction(v["duration"]["value"], v["duration"]["timescale"]) != duration:
        out.append("duration is not frameCount / frameRate")
    if doc["hashes"]["renderedWithSourceHash"] != doc["generator"]["sourceHash"]:
        out.append("hashes were rendered from another generator source: run scripts/media/studio/render_studio.py")
    if not doc["media"]["path"].endswith(f"-{doc['generator']['sourceHash'][:16]}/{doc['media']['fileName']}"):
        out.append("media.path is not the cache folder of this generator source")
    if doc["audio"] is not None and doc["audio"]["sampleCount"] != duration * 48_000:
        out.append("audio sampleCount is not the video duration at 48 kHz")
    if (doc["clicks"] is None) != (doc["audio"] is None):
        out.append("clicks are listed exactly when there is an audio track")
    if doc["clicks"] is not None:
        samples = [e["sample"] for e in doc["clicks"]["events"]]
        for e in doc["clicks"]["events"]:
            if Fraction(e["time"]["value"], e["time"]["timescale"]) != Fraction(e["sample"], 48_000):
                out.append(f"click at sample {e['sample']}: time is not sample / 48000")
            if e["frame"] != e["sample"] * fps.numerator // (48_000 * fps.denominator):
                out.append(f"click at sample {e['sample']}: frame is not floor(time x fps)")
            if e["sample"] + doc["clicks"]["durationSamples"] > doc["audio"]["sampleCount"]:
                out.append(f"click at sample {e['sample']} runs past the end of the audio")
        if samples != sorted(samples) or any(b - a < 4_800 for a, b in zip(samples, samples[1:])):
            out.append("clicks are not in order at least 100 ms apart")
    if doc["barcode"] is not None:
        at = 0
        for run in doc["barcode"]["frameMap"]:
            if run["frame"] != at:
                out.append("frame map runs are not contiguous from frame 0")
            at = run["frame"] + run["count"]
        if at != v["frameCount"]:
            out.append("the frame map does not cover every frame")
        elif doc["barcode"]["frameMapSha256"] != _frame_map_sha256(doc):
            out.append("frameMapSha256 is not the hash of the frame map")
    kinds = [label["kind"] for label in doc["labels"]]
    if doc["role"] in ("match", "broll", "angle") and "sample" not in kinds:
        out.append("demo media must burn in the Sample label")
    for label in doc["labels"]:
        if label["kind"] == "sample" and label["text"] != "Sample video (synthetic)":
            out.append("the Sample label must read 'Sample video (synthetic)'")
    if doc["role"] == "angle":
        names = [label["text"] for label in doc["labels"] if label["kind"] == "angle"]
        if names != [doc["angle"]["name"]]:
            out.append("an angle render burns in exactly its angle name")
        if doc["media"]["bundled"] is not True:
            out.append("angle renders are the bundled demo subset")
    return out


def check_manifests(ctx, rep) -> None:
    docs = _manifests()
    if not docs:
        rep.fail("media fixtures", "no manifest under spec/studio/fixtures/media")
        return
    for rel, doc in docs:
        errors = ctx.schemas.validate(doc, SCHEMAS[TRUTH])
        if errors:
            rep.fail(rel, "schema: " + "; ".join(errors[:4]))
            continue
        problems = _problems(doc)
        for p in problems:
            rep.fail(rel, p)
        if not problems:
            rep.ok("media fixture manifests consistent")


def check_match_fold(ctx, rep) -> None:
    """The coherent match's point log folds through the core reference to the score its manifest states."""
    from jovra_ref import scoring
    docs = [(rel, d) for rel, d in _manifests() if d["role"] == "match"]
    if not docs:
        rep.fail("media fixtures", "no coherent match manifest")
    for rel, doc in docs:
        m = doc["match"]
        result = scoring.fold(m["setup"], m["log"])
        sets = [s["games"] for s in result["sets"]]
        got = {"scoreline": result["match"]["scoreline"], "winnerSide": result["match"]["winner"], "sets": sets,
               "status": result["match"]["status"]}
        if got != m["expected"]:
            rep.fail(rel, f"the point log folds to {got}, the manifest states {m['expected']}")
            continue
        if got["scoreline"] != MATCH_SCORELINE:
            rep.fail(rel, f"the sample match must fold to {MATCH_SCORELINE}, got {got['scoreline']}")
            continue
        fps = Fraction(doc["video"]["frameRate"]["num"], doc["video"]["frameRate"]["den"])
        windows_ok = all(p["eventId"] == e["id"] and p["tStartMs"] == e["tStartMs"] and p["tEndMs"] == e["tEndMs"]
                         and p["startFrame"] == int(Fraction(p["tStartMs"], 1000) * fps)
                         and p["endFrame"] == int(Fraction(p["tEndMs"], 1000) * fps)
                         for p, e in zip(m["points"], m["log"])) and len(m["points"]) == len(m["log"])
        clicks = [e["sample"] for e in doc["clicks"]["events"]]
        inside = all(any(p["tStartMs"] * 48 <= s < p["tEndMs"] * 48 for p in m["points"]) for s in clicks)
        if not windows_ok:
            rep.fail(rel, "point windows do not match the log's times and frames")
        elif sum(p["hits"] for p in m["points"]) != len(clicks) or not inside:
            rep.fail(rel, "every hit click must fall inside a point, and the points' hits must count the clicks")
        else:
            rep.ok("coherent match folds to its stated score")


def check_restart(ctx, rep) -> None:
    """The restarted capture: segment files tile the session clock around one gap; a click in the gap is in no file."""
    segs = sorted((d for _, d in _manifests() if "restart" in d), key=lambda d: d["restart"]["segment"])
    if [d["restart"]["segment"] for d in segs] != [0, 1]:
        rep.fail("media fixtures", "the restart variant must have segments 0 and 1")
        return
    gap = segs[0]["restart"]["gaps"][0]
    first, second = segs
    ok = (first["barcode"]["frameMap"][0]["frameId"] == 0 and first["video"]["frameCount"] == gap["fromFrame"]
          and second["barcode"]["frameMap"][0]["frameId"] == gap["toFrame"]
          and second["restart"]["sessionStartFrame"] == gap["toFrame"]
          and first["barcode"]["sourceId"] == second["barcode"]["sourceId"]
          and [d["barcode"]["segment"] for d in segs] == [0, 1]
          and gap["toFrame"] + second["video"]["frameCount"] == second["restart"]["sessionFrameCount"])
    in_gap = first["restart"]["clicksInGapFrames"]
    if not ok:
        rep.fail("media fixtures", "restart segments do not tile the session clock around the gap")
    elif not in_gap or not all(gap["fromFrame"] <= f < gap["toFrame"] for f in in_gap):
        rep.fail("media fixtures", "the restart fixture must lose at least one click to the gap")
    else:
        rep.ok("restart fixture tiles the session clock")


def check_demo_subset(ctx, rep) -> None:
    doc = json.loads((FIX / render_studio.DEMO_SUBSET).read_text(encoding="utf-8"))
    errors = ctx.schemas.validate(doc, SCHEMAS[SUBSET])
    if errors:
        rep.fail(render_studio.DEMO_SUBSET, "schema: " + "; ".join(errors[:4]))
        return
    bundled = sorted(rel for rel, d in _manifests() if d["media"]["bundled"])
    listed = sorted(f["manifest"] for f in doc["files"])
    angles = [f.get("angle") for f in doc["files"] if f["role"] == "angle"]
    if listed != bundled:
        rep.fail(render_studio.DEMO_SUBSET, f"lists {listed}, the manifests mark {bundled} as bundled")
    elif angles != ANGLES:
        rep.fail(render_studio.DEMO_SUBSET, f"the ST27 demo needs the six angles {ANGLES}, has {angles}")
    elif doc["budgetBytes"] != 25_000_000:
        rep.fail(render_studio.DEMO_SUBSET, "the bundled demo budget is 25 MB")
    else:
        rep.ok("demo subset lists the bundled media")


SELF_TESTS = {"media-fixtures-manifests": check_manifests, "media-fixtures-match-fold": check_match_fold,
              "media-fixtures-restart": check_restart, "media-fixtures-demo-subset": check_demo_subset}
