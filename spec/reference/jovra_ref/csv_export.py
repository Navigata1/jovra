"""CSV export driven by the hand-written contracts in spec/contracts/csv/ (column order, null and boolean
spelling, quoting and line endings all come from the contract)."""

from __future__ import annotations

import json
from pathlib import Path

from .conformance import get_path
from .scoring import call_text

CONTRACTS = Path(__file__).resolve().parents[2] / "contracts" / "csv"


def load_contract(name: str) -> dict:
    return json.loads((CONTRACTS / f"{name}.v1.json").read_text(encoding="utf-8"))


def _cell(value, contract: dict) -> str:
    if value is None:
        return contract["null"]
    if isinstance(value, bool):
        return contract["booleans"][0] if value else contract["booleans"][1]
    text = str(value)
    if contract["quoting"] == "minimal" and any(ch in text for ch in (contract["delimiter"], '"', "\r", "\n")):
        text = '"' + text.replace('"', '""') + '"'
    return text


def _render(rows: list[dict], contract: dict) -> str:
    names = [c["name"] for c in contract["columns"]]
    lines = []
    if contract["header"]:
        lines.append(contract["delimiter"].join(names))
    for row in rows:
        lines.append(contract["delimiter"].join(_cell(row.get(n), contract) for n in names))
    return "".join(line + contract["lineEnding"] for line in lines)


def _names(players: list[dict]) -> dict:
    return {p["id"]: p["displayName"] for p in players}


def points_csv(session_input: dict, fold_result: dict) -> str:
    contract = load_contract("points")
    names = _names(session_input["players"])
    side_names = {s: " / ".join(names[p] for p in session_input["sides"][s]) for s in ("A", "B")}
    rows = []
    for p in fold_result["points"]:
        before = p["before"]
        rows.append({
            "point_number": p["index"] + 1,
            "point_id": p["id"],
            "kind": p["kind"],
            "set_number": None if p["set"] is None else p["set"] + 1,
            "game_number": None if p["game"] is None else p["game"] + 1,
            "game_in_set": None if p["gameInSet"] is None else p["gameInSet"] + 1,
            "tiebreak": p["tiebreak"],
            "server": names.get(p["server"]) if p["server"] else None,
            "receiver": names.get(p["receiver"]) if p["receiver"] else None,
            "server_side": p["serverSide"],
            "court_side": p["courtSide"],
            "score_before": call_text(p["call"], p["serverSide"]) if p["call"] else None,
            "games_before": f"{before['games']['A']}-{before['games']['B']}" if before else None,
            "sets_before": f"{before['sets']['A']}-{before['sets']['B']}" if before else None,
            "winner_side": p["winner"],
            "winner": side_names[p["winner"]] if p["winner"] else None,
            "end_type": p["endType"],
            "serve_number": p["serveNumber"],
            "stroke_count": p["strokeCount"],
            "rally_length": p["rallyLength"],
            "break_point": p["pressure"]["breakPoint"] if p["pressure"] else None,
            "t_start_ms": p.get("tStartMs"),
            "t_end_ms": p.get("tEndMs"),
            "provenance": p["provenance"],
            "review_state": p["reviewState"],
            "determined": p["determined"],
            "after_match_end": p["afterMatchEnd"],
        })
    return _render(rows, contract)


def stats_csv(session_input: dict, stats_result: dict) -> str:
    contract = load_contract("stats")
    names = _names(session_input["players"])
    side_names = {s: " / ".join(names[p] for p in session_input["sides"][s]) for s in ("A", "B")}
    rows = []
    for spec in contract["rows"]:
        scopes = [("A", stats_result["sides"]["A"]), ("B", stats_result["sides"]["B"])] \
            if spec["scope"] == "side" else [(None, stats_result)]
        for side, source in scopes:
            value = get_path(source, spec["stat"])
            row = {"stat": spec["stat"], "side": side, "players": side_names[side] if side else None}
            if isinstance(value, dict):
                row.update({"numerator": value["n"], "denominator": value["d"], "pct": value["pct"],
                            "display": value["display"]})
            else:
                row.update({"numerator": value, "denominator": None, "pct": None, "display": str(value)})
            rows.append(row)
    return _render(rows, contract)
