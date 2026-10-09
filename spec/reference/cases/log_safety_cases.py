"""A hand-derived missing-anchor refusal for a cyclic future supersede chain."""
from .common import CLUB_BO3, singles
from jovra_ref import conformance

ORDER = 13


def generate(ctx):
    setup = singles(CLUB_BO3)
    setup['log'] = [dict(id=f'p{i:02}', seq=i, type='point', reviewed={
        'winner': 'A', 'endType': 'unknown', 'provenance': 'manual', 'source': 'user'}) for i in range(1, 4)]
    setup['log'][0]['insertBefore'] = 'p02'
    setup['log'][1]['supersedes'] = 'p03'
    setup['log'][2]['supersedes'] = 'p02'
    actual = conformance.run_scoring_error(setup)
    if actual != 'insertTargetMissing':
        raise ValueError(f'future supersede cycle: expected insertTargetMissing, got {actual}')
    ctx.write_json(ctx.fixtures / 'scoring/E18-future-supersede-anchor-cycle.json', {
        'schemaVersion': '1.2.0', 'kind': 'jovra.fixture.scoring', 'id': 'E18-future-supersede-anchor-cycle',
        'title': 'Cyclic future corrections cannot supply an earlier insert anchor',
        'covers': ['ADR0003', 'insertTargetMissing', 'bounded-log-traversal'], 'input': setup,
        'expectError': {'code': 'insertTargetMissing'}})
    return 1
