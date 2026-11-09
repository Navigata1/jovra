"""Compare simulator inventories using the checkout's recorded device identities."""
from __future__ import annotations

import hashlib

Identity = tuple[str, str, str, str]


def identities(inventory: dict) -> dict[str, Identity]:
    result = {}
    for runtime, entries in inventory["devices"].items():
        for device in entries:
            udid = device["udid"].upper()
            if udid in result:
                raise ValueError(f"duplicate simulator UUID: {udid}")
            result[udid] = (udid, device["name"], device.get("deviceTypeIdentifier", ""), runtime)
    return result


def digest(items: list[Identity]) -> str:
    return hashlib.sha256("\n".join("|".join(i) for i in sorted(items)).encode()).hexdigest()[:16]


def compare(command: str, before: dict[str, Identity], after: dict[str, Identity],
            owned: list[Identity]) -> tuple[list[str], list[str]]:
    ours = {ident[0] for ident in owned}
    other_before = [ident for udid, ident in before.items() if udid not in ours]
    kept = [ident for ident in other_before if after.get(ident[0]) == ident]
    added = [udid for udid in after if udid not in before and udid not in ours]
    lines = [
        f"other devices before: {len(other_before)} (identity sha256 {digest(other_before)})",
        f"other devices after, unchanged: {len(kept)} (identity sha256 {digest(kept)})",
    ]
    problems = [
        f"a device this script does not own was removed or changed: {ident[0]}"
        for ident in other_before if after.get(ident[0]) != ident
    ]
    if added:
        lines.append(f"other devices added meanwhile by another process (not touched): {len(added)}")
    for ident in owned:
        udid, name, _, runtime = ident
        now = after.get(udid)
        if command == "create":
            lines.append(f"{name}: {udid} ({runtime.rsplit('.', 1)[-1]})")
            if now is None:
                problems.append(f"{name} is missing after create")
            elif now != ident or (udid in before and before[udid] != ident):
                problems.append(f"create changed the identity of {name} ({udid})")
        else:
            lines.append(f"{name}: {udid} -> {'absent' if now is None else 'present'}")
            if before.get(udid) != ident:
                problems.append(f"{name} did not match the recorded identity before delete")
            if now is not None:
                problems.append(f"{name} is still present after delete")
    return lines, problems
