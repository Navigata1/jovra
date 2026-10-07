#!/usr/bin/env python3
"""Check real planning invariants with deliberately invalid plans; no rendering."""
from copy import deepcopy
from pathlib import Path
import json
from validate_edit_plan import validate

sample = json.loads((Path(__file__).resolve().parents[1] / 'examples/edit-plan.sample.json').read_text())
validate(sample)
cases = []
def altered(label, edit):
    plan = deepcopy(sample)
    edit(plan)
    cases.append((label, plan))
altered('unknown source', lambda p: p['segments'][0].update(sourceId='missing'))
altered('source overrun', lambda p: p['segments'][0].update(sourceInFrame=590, sourceOutFrame=710))
altered('output gap', lambda p: p['segments'][1].update(outputInFrame=121))
altered('incomplete timeline', lambda p: p['output'].update(totalFrames=241))
altered('short audio bed', lambda p: p['audio'].update(sourceOutFrame=269))
altered('missing audio', lambda p: p['audio'].update(sourceId='camera-b'))
altered('unsupported model operation', lambda p: p['segments'][0].update(transition='arbitrary-filter'))
altered('executable payload', lambda p: p.update(command='untrusted command'))
altered('unlabelled speed', lambda p: p['segments'][0].update(speed=1.25))
altered('bool frame', lambda p: p['segments'][0].update(sourceInFrame=True))
altered('mismatched proxy clock', lambda p: p['sources'][1].update(fps={'num': 24, 'den': 1}))
altered('stale score', lambda p: p['segments'][0].update(overlayRefs=[{'kind':'score','refId':'point-1','eventRevision':1,'provenance':'manual'}]))
for label, plan in cases:
    try:
        validate(plan)
    except ValueError:
        continue
    raise AssertionError('invalid plan accepted: ' + label)
print(json.dumps({'validSample': True, 'rejectedInvalidCases': len(cases), 'scope': 'planning invariants only; no media or cloud validation'}, indent=2))
