#!/usr/bin/env python3
"""Contract-completion tests (ticket T02). Standard library only.

Run from the repo root:  python3 -m unittest discover -s scripts/spec -p 'test_*.py' -v

The seams under test are the two command-line tools both platforms rely on (the fixture generator and the
validator) and the contract files they produce. Expected values come from the ticket and the screen spec
(docs/spec/tickets.json T02, docs/spec/screens.md §0.6), never from the code under test.
"""

from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "spec"
sys.path.insert(0, str(Path(__file__).resolve().parent))

from jsonschema_subset import SchemaSet  # noqa: E402

GENERATOR = Path("spec/reference/generate_fixtures.py")
VALIDATOR = Path("scripts/spec/validate.py")

# Capability statuses on main before T02 (spec/contracts/capability-registry.v1.json at eb99384).
STATUSES_BEFORE_T02 = {
    "scoring.manual": "manual",
    "points.review": "manual",
    "checkpoint.autofill": "estimated",
    "audio.hitDetection": "disabled",
    "rally.segmentation": "disabled",
    "court.calibration": "manual",
    "camera.movedDetection": "disabled",
    "pose.overlay2d": "estimated",
    "serveSpeed.manualAssisted": "estimated",
    "shotPlacement.manual": "manual",
    "strokeClassification": "unsupported",
    "ballTrajectory": "unsupported",
    "bouncePlacement.auto": "unsupported",
    "pointOutcome.auto": "unsupported",
    "lineCalling": "unsupported",
    "spinRpm": "unsupported",
    "biomechanics3d": "unsupported",
    "stringBed.pitchCheck": "unsupported",
}

ALL_FIELDS_SESSION = SPEC / "fixtures/records/session.all-fields.json"
ALL_FIELDS_PLAN = SPEC / "fixtures/records/practice-plan.all-fields.json"
ALL_FIELDS_EXPORT = SPEC / "fixtures/records/export.all-fields.json"
ALL_FIELDS_ARCHIVE = SPEC / "fixtures/records/archive.all-fields.json"
MEDIA_MANIFEST = SPEC / "fixtures/sample/media-manifest.json"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def run(tool: Path, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(tool)], cwd=cwd, capture_output=True, text=True)


def objects(node, path="$"):
    """(json path, object) for every object in a document."""
    if isinstance(node, dict):
        yield path, node
        for key, value in node.items():
            yield from objects(value, f"{path}.{key}")
    elif isinstance(node, list):
        for i, value in enumerate(node):
            yield from objects(value, f"{path}[{i}]")


def closed_object_mutations(doc: dict):
    """Yield (json path, mutated copy) with an unknown property added to that one object."""
    for path, _ in list(objects(doc)):
        mutated = copy.deepcopy(doc)
        dict(objects(mutated))[path]["unexpectedProperty"] = True
        yield path, mutated


class SchemasFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schemas = SchemaSet(SPEC / "schemas")

    def errors(self, doc: dict, schema: str) -> list[str]:
        return self.schemas.validate(doc, schema)


class CapabilityRegistryTests(SchemasFixture):
    def test_registry_preseeds_lineSnap_and_faceBlur_disabled_and_changes_no_other_status(self):
        registry = load(SPEC / "contracts/capability-registry.v1.json")
        self.assertEqual(self.errors(registry, "capability-registry.schema.json"), [])
        statuses = {c["id"]: c["status"] for c in registry["capabilities"]}
        self.assertEqual(statuses.pop("lineSnap"), "disabled")
        self.assertEqual(statuses.pop("faceBlur"), "disabled")
        self.assertEqual(statuses, STATUSES_BEFORE_T02)

    def test_faceBlur_is_ungated_so_it_can_become_estimated_without_a_record_and_lineSnap_is_gated(self):
        caps = {c["id"]: c for c in load(SPEC / "contracts/capability-registry.v1.json")["capabilities"]}
        self.assertIsNone(caps["faceBlur"]["gate"])  # T39: estimated + 'Not benchmarked' with no record
        self.assertIsNotNone(caps["lineSnap"]["gate"])  # T11/T35: gated floor, disabled until a record passes
        self.assertIsNone(caps["lineSnap"]["lastBenchmark"])
        self.assertIsNone(caps["faceBlur"]["lastBenchmark"])


class SessionSchemaTests(SchemasFixture):
    def test_a_schemaVersion_1_0_0_document_still_validates_after_the_minor_bump(self):
        session = load(SPEC / "fixtures/sample/jon-vs-alex.session.json")
        self.assertEqual(session["schemaVersion"], "1.0.0")
        self.assertEqual(self.errors(session, "session.schema.json"), [])

    def test_the_document_with_every_new_optional_field_validates_at_1_1_0(self):
        doc = load(ALL_FIELDS_SESSION)
        self.assertEqual(doc["schemaVersion"], "1.1.0")
        self.assertEqual(self.errors(doc, "session.schema.json"), [])

    def test_the_all_fields_document_carries_every_field_the_ticket_lists(self):
        doc = load(ALL_FIELDS_SESSION)
        rally = doc["rallyPlayback"]
        self.assertIn("preRollMs", rally)  # per session
        self.assertIn("postRollMs", rally)
        self.assertTrue(any("preRollMs" in c and "postRollMs" in c for c in rally["clips"]))  # per clip
        self.assertIn(doc["analysis"]["excludedSide"], ("left", "right"))
        kinds = {s["kind"] for s in doc["swings"]}
        self.assertEqual(kinds, {"serve", "stroke"})  # serve and stroke key moments
        self.assertTrue(all(s["keyMoments"] for s in doc["swings"]))
        mark = doc["serveMarks"][0]
        for field in ("contactFrame", "bounceFrame", "bounceCourt", "serverPosition", "contactDefaulted"):
            self.assertIn(field, mark)
        self.assertTrue(any("shotIndex" in s and "stroke" in s for s in doc["shots"]))  # per-shot stroke tag
        self.assertTrue(all("eventLogVersion" in e for e in doc["exports"]))
        consent = doc["consent"]
        self.assertTrue(consent["juniorPlayerIds"])
        self.assertIn("attachment", consent["writtenConsents"][0])
        self.assertIn("withdrawnAt", consent)
        self.assertTrue(any("staleFromMs" in c for c in doc["calibrations"]))
        self.assertTrue(any(m.get("note") for m in doc["marks"]))  # bookmark note (existing field, reused)

    def test_an_unknown_property_inside_any_closed_object_fails(self):
        for path, schema in ((ALL_FIELDS_SESSION, "session.schema.json"),
                             (ALL_FIELDS_PLAN, "practice-plan.schema.json"),
                             (ALL_FIELDS_EXPORT, "export.schema.json"),
                             (ALL_FIELDS_ARCHIVE, "archive-manifest.schema.json")):
            doc = load(path)
            checked = 0
            for where, mutated in closed_object_mutations(doc):
                with self.subTest(file=path.name, object=where):
                    self.assertNotEqual(self.errors(mutated, schema), [], f"{where} accepted an unknown property")
                checked += 1
            self.assertGreaterEqual(checked, 5)

    def test_practice_plan_gains_drill_session_logs_and_dated_goals(self):
        plan = load(ALL_FIELDS_PLAN)
        self.assertEqual(self.errors(plan, "practice-plan.schema.json"), [])
        log = plan["drillLogs"][0]
        self.assertIn("tally", log)
        self.assertIn("setsCompleted", log)
        goal = plan["goals"][0]
        self.assertIn("targetDate", goal)
        self.assertIn("window", goal)

    def test_archive_manifest_accepts_the_rally_only_copy_role(self):
        archive = load(ALL_FIELDS_ARCHIVE)
        self.assertEqual(self.errors(archive, "archive-manifest.schema.json"), [])
        roles = [f["role"] for f in archive["files"]]
        self.assertIn("rallyOnlyCopy", roles)

    def test_export_manifest_records_the_event_log_version_per_session(self):
        export = load(ALL_FIELDS_EXPORT)
        self.assertEqual(self.errors(export, "export.schema.json"), [])
        self.assertTrue(all(isinstance(s["eventLogVersion"], int) for s in export["sessions"]))


class SampleMediaManifestTests(SchemasFixture):
    def test_manifest_validates_and_lists_eight_sessions_plus_three_practice_clips(self):
        manifest = load(MEDIA_MANIFEST)
        self.assertEqual(manifest["kind"], "jovra.sampleMediaManifest")
        self.assertEqual(self.errors(manifest, "sample-media-manifest.schema.json"), [])
        session_entries = [m for m in manifest["media"] if m["role"] == "sessionVideo"]
        clips = [m for m in manifest["media"] if m["role"] == "practiceClip"]
        self.assertEqual(len(manifest["media"]), 11)
        self.assertEqual(len(session_entries), 8)
        self.assertEqual(len({m["sessionId"] for m in session_entries}), 8)
        # screens.md §0.6: Jon vs Alex (Oct 6), Serve practice (Oct 4), Forehand session (Oct 2), 5 older sessions
        dates = sorted(m["sessionDate"] for m in session_entries)
        self.assertEqual(dates[-3:], ["2026-10-02", "2026-10-04", "2026-10-06"])
        self.assertTrue(all("2026-09-09" <= d < "2026-10-02" for d in dates[:5]))
        self.assertEqual(sorted((c["sessionDate"], c["angle"]) for c in clips),
                         [("2026-09-28", "behindBaseline"), ("2026-10-02", "sideOn"), ("2026-10-04", "behindBaseline")])

    def test_jon_vs_alex_entry_names_the_sample_session_and_its_54_minute_60_fps_video(self):
        manifest = load(MEDIA_MANIFEST)
        session = load(SPEC / "fixtures/sample/jon-vs-alex.session.json")
        entry = next(m for m in manifest["media"] if m["sessionDate"] == "2026-10-06" and m["role"] == "sessionVideo")
        self.assertEqual(entry["sessionId"], session["id"])
        self.assertEqual(entry["durationMs"], 3_240_000)  # 54:00 (screens.md §0.6)
        self.assertEqual(entry["frameRate"], {"num": 60, "den": 1})  # FrameReadout "60 fps" (S10)

    def test_media_ids_and_file_names_are_unique(self):
        media = load(MEDIA_MANIFEST)["media"]
        self.assertEqual(len({m["mediaId"] for m in media}), len(media))
        self.assertEqual(len({m["fileName"] for m in media}), len(media))


class PlumbingByConventionTests(unittest.TestCase):
    """Adding a fixture kind means adding files (cases module + schema), never editing a shared list."""

    PROBE_CASES = '''"""Temporary probe fixture kind used only by the T02 convention test."""

ORDER = 900


def generate(ctx) -> int:
    ctx.write_json(ctx.fixtures / "probe" / "P01-probe.json",
                   {"schemaVersion": "1.0.0", "kind": "jovra.fixture.probe", "id": "P01", "value": 3})
    return 1
'''
    PROBE_SCHEMA = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "probe",
        "type": "object",
        "required": ["schemaVersion", "kind", "id", "value"],
        "additionalProperties": False,
        "properties": {
            "schemaVersion": {"$ref": "common.schema.json#/$defs/schemaVersion"},
            "kind": {"const": "jovra.fixture.probe"},
            "id": {"type": "string"},
            "value": {"type": "integer"},
        },
    }

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="jovra-t02-"))
        shutil.copytree(SPEC, self.tmp / "spec", ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copytree(ROOT / "scripts/spec", self.tmp / "scripts/spec", ignore=shutil.ignore_patterns("__pycache__"))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_new_kind_generates_and_validates_with_no_shared_edit_and_fails_without_its_schema(self):
        (self.tmp / "spec/reference/cases/probe_cases.py").write_text(self.PROBE_CASES, encoding="utf-8")
        probe_schema = self.tmp / "spec/schemas/fixture-probe.schema.json"
        probe_schema.write_text(json.dumps(self.PROBE_SCHEMA), encoding="utf-8")
        gen = run(GENERATOR, self.tmp)
        self.assertEqual(gen.returncode, 0, gen.stdout + gen.stderr)
        self.assertTrue((self.tmp / "spec/fixtures/probe/P01-probe.json").exists())
        ok = run(VALIDATOR, self.tmp)
        self.assertEqual(ok.returncode, 0, ok.stdout)
        self.assertIn("RESULT: PASS", ok.stdout)
        probe_schema.unlink()
        bad = run(VALIDATOR, self.tmp)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn("spec/fixtures/probe/P01-probe.json: no schema fixture-probe.schema.json for kind "
                      "'jovra.fixture.probe'", bad.stdout)

    def test_a_schema_whose_kind_const_disagrees_with_its_file_name_is_rejected(self):
        schema = dict(self.PROBE_SCHEMA, properties=dict(self.PROBE_SCHEMA["properties"],
                                                         kind={"const": "jovra.fixture.other"}))
        (self.tmp / "spec/schemas/fixture-probe.schema.json").write_text(json.dumps(schema), encoding="utf-8")
        bad = run(VALIDATOR, self.tmp)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn("fixture-probe.schema.json declares kind 'jovra.fixture.other'", bad.stdout)

    def test_generator_rewrites_every_committed_fixture_byte_for_byte(self):
        gen = run(GENERATOR, self.tmp)
        self.assertEqual(gen.returncode, 0, gen.stdout + gen.stderr)
        for folder in ("fixtures", "contracts"):
            for path in sorted((SPEC / folder).rglob("*")):
                if path.is_file():
                    copy_path = self.tmp / "spec" / folder / path.relative_to(SPEC / folder)
                    with self.subTest(file=str(path.relative_to(ROOT))):
                        self.assertEqual(copy_path.read_bytes(), path.read_bytes())


class ValidatorTests(unittest.TestCase):
    def test_validator_passes_on_the_repository(self):
        result = run(VALIDATOR, ROOT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("RESULT: PASS", result.stdout)
        self.assertIn("closed-object rejections", result.stdout)


if __name__ == "__main__":
    unittest.main()
