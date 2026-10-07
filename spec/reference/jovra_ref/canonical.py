"""Deterministic JSON layout for fixtures: nested containers stay multi-line near the top, while short
containers and deep records (one point, one game) collapse onto a single line so diffs stay readable.
Layout is cosmetic: consumers compare parsed values, never bytes, for JSON fixtures."""

from __future__ import annotations

import json

INLINE_WIDTH = 100
RECORD_DEPTH = 3  # list elements at or below this depth (one point, one game, one log event) take one line


def _one_line(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(", ", ": "))


def dumps(obj, depth: int = 0, in_list: bool = False) -> str:
    if not isinstance(obj, (dict, list)) or not obj:
        return _one_line(obj)
    flat = _one_line(obj)
    if len(flat) <= INLINE_WIDTH or (in_list and depth >= RECORD_DEPTH):
        return flat
    pad = "  " * (depth + 1)
    end = "  " * depth
    if isinstance(obj, dict):
        body = ",\n".join(f"{pad}{json.dumps(k, ensure_ascii=False)}: {dumps(v, depth + 1)}" for k, v in obj.items())
        return "{\n" + body + "\n" + end + "}"
    body = ",\n".join(pad + dumps(v, depth + 1, True) for v in obj)
    return "[\n" + body + "\n" + end + "]"
