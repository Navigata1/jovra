#!/usr/bin/env python3
"""Independently schema-check and compare emitted Swift folds against every Python golden.

Run Swift tests with JOVRA_SCORING_OUTPUT_DIR, then pass that directory here. Uses the independent
Python canonical serializer, never Swift's output models or its comparison implementation.
"""
import json
import sys
from pathlib import Path
from canonical_json import canonicalize
from jsonschema_subset import SchemaSet

ROOT = Path(__file__).resolve().parents[2]


def verify(directory: Path) -> int:
    schemas = SchemaSet(ROOT / 'spec/schemas')
    schemas.files['native-fold.schema.json'] = {'$ref': 'engine-output.schema.json#/$defs/foldResult'}
    expected_files = set()
    for path in sorted((ROOT / 'spec/fixtures/scoring').glob('*.json')):
        fixture = json.loads(path.read_text())
        for index, checkpoint in enumerate(fixture.get('checkpoints', [])):
            name = f"{fixture['id']}-{index}.json"
            expected_files.add(name)
            encoded = (directory / name).read_text(encoding='utf-8')
            actual = json.loads(encoded)
            errors = schemas.validate(actual, 'native-fold.schema.json')
            if errors:
                raise ValueError(f'{name}: {errors}')
            expected = canonicalize(json.dumps(checkpoint['expected']['fold'], ensure_ascii=False))
            if encoded != expected:
                raise ValueError(f'{name}: native bytes differ from independent golden canonical bytes')
            if not schemas.validate({**actual, 'unregistered': True}, 'native-fold.schema.json'):
                raise ValueError('schema negative control accepted an unknown output field')
    actual_files = {path.name for path in directory.glob('*.json')}
    if actual_files != expected_files:
        raise ValueError(f'output manifest differs: missing={expected_files-actual_files}, extra={actual_files-expected_files}')
    print(f'PASS: {len(expected_files)} native folds independently schema-valid and byte-equal; schema negative controls refused')
    return len(expected_files)


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
