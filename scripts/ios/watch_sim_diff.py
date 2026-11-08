#!/usr/bin/env python3
"""Compare two `xcrun simctl list devices -j` captures around scripts/ios/watch-sim.sh (ticket W03).

Usage: watch_sim_diff.py --command create|delete BEFORE.json AFTER.json NAME...

A device's identity is (udid, name, device type, runtime); its boot state is not compared because other agents boot
and shut down their own simulators concurrently. The check fails when:
  - a device that is not one of NAME was removed or changed identity (the script must never touch it);
  - `create` left any NAME missing, or `delete` left any NAME present;
  - a NAME device changed in a way the command does not explain (create never removes, delete never adds).
Devices that are not NAME and appear only in AFTER were added by another process; they are listed, not failed.
Other devices are summarised by count and a SHA-256 of their sorted identities, so the report names no simulator that
belongs to anything else on the machine. Exit status 1 on any failure.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

Identity = tuple[str, str, str, str]


def identities(path: pathlib.Path) -> dict[str, Identity]:
    devices = json.loads(path.read_text(encoding="utf-8"))["devices"]
    return {
        d["udid"]: (d["udid"], d["name"], d.get("deviceTypeIdentifier", ""), runtime)
        for runtime, entries in devices.items()
        for d in entries
    }


def digest(items: list[Identity]) -> str:
    return hashlib.sha256("\n".join("|".join(i) for i in sorted(items)).encode()).hexdigest()[:16]


def compare(command: str, before: dict[str, Identity], after: dict[str, Identity], names: list[str]) -> tuple[list[str], list[str]]:
    ours = set(names)
    lines: list[str] = []
    problems: list[str] = []
    other_before = [i for i in before.values() if i[1] not in ours]
    other_after = {u: i for u, i in after.items() if i[1] not in ours}
    for ident in other_before:
        if other_after.get(ident[0]) != ident:
            problems.append(f"a device this script does not own was removed or changed: {ident[0]}")
    added = [i for u, i in other_after.items() if u not in before]
    kept = [i for i in other_before if other_after.get(i[0]) == i]
    lines.append(f"other devices before: {len(other_before)} (identity sha256 {digest(other_before)})")
    lines.append(f"other devices after, unchanged: {len(kept)} (identity sha256 {digest(kept)})")
    if added:
        lines.append(f"other devices added meanwhile by another process (not touched): {len(added)}")
    for name in names:
        was = [i for i in before.values() if i[1] == name]
        now = [i for i in after.values() if i[1] == name]
        lines.append(f"{name}: before {[i[0] for i in was] or 'absent'} -> after {[i[0] for i in now] or 'absent'}"
                     + (f" ({now[0][3].rsplit('.', 1)[-1]})" if now else ""))
        if command == "create":
            if not now:
                problems.append(f"{name} is missing after create")
            if any(i not in now for i in was):
                problems.append(f"create removed or changed the existing {name}")
        else:
            if now:
                problems.append(f"{name} is still present after delete")
    return lines, problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--command", choices=["create", "delete"], required=True)
    parser.add_argument("before", type=pathlib.Path)
    parser.add_argument("after", type=pathlib.Path)
    parser.add_argument("names", nargs="+")
    args = parser.parse_args(argv)
    lines, problems = compare(args.command, identities(args.before), identities(args.after), args.names)
    print(f"watch-sim.sh {args.command}: simctl list before/after")
    for line in lines:
        print(f"  {line}")
    for problem in problems:
        print(f"  FAIL {problem}")
    print(f"  result: {'FAIL' if problems else 'PASS'} ({len(problems)} problem(s))")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
