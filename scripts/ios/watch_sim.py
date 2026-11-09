"""Create, identify and delete the watch simulators allocated by this checkout."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from uuid import UUID

from watch_sim_diff import Identity, compare, identities

TYPE = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-"
TYPES = {
    "JOVRA Watch Ultra 3 49mm": TYPE + "Ultra-3-49mm",
    "JOVRA Watch Series 11 42mm": TYPE + "Series-11-42mm",
    "JOVRA Watch SE 3 40mm": TYPE + "SE-3-40mm",
}
RUNTIME = r"com\.apple\.CoreSimulator\.SimRuntime\.watchOS-([0-9]+(?:-[0-9]+)+)"


def simctl(*args: str, check: bool = True) -> str:
    return subprocess.run(
        ["xcrun", "simctl", *args], check=check, text=True, capture_output=True,
    ).stdout.strip()


def runtime() -> str:
    chosen = os.environ.get("WATCH_RUNTIME")
    if chosen:
        if not re.fullmatch(RUNTIME, chosen):
            raise ValueError("WATCH_RUNTIME must be a watchOS simulator runtime identifier")
        return chosen
    available = re.findall(RUNTIME, simctl("list", "runtimes", "available"))
    if not available:
        raise ValueError("no available watchOS simulator runtime")
    newest = max(available, key=lambda version: tuple(map(int, version.split("-"))))
    return "com.apple.CoreSimulator.SimRuntime.watchOS-" + newest


def inventory() -> dict[str, Identity]:
    return identities(json.loads(simctl("list", "devices", "-j")))


def load_owners(receipt: Path) -> dict[str, Identity]:
    if not receipt.exists():
        return {}
    owners = {}
    records = json.loads(receipt.read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError("invalid simulator ownership receipt")
    for item in records:
        udid, name, kind, os_runtime = item
        if (str(UUID(udid)).upper() != udid or name in owners or TYPES.get(name) != kind
                or not re.fullmatch(RUNTIME, os_runtime)
                or any(other[0] == udid for other in owners.values())):
            raise ValueError("invalid simulator ownership receipt")
        owners[name] = (udid, name, kind, os_runtime)
    return owners


def save_owners(receipt: Path, owners: dict[str, Identity]) -> None:
    pending = receipt.with_suffix(".tmp")
    pending.write_text(json.dumps(list(owners.values()), indent=2) + "\n", encoding="utf-8")
    pending.replace(receipt)


def verify_owners(owners: dict[str, Identity], devices: dict[str, Identity]) -> None:
    for ident in devices.values():
        if ident[1] in TYPES and owners.get(ident[1]) != ident:
            raise ValueError(f"{ident[1]} ({ident[0]}) is not owned by this checkout or changed identity")
    for ident in owners.values():
        if devices.get(ident[0]) != ident:
            raise ValueError(f"recorded simulator {ident[1]} ({ident[0]}) is missing or changed identity")


def paired_watch_ids() -> set[str]:
    pairs = json.loads(simctl("list", "pairs", "-j"))["pairs"]
    return {pair["watch"]["udid"].upper() for pair in pairs.values()}


def create(receipt: Path, owners: dict[str, Identity], before: dict[str, Identity]) -> None:
    selected = runtime()
    if any(ident[3] != selected for ident in owners.values()):
        raise ValueError("recorded watches use another runtime; delete them before changing WATCH_RUNTIME")
    for name, kind in TYPES.items():
        if name in owners:
            print(f"   exists   {name} ({owners[name][0]})")
            continue
        udid = simctl("create", name, kind, selected).upper()
        ident = (udid, name, kind, selected)
        if (str(UUID(udid)).upper() != udid or udid in before
                or any(other[0] == udid for other in owners.values())
                or inventory().get(udid) != ident):
            raise ValueError(f"simctl returned an unexpected identity for {name} ({udid})")
        owners[name] = ident
        save_owners(receipt, owners)
        print(f"   created  {name} ({udid})")


def delete(receipt: Path, owners: dict[str, Identity]) -> None:
    for udid, name, _, _ in list(owners.values()):
        verify_owners(owners, inventory())
        if paired_watch_ids().intersection(ident[0] for ident in owners.values()):
            raise ValueError("refusing to delete a watch in an existing simulator pair")
        simctl("shutdown", udid, check=False)
        simctl("delete", udid)
        del owners[name]
        save_owners(receipt, owners)
        print(f"   deleted  {name} ({udid})")


def write_report(path: Path, report: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(report, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("create", "delete"):
        commands.add_parser(command).add_argument("--evidence", type=Path)
    commands.add_parser("list")
    commands.add_parser("udid").add_argument("name", choices=TYPES)
    args = parser.parse_args()
    directory = Path(__file__).resolve().parents[2] / ".cache" / "watch-sim"
    receipt = directory / "owned.json"
    evidence = getattr(args, "evidence", None)
    report_path = evidence / f"simctl-{args.command}.txt" if evidence else None
    try:
        directory.mkdir(parents=True, exist_ok=True)
        with (directory / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            owners = load_owners(receipt)
            before = inventory()
            verify_owners(owners, before)
            if args.command == "udid":
                if args.name not in owners:
                    return 1
                print(owners[args.name][0])
                return 0
            if args.command == "list":
                for udid, name, _, _ in owners.values():
                    print(f"{name} ({udid})")
                return 0
            owned_before = list(owners.values())
            if args.command == "create":
                create(receipt, owners, before)
            else:
                delete(receipt, owners)
            allowed = list(owners.values()) if args.command == "create" else owned_before
            after = inventory()
            verify_owners(owners, after)
            lines, problems = compare(args.command, before, after, allowed)
            lines = [f"watch-sim.sh {args.command}: simctl list before/after", *lines,
                     *(f"FAIL {problem}" for problem in problems),
                     f"result: {'FAIL' if problems else 'PASS'} ({len(problems)} problem(s))"]
            report = "\n".join(lines) + "\n"
            print(report, end="")
            if report_path:
                write_report(report_path, report)
            return int(bool(problems))
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"watch-sim: {detail}", file=sys.stderr)
        if report_path:
            try:
                write_report(report_path, f"watch-sim.sh {args.command}\nFAIL {detail}\nresult: FAIL\n")
            except OSError as report_error:
                print(f"watch-sim: cannot write evidence: {report_error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
