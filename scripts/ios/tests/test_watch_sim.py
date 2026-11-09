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
        if blocked := os.environ.get("TEST_BLOCK_OWNED_RECEIPT"):
            pathlib.Path(blocked).mkdir()
    if args[0] == "shutdown" and os.environ.get("TEST_PAIR_ON_SHUTDOWN"):
        state["pairs"]["new-pair"] = {"watch": {"udid": args[1]}}
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

    def run_watch(self, *args, entrypoint=None):
        return subprocess.run(
            ["bash", str(entrypoint or self.entrypoint), *args], env=self.env, text=True,
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
        self.assertEqual(json.loads(self.ownership.read_text())["devices"], [])
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

    def test_refuses_delete_when_a_watch_is_paired_during_shutdown(self):
        self.assertEqual(self.run_watch("create").returncode, 0)
        before = self.state()
        receipt_before = self.ownership.read_bytes()
        udid = before["devices"][WATCH][0]["udid"]
        self.env["TEST_PAIR_ON_SHUTDOWN"] = "1"

        refused = self.run_watch("delete")

        self.assertNotEqual(refused.returncode, 0, refused.stdout)
        self.assertIn("existing simulator pair", refused.stderr)
        self.assertEqual(self.state()["devices"], before["devices"])
        self.assertEqual(self.state()["pairs"], {"new-pair": {"watch": {"udid": udid}}})
        self.assertEqual(self.state()["mutations"], before["mutations"] + [["shutdown", udid]])
        self.assertEqual(self.ownership.read_bytes(), receipt_before)

    def test_evidence_publication_does_not_follow_stale_report_symlinks(self):
        evidence = self.state_file.parent / "reports"
        evidence.mkdir()
        with tempfile.TemporaryDirectory() as outside:
            sentinel = Path(outside) / "do-not-modify"
            original = b"external evidence sentinel\x00\xff\n"
            for operation in ("create", "delete"):
                with self.subTest(operation=operation):
                    sentinel.write_bytes(original)
                    report = evidence / f"simctl-{operation}.txt"
                    report.symlink_to(sentinel)
                    if operation == "delete":
                        state = self.state()
                        state["pairs"]["existing-pair"] = {"watch": {"udid": state["devices"][WATCH][0]["udid"]}}
                        self.write_state(state)
                    result = self.run_watch(operation, "--evidence", str(evidence))
                    self.assertEqual(result.returncode, 0 if operation == "create" else 1, result.stderr)
                    self.assertEqual(sentinel.read_bytes(), original, result.stdout)
                    self.assertFalse(report.is_symlink())
                    self.assertIn("result: PASS" if operation == "create" else "result: FAIL", report.read_text())
            self.assertEqual({path.name for path in evidence.iterdir()}, {"simctl-create.txt", "simctl-delete.txt"})

    def test_another_worktree_cannot_reuse_a_shared_or_copied_receipt(self):
        checkout = self.ownership.parents[2]
        second = checkout.parent / (checkout.name + "-other")
        self.addCleanup(shutil.rmtree, second, True)
        git = ["git", "-C", str(checkout), "-c", "core.hooksPath=/dev/null"]
        commands = [
            ["init", "--quiet", "--template="],
            ["add", "scripts"],
            ["-c", "user.name=IDC", "-c", "user.email=hello@islanddevcrew.com",
             "commit", "--quiet", "--no-gpg-sign", "-m", "Synthetic simulator test checkout"],
            ["worktree", "add", "--quiet", "--detach", str(second)],
        ]
        for command in commands:
            subprocess.run([*git, *command], check=True, capture_output=True, timeout=10)

        created = self.run_watch("create")
        self.assertEqual(created.returncode, 0, created.stderr)
        baseline = self.state()
        receipt_before = self.ownership.read_bytes()
        foreign_entrypoint = second / self.entrypoint.relative_to(checkout)
        foreign_cache = second / ".cache"
        foreign_receipt = second / self.ownership.relative_to(checkout)

        foreign_cache.symlink_to(self.ownership.parents[1], target_is_directory=True)
        for operation in ("udid", "create", "delete"):
            with self.subTest(receipt="shared", operation=operation):
                self.write_state(baseline)
                self.ownership.write_bytes(receipt_before)
                args = [operation, ULTRA] if operation == "udid" else [operation]
                refused = self.run_watch(*args, entrypoint=foreign_entrypoint)
                self.assertNotEqual(refused.returncode, 0, refused.stdout)
                self.assertIn("must be local to this checkout", refused.stderr)
                self.assertEqual(self.state(), baseline)
                self.assertEqual(self.ownership.read_bytes(), receipt_before)

        foreign_cache.unlink()
        foreign_receipt.parent.mkdir(parents=True)
        foreign_receipt.write_bytes(receipt_before)
        self.write_state(baseline)
        self.ownership.write_bytes(receipt_before)
        refused = self.run_watch("delete", entrypoint=foreign_entrypoint)
        self.assertNotEqual(refused.returncode, 0, refused.stdout)
        self.assertIn("belongs to a different checkout", refused.stderr)
        self.assertEqual(self.state(), baseline)
        self.assertEqual(foreign_receipt.read_bytes(), receipt_before)
        self.assertEqual(self.run_watch("udid", ULTRA).stdout.strip(), baseline["devices"][WATCH][0]["udid"])

    def test_create_preserves_external_file_linked_from_stale_receipt_temp(self):
        self.ownership.parent.mkdir(parents=True)
        with tempfile.TemporaryDirectory() as outside:
            sentinel = Path(outside) / "do-not-modify"
            original = b"external sentinel\x00\xff\n"
            sentinel.write_bytes(original)
            stale_temp = self.ownership.with_suffix(".tmp")
            stale_temp.symlink_to(sentinel)

            created = self.run_watch("create")
            self.assertEqual(sentinel.read_bytes(), original, created.stdout)
            self.assertEqual(created.returncode, 0, created.stderr)
            self.assertTrue(stale_temp.is_symlink())
            self.assertEqual({p.name for p in self.ownership.parent.iterdir()}, {"lock", "owned.json", "owned.tmp"})
            self.assertEqual(len(json.loads(self.ownership.read_text())["devices"]), 3)

    def test_failed_receipt_publication_removes_the_own_temporary_file(self):
        self.env["TEST_BLOCK_OWNED_RECEIPT"] = str(self.ownership)
        created = self.run_watch("create")
        self.assertNotEqual(created.returncode, 0, created.stdout)
        self.assertTrue(self.ownership.is_dir(), "The injected blocker must remain untouched")
        self.assertEqual({p.name for p in self.ownership.parent.iterdir()}, {"lock", "owned.json"})
        self.assertEqual([item[0] for item in self.state()["mutations"]], ["create"])
