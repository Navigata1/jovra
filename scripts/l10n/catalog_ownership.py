#!/usr/bin/env python3
"""String Catalog ownership check: a ticket's PR may edit only the tables of its own owned areas.

Usage:
  scripts/l10n/catalog_ownership.py --branch ticket/t23-framing-calibration --base origin/main
  scripts/l10n/catalog_ownership.py --branch <branch> FILE ...      (an explicit changed-file list)

Rules (docs/DEVELOPING.md, "Localization"):
  - String Catalogs live in ios/Jovra/Resources/Localization, one table per owned area, named after
    the area's folder with dots: Capture.Framing <-> ios/Jovra/Features/Capture/Framing,
    DesignSystem.Components <-> ios/Jovra/DesignSystem/Components, App <-> ios/Jovra/App.
  - A table belongs to the ticket whose owned area (docs/spec/tickets.json) is the most specific
    prefix of the table's folder. A ticket may add, edit or delete only its own tables.
  - The owner of ios/Jovra/Resources/Localization (the localization foundation, T06) may edit any table;
    tables with no owning area (InfoPlist, ...) are edited only by that owner.
  - The ticket comes from the branch name ticket/tNN-slug. Other branches own no table.
Exit status 1 when any changed catalog is not the ticket's.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

LOCALIZATION = "ios/Jovra/Resources/Localization"
BRANCH = re.compile(r"^ticket/t(?P<number>\d+)-")


def load_tickets(path: pathlib.Path) -> dict[str, list[str]]:
    """Ticket id -> owned area paths (parenthetical notes stripped)."""
    tickets = json.loads(path.read_text(encoding="utf-8"))["tickets"]
    return {
        ticket["id"]: [re.sub(r"\s*\(.*\)\s*$", "", area).rstrip("/") for area in ticket["owned_areas"]]
        for ticket in tickets
    }


def _is_within(path: str, area: str) -> bool:
    return path == area or path.startswith(area + "/")


def area_owner(path: str, tickets: dict[str, list[str]]) -> tuple[str, str] | None:
    """(ticket, area) whose owned area most specifically contains `path`."""
    best: tuple[str, str] | None = None
    for ticket, areas in tickets.items():
        for area in areas:
            if _is_within(path, area) and (best is None or len(area) > len(best[1])):
                best = (ticket, area)
    return best


def table_owner(table: str, tickets: dict[str, list[str]]) -> tuple[str, str] | None:
    folder = table.replace(".", "/")
    for candidate in (f"ios/Jovra/Features/{folder}", f"ios/Jovra/{folder}"):
        owner = area_owner(candidate, tickets)
        # Only an area at or below the app's top-level folders counts, never a blanket ios/... area.
        if owner and owner[1].count("/") >= 2:
            return owner
    return None


def owner_of(table: str, tickets: dict[str, list[str]]) -> str | None:
    owner = table_owner(table, tickets)
    return owner[0] if owner else None


def ticket_of(branch: str) -> str | None:
    match = BRANCH.match(branch)
    return f"T{int(match.group('number')):02d}" if match else None


def check(branch: str, changed: list[str], tickets: dict[str, list[str]]) -> list[str]:
    catalogs = [path for path in changed if path.endswith(".xcstrings")]
    if not catalogs:
        return []
    ticket = ticket_of(branch)
    problems = []
    for path in catalogs:
        if pathlib.PurePosixPath(path).parent.as_posix() != LOCALIZATION:
            problems.append(f"{path}: String Catalogs live in {LOCALIZATION}")
            continue
        if ticket is None or ticket not in tickets:
            problems.append(f"{path}: branch {branch} is not a ticket branch (ticket/tNN-slug), so it owns no table")
            continue
        if LOCALIZATION in tickets[ticket]:
            continue
        table = pathlib.PurePosixPath(path).name.removesuffix(".xcstrings")
        owner = table_owner(table, tickets)
        if owner is None:
            problems.append(f"{path}: table {table} has no owning area; only the localization owner edits it")
        elif owner[0] != ticket:
            problems.append(f"{path}: table {table} belongs to {owner[0]} ({owner[1]}), not {ticket}")
    return problems


def changed_files(base: str, cwd: str | None = None) -> list[str]:
    """Every path the branch touched since its merge base with `base`.

    --no-renames lists a rename as a deletion plus an addition, so renaming another ticket's table
    (deleting it) is checked like any other edit of that table.
    """
    output = subprocess.run(["git", "diff", "--name-only", "--no-renames", f"{base}...HEAD"],
                            check=True, capture_output=True, text=True, cwd=cwd).stdout
    return [line for line in output.splitlines() if line]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--base", help="git ref to diff against (merge base ... HEAD)")
    parser.add_argument("--tickets", default=str(pathlib.Path(__file__).resolve().parents[2] / "docs/spec/tickets.json"))
    parser.add_argument("files", nargs="*")
    args = parser.parse_args(argv)
    changed = args.files or (changed_files(args.base) if args.base else [])
    problems = check(args.branch, changed, load_tickets(pathlib.Path(args.tickets)))
    catalogs = [path for path in changed if path.endswith(".xcstrings")]
    for problem in problems:
        print(problem)
    print(f"catalog ownership: {len(catalogs)} changed catalog(s) on {args.branch} "
          f"(ticket {ticket_of(args.branch) or 'none'}), {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
