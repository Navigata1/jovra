"""Hand-derived valid-output controls for inconsistent zero-stroke error observations."""
from .common import CLUB_BO3, singles
from jovra_ref import conformance

ORDER = 12


def generate(ctx):
    for index, end in enumerate(('forcedError', 'unforcedError'), 65):
        fixture_id = f"S{index}-zero-stroke-{'forced' if end == 'forcedError' else 'unforced'}-error"
        setup = singles(CLUB_BO3)
        setup['log'] = [{'id': 'p01', 'seq': 1, 'type': 'point', 'reviewState': 'reviewed', 'reviewed': {
            'winner': 'B', 'endType': end, 'strokeCount': 0, 'provenance': 'reviewed', 'source': 'user'}}]
        assertions = [{'checkpoint': 0, 'path': path, 'equals': value} for path, value in [
            ('fold.points[0].strokeCount', 0), ('fold.points[0].winner', 'B'),
            ('fold.points[0].rallyLength', None), ('fold.points[0].endType', end),
            ('fold.conflicts', [{'type': 'outcomeInconsistent', 'pointId': 'p01'}]),
            ('fold.next.before.points', {'A': 0, 'B': 1}), ('stats.rallyLength.unknown', 1),
            ('stats.rallyLength.0-4', 0), ('stats.shots.total', 0)]]
        checkpoints = conformance.run_scoring(setup, [1])
        errors = conformance.check_assertions(checkpoints, assertions)
        if errors:
            raise ValueError(f'{fixture_id}: {errors}')
        ctx.write_json(ctx.fixtures / 'scoring' / f'{fixture_id}.json', {
            'schemaVersion': '1.2.0', 'kind': 'jovra.fixture.scoring', 'id': fixture_id,
            'title': f'Zero-stroke {end}: keep observation, derived rally length unknown',
            'covers': ['C11', 'ADR0003', 'valid-input-valid-output'], 'input': setup,
            'assertions': assertions, 'checkpoints': checkpoints})
    return 2
