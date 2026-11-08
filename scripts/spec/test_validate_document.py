#!/usr/bin/env python3
"""The validator's --document mode (ticket T15). Standard library only.

Run from the repo root:  python3 -m unittest discover -s scripts/spec -p 'test_*.py' -v

A native producer (the capture engine's RecordingSink handoff) emits a session document outside spec/. The
reference validator must judge that document exactly as it would a committed fixture: schema for its kind,
reference integrity, and every repository check, without writing anything into spec/.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts/spec/validate.py"
SESSION = ROOT / "spec/fixtures/records/session.all-fields.json"


def run(*paths: Path) -> subprocess.CompletedProcess:
    args = [sys.executable, str(VALIDATOR)]
    for path in paths:
        args += ["--document", str(path)]
    return subprocess.run(args, cwd=ROOT, capture_output=True, text=True, check=False)


class ValidateDocumentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.before = sorted(p.relative_to(ROOT) for p in (ROOT / "spec").rglob("*"))

    def tearDown(self) -> None:
        self.tmp.cleanup()
        # The mode never writes into spec/ (the earlier capture probe copied a file in and out).
        self.assertEqual(self.before, sorted(p.relative_to(ROOT) for p in (ROOT / "spec").rglob("*")))

    def emitted(self, mutate=None) -> Path:
        doc = json.loads(SESSION.read_text(encoding="utf-8"))
        doc["id"] = "emitted-capture"
        if mutate:
            mutate(doc)
        path = self.dir / "emitted-session.json"
        path.write_text(json.dumps(doc, indent=2), encoding="utf-8")
        return path

    def test_a_valid_external_session_passes_and_is_counted(self) -> None:
        result = run(self.emitted())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("RESULT: PASS", result.stdout)
        self.assertRegex(result.stdout, r"external documents\s+1")

    def test_a_gap_reason_outside_the_contract_fails(self) -> None:
        # 'paused' is the ticket's word; the contract value is 'userPaused'.
        def bad_gap(doc):
            doc["recording"]["gaps"] = [{"startMs": 1000, "endMs": 2000, "reason": "paused"}]
        result = run(self.emitted(bad_gap))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("emitted-session.json", result.stdout)
        self.assertIn("RESULT: FAIL", result.stdout)

    def test_a_reference_integrity_problem_in_the_external_document_fails(self) -> None:
        def mark_after_end(doc):
            doc["marks"] = [dict(doc["marks"][0], tMs=doc["recording"]["durationMs"] + 60_000)]
        result = run(self.emitted(mark_after_end))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("emitted-session.json", result.stdout)

    def test_a_missing_document_fails_without_a_traceback(self) -> None:
        result = run(self.dir / "absent.json")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("absent.json", result.stdout)


if __name__ == "__main__":
    unittest.main()
