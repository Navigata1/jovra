"""Canonical byte vectors worked by hand; source fixture layout remains cosmetic."""
from __future__ import annotations

CASES = [{'id': 'integral', 'input': '1.0', 'canonical': '1'}, {'id': 'negative-zero', 'input': '-0.0', 'canonical': '0'}, {'id': 'small-exponent', 'input': '1e-7', 'canonical': '0.0000001'}, {'id': 'fractional-zeroes', 'input': '1.2300', 'canonical': '1.23'}, {'id': 'large-integer', 'input': '9007199254740993', 'canonical': '9007199254740993'}, {'id': 'integer-exponent', 'input': '1.2e3', 'canonical': '1200'}, {'id': 'negative-decimal', 'input': '-12.300', 'canonical': '-12.3'}, {'id': 'empty', 'input': '{}', 'canonical': '{}'}, {'id': 'sorted-nested', 'input': '{"z":null,"a":{"b":true,"a":[1.0,2.50]}}', 'canonical': '{"a":{"a":[1,2.5],"b":true},"z":null}'}, {'id': 'unicode-slash', 'input': '{"text":"See / café 🎾"}', 'canonical': '{"text":"See / café 🎾"}'}, {'id': 'controls', 'input': '{"text":"line\\nnext\\tcell"}', 'canonical': '{"text":"line\\nnext\\tcell"}'}]


CASES += [
    {"id": "all-controls-and-quote-backslash", "input": r'{"text":"\b\f\n\r\t\u0000\u001f\"\\\/"}',
     "canonical": r'{"text":"\b\f\n\r\t\u0000\u001f\"\\/"}'},
    {"id": "escaped-surrogate-pair", "input": r'{"text":"\ud83c\udfbe"}',
     "canonical": '{"text":"🎾"}'},
]

ORDER = 35


def generate(ctx):
    ctx.write_json(ctx.contracts / "canonical-json.v1.json", {
        "schemaVersion": ctx.version, "kind": "jovra.fixture.canonical", "id": "CJSON01",
        "title": "Independent exact numeric, key-order and escaping bytes", "cases": CASES})
    return 1


def check(path, doc, docs):
    from canonical_json import canonicalize
    problems = []
    for case in doc["cases"]:
        if canonicalize(case["input"]) != case["canonical"]:
            problems.append(f"canonical case {case['id']} differs from its hand-derived bytes")
    return problems


CHECKS = {"jovra.fixture.canonical": check}
