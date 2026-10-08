"""Shared exact arithmetic, canonical hashing, typed rejections and the fixture patch helper.

Standard library only. No floating point reaches a decision: times are integer microseconds or exact
Fractions, and every rounding goes through one half-up function (the time analogue of ADR-0011).
"""

from __future__ import annotations

import copy
import hashlib
import json
from datetime import datetime
from fractions import Fraction
from math import isqrt

US_PER_S = 1_000_000


class Reject(ValueError):
    """A rule violation with a stable machine code (fixtures assert the code, not the message)."""

    def __init__(self, code: str, message: str):
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


def require(condition: bool, code: str, message: str) -> None:
    if not condition:
        raise Reject(code, message)


# ----- rounding ---------------------------------------------------------------------------------

def round_half_up(value: Fraction | int) -> int:
    """floor(value + 1/2) in exact arithmetic. Python's round() is half-even and is never used here."""
    value = Fraction(value)
    return (value + Fraction(1, 2)).__floor__()


def sqrt_half_up(value: Fraction | int) -> int:
    """floor(sqrt(value) + 1/2) for value >= 0, exactly: floor((floor(sqrt(4v)) + 1) / 2)."""
    value = Fraction(value)
    if value < 0:
        raise ValueError("negative square root")
    return (isqrt((4 * value).__floor__()) + 1) // 2


# ----- wall-clock timestamps -----------------------------------------------------------------------

def when(stamp: str) -> datetime:
    """Parse an RFC 3339 'Z' timestamp (studio-common dateTime) for ordering. Timestamps are never compared as text:
    the schema allows fractional seconds, and '...:00.500Z' sorts before '...:00Z' as a string."""
    if type(stamp) is not str or not stamp.endswith("Z"):
        raise Reject("badTimestamp", f"{stamp!r} is not an RFC 3339 UTC timestamp")
    try:
        return datetime.fromisoformat(stamp[:-1] + "+00:00")
    except ValueError as exc:
        raise Reject("badTimestamp", f"{stamp!r}: {exc}") from None


# ----- time ---------------------------------------------------------------------------------------

def fps_fraction(fps: dict) -> Fraction:
    return Fraction(fps["num"], fps["den"])


def frame_duration_us(fps: dict) -> Fraction:
    return Fraction(US_PER_S * fps["den"], fps["num"])


def frame_start_us(frame: int, fps: dict) -> Fraction:
    """Exact start time of a CFR frame, in microseconds, as a Fraction."""
    return frame * frame_duration_us(fps)


def frame_at_us(time_us: Fraction | int, fps: dict) -> int:
    """The one time -> frame rule: frame = floor(t * fps + 1/2) (multicam-sync research section 7)."""
    return round_half_up(Fraction(time_us) * fps_fraction(fps) / US_PER_S)


def seconds(frames: int, fps: dict) -> Fraction:
    return Fraction(frames) / fps_fraction(fps)


def rate_fraction(rate: dict) -> Fraction:
    return Fraction(rate["num"], rate["den"])


# ----- percentages (identical to the core engine's integer pct) ---------------------------------

def pct(n: int, d: int):
    """(200n + d) div 2d, half-up; d = 0 gives None (display an em dash)."""
    if d == 0:
        return None
    return (200 * n + d) // (2 * d)


def delta_pp_display(before, after) -> str:
    if before is None or after is None:
        return "—"
    delta = after - before
    unit = "percentage point" if abs(delta) == 1 else "percentage points"
    sign = "+" if delta > 0 else ""
    return f"{sign}{delta} {unit}"


# ----- canonical JSON and hashing ---------------------------------------------------------------

def _no_floats(value, where="$"):
    if isinstance(value, float):
        raise Reject("floatInContract", f"{where}: floating point value {value!r}; use integers or rationals")
    if isinstance(value, dict):
        for key, item in value.items():
            _no_floats(item, f"{where}.{key}")
    elif isinstance(value, list):
        for i, item in enumerate(value):
            _no_floats(item, f"{where}[{i}]")


def canonical_bytes(value) -> bytes:
    """Sorted keys, no insignificant whitespace, UTF-8. Equal to RFC 8785 for documents without floats,
    which is why floats are refused rather than serialized."""
    _no_floats(value)
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def canonical_sha256(value) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def output_spec_sha256(plan: dict) -> str:
    """The server-side reservation key component: canonical SHA-256 of (projectId, planRevision, output) of a stored
    plan version. The gateway computes it from the plan it holds; a client-supplied hash is never used."""
    return canonical_sha256({"projectId": plan["projectId"], "planRevision": plan["planRevision"], "output": plan["output"]})


# ----- fixture patches (a small subset of RFC 6902) ---------------------------------------------

def _pointer(path: str) -> list:
    if path == "":
        return []
    if not path.startswith("/"):
        raise ValueError(f"bad pointer {path!r}")
    out = []
    for token in path[1:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        out.append(int(token) if token.isdigit() else token)
    return out


def apply_patch(document, operations: list):
    """Return a patched deep copy. Ops: replace, add (object key or list index/'-'), remove."""
    doc = copy.deepcopy(document)
    for op in operations:
        tokens = _pointer(op["path"])
        if not tokens:
            raise ValueError("cannot patch the document root")
        parent = doc
        for token in tokens[:-1]:
            parent = parent[token]
        last = tokens[-1]
        kind = op["op"]
        if kind == "replace":
            if isinstance(parent, list):
                parent[last] = copy.deepcopy(op["value"])
            else:
                if last not in parent:
                    raise ValueError(f"replace of missing key {op['path']}")
                parent[last] = copy.deepcopy(op["value"])
        elif kind == "add":
            if isinstance(parent, list):
                if last == "-":
                    parent.append(copy.deepcopy(op["value"]))
                else:
                    parent.insert(last, copy.deepcopy(op["value"]))
            else:
                parent[last] = copy.deepcopy(op["value"])
        elif kind == "remove":
            del parent[last]
        else:
            raise ValueError(f"unsupported patch op {kind!r}")
    return doc
