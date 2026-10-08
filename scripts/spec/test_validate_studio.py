#!/usr/bin/env python3
"""Black-box tests of the Studio contract plumbing (ticket S03). Standard library only.

Each test copies the Studio contract tree into a temporary folder, changes files there the way a later ticket would
(a new cases module, vector kind, checker or module page), and runs the real commands:

    python3 spec/reference/studio/generate_studio_fixtures.py
    python3 scripts/spec/validate_studio.py [--list]

The repository itself is never modified.  Usage:  python3 scripts/spec/test_validate_studio.py [-v]
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COPIED = ("scripts/spec", "spec", "design-reference/studio/brief")

TEMP_CASES = '''\
"""A temporary cases module (test only)."""

KIND = "temp-probe"


def fixtures(sample):
    return {"vectors/temp-probe.json": {
        "schemaVersion": "jovra.studio-fixture.vectors/1", "kind": KIND, "status": "test only",
        "cases": [{"id": "two-plus-two", "a": 2, "b": 2, "expect": 4}]}}
'''

TEMP_CHECKER = '''

def check_probe(ctx, case, rep, where):
    if case["a"] + case["b"] == case["expect"]:
        rep.ok("temp-probe vectors")
    else:
        rep.fail(where, "sum differs")


VECTOR_CHECKERS = {KIND: check_probe}
'''

TEMP_PAGE = """\
---
module: temp-probe
reference: []
cases: [spec/reference/studio/cases/temp_probe_cases.py]
kinds: [temp-probe]
coverage: covered
swift: pending
kotlin: pending
---
# Temporary probe

Test only.
"""


class Sandbox:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="jovra-s03-")
        self.root = Path(self.tmp.name)
        for rel in COPIED:
            shutil.copytree(ROOT / rel, self.root / rel, ignore=shutil.ignore_patterns("__pycache__"))

    def close(self):
        self.tmp.cleanup()

    def path(self, rel: str) -> Path:
        return self.root / rel

    def write(self, rel: str, text: str) -> None:
        p = self.path(rel)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def append(self, rel: str, text: str) -> None:
        self.write(rel, self.path(rel).read_text(encoding="utf-8") + text)

    def run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, *args], cwd=self.root, capture_output=True, text=True, timeout=300)

    def generate(self) -> subprocess.CompletedProcess:
        out = self.run("spec/reference/studio/generate_studio_fixtures.py")
        if out.returncode != 0:
            raise AssertionError(f"generator failed:\n{out.stdout}\n{out.stderr}")
        return out

    def validate(self, *flags: str) -> subprocess.CompletedProcess:
        return self.run("scripts/spec/validate_studio.py", *flags)


class StudioPlumbingTest(unittest.TestCase):
    def setUp(self):
        self.box = Sandbox()
        self.addCleanup(self.box.close)

    def assertFailsWith(self, result, text):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(text, result.stdout)
        self.assertIn("RESULT: FAIL", result.stdout)

    def assertPasses(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("RESULT: PASS", result.stdout)

    def test_committed_tree_passes(self):
        self.assertPasses(self.box.validate())

    def test_vector_kind_without_checker_fails(self):
        self.box.write("spec/reference/studio/cases/temp_probe_cases.py", TEMP_CASES)
        self.box.generate()
        self.assertTrue(self.box.path("spec/studio/fixtures/vectors/temp-probe.json").exists(),
                        "the generator writes what a discovered cases module declares")
        self.assertFailsWith(self.box.validate(), "no checker for kind temp-probe")

    def test_registered_kind_without_module_page_fails(self):
        self.box.write("spec/reference/studio/cases/temp_probe_cases.py", TEMP_CASES + TEMP_CHECKER)
        self.box.generate()
        self.assertFailsWith(self.box.validate(), "kind temp-probe has no module page")

    def test_kind_with_checker_and_page_passes(self):
        self.box.write("spec/reference/studio/cases/temp_probe_cases.py", TEMP_CASES + TEMP_CHECKER)
        self.box.write("spec/studio/modules/temp-probe.md", TEMP_PAGE)
        self.box.generate()
        result = self.box.validate()
        self.assertPasses(result)
        self.assertIn("temp-probe vectors", result.stdout)

    def test_new_page_appears_in_generated_index_without_readme_edit(self):
        readme = self.box.path("spec/studio/README.md").read_bytes()
        self.box.write("spec/reference/studio/cases/temp_probe_cases.py", TEMP_CASES + TEMP_CHECKER)
        self.box.write("spec/studio/modules/temp-probe.md", TEMP_PAGE)
        self.box.generate()
        index = self.box.path("spec/studio/modules/README.md").read_text(encoding="utf-8")
        self.assertIn("(temp-probe.md)", index)
        self.assertEqual(readme, self.box.path("spec/studio/README.md").read_bytes())

    def test_stale_module_index_fails(self):
        self.box.write("spec/studio/modules/temp-probe.md", TEMP_PAGE.replace("[temp-probe]", "[]")
                       .replace("covered", "not-covered").replace("[spec/reference/studio/cases/temp_probe_cases.py]", "[]"))
        self.assertFailsWith(self.box.validate(), "spec/studio/modules/README.md is stale")

    def test_page_naming_an_unregistered_kind_fails(self):
        self.box.write("spec/studio/modules/temp-probe.md", TEMP_PAGE.replace("[spec/reference/studio/cases/temp_probe_cases.py]", "[]"))
        self.box.generate()
        self.assertFailsWith(self.box.validate(), "names kind temp-probe, which no cases module registers")

    def test_missing_generated_file_fails(self):
        self.box.path("spec/studio/fixtures/vectors/quote-credits.json").unlink()
        self.assertFailsWith(self.box.validate(), "generated file missing: vectors/quote-credits.json")

    def test_readme_with_a_per_module_line_fails(self):
        self.box.append("spec/studio/README.md", "\nThe ledger rules are in `ledger.py`.\n")
        self.assertFailsWith(self.box.validate(), "spec/studio/README.md: names module ledger on line")

    def test_list_prints_kinds_modules_and_status(self):
        result = self.box.validate("--list")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rows = {line.split()[0]: line.split() for line in result.stdout.splitlines() if line.strip()}
        # kind, type, count, invalid, module, coverage, swift, kotlin
        self.assertEqual(rows["quote-credits"][1:3], ["vector", "8"])
        self.assertEqual(rows["quote-credits"][4:7], ["ledger", "covered", "pending"])
        self.assertEqual(rows["sync-fit"][4], "sync")
        self.assertEqual(rows["jovra.edit-plan/2"][1], "schema")
        self.assertEqual(rows["normalization"][1:], ["page", "-", "-", "normalization", "not-covered", "pending",
                                                     "pending"])


if __name__ == "__main__":
    unittest.main(verbosity=2 if "-v" in sys.argv else 1, argv=[sys.argv[0]])
