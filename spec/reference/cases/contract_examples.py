"""Contract examples (T02): one document per 1.1 record type carrying every field added in 1.1.

They are the documents T03 round-trips and the validator's closed-object self-test mutates. They are labelled
Sample and are not demo content: no screen shows them. Times, ids and positions are illustrative but consistent:
the match log folds, every id resolves and every 1.1 time sits inside the recording (jovra_ref/references.py), the
serve speed and its range are computed from its serve mark (CLAUDE.md hard rule 1), and file sizes and hashes match
the files they name. The generator refuses to write a
session that breaks any of these.
"""

from __future__ import annotations

import copy
import hashlib
import json

from jovra_ref import references, scoring

from . import records, sample_media

ORDER = 70
VERSION = "1.1.0"
T = "2026-10-07T18:00:00Z"
JON, MIA = "ex-player-jon", "ex-player-mia"
# Jon serves from the near end (toss: side A starts near), so the defaulted contact is the centre mark of the near
# baseline: x 0, y -11.885 in court metres (common.point2, origin at the centre of the net).
NEAR_CENTRE_MARK = {"x": 0, "y": -references.BASELINE_Y}
SERVE_MARK = {
    "id": "ex-serve-mark-1", "pointId": "ex-point-1", "shotId": "ex-shot-1",
    "contactFrame": {"value": 1830, "timescale": 60}, "bounceFrame": {"value": 1854, "timescale": 60},
    "bounceCourt": {"x": -2.4, "y": 5.1}, "bounceImage": {"x": 0.44, "y": 0.39},
    "serverPosition": NEAR_CENTRE_MARK, "contactDefaulted": True, "servedTo": "deuce",
}
SAMPLE_PROV = {"status": "manual", "source": "user", "sample": True}


def _point(pid, seq, winner, start, end, **extra):
    serves = [{"result": "in"}]
    outcome = {"winner": winner, "endType": "winner", "serves": serves, "strokeCount": 3,
               "provenance": "manual", "source": "user"}
    return {"id": pid, "seq": seq, "type": "point", "recordedServer": JON, "tStartMs": start, "tEndMs": end,
            "reviewed": outcome, "reviewState": "reviewed", **extra}


def session() -> dict:
    log = [
        _point("ex-point-1", 1, "A", 28_000, 36_000),
        _point("ex-point-2", 2, "B", 52_000, 61_000),
        _point("ex-point-3", 3, "A", 80_000, 112_000),
        {"id": "ex-void-3", "seq": 4, "type": "void", "target": "ex-point-3", "source": "user"},
        _point("ex-point-3a", 5, "A", 80_000, 95_000, parentIds=["ex-point-3"]),
        _point("ex-point-3b", 6, "B", 99_000, 112_000, parentIds=["ex-point-3"]),
    ]
    mark_prov = dict(SAMPLE_PROV)
    calibration_id = "ex-calibration-1"
    doc = {
        "schemaVersion": VERSION,
        "kind": "jovra.session",
        "id": "ex-session-all-fields",
        "sport": "tennis",
        "createdAt": T,
        "updatedAt": T,
        "title": "Contract example: every 1.1 field",
        "sample": {"label": "Sample", "synthetic": True, "generator": "sample:contractExample@1.1.0",
                   "mediaIds": ["sample-media.2026-10-04-behind-baseline-12-serves"]},
        "sessionKind": "match",
        "capturePurpose": "match",
        "players": [
            {"id": JON, "displayName": "Jon", "handedness": "right", "backhand": "twoHanded", "isSelf": True},
            {"id": MIA, "displayName": "Mia", "handedness": "left", "backhand": "twoHanded", "isSelf": False,
             "profileId": "ex-profile-mia"},
        ],
        "sides": {"A": [JON], "B": [MIA]},
        "match": {
            "format": {"presetId": "club_bo3", "setsToWin": 2, "gameScoring": "ad",
                       "set": {"kind": "tiebreakSet", "games": 6, "tiebreakAt": 6, "tiebreak": {"points": 7}},
                       "lets": "let"},
            "toss": {"firstServer": JON, "startingEnds": {"A": "near", "B": "far"}},
            "log": log,
        },
        "recording": {
            "mode": "camera", "startedAt": "2026-10-07T17:00:00Z", "timeZone": "America/Chicago",
            "durationMs": 600_000,
            "segments": [{"id": "ex-segment-0", "index": 0, "file": {"path": "media/segment-000.mp4"}, "startMs": 0,
                          "durationMs": 600_000, "frameRate": {"num": 60, "den": 1}, "width": 1920, "height": 1080,
                          "codec": "hevc", "hasAudio": True, "finalized": True}],
            "gaps": [], "microphone": "granted", "mediaAvailable": True,
            "captureEvents": [
                {"tMs": 300_000, "kind": "thermalState", "thermalState": "serious"},
                {"tMs": 300_000, "kind": "courtModeOn"},
                {"tMs": 420_000, "kind": "frameRateChange", "frameRate": {"num": 30, "den": 1}},
            ],
            "recovery": {"recoveredAt": T, "outcome": "partial", "savedThroughMs": 598_000,
                         "truncatedSegmentIds": ["ex-segment-0"],
                         "unrecoverable": [{"path": "media/segment-001.mp4",
                                            "reason": "The last 2 seconds could not be decoded."}]},
        },
        "marks": [{"id": "ex-mark-1", "tMs": 30_000, "kind": "point", "note": "Great point", "provenance": mark_prov}],
        "shots": [
            {"id": "ex-shot-1", "pointId": "ex-point-1", "tMs": 30_500, "hitter": JON, "shotIndex": 1,
             "stroke": "serve", "provenance": mark_prov},
            {"id": "ex-shot-2", "pointId": "ex-point-1", "tMs": 31_400, "hitter": MIA, "shotIndex": 2,
             "stroke": "forehand",
             "placement": {"court": {"x": 2.1, "y": -9.4}, "zone": "deep", "inOut": "in",
                           "calibrationId": calibration_id},
             "provenance": mark_prov},
        ],
        "calibrations": [{
            "id": calibration_id, "method": "fourTap", "frameMs": 1_000,
            "imagePoints": [{"x": 0.12, "y": 0.86}, {"x": 0.88, "y": 0.86}, {"x": 0.63, "y": 0.31},
                            {"x": 0.37, "y": 0.31}],
            "courtPoints": [{"x": -4.115, "y": -11.885}, {"x": 4.115, "y": -11.885}, {"x": 4.115, "y": 11.885},
                            {"x": -4.115, "y": 11.885}],
            "residualPx": 1.4, "status": "cameraMoved", "staleFromMs": 420_000,
            "camera": {"lens": "wide", "width": 1920, "height": 1080, "frameRate": {"num": 60, "den": 1},
                       "zoomFactor": "1.0"},
            "provenance": mark_prov,
        }],
        "annotations": [],
        "voiceNotes": [],
        "comparisons": [{
            "id": "ex-comparison-1", "title": "Serve now and then",
            "left": {"sessionId": "ex-session-all-fields", "syncTimeMs": 30_500},
            "right": {"sessionId": "ex-session-other", "syncTimeMs": 1_803_000, "nudgeFrames": 1},
            "syncedAt": "contact", "createdAt": T, "note": "Keep the toss position consistent.",
        }],
        "derivedValues": [
            {"id": "ex-derived-speed", "key": "serveSpeed.estimate", "value": references.serve_speed_mph(SERVE_MARK),
             "unit": "mph", "range": None,
             "label": "Estimated average speed, contact→bounce",
             "scope": {"pointId": "ex-point-1", "serveMarkId": "ex-serve-mark-1"},
             "provenance": {"status": "estimated", "source": "model:serveSpeed.manualAssisted@1.0.0",
                            "capabilityId": "serveSpeed.manualAssisted", "capabilityVersion": "1.0.0",
                            "calibrationId": calibration_id, "sample": True}},
        ],
        "analysis": {"state": "paused", "reason": "Analysis pauses if you leave JOVRA", "excludedSide": "left",
                     "runs": [{"capabilityId": "audio.hitDetection", "capabilityVersion": "1.0.0",
                               "status": "skipped"}]},
        "review": {"state": "inProgress", "updatedAt": T},
        "archive": {"state": "backedUp", "provider": "googleDrive", "manifest": "archive.json", "backedUpAt": T,
                    "copy": "rallyOnlyCopy", "restoredAt": T},
        "storage": {"originals": "onDevice", "includeInDeviceBackup": False},
        "original": {"state": "partial", "reason": "The last 2 seconds could not be decoded.", "updatedAt": T},
        "consent": {
            "status": "writtenFormAttached", "competitionMode": True, "juniorPlayerIds": [MIA],
            "writtenConsents": [{"id": "ex-consent-1",
                                 "attachment": {"path": "consent/written-consent.pdf", "mimeType": "application/pdf"},
                                 "coversPlayerIds": [MIA], "attachedAt": "2026-10-07T16:55:00Z"}],
            "withdrawnAt": "2026-10-07T17:09:00Z",
        },
        "rallyPlayback": {
            "preRollMs": 1500, "postRollMs": 2500,
            "clips": [{"targetId": "ex-point-1", "preRollMs": 2000, "postRollMs": 4000},
                      {"targetId": "ex-mark-1", "excluded": True}],
        },
        "serveMarks": [dict(SERVE_MARK, calibrationId=calibration_id, outlierConfirmed=False, provenance=mark_prov)],
        "swings": [
            {"id": "ex-swing-serve", "kind": "serve", "stroke": "serve", "serveMarkId": "ex-serve-mark-1",
             "clip": {"fromMs": 29_000, "toMs": 31_500},  # -1.0 / +1.0 s around contact, nudged 0.5 s earlier
             "keyMoments": [{"name": n, "time": {"value": v, "timescale": 60}, "provenance": mark_prov}
                            for n, v in (("tossRelease", 1759), ("trophy", 1801), ("racketDrop", 1822),
                                         ("contact", 1830), ("landing", 1846))]
             + [{"name": "tossPeak", "time": {"value": 1790, "timescale": 60}, "imagePoint": {"x": 0.47, "y": 0.22},
                 "provenance": mark_prov}]},
            {"id": "ex-swing-forehand", "kind": "stroke", "stroke": "forehand", "shotId": "ex-shot-2",
             "markId": "ex-mark-1", "clip": {"fromMs": 30_400, "toMs": 32_400},
             "keyMoments": [{"name": n, "time": {"value": v, "timescale": 240}, "provenance": mark_prov}
                            for n, v in (("ready", 7440), ("unitTurn", 7476), ("racketDrop", 7512),
                                         ("contact", 7536), ("finish", 7584))],
             "reviewChecks": [{"check": "contactTiming", "status": "looksGood"},
                              {"check": "followThrough", "status": "workOnIt"},
                              {"check": "balance", "status": "notReviewed"}]},
        ],
        "exports": [
            {"id": "ex-export-clip", "kind": "clip", "createdAt": "2026-10-07T17:20:00Z", "eventLogVersion": 3,
             "includesAudio": False, "facesBlurred": True, "rallyOnly": False,
             "range": {"fromMs": 26_500, "toMs": 40_000}, "pointIds": ["ex-point-1"], "destination": "photos",
             "status": "done"},
            {"id": "ex-export-condensed", "kind": "condensedMatch", "createdAt": T, "eventLogVersion": 6,
             "includesAudio": False, "rallyOnly": True,
             "file": {"path": "exports/condensed.mp4", "mimeType": "video/mp4"}, "destination": "app",
             "status": "failed", "failureReason": "Not enough space on this iPhone."},
        ],
    }
    speed = doc["derivedValues"][0]
    speed["range"] = references.estimate_range(speed["value"], references.serve_range_pct(doc, SERVE_MARK))
    fixture_input = {"format": doc["match"]["format"], "players": doc["players"], "sides": doc["sides"],
                     "toss": doc["match"]["toss"], "log": log}
    scoring.fold(fixture_input, log)  # the example's log must stay foldable
    problems = references.session_problems(doc, sample_media.manifest())
    if problems:
        raise ValueError("contract example session is inconsistent: " + "; ".join(problems))
    return doc


def practice_plan(jon_vs_alex: dict) -> dict:
    plan = copy.deepcopy(records.practice_plan(jon_vs_alex))
    plan.update(schemaVersion=VERSION, id="ex-plan-all-fields", title="Contract example: every 1.1 field",
                createdAt=T, updatedAt=T)
    item = plan["items"][0]
    item["drill"].update(durationMinutes=8, sets=3, reps=10)
    plan["goals"][0].update(window="fourWeeks", targetDate="2026-11-04", createdAt=T)
    plan["drillLogs"] = [{
        "id": "ex-drill-log-1", "itemId": item["id"], "drillTitle": item["drill"]["title"],
        "startedAt": "2026-10-07T17:30:00Z", "finishedAt": "2026-10-07T17:39:00Z", "activeSeconds": 480,
        "status": "finished", "setsPlanned": 3, "setsCompleted": 3, "tally": {"in": 21, "out": 9},
        "recordedSessionId": "ex-session-all-fields", "goalIds": [plan["goals"][0]["id"]], "sample": True,
    }]
    return plan


def _facts(path) -> dict:
    data = path.read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "md5": hashlib.md5(data).hexdigest()}


def export_manifest(session_path, session_doc: dict) -> dict:
    facts = _facts(session_path)
    return {
        "schemaVersion": VERSION, "kind": "jovra.export", "exportedAt": T,
        "app": {"name": "JOVRA", "version": "0.0.0", "build": "1", "platform": "reference"},
        "scope": "sharePack", "includesAudio": False, "includesOriginals": False,
        "sessions": [{"id": session_doc["id"], "title": session_doc["title"], "path": session_path.name,
                      "sample": True, "eventLogVersion": 6}],
        "files": [{"path": session_path.name, "role": "sessionJson", "mimeType": "application/json",
                   "bytes": facts["bytes"], "sha256": facts["sha256"], "sessionId": session_doc["id"]}],
        "csvContracts": [{"name": "points", "version": 1}],
        "contact": "hello@islanddevcrew.com",
        "facesBlurred": True,
        "sharePack": {"audience": "opponent", "selection": "selectedPoints", "source": "rallyOnly"},
    }


def archive_manifest(session_path, session_doc: dict) -> dict:
    facts = _facts(session_path)
    upload = {"lastConfirmedOffset": 0, "attempts": 0, "wifiOnly": True, "updatedAt": T}
    return {
        "schemaVersion": VERSION, "kind": "jovra.archiveManifest", "sessionId": session_doc["id"],
        "provider": "googleDrive", "scope": "https://www.googleapis.com/auth/drive.file", "createdAt": T,
        "updatedAt": T, "sample": True, "spaceSaver": True, "includesAudio": False,
        "remoteFolder": {"displayPath": "JOVRA/2026/2026-10-07 Contract example"},
        "files": [
            {"role": "sidecar", "localPath": session_path.name, "mimeType": "application/json",
             "bytes": facts["bytes"], "md5": facts["md5"], "sha256": facts["sha256"],
             "remote": {"name": "session.jovra.json", "fileId": "SAMPLE-not-a-drive-id-0002",
                        "appProperties": {"jovraSessionId": session_doc["id"], "jovraRole": "sidecar"}},
             "upload": dict(upload, state="waitingForNetwork", attempts=1,
                            lastError={"code": "network", "message": "Waiting for a connection"})},
            {"role": "rallyOnlyCopy", "localPath": "exports/rally-only.mp4", "mimeType": "video/mp4",
             "bytes": 1_700_000_000, "eventLogVersion": 6,
             "remote": {"name": "rally-only.mp4"},
             "upload": dict(upload, state="queued")},
        ],
    }


def generate(ctx) -> int:
    out = ctx.fixtures / "records"
    jon_vs_alex = json.loads((ctx.fixtures / "sample" / "jon-vs-alex.session.json").read_text(encoding="utf-8"))
    session_doc = session()
    session_path = out / "session.all-fields.json"
    ctx.write_json(session_path, session_doc)
    plan = practice_plan(jon_vs_alex)
    export = export_manifest(session_path, session_doc)
    archive = archive_manifest(session_path, session_doc)
    sessions = {session_doc["id"]: session_doc}
    problems = references.practice_plan_problems(plan) + references.export_problems(export, sessions) \
        + references.archive_problems(archive, sessions)
    if problems:
        raise ValueError("contract examples are inconsistent: " + "; ".join(problems))
    ctx.write_json(out / "practice-plan.all-fields.json", plan)
    ctx.write_json(out / "export.all-fields.json", export)
    ctx.write_json(out / "archive.all-fields.json", archive)
    return 4
