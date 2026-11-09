#!/usr/bin/env python3
"""Install the bundled Studio demo subset into the app's resources.

    python3 scripts/media/studio/install_demo.py            copy into ios/Jovra/Resources/StudioSampleMedia/
    python3 scripts/media/studio/install_demo.py DEST       copy into DEST (tests, other targets)

The subset is the list in spec/studio/fixtures/media/demo-subset.json (today: the six angle-labelled synthetic
renders of the match sample for ST27). Each file is taken from the render cache at the path its committed manifest
names, so the copy is the media that manifest describes. The installer fails, naming the command to run, when a file
is not rendered for the current generator source, and fails when the subset is over its budget (``budgetBytes``,
25 MB). It writes ``studio-sample-media.json`` beside the media (what each file is, all labelled Sample), then prints ``du -sk`` of the
folder.

The installer only ever deletes files it wrote itself. It refuses, touching nothing, a DEST whose folder name is not
``StudioSampleMedia``, a non-empty DEST with no readable ``studio-sample-media.json`` index, an index that names
anything but a plain ``*.mp4`` file name, and a DEST holding any file or folder that neither the previous index nor
this install names. A file the previous index lists and this subset no longer does is removed; nothing else is.

The folder is git-ignored: no media is ever committed (scripts/media/studio/check_added_binaries.py enforces it).
XcodeGen picks the files up as app resources the next time the project is generated (scripts/ios/generate.sh).
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SUBSET = ROOT / "spec" / "studio" / "fixtures" / "media" / "demo-subset.json"
INDEX_NAME = "studio-sample-media.json"
DEST_NAME = "StudioSampleMedia"


def previous_install(dest: Path) -> tuple[set[str], list[str]]:
    """The media file names a previous install wrote into ``dest`` (from its index), and the reasons ``dest`` is not
    safe to install into. A destination that is not provably ours is refused rather than cleaned."""
    if dest.name != DEST_NAME:
        return set(), [f"refusing {dest}: the destination folder must be named {DEST_NAME} "
                       f"(the installer replaces that folder's contents)"]
    if dest.exists() and not dest.is_dir():
        return set(), [f"refusing {dest}: it exists and is not a folder"]
    present = list(dest.iterdir()) if dest.exists() else []
    if not present:
        return set(), []
    links = [p.name for p in present if p.is_symlink()]
    if links:
        return set(), [f"refusing {dest}: it holds symbolic links {sorted(links)!r}; the installer writes only real files"]
    index_path = dest / INDEX_NAME
    try:
        listed = [f["fileName"] for f in json.loads(index_path.read_text(encoding="utf-8"))["files"]]
    except (OSError, ValueError, KeyError, TypeError) as error:
        return set(), [f"refusing {dest}: it is not empty and has no readable {INDEX_NAME} from a previous install "
                       f"({type(error).__name__}); empty it or choose another folder"]
    unsafe = [name for name in listed
              if not isinstance(name, str) or Path(name).name != name or not name.endswith(".mp4")]
    if unsafe:
        return set(), [f"refusing {dest}: its {INDEX_NAME} names {unsafe!r}, which are not plain *.mp4 file names"]
    return set(listed), []


def install(dest: Path) -> tuple[int, list[str]]:
    """Copy the subset into ``dest``. Returns (bytes installed, problems); nothing is touched when there are problems."""
    subset = json.loads(SUBSET.read_text(encoding="utf-8"))
    owned, problems = previous_install(dest)
    if problems:
        return 0, problems
    new_names = {entry["fileName"] for entry in subset["files"]}
    foreign = sorted(p.name for p in dest.iterdir() if p.name not in owned | new_names | {INDEX_NAME}) \
        if dest.exists() else []
    if foreign:
        return 0, [f"refusing {dest}: it holds {foreign!r}, which no Studio demo install wrote; move them out first"]
    files = []
    for entry in subset["files"]:
        manifest = json.loads((ROOT / "spec" / "studio" / "fixtures" / entry["manifest"]).read_text(encoding="utf-8"))
        source = ROOT / manifest["media"]["path"]
        if not source.is_file():
            problems.append(f"{entry['fileName']} is not rendered for this generator source "
                            f"(run: python3 scripts/media/studio/render_studio.py --set {manifest['set']})")
            continue
        files.append((source, entry, manifest))
    total = sum(source.stat().st_size for source, _, _ in files)
    if not problems and total > subset["budgetBytes"]:
        problems.append(f"the demo subset is {total:,} bytes, over its {subset['budgetBytes']:,}-byte budget")
    if problems:
        return total, problems
    dest.mkdir(parents=True, exist_ok=True)
    keep = {INDEX_NAME}
    index = {"schemaVersion": "jovra.studio-sample-media/1", "sample": True, "label": "Sample video (synthetic)",
             "files": []}
    for source, entry, manifest in files:
        target = dest / entry["fileName"]
        if not target.exists() or target.stat().st_size != source.stat().st_size \
                or target.read_bytes() != source.read_bytes():
            shutil.copyfile(source, target)
        keep.add(entry["fileName"])
        v = manifest["video"]
        index["files"].append({"fileName": entry["fileName"], "id": manifest["id"], "role": entry["role"],
                               "angle": entry.get("angle"), "frameRate": v["frameRate"], "frameCount": v["frameCount"],
                               "width": v["width"], "height": v["height"], "hasAudio": manifest["audio"] is not None,
                               "matchWindow": manifest.get("angle", {}).get("matchWindow")})
    (dest / INDEX_NAME).write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    for name in sorted(owned - keep):
        stale = dest / name
        if stale.is_file() and not stale.is_symlink():
            stale.unlink()
    return total, []


def main(argv: list[str]) -> int:
    dest = Path(argv[0]) if argv else ROOT / "ios" / "Jovra" / "Resources" / "StudioSampleMedia"
    subset = json.loads(SUBSET.read_text(encoding="utf-8"))
    total, problems = install(dest)
    for p in problems:
        print(f"error: {p}", file=sys.stderr)
    if problems:
        return 1
    du = subprocess.run(["du", "-sk", str(dest)], capture_output=True, text=True, check=True).stdout.strip()
    print(f"Installed {len(subset['files'])} Studio demo files into {dest}: {total:,} bytes "
          f"({total / 1_000_000:.2f} MB of the {subset['budgetBytes'] / 1_000_000:.0f} MB budget)")
    print(f"du -sk: {du}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
