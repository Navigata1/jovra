#!/usr/bin/env python3
"""V01: the label scoring fixtures, the hash-fixed split and the label set are checked, not just written.
A wrong expectation fails the fixture check, a hand-picked split or a label file edited after sealing fails
the label-set check, and the schema refuses imagery-shaped or malformed label documents."""
import copy
import hashlib
import json
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'scripts/spec'), str(ROOT / 'spec/reference')]
from jsonschema_subset import SchemaSet  # noqa: E402
from cases import label_scoring_cases as cases  # noqa: E402
from jovra_ref import labels  # noqa: E402

FIXTURES = ROOT / 'spec/benchmarks/scoring'
SCHEMAS = SchemaSet(ROOT / 'spec/schemas')


def load(name):
    return json.loads((FIXTURES / name).read_text(encoding='utf-8'))


def human_labels(recording_sha256, seconds=120, hits=3):
    doc = copy.deepcopy(cases.L01_LABELS)
    doc['recording'] = cases.recording(recording_sha256, seconds)
    doc['labelledBy'] = {'method': 'human', 'tool': 'jovra-label@1.0.0'}
    doc['split'] = labels.make_split(doc['recording'])
    doc['hits'] = doc['hits'][:hits]
    return doc


class FixturesAreChecked(unittest.TestCase):
    def test_committed_fixtures_reproduce(self):
        names = sorted(p.name for p in FIXTURES.glob('L*.json'))
        self.assertEqual(names, ['L01-every-kind-both-splits.json', 'L02-undefined-and-open.json'])
        for name in names:
            self.assertEqual(cases.fixture_problems(load(name)), [], name)
            self.assertEqual(SCHEMAS.validate(load(name), 'fixture-label-scoring.schema.json'), [], name)

    def test_a_wrong_expected_value_fails_the_check(self):
        doc = load('L01-every-kind-both-splits.json')
        row = next(r for r in doc['expected']['heldOut']['rows'] if r['group'] == 'hits' and r['name'] == 'recall')
        row['value'] = '0.8000'
        problems = cases.fixture_problems(doc)
        self.assertEqual(len(problems), 1)
        self.assertIn('heldOut hits / recall', problems[0])

    def test_moving_an_observation_across_the_tolerance_changes_the_result(self):
        doc = load('L01-every-kind-both-splits.json')
        doc['observations']['hits'][10]['time'] = {'value': 75101, 'timescale': 1000}   # 101 ms from its label
        self.assertTrue(any('tuning hits / matched' in p for p in cases.fixture_problems(doc)))

    def test_a_boundary_pair_is_counted_once_in_its_labels_split(self):
        doc = load('L01-every-kind-both-splits.json')
        result = labels.score(doc['labels'], doc['observations'], doc['tolerances'])
        observed = sum(int(r['value']) for name in labels.SPLITS for r in result[name]['rows']
                       if r['group'] == 'hits' and r['name'] == 'observations')
        self.assertEqual(observed, len(doc['observations']['hits']))

    def test_an_omitted_kind_has_no_rows_and_an_empty_one_is_scored(self):
        doc = load('L02-undefined-and-open.json')
        del doc['observations']['hits']
        rows = labels.score(doc['labels'], doc['observations'], doc['tolerances'])['tuning']['rows']
        self.assertNotIn('hits', {r['group'] for r in rows})
        recall = next(r for r in rows if r['group'] == 'bounces' and r['name'] == 'recall')
        self.assertEqual(recall['value'], '0.0000')


class SplitIsFixedByTheHash(unittest.TestCase):
    def test_held_out_and_tuning_windows_are_disjoint_and_cover_the_recording(self):
        for seed in range(40):
            sha = hashlib.sha256(f'recording {seed}'.encode()).hexdigest()
            for total in (1, 29_999, 30_000, 30_001, 90_000, 359_960, 4_277_700):
                recording = {'sha256': sha, 'duration': {'value': total, 'timescale': 1000}}
                split = labels.make_split(recording)
                n = labels.window_count(total, split['windowMs'])
                held, tuning = labels.windows_in('heldOut', split), labels.windows_in('tuning', split)
                self.assertEqual(set(held) & set(tuning), set())
                self.assertEqual(sorted(held + tuning), list(range(n)))
                covered = sum((b - a for i in held + tuning for a, b in [labels.window_range(i, split)]), Fraction(0))
                self.assertEqual(covered, Fraction(total, 1000))
                if n >= 2:
                    self.assertGreaterEqual(len(held), 1)
                    self.assertGreaterEqual(len(tuning), 1)
                else:
                    self.assertEqual(held, [])

    def test_the_share_is_three_in_ten_rounded_half_up(self):
        sha = cases.L01_RECORDING
        for windows, expected in ((2, 1), (3, 1), (4, 1), (5, 2), (10, 3), (142, 43)):
            self.assertEqual(len(labels.held_out_windows(sha, windows * 30_000, 30_000, 300)), expected, windows)

    def test_the_windows_follow_from_the_recording_hash_alone(self):
        self.assertEqual(labels.held_out_windows(cases.L01_RECORDING, 120_000, 30_000, 300), [1])
        other = hashlib.sha256(b'jovra synthetic recording 1\n').hexdigest()
        self.assertEqual(labels.held_out_windows(other, 120_000, 30_000, 300), [2])

    def test_a_time_on_a_boundary_belongs_to_the_later_window_and_the_end_to_the_last(self):
        split = cases.L01_LABELS['split']
        self.assertEqual(labels.split_of(Fraction(29_999, 1000), split), 'tuning')
        self.assertEqual(labels.split_of(Fraction(30), split), 'heldOut')
        self.assertEqual(labels.split_of(Fraction(60), split), 'tuning')
        self.assertEqual(labels.window_of(Fraction(120), split), 3)

    def test_a_hand_picked_split_is_refused(self):
        doc = copy.deepcopy(cases.L01_LABELS)
        doc['split']['heldOutWindows'] = [3]
        self.assertTrue(any('hash-fixed split' in p for p in labels.label_problems(doc)))


class LabelDocuments(unittest.TestCase):
    def test_the_fixture_labels_are_consistent(self):
        self.assertEqual(labels.label_problems(cases.L01_LABELS), [])
        self.assertEqual(labels.label_problems(cases.L02_LABELS), [])

    def test_order_duplicates_and_open_rallies(self):
        doc = copy.deepcopy(cases.L01_LABELS)
        doc['hits'][0], doc['hits'][1] = doc['hits'][1], doc['hits'][0]
        self.assertIn('hits are not in time order', labels.label_problems(doc))
        doc = copy.deepcopy(cases.L01_LABELS)
        doc['hits'].insert(1, copy.deepcopy(doc['hits'][0]))
        self.assertTrue(any('two hits by the near player' in p for p in labels.label_problems(doc)))
        doc = copy.deepcopy(cases.L01_LABELS)
        doc['rallies'][0]['end'] = None
        self.assertIn('rally 1 is open but is not the last rally', labels.label_problems(doc))
        doc = copy.deepcopy(cases.L01_LABELS)
        doc['bounces'][-1]['time'] = {'value': 121, 'timescale': 1}
        self.assertIn('bounces hold a time after the recording ends', labels.label_problems(doc))

    def test_the_schema_refuses_names_paths_and_points_outside_the_picture(self):
        schema = 'benchmark-labels.schema.json'
        self.assertEqual(SCHEMAS.validate(cases.L01_LABELS, schema), [])
        for mutate in (lambda d: d['recording'].update(fileName='match.mp4'),
                       lambda d: d['labelledBy'].update(name='Someone'),
                       lambda d: d['bounces'][0]['imagePoint'].update(x=1.2),
                       lambda d: d['hits'][0].update(stroke='smash'),
                       lambda d: d.update(frames=[])):
            doc = copy.deepcopy(cases.L01_LABELS)
            mutate(doc)
            self.assertNotEqual(SCHEMAS.validate(doc, schema), [])

    def test_observations_for_another_recording_are_refused(self):
        other = copy.deepcopy(cases.L01_OBSERVATIONS)
        other['recordingSha256'] = cases.L02_RECORDING
        self.assertIn('observations are for a different recording than the labels',
                      labels.observation_problems(other, cases.L01_LABELS))


class LabelSet(unittest.TestCase):
    def sealed(self, root, doc):
        name = f"rec-{doc['recording']['sha256'][:12]}.labels.json"
        path = root / 'spec/benchmarks/labels' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        data = (json.dumps(doc, indent=2, sort_keys=True) + '\n').encode()
        path.write_bytes(data)
        return {'path': f'spec/benchmarks/labels/{name}', 'recordingSha256': doc['recording']['sha256'],
                'labelsSha256': hashlib.sha256(data).hexdigest(), 'split': doc['split'], 'counts': labels.counts(doc)}, path

    def label_set(self, entries, status, target=3):
        return {'schemaVersion': '1.0.0', 'kind': 'jovra.benchmarkLabelSet', 'description': 'test', 'status': status,
                'recordings': [{'role': 'match', 'sha256': cases.L01_RECORDING, 'description': 'synthetic',
                                'targets': {'hits': target}}],
                'labelFiles': entries}

    def test_the_committed_set_is_founder_pending_with_the_ticket_targets(self):
        doc = json.loads((ROOT / 'spec/benchmarks/labels/manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(SCHEMAS.validate(doc, 'benchmark-label-set.schema.json'), [])
        self.assertEqual(cases.label_set_problems(doc), [])
        targets = {r['role']: r['targets'] for r in doc['recordings']}
        self.assertEqual(targets['match'], {'hits': 300, 'bounces': 150})
        self.assertEqual(targets['sideView'], {'strokes': 100})
        if not doc['labelFiles']:
            self.assertEqual(doc['status'], 'founderPending')

    def test_complete_only_when_every_target_is_met(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            entry, _ = self.sealed(root, human_labels(cases.L01_RECORDING, hits=3))
            self.assertEqual(cases.label_set_problems(self.label_set([entry], 'complete'), root), [])
            self.assertIn('status is founderPending but the targets say complete',
                          cases.label_set_problems(self.label_set([entry], 'founderPending'), root))
            self.assertIn('status is complete but the targets say founderPending',
                          cases.label_set_problems(self.label_set([entry], 'complete', target=4), root))
            self.assertIn('status is complete but the targets say founderPending',
                          cases.label_set_problems(self.label_set([], 'complete'), root))

    def test_labels_on_an_excerpt_do_not_count_towards_a_target(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            entry, _ = self.sealed(root, human_labels(cases.L02_RECORDING, hits=3))
            self.assertIn('status is complete but the targets say founderPending',
                          cases.label_set_problems(self.label_set([entry], 'complete'), root))

    def test_a_label_file_edited_after_sealing_is_refused(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            doc = human_labels(cases.L01_RECORDING)
            entry, path = self.sealed(root, doc)
            doc['hits'][0]['stroke'] = 'backhand'
            path.write_text(json.dumps(doc, indent=2, sort_keys=True) + '\n', encoding='utf-8')
            problems = cases.label_set_problems(self.label_set([entry], 'complete'), root)
            self.assertEqual(len(problems), 1)
            self.assertIn('changed after it was sealed', problems[0])

    def test_a_recorded_split_or_count_that_is_not_the_files_is_refused(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            entry, _ = self.sealed(root, human_labels(cases.L01_RECORDING))
            wrong = copy.deepcopy(entry)
            wrong['split']['heldOutWindows'] = [0]
            self.assertTrue(any('recorded split' in p for p in cases.label_set_problems(self.label_set([wrong], 'complete'), root)))
            wrong = copy.deepcopy(entry)
            wrong['counts']['hits'] = 300
            self.assertTrue(any('recorded counts' in p for p in cases.label_set_problems(self.label_set([wrong], 'complete'), root)))

    def test_synthetic_labels_an_open_rally_and_a_missing_file_are_refused(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            synthetic = human_labels(cases.L01_RECORDING)
            synthetic['labelledBy'] = {'method': 'synthetic', 'tool': 'fixture-author@1.0.0'}
            entry, _ = self.sealed(root, synthetic)
            self.assertTrue(any('only labels a person made' in p for p in cases.label_set_problems(self.label_set([entry], 'complete'), root)))
            unfinished = human_labels(cases.L01_RECORDING)
            unfinished['rallies'] = unfinished['rallies'][:1] + [{'start': {'value': 20, 'timescale': 1}, 'end': None}]
            entry, path = self.sealed(root, unfinished)
            self.assertTrue(any('open rally' in p for p in cases.label_set_problems(self.label_set([entry], 'complete'), root)))
            path.unlink()
            self.assertTrue(any('is not committed' in p for p in cases.label_set_problems(self.label_set([entry], 'complete'), root)))


if __name__ == '__main__':
    unittest.main()
