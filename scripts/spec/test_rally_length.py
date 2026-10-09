#!/usr/bin/env python3
"""Public fold safety: a zero-stroke error is inconsistent, never a negative rally."""
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'scripts/spec'), str(ROOT / 'spec/reference')]
from jsonschema_subset import SchemaSet
from cases.common import CLUB_BO3, singles
from jovra_ref import scoring

class RallyLengthSafety(unittest.TestCase):
    def test_zero_stroke_errors_preserve_observation_and_unknown_derived_length(self):
        schemas = SchemaSet(ROOT / 'spec/schemas')
        schemas.files['input.schema.json'] = {'$ref': 'fixture-scoring.schema.json#/$defs/engineInput'}
        schemas.files['output.schema.json'] = {'$ref': 'engine-output.schema.json#/$defs/foldResult'}
        for end in ('forcedError', 'unforcedError'):
            with self.subTest(end=end):
                outcome = {'winner': 'B', 'endType': end, 'strokeCount': 0, 'provenance': 'reviewed', 'source': 'user'}
                log = [{'id': 'p01', 'seq': 1, 'type': 'point', 'reviewed': outcome, 'reviewState': 'reviewed'}]
                setup = {**singles(CLUB_BO3), 'log': log}
                self.assertEqual(schemas.validate(setup, 'input.schema.json'), [])
                result = scoring.fold(setup, log)
                self.assertEqual(result['points'][0]['strokeCount'], 0)
                self.assertEqual(result['points'][0]['winner'], 'B')
                self.assertIsNone(result['points'][0]['rallyLength'])
                self.assertEqual(result['conflicts'], [{'type': 'outcomeInconsistent', 'pointId': 'p01'}])
                self.assertEqual(result['next']['before']['points'], {'A': 0, 'B': 1})
                self.assertEqual(schemas.validate(result, 'output.schema.json'), [])
