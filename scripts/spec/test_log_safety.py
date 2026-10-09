#!/usr/bin/env python3
"""A future correction cycle must terminate at the public fold seam."""
import json
import subprocess
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'spec/reference'))
from cases.common import CLUB_BO3, singles

class LogTraversalSafety(unittest.TestCase):
    def test_future_supersede_cycle_refuses_missing_insert_anchor(self):
        setup = singles(CLUB_BO3)
        setup['log'] = [dict(id=f'p{i:02}', seq=i, type='point', reviewed={
            'winner': 'A', 'endType': 'unknown', 'provenance': 'manual', 'source': 'user'}) for i in range(1, 4)]
        setup['log'][0]['insertBefore'] = 'p02'
        setup['log'][1]['supersedes'] = 'p03'
        setup['log'][2]['supersedes'] = 'p02'
        code = '''import json,sys
sys.path.insert(0, 'spec/reference')
from jovra_ref.scoring import fold
from jovra_ref.log import LogError
setup=json.loads(sys.stdin.read())
try: fold(setup,setup['log'])
except LogError as error: print(error.code)
'''
        child = subprocess.run([sys.executable, '-c', code], cwd=ROOT, input=json.dumps(setup),
                               text=True, capture_output=True, timeout=2)
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertEqual(child.stdout.strip(), 'insertTargetMissing')
