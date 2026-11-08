#!/usr/bin/env python3
"""The trend fixture's checks can fail: an averaging engine, a hand-edited expectation and an out-of-scope session
are each refused (T05)."""
import copy
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'scripts/spec'), str(ROOT / 'spec/reference')]
from jsonschema_subset import SchemaSet  # noqa: E402
from cases import trend_cases  # noqa: E402
from jovra_ref import stats, trend  # noqa: E402

FIXTURE = ROOT / 'spec/fixtures/trend/TR01-pooled-trends.json'


class TrendFixture(unittest.TestCase):
    def setUp(self):
        self.doc = json.loads(FIXTURE.read_text(encoding='utf-8'))

    def test_committed_fixture_is_schema_valid_and_passes_its_checks(self):
        schemas = SchemaSet(ROOT / 'spec/schemas')
        self.assertEqual(schemas.validate(self.doc, 'fixture-trend.schema.json'), [])
        self.assertEqual(trend_cases.check(FIXTURE, self.doc, {}), [])

    def test_an_engine_that_averages_percentages_is_refused(self):
        def averaged(ratios):
            shown = [r for r in ratios if r['d']]
            if not shown:
                return stats.ratio(0, 0)
            mean = round(sum(r['pct'] for r in shown) / len(shown))
            return {**stats.ratio(sum(r['n'] for r in ratios), sum(r['d'] for r in ratios)), 'pct': mean,
                    'display': f'{mean}%'}
        with mock.patch.object(trend, 'pool', averaged):
            problems = trend_cases.check(FIXTURE, self.doc, {})
        self.assertTrue(any('pool-not-average' in p for p in problems), problems)

    def test_a_hand_edited_expectation_is_refused(self):
        doc = copy.deepcopy(self.doc)
        case = next(c for c in doc['cases'] if c['name'] == 'weekly-first-serves-in')
        case['expected']['headline']['deltaPoints'] = 3  # the raw 66.67 - 63.33, not the displayed integers
        problems = trend_cases.check(FIXTURE, doc, {})
        self.assertTrue(any('weekly-first-serves-in' in p for p in problems), problems)

    def test_a_sample_session_never_reaches_a_real_trend(self):
        sessions = [{'id': 'demo', 'date': '2026-10-04', 'comparableKind': 'singlesMatch', 'sample': True, 'n': 9, 'd': 9}]
        real = trend.bucketed(sessions, range_='4W', as_of='2026-10-06', comparable_kind='singlesMatch')
        self.assertEqual(real['sessionCount'], 0)
        self.assertEqual(real['excluded']['otherScope'], 1)
        self.assertEqual(real['state'], 'noData')

    def test_schema_refuses_an_unknown_field(self):
        schemas = SchemaSet(ROOT / 'spec/schemas')
        doc = copy.deepcopy(self.doc)
        doc['cases'][0]['expected']['average'] = 62
        self.assertNotEqual(schemas.validate(doc, 'fixture-trend.schema.json'), [])


if __name__ == '__main__':
    unittest.main()
