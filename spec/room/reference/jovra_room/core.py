"""Shared helpers: stable rejection codes, canonical JSON fingerprints, RFC 3339 parsing and a JSON-patch subset."""

from __future__ import annotations

import copy
import hashlib
import json
from datetime import datetime, timezone


class Reject(Exception):
    """A rule rejected an input. ``code`` is the stable, language-neutral code that fixtures pin."""

    def __init__(self, code: str, detail: str = ""):
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code


def canonical(obj) -> str:
    """Canonical JSON: sorted keys, no insignificant whitespace, UTF-8. Ports must produce the same bytes."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def fingerprint(obj) -> str:
    return hashlib.sha256(canonical(obj).encode("utf-8")).hexdigest()


def parse_time(text: str) -> datetime:
    fmt = "%Y-%m-%dT%H:%M:%S.%fZ" if "." in text else "%Y-%m-%dT%H:%M:%SZ"
    return datetime.strptime(text, fmt).replace(tzinfo=timezone.utc)


def seconds_between(earlier: str, later: str) -> float:
    """Only for two timestamps written by the same device's clock."""
    return (parse_time(later) - parse_time(earlier)).total_seconds()


def _pointer(path: str) -> list:
    if path == "":
        return []
    if not path.startswith("/"):
        raise ValueError(f"bad JSON pointer {path!r}")
    out = []
    for raw in path[1:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
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
            if not isinstance(parent, list) and last not in parent:
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
