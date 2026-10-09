#!/usr/bin/env python3
"""Independent sorted canonical JSON for native conformance (ADR-0029), not fixture pretty printing."""
from __future__ import annotations

import argparse
from decimal import Decimal
import json
from pathlib import Path
import sys


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse(text: str):
    def reject_constant(value):
        raise ValueError(f"non-finite JSON number: {value}")
    return json.loads(text, parse_float=Decimal, parse_int=int,
                      parse_constant=reject_constant, object_pairs_hook=_pairs)


def dumps(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, Decimal):
        if not value.is_finite():
            raise ValueError("non-finite JSON number")
        if value.is_zero():
            return "0"
        result = format(value, "f")
        return result.rstrip("0").rstrip(".") if "." in result else result
    if isinstance(value, str):
        # Canonical output is UTF-8. A decoded lone UTF-16 surrogate is not a Unicode scalar.
        # Valid escaped surrogate pairs are already combined by json.loads and remain unescaped.
        try:
            value.encode("utf-8")
        except UnicodeEncodeError as exc:
            raise ValueError("unpaired Unicode surrogate in JSON string") from exc
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ",".join(dumps(item) for item in value) + "]"
    if isinstance(value, dict):
        if not all(isinstance(key, str) for key in value):
            raise ValueError("JSON object keys must be strings")
        return "{" + ",".join(dumps(key) + ":" + dumps(value[key]) for key in sorted(value)) + "}"
    raise TypeError("canonical values must come from exact JSON parsing; binary floats are not accepted")


def canonicalize(text: str) -> str:
    return dumps(parse(text))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", nargs="?", type=Path)
    args = parser.parse_args()
    text = args.file.read_text(encoding="utf-8") if args.file else sys.stdin.read()
    try:
        sys.stdout.write(canonicalize(text))
    except (ValueError, TypeError) as exc:
        print(f"canonical JSON refused: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
