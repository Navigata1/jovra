"""Exercise watch-ui-test.sh with fake build, SDK and disk commands."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
FLOOR_KIB = 8 * 1024 * 1024

FAKE = """#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
log = pathlib.Path(os.environ["WATCH_DISK_TEST_LOG"])
calls = [json.loads(line) for line in log.read_text().splitlines()]
with log.open("a") as output:
    print(json.dumps([name, *args]), file=output)

if name == "df":
    assert len(args) == 2 and args[0] == "-Pk"
    path = args[1]
    label = "internal" if path == "/" else "build"
    seen = sum(call[0] == "df" and (call[2] == "/") == (label == "internal") for call in calls)
    readings = json.loads(os.environ["WATCH_DISK_TEST_READINGS"])[label]
    value = readings[min(seen, len(readings) - 1)]
    if value == "error":
        sys.exit(1)
    print("Filesystem 1024-blocks Used Available Capacity Mounted on")
    print(f"/dev/fake 99999999 100 {value} 10% /")
elif name == "watch-sim.sh":
    assert args[0] == "udid"
    print("11111111-1111-4111-8111-111111111111")
elif name == "generate.sh":
    assert not args
elif name == "xcodebuild":
    assert args[0] == "test"
    bundle = pathlib.Path(args[args.index("-resultBundlePath") + 1])
    bundle.mkdir(parents=True)
    failed = os.environ.get("WATCH_DISK_TEST_FAIL") == "1"
    (bundle / "result").write_text("Failed" if failed else "Passed")
    sys.exit(65 if failed else 0)
elif name == "xcrun":
    assert args[0] == "xcresulttool"
    if args[1] == "export":
        dst = pathlib.Path(args[args.index("--output-path") + 1])
        (dst / "manifest.json").write_text("[]")
    else:
        status = (pathlib.Path(args[args.index("--path") + 1]) / "result").read_text()
        if args[3] == "tests":
            print(json.dumps({"testNodes": [{"nodeType": "Test Suite", "name": "SyntheticSuite",
                "children": [{"nodeType": "Test Case", "result": status}]}]}))
        elif args[3] == "summary":
            print(json.dumps({"result": status, "failedTests": int(status == "Failed"),
                "testFailures": [{"testIdentifierString": "SyntheticSuite/test", "failureText": "retained failure"}]
                if status == "Failed" else []}))
        else:
            sys.exit("unexpected xcresult command")
else:
    sys.exit("unexpected fake command")
"""


class WatchUIDiskTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        scripts = self.root / "scripts" / "ios"
        scripts.mkdir(parents=True)
        for filename in ("watch-ui-test.sh", "common.sh", "xcresult-summary.py"):
            shutil.copy2(SOURCE / filename, scripts)
        for directory, names in ((scripts, ("generate.sh", "watch-sim.sh")),
                                 (self.root, ("df", "xcrun", "xcodebuild"))):
            for name in names:
                path = directory / name
                path.write_text(FAKE)
                path.chmod(0o700)
        self.log = self.root / "calls.jsonl"
        self.log.touch()
        self.derived = self.root / "uncreated" / "products"
        self.runner = scripts / "watch-ui-test.sh"

    def run_watch(self, internal, build, *devices, fail=False):
        return subprocess.run(
            ["bash", str(self.runner), *(arg for device in devices for arg in ("-device", device)), "disk-test"],
            env={**os.environ, "PATH": str(self.root) + os.pathsep + os.environ["PATH"],
                 "DERIVED_DATA": str(self.derived), "WATCH_DISK_TEST_LOG": str(self.log),
                 "WATCH_DISK_TEST_READINGS": json.dumps({"internal": internal, "build": build}),
                 "WATCH_DISK_TEST_FAIL": "1" if fail else "0"},
            capture_output=True, text=True, check=False, timeout=10,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def launched(self, command):
        return [call for call in self.calls() if call[0] == command]

    def test_low_internal_space_prevents_generation_and_simulator_calls(self):
        result = self.run_watch([FLOOR_KIB - 1], [FLOOR_KIB], "ultra49")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("not run (disk)", result.stderr)
        self.assertEqual(self.calls(), [["df", "-Pk", "/"]])

    def test_low_derived_volume_is_measured_at_nearest_existing_ancestor(self):
        result = self.run_watch([FLOOR_KIB], [FLOOR_KIB - 1], "ultra49")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("not run (disk)", result.stderr)
        self.assertEqual(self.calls(), [["df", "-Pk", "/"], ["df", "-Pk", str(self.root)]])

    def test_unreadable_disk_measurements_fail_closed(self):
        for value in ("malformed", "error"):
            with self.subTest(value=value):
                self.log.write_text("")
                result = self.run_watch([FLOOR_KIB], [value], "ultra49")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("not run (disk)", result.stderr)
                self.assertEqual(self.launched("generate.sh"), [])
                self.assertEqual(self.launched("xcodebuild"), [])

    def test_rechecks_after_generation_before_first_destination(self):
        result = self.run_watch([FLOOR_KIB, FLOOR_KIB - 1], [FLOOR_KIB], "ultra49")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("ultra49", result.stderr)
        self.assertEqual(len(self.launched("generate.sh")), 1)
        self.assertEqual(self.launched("watch-sim.sh"), [])
        self.assertEqual(self.launched("xcodebuild"), [])

    def test_rechecks_between_destinations_and_preserves_failed_result(self):
        result = self.run_watch([FLOOR_KIB, FLOOR_KIB, FLOOR_KIB - 1], [FLOOR_KIB],
                                "ultra49", "series42", fail=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("series42", result.stderr)
        self.assertIn("not run (disk)", result.stderr)
        self.assertIn("retained failure", result.stdout)
        self.assertEqual(len(self.launched("xcodebuild")), 1)
        receipt = next(self.derived.glob("watch-tests-ultra49-*.xcresult"))
        self.assertEqual((receipt / "result").read_text(), "Failed")
        self.assertEqual(list(self.derived.glob("watch-tests-series42-*")), [])

    def test_space_at_floor_allows_a_run_with_a_completed_receipt(self):
        result = self.run_watch([FLOOR_KIB], [FLOOR_KIB], "ultra49")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.launched("xcodebuild")), 1)
        self.assertIn("1 passed", result.stdout)
