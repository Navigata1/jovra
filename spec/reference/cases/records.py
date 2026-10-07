"""Example records for the non-engine schemas, plus the v1 capability registry contract.

All example records are visibly Sample (CLAUDE.md hard rule 1). Equipment names are the brief's
user-entered sample text (D6: no catalog), not endorsements. File sizes and hashes in the export and
archive examples are computed from the real sample files they point at; Drive ids are obvious
placeholders because no Drive call was ever made (D3: real-Drive verification is UNVERIFIED).
"""

from __future__ import annotations

import hashlib
from pathlib import Path

from jovra_ref.sample_match import JON, uid

T0 = "2026-10-07T01:30:00Z"


def _entity(name: str) -> dict:
    return {"id": uid(name), "createdAt": "2026-09-28T18:00:00Z", "updatedAt": "2026-09-28T18:00:00Z"}


def equipment() -> dict:
    hyper_g = {**_entity("string/hyper-g"), "brand": "Solinco", "model": "Hyper-G", "material": "polyester",
               "construction": "shaped", "gaugeLabel": "17", "nominalDiameterMm": "1.20", "color": "green"}
    ghost = {**_entity("string/ghost-wire"), "brand": "Tier One", "model": "Ghost Wire", "material": "polyester",
             "construction": "round", "gaugeLabel": "17", "nominalDiameterMm": "1.20", "color": "white"}
    weiss = {**_entity("string/weisscannon"), "brand": "WeissCANNON", "model": "Silverstring",
             "material": "polyester", "construction": "round", "gaugeLabel": "1.25", "nominalDiameterMm": "1.25"}
    prestige = {**_entity("frame/prestige"), "brand": "Head", "model": "Prestige", "source": "userEntered"}
    pro_staff = {**_entity("frame/pro-staff-85"), "brand": "Wilson", "model": "Pro Staff 85", "source": "userEntered"}

    def seg(product, value):
        return {"stringProductId": product["id"],
                "productSnapshot": {"brand": product["brand"], "model": product["model"],
                                    "gaugeLabel": product["gaugeLabel"],
                                    "nominalDiameterMm": product["nominalDiameterMm"]},
                "tension": {"value": value, "unit": "lb"}}

    job = {**_entity("stringJob/2026-09-28"), "racketId": uid("racket/head-prestige"), "strungOn": "2026-09-28",
           "timeZone": "America/Chicago", "strungBy": {"kind": "self"},
           "machine": {"type": "crankLockout"}, "layout": "hybrid", "mains": seg(hyper_g, "52"),
           "crosses": seg(ghost, "50"), "method": "twoPiece", "notes": "Sample setup"}
    return {
        "schemaVersion": "1.0.0",
        "kind": "jovra.equipment",
        "updatedAt": T0,
        "sample": {"label": "Sample"},
        "frameModels": [prestige, pro_staff],
        "rackets": [
            {**_entity("racket/head-prestige"), "ownerPlayerId": JON, "frameModelId": prestige["id"],
             "nickname": "Head Prestige", "status": "active"},
            {**_entity("racket/pro-staff-85"), "ownerPlayerId": JON, "frameModelId": pro_staff["id"],
             "nickname": "Classic frame", "status": "retired"},
        ],
        "stringProducts": [hyper_g, ghost, weiss],
        "stringInventory": [{**_entity("inventory/weisscannon"), "stringProductId": weiss["id"], "form": "set",
                             "initialLength": {"value": "12.2", "unit": "m"}}],
        "stringJobs": [job],
        "setupRatings": [{**_entity("rating/2026-10-06"), "stringJobId": job["id"], "ratedAt": "2026-10-07T01:00:00Z",
                          "stage": "fresh", "axes": {"control": 4, "comfort": 3, "spin": 4}}],
        "courtKit": [{"id": uid("kit/bag"), "kind": "bag", "label": "Dunlop bag"},
                     {"id": uid("kit/balls"), "kind": "balls", "label": "Grand Prix balls"}],
        "reminders": [{"id": uid("reminder/prestige"), "racketId": uid("racket/head-prestige"),
                       "afterLoggedHours": 20, "afterDays": 60}],
    }


def _gate(promotes, metrics, data):
    return {"promotesTo": promotes,
            "metrics": [{"name": n, "comparator": c, "threshold": t, **({"unit": u} if u else {})}
                        for n, c, t, u in metrics],
            "minimumData": data}


def _cap(cid, title, status, in_v1, method, label, review, cal=False, mic=False, video=True, deps=None, gate=None,
         notes=None):
    cap = {"id": cid, "title": title, "status": status, "inV1": in_v1, "method": method, "version": "1.0.0",
           "uiLabel": label, "outputsNeedReview": review,
           "requires": {"calibration": cal, "microphone": mic, "video": video}, "gate": gate, "lastBenchmark": None}
    if deps:
        cap["requires"]["capabilities"] = deps
    if notes:
        cap["notes"] = notes
    return cap


def capability_registry() -> dict:
    caps = [
        _cap("scoring.manual", "Manual scoring and Mark point", "manual", True,
             "Player taps point winners, end types and bookmarks; the score is folded from the log.", "Manual", False,
             video=False),
        _cap("points.review", "Fast Point Review", "manual", True,
             "Player confirms or corrects each point; corrections supersede, never overwrite.", "Reviewed", False),
        _cap("checkpoint.autofill", "Changeover checkpoint auto-fill", "estimated", True,
             "Bounded enumeration of point winners consistent with as-called game scores and legal game lengths.",
             "Estimated", True, video=False,
             notes="Not yet in spec/reference; needs its own fixtures before either platform ships it."),
        _cap("audio.hitDetection", "Racket-ball hit detection (audio)", "disabled", True,
             "Spectral-flux onsets on the audio track with travel-time correction (vDSP / Accelerate).", "Estimated",
             True, mic=True, gate=_gate("estimated", [("own-court hit precision", ">=", "0.95", None),
                                                     ("own-court hit recall", ">=", "0.90", None),
                                                     ("onset MAE", "<=", "10", "ms")],
                                       "Synthetic sample video benchmark plus >= 10 real sessions at >= 3 venues"),
             notes="D10: suggestions always start as Needs review. Unavailable when the microphone is off (D5)."),
        _cap("rally.segmentation", "Rally segmentation", "disabled", True,
             "Rallies = hits with gaps < ~3 s; point gaps > ~5 s; motion corroboration.", "Estimated", True, mic=True,
             deps=["audio.hitDetection"],
             gate=_gate("estimated", [("hits inside kept clips", ">=", "0.99", None),
                                      ("boundary F1 at 1 s", ">=", "0.90", None)],
                        "Same benchmark set as audio.hitDetection")),
        _cap("court.calibration", "Court calibration (4 taps)", "manual", True,
             "Player taps four singles-court corners; homography from ITF dimensions.", "Manual", False, cal=True),
        _cap("camera.movedDetection", "Camera-moved detection", "disabled", True,
             "Homographic registration of frames against the calibration frame.", "Estimated", True, cal=True,
             gate=_gate("estimated", [("1-degree nudge detected", ">=", "0.99", None),
                                      ("false alarms per hour", "<=", "1", None)], "Bench and court footage")),
        _cap("pose.overlay2d", "2D pose overlay (Stroke Lab)", "estimated", True,
             "Apple Vision / ML Kit 2D body pose on demand on selected frames; never scored.", "2D pose estimate",
             True, gate=_gate("validated", [("keypoint agreement on labelled frames", ">=", "0.90", None)],
                              "Labelled side-on clips incl. left-handers")),
        _cap("serveSpeed.manualAssisted", "Serve speed (manual-assisted)", "estimated", True,
             "Player marks contact and bounce frames and taps the bounce on the calibrated court; average speed = "
             "distance / time from an assumed contact point above the server's baseline position.",
             "Estimated average speed, contact→bounce", True, cal=True, deps=["court.calibration"],
             gate=_gate("validated", [("MAPE vs radar", "<=", "7", "%"), ("within 10% of radar", ">=", "0.90", None)],
                        "Radar-paired serves on >= 3 courts")),
        _cap("shotPlacement.manual", "Shot placement (manual taps)", "manual", True,
             "Player taps bounces on the court diagram or the calibrated frame.", "Manual", False),
        _cap("strokeClassification", "Automatic stroke classification", "unsupported", False,
             "Out of v1 (backlog Later).", "Not available", True),
        _cap("ballTrajectory", "Ball tracking", "unsupported", False, "Out of v1 (backlog Later).", "Not available",
             True),
        _cap("bouncePlacement.auto", "Automatic bounce maps", "unsupported", False, "Out of v1 (backlog Later).",
             "Not available", True),
        _cap("pointOutcome.auto", "Automatic point winners", "unsupported", False,
             "Out of v1 (backlog Later). The log format already separates detected from reviewed outcomes.",
             "Not available", True),
        _cap("lineCalling", "Line calls", "unsupported", False,
             "Never: far-baseline resolution is 0.2-0.4 m per pixel against 5 cm lines.", "Not available", True),
        _cap("spinRpm", "Spin RPM", "unsupported", False, "Never from a single phone camera.", "Not available", True),
        _cap("biomechanics3d", "3D biomechanics", "unsupported", False, "Never from a single phone camera.",
             "Not available", True),
        _cap("stringBed.pitchCheck", "String-bed pitch check", "unsupported", False,
             "Relative acoustic estimate; P2 candidate pending bench gate and patent review.", "Not available", True,
             mic=True, video=False),
    ]
    return {"schemaVersion": "1.0.0", "kind": "jovra.capabilityRegistry", "registryVersion": 1, "updatedAt": T0,
            "capabilities": caps}


def practice_plan(session: dict) -> dict:
    log = session["match"]["log"]
    lost_on_first = [e["id"] for e in log if e["recordedServer"] == JON and e["reviewed"]["winner"] == "B"
                     and [s["result"] for s in e["reviewed"]["serves"] if s["result"] != "let"] == ["in"]]
    return {
        "schemaVersion": "1.0.0",
        "kind": "jovra.practicePlan",
        "id": uid("plan/toss"),
        "createdAt": T0,
        "updatedAt": T0,
        "title": "One focus for next time",
        "label": "Suggested practice",
        "sample": True,
        "playerId": JON,
        "basedOnSessions": [session["id"]],
        "items": [{
            "id": uid("plan/toss/item"),
            "focus": "Build a repeatable toss",
            "drill": {"title": "Toss-and-catch ladder",
                      "instructions": "Toss without hitting; let it land on the racket placed in front of the "
                                      "baseline. Ten in a row, then add serves at 70% pace.",
                      "durationMinutes": 15, "reps": 50},
            "origin": {"kind": "rule", "ruleId": "practice.firstServePointsWon", "ruleVersion": "1.0.0",
                       "condition": "firstServePointsWon.pct < 72"},
            "evidence": [{
                "sessionId": session["id"], "stat": "firstServePointsWon", "side": "A",
                "value": {"n": 28, "d": 40, "pct": 70, "display": "70%"},
                "text": "28 of 40 first-serve points won", "pointIds": lost_on_first,
                "provenance": {"status": "reviewed", "source": "rule:practice.firstServePointsWon@1.0.0",
                               "denominator": 40, "sample": True},
                "availability": "videoUnavailable"}],
            "status": "planned",
            "userEdited": False,
        }],
        "goals": [{"id": uid("goal/first-serve"), "stat": "firstServeIn", "target": 70, "sessionKind": "match"}],
    }


def _file_facts(path: Path) -> dict:
    data = path.read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "md5": hashlib.md5(data).hexdigest()}


def export_manifest(sample_dir: Path, session: dict) -> dict:
    files = []
    for name, role, mime in (("jon-vs-alex.session.json", "sessionJson", "application/json"),
                             ("jon-vs-alex.points.csv", "pointsCsv", "text/csv"),
                             ("jon-vs-alex.stats.csv", "statsCsv", "text/csv")):
        facts = _file_facts(sample_dir / name)
        files.append({"path": name, "role": role, "mimeType": mime, "bytes": facts["bytes"],
                      "sha256": facts["sha256"], "sessionId": session["id"]})
    return {
        "schemaVersion": "1.0.0", "kind": "jovra.export", "exportedAt": T0,
        "app": {"name": "JOVRA", "version": "0.0.0", "platform": "reference"},
        "scope": "session", "includesAudio": False, "includesOriginals": False,
        "sessions": [{"id": session["id"], "title": session["title"], "path": "jon-vs-alex.session.json",
                      "sample": True}],
        "files": files,
        "csvContracts": [{"name": "points", "version": 1}, {"name": "stats", "version": 1}],
        "contact": "hello@islanddevcrew.com",
    }


def archive_manifest(sample_dir: Path, session: dict) -> dict:
    facts = _file_facts(sample_dir / "jon-vs-alex.session.json")
    return {
        "schemaVersion": "1.0.0", "kind": "jovra.archiveManifest", "sessionId": session["id"],
        "provider": "googleDrive", "scope": "https://www.googleapis.com/auth/drive.file",
        "createdAt": T0, "updatedAt": T0, "sample": True, "spaceSaver": False, "includesAudio": False,
        "remoteFolder": {"displayPath": "JOVRA/2026/2026-10-06 Jon vs Alex"},
        "files": [{
            "role": "sidecar", "localPath": "jon-vs-alex.session.json", "mimeType": "application/json",
            "bytes": facts["bytes"], "md5": facts["md5"], "sha256": facts["sha256"],
            "remote": {"name": "session.jovra.json", "fileId": "SAMPLE-not-a-drive-id-0001",
                       "appProperties": {"jovraSessionId": session["id"], "jovraRole": "sidecar"}},
            "upload": {"state": "sessionCreated", "lastConfirmedOffset": 0, "attempts": 1, "wifiOnly": True,
                       "resumable": {"secretRef": "keychain:jovra.drive.resumable.SAMPLE", "createdAt": T0},
                       "updatedAt": T0},
        }],
    }


def write(records_dir: Path, contracts_dir: Path, write_json, version) -> int:
    import json
    sample_dir = records_dir.parent / "sample"
    session = json.loads((sample_dir / "jon-vs-alex.session.json").read_text(encoding="utf-8"))
    write_json(contracts_dir / "capability-registry.v1.json", capability_registry())
    write_json(records_dir / "equipment.sample.json", equipment())
    write_json(records_dir / "practice-plan.sample.json", practice_plan(session))
    write_json(sample_dir / "export.json", export_manifest(sample_dir, session))
    write_json(sample_dir / "archive.json", archive_manifest(sample_dir, session))
    return 5
