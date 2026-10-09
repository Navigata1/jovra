#!/usr/bin/env python3
"""Independently validate every emitted Swift stat result and its exact golden bytes."""
import json
import sys
from pathlib import Path
from canonical_json import canonicalize
from jsonschema_subset import SchemaSet

ROOT = Path(__file__).resolve().parents[2]

def verify(directory: Path) -> int:
    schemas = SchemaSet(ROOT / 'spec/schemas')
    schemas.files['native-stats.schema.json'] = {'$ref': 'engine-output.schema.json#/$defs/statsResult'}
    expected = {}
    for path in sorted((ROOT / 'spec/fixtures').rglob('*.json')):
        fixture = json.loads(path.read_text())
        if fixture['kind'] == 'jovra.fixture.stats':
            expected[f"{fixture['id']}.json"] = fixture['expected']
        elif fixture['kind'] == 'jovra.fixture.scoring':
            for index, checkpoint in enumerate(fixture.get('checkpoints', [])):
                expected[f"{fixture['id']}-{index}.json"] = checkpoint['expected']['stats']
    for name, golden in expected.items():
        encoded = (directory / name).read_text(encoding='utf-8')
        actual = json.loads(encoded)
        errors = schemas.validate(actual, 'native-stats.schema.json')
        if errors:
            raise ValueError(f'{name}: {errors}')
        if encoded != canonicalize(json.dumps(golden, ensure_ascii=False)):
            raise ValueError(f'{name}: native bytes differ from independent golden canonical bytes')
        if not schemas.validate({**actual, 'unregistered': True}, 'native-stats.schema.json'):
            raise ValueError('schema negative control accepted an unknown output field')
    actual_files = {path.name for path in directory.glob('*.json')}
    if actual_files != set(expected):
        raise ValueError(f'output manifest differs: missing={set(expected)-actual_files}, extra={actual_files-set(expected)}')
    print(f'PASS: {len(expected)} native stat results independently schema-valid and byte-equal; schema negative controls refused')
    return len(expected)

if __name__ == '__main__':
    verify(Path(sys.argv[1]))
