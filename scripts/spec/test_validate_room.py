#!/usr/bin/env python3
"""Negative controls for the room-contracts check (ticket W01, issue #267). Standard library only.

Issue #267 asks that breaking a Room fixture turns room-contracts red. These tests prove it on every run, in CI and
locally, without a scratch branch: each test copies the Room contract tree into a temporary folder, breaks one fixture
there the way a careless edit would, and runs the same command the room-contracts job runs:

    python3 scripts/spec/validate_room.py

The clean copy must exit 0 (so the control is not vacuous) and every broken copy must exit 1 and name the broken file.
The repository itself is never modified.  Usage:  python3 scripts/spec/test_validate_room.py [-v]
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COPIED = (
    "scripts/spec",
    "spec",
    "design-reference/adaptive/brief",
    "docs/handoff/adaptive-v3/scripts",
)
FIX = Path("spec/room/fixtures")


def copy_tree(dest: Path) -> None:
    for rel in COPIED:
        shutil.copytree(ROOT / rel, dest / rel, ignore=shutil.ignore_patterns("__pycache__"))


def run_validator(tree: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(tree / "scripts/spec/validate_room.py")],
                          cwd=tree, capture_output=True, text=True, timeout=300,
                          env={"PYTHONDONTWRITEBYTECODE": "1", "PATH": "/usr/bin:/bin"})


def edit_json(path: Path, change) -> None:
    doc = json.loads(path.read_text(encoding="utf-8"))
    change(doc)
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


class RoomContractsNegativeControls(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tree = Path(self._tmp.name)
        copy_tree(self.tree)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def assertRed(self, proc: subprocess.CompletedProcess, *needles: str) -> None:
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 1, f"validator should fail, got exit {proc.returncode}:\n{out}")
        self.assertIn("FAILED:", proc.stdout)
        for needle in needles:
            self.assertIn(needle, out)

    def test_clean_copy_is_green(self) -> None:
        proc = run_validator(self.tree)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("PASS: JOVRA Room v1 contracts", proc.stdout)

    def test_flipped_freshness_vector_is_red(self) -> None:
        """The break named in issue #267: fresh-boundary expect Fresh -> Delayed."""
        def flip(doc):
            case = next(c for c in doc["cases"] if c["id"] == "fresh-boundary")
            self.assertEqual(case["expect"], "Fresh")
            case["expect"] = "Delayed"
        edit_json(self.tree / FIX / "vectors/freshness.json", flip)
        self.assertRed(run_validator(self.tree),
                       'FAIL vectors/freshness.json#fresh-boundary: expected "Delayed", got "Fresh"',
                       "vectors/freshness.json differs from a fresh generation")

    def test_hand_edited_record_is_red(self) -> None:
        """A record edited by hand instead of regenerated from the reference."""
        def bump(doc):
            doc["snapshotSeq"] += 1
        edit_json(self.tree / FIX / "records/room-snapshot.json", bump)
        self.assertRed(run_validator(self.tree), "records/room-snapshot.json differs from a fresh generation")

    def test_record_missing_required_field_is_red(self) -> None:
        """A record that no longer satisfies its schema."""
        def drop(doc):
            self.assertIn("snapshotSeq", doc)
            del doc["snapshotSeq"]
        edit_json(self.tree / FIX / "records/room-snapshot.json", drop)
        self.assertRed(run_validator(self.tree), "room-snapshot")

    def test_deleted_fixture_is_red(self) -> None:
        (self.tree / FIX / "records/device-status.json").unlink()
        self.assertRed(run_validator(self.tree), "FAIL determinism: records/device-status.json differs from a fresh generation")


if __name__ == "__main__":
    unittest.main(verbosity=2 if "-v" in sys.argv else 1, argv=[a for a in sys.argv if a != "-v"])
