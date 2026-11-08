#!/usr/bin/env python3
"""T32: the rally fixtures are checked, not just written. A wrong expectation fails the validator's check, the
schema refuses malformed cases, and the session roll writers refuse what Playback settings cannot produce."""
import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'scripts/spec'), str(ROOT / 'spec/reference')]
from jsonschema_subset import SchemaSet  # noqa: E402
from cases import rally_cases  # noqa: E402
from jovra_ref import rally  # noqa: E402

RALLY = ROOT / 'spec/fixtures/rally'


def load(name):
    return json.loads((RALLY / name).read_text(encoding='utf-8'))


class RallyFixturesAreChecked(unittest.TestCase):
    def test_committed_fixtures_cover_the_required_families(self):
        ids = sorted(p.stem for p in RALLY.glob('R*.json'))
        self.assertEqual(ids, ['R01-bookmarks-only', 'R02-threshold-edges', 'R03-excluded-side',
                               'R04-hits-and-marks', 'R05-plan-rolls'])
        for name in ids:
            self.assertEqual(rally_cases.check(None, load(f'{name}.json'), {}), [], name)

    def test_a_wrong_expectation_is_reported(self):
        mutations = {
            'threshold off by one': ('R02-threshold-edges.json', 0,
                                     lambda e: e['candidates'][0]['rallies'].append(
                                         {'startMs': 12_999, 'endMs': 12_999, 'hitCount': 1})),
            'excluded side ignored': ('R03-excluded-side.json', 0,
                                      lambda e: e['dropped']['excludedSide'].pop()),
            'mark not attached': ('R04-hits-and-marks.json', 0,
                                  lambda e: e['candidates'][0]['markIds'].clear()),
            'gap chip rounds up': ('R05-plan-rolls.json', 4, lambda e: e['gaps'][1].update(label='+0:01')),
            'per-clip roll ignored': ('R05-plan-rolls.json', 0,
                                      lambda e: e['ranges'][1]['range'].update(fromMs=50_000)),
        }
        for label, (name, index, mutate) in mutations.items():
            with self.subTest(label):
                doc = load(name)
                mutate(doc['cases'][index]['expected'])
                self.assertTrue(rally_cases.check(None, doc, {}))

    def test_kept_plus_skipped_must_equal_the_recording(self):
        doc = load('R05-plan-rolls.json')
        doc['cases'][1]['expected']['skippedMs'] += 1
        problems = rally_cases.check(None, doc, {})
        self.assertTrue(any('kept + skipped' in p for p in problems), problems)

    def test_schema_refuses_a_case_with_both_a_result_and_an_error(self):
        schemas = SchemaSet(ROOT / 'spec/schemas')
        doc = load('R02-threshold-edges.json')
        self.assertEqual(schemas.validate(doc, 'fixture-rally.schema.json'), [])
        bad = copy.deepcopy(doc)
        bad['cases'][0]['expectedError'] = 'duplicateId'
        self.assertTrue(schemas.validate(bad, 'fixture-rally.schema.json'))
        bad = copy.deepcopy(doc)
        bad['cases'][0]['hits'][0]['side'] = 'centre'
        self.assertTrue(schemas.validate(bad, 'fixture-rally.schema.json'))


class SessionRollWriters(unittest.TestCase):
    def test_writers_return_a_new_document(self):
        base = rally_cases.base_session()
        before = copy.deepcopy(base)
        edited = rally.set_session_rolls(base, 2_000, 3_000)
        self.assertEqual(base, before)
        self.assertEqual(edited['rallyPlayback'], {'preRollMs': 2_000, 'postRollMs': 3_000})

    def test_session_rolls_are_half_second_steps_up_to_five_seconds(self):
        base = rally_cases.base_session()
        for pre, post in ((5_500, 0), (1_250, 2_500), (-500, 2_500)):
            with self.subTest(pre=pre, post=post):
                with self.assertRaises(rally.RallyError) as raised:
                    rally.set_session_rolls(base, pre, post)
                self.assertEqual(raised.exception.code, 'rollOutOfRange')

    def test_a_clip_override_needs_a_point_or_mark_of_this_session(self):
        with self.assertRaises(rally.RallyError) as raised:
            rally.set_clip_rolls(rally_cases.base_session(), 'nope', pre_roll_ms=500)
        self.assertEqual(raised.exception.code, 'unknownTarget')

    def test_a_first_clip_override_starts_from_the_default_session_rolls(self):
        edited = rally.set_clip_excluded(rally_cases.base_session(), 'rp-mark-1', True)
        self.assertEqual(edited['rallyPlayback'], {'preRollMs': 1_500, 'postRollMs': 2_500,
                                                   'clips': [{'targetId': 'rp-mark-1', 'excluded': True}]})
        restored = rally.set_clip_excluded(edited, 'rp-mark-1', False)
        self.assertEqual(restored['rallyPlayback']['clips'], [{'targetId': 'rp-mark-1'}])

    def test_a_1_0_document_is_stamped_1_1_when_it_gains_rolls(self):
        base = dict(rally_cases.base_session(), schemaVersion='1.0.0')
        self.assertEqual(rally.set_session_rolls(base, 0, 0)['schemaVersion'], '1.1.0')
        later = dict(rally_cases.base_session(), schemaVersion='1.2.0')
        self.assertEqual(rally.set_session_rolls(later, 0, 0)['schemaVersion'], '1.2.0')

    def test_committed_session_is_the_writers_output(self):
        self.assertEqual(load('session.rolls.json'), rally_cases.rolls_session())


if __name__ == '__main__':
    unittest.main()
