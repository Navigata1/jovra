"""Shared by the fixture generator and scripts/spec/validate.py: run a fixture's input through the
reference engine and evaluate hand-written assertions."""

from __future__ import annotations

import re

from . import scoring, stats, units
from .log import LogError

_TOKEN = re.compile(r"([A-Za-z0-9_+-]+)|\[(\d+)\]")


def get_path(obj, path: str):
    """Evaluate a dotted path with [n] indexes, e.g. fold.points[3].call.kind (keys may contain '-' or '+')."""
    for part in path.split("."):
        pos = 0
        while pos < len(part):
            m = _TOKEN.match(part, pos)
            if m is None:
                raise KeyError(f"bad path {path!r}")
            if m.group(1) is not None:
                obj = obj[m.group(1)]
            else:
                obj = obj[int(m.group(2))]
            pos = m.end()
    return obj


def run_scoring(fixture_input: dict, after_seqs: list[int]) -> list[dict]:
    folds = scoring.fold_checkpoints(fixture_input, fixture_input["log"], after_seqs)
    out = []
    for seq, result in zip(after_seqs, folds):
        out.append({"afterSeq": seq, "expected": {"fold": result, "stats": stats.compute(result)}})
    return out


def run_scoring_error(fixture_input: dict) -> str | None:
    try:
        scoring.fold(fixture_input, fixture_input["log"])
    except LogError as exc:
        return exc.code
    return None


def check_assertions(checkpoints: list[dict], assertions: list[dict]) -> list[str]:
    failures = []
    for a in assertions:
        target = checkpoints[a["checkpoint"]]["expected"]
        try:
            actual = get_path(target, a["path"])
        except (KeyError, IndexError, TypeError) as exc:
            failures.append(f"checkpoint {a['checkpoint']} {a['path']}: path error {exc}")
            continue
        if actual != a["equals"]:
            failures.append(f"checkpoint {a['checkpoint']} {a['path']}: expected {a['equals']!r}, engine {actual!r}")
    return failures


def run_units_case(case: dict) -> dict:
    op = case["op"]
    if op == "convert":
        exact = units.convert(case["value"], case["from"], case["to"])
        return {"value": units.decimal_text(exact, case["places"])}
    if op == "display":
        return units.display(case["value"], case["unit"], case["preferredUnit"])
    if op == "gaugeHint":
        return units.gauge_hint(case["label"])
    raise ValueError(f"unknown units op {op}")


def run_pct_case(case: dict):
    op = case["op"]
    if op == "ratio":
        return stats.ratio(case["n"], case["d"])
    if op == "delta":
        return {"text": stats.delta_text(stats.ratio(*case["current"]), stats.ratio(*case["prior"]))}
    if op == "pool":
        return stats.pool([stats.ratio(n, d) for n, d in case["parts"]])
    raise ValueError(f"unknown pct op {op}")
