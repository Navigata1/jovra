#!/usr/bin/env python3
"""Maintenance-only concrete stats schema mapping; no runtime schema interpreter."""
import json
from generate_swift_models import Generator, SPECS, ROOT, pascal, identifier


class StatsGenerator(Generator):
    def flatten(self, schema, file):
        result = super().flatten(schema, file)
        # allOf's inline required constraints apply alongside its referenced shape.
        extra = [key for part in schema.get('allOf', []) for key in part.get('required', [])]
        if extra:
            result['required'] = list(dict.fromkeys(result.get('required', []) + extra))
        return result

    def type(self, schema, file, path, hint):
        if file == 'engine-output' and path.endswith('/series/items'):
            return 'StatsMomentumPair'
        return super().type(schema, file, path, hint)

    def emit_object(self, name, schema, file, path):
        super().emit_object(name, schema, file, path)
        if any(identifier(key) != key for key in schema.get('properties', {})):
            keys = '    enum CodingKeys: String, CodingKey {\n' + ''.join(
                '        case ' + identifier(key) + ' = ' + json.dumps(key) + '\n'
                for key in schema['properties']) + '    }\n'
            self.output[name] = self.output[name].replace('    public init(', keys + '    public init(', 1)


g = StatsGenerator()
for file, (name, _) in SPECS.items():
    g.type(g.docs[file], file, '', name)
existing = set(g.output)
for key in g.docs['engine-output']['$defs']:
    g.names[('engine-output', '/$defs/' + key)] = 'Stats' + pascal(key)
g.names[('engine-output', '/$defs/statsResult')] = 'StatsResult'
g.names[('engine-output', '/$defs/sideStats')] = 'SideStats'
g.names[('engine-output', '/$defs/serveBlock')] = 'ServeStats'
g.type(g.docs['engine-output']['$defs']['statsResult'], 'engine-output', '/$defs/statsResult', 'StatsResult')
destination = ROOT / 'ios/Packages/JovraCore/Sources/JovraCore/Stats/StatsModels.swift'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text('// Generated concrete stats models by scripts/spec/generate_stats_models.py.\nimport Foundation\n\n' + '\n'.join(g.output[key] for key in sorted(set(g.output) - existing)))
