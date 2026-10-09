"""Patch and invalid-case helpers shared by the cases modules (not a cases module itself)."""

from __future__ import annotations


def rep(path, value):
    return {"op": "replace", "path": path, "value": value}


def add(path, value):
    return {"op": "add", "path": path, "value": value}


def rm(path):
    return {"op": "remove", "path": path}


def bad(cid, why, patch, code=None):
    return {"id": cid, "why": why, "patch": patch,
            "expect": {"layer": "schema"} if code is None else {"layer": "reference", "code": code}}


def invalid_docs(sets):
    return {name: {"schemaVersion": "jovra.studio-fixture.invalid-cases/1", "base": f"records/{name}.json", "cases": cases}
            for name, cases in sets.items()}
