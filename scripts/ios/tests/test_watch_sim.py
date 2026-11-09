"""Exercise watch-sim.sh against a synthetic simctl device inventory."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
WATCH = "com.apple.CoreSimulator.SimRuntime.watchOS-26-5"
OLDER = "com.apple.CoreSimulator.SimRuntime.watchOS-26-4"
IOS = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
ULTRA = "JOVRA Watch Ultra 3 49mm"
ULTRA_TYPE = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-3-49mm"

FAKE_SIMCTL = """#!/usr/bin/env python3
import json, os, pathlib, sys, uuid
assert sys.argv[1] == "simctl"
path = pathlib.Path(os.environ["TEST_SIMCTL_STATE"])
state = json.loads(path.read_text())
args = sys.argv[2:]
if args[:2] == ["list", "devices"]:
    print(json.dumps({"devices": state["devices"]}))
elif args[:2] == ["list", "pairs"]:
    print(json.dumps({"pairs": state["pairs"]}))
elif args[:3] == ["list", "runtimes", "available"]:
    print("watchOS 26.5 (build) - com.apple.CoreSimulator.SimRuntime.watchOS-26-5")
    print("iOS 27.2 (build) - com.apple.CoreSimulator.SimRuntime.iOS-27-2")
    print("watchOS 9.9 (build) - com.apple.CoreSimulator.SimRuntime.watchOS-9-9")
elif args[0] in ("create", "shutdown", "delete"):
    state["mutations"].append(args)
    if args[0] == "create":
        _, name, kind, runtime = args
        udid = str(uuid.uuid4()).upper()
        state["devices"].setdefault(runtime, []).append(
            {"udid": udid, "name": name, "deviceTypeIdentifier": kind}
        )
        print(udid)
    if args[0] == "delete":
        for runtime, devices in state["devices"].items():
            state["devices"][runtime] = [d for d in devices if d["udid"] != args[1]]
    path.write_text(json.dumps(state))
else:
    raise SystemExit("Unexpected simulator command: " + str(args))
"""


class WatchSimTests(unittest.TestCase):
    def setUp(self):
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        root = Path(workspace.name)
        scripts = root / "scripts" / "ios"
        scripts.mkdir(parents=True)
        for source in SOURCE.glob("watch*"):
            if source.is_file():
                shutil.copyfile(source, scripts / source.name)
        self.entrypoint = scripts / "watch-sim.sh"
        self.state_file = root / "inventory.json"
        self.ownership = root / ".cache" / "watch-sim" / "owned.json"
        self.write_state({"devices": {}, "pairs": {}, "mutations": []})
        executable = root / "xcrun"
        executable.write_text(FAKE_SIMCTL)
        executable.chmod(0o700)
        self.env = {
            **os.environ,
            "PATH": str(root) + os.pathsep + os.environ["PATH"],
            "TEST_SIMCTL_STATE": str(self.state_file),
            "WATCH_RUNTIME": WATCH,
        }

    def run_watch(self, *args):
        return subprocess.run(
            ["bash", str(self.entrypoint), *args], env=self.env, text=True,
            capture_output=True, check=False, timeout=10,
        )

    def state(self):
        return json.loads(self.state_file.read_text())

    def write_state(self, value):
        self.state_file.write_text(json.dumps(value))

    def test_create_and_delete_refuse_a_simulator_owned_elsewhere(self):
        for runtime, kind in ((IOS, "unrelated-phone"), (OLDER, ULTRA_TYPE), (WATCH, ULTRA_TYPE)):
            for operation in ("create", "delete", "udid"):
                with self.subTest(operation=operation, runtime=runtime, kind=kind):
                    foreign = {"udid": "BAE56DD9-1546-45FC-8883-DCAD200FADCF",
                               "name": ULTRA, "deviceTypeIdentifier": kind}
                    baseline = {"devices": {runtime: [foreign]}, "pairs": {}, "mutations": []}
                    self.write_state(baseline)
                    args = [operation, ULTRA] if operation == "udid" else [operation]
                    result = self.run_watch(*args)
                    self.assertEqual(self.state(), baseline, result.stdout)
                    self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_own_uuid_lifecycle_preserves_the_rest_of_the_inventory(self):
        foreign = {"udid": "15591CF6-DC66-4DE4-9A5B-A6E6ECF862E6",
                   "name": "Someone else's simulator", "deviceTypeIdentifier": "iphone"}
        baseline = {"devices": {IOS: [foreign]}, "pairs": {}, "mutations": []}
        self.write_state(baseline)
        evidence = self.state_file.parent / "evidence"
        del self.env["WATCH_RUNTIME"]
        created = self.run_watch("create", "--evidence", str(evidence))
        self.assertEqual(created.returncode, 0, created.stderr)
        names = {row["name"]: row["udid"] for row in self.state()["devices"][WATCH]}
        self.assertEqual(len(names), 3)
        self.assertEqual(self.run_watch("udid", ULTRA).stdout.strip(), names[ULTRA])
        self.assertEqual(len(self.run_watch("list").stdout.splitlines()), 3)
        existing = self.state()
        repeat = self.run_watch("create")
        self.assertEqual(repeat.returncode, 0, repeat.stderr)
        self.assertEqual(self.state(), existing)
        deleted = self.run_watch("delete", "--evidence", str(evidence))
        self.assertEqual(deleted.returncode, 0, deleted.stderr)
        self.assertEqual(self.state()["devices"], {IOS: [foreign], WATCH: []})
        self.assertEqual(json.loads(self.ownership.read_text()), [])
        self.assertEqual(self.state()["mutations"][3:],
                         [[command, udid] for udid in names.values() for command in ("shutdown", "delete")])
        for operation in ("create", "delete"):
            report = (evidence / f"simctl-{operation}.txt").read_text()
            self.assertIn("other devices after, unchanged: 1", report)
            self.assertIn("result: PASS", report)

    def test_refuses_to_act_on_changed_recorded_uuid_type_or_runtime(self):
        created = self.run_watch("create")
        self.assertEqual(created.returncode, 0, created.stderr)
        baseline = self.state()
        for change in ("uuid", "type", "runtime"):
            with self.subTest(change=change):
                state = json.loads(json.dumps(baseline))
                device = state["devices"][WATCH][0]
                if change == "uuid":
                    device["udid"] = "36EB950D-8215-4F1D-A84F-0D5639E2BF86"
                elif change == "type":
                    device["deviceTypeIdentifier"] = "unrelated-watch"
                else:
                    state["devices"][OLDER] = [state["devices"][WATCH].pop(0)]
                self.write_state(state)
                deleted = self.run_watch("delete")
                self.assertNotEqual(deleted.returncode, 0, deleted.stdout)
                self.assertEqual(self.state(), state)
                self.assertNotEqual(self.run_watch("udid", ULTRA).returncode, 0)

    def test_refuses_to_delete_when_a_recorded_watch_is_paired(self):
        created = self.run_watch("create")
        self.assertEqual(created.returncode, 0, created.stderr)
        state = self.state()
        state["pairs"]["pair-id"] = {"watch": {"udid": state["devices"][WATCH][-1]["udid"]}}
        self.write_state(state)
        evidence = self.state_file.parent
        report = evidence / "simctl-delete.txt"
        report.write_text("result: PASS\n")
        deleted = self.run_watch("delete", "--evidence", str(evidence))
        self.assertNotEqual(deleted.returncode, 0, deleted.stdout)
        self.assertIn("existing simulator pair", deleted.stderr)
        self.assertIn("result: FAIL", report.read_text())
        self.assertEqual(self.state(), state)
