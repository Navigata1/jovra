import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid

import yaml

from generate import generate

ROOT = Path(__file__).resolve().parents[3]
PROBE = Path("scripts/ios/replay-segment-menu")
MEDIA = Path("ios/Jovra/Resources/Fixtures/fixture-camera-720p30.mp4")
ENTRY = Path("ios/Jovra/App/JovraApp.swift")
PROJECT = Path("ios/project.yml")
SELECTOR = "JovraUITests/ReplaySegmentMenuUITests/testActualMenuOpensLaterSegmentAfterTheFirstIsUnavailable"


class GenerateProbeTests(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.scratch = Path(work.name).resolve()
        self.source = self.scratch / "source"
        self.source.mkdir()
        for relative in (MEDIA, ENTRY, PROJECT, PROBE / "AlternateApp.swift.in", PROBE / "ProbeCustody.swift",
                         PROBE / "segment-menu-fixture.json", PROBE / "ReplaySegmentMenuUITests.swift"):
            dest = self.source / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, dest)
        self.git("init", "--quiet")
        self.commit()
        self.output = self.scratch / "output"

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.source), *args], timeout=10)

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Probe Test", "-c", "user.email=probe@example.invalid",
                 "commit", "-qm", "synthetic input")

    def test_generates_only_the_isolated_app_and_one_test_target(self):
        result = generate(self.source, self.output)
        checkout = self.output / "checkout"
        config = yaml.safe_load((checkout / PROJECT).read_text())
        app, ui = (config["targets"][name] for name in ("Jovra", "JovraUITests"))
        token = uuid.UUID(result["token"])
        bundle = "com.islanddevcrew.jovra.menuprobe" + token.hex
        self.assertEqual(app["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"], bundle)
        self.assertEqual(ui["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"], bundle + ".uitests")
        self.assertEqual(config["settings"]["base"]["SUPPORTED_PLATFORMS"], "iphonesimulator")
        self.assertNotIn("entitlements", app)
        self.assertNotIn("CFBundleURLTypes", app["info"]["properties"])
        self.assertNotIn("NSBonjourServices", app["info"]["properties"])
        self.assertEqual(app["sources"][0]["excludes"], ["App/JovraApp.swift"])
        scheme = config["schemes"]["Jovra"]["test"]
        self.assertEqual(scheme["targets"], ["JovraUITests"])
        self.assertEqual(scheme["environmentVariables"], {"JOVRA_SEGMENT_MENU_PROBE_TOKEN": str(token)})
        self.assertEqual([s["path"] for s in ui["sources"] if s["path"].startswith("MenuProbe/")],
                         ["MenuProbe/ReplaySegmentMenuUITests.swift"])
        self.assertEqual(result["selector"], SELECTOR)
        self.assertEqual(result["head"], self.git("rev-parse", "HEAD").decode().strip())
        self.assertEqual((checkout / ENTRY).read_bytes(), (self.source / ENTRY).read_bytes())
        self.assertEqual((checkout / "ios/MenuProbe/ReplaySegmentMenuUITests.swift").read_bytes(),
                         (self.source / PROBE / "ReplaySegmentMenuUITests.swift").read_bytes())
        for relative, digest in result["files"].items():
            self.assertEqual(hashlib.sha256((checkout / relative).read_bytes()).hexdigest(), digest)
        self.assertEqual(json.loads((self.output / "probe-manifest.json").read_text()), result)
        self.assertEqual(self.git("status", "--porcelain"), b"")

    def test_generation_allocates_a_new_alternate_identity(self):
        first = generate(self.source, self.output)
        second = generate(self.source, self.scratch / "second")
        self.assertNotEqual(first["token"], second["token"])
        self.assertNotEqual(first["appBundle"], second["appBundle"])
        self.assertNotEqual(first["runnerBundle"], second["runnerBundle"])

    def test_refuses_output_inside_source(self):
        path = self.source / "output"
        with self.assertRaisesRegex(ValueError, "output parent"):
            generate(self.source, path)
        self.assertFalse(path.exists())

    def test_refuses_existing_output_without_overwriting(self):
        self.output.mkdir()
        marker = self.output / "sentinel"
        marker.write_bytes(b"keep")
        with self.assertRaises(FileExistsError):
            generate(self.source, self.output)
        self.assertEqual(list(self.output.iterdir()), [marker])
        self.assertEqual(marker.read_bytes(), b"keep")

    def test_refuses_dirty_checkout_without_creating_output(self):
        (self.source / "untracked").write_text("not source")
        with self.assertRaisesRegex(ValueError, "clean checkout"):
            generate(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_refuses_committed_substitute_for_pinned_fixture(self):
        (self.source / MEDIA).write_bytes(b"changed")
        self.commit()
        with self.assertRaisesRegex(ValueError, "fixture bytes"):
            generate(self.source, self.output)
        self.assertFalse((self.output / "probe-manifest.json").exists())

    def test_refuses_linked_output_parent_without_writing_to_it(self):
        alias = self.scratch / "alias"
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "output parent"):
            generate(self.source, alias / "output")
        self.assertFalse((self.source / "output").exists())


if __name__ == "__main__":
    unittest.main()
