#!/usr/bin/env python3
"""Public validator seam for native encoded documents; negative cases must exit non-zero."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class EncodedDocuments(unittest.TestCase):
    def test_unknown_kind_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'unknown.json').write_text('{"kind":"jovra.unclaimed","schemaVersion":"1.0.0"}')
            result = subprocess.run(['python3', str(ROOT/'scripts/spec/validate.py'), '--encoded-dir', directory], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn('no schema', result.stdout)
    def test_invalid_typed_document_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'session.json').write_text('{"kind":"jovra.session","schemaVersion":"1.1.0"}')
            result = subprocess.run(['python3', str(ROOT/'scripts/spec/validate.py'), '--encoded-dir', directory], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn('schema', result.stdout)
    def test_empty_output_directory_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(['python3', str(ROOT/'scripts/spec/validate.py'), '--encoded-dir', directory], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout)

if __name__ == '__main__': unittest.main()
