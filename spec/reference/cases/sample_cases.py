"""The Jon vs Alex sample match fixture and the sample library (engine in jovra_ref.sample_match)."""

from __future__ import annotations

from jovra_ref import sample_match

from . import records, sample_media

ORDER = 40  # records (50) and the contract examples read the session file this writes


def generate(ctx) -> int:
    match = sample_match.write(ctx.fixtures / "sample", ctx.write_json, ctx.version)
    library = sample_match.write_library(ctx.fixtures / "sample" / "library", ctx.write_json,
                                         sample_media.manifest(), records.equipment())
    return match + library


def check_library(path, doc: dict, docs: dict) -> list[str]:
    """Re-run the library summary over the documents the fixture names; every one must be Sample and every media
    id must exist in the sample media manifest."""
    import json
    folder = path.parent
    load = lambda name: json.loads((folder / name).read_text(encoding="utf-8"))  # noqa: E731
    sessions = [load(name) for name in doc["sessionFiles"]]
    equipment, plan = load(doc["equipmentFile"]), load(doc["practicePlanFile"])
    manifest = load(doc["mediaManifest"])
    problems = []
    if sample_match.library_summary(sessions, equipment) != doc["expected"]:
        problems.append("library summary differs from the reference generator")
    known = {m["mediaId"] for m in manifest["media"]}
    for s in sessions:
        if s.get("sample", {}).get("label") != "Sample":
            problems.append(f"{s['title']}: not flagged Sample")
        problems += [f"{s['title']}: media id {m} is not in the manifest" for m in s["sample"].get("mediaIds", [])
                     if m not in known]
    if equipment.get("sample", {}).get("label") != "Sample" or plan.get("sample") is not True:
        problems.append("library equipment and practice plan must be flagged Sample")
    return problems


CHECKS = {"jovra.fixture.sampleLibrary": check_library}
