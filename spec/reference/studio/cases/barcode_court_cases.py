"""Barcode-court trusted contexts and compile vectors over the S08 media (`barcode-court`). Module page:
spec/studio/modules/barcode-court.md.

Two Sample projects are built from the S08 media fixtures (spec/studio/modules/media-fixtures.md):

* `court-60`: one camera, the 60 fps barcode source `bc-060` (10 s, eight clicks), so a 1/2x replay of real 60 fps
  frames plays at 30 fps output;
* `court-match`: the coherent synthetic match (54:00 at 30 fps, every hit a click, the 124-point log that folds to
  6-4 6-3) as the one camera, with the three B-roll clips.

Each project's records (spec/studio/fixtures/records/barcode-court/) are a SourceManifest whose original and render
proxy are the generated file itself, with its real SHA-256 and the hash of its decoded PTS table (one jovra.pts-table/1
record per source), an identity SyncMap (the one camera is the reference: offset 0, rate 1), a keeper catalog over the
S08 ground truth (keeper windows from the point log or the barcode source's frames, contacts at the click frames), a
B-roll catalog and a ReferenceCatalog. The trusted EDL context is `bundle.edl_context` over those records, exactly as
for the sample-court-day project.

The vector file `vectors/barcode-court.json` holds:

* `media`: which S08 file each source is, the generator source it must come from, and the measurements a render on
  the build machine gave (SHA-256, size, decoded PTS index, encoder). scripts/media/studio/barcode_court.py --measure
  writes them; this module carries them over (like the S08 manifests' `hashes`) and reports the context stale when
  the generator's source no longer matches. With JOVRA_STUDIO_MEDIA=1 the media self-test also regenerates the files
  into the cache and compares their bytes.
* one `context` case per project: the compile context, the barcode table and click onsets of every source, and (for
  the match) the point-event fold of every kept point.
* `compile` cases: a hand-written StoryPlan compiled by compile.py (S07) with a request, its expected output, and what
  a renderer test compares: the expected output frame map (`framemap.frame_map`), the click map, the overlay schedule,
  the operations it exercises and, for a plan with dissolves or dips, the same for its clean alternate.
"""

from __future__ import annotations

import copy
import json
import os
import sys
from fractions import Fraction
from pathlib import Path

from studio import bundle, compile as compiler, edl, framemap, normalization, records
from studio.core import Reject, apply_patch, canonical_bytes, canonical_sha256

KIND = "barcode-court"
VECTOR = "vectors/barcode-court.json"
RECORDS = "records/barcode-court"
ROOT = Path(__file__).resolve().parents[4]
FIX = ROOT / "spec" / "studio" / "fixtures"
STUDIO_MEDIA = ROOT / "scripts" / "media" / "studio"
for _p in (STUDIO_MEDIA, STUDIO_MEDIA.parent, ROOT / "spec" / "reference"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))
MEDIA_ENV = "JOVRA_STUDIO_MEDIA"
CREATED = "2026-11-08T00:00:00Z"
NORMALIZER = "jovra-normalize@0.1.0"
RATE1 = {"num": 1_000_000_000, "den": 1_000_000_000}
US = 1_000_000
FPS30 = {"num": 30, "den": 1}

# ----- the two projects ---------------------------------------------------------------------------------------------

SOURCES = {
    "court-60": [("bc-060", "barcodeSources/bc-060", "match", "Barcode source, 60 fps")],
    "court-match": [("match", "match/match-jon-vs-alex", "match", "Coherent synthetic match"),
                    ("broll-push", "broll/broll-court-push", "broll", "Court push-in"),
                    ("broll-drop", "broll/broll-ball-drop", "broll", "Ball drop"),
                    ("broll-pan", "broll/broll-sideline-pan", "broll", "Sideline pan")],
}
PROJECT_ID = {"court-60": "sample-barcode-court-60", "court-match": "sample-barcode-court-match"}
CONTEXT_ID = {p: f"context-{p}" for p in SOURCES}

# court-60: three keepers tile bc-060's 600 frames; their edges sit between clicks (frames 18 60 102 194 285 376 517
# 566), so a transition's handles never reach a contact's protected window.
COURT60_KEEPERS = [("k-01", "p-001", 0, 240), ("k-02", "p-002", 240, 446), ("k-03", "p-003", 446, 600)]

# court-match: the kept points (point numbers of the S08 log). Every point of at least 10 s, in match order.
MATCH_MIN_FRAMES = 300
BROLL_WINDOW = (15, 165)       # 5 s of each 6 s clip, leaving half-second handles for a dip or dissolve
NOTE_USES = {"note-goal": "goal", "note-drill": "drill", "note-next": "next", "note-players": "players",
             "note-dedication": "dedication", "note-caption": "caption"}
BROLL_CHAPTER = {"b-push": "arrival", "b-drop": "after", "b-pan": "after"}
BROLL_SOURCE = {"b-push": "broll-push", "b-drop": "broll-drop", "b-pan": "broll-pan"}


# ----- S08 ground truth -------------------------------------------------------------------------------------------

def s08(rel: str) -> dict:
    """The committed S08 manifest of one media file (`<set>/<clip>`)."""
    return json.loads((FIX / "media" / f"{rel}.json").read_text(encoding="utf-8"))


def live_source_hash(rel: str) -> str:
    """The S08 generator's source hash for the clip's set, computed from the generator's code now."""
    import render_studio   # on sys.path through media_fixtures_cases
    from jovra_studio_media.sets import discover
    set_name = rel.split("/")[0]
    return render_studio.set_hash(next(m for m in discover() if m.SET == set_name))


def _committed_media() -> dict:
    path = FIX / VECTOR
    if not path.is_file():
        return {}
    doc = json.loads(path.read_text(encoding="utf-8"))
    case = next((c for c in doc["cases"] if c["id"] == "media"), None)
    return {e["manifest"]: e["measured"] for e in case["input"]["media"]} if case else {}


def media_entries() -> list:
    """Every bound media file: its S08 manifest, the generator source it must come from now, and the carried-over
    measurements (None until scripts/media/studio/barcode_court.py --measure has run)."""
    measured = _committed_media()
    out = []
    for project, sources in SOURCES.items():
        for sid, rel, role, _ in sources:
            doc = s08(rel)
            out.append({"project": project, "sourceId": sid, "manifest": rel, "role": role,
                        "generatorSourceHash": live_source_hash(rel),
                        "barcodeSourceId": doc["barcode"]["sourceId"],
                        "frameMapSha256": doc["barcode"]["frameMapSha256"],
                        "measured": measured.get(rel)})
    return out


# ----- records --------------------------------------------------------------------------------------------------

def _zero_measure(doc: dict) -> dict:
    """Placeholder measurements before the first --measure (the context is then reported stale)."""
    fps = doc["video"]["frameRate"]
    step = 15360 * fps["den"] // fps["num"]
    return {"measuredWithSourceHash": "0" * 64, "encoder": "unmeasured", "sha256": "0" * 64, "sizeBytes": 1,
            "videoTimescale": 15360, "ptsTicks": [{"value": 0, "step": step, "count": doc["video"]["frameCount"]}]}


def pts_table(sid: str, doc: dict, m: dict) -> dict:
    """The decoded PTS index of the file and the half-up selection of its render proxy (the file itself, CFR at its
    own rate, so the selection is the identity)."""
    v = doc["video"]
    ticks = normalization.expand_pts(m["ptsTicks"])
    frame_ticks = Fraction(m["videoTimescale"] * v["frameRate"]["den"], v["frameRate"]["num"])
    original = {"timescale": m["videoTimescale"], "nominalFps": v["frameRate"], "pts": m["ptsTicks"],
                "endPts": int(ticks[-1] + frame_ticks), "frameCount": v["frameCount"], "width": v["width"],
                "height": v["height"], "rotationDegrees": 0, "hdr": False, "transfer": "bt709"}
    return normalization.derive_table({"sourceId": sid, "normalizerVersion": NORMALIZER, "original": original,
                                       "proxy": {"fps": v["frameRate"], "targetLongEdge": max(v["width"], v["height"]),
                                                 "toneMap": None}})


def _duration_us(doc: dict) -> int:
    v = doc["video"]
    us = Fraction(v["frameCount"] * v["frameRate"]["den"] * US, v["frameRate"]["num"])
    assert us.denominator == 1
    return int(us)


def source_entry(sid: str, rel: str, role: str, label: str, primary: bool, m: dict, table: dict) -> dict:
    doc = s08(rel)
    v, ts = doc["video"], m["videoTimescale"]
    dur = _duration_us(doc)
    return {
        "sourceId": sid, "role": role, "slot": "near-baseline" if role == "match" else None, "isPrimary": primary,
        "deviceLabel": f"Sample {label} (synthetic)",
        "original": {"sha256": m["sha256"], "sizeBytes": m["sizeBytes"], "container": "mp4", "durationUs": dur,
                     "timescale": ts, "startPts": {"value": 0, "timescale": ts}, "frameCount": v["frameCount"],
                     "nominalFps": v["frameRate"], "vfr": False,
                     "video": {"codec": "h264", "width": v["width"], "height": v["height"], "rotationDegrees": 0,
                               "pixelAspect": {"num": 1, "den": 1}},
                     "colour": {"primaries": "bt709", "transfer": "bt709", "matrix": "bt709", "range": "limited",
                                "bitDepth": 8, "hdr": False},
                     "audio": None if doc["audio"] is None else {"codec": "aac", "sampleRate": 48000, "channels": 1}},
        "lens": {"kind": "unknown", "zoomFactor": None},
        "captureHints": {"wallClockStart": None, "wallClockSource": "none", "roomOffsetUs": None,
                         "roomRoundTripUs": None},
        "segments": [{"segmentId": "seg-0", "index": 0, "reason": "import", "fileZeroHostNs": None,
                      "startPts": {"value": 0, "timescale": ts}, "durationUs": dur, "frameCount": v["frameCount"]}],
        "proxies": [{"class": "render", "sha256": m["sha256"], "fps": v["frameRate"], "width": v["width"],
                     "height": v["height"], "frameCount": v["frameCount"],
                     "ptsTableSha256": normalization.table_sha256(table), "normalizerVersion": NORMALIZER,
                     "rotationApplied": False, "toneMapped": False}],
        "verification": {"status": "verified", "method": "sha256-full-read-device", "verifiedAt": CREATED},
    }


def sync_map(project: str, primary: str, duration_us: int) -> dict:
    """Identity: the one camera is the reference (offset 0, rate 1), so session time is its own presentation time."""
    return {
        "schemaVersion": "jovra.sync-map/1", "projectId": PROJECT_ID[project], "revision": 1, "sample": True,
        "sourceManifestRevision": 1,
        "matchClock": {"unit": "us", "referenceSourceId": primary, "referenceSegmentId": "seg-0",
                       "origin": "earliest-coverage"},
        "outputFps": FPS30,
        "speedOfSound": {"mmPerSecond": 343000, "temperatureC": None, "method": "default-343"},
        "placements": [{"sourceId": primary, "slot": "near-baseline", "positionMm": {"xMm": 0, "yMm": -17365,
                                                                                     "zMm": 1500},
                        "from": "slot-default"}],
        "sources": [{"sourceId": primary, "audioLatencyUs": None, "gaps": [], "pieces": [{
            "segmentId": "seg-0", "sourceDurationUs": duration_us,
            "matchCoverage": {"startUs": 0, "endUs": duration_us}, "transform": {"offsetUs": 0, "rate": RATE1},
            "fit": None, "anchors": [], "state": "reference", "reasons": [], "checkpoints": [], "reviewedAt": None}]}],
        "provenance": {"capabilityId": "studio.multiCameraSync", "method": "jovra-sync", "methodVersion": "0.1",
                       "status": "estimated"},
    }


def _us_of_frame(frame: int, fps: dict) -> int:
    return int(Fraction(frame * fps["den"] * US, fps["num"]))


def court60_keepers(doc: dict) -> list:
    fps = doc["video"]["frameRate"]
    clicks = [e["frame"] for e in doc["clicks"]["events"]]
    return [{"keeperId": kid, "eventRefs": [pid],
             "session": {"startUs": _us_of_frame(a, fps), "endUs": _us_of_frame(b, fps)},
             "views": [{"sourceId": "bc-060", "window": {"inFrame": a, "outFrame": b}, "primary": True}],
             "contacts": [{"sourceId": "bc-060", "frame": f} for f in clicks if a <= f < b],
             "selection": "manual", "provenance": "manual"} for kid, pid, a, b in COURT60_KEEPERS]


def kept_points(doc: dict) -> list:
    return [p for p in doc["match"]["points"] if p["endFrame"] - p["startFrame"] >= MATCH_MIN_FRAMES]


def match_keepers(doc: dict) -> list:
    clicks = [e["frame"] for e in doc["clicks"]["events"]]
    out = []
    for p in kept_points(doc):
        a, b = p["startFrame"], p["endFrame"]
        out.append({"keeperId": f"k-{p['pointNumber']:03d}", "eventRefs": [f"p-{p['pointNumber']:03d}"],
                    "session": {"startUs": p["tStartMs"] * 1000, "endUs": p["tEndMs"] * 1000},
                    "views": [{"sourceId": "match", "window": {"inFrame": a, "outFrame": b}, "primary": True}],
                    "contacts": [{"sourceId": "match", "frame": f} for f in clicks if a <= f < b],
                    "selection": "manual", "provenance": "manual"})
    return out


def point_fold(doc: dict) -> dict:
    """The core fold of the match's point log (spec/reference/jovra_ref/scoring.py), per point number."""
    from jovra_ref import scoring
    m = doc["match"]
    result = scoring.fold(m["setup"], m["log"])
    sides = {pid: side for side, ids in m["setup"]["sides"].items() for pid in ids}
    out = {}
    for n, (p, folded) in enumerate(zip(m["points"], result["points"]), start=1):
        assert folded["id"] == p["eventId"]
        out[n] = {"eventId": p["eventId"], "set": folded["set"], "game": folded["gameInSet"],
                  "serverSide": sides[folded["server"]], "before": folded["before"],
                  "call": scoring.call_text(folded["call"], folded["serverSide"]), "winner": folded["winner"],
                  "provenance": folded["provenance"]}
    return out


def reference_catalog(project: str, keepers: list, fold: dict | None, cue_keeper: str | None) -> dict:
    refs = []
    for k in keepers:
        pid = k["eventRefs"][0]
        prov = fold[int(pid[2:])]["provenance"] if fold else "manual"
        refs.append({"refId": pid, "kind": "score", "provenance": prov, "eventRevision": 1,
                     "origin": {"recordKind": "point-event", "recordId": pid}})
    if project == "court-match":
        refs.append({"refId": "stat-first-serve-in", "kind": "metric", "provenance": "reviewed", "eventRevision": 1,
                     "origin": {"recordKind": "stat", "recordId": "stat-first-serve-in"}})
        refs.append({"refId": "cue-01", "kind": "cue", "provenance": "reviewed", "eventRevision": 1,
                     "origin": {"recordKind": "lesson-cue", "recordId": "cue-01"}})
        refs.append({"refId": "ann-01", "kind": "annotation", "provenance": "reviewed", "eventRevision": 1,
                     "origin": {"recordKind": "annotation", "recordId": "ann-01"}})
        for nid in NOTE_USES:
            refs.append({"refId": nid, "kind": "note", "provenance": "manual", "eventRevision": 1,
                         "origin": {"recordKind": "user-note", "recordId": nid}})
    return {"schemaVersion": "jovra.reference-catalog/1", "projectId": PROJECT_ID[project], "revision": 1,
            "sample": True, "eventRevision": 1, "references": refs, "consents": [], "rights": []}


def broll_catalog(project: str) -> dict:
    items = []
    if project == "court-match":
        for bid, sid in BROLL_SOURCE.items():
            what = next(x[3] for x in SOURCES[project] if x[0] == sid)
            items.append({"brollId": bid, "sourceId": sid,
                          "window": {"inFrame": BROLL_WINDOW[0], "outFrame": BROLL_WINDOW[1]},
                          "depictsThisMatch": True, "origin": "captured-today",
                          "rights": {"holder": "user", "scope": ["private-film"], "rightsRecordId": None},
                          "disclosureTemplateId": None, "revealsLocation": False, "participantIds": [],
                          "description": f"{what} (Sample video, synthetic)"})
    return {"schemaVersion": "jovra.broll-catalog/1", "projectId": PROJECT_ID[project], "revision": 1, "sample": True,
            "items": items}


CUE_KEEPER = "k-029"     # the cue and the annotation belong to point 29, the longest rally (18.2 s)


def project_records(project: str, media: dict) -> dict:
    """name -> record for one project (names relative to records/barcode-court/)."""
    out, entries = {}, []
    primary = SOURCES[project][0][0]
    for sid, rel, role, label in SOURCES[project]:
        doc = s08(rel)
        m = media.get(rel) or _zero_measure(doc)
        table = pts_table(sid, doc, m)
        out[f"{project}.pts-table.{sid}"] = dict(table, sample=True)
        entries.append(source_entry(sid, rel, role, label, sid == primary, m, table))
    out[f"{project}.source-manifest"] = {"schemaVersion": "jovra.source-manifest/1", "projectId": PROJECT_ID[project],
                                         "revision": 1, "sample": True, "createdAt": CREATED, "sources": entries}
    primary_doc = s08(SOURCES[project][0][1])
    out[f"{project}.sync-map"] = sync_map(project, primary, _duration_us(primary_doc))
    fold = point_fold(primary_doc) if project == "court-match" else None
    keepers = match_keepers(primary_doc) if project == "court-match" else court60_keepers(primary_doc)
    out[f"{project}.keeper-catalog"] = {"schemaVersion": "jovra.keeper-catalog/1", "projectId": PROJECT_ID[project],
                                        "revision": 1, "sample": True, "eventRevision": 1, "syncRevision": 1,
                                        "keepers": keepers}
    out[f"{project}.broll-catalog"] = broll_catalog(project)
    out[f"{project}.reference-catalog"] = reference_catalog(project, keepers, fold, CUE_KEEPER)
    return out


def all_records(media: dict) -> dict:
    out = {}
    for project in SOURCES:
        out.update(project_records(project, media))
    return out


def roles(recs: dict, project: str) -> dict:
    return {"manifest": recs[f"{project}.source-manifest"], "syncMap": recs[f"{project}.sync-map"],
            "keepers": recs[f"{project}.keeper-catalog"], "brolls": recs[f"{project}.broll-catalog"],
            "references": recs[f"{project}.reference-catalog"]}


# ----- the compile contexts -----------------------------------------------------------------------------------------

def compile_context(recs: dict, project: str) -> dict:
    """The planning context plus the trusted EDL context (bundle.edl_context over this project's records), the media
    index, stage S1 and a renderer that supports every SD6b operation; cases patch stage and renderer."""
    b = roles(recs, project)
    manifest, cat, brolls, refs = b["manifest"], b["keepers"], b["brolls"], b["references"]
    primary = next(s for s in manifest["sources"] if s["isPrimary"])
    keepers = []
    for n, k in enumerate(cat["keepers"]):
        keepers.append({"keeperId": k["keeperId"], "origin": "point", "eventRefs": list(k["eventRefs"]),
                        "session": dict(k["session"]), "slots": ["near-baseline"], "selection": k["selection"],
                        "provenance": k["provenance"], "markIds": [], "lessonClipIds": [],
                        "facts": {"index": n, "rallyLength": len(k["contacts"]), "rallyReal": False,
                                  "breakPoint": False, "setPoint": False, "matchPoint": False,
                                  "provenance": k["provenance"]}})
    fps = {s["sourceId"]: s["proxies"][0]["fps"] for s in manifest["sources"]}
    planning_brolls = [{"brollId": i["brollId"], "chapter": BROLL_CHAPTER[i["brollId"]],
                        "durationMs": (i["window"]["outFrame"] - i["window"]["inFrame"]) * 1000
                        * fps[i["sourceId"]]["den"] // fps[i["sourceId"]]["num"],
                        "depictsThisMatch": i["depictsThisMatch"], "revealsLocation": i["revealsLocation"]}
                       for i in brolls["items"]]
    ids = {r["refId"] for r in refs["references"]}
    return _plain({
        "projectId": manifest["projectId"], "sample": True,
        "bindings": {"eventRevision": cat["eventRevision"], "syncRevision": b["syncMap"]["revision"],
                     "keeperCatalogRevision": cat["revision"], "brollCatalogRevision": brolls["revision"]},
        "coverageSeconds": primary["original"]["durationUs"] // US,
        "primaryHasAudio": primary["original"]["audio"] is not None, "juniorMode": False,
        "pointCoverageComplete": True, "keepers": keepers, "brolls": planning_brolls,
        "references": [{"refId": r["refId"], "kind": r["kind"], "provenance": r["provenance"]}
                       for r in refs["references"]],
        "notes": [{"noteId": n, "use": u, "date": None} for n, u in NOTE_USES.items() if n in ids],
        "lessons": [],
        "cues": [{"cueId": "cue-01", "keeperId": CUE_KEEPER, "provenance": "reviewed"}] if "cue-01" in ids else [],
        "annotations": [{"refId": "ann-01", "keeperId": CUE_KEEPER}] if "ann-01" in ids else [],
        "progress": None, "rights": [], "consents": [],
        "edl": bundle.edl_context(b),
        "media": {"primarySourceId": primary["sourceId"], "slots": {"near-baseline": primary["sourceId"]},
                  "views": {k["keeperId"]: [{"sourceId": v["sourceId"], "window": dict(v["window"])}
                                            for v in k["views"]] for k in cat["keepers"]},
                  "brolls": {i["brollId"]: {"sourceId": i["sourceId"], "window": dict(i["window"])}
                             for i in brolls["items"]}},
        "stage": "S1", "renderer": {"supportedOps": list(compiler.OPS)},
    })


def _plain(value):
    if isinstance(value, dict):
        return {k: _plain(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(v) for v in value]
    return value


def barcode_table(project: str) -> dict:
    out = {}
    for sid, rel, _, _ in SOURCES[project]:
        b = s08(rel)["barcode"]
        out[sid] = {"barcodeSourceId": b["sourceId"],
                    "runs": [{"frame": r["frame"], "segment": b["segment"], "frameId": r["frameId"],
                              "count": r["count"]} for r in b["frameMap"]]}
    return out


def click_table(project: str) -> dict:
    return {sid: [e["sample"] for e in s08(rel)["clicks"]["events"]] for sid, rel, _, _ in SOURCES[project]
            if s08(rel)["clicks"] is not None}


def fold_table(recs: dict) -> list:
    """The point-event fold of every kept point of the match: what a score overlay over that point derives (S42)."""
    fold = point_fold(s08(SOURCES["court-match"][0][1]))
    out = []
    for k in recs["court-match.keeper-catalog"]["keepers"]:
        n = int(k["eventRefs"][0][2:])
        out.append(dict({"refId": k["eventRefs"][0], "pointNumber": n, "session": dict(k["session"])}, **fold[n]))
    return out


# ----- plans ----------------------------------------------------------------------------------------------------

def beat(bid, role, treatment, keeper=None, broll=None, den=None, overlays=(), note=None, template=None, why=""):
    return {"beatId": bid, "role": role, "treatment": treatment, "keeperId": keeper, "brollId": broll,
            "angle": "near-baseline" if keeper else None, "replaySpeedDen": den,
            "overlays": [{"kind": k, "refId": r} for k, r in overlays], "noteId": note, "templateId": template,
            "reasonForReview": why or f"{role} for the barcode-court vectors"}


def story(project: str, brief: str, profile: str, seconds: int, aspect: str, beats: list, audience="self") -> dict:
    return {"schemaVersion": "jovra.story-brief/1", "briefId": brief, "projectId": PROJECT_ID[project], "revision": 1,
            "sample": True, "profile": {"id": profile, "revision": 1},
            "bindings": {"eventRevision": 1, "syncRevision": 1, "keeperCatalogRevision": 1,
                         "brollCatalogRevision": 1},
            "planner": {"kind": "user", "modelId": None, "adapterVersion": "jovra-planner@0.1.0"},
            "feelingKey": "feeling.barcode-court", "audience": audience, "durationTargetSeconds": seconds,
            "aspect": aspect, "primaryAudioPolicy": "continuous-primary-court-audio", "effectIntensity": "low",
            "cleanAlternate": True, "privacy": {"venueVisible": False, "faces": "show"}, "music": None,
            "narration": None, "beats": beats, "comparisons": [], "omitted": [], "unresolved": []}


def rally60_plan(aspect: str) -> dict:
    beats = [beat("b01", "opening", "live", "k-01"), beat("b02", "opening", "replay", "k-01", den=2),
             beat("b03", "key-exchange", "live", "k-02"), beat("b04", "key-exchange", "replay", "k-02", den=2),
             beat("b05", "payoff", "live", "k-03"), beat("b06", "payoff", "replay", "k-03", den=2),
             beat("b07", "close", "title-card", template="card.accent")]
    return story("court-60", "brief-rally-60-" + aspect.replace(":", "x"), "rally-pulse", 31, aspect, beats)


def _live(n, k, role, overlays=()):
    return beat(f"b{n:02d}", role, "live", k, overlays=overlays)


def coach_plan(keepers: list) -> dict:
    """Goal, eight examples of the longest rallies (one with the cue, metric and annotation and a pause on it, one
    1/2x replay the 30 fps camera cannot make cleanly), then the drill and the next checkpoint."""
    ids = [k["keeperId"] for k in keepers]
    examples = [k for k in ("k-029", "k-039", "k-091", "k-005", "k-041", "k-032", "k-090", "k-028",
                            "k-008", "k-114", "k-089", "k-111", "k-014", "k-070", "k-016", "k-021") if k in ids]
    beats = [beat("b01", "goal", "title-card", note="note-goal", template="card.goal")]
    n = 2
    for i, k in enumerate(examples):
        score = ("score", "p-" + k[2:])
        if i == 0:
            beats.append(_live(n, k, "example", [score, ("metric", "stat-first-serve-in"), ("cue", "cue-01")]))
            beats.append(beat(f"b{n + 1:02d}", "cue", "freeze", k, overlays=[score, ("cue", "cue-01"),
                                                                              ("annotation", "ann-01")]))
            beats.append(beat(f"b{n + 2:02d}", "replay", "replay", k, den=2))
            n += 3
        else:
            beats.append(_live(n, k, "example", [score]))
            n += 1
    beats.append(beat(f"b{n:02d}", "drill", "title-card", note="note-drill", template="card.drill"))
    beats.append(beat(f"b{n + 1:02d}", "checkpoint", "title-card", note="note-next", template="card.next-checkpoint"))
    return story("court-match", "brief-coach-court", "coach-cut", 240, "16:9", beats, audience="coach")


def broadcast_plan(keepers: list) -> dict:
    beats = [beat("b01", "intro", "title-card", note="note-players", template="card.match-intro")]
    for n, k in enumerate(keepers, start=2):
        beats.append(_live(n, k["keeperId"], "point", [("score", k["eventRefs"][0])]))
    beats.append(beat(f"b{len(keepers) + 2:02d}", "final-score", "title-card", template="card.final-score"))
    return story("court-match", "brief-broadcast-court", "match-broadcast", 460, "16:9", beats, audience="family")


def memories_plan() -> dict:
    moments = ["k-005", "k-008", "k-014", "k-016", "k-021", "k-028", "k-029", "k-032", "k-039"]
    beats = [beat("b01", "arrival", "broll", broll="b-push", overlays=[("note", "note-caption")]),
             beat("b02", "arrival", "title-card", template="card.date")]
    n = 3
    for k in moments:
        role = "highlight" if k == "k-029" else "match-moment"
        overlays = [("score", "p-" + k[2:])] if k == "k-029" else []
        beats.append(_live(n, k, role, overlays))
        n += 1
    beats += [beat(f"b{n:02d}", "after", "broll", broll="b-drop"), beat(f"b{n + 1:02d}", "after", "broll",
                                                                          broll="b-pan"),
              beat(f"b{n + 2:02d}", "dedication", "title-card", note="note-dedication", template="card.dedication")]
    return story("court-match", "brief-memories-court", "court-memories", 150, "16:9", beats, audience="family")


# ----- cases --------------------------------------------------------------------------------------------------------

S41_OPS = ["live", "broll", "replay", "transition", "primary-bed", "hold-bed", "silence"]


def _req(transitions: dict | None = None, **extra) -> dict:
    out = {"fps": FPS30}
    if transitions:
        out["transitions"] = transitions
    out.update(extra)
    return out


DISSOLVE6, DIP6 = {"type": "dissolve", "frames": 6}, {"type": "dip", "frames": 6}
RALLY_TRANSITIONS = {"b03": DISSOLVE6, "b04": DISSOLVE6, "b05": DIP6}


def case_specs(recs: dict) -> list:
    """(id, why, context, contextPatch, plan, request, assert)."""
    keepers = recs["court-match.keeper-catalog"]["keepers"]
    s41 = [{"op": "replace", "path": "/renderer/supportedOps", "value": S41_OPS}]
    return [
        ("rally-60-portrait", "Rally Pulse from the 60 fps barcode source at 30 fps output, 9:16 letterboxed: every "
         "kept moment live at 1x (every other 60 fps frame) and again as a labelled 1/2x replay of every 60 fps frame; "
         "two dissolves and a dip to forest; the accent card closes it", CONTEXT_ID["court-60"], [],
         rally60_plan("9:16"), _req(RALLY_TRANSITIONS), RALLY60_ASSERT),
        ("rally-60-s41", "The same film for a renderer that can only do live, B-roll, replay, transitions and the bed "
         "(S41): the accent card is listed (notInThisBuild) and 30 s of real material remain, at 1280x720",
         CONTEXT_ID["court-60"], s41, rally60_plan("16:9"), _req(RALLY_TRANSITIONS), RALLY60_S41_ASSERT),
        ("coach-court", "Coach's Cut over the match: goal card, sixteen examples with their score bug, the cue, the "
         "metric and the annotation on the longest rally and a pause on it, its 1/2x replay omitted (a 30 fps camera "
         "has no frames for it at 30 fps), dissolves, and the drill and next-checkpoint cards over held court sound",
         CONTEXT_ID["court-match"], [], coach_plan(keepers),
         _req({"b03": {"type": "dissolve", "frames": 12}, "b06": {"type": "dissolve", "frames": 12}}), COACH_ASSERT),
        ("memories-court", "Court Memories over the match and its B-roll: B-roll (silent at S1) with a caption, the "
         "date card, nine moments, two dips to forest and a dissolve, the dedication card; the warm grade is S2",
         CONTEXT_ID["court-match"], [], memories_plan(),
         _req({"b03": {"type": "dip", "frames": 15}, "b12": {"type": "dissolve", "frames": 15},
               "b14": {"type": "dip", "frames": 15}}), MEMORIES_ASSERT),
        ("broadcast-court", "Match Broadcast of every kept point in order, each with its score bug, between the "
         "players card and the final score card (point coverage is complete and the camera never restarted)",
         CONTEXT_ID["court-match"], [], broadcast_plan(keepers), _req({"b03": {"type": "dissolve", "frames": 8}}),
         BROADCAST_ASSERT),
        ("contact-blend-refused", "With a stored contact at bc-060 frame 238, two frames before k-02, the dissolve "
         "out of k-01's replay would blend it: a typed rejection, never a silent cut", CONTEXT_ID["court-60"],
         [{"op": "replace", "path": "/edl/contacts/bc-060", "value": [18, 60, 102, 194, 238, 285, 376, 517, 566]}],
         rally60_plan("9:16"), _req(RALLY_TRANSITIONS), {"rejectCode": "contactProtected"}),
    ]


# Hand-derived from the keeper windows above (court-60): live at 1x of 60 fps is k = 2 source frames per output frame,
# so k-01 240 -> 120, k-02 206 -> 103, k-03 154 -> 77 output frames; a 1/2x replay is k = 1 over the whole window
# (min(window, 8 s = 240)): 240, 206, 154; the accent card holds 1.5 s = 45. 300 + 600 + 45 = 945 frames = 31.5 s.
RALLY60_SEGMENTS = ["live bc-060 0-240 0-120", "replay bc-060 0-240 1/2 120-360", "live bc-060 240-446 360-463",
                    "replay bc-060 240-446 1/2 463-669", "live bc-060 446-600 669-746",
                    "replay bc-060 446-600 1/2 746-900", "title-card card.accent 900-945"]
RALLY60_ASSERT = {
    "segments": RALLY60_SEGMENTS, "totalFrames": 945, "size": [720, 1280], "framing": "letterbox",
    "transitions": ["s03 dissolve 6", "s04 dissolve 6", "s05 dip 6"],
    # a 6-frame transition at boundary b: frames b-3..b-1 already show the incoming side, b..b+2 still the outgoing
    "probes": {"0": ["source", [3, 0, 0]], "119": ["source", [3, 0, 238]], "120": ["source", [3, 0, 0]],
               "356": ["source", [3, 0, 236]], "357": ["dissolve", [3, 0, 237], [3, 0, 234]],
               "362": ["dissolve", [3, 0, 242], [3, 0, 244]], "363": ["source", [3, 0, 246]],
               "666": ["dip-out", [3, 0, 443]], "669": ["dip-in", [3, 0, 446]], "671": ["dip-in", [3, 0, 450]],
               "672": ["source", [3, 0, 452]], "900": ["card", "card.accent"]},
    "omitted": [], "cleanAlternateTransitions": 0,
}
RALLY60_S41_ASSERT = {"segments": RALLY60_SEGMENTS[:-1], "totalFrames": 900, "size": [1280, 720], "framing": "fill",
                      "omitted": [["b07", "card", "notInThisBuild"]], "notInThisBuild": ["card"],
                      "transitions": ["s03 dissolve 6", "s04 dissolve 6", "s05 dip 6"]}
COACH_ASSERT = {"omitted": [["b04", "replay", "cleanFrame", "originalSpeedFallback"]], "freeze": "s03",
                "labels": ["label.paused"], "transitions": ["s03 dissolve 12", "s05 dissolve 12"],
                "overlayKinds": ["annotation", "cue", "metric", "score"]}
MEMORIES_ASSERT = {"omitted": [[None, "grade", "notInThisStage"]], "grade": "none",
                   "transitions": ["s03 dip 15", "s12 dissolve 15", "s14 dip 15"],
                   "brollSilent": True, "overlayKinds": ["note", "score"]}
BROADCAST_ASSERT = {"omitted": [], "transitions": ["s03 dissolve 8"], "firstLast": ["card.match-intro",
                                                                                   "card.final-score"]}


def compact_segment(s: dict) -> str:
    if s["op"] == "title-card":
        return f"title-card {s['templateId']} {s['outputInFrame']}-{s['outputOutFrame']}"
    out = f"{s['outputInFrame']}-{s['outputOutFrame']}"
    if s["op"] == "freeze":
        return f"freeze {s['sourceId']} @{s['sourceFrame']} {out}"
    speed = f" 1/{s['speed']['den']}" if s["op"] == "replay" else ""
    return f"{s['op']} {s['sourceId']} {s['sourceInFrame']}-{s['sourceOutFrame']}{speed} {out}"


def renderer_facts(doc: dict, project: str) -> dict:
    """What a renderer test compares, for one EDL."""
    runs = framemap.frame_map(doc, framemap.Barcodes(barcode_table(project)))
    return {"frameMap": runs, "frameMapSha256": framemap.frame_map_sha256(runs),
            "clickMap": framemap.click_map(doc, click_table(project)),
            "overlays": framemap.overlay_schedule(doc), "operations": sorted(framemap.operations(doc))}


def run_case(profiles: dict, plan: dict, context: dict, request: dict, project: str) -> dict:
    got = compiler.run_vector(profiles, {"op": "compile", "input": {"plan": plan, "context": context,
                                                                     "request": request}})
    if "edl" not in got:
        return got
    out = dict(got, **renderer_facts(got["edl"], project))
    if got["validation"]["needsCleanAlternate"]:
        alt = edl.clean_alternate(got["edl"])
        out["cleanAlternate"] = dict({"edl": alt, "sha256": canonical_sha256(alt)}, **renderer_facts(alt, project))
    else:
        out["cleanAlternate"] = None
    return out


def build_vector(recs: dict, profiles: dict, media: list) -> dict:
    contexts = {CONTEXT_ID[p]: compile_context(recs, p) for p in SOURCES}
    cases = [{"id": "media", "why": "The S08 media every source binds, and what a render on the build machine "
                                    "measured (scripts/media/studio/barcode_court.py --measure)",
              "op": "media", "input": {"media": media}}]
    for project in SOURCES:
        cid = CONTEXT_ID[project]
        expect = {"context": contexts[cid], "barcodes": barcode_table(project), "clicks": click_table(project)}
        if project == "court-match":
            expect["pointFold"] = fold_table(recs)
        cases.append({"id": cid, "why": f"The {PROJECT_ID[project]} compile context (stage S1, every operation "
                                        "supported), from its records under records/barcode-court/",
                      "op": "context", "input": {"project": project}, "expect": expect,
                      "assert": CONTEXT_ASSERT[project]})
    for cid, why, base, patch, plan, request, hand in case_specs(recs):
        project = next(p for p, c in CONTEXT_ID.items() if c == base)
        context = apply_patch(contexts[base], patch) if patch else contexts[base]
        cases.append({"id": cid, "why": why, "op": "compile", "context": base, "contextPatch": patch,
                      "input": {"plan": plan, "request": request},
                      "expect": run_case(profiles, plan, context, request, project), "assert": hand})
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": KIND,
            "status": "Sample: compile.py (S07) over contexts built from the S08 media's records; frame, click and "
                      "overlay maps from framemap.py; media hashes measured on the build machine, regenerated at test "
                      "time",
            "cases": cases}


# Hand values: bc-060 is 600 frames of 1280x720 at 60 fps (10 s); the match 97200 frames of 640x360 at 30 fps
# (54:00); 37 points of the 124 last at least 10 s.
CONTEXT_ASSERT = {
    "court-60": {"primary": "bc-060", "fps": 60, "size": [1280, 720], "frames": 600, "keepers": 3, "brolls": 0,
                 "contacts": [18, 60, 102, 194, 285, 376, 517, 566]},
    "court-match": {"primary": "match", "fps": 30, "size": [640, 360], "frames": 97200, "keepers": 37, "brolls": 3},
}


def fixtures(sample) -> dict:
    media = media_entries()
    measured = {e["manifest"]: e["measured"] for e in media}
    recs = all_records(measured)
    out = {f"{RECORDS}/{name}.json": doc for name, doc in recs.items()}
    out[VECTOR] = build_vector(recs, sample.profiles, media)
    return out


# ----- checker ------------------------------------------------------------------------------------------------------

def _records_from_disk(ctx) -> dict:
    return {p.name[: -len(".json")]: json.loads(p.read_text(encoding="utf-8"))
            for p in sorted((FIX / RECORDS).glob("*.json"))}


def stale_problems(media: list) -> list:
    """The context is stale when any bound file was measured from another generator source than the S08 generator's
    code has now (a changed parameter), or was never measured."""
    out = []
    for e in media:
        now = live_source_hash(e["manifest"])
        m = e["measured"]
        if m is None or m["measuredWithSourceHash"] != now:
            was = "never" if m is None else m["measuredWithSourceHash"][:16]
            out.append(f"the barcode-court context is stale: {e['manifest']} was measured from generator source "
                       f"{was}, the S08 generator is now {now[:16]}; run scripts/media/studio/barcode_court.py "
                       "--measure")
        doc = s08(e["manifest"])
        if doc["barcode"]["frameMapSha256"] != e["frameMapSha256"]:
            out.append(f"{e['manifest']}: the S08 frame map changed under the context")
    return out


def _check_media(ctx, case, report, where) -> None:
    problems = stale_problems(case["input"]["media"])
    recs = _records_from_disk(ctx)
    for e in case["input"]["media"]:
        m = e["measured"]
        if m is None:
            continue
        src = next(s for s in recs[f"{e['project']}.source-manifest"]["sources"] if s["sourceId"] == e["sourceId"])
        table = recs[f"{e['project']}.pts-table.{e['sourceId']}"]
        if src["original"]["sha256"] != m["sha256"] or src["proxies"][0]["sha256"] != m["sha256"]:
            problems.append(f"{e['sourceId']}: the manifest does not bind the measured file sha256")
        if src["proxies"][0]["ptsTableSha256"] != normalization.table_sha256(table) \
                or table["original"]["pts"] != m["ptsTicks"]:
            problems.append(f"{e['sourceId']}: the PTS table is not the decoded index of the measured file")
    for p in problems:
        report.fail(where, p)
    if not problems:
        report.ok("barcode-court media bound to the current S08 generator", len(case["input"]["media"]))


def _check_context(ctx, case, report, where, contexts) -> None:
    project = case["input"]["project"]
    got = case["expect"]
    problems = []
    if got["context"] != contexts[case["id"]]:
        problems.append("the stored context is out of date with the records under records/barcode-court/")
    if got["barcodes"] != barcode_table(project) or got["clicks"] != click_table(project):
        problems.append("the barcode or click table differs from the S08 manifests")
    if project == "court-match" and got.get("pointFold") != fold_table(_records_from_disk(ctx)):
        problems.append("the point-event fold differs from the core fold of the match log")
    c = got["context"]
    prim = c["edl"]["sources"][c["media"]["primarySourceId"]]
    have = {"primary": c["media"]["primarySourceId"], "fps": prim["proxy"]["fps"]["num"],
            "size": [prim["proxy"]["width"], prim["proxy"]["height"]], "frames": prim["proxy"]["frameCount"],
            "keepers": len(c["keepers"]), "brolls": len(c["brolls"]),
            "contacts": c["edl"]["contacts"].get(c["media"]["primarySourceId"])}
    problems += [f"{k}: {have[k]!r}, hand value {v!r}" for k, v in case["assert"].items() if have[k] != v]
    for p in problems:
        report.fail(where, p)
    if not problems:
        report.ok("barcode-court vectors (context)")


def independent_frame(doc: dict, o: int, barcodes: dict):
    """Output frame `o`'s picture, worked frame by frame without framemap.py: the segment that holds it, and the
    transition window around a boundary (n frames; the incoming side shows from b - (n - n // 2))."""
    out_fps = Fraction(doc["output"]["fps"]["num"], doc["output"]["fps"]["den"])
    fps = {s["id"]: Fraction(s["proxy"]["fps"]["num"], s["proxy"]["fps"]["den"]) for s in doc["sources"]}

    def show(seg):
        if seg["op"] == "title-card":
            return ["card", seg["templateId"]]
        if seg["op"] == "freeze":
            frame = seg["sourceFrame"]
        else:
            per = fps[seg["sourceId"]] * seg["speed"]["num"] / seg["speed"]["den"] / out_fps
            frame = seg["sourceInFrame"] + int((o - seg["outputInFrame"]) * per // 1)
        b = barcodes[seg["sourceId"]]
        run = next(r for r in b["runs"] if r["frame"] <= frame < r["frame"] + r["count"])
        return [b["barcodeSourceId"], run["segment"], run["frameId"] + frame - run["frame"]]

    segs = doc["segments"]
    for j, seg in enumerate(segs):
        tr = seg["transitionIn"]
        b = seg["outputInFrame"]
        if tr["frames"] and b - (tr["frames"] - tr["frames"] // 2) <= o < b + tr["frames"] // 2:
            if tr["type"] == "dissolve":
                return ["dissolve", show(segs[j - 1]), show(seg)]
            return ["dip-out", show(segs[j - 1])] if o < b else ["dip-in", show(seg)]
    seg = next(s for s in segs if s["outputInFrame"] <= o < s["outputOutFrame"])
    pic = show(seg)
    return pic if pic[0] == "card" else ["source", pic]


def _entry_as_probe(entry: dict):
    def pic(e):
        return ["card", e["card"]] if "card" in e else e["barcode"]
    if entry["picture"] == "card":
        return ["card", entry["templateId"]]
    if entry["picture"] == "dissolve":
        return ["dissolve", pic(entry["from"]), pic(entry["to"])]
    return [entry["picture"], pic(entry)]


def frame_map_problems(doc: dict, facts: dict, barcodes: dict) -> list:
    """The stored frame map against the plan, frame by frame (an implementation that shares no code with framemap)."""
    frames = framemap.expand(facts["frameMap"])
    if len(frames) != doc["output"]["totalFrames"]:
        return [f"the frame map covers {len(frames)} frames, the plan {doc['output']['totalFrames']}"]
    for o, entry in enumerate(frames):
        want = independent_frame(doc, o, barcodes)
        got = _entry_as_probe(entry)
        got = ["card", got[1]] if got[0] == "card" else got
        if got != want:
            return [f"output frame {o}: the frame map says {got}, the plan shows {want}"]
    if facts["frameMapSha256"] != canonical_sha256(facts["frameMap"]):
        return ["frameMapSha256 is not the hash of the frame map"]
    return []


def _hand_problems(got: dict, a: dict) -> list:
    doc = got["edl"]
    segs = doc["segments"]
    have = {"segments": [compact_segment(s) for s in segs], "totalFrames": doc["output"]["totalFrames"],
            "size": [doc["output"]["width"], doc["output"]["height"]],
            "framing": sorted({s["framing"]["mode"] for s in segs if "framing" in s}),
            "transitions": [f"{s['id']} {s['transitionIn']['type']} {s['transitionIn']['frames']}" for s in segs
                            if s["transitionIn"]["type"] != "cut"],
            "omitted": [[o["beatId"], o["op"], o["reason"]] + ([o["fallback"]] if "fallback" in o else [])
                        for o in got["omitted"]],
            "notInThisBuild": got["notInThisBuild"], "grade": doc["grade"]["presetId"],
            "labels": sorted({s["labelTemplateId"] for s in segs if s.get("labelTemplateId")}),
            "overlayKinds": sorted({r["kind"] for s in segs for r in s["overlayRefs"]}),
            "freeze": next((s["id"] for s in segs if s["op"] == "freeze"), None),
            "firstLast": [segs[0].get("templateId"), segs[-1].get("templateId")],
            "brollSilent": all(p["route"] == "silence" for s in segs if s["op"] == "broll" for p in doc["audio"]["bed"]
                               if p["outputInFrame"] < s["outputOutFrame"]
                               and s["outputInFrame"] < p["outputOutFrame"])}
    p = []
    for k, v in a.items():
        if k == "framing":
            if have["framing"] != [v]:
                p.append(f"framing {have['framing']}, hand value {v}")
        elif k == "probes":
            frames = framemap.expand(got["frameMap"])
            for o, want in v.items():
                entry = _entry_as_probe(frames[int(o)])
                if entry != want:
                    p.append(f"output frame {o}: {entry}, hand value {want}")
        elif k == "cleanAlternateTransitions":
            alt = got["cleanAlternate"]["edl"]
            n = sum(1 for s in alt["segments"] if s["transitionIn"]["type"] != "cut")
            if n != v:
                p.append(f"the clean alternate keeps {n} transitions")
        elif have[k] != v:
            p.append(f"{k}: {have[k]!r}, hand value {v!r}")
    return p


def _clean_alternate_problems(got: dict) -> list:
    alt = got["cleanAlternate"]
    if alt is None:
        return [] if not got["validation"]["needsCleanAlternate"] else ["a plan with motion has no clean alternate"]
    doc, a = got["edl"], alt["edl"]
    p = []
    if [(s["outputInFrame"], s["outputOutFrame"], s.get("sourceInFrame")) for s in a["segments"]] != \
            [(s["outputInFrame"], s["outputOutFrame"], s.get("sourceInFrame")) for s in doc["segments"]]:
        p.append("the clean alternate does not keep the same cuts")
    if not a["cleanAlternate"] or any(s["transitionIn"]["type"] != "cut" for s in a["segments"]):
        p.append("the clean alternate still has a dissolve or dip")
    return p


def _check_compile(ctx, case, report, where, contexts, profiles) -> None:
    project = next(p for p, c in CONTEXT_ID.items() if c == case["context"])
    context = apply_patch(contexts[case["context"]], case["contextPatch"]) if case["contextPatch"] \
        else copy.deepcopy(contexts[case["context"]])
    snapshot = copy.deepcopy(context)
    inp = case["input"]
    got = run_case(profiles, inp["plan"], context, inp["request"], project)
    if got != case["expect"]:
        report.fail(where, "reference output differs from the stored expectation")
        return
    if context != snapshot:
        report.fail(where, "the compiler changed its input")
        return
    a = case["assert"]
    if "rejectCode" in a:
        if got.get("rejectCode") == a["rejectCode"]:
            report.ok("barcode-court vectors (reject)")
        else:
            report.fail(where, f"expected {a['rejectCode']}, got {got}")
        return
    if "edl" not in got:
        report.fail(where, f"not compiled: {got}")
        return
    errors = ctx.schemas.validate(inp["plan"], ctx.schema_for("jovra.story-brief/1"))
    problems = [f"plan schema: {e}" for e in errors[:3]]
    barcodes = barcode_table(project)
    docs = [("", got["edl"], got)] + ([("clean alternate: ", got["cleanAlternate"]["edl"], got["cleanAlternate"])]
                                      if got["cleanAlternate"] else [])
    for label, doc, facts in docs:
        try:
            edl.validate(doc, profiles, context["edl"])
        except Reject as exc:
            problems.append(f"{label}edl.validate rejects the compiled plan: {exc}")
        problems += [f"{label}schema: {e}" for e in ctx.schemas.validate(doc, ctx.schema_for(doc["schemaVersion"]))[:3]]
        problems += [label + x for x in frame_map_problems(doc, facts, barcodes)]
    problems += _clean_alternate_problems(got)
    problems += _hand_problems(got, a)
    again = compiler.run_vector(profiles, {"op": "compile", "input": {"plan": copy.deepcopy(inp["plan"]),
                                                                       "context": snapshot,
                                                                       "request": copy.deepcopy(inp["request"])}})
    if canonical_bytes(again["edl"]) != canonical_bytes(got["edl"]):
        problems.append("compiling the same plan twice gave different canonical JSON")
    for p in problems:
        report.fail(where, p)
    if not problems:
        report.ok("barcode-court vectors (compiled, validated, frame map consistent)")
        report.ok("barcode-court frame maps checked frame by frame", len(docs))


def _contexts(ctx) -> dict:
    recs = _records_from_disk(ctx)
    return {CONTEXT_ID[p]: compile_context(recs, p) for p in SOURCES}


def check_vector(ctx, case, report, where) -> None:
    if case["op"] == "media":
        _check_media(ctx, case, report, where)
    elif case["op"] == "context":
        _check_context(ctx, case, report, where, _contexts(ctx))
    elif case["op"] == "compile":
        _check_compile(ctx, case, report, where, _contexts(ctx), ctx.profiles)
    else:
        report.fail(where, f"unknown op {case['op']!r}")


VECTOR_CHECKERS = {KIND: check_vector}


# ----- self-tests ---------------------------------------------------------------------------------------------------

# What the coverage table requires beyond the stage allowlist (compile.S1_OPS): the features the ticket names.
REQUIRED_FEATURES = ["transition.cut", "transition.dissolve", "transition.dip", "card.title", "overlay.score",
                     "overlay.metric", "overlay.cue", "overlay.annotation", "overlay.provenance-chip", "label.replay",
                     "label.paused", "badge.sample", "replay.1/2-from-60fps-at-30fps", "output.9:16",
                     "framing.letterbox", "output.16:9", "clean-alternate"]
# Named by the ticket, not reachable over the S08 media yet (the module page says why).
NOT_COVERED = {"card.recording-gap": "no restarted S08 source can be offered (bundle.trusted_sources) and the 10 s "
                                     "restart could not fill Match Broadcast's 5 minutes"}


def coverage(cases: list) -> dict:
    """feature -> ids of the compiled vectors (or their clean alternates) that exercise it."""
    table: dict = {}
    for c in cases:
        if c["op"] != "compile" or "edl" not in c["expect"]:
            continue
        ops = set(c["expect"]["operations"])
        if c["expect"]["cleanAlternate"]:
            ops |= set(c["expect"]["cleanAlternate"]["operations"])
        for op in ops:
            table.setdefault(op, []).append(c["id"])
    return table


def check_coverage(ctx, report) -> None:
    """Every operation of the S1 allowlist, and every feature the ticket names, appears in at least one compiled
    barcode-court vector; the table (operation: vector ids) is printed as the count labels."""
    table = coverage(ctx.fixture(VECTOR)["cases"])
    missing = [op for op in list(compiler.S1_OPS) + REQUIRED_FEATURES if op not in table]
    for op in missing:
        report.fail("barcode-court coverage", f"{op} appears in no barcode-court compile vector")
    for op in list(compiler.S1_OPS) + REQUIRED_FEATURES:
        if op in table:
            report.ok(f"coverage  {op:<32} {', '.join(table[op])}")
    for op, why in NOT_COVERED.items():
        if op in table:
            report.fail("barcode-court coverage", f"{op} is covered now: remove it from NOT_COVERED")
        else:
            report.ok(f"coverage  {op:<32} NOT COVERED (barcode-court.md)")


def check_records(ctx, report) -> None:
    """The records under records/barcode-court/ pass their schemas, their reference rules and the cross-record rules
    the sample-court-day project passes (sync against manifest, catalogs inside their sources)."""
    recs = _records_from_disk(ctx)
    problems = []
    for name, doc in recs.items():
        errors = ctx.schemas.validate(doc, ctx.schema_for(doc["schemaVersion"]))
        if errors:
            problems.append(f"{name}: schema: {'; '.join(errors[:3])}")
            continue
        try:
            ctx.semantic(doc)
        except Reject as exc:
            problems.append(f"{name}: reference: {exc}")
    for project in SOURCES:
        b = roles(recs, project)
        try:
            bundle.check_sync_against_manifest(b)
            bundle.check_catalogs(b)
            records.check_sync_map(b["syncMap"], bundle.capture_hints(b["manifest"], b["syncMap"]))
        except Reject as exc:
            problems.append(f"{project}: cross-record: {exc}")
        offered = set(bundle.edl_context(b)["sources"])
        if offered != {s[0] for s in SOURCES[project]}:
            problems.append(f"{project}: bundle offers {sorted(offered)} for cutting")
    for p in problems:
        report.fail("barcode-court records", p)
    if not problems:
        report.ok("barcode-court records valid (schema, reference, cross-record)", len(recs))


def check_mutations(ctx, report) -> None:
    """The maps are checked, not trusted: a frame map, a clean alternate or a measurement that drifts is caught."""
    cases = {c["id"]: c for c in ctx.fixture(VECTOR)["cases"]}
    rally = cases["rally-60-portrait"]["expect"]
    barcodes = barcode_table("court-60")
    caught, tries = 0, 0
    doc = rally["edl"]
    for name, mutate in (("shift", lambda d: apply_patch(d, [{"op": "replace", "path": "/segments/1/sourceInFrame",
                                                              "value": 1}])),
                         ("cut-for-dip", lambda d: apply_patch(d, [{"op": "replace", "path": "/segments/4/transitionIn",
                                                                    "value": {"type": "cut", "frames": 0}}]))):
        tries += 1
        if frame_map_problems(mutate(doc), rally, barcodes):
            caught += 1
        else:
            report.fail("barcode-court mutations", f"{name}: the frame map still matches a mutated plan")
    media = copy.deepcopy(cases["media"]["input"]["media"])
    media[0]["measured"] = dict(media[0]["measured"] or {}, measuredWithSourceHash="f" * 64)
    tries += 1
    if stale_problems(media):
        caught += 1
    else:
        report.fail("barcode-court mutations", "a measurement from another generator source is not reported stale")
    if caught == tries:
        report.ok("barcode-court mutations caught", caught)


def check_media_files(ctx, report) -> None:
    """With JOVRA_STUDIO_MEDIA=1: regenerate the bound files into the cache with the S08 generator and compare their
    SHA-256, size and decoded PTS index with the context (scripts/media/studio/barcode_court.py --check)."""
    entries = ctx.fixture(VECTOR)["cases"][0]["input"]["media"]
    if os.environ.get(MEDIA_ENV) != "1":
        report.ok(f"barcode-court media files NOT regenerated (set {MEDIA_ENV}=1 to compare bytes)")
        return
    import barcode_court   # scripts/media/studio, on sys.path through media_fixtures_cases
    problems = barcode_court.compare(entries, ROOT / ".cache" / "media" / "studio")
    for p in problems:
        report.fail("barcode-court media", p)
    if not problems:
        report.ok("barcode-court media files regenerated and byte-identical to the context", len(entries))


SELF_TESTS = {"barcode-court-coverage": check_coverage, "barcode-court-records": check_records,
              "barcode-court-mutations": check_mutations, "barcode-court-media": check_media_files}
