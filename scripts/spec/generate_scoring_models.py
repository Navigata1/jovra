#!/usr/bin/env python3
"""Maintenance-only named Swift output model generation; never a runtime interpreter."""
from generate_swift_models import Generator, SPECS, ROOT, pascal, KEYWORDS

KEYWORDS.add("break")
g = Generator()
for file, (name, _) in SPECS.items():
    g.type(g.docs[file], file, '', name)
existing = set(g.output)
for key in g.docs['engine-output']['$defs']:
    g.names[('engine-output', '/$defs/' + key)] = 'Timeline' + pascal(key)
g.names[('engine-output', '/$defs/foldResult')] = 'MatchTimeline'
g.type(g.docs['engine-output']['$defs']['foldResult'], 'engine-output', '/$defs/foldResult', 'MatchTimeline')
destination = ROOT / 'ios/Packages/JovraCore/Sources/JovraCore/Scoring/TimelineModels.swift'
# Synthesized decodeIfPresent collapses explicit null into absence for this optional nullable field.
decoder = (ROOT / 'scripts/spec/templates/timeline-null-decoder.swift.txt').read_text()
g.output['MatchTimeline'] = g.output['MatchTimeline'].replace('    public init(match:', decoder + '    public init(match:')
destination.write_text('// Generated concrete output models by scripts/spec/generate_scoring_models.py.\nimport Foundation\n\n' + '\n'.join(g.output[k] for k in sorted(set(g.output)-existing)))
