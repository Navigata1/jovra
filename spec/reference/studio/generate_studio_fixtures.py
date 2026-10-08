#!/usr/bin/env python3
"""Write spec/studio/fixtures and spec/studio/contracts/story-profiles.v1.json deterministically.

Same bytes on every run. Everything written is fictional Sample data (implementation-states.md). Expected
values in vectors come from the reference; each vector also carries hand-derived assertions that do not, and
scripts/spec/validate_studio.py checks both.  Usage:  python3 spec/reference/studio/generate_studio_fixtures.py
"""

from __future__ import annotations

import hashlib
import json
import sys
from fractions import Fraction
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from studio import edl, syncfit  # noqa: E402
from studio.core import frame_at_us, round_half_up  # noqa: E402

ROOT = HERE.parents[2]
OUT = ROOT / "spec" / "studio" / "fixtures"
CONTRACTS = ROOT / "spec" / "studio" / "contracts"
MODULES = ROOT / "spec" / "studio" / "modules"
MODULE_INDEX = MODULES / "README.md"
DESIGN_PROFILES = ROOT / "design-reference" / "studio" / "brief" / "story-profiles.json"

PROJECT = "sample-court-day"
FPS60 = {"num": 60, "den": 1}
FPS30 = {"num": 30, "den": 1}
RATE1 = {"num": 1_000_000_000, "den": 1_000_000_000}
HOUR_US = 3_600_000_000
EVENT_REVISION = 3
SYNC_REVISION = 2
MANIFEST_REVISION = 1
KEEPER_REVISION = 1
BROLL_REVISION = 1

# Court geometry in mm (ITF; club fence run-back 5.48 m, side run 3.05 m), phones at 1.5 m, hits at 1.0 m.
POS = {
    "BS": {"xMm": 0, "yMm": -17365, "zMm": 1500},
    "BN": {"xMm": 0, "yMm": 17365, "zMm": 1500},
    "CSW": {"xMm": -8535, "yMm": -17365, "zMm": 1500},
    "CSE": {"xMm": 8535, "yMm": -17365, "zMm": 1500},
    "CNW": {"xMm": -8535, "yMm": 17365, "zMm": 1500},
    "CNE": {"xMm": 8535, "yMm": 17365, "zMm": 1500},
}
SOUTH_BASELINE = {"xMm": 0, "yMm": -11885, "zMm": 1000}
NORTH_BASELINE = {"xMm": 0, "yMm": 11885, "zMm": 1000}
NET_CENTRE = {"xMm": 0, "yMm": 0, "zMm": 1000}


def fake_sha(label: str) -> str:
    """Deterministic stand-in hashes for fictional files (Sample: no real media exists)."""
    return hashlib.sha256(("jovra-sample:" + label).encode()).hexdigest()


def dump(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# ----- story profiles -----------------------------------------------------------------------------

EXPORT_AUDIO_ON = ("rally-pulse", "court-memories")   # spec D-1: Include audio starts on only for these

GRAMMAR = {
    "coach-cut": {
        "chronology": "free", "ops": ["live", "replay", "freeze", "title-card"], "replaySpeedDens": [2, 4],
        "transitions": ["dissolve"], "maxTransitionMs": 400, "freezeMs": {"min": 500, "max": 3000},
        "cardMs": {"min": 1000, "max": 6000}, "replayMaxMs": 8000, "reframe": "if-box-fits", "gradePresets": ["none"],
        "narration": True, "music": False,
        "overlays": {"score": ["manual", "reviewed", "validated"], "metric": ["manual", "estimated", "reviewed", "validated"],
                     "note": ["manual", "reviewed"], "cue": ["manual", "reviewed", "validated"],
                     "annotation": ["manual", "reviewed"]}},
    "match-broadcast": {
        "chronology": "strict", "ops": ["live", "replay", "title-card"], "replaySpeedDens": [2],
        "transitions": ["dissolve"], "maxTransitionMs": 267, "freezeMs": {"min": 500, "max": 4000},
        "cardMs": {"min": 1000, "max": 5000}, "replayMaxMs": 8000, "reframe": "letterbox-only", "gradePresets": ["none"],
        "narration": False, "music": False,
        "overlays": {"score": ["manual", "reviewed", "validated"], "note": ["manual", "reviewed"]}},
    "rally-pulse": {
        "chronology": "free", "ops": ["live", "replay", "title-card"], "replaySpeedDens": [2, 4],
        "transitions": ["dissolve", "dip"], "maxTransitionMs": 200, "freezeMs": {"min": 500, "max": 4000},
        "cardMs": {"min": 1000, "max": 1500}, "replayMaxMs": 8000, "reframe": "if-box-fits",
        "gradePresets": ["none", "warm-court-1"], "narration": False, "music": True,
        "overlays": {"score": ["manual", "reviewed", "validated"], "metric": ["reviewed", "validated"]}},
    "progress-story": {
        "chronology": "free", "ops": ["live", "replay", "freeze", "title-card"], "replaySpeedDens": [2, 4],
        "transitions": ["dissolve"], "maxTransitionMs": 400, "freezeMs": {"min": 500, "max": 4000},
        "cardMs": {"min": 1000, "max": 6000}, "replayMaxMs": 8000, "reframe": "if-box-fits", "gradePresets": ["none"],
        "narration": True, "music": True,
        "overlays": {"metric": ["reviewed", "validated"], "note": ["manual", "reviewed"],
                     "cue": ["manual", "reviewed", "validated"]}},
    "court-memories": {
        "chronology": "free", "ops": ["live", "broll", "title-card"], "replaySpeedDens": [],
        "transitions": ["dissolve", "dip"], "maxTransitionMs": 500, "freezeMs": {"min": 500, "max": 4000},
        "cardMs": {"min": 1000, "max": 6000}, "replayMaxMs": 0, "reframe": "if-box-fits",
        "gradePresets": ["none", "warm-court-1"], "narration": True, "music": True,
        "overlays": {"score": ["manual", "reviewed", "validated"], "note": ["manual", "reviewed"]}},
}


def profile_catalog() -> dict:
    src = json.loads(DESIGN_PROFILES.read_text(encoding="utf-8"))
    profiles = []
    for p in src["profiles"]:
        lo, hi = p["recommendedDurationSeconds"]
        grammar = {"durationSeconds": {"min": lo, "max": hi}}
        grammar.update(GRAMMAR[p["id"]])
        # D-1 / SD5: exported files default to no audio, except Rally Pulse and Court Memories (switch always shown)
        export_audio = {"includeByDefault": p["id"] in EXPORT_AUDIO_ON, "switchShown": True,
                        "juniorMode": "no-audio-no-switch"}
        profiles.append(dict(p, revision=1, grammar=grammar, exportAudio=export_audio))
        profiles[-1] = {k: profiles[-1][k] for k in ("id", "revision", "name", "intent", "recommendedDurationSeconds",
                                                     "beats", "editing", "mustNot", "fallback", "exportAudio",
                                                     "grammar")}
    return {
        "schemaVersion": "jovra.story-profile-catalog/1",
        "derivedFrom": "design-reference/studio/brief/story-profiles.json#jovra.story-profiles/1",
        "status": "design specification with proposed grammar defaults (film-engine research section 6, INFERRED); "
                  "tune on real footage. Not an implemented renderer.",
        "defaults": src["defaults"],
        "profiles": profiles,
    }


# ----- source manifest ----------------------------------------------------------------------------

def match_source(sid, slot, primary, label, *, vfr=False, rotation=0, hdr=False, audio=True):
    frames = 216000  # 60 min at 60 fps
    colour = ({"primaries": "bt2020", "transfer": "hlg", "matrix": "bt2020nc", "range": "limited", "bitDepth": 10,
               "hdr": True} if hdr else
              {"primaries": "bt709", "transfer": "bt709", "matrix": "bt709", "range": "limited", "bitDepth": 8,
               "hdr": False})
    w, h = (1920, 1080)
    pw, ph = (h, w) if rotation in (90, 270) else (w, h)
    return {
        "sourceId": sid, "role": "match", "slot": slot, "isPrimary": primary, "deviceLabel": label,
        "original": {
            "sha256": fake_sha(sid + ":original"), "sizeBytes": 3_600_000_000, "container": "mov",
            "durationUs": HOUR_US, "timescale": 600, "startPts": {"value": 0, "timescale": 600}, "frameCount": frames,
            "nominalFps": FPS60, "vfr": vfr,
            "video": {"codec": "hevc", "width": w, "height": h, "rotationDegrees": rotation,
                      "pixelAspect": {"num": 1, "den": 1}},
            "colour": colour,
            "audio": {"codec": "aac", "sampleRate": 48000, "channels": 1} if audio else None,
        },
        "lens": {"kind": "wide", "zoomFactor": "1.0"},
        "captureHints": {"wallClockStart": "2026-10-07T21:00:00Z", "wallClockSource": "room-ntp",
                         "roomOffsetUs": 0 if primary else 4200, "roomRoundTripUs": None if primary else 9800},
        "segments": [{"segmentId": "seg-0", "index": 0, "reason": "start", "fileZeroHostNs": 1_000_000_000,
                      "startPts": {"value": 0, "timescale": 600}, "durationUs": HOUR_US, "frameCount": frames}],
        "proxies": [{"class": "render", "sha256": fake_sha(sid + ":render-proxy"), "fps": FPS60, "width": pw,
                     "height": ph, "frameCount": frames, "ptsTableSha256": fake_sha(sid + ":pts-table"),
                     "normalizerVersion": "jovra-normalize@0.1.0", "rotationApplied": rotation != 0,
                     "toneMapped": hdr}],
        "verification": {"status": "verified", "method": "sha256-full-read-device", "verifiedAt": "2026-10-07T22:10:00Z"},
    }


def broll_source(sid, seconds, label):
    frames = seconds * 30
    return {
        "sourceId": sid, "role": "broll", "slot": None, "isPrimary": False, "deviceLabel": label,
        "original": {
            "sha256": fake_sha(sid + ":original"), "sizeBytes": seconds * 1_000_000, "container": "mov",
            "durationUs": seconds * 1_000_000, "timescale": 600, "startPts": {"value": 0, "timescale": 600},
            "frameCount": frames, "nominalFps": FPS30, "vfr": False,
            "video": {"codec": "hevc", "width": 1920, "height": 1080, "rotationDegrees": 0,
                      "pixelAspect": {"num": 1, "den": 1}},
            "colour": {"primaries": "bt709", "transfer": "bt709", "matrix": "bt709", "range": "limited",
                       "bitDepth": 8, "hdr": False},
            "audio": {"codec": "aac", "sampleRate": 48000, "channels": 1},
        },
        "lens": {"kind": "wide", "zoomFactor": None},
        "captureHints": {"wallClockStart": None, "wallClockSource": "device", "roomOffsetUs": None,
                         "roomRoundTripUs": None},
        "segments": [{"segmentId": "seg-0", "index": 0, "reason": "start", "fileZeroHostNs": None,
                      "startPts": {"value": 0, "timescale": 600}, "durationUs": seconds * 1_000_000,
                      "frameCount": frames}],
        "proxies": [{"class": "render", "sha256": fake_sha(sid + ":render-proxy"), "fps": FPS30, "width": 1920,
                     "height": 1080, "frameCount": frames, "ptsTableSha256": fake_sha(sid + ":pts-table"),
                     "normalizerVersion": "jovra-normalize@0.1.0", "rotationApplied": False, "toneMapped": False}],
        "verification": {"status": "verified", "method": "sha256-full-read-device", "verifiedAt": "2026-10-07T22:10:00Z"},
    }


def source_manifest() -> dict:
    return {
        "schemaVersion": "jovra.source-manifest/1", "projectId": PROJECT, "revision": MANIFEST_REVISION,
        "sample": True, "createdAt": "2026-10-07T22:00:00Z",
        "sources": [
            match_source("camera-1", "near-baseline", True, "Jon's iPhone"),
            match_source("camera-2", "far-baseline", False, "Alex's phone", vfr=True),
            match_source("camera-3", "near-left-corner", False, "Corner left", rotation=90, hdr=True),
            broll_source("broll-1", 60, "Arrival"),
            broll_source("broll-2", 90, "After the match"),
        ],
    }


# ----- sync anchors -------------------------------------------------------------------------------

VISUAL_NOISE = [2100, -1800, 900, -2600, 1500, -700, 3100, -1200, 400, -2200, 1700, -300]
AUDIO_NOISE = [150, -220, 80, -60, 190, -140, 30, -90]


def synth_anchors(*, offset, rate: Fraction, events, src_pos, ref_pos, c=343_000, corrected=True, prefix="a",
                  noise=True):
    """events: [(t_event_us, modality, kind, position|None)] -> anchors on the source clock (Sample, synthetic)."""
    anchors = []
    vi = ai = 0
    for i, (t_e, modality, kind, pos) in enumerate(events):
        if modality == "audio":
            d_src = syncfit.sound_delay_us(pos, src_pos, c)
            d_ref = syncfit.sound_delay_us(pos, ref_pos, c)
            jitter = AUDIO_NOISE[ai % len(AUDIO_NOISE)] if noise else 0
            ai += 1
            x = round_half_up((Fraction(t_e + d_src) - offset) / rate) + jitter
            y = t_e + d_ref
            event_pos = pos if corrected else None
        else:
            jitter = VISUAL_NOISE[vi % len(VISUAL_NOISE)] if noise else 0
            vi += 1
            x = round_half_up((Fraction(t_e) - offset) / rate) + jitter
            y = t_e
            event_pos = None
        anchors.append({"id": f"{prefix}-{i + 1:02d}", "kind": kind, "modality": modality, "sourceTimeUs": x,
                        "referenceTimeUs": y, "eventPositionMm": event_pos})
    return anchors


def camera2_events():
    ev = [(60_000_000, "audio", "slate-clap", NET_CENTRE)]
    for i in range(13):
        t = 120_000_000 + i * 260_000_000
        if i % 3 == 0:
            ev.append((t, "visual", "serve-contact", None))
        else:
            ev.append((t, "audio", "impact", SOUTH_BASELINE if i % 2 else NORTH_BASELINE))
    return ev


def stored_piece(seg_id, duration, fitted, raw_anchors, *, state=None, checkpoints=(), reviewed_at=None):
    t = fitted["transform"]
    anchors = []
    for raw, got in zip(raw_anchors, fitted["anchors"]):
        anchors.append(dict(raw, sourceDelayUs=got["sourceDelayUs"], referenceDelayUs=got["referenceDelayUs"],
                            corrected=got["corrected"], residualUs=got["residualUs"], inlier=got["inlier"],
                            reviewed=state == "reviewed"))
    return {
        "segmentId": seg_id, "sourceDurationUs": duration,
        "matchCoverage": None if t is None else {"startUs": syncfit.map_us(t, 0), "endUs": syncfit.map_us(t, duration)},
        "transform": t, "fit": fitted["fit"], "anchors": anchors, "state": state or fitted["state"],
        "reasons": fitted["reasons"], "checkpoints": list(checkpoints), "reviewedAt": reviewed_at,
    }


def sync_map():
    out30 = FPS30
    cam2_raw = synth_anchors(offset=120_000, rate=Fraction(10003, 10000), events=camera2_events(),
                             src_pos=POS["BN"], ref_pos=POS["BS"], prefix="c2")
    cam2 = syncfit.fit_device([{"segmentId": "seg-0", "sourceDurationUs": HOUR_US, "anchors": cam2_raw}],
                              source_position=POS["BN"], reference_position=POS["BS"], c_mm_per_s=343_000,
                              output_fps=out30)[0]
    cam3_events = [(200_000_000 + i * 400_000_000, "visual", "serve-contact", None) for i in range(5)]
    cam3_raw = synth_anchors(offset=2_350_000, rate=Fraction(1_000_012, 1_000_000), events=cam3_events,
                             src_pos=POS["CSW"], ref_pos=POS["BS"], prefix="c3")
    cam3 = syncfit.fit_device([{"segmentId": "seg-0", "sourceDurationUs": HOUR_US, "anchors": cam3_raw}],
                              source_position=POS["CSW"], reference_position=POS["BS"], c_mm_per_s=343_000,
                              output_fps=out30)[0]
    ref_piece = {"segmentId": "seg-0", "sourceDurationUs": HOUR_US, "matchCoverage": {"startUs": 0, "endUs": HOUR_US},
                 "transform": {"offsetUs": 0, "rate": RATE1}, "fit": None, "anchors": [], "state": "reference",
                 "reasons": [], "checkpoints": [], "reviewedAt": None}
    return {
        "schemaVersion": "jovra.sync-map/1", "projectId": PROJECT, "revision": SYNC_REVISION, "sample": True,
        "sourceManifestRevision": MANIFEST_REVISION,
        "matchClock": {"unit": "us", "referenceSourceId": "camera-1", "referenceSegmentId": "seg-0",
                       "origin": "earliest-coverage"},
        "outputFps": out30,
        "speedOfSound": {"mmPerSecond": 343_000, "temperatureC": None, "method": "default-343"},
        "placements": [
            {"sourceId": "camera-1", "slot": "near-baseline", "positionMm": POS["BS"], "from": "slot-default"},
            {"sourceId": "camera-2", "slot": "far-baseline", "positionMm": POS["BN"], "from": "slot-default"},
            {"sourceId": "camera-3", "slot": "near-left-corner", "positionMm": POS["CSW"], "from": "slot-default"},
        ],
        "sources": [
            {"sourceId": "camera-1", "audioLatencyUs": None, "pieces": [ref_piece], "gaps": []},
            {"sourceId": "camera-2", "audioLatencyUs": None,
             "pieces": [stored_piece("seg-0", HOUR_US, cam2, cam2_raw, state="reviewed",
                                     checkpoints=["start", "middle", "end"], reviewed_at="2026-10-07T22:40:00Z")],
             "gaps": []},
            {"sourceId": "camera-3", "audioLatencyUs": None,
             "pieces": [stored_piece("seg-0", HOUR_US, cam3, cam3_raw)], "gaps": []},
        ],
        "provenance": {"capabilityId": "studio.multiCameraSync", "method": "jovra-sync", "methodVersion": "0.1",
                       "status": "estimated"},
    }


# ----- keepers and B-roll -------------------------------------------------------------------------

def keeper_catalog():
    def k(kid, events, session, views, contacts, selection="manual", prov="manual"):
        return {"keeperId": kid, "eventRefs": events, "session": {"startUs": session[0], "endUs": session[1]},
                "views": [{"sourceId": s, "window": {"inFrame": a, "outFrame": b}, "primary": p} for s, a, b, p in views],
                "contacts": [{"sourceId": s, "frame": f} for s, f in contacts], "selection": selection,
                "provenance": prov}
    return {
        "schemaVersion": "jovra.keeper-catalog/1", "projectId": PROJECT, "revision": KEEPER_REVISION, "sample": True,
        "eventRevision": EVENT_REVISION, "syncRevision": SYNC_REVISION,
        "keepers": [
            k("k-01", ["p-003"], (12_000_000, 19_500_000), [("camera-1", 720, 1180, True), ("camera-2", 700, 1160, False)],
              [("camera-2", 900), ("camera-1", 905)]),
            k("k-02", ["p-041"], (1_196_000_000, 1_264_000_000), [("camera-1", 71800, 75800, True)],
              [("camera-1", 72500), ("camera-1", 73100), ("camera-1", 73700)], prov="reviewed"),
            k("k-03", ["p-067", "p-068"], (1_998_000_000, 2_085_000_000), [("camera-1", 119900, 125000, True)],
              [("camera-1", 121000), ("camera-1", 122400)]),
            k("k-04", ["p-090"], (2_498_000_000, 2_620_000_000),
              [("camera-1", 149950, 157200, True), ("camera-2", 149900, 157100, False)],
              [("camera-2", 151000), ("camera-2", 152200)], selection="heuristic", prov="estimated"),
        ],
    }


def broll_catalog():
    def item(bid, sid, a, b, desc):
        return {"brollId": bid, "sourceId": sid, "window": {"inFrame": a, "outFrame": b}, "depictsThisMatch": True,
                "origin": "captured-today", "rights": {"holder": "user", "scope": ["private-film"], "rightsRecordId": None},
                "disclosureTemplateId": None, "revealsLocation": False, "participantIds": ["jon"], "description": desc}
    return {"schemaVersion": "jovra.broll-catalog/1", "projectId": PROJECT, "revision": BROLL_REVISION, "sample": True,
            "items": [item("b-01", "broll-1", 0, 1800, "Walking to the court"),
                      item("b-02", "broll-2", 0, 2700, "Packing the bag after the match")]}


# ----- EDL helpers --------------------------------------------------------------------------------

class Plan:
    def __init__(self, manifest, smap, keepers):
        self.manifest = {s["sourceId"]: s for s in manifest["sources"]}
        self.maps = {}
        for s in smap["sources"]:
            p = s["pieces"][0]
            self.maps[s["sourceId"]] = p["transform"]
        self.keepers = {k["keeperId"]: k for k in keepers["keepers"]}

    def source(self, sid):
        m = self.manifest[sid]
        proxy = [p for p in m["proxies"] if p["class"] == "render"][0]
        cov = {"inFrame": 0, "outFrame": proxy["frameCount"], "sessionStartUs": None, "rate": None}
        if m["role"] == "match":
            t = self.maps[sid]
            cov.update(sessionStartUs=t["offsetUs"], rate=t["rate"])
        return {"id": sid, "role": m["role"], "sha256": m["original"]["sha256"],
                "proxy": {"fps": proxy["fps"], "width": proxy["width"], "height": proxy["height"],
                          "frameCount": proxy["frameCount"], "ptsTableSha256": proxy["ptsTableSha256"]},
                "hasAudio": m["original"]["audio"] is not None, "coverage": [cov]}

    def fps(self, sid):
        return [p for p in self.manifest[sid]["proxies"] if p["class"] == "render"][0]["fps"]

    def session(self, sid, frame) -> Fraction:
        t = self.maps[sid]
        fps = self.fps(sid)
        return t["offsetUs"] + Fraction(t["rate"]["num"], t["rate"]["den"]) * Fraction(frame * 1_000_000 * fps["den"], fps["num"])

    def frame_for_session(self, sid, session_us) -> int:
        t = self.maps[sid]
        src_us = (Fraction(session_us) - t["offsetUs"]) / Fraction(t["rate"]["num"], t["rate"]["den"])
        return frame_at_us(src_us, self.fps(sid))

    def src_frames(self, sid, out_frames, out_fps, speed_den=1):
        n = Fraction(out_frames) * Fraction(self.fps(sid)["num"], self.fps(sid)["den"]) / \
            Fraction(out_fps["num"], out_fps["den"]) / speed_den
        assert n.denominator == 1, (sid, out_frames)
        return int(n)

    def protected(self, keeper_id, sid, s_in, s_out, pad=15):
        out = []
        for c in self.keepers[keeper_id]["contacts"] if keeper_id else []:
            if c["sourceId"] == sid and s_in <= c["frame"] < s_out:
                out.append({"inFrame": max(s_in, c["frame"] - pad), "outFrame": min(s_out, c["frame"] + pad + 1)})
        return out


CUT = {"type": "cut", "frames": 0}
FILL = {"mode": "fill"}


def ov(kind, ref, prov):
    return {"kind": kind, "refId": ref, "eventRevision": EVENT_REVISION, "provenance": prov}


def live(P, sid_, o_in, o_out, src, s_in, out_fps, keeper=None, overlays=(), framing=FILL, tr=CUT):
    s_out = s_in + P.src_frames(src, o_out - o_in, out_fps)
    return {"id": sid_, "op": "live", "outputInFrame": o_in, "outputOutFrame": o_out, "transitionIn": tr,
            "sourceId": src, "sourceInFrame": s_in, "sourceOutFrame": s_out, "speed": {"num": 1, "den": 1},
            "sessionInUs": round_half_up(P.session(src, s_in)), "keeperId": keeper,
            "protectedFrames": P.protected(keeper, src, s_in, s_out), "overlayRefs": list(overlays),
            "framing": framing}


def broll(P, sid_, o_in, o_out, src, s_in, out_fps, bid, overlays=(), tr=CUT):
    s_out = s_in + P.src_frames(src, o_out - o_in, out_fps)
    return {"id": sid_, "op": "broll", "outputInFrame": o_in, "outputOutFrame": o_out, "transitionIn": tr,
            "sourceId": src, "sourceInFrame": s_in, "sourceOutFrame": s_out, "speed": {"num": 1, "den": 1},
            "brollId": bid, "overlayRefs": list(overlays), "framing": FILL}


def replay(P, sid_, o_in, o_out, src, s_in, out_fps, of, den, overlays=(), framing=FILL, tr=CUT):
    s_out = s_in + P.src_frames(src, o_out - o_in, out_fps, den)
    return {"id": sid_, "op": "replay", "outputInFrame": o_in, "outputOutFrame": o_out, "transitionIn": tr,
            "sourceId": src, "sourceInFrame": s_in, "sourceOutFrame": s_out, "speed": {"num": 1, "den": den},
            "replayOf": of, "labelTemplateId": "label.replay", "overlayRefs": list(overlays), "framing": framing}


def card(sid_, o_in, o_out, template, refs=(), overlays=(), tr=CUT):
    return {"id": sid_, "op": "title-card", "outputInFrame": o_in, "outputOutFrame": o_out, "transitionIn": tr,
            "templateId": template, "textRefs": list(refs), "overlayRefs": list(overlays)}


def bed(route, src, s_in, o_in, o_out, fade=None, fade_in=None, fade_out=None):
    """A bed piece. Sounding routes fade 20 ms by default (the minimum at a cut where the bed changes source); silence
    fades 10 ms. Where the bed changes source at a dissolve or dip, fade_in / fade_out span the picture transition."""
    if fade is None:
        fade = 10 if route == "silence" else 20
    return {"route": route, "sourceId": src, "sourceInFrame": s_in, "outputInFrame": o_in, "outputOutFrame": o_out,
            "fadeInMs": fade if fade_in is None else fade_in, "fadeOutMs": fade if fade_out is None else fade_out}


def synced_primary(P, seg, out_fps, fade_in=None):
    """A primary-bed piece under a live segment, in sync through the session clock."""
    session = P.session(seg["sourceId"], seg["sourceInFrame"])
    return bed("primary-bed", "camera-1", P.frame_for_session("camera-1", session), seg["outputInFrame"],
               seg["outputOutFrame"], fade_in=fade_in)


def plan_doc(plan_id, revision, profile, out, sources, segments, chapters, audio, grade="none", P=None):
    return {
        "schemaVersion": "jovra.edit-plan/2", "projectId": PROJECT, "planId": plan_id, "planRevision": revision,
        "sample": True, "cleanAlternate": False,
        "bindings": {"sourceManifestRevision": MANIFEST_REVISION, "syncRevision": SYNC_REVISION,
                     "eventRevision": EVENT_REVISION, "profileId": profile, "profileRevision": 1,
                     "keeperCatalogRevision": KEEPER_REVISION, "brollCatalogRevision": BROLL_REVISION},
        "output": out, "grade": {"presetId": grade}, "sources": [P.source(s) for s in sources],
        "segments": segments, "chapters": chapters, "audio": audio,
    }


def out_spec(width, height, aspect, frames):
    return {"fps": FPS30, "width": width, "height": height, "aspect": aspect, "totalFrames": frames,
            "container": "mp4", "videoCodec": "h264", "audioCodec": "aac", "audioSampleRate": 48000}


def chapter(cid, frame, template):
    return {"id": cid, "outputInFrame": frame, "templateId": template}


def storyboard(P):
    """Screen 36 draft: Court Memories, 258 s; Camera 2 window 00:12.400-00:18.600 placed at 00:12.000-00:18.200."""
    o = FPS30
    s = [
        broll(P, "s01", 0, 360, "broll-1", 60, o, "b-01", overlays=[ov("note", "note-caption", "manual")]),
        live(P, "s02", 360, 546, "camera-2", 744, o, keeper="k-01", tr={"type": "dissolve", "frames": 12}),
        live(P, "s03", 546, 2346, "camera-1", 72000, o, keeper="k-02", overlays=[ov("score", "p-041", "reviewed")]),
        live(P, "s04", 2346, 4746, "camera-1", 120000, o, keeper="k-03"),
        live(P, "s05", 4746, 7050, "camera-2", 150000, o, keeper="k-04"),
        broll(P, "s06", 7050, 7740, "broll-2", 30, o, "b-02", tr={"type": "dip", "frames": 15}),
    ]
    # the bed changes source at the s02 dissolve (12 frames: 200 ms each side) and the s06 dip (15 frames: 267 ms
    # before, 234 ms after), so the switch is an audio dip across each picture transition
    audio = {"primarySourceId": "camera-1", "narration": None, "music": None, "bed": [
        bed("alt-bed", "broll-1", 60, 0, 360, fade_out=200),
        synced_primary(P, s[1], o, fade_in=200),
        bed("primary-bed", "camera-1", 72000, 546, 2346),
        bed("primary-bed", "camera-1", 120000, 2346, 4746),
        bed("alt-bed", "camera-2", 150000, 4746, 7050, fade_out=267),
        bed("alt-bed", "broll-2", 30, 7050, 7740, fade_in=234),
    ]}
    return plan_doc("court-memories-storyboard", 1, "court-memories", out_spec(1920, 1080, "16:9", 7740),
                    ["camera-1", "camera-2", "broll-1", "broll-2"], s,
                    [chapter("ch-arrival", 0, "chapter.arrival"), chapter("ch-match", 360, "chapter.match"),
                     chapter("ch-closing", 7050, "chapter.after")], audio, grade="warm-court-1", P=P)


def final_film_plan(P):
    """The delivered Court Memories film (screens 33/39): 04:18 with chapters 00:42 + 02:21 + 01:15."""
    o = FPS30
    s = [
        broll(P, "f01", 0, 1260, "broll-1", 60, o, "b-01", overlays=[ov("note", "note-caption", "manual")]),
        live(P, "f02", 1260, 1446, "camera-2", 744, o, keeper="k-01", tr={"type": "dissolve", "frames": 12}),
        live(P, "f03", 1446, 3246, "camera-1", 72000, o, keeper="k-02", overlays=[ov("score", "p-041", "reviewed")]),
        live(P, "f04", 3246, 5490, "camera-1", 120000, o, keeper="k-03"),
        broll(P, "f05", 5490, 7740, "broll-2", 30, o, "b-02", tr={"type": "dip", "frames": 15}),
    ]
    audio = {"primarySourceId": "camera-1", "narration": None, "music": None, "bed": [
        bed("alt-bed", "broll-1", 60, 0, 1260, fade_out=200),
        synced_primary(P, s[1], o, fade_in=200),
        bed("primary-bed", "camera-1", 72000, 1446, 3246),
        bed("primary-bed", "camera-1", 120000, 3246, 5490, fade_out=267),
        bed("alt-bed", "broll-2", 30, 5490, 7740, fade_in=234),
    ]}
    return plan_doc("court-memories-final", 2, "court-memories", out_spec(1920, 1080, "16:9", 7740),
                    ["camera-1", "camera-2", "broll-1", "broll-2"], s,
                    [chapter("ch-arrival", 0, "chapter.arrival"), chapter("ch-match", 1260, "chapter.match"),
                     chapter("ch-after", 5490, "chapter.after")], audio, grade="warm-court-1", P=P)


def coach_cut(P):
    o = FPS30
    c02 = live(P, "c02", 120, 1920, "camera-1", 72000, o, keeper="k-02",
               overlays=[ov("score", "p-041", "reviewed"), ov("metric", "stat-first-serve-in", "reviewed")])
    c05 = live(P, "c05", 2250, 5520, "camera-2", 150000, o, keeper="k-04", overlays=[ov("score", "p-090", "manual")])
    s = [
        card("c01", 0, 120, "card.goal", ["note-goal"]),
        c02,
        {"id": "c03", "op": "freeze", "outputInFrame": 1920, "outputOutFrame": 2010, "transitionIn": CUT,
         "sourceId": "camera-1", "sourceFrame": 73100, "labelTemplateId": "label.paused",
         "overlayRefs": [ov("annotation", "ann-01", "reviewed"), ov("cue", "cue-03", "reviewed")], "framing": FILL},
        replay(P, "c04", 2010, 2250, "camera-1", 72980, o, "c02", 2),
        c05,
        card("c06", 5520, 5640, "card.drill", ["note-drill"]),
        card("c07", 5640, 5760, "card.next-checkpoint", ["note-next"]),
    ]
    audio = {"primarySourceId": "camera-1", "music": None,
             "narration": {"voice": "user-recorded", "consent": {"consentRecordId": "consent-voice-jon", "granted": True},
                           "disclosureTemplateId": None, "duckDb": -12, "scriptNoteIds": ["note-drill", "note-next"],
                           "windows": [{"outputInFrame": 5520, "outputOutFrame": 5760}]},
             "bed": [
                 bed("silence", None, None, 0, 120),
                 bed("primary-bed", "camera-1", 72000, 120, 1920),
                 bed("hold-bed", "camera-1", 75600, 1920, 2250),
                 bed("alt-bed", "camera-2", 150000, 2250, 5520),
                 bed("silence", None, None, 5520, 5760),
             ]}
    return plan_doc("coach-cut-serve", 1, "coach-cut", out_spec(1920, 1080, "16:9", 5760),
                    ["camera-1", "camera-2"], s,
                    [chapter("ch-goal", 0, "chapter.goal"), chapter("ch-example-1", 120, "chapter.example"),
                     chapter("ch-example-2", 2250, "chapter.example"), chapter("ch-practice", 5520, "chapter.practice")],
                    audio, P=P)


def rally_pulse(P):
    o = FPS30
    pan = {"mode": "reframe", "basis": "reviewed-action-box",
           "windows": [{"atFrame": 0, "x": 3418, "y": 0, "w": 3164, "h": 10000},
                       {"atFrame": 210, "x": 3600, "y": 0, "w": 3164, "h": 10000}]}
    still = {"mode": "reframe", "basis": "reviewed-action-box",
             "windows": [{"atFrame": 0, "x": 3418, "y": 0, "w": 3164, "h": 10000}]}
    s = [
        live(P, "r01", 0, 420, "camera-1", 72300, o, keeper="k-02", overlays=[ov("score", "p-041", "reviewed")],
             framing=pan),
        live(P, "r02", 420, 900, "camera-1", 120000, o, keeper="k-03", framing=still,
             tr={"type": "dissolve", "frames": 6}),
        card("r03", 900, 945, "card.accent"),
        live(P, "r04", 945, 1350, "camera-2", 150700, o, keeper="k-04", framing={"mode": "letterbox"}),
    ]
    audio = {"primarySourceId": "camera-1", "narration": None,
             "music": {"assetId": "track-01", "rightsRecordId": "rights-track-01", "rightsScope": ["private-film"],
                       "windows": [{"outputInFrame": 0, "outputOutFrame": 1350}]},
             "bed": [
                 # r01 -> r02 jumps to another moment of camera-1 at a dissolve: a switch, so an audio dip spans it
                 bed("primary-bed", "camera-1", 72300, 0, 420, fade_out=100),
                 bed("primary-bed", "camera-1", 120000, 420, 900, fade_in=100),
                 bed("hold-bed", "camera-1", 120960, 900, 945),
                 bed("alt-bed", "camera-2", 150700, 945, 1350),
             ]}
    return plan_doc("rally-pulse-portrait", 1, "rally-pulse", out_spec(1080, 1920, "9:16", 1350),
                    ["camera-1", "camera-2"], s, [], audio, P=P)


def match_broadcast(P):
    o = FPS30
    m02 = live(P, "m02", 150, 4650, "camera-1", 6000, o, overlays=[ov("score", "game-07", "reviewed")],
               framing={"mode": "fill"})
    # replay of session 240.0-244.0 s from the far baseline, after the point and before the next serve
    r_in = P.frame_for_session("camera-2", 240_000_000)
    s = [
        card("m01", 0, 150, "card.match-intro", ["note-players"]),
        m02,
        replay(P, "m03", 4650, 4890, "camera-2", r_in, o, "m02", 2, tr={"type": "dissolve", "frames": 8}),
        live(P, "m04", 4890, 9000, "camera-1", 15600, o, overlays=[ov("score", "game-08", "reviewed")],
             tr={"type": "dissolve", "frames": 8}),
    ]
    audio = {"primarySourceId": "camera-1", "narration": None, "music": None, "bed": [
        bed("silence", None, None, 0, 150),
        bed("primary-bed", "camera-1", 6000, 150, 4650),
        # the hold-bed ends at 15480; m04's bed starts at 15600 (a jump) at a dissolve: an audio dip spans it
        bed("hold-bed", "camera-1", 15000, 4650, 4890, fade_out=134),
        bed("primary-bed", "camera-1", 15600, 4890, 9000, fade_in=134),
    ]}
    return plan_doc("match-broadcast-set-1", 1, "match-broadcast", out_spec(1920, 1080, "16:9", 9000),
                    ["camera-1", "camera-2"], s, [chapter("ch-intro", 0, "chapter.intro"),
                                                  chapter("ch-games", 150, "chapter.games")], audio, P=P)


# ----- main ---------------------------------------------------------------------------------------

def sample_project() -> SimpleNamespace:
    """The Sample project every cases module builds from: its records (keyed by path relative to
    spec/studio/fixtures), the edit plans, the plan helper P, the trusted EDL context and the story profiles."""
    import generate_studio_records as rec
    from studio import bundle as studio_bundle
    manifest = source_manifest()
    smap = sync_map()
    keepers = keeper_catalog()
    P = Plan(manifest, smap, keepers)
    plans = {"storyboard": storyboard(P), "final": final_film_plan(P), "coach": coach_cut(P),
             "rally": rally_pulse(P), "broadcast": match_broadcast(P)}
    records = {
        "records/source-manifest.json": manifest,
        "records/sync-map.json": smap,
        "records/keeper-catalog.json": keepers,
        "records/broll-catalog.json": broll_catalog(),
        "records/project-lock.json": rec.project_lock(manifest),
        "records/story-brief.court-memories.json": rec.court_memories_brief(),
        "records/story-brief.progress.json": rec.progress_brief(),
        "records/edit-plan.court-memories-storyboard.json": plans["storyboard"],
        "records/edit-plan.court-memories-storyboard.clean.json": edl.clean_alternate(plans["storyboard"]),
        "records/edit-plan.court-memories-final.json": plans["final"],
        "records/edit-plan.coach-cut-serve.json": plans["coach"],
        "records/edit-plan.rally-pulse-portrait.json": plans["rally"],
        "records/edit-plan.rally-pulse-portrait.clean.json": edl.clean_alternate(plans["rally"]),
        "records/edit-plan.match-broadcast-set-1.json": plans["broadcast"],
        "records/camera-invite.json": rec.camera_invites(),
        "records/storage-providers.json": rec.storage_providers(),
        "records/delivered-artifact.film.json": rec.delivered_artifact(plans["final"]),
    }
    for name, doc in rec.observations().items():
        records[f"records/{name}.json"] = doc
    for name, doc in rec.lessons().items():
        records[f"records/{name}.json"] = doc
    records["records/reference-catalog.json"] = rec.reference_catalog()
    for name, doc in rec.quotes(plans["final"], plans["storyboard"]).items():
        records[f"records/{name}.json"] = doc
    for name, doc in rec.reservations(plans["final"], plans["storyboard"]).items():
        records[f"records/{name}.json"] = doc
    for name, doc in rec.render_jobs(plans["final"], plans["storyboard"]).items():
        records[f"records/{name}.json"] = doc
    trusted = studio_bundle.edl_context({"manifest": manifest, "syncMap": smap, "keepers": keepers,
                                         "brolls": records["records/broll-catalog.json"],
                                         "references": records["records/reference-catalog.json"]})
    plans["syncmap"] = smap
    plans["manifest"] = manifest
    return SimpleNamespace(manifest=manifest, smap=smap, keepers=keepers, P=P, plans=plans, records=records,
                           trusted=trusted, profiles={p["id"]: p for p in profile_catalog()["profiles"]})


class DeclarationError(ValueError):
    """Two cases modules declare the same fixture path."""


def build() -> dict:
    """Every fixture document, keyed by its path relative to spec/studio/fixtures: whatever each discovered cases
    module (spec/reference/studio/cases/*_cases.py) declares, written once."""
    from studio import cases
    sample = sample_project()
    docs: dict = {}
    owner: dict = {}
    for module in cases.discover():
        declare = getattr(module, "fixtures", None)
        if declare is None:
            continue
        for rel, doc in declare(sample).items():
            if rel in docs:
                raise DeclarationError(f"{rel} is declared by {owner[rel]} and by {cases.repo_path(module)}")
            docs[rel] = doc
            owner[rel] = cases.repo_path(module)
    return docs


def module_index() -> str:
    """spec/studio/modules/README.md: a link to every module page in the folder (names only, so a page's status
    changes never touch the index)."""
    pages = sorted(p.stem for p in MODULES.glob("*.md") if p.name != MODULE_INDEX.name)
    lines = ["# Studio module pages", "",
             "Generated by `spec/reference/studio/generate_studio_fixtures.py` from the pages in this folder; do not",
             "edit it by hand. A new page appears here when the generator runs. Each page's front matter (`kinds`,",
             "`coverage`, `swift`, `kotlin`) is checked by `scripts/spec/validate_studio.py`, and",
             "`python3 scripts/spec/validate_studio.py --list` prints every registered kind with its module and status.",
             ""]
    lines += [f"- [{name}]({name}.md)" for name in pages]
    return "\n".join(lines) + "\n"


def main() -> None:
    sys.path.insert(0, str(HERE))
    dump(CONTRACTS / "story-profiles.v1.json", profile_catalog())
    docs = build()
    for old in sorted(OUT.rglob("*.json")):
        if str(old.relative_to(OUT)) not in docs:
            old.unlink()
    for rel, doc in docs.items():
        dump(OUT / rel, doc)
    MODULE_INDEX.write_text(module_index(), encoding="utf-8")
    print(f"wrote {len(docs)} fixture files, the story-profile catalog and the module index")


if __name__ == "__main__":
    main()
