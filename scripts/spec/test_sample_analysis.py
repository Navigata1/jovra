#!/usr/bin/env python3
"""The sample analysis fixture's checks can fail (T40): its fractions move when one placement moves, a serve mark two
frames from the rendered contact is refused, a hand-edited expectation is refused and a calibration that no longer
matches the rendered pixels is refused."""
import copy
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'scripts/spec'), str(ROOT / 'spec/reference')]
from jsonschema_subset import SchemaSet  # noqa: E402
from cases import sample_analysis_cases, sample_media  # noqa: E402
from jovra_ref import sample_match  # noqa: E402

SAMPLE = ROOT / 'spec/fixtures/sample'
ORACLE = SAMPLE / 'analysis/analysis.expected.json'
JON_VS_ALEX = 'analysis/sessions/jon-vs-alex.analysis.json'
OCT_4 = 'analysis/sessions/2026-10-04-serve-practice.analysis.json'


def truth_docs() -> dict:
    folder = ROOT / 'spec/fixtures/media/sample'
    return {path: json.loads(path.read_text(encoding='utf-8')) for path in sorted(folder.glob('*.truth.json'))}


def load(rel: str) -> dict:
    return json.loads((SAMPLE / rel).read_text(encoding='utf-8'))


def installed(jva_record: dict) -> list[dict]:
    library = load('library/library.expected.json')
    sessions = [load(f'library/{name}') for name in library['sessionFiles']]
    return [sample_match.apply_analysis(s, jva_record) if s['id'] == jva_record['sessionId'] else s for s in sessions]


class SampleAnalysisFixture(unittest.TestCase):
    def setUp(self):
        self.oracle = json.loads(ORACLE.read_text(encoding='utf-8'))
        self.truths = truth_docs()

    def check_copy(self, mutate) -> list[str]:
        """Runs the fixture check over a copy of spec/fixtures/sample whose files `mutate(root)` has edited."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'sample'
            shutil.copytree(SAMPLE, root)
            mutate(root)
            path = root / 'analysis/analysis.expected.json'
            doc = json.loads(path.read_text(encoding='utf-8'))
            return sample_analysis_cases.check_analysis(path, doc, self.truths)

    @staticmethod
    def edit(root: Path, rel: str, change) -> None:
        doc = json.loads((root / rel).read_text(encoding='utf-8'))
        change(doc)
        (root / rel).write_text(json.dumps(doc), encoding='utf-8')

    def test_committed_fixture_is_schema_valid_and_passes_its_checks(self):
        schemas = SchemaSet(ROOT / 'spec/schemas')
        self.assertEqual(schemas.validate(self.oracle, 'fixture-sample-analysis.schema.json'), [])
        for name in self.oracle['analysisFiles']:
            self.assertEqual(schemas.validate(load(f'analysis/{name}'), 'sample-analysis.schema.json'), [], name)
        self.assertEqual(self.check_copy(lambda root: None), [])

    def test_moving_one_placement_changes_the_oracle_fractions(self):
        record = load(JON_VS_ALEX)
        before = sample_match.analysis_summary(installed(record), sample_media.manifest())['shotPlacement'][0]
        moved = copy.deepcopy(record)
        deep = next(s for s in moved['shots'] if s['stroke'] == 'forehand' and s.get('placement', {}).get('inOut') == 'in'
                    and abs(s['placement']['court']['y']) > sample_match.SERVICE_LINE)
        deep['placement']['court']['y'] = 3.0 if deep['placement']['court']['y'] > 0 else -3.0
        after = sample_match.analysis_summary(installed(moved), sample_media.manifest())['shotPlacement'][0]
        self.assertEqual((before['deep']['n'], before['short']['n']), (31, 12))
        self.assertEqual((after['deep'], after['short']),
                         ({'n': 30, 'd': 50, 'pct': 60, 'display': '60%'}, {'n': 13, 'd': 50, 'pct': 26, 'display': '26%'}))

    def test_a_moved_placement_in_the_committed_files_is_refused(self):
        def mutate(root):
            def change(doc):
                shot = next(s for s in doc['shots'] if s.get('placement', {}).get('inOut') == 'out')
                shot['placement']['inOut'] = 'in'
                shot['placement']['court'] = {'x': 0.5, 'y': 9.0}
            self.edit(root, JON_VS_ALEX, change)
        self.assertIn('analysis summary differs from the reference generator', self.check_copy(mutate))

    def test_a_serve_mark_two_frames_from_the_rendered_contact_is_refused(self):
        def mutate(root):
            self.edit(root, OCT_4, lambda doc: doc['serveMarks'][3]['contactFrame'].update(
                value=doc['serveMarks'][3]['contactFrame']['value'] - 2))
        problems = self.check_copy(mutate)
        self.assertTrue(any('serve mark 4: contactFrame is' in p for p in problems), problems)

    def test_a_calibration_off_the_rendered_pixels_is_refused(self):
        def mutate(root):
            self.edit(root, OCT_4, lambda doc: doc['calibrations'][0]['imagePoints'][2].update(x=0.75))
        problems = self.check_copy(mutate)
        self.assertTrue(any('px from the rendered pixels' in p for p in problems), problems)

    def test_an_edited_expectation_is_refused(self):
        def mutate(root):
            self.edit(root, 'analysis/analysis.expected.json',
                      lambda doc: doc['expected']['shotPlacement'][0].update(tagged=134))
        self.assertIn('analysis summary differs from the reference generator', self.check_copy(mutate))

    def test_every_serve_mark_is_within_one_frame_of_the_rendered_serve(self):
        truth = json.loads((ROOT / 'spec/fixtures/media/sample/2026-10-04-behind-baseline-12-serves.truth.json')
                           .read_text(encoding='utf-8'))
        marks = load(OCT_4)['serveMarks']
        self.assertEqual(len(marks), 12)
        base = 300 * 60  # the clip starts 5:00 into the session, 60 fps
        for mark, serve in zip(marks, truth['serves']):
            self.assertLessEqual(abs(mark['contactFrame']['value'] - base - serve['contact']['frame']), 1)
            self.assertLessEqual(abs(mark['bounceFrame']['value'] - base - serve['bounce']['frame']), 1)


if __name__ == '__main__':
    unittest.main()
