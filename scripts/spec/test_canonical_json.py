"""Hand-derived native canonical byte vectors; expected values never come from a native encoder."""
import json
from pathlib import Path
import unittest
from canonical_json import canonicalize

ROOT = Path(__file__).resolve().parents[2]


class CanonicalJSONTests(unittest.TestCase):
    def test_independent_vectors(self):
        vectors = json.loads((ROOT / "spec/contracts/canonical-json.v1.json").read_text())
        for vector in vectors["cases"]:
            with self.subTest(vector["id"]):
                self.assertEqual(canonicalize(vector["input"]), vector["canonical"])

    def test_invalid_numbers_and_duplicate_keys_are_refused(self):
        for value in ('NaN', 'Infinity', '-Infinity', '{"id":1,"id":2}'):
            with self.subTest(value):
                with self.assertRaises(ValueError):
                    canonicalize(value)


if __name__ == '__main__':
    unittest.main()
