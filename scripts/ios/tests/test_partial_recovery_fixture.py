"""Host-only safety controls. All simulator data is synthetic temporary files."""
import json
import os
import plistlib
import shutil
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from uuid import uuid4

from partial_recovery_fixture import (
    DAMAGE, FixtureError, damage_first_segment, directory, isolated_sessions, pending_snapshot, recovery_snapshot,
)


class PartialRecoveryFixtureTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.session_id = str(uuid4()).upper()
        self.folder = self.root / self.session_id
        self.originals = self.folder / "originals"
        self.originals.mkdir(parents=True)
        self.first = self.originals / "segment-0.mp4"
        self.second = self.originals / "segment-1.mp4"
        self.first.write_bytes(b"fixture segment zero")
        self.second.write_bytes(b"fixture segment one")
        self.document = {
            "id": self.session_id, "title": "Partial recovery fixture",
            "sample": {"synthetic": True, "generator": "JOVRAFixtureCamera"},
            "original": {"state": "recording"}, "recording": {"mode": "simulatorFixture", "mediaAvailable": False},
        }
        self.journal = {
            "formatVersion": 1, "sessionID": self.session_id, "mode": "simulatorFixture", "finished": False,
            "segments": [
                {"id": f"segment-{i}", "index": i, "finalized": True, "durationMs": 2000,
                 "file": {"path": f"originals/segment-{i}.mp4", "bytes": file.stat().st_size}}
                for i, file in enumerate((self.first, self.second))
            ],
        }
        self.write_json("session.json", self.document)
        self.write_json("capture-journal.json", self.journal)

    def write_json(self, name, contents):
        (self.folder / name).write_text(json.dumps(contents))

    def test_only_first_segment_is_replaced_and_repeat_damage_refuses(self):
        preserved = {path: path.read_bytes() for path in (self.second, self.folder / "session.json",
                                                            self.folder / "capture-journal.json")}
        with directory(self.root) as sessions:
            pending = pending_snapshot(sessions)
            receipt = damage_first_segment(sessions, pending)
        self.assertEqual(receipt["sessionID"], self.session_id)
        self.assertEqual(self.first.read_bytes(), DAMAGE)
        for path, data in preserved.items():
            self.assertEqual(path.read_bytes(), data)
        with directory(self.root) as sessions, self.assertRaises(FixtureError):
            damage_first_segment(sessions, pending)

    def test_foreign_session_or_nonfinalized_journal_refuses_before_any_change(self):
        original = self.first.read_bytes()
        self.document["sample"]["synthetic"] = False
        self.write_json("session.json", self.document)
        with directory(self.root) as sessions, self.assertRaises(FixtureError):
            pending_snapshot(sessions)
        self.document["sample"]["synthetic"] = True
        self.write_json("session.json", self.document)
        self.journal["segments"][1]["finalized"] = False
        self.write_json("capture-journal.json", self.journal)
        with directory(self.root) as sessions, self.assertRaises(FixtureError):
            pending_snapshot(sessions)
        self.assertEqual(self.first.read_bytes(), original)

    def test_symlink_originals_refused_without_touching_external_file(self):
        outside = self.root / "foreign-originals"
        self.originals.rename(outside)
        self.originals.symlink_to(outside, target_is_directory=True)
        with directory(self.root) as sessions, self.assertRaises((FixtureError, OSError)):
            pending_snapshot(sessions)
        self.assertEqual((outside / self.first.name).read_bytes(), b"fixture segment zero")

    def test_snapshot_detects_rewritten_original_and_records_session_receipt_timestamps(self):
        from hashlib import sha256

        with directory(self.root) as sessions:
            seed = damage_first_segment(sessions, pending_snapshot(sessions))
        self.document["original"] = {"state": "partial"}
        self.document["recording"].update(mediaAvailable=True, segments=[{
            "id": "segment-1", "file": {"path": "originals/segment-1.mp4",
                                        "sha256": sha256(self.second.read_bytes()).hexdigest()},
        }], recovery={"outcome": "partial", "unrecoverable": [{"path": "originals/segment-0.mp4"}]})
        self.write_json("session.json", self.document)
        self.write_json("capture-recovery.json", {"syntheticTestReport": True})
        with directory(self.root) as sessions:
            snapshot = recovery_snapshot(sessions, seed)
            self.assertIn("mtimeNs", snapshot["session"])
            self.assertIn("mtimeNs", snapshot["report"])
            self.assertEqual(recovery_snapshot(sessions, seed), snapshot)
            self.second.write_bytes(b"changed")
            with self.assertRaises(FixtureError):
                recovery_snapshot(sessions, seed)

    def test_cli_custody_requires_tokenized_device_and_container_identity(self):
        token = "1234abcd5678"
        udid = str(uuid4()).upper()
        bundle = f"com.islanddevcrew.jovra.partial-recovery-{token}"
        container = (self.root / "Library/Developer/CoreSimulator/Devices" / udid
                     / "data/Containers/Data/Application" / str(uuid4()).upper())
        sessions = container / "Library/Application Support/JOVRA/sessions"
        sessions.mkdir(parents=True)
        metadata = container / ".com.apple.mobile_container_manager.metadata.plist"
        metadata.write_bytes(plistlib.dumps({"MCMMetadataIdentifier": bundle}))
        device = {"udid": udid, "name": "Another owner's device", "state": "Booted", "isAvailable": True}
        inventory = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": [device]}}
        with patch("partial_recovery_fixture.Path.home", return_value=self.root), patch(
            "partial_recovery_fixture.simctl", side_effect=[json.dumps(inventory)]
        ) as fake:
            with self.assertRaises(FixtureError), isolated_sessions(udid, token):
                self.fail("Foreign device opened")
            self.assertEqual(fake.call_count, 1)
        device["name"] = f"JOVRA-PartialRecovery-{token}"
        with patch("partial_recovery_fixture.Path.home", return_value=self.root), patch(
            "partial_recovery_fixture.simctl", side_effect=[json.dumps(inventory), str(container)]
        ):
            with isolated_sessions(udid, token) as opened:
                self.assertEqual(os.fstat(opened).st_ino, sessions.stat().st_ino)
        metadata.write_bytes(plistlib.dumps({"MCMMetadataIdentifier": "com.islanddevcrew.jovra"}))
        with patch("partial_recovery_fixture.Path.home", return_value=self.root), patch(
            "partial_recovery_fixture.simctl", side_effect=[json.dumps(inventory), str(container)]
        ):
            with self.assertRaises(FixtureError), isolated_sessions(udid, token):
                self.fail("Foreign app container opened")

    def test_late_parent_redirect_cannot_damage_foreign_fixture(self):
        token = "1234abcd5678"
        udid = str(uuid4()).upper()
        bundle = f"com.islanddevcrew.jovra.partial-recovery-{token}"
        container = (self.root / "Library/Developer/CoreSimulator/Devices" / udid
                     / "data/Containers/Data/Application" / str(uuid4()).upper())
        support = container / "Library/Application Support"
        sessions = support / "JOVRA/sessions"
        shutil.copytree(self.folder, sessions / self.session_id)
        (container / ".com.apple.mobile_container_manager.metadata.plist").write_bytes(
            plistlib.dumps({"MCMMetadataIdentifier": bundle}))
        foreign = self.root / "foreign-application-support"
        foreign_sessions = foreign / "JOVRA/sessions"
        shutil.copytree(self.folder, foreign_sessions / self.session_id)
        foreign_media = foreign_sessions / self.session_id / "originals/segment-0.mp4"
        inventory = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": [{
            "udid": udid, "name": f"JOVRA-PartialRecovery-{token}", "state": "Booted", "isAvailable": True,
        }]}}
        with directory(sessions) as opened:
            pending = pending_snapshot(opened)
        actual_open = os.open
        redirected = False

        def redirect_before_child_open(name, *args, **kwargs):
            nonlocal redirected
            if name == "Application Support" and kwargs.get("dir_fd") is not None and not redirected:
                support.rename(support.with_name("Application Support original"))
                support.symlink_to(foreign, target_is_directory=True)
                redirected = True
            return actual_open(name, *args, **kwargs)

        with patch("partial_recovery_fixture.Path.home", return_value=self.root), patch(
            "partial_recovery_fixture.simctl", side_effect=[json.dumps(inventory), str(container)]
        ), patch("partial_recovery_fixture.os.open", side_effect=redirect_before_child_open):
            with self.assertRaises(OSError), isolated_sessions(udid, token) as opened:
                damage_first_segment(opened, pending)
        self.assertTrue(redirected, "The adversarial parent swap must execute")
        self.assertEqual(foreign_media.read_bytes(), b"fixture segment zero")

    def test_same_bytes_replacement_cannot_use_old_pending_receipt(self):
        with directory(self.root) as sessions:
            pending = pending_snapshot(sessions)
            replacement = self.first.with_suffix(".copy")
            replacement.write_bytes(self.first.read_bytes())
            replacement.replace(self.first)
            with self.assertRaisesRegex(FixtureError, "pre-damage receipt"):
                damage_first_segment(sessions, pending)
        self.assertEqual(self.first.read_bytes(), b"fixture segment zero")
