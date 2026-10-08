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
sys.path.insert(0, str(SPEC / "reference"))

from jsonschema_subset import SchemaSet, ecma_pattern  # noqa: E402

from jovra_ref import references  # noqa: E402

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


class PatternAnchorTests(SchemasFixture):
    """JSON Schema 2020-12 'pattern' is ECMA-262: '$' is the end of the input, never 'before a final newline'."""

    def test_a_session_id_or_timestamp_ending_in_a_newline_is_rejected(self):
        session = load(ALL_FIELDS_SESSION)
        for field in ("id", "createdAt"):
            with self.subTest(field=field):
                bad = dict(session, **{field: session[field] + "\n"})
                self.assertNotEqual(self.errors(bad, "session.schema.json"), [])

    def test_dollar_becomes_end_of_input_except_when_escaped_or_inside_a_class(self):
        self.assertEqual(ecma_pattern("^a$"), "^a\\Z")
        self.assertEqual(ecma_pattern("^[$]\\$$"), "^[$]\\$\\Z")
        self.assertEqual(ecma_pattern("^(x|y$)$"), "^(x|y\\Z)\\Z")

    def test_a_schema_using_a_class_escape_whose_meaning_differs_from_ecma_is_refused(self):
        schemas = SchemaSet(SPEC / "schemas")
        schemas.files["probe.schema.json"] = {"type": "string", "pattern": "^\\d+$"}
        self.assertTrue(any("probe.schema.json" in p and "\\d" in p for p in schemas.check_all()))


def session_problems(doc: dict) -> list[str]:
    return references.session_problems(doc, load(MEDIA_MANIFEST))


class SessionReferenceTests(unittest.TestCase):
    """Every id a 1.1 field holds must name a record that exists (verifier round 1, finding 4)."""

    def mutated(self, mutate) -> dict:
        doc = load(ALL_FIELDS_SESSION)
        mutate(doc)
        return doc

    def test_the_contract_example_has_no_dangling_reference(self):
        self.assertEqual(session_problems(load(ALL_FIELDS_SESSION)), [])

    def test_each_dangling_reference_or_inverted_range_is_reported(self):
        mutations = {
            "junior player": lambda d: d["consent"].update(juniorPlayerIds=["nobody"]),
            "written consent player": lambda d: d["consent"]["writtenConsents"][0].update(coversPlayerIds=["nobody"]),
            "serve mark calibration": lambda d: d["serveMarks"][0].update(calibrationId="nope"),
            "serve mark point": lambda d: d["serveMarks"][0].update(pointId="nope"),
            "serve mark shot": lambda d: d["serveMarks"][0].update(shotId="nope"),
            "swing serve mark": lambda d: d["swings"][0].update(serveMarkId="nope"),
            "swing shot": lambda d: d["swings"][1].update(shotId="nope"),
            "swing mark": lambda d: d["swings"][1].update(markId="nope"),
            "rally clip target": lambda d: d["rallyPlayback"]["clips"][0].update(targetId="nope"),
            "rally clip duplicate target": lambda d: d["rallyPlayback"]["clips"].append(
                {"targetId": "ex-point-1", "preRollMs": 0}),
            "export log version": lambda d: d["exports"][0].update(eventLogVersion=7),
            "export point": lambda d: d["exports"][0].update(pointIds=["nope"]),
            "export range": lambda d: d["exports"][0].update(range={"fromMs": 40_000, "toMs": 26_500}),
            "swing clip range": lambda d: d["swings"][0].update(clip={"fromMs": 2, "toMs": 1}),
            "shot point": lambda d: d["shots"][0].update(pointId="nope"),
            "shot hitter": lambda d: d["shots"][0].update(hitter="nobody"),
            "placement calibration": lambda d: d["shots"][1]["placement"].update(calibrationId="nope"),
            "derived value scope": lambda d: d["derivedValues"][0]["scope"].update(serveMarkId="nope"),
            "derived value calibration": lambda d: d["derivedValues"][0]["provenance"].update(calibrationId="nope"),
            "truncated segment": lambda d: d["recording"]["recovery"].update(truncatedSegmentIds=["nope"]),
            "sample media id": lambda d: d["sample"].update(mediaIds=["sample-media.nope"]),
        }
        for label, mutate in mutations.items():
            with self.subTest(mutation=label):
                self.assertNotEqual(session_problems(self.mutated(mutate)), [], label)

    def test_an_empty_range_is_allowed(self):
        doc = self.mutated(lambda d: d["exports"][0].update(range={"fromMs": 5, "toMs": 5}))
        self.assertEqual(session_problems(doc), [])

    def test_a_session_without_a_log_has_event_log_version_zero(self):
        doc = self.mutated(lambda d: d.pop("match"))
        doc["exports"] = [dict(doc["exports"][0], eventLogVersion=0, pointIds=[])]
        doc.pop("serveMarks"), doc.pop("swings"), doc.pop("derivedValues"), doc.pop("rallyPlayback")
        for shot in doc["shots"]:
            shot.pop("pointId")
        self.assertEqual(session_problems(doc), [])
        doc["exports"][0]["eventLogVersion"] = 1
        self.assertNotEqual(session_problems(doc), [])


class SampleMediaReferenceTests(unittest.TestCase):
    """T09: 'Every media id in the installed sessions exists in the sample media manifest'."""

    def test_the_session_schema_has_a_place_for_sample_media_ids(self):
        sample_info = load(SPEC / "schemas/session.schema.json")["$defs"]["sampleInfo"]
        self.assertIn("mediaIds", sample_info["properties"])
        self.assertNotIn("mediaIds", sample_info["required"])

    def test_the_contract_example_references_media_that_exist_in_the_manifest(self):
        ids = load(ALL_FIELDS_SESSION)["sample"]["mediaIds"]
        known = {m["mediaId"] for m in load(MEDIA_MANIFEST)["media"]}
        self.assertTrue(ids)
        self.assertLessEqual(set(ids), known)

    def test_a_manifest_session_may_only_reference_its_own_media(self):
        manifest = load(MEDIA_MANIFEST)
        jon_vs_alex = load(SPEC / "fixtures/sample/jon-vs-alex.session.json")
        own = next(m["mediaId"] for m in manifest["media"] if m["sessionId"] == jon_vs_alex["id"])
        other = next(m["mediaId"] for m in manifest["media"] if m["sessionId"] != jon_vs_alex["id"])
        doc = copy.deepcopy(jon_vs_alex)
        doc["sample"]["mediaIds"] = [own]
        self.assertEqual(references.session_problems(doc, manifest), [])
        doc["sample"]["mediaIds"] = [other]
        self.assertNotEqual(references.session_problems(doc, manifest), [])


class ServeSpeedExampleTests(unittest.TestCase):
    """Hard rule 1: the example's speed is computed from its own serve mark (verifier round 1, finding 3)."""

    def test_defaulted_contact_sits_on_the_centre_mark_of_the_servers_baseline(self):
        mark = load(ALL_FIELDS_SESSION)["serveMarks"][0]
        self.assertTrue(mark["contactDefaulted"])
        self.assertEqual(mark["serverPosition"], {"x": 0, "y": -11.885})  # near baseline (toss: A starts near)

    def test_the_estimate_is_the_ground_distance_over_the_flight_time(self):
        doc = load(ALL_FIELDS_SESSION)
        mark = doc["serveMarks"][0]
        speed = next(v for v in doc["derivedValues"] if v["scope"].get("serveMarkId") == mark["id"])
        # by hand: (0, -11.885) -> (-2.4, 5.1) is sqrt(2.4^2 + 16.985^2) = 17.154 m; frames 1830 -> 1854 at 60 fps
        # are 0.400 s; 42.885 m/s / 0.44704 = 95.93 mph, shown as 96.
        self.assertEqual((speed["value"], speed["unit"]), (96, "mph"))
        self.assertEqual(references.serve_speed_mph(mark), 96)

    def test_a_typed_speed_that_disagrees_with_the_mark_is_reported(self):
        doc = load(ALL_FIELDS_SESSION)
        doc["derivedValues"][0]["value"] = 104
        self.assertTrue(any("serve" in p and "104" in p for p in session_problems(doc)))
        doc = load(ALL_FIELDS_SESSION)
        doc["serveMarks"][0]["serverPosition"] = {"x": 0.3, "y": -11.885}
        self.assertTrue(any("contactDefaulted" in p for p in session_problems(doc)))


class PracticePlanAndManifestReferenceTests(unittest.TestCase):
    def test_drill_logs_must_name_an_item_and_goals_of_their_plan(self):
        plan = load(ALL_FIELDS_PLAN)
        self.assertEqual(references.practice_plan_problems(plan), [])
        bad = copy.deepcopy(plan)
        bad["drillLogs"][0]["itemId"] = "nope"
        self.assertNotEqual(references.practice_plan_problems(bad), [])
        bad = copy.deepcopy(plan)
        bad["drillLogs"][0]["goalIds"] = ["nope"]
        self.assertNotEqual(references.practice_plan_problems(bad), [])

    def test_an_export_cannot_claim_a_log_version_its_session_never_had(self):
        export = load(ALL_FIELDS_EXPORT)
        sessions = {s["id"]: s for s in (load(ALL_FIELDS_SESSION),)}
        self.assertEqual(references.export_problems(export, sessions), [])
        export["sessions"][0]["eventLogVersion"] = 99
        self.assertNotEqual(references.export_problems(export, sessions), [])

    def test_validator_fails_a_tree_whose_session_points_at_a_missing_calibration(self):
        tmp = Path(tempfile.mkdtemp(prefix="jovra-t02-ref-"))
        try:
            shutil.copytree(SPEC, tmp / "spec", ignore=shutil.ignore_patterns("__pycache__"))
            shutil.copytree(ROOT / "scripts/spec", tmp / "scripts/spec", ignore=shutil.ignore_patterns("__pycache__"))
            path = tmp / "spec/fixtures/records/session.all-fields.json"
            doc = load(path)
            doc["serveMarks"][0]["calibrationId"] = "nope"
            path.write_text(json.dumps(doc), encoding="utf-8")
            result = run(VALIDATOR, tmp)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("serveMarks[0].calibrationId 'nope'", result.stdout)
        finally:
            shutil.rmtree(tmp)


def frame_ms(value: int, timescale: int) -> float:
    return value * 1000 / timescale


class ServeSpeedContractTests(SchemasFixture):
    """Hard rule 1: a serve speed is computed from its mark in any unit, never typed (verifier round 2, finding 1),
    and it carries its range (finding 4: screens.md S12 '104 mph (94–114)', ±10%, ±15% below 60 fps)."""

    def speed(self, doc: dict) -> dict:
        return next(v for v in doc["derivedValues"] if v["key"] == "serveSpeed.estimate")

    def both(self, mutate) -> tuple[list[str], list[str]]:
        doc = load(ALL_FIELDS_SESSION)
        mutate(doc)
        return self.errors(doc, "session.schema.json"), session_problems(doc)

    def test_a_typed_km_per_hour_value_is_reported(self):
        def typed(d):
            self.speed(d).update(unit="km/h", value=999, range={"low": 899, "high": 1099, "pct": 10})
        _, problems = self.both(typed)
        self.assertTrue(any("999" in p for p in problems), problems)

    def test_the_km_per_hour_value_is_recomputed_through_the_exact_factor(self):
        # by hand: 17.1537 m / 0.400 s = 42.884 m/s x 3.6 = 154.38 km/h -> 154; ±10% = 138.6 -> 139, 169.4 -> 169
        def converted(d):
            self.speed(d).update(unit="km/h", value=154, range={"low": 139, "high": 169, "pct": 10})
        errors, problems = self.both(converted)
        self.assertEqual((errors, problems), ([], []))

    def test_a_speed_without_its_serve_mark_or_calibration_fails_schema_and_references(self):
        def no_mark(d):
            self.speed(d)["scope"].pop("serveMarkId")
            self.speed(d).update(value=150)
        def no_calibration(d):
            self.speed(d)["provenance"].pop("calibrationId")
        def no_range(d):
            self.speed(d).pop("range")
        for label, mutate in (("no serve mark", no_mark), ("no calibration", no_calibration), ("no range", no_range)):
            with self.subTest(label):
                errors, problems = self.both(mutate)
                self.assertNotEqual(errors, [], label)
                self.assertNotEqual(problems, [], label)

    def test_any_other_unit_is_rejected(self):
        errors, problems = self.both(lambda d: self.speed(d).update(unit="m/s"))
        self.assertNotEqual(errors, [])
        self.assertNotEqual(problems, [])

    def test_the_calibration_must_be_the_marks_own(self):
        def other(d):
            d["calibrations"].append(dict(d["calibrations"][0], id="ex-calibration-2"))
            self.speed(d)["provenance"]["calibrationId"] = "ex-calibration-2"
        self.assertTrue(any("calibration" in p for p in self.both(other)[1]))

    def test_the_example_stores_its_range(self):
        # 96 mph ±10% (60 fps at contact): 86.4 -> 86, 105.6 -> 106. The S12 demo: 104 -> 93.6 -> 94, 114.4 -> 114.
        self.assertEqual(self.speed(load(ALL_FIELDS_SESSION))["range"], {"low": 86, "high": 106, "pct": 10})
        self.assertEqual(references.estimate_range(104, 10), {"low": 94, "high": 114, "pct": 10})

    def test_a_wrong_range_or_a_low_frame_rate_range_is_reported(self):
        wrong = lambda d: self.speed(d)["range"].update(low=90)
        slow = lambda d: d["recording"]["segments"][0].update(frameRate={"num": 30, "den": 1})
        for label, mutate in (("wrong low", wrong), ("30 fps at contact needs ±15%", slow)):
            with self.subTest(label):
                self.assertTrue(any("range" in p for p in self.both(mutate)[1]), label)


class CaptureEventTests(SchemasFixture):
    """Story 99 / T25: the metadata records the change itself (verifier round 2, finding 5)."""

    def test_a_frame_rate_change_needs_its_frame_rate_and_a_thermal_event_its_state(self):
        for kind, field in (("frameRateChange", "frameRate"), ("thermalState", "thermalState")):
            with self.subTest(kind):
                doc = load(ALL_FIELDS_SESSION)
                event = next(e for e in doc["recording"]["captureEvents"] if e["kind"] == kind)
                self.assertEqual(self.errors(doc, "session.schema.json"), [])
                event.pop(field)
                self.assertNotEqual(self.errors(doc, "session.schema.json"), [])


class ParentIdTests(unittest.TestCase):
    """Point parentIds (1.1.0) resolve: an earlier, voided point other than itself (verifier round 2, finding 2)."""

    def problems(self, parents: list[str], index: int = 4) -> list[str]:
        doc = load(ALL_FIELDS_SESSION)
        doc["match"]["log"][index]["parentIds"] = parents
        return session_problems(doc)

    def test_the_example_split_resolves(self):
        self.assertEqual(self.problems(["ex-point-3"]), [])

    def test_a_dangling_self_later_or_unvoided_parent_is_reported(self):
        cases = {"missing": ["nope-123"], "itself": ["ex-point-3a"], "later point": ["ex-point-3b"],
                 "not voided": ["ex-point-1"], "not a point": ["ex-void-3"]}
        for label, parents in cases.items():
            with self.subTest(label):
                self.assertNotEqual(self.problems(parents), [], label)


class ConsentConsistencyTests(unittest.TestCase):
    """Verifier round 2, finding 7."""

    def test_juniors_mean_consent_is_required(self):
        doc = load(ALL_FIELDS_SESSION)
        doc["consent"]["status"] = "notRequired"
        doc["consent"].pop("writtenConsents")
        self.assertTrue(any("notRequired" in p for p in session_problems(doc)))

    def test_consent_is_not_withdrawn_before_it_was_attached(self):
        doc = load(ALL_FIELDS_SESSION)
        doc["consent"]["withdrawnAt"] = "2020-01-01T00:00:00Z"
        self.assertTrue(any("withdrawnAt" in p for p in session_problems(doc)))


class RecordingBoundsTests(unittest.TestCase):
    """1.1 times fall inside the recording (verifier round 2, finding 8). The example records 600,000 ms."""

    def test_each_time_past_the_recording_or_outside_its_clip_is_reported(self):
        mutations = {
            "key moment past the end": lambda d: d["swings"][0]["keyMoments"][0].update(
                time={"value": 999_999, "timescale": 60}),
            "key moment outside its swing clip": lambda d: d["swings"][0]["keyMoments"][0].update(
                time={"value": 60, "timescale": 60}),
            "stale calibration past the end": lambda d: d["calibrations"][0].update(staleFromMs=99_999_999),
            "capture event past the end": lambda d: d["recording"]["captureEvents"][0].update(tMs=600_001),
            "export range past the end": lambda d: d["exports"][0].update(range={"fromMs": 0, "toMs": 600_001}),
            "rally target mark past the end": lambda d: d["marks"][0].update(tMs=600_001),
            "rally target point past the end": lambda d: d["match"]["log"][0].update(tEndMs=600_001),
            "serve mark bounce past the end": lambda d: d["serveMarks"][0].update(
                bounceFrame={"value": 36_001, "timescale": 60}),
            "swing clip past the end": lambda d: d["swings"][1].update(clip={"fromMs": 30_400, "toMs": 600_001}),
        }
        self.assertEqual(session_problems(load(ALL_FIELDS_SESSION)), [])
        for label, mutate in mutations.items():
            with self.subTest(label):
                doc = load(ALL_FIELDS_SESSION)
                mutate(doc)
                self.assertNotEqual(session_problems(doc), [], label)

    def test_every_key_moment_of_the_example_sits_inside_its_swing_clip(self):
        for swing in load(ALL_FIELDS_SESSION)["swings"]:
            for moment in swing["keyMoments"]:
                t = frame_ms(moment["time"]["value"], moment["time"]["timescale"])
                self.assertTrue(swing["clip"]["fromMs"] <= t <= swing["clip"]["toMs"], (swing["id"], moment))


class OriginalFacetTests(SchemasFixture):
    """ios-v1-spec SessionStore: four independent facets, original among them (verifier round 2, finding 9)."""

    STATES = ["recording", "recovering", "saved", "savedWithGaps", "partial", "importing", "archiveOnly", "missing",
              "trashed"]

    def test_the_original_facet_takes_exactly_the_spec_states(self):
        original = load(SPEC / "schemas/session.schema.json")["$defs"]["originalState"]
        self.assertEqual(original["properties"]["state"]["enum"], self.STATES)

    def test_the_example_records_a_partial_recovery_on_the_original_facet(self):
        doc = load(ALL_FIELDS_SESSION)
        self.assertEqual(doc["original"]["state"], "partial")  # T16: an unrecoverable segment -> partial
        doc["original"]["state"] = "lost"
        self.assertNotEqual(self.errors(doc, "session.schema.json"), [])


def since_paths(doc, schemas: SchemaSet, schema_file: str) -> set[str]:
    """Instance paths of every property whose schema says 'Since 1.1.0' (on the property, its $ref or its items)."""
    found = set()

    def resolved(node, file):
        while isinstance(node, dict) and "$ref" in node:
            node, file = schemas.resolve(node["$ref"], file)
        return node, file

    def is_new(node, file) -> bool:
        nodes = [node]
        target, target_file = resolved(node, file)
        nodes.append(target)
        if isinstance(target, dict) and "items" in target:
            nodes.append(resolved(target["items"], target_file)[0])
        return any(isinstance(n, dict) and n.get("description", "").startswith("Since 1.1.0") for n in nodes)

    def branches(node, file):
        node, file = resolved(node, file)
        if not isinstance(node, dict):
            return
        yield node, file
        for key in ("allOf", "anyOf", "oneOf"):
            for sub in node.get(key, []):
                yield from branches(sub, file)

    def walk(value, node, file, path):
        for branch, bfile in branches(node, file):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key in branch.get("properties", {}):
                        sub = branch["properties"][key]
                        if is_new(sub, bfile):
                            found.add(f"{path}.{key}")
                        walk(item, sub, bfile, f"{path}.{key}")
            elif isinstance(value, list) and "items" in branch:
                for i, item in enumerate(value):
                    walk(item, branch["items"], bfile, f"{path}[{i}]")

    walk(doc, schemas.files[schema_file], schema_file, "$")
    return found


class SchemaVersionGateTests(SchemasFixture):
    """A document stamped 1.0.x carries nothing added in 1.1.0 (verifier round 2, finding 3)."""

    DOCS = ((ALL_FIELDS_SESSION, "session.schema.json"), (ALL_FIELDS_PLAN, "practice-plan.schema.json"),
            (ALL_FIELDS_EXPORT, "export.schema.json"), (ALL_FIELDS_ARCHIVE, "archive-manifest.schema.json"))

    def test_every_all_fields_example_fails_when_stamped_1_0_0(self):
        for path, schema in self.DOCS:
            with self.subTest(path.name):
                doc = dict(load(path), schemaVersion="1.0.0")
                self.assertNotEqual(self.errors(doc, schema), [])

    def test_every_since_1_1_field_is_named_by_the_1_0_rejection(self):
        for path, schema in self.DOCS:
            doc = dict(load(path), schemaVersion="1.0.0")
            errors = self.errors(doc, schema)
            new = since_paths(doc, self.schemas, schema)
            self.assertGreaterEqual(len(new), 1, path.name)
            for where in sorted(new):
                with self.subTest(file=path.name, field=where):
                    self.assertTrue(any(e.startswith(where + ":") or e.startswith(where + ".")
                                        or e.startswith(where + "[") or where.startswith(e.split(":")[0] + ".")
                                        or where.startswith(e.split(":")[0] + "[") for e in errors),
                                    f"{where} is accepted in a 1.0.0 document")

    def test_values_added_to_1_0_enums_are_rejected_in_a_1_0_document(self):
        session = load(SPEC / "fixtures/sample/jon-vs-alex.session.json")
        archive = load(SPEC / "fixtures/sample/archive.json")
        export = load(SPEC / "fixtures/sample/export.json")
        cases = [
            (session, "session.schema.json", lambda d: d["analysis"].update(state="paused")),
            (session, "session.schema.json", lambda d: d["analysis"].update(state="unavailable")),
            (session, "session.schema.json", lambda d: d["archive"].update(state="waitingForWiFi")),
            (archive, "archive-manifest.schema.json", lambda d: d["files"][0].update(role="rallyOnlyCopy")),
            (archive, "archive-manifest.schema.json", lambda d: d["files"][0]["upload"].update(state="cancelled")),
            (archive, "archive-manifest.schema.json",
             lambda d: d["files"][0]["upload"].update(state="waitingForNetwork")),
            (export, "export.schema.json", lambda d: d["files"][0].update(role="viewerHtml")),
            (export, "export.schema.json", lambda d: d["files"][0].update(role="condensedMatch")),
            (export, "export.schema.json", lambda d: d["files"][0].update(role="highlightReel")),
        ]
        for base, schema, mutate in cases:
            self.assertEqual(base["schemaVersion"], "1.0.0")
            doc = copy.deepcopy(base)
            mutate(doc)
            with self.subTest(schema=schema, doc=canon_short(doc, base)):
                self.assertNotEqual(self.errors(doc, schema), [])
                self.assertEqual(self.errors(dict(doc, schemaVersion="1.1.0"), schema), [])


def canon_short(doc: dict, base: dict) -> str:
    return next((f"{k}" for k in doc if doc[k] != base.get(k)), "")


class SampleMediaConsistencyTests(unittest.TestCase):
    """Entries for one session agree with its sessionVideo (verifier round 2, finding 10)."""

    def check(self, manifest: dict) -> list[str]:
        from cases import sample_media
        jon_vs_alex = SPEC / "fixtures/sample/jon-vs-alex.session.json"
        return sample_media.check_manifest(MEDIA_MANIFEST, manifest, {jon_vs_alex: load(jon_vs_alex)})

    def test_a_clip_whose_date_kind_or_angle_disagrees_with_its_session_video_is_reported(self):
        self.assertEqual(self.check(load(MEDIA_MANIFEST)), [])
        for field, value in (("sessionKind", "servePractice"), ("sessionDate", "2026-09-27"), ("angle", "sideOn")):
            with self.subTest(field):
                manifest = load(MEDIA_MANIFEST)
                clip = next(m for m in manifest["media"] if m["mediaId"] == "sample-media.2026-09-28-serve-clip")
                clip[field] = value
                self.assertTrue(any(field in p for p in self.check(manifest)), field)


class ValidatorTests(unittest.TestCase):
    def test_validator_passes_on_the_repository(self):
        result = run(VALIDATOR, ROOT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("RESULT: PASS", result.stdout)
        self.assertIn("closed-object rejections", result.stdout)


if __name__ == "__main__":
    unittest.main()
