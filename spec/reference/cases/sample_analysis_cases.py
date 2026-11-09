"""The sample analysis content (T40): per-session overlays and the analysis oracle under spec/fixtures/sample/analysis
(engine in jovra_ref.sample_match, analysis section).

The check re-derives everything from the committed files, independently of the generator's own run: the overlays
apply cleanly to the shipped library sessions, the installed documents keep reference integrity, the summary over
them equals `expected`, every serve mark lies within 1 frame of the renderer's ground truth for its serve, and each
calibration re-projects the rendered pixels within CAMERA_TOLERANCE_PX.
"""

from __future__ import annotations

import json

from jovra_ref import references, sample_match

from . import records, sample_media

ORDER = 45  # after the library (40): the overlays are written against the library's sessions


def generate(ctx) -> int:
    return sample_match.write_analysis(ctx.fixtures / "sample" / "analysis", ctx.write_json, sample_media.manifest(),
                                       records.equipment(), sample_match.load_truths(ctx.spec))


def _truths(docs: dict) -> dict:
    return {d["id"].removeprefix("sample/"): d for d in docs.values()
            if d.get("kind") == "jovra.groundTruth" and d["id"].startswith("sample/")}


def serve_mark_truth_problems(installed: dict, truths: dict, manifest: dict) -> list[str]:
    """Every serve mark's contact and bounce frame lies within 1 frame of its rendered serve (matched in order)."""
    problems = []
    for doc in installed.values():
        marks = doc.get("serveMarks", [])
        if not marks:
            continue
        clip = next((m for m in manifest["media"] if m["sessionId"] == doc["id"] and m["role"] == "practiceClip"),
                    None)
        truth = truths.get(clip["mediaId"].removeprefix("sample-media.")) if clip else None
        if truth is None or len(truth.get("serves", [])) != len(marks):
            problems.append(f"{doc['title']}: {len(marks)} serve marks but no rendered clip with as many serves")
            continue
        fps = clip["frameRate"]["num"] // clip["frameRate"]["den"]
        base = clip["coversSessionMs"]["fromMs"] * fps // 1000
        for i, (mark, serve) in enumerate(zip(marks, truth["serves"])):
            for key, moment in (("contactFrame", "contact"), ("bounceFrame", "bounce")):
                t = mark.get(key)
                if t is None or t["timescale"] != fps:
                    problems.append(f"{doc['title']} serve mark {i + 1}: {key} is not on the {fps} fps clip")
                    continue
                off = t["value"] - base - serve[moment]["frame"]
                if abs(off) > 1:
                    problems.append(f"{doc['title']} serve mark {i + 1}: {key} is {off} frames from the rendered "
                                    f"{moment} (frame {serve[moment]['frame']})")
            if mark.get("servedTo") != serve["side"]:
                problems.append(f"{doc['title']} serve mark {i + 1}: servedTo {mark.get('servedTo')} but the serve "
                                f"went {serve['side']}")
    return problems


def check_analysis(path, doc: dict, docs: dict) -> list[str]:
    folder = path.parent
    load = lambda name: json.loads((folder / name).read_text(encoding="utf-8"))  # noqa: E731
    library = load(doc["libraryFixture"])
    library_folder = (folder / doc["libraryFixture"]).parent
    sessions = {s["id"]: s for s in (json.loads((library_folder / name).read_text(encoding="utf-8"))
                                     for name in library["sessionFiles"])}
    manifest = load(doc["mediaManifest"])
    problems = []
    installed = dict(sessions)
    for name in doc["analysisFiles"]:
        record = load(name)
        if record.get("sample", {}).get("label") != "Sample":
            problems.append(f"{name}: not flagged Sample")
        session = sessions.get(record["sessionId"])
        if session is None:
            problems.append(f"{name}: names no library session")
            continue
        try:
            installed[session["id"]] = sample_match.apply_analysis(installed[session["id"]], record)
        except AssertionError as exc:
            problems.append(f"{name}: does not apply to {session['title']}: {exc}")
    for d in installed.values():
        problems += [f"{d['title']} (installed): {p}" for p in references.session_problems(d, manifest)]
    if sample_match.analysis_summary(list(installed.values()), manifest) != doc["expected"]:
        problems.append("analysis summary differs from the reference generator")
    truths = _truths(docs)
    problems += serve_mark_truth_problems(installed, truths, manifest)
    for entry in doc["reference"]["calibrationTruth"]:
        cal = next((c for d in installed.values() for c in d.get("calibrations", []) if c["id"] == entry["calibrationId"]),
                   None)
        truth = truths.get(entry["truth"].removeprefix("sample/"))
        if cal is None or truth is None:
            problems.append(f"calibration {entry['calibrationId']}: no such calibration or truth")
            continue
        error = sample_match.calibration_error_px(cal, truth)
        if error > sample_match.CAMERA_TOLERANCE_PX:
            problems.append(f"calibration {entry['calibrationId']} is {error:.2f} px from the rendered pixels")
    oct4 = next((d for d in installed.values() if d.get("serveMarks")), None)
    if oct4 is not None and sample_match.serve_speed_reference(oct4, manifest) != doc["reference"]["serveSpeeds"]:
        problems.append("reference serve speeds differ from the estimator over the installed marks")
    return problems


CHECKS = {"jovra.fixture.sampleAnalysis": check_analysis}
