#!/usr/bin/env python3
"""List every binary file a branch adds, and fail when one of them is media outside the bundled demo subset.

    python3 scripts/media/studio/check_added_binaries.py                  # against origin/main
    python3 scripts/media/studio/check_added_binaries.py --base <ref>     # e.g. the pull request's base commit

Studio media fixtures are generated at test time into the git-ignored cache; only manifests are committed (S08). The
one place media may live in the tree is the bundled demo subset folder, ios/Jovra/Resources/StudioSampleMedia/
(itself git-ignored and filled by scripts/media/studio/install_demo.py). This check reads ``git diff --numstat``
between the merge base and HEAD, prints every added binary path (git reports a binary as "-  -"), and treats a file
as media by its extension or by its leading bytes (an ISO-BMFF ``ftyp`` box, RIFF/WAVE, Matroska, Ogg, FLAC or ID3),
so a renamed .mp4 is still caught. Images (evidence screenshots) are listed but allowed.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ALLOWED_MEDIA_PREFIX = "ios/Jovra/Resources/StudioSampleMedia/"
MEDIA_EXTENSIONS = {".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi", ".mts", ".3gp", ".y4m", ".yuv", ".h264", ".hevc",
                    ".wav", ".aac", ".m4a", ".mp3", ".flac", ".caf", ".aif", ".aiff", ".ogg", ".opus"}


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout


def sniff(head: bytes) -> str | None:
    if len(head) >= 12 and head[4:8] == b"ftyp":
        return "ISO-BMFF (mp4/mov)"
    if head[:4] == b"RIFF" and head[8:12] in (b"WAVE", b"AVI "):
        return "RIFF " + head[8:12].decode().strip()
    if head[:4] == b"\x1aE\xdf\xa3":
        return "Matroska/WebM"
    if head[:4] in (b"OggS", b"fLaC") or head[:3] == b"ID3":
        return "audio"
    return None


def added_binaries(repo: Path, base: str) -> list[str]:
    merge_base = git(repo, "merge-base", base, "HEAD").strip()
    out = git(repo, "diff", "--numstat", "--diff-filter=A", "--no-renames", f"{merge_base}..HEAD")
    paths = []
    for line in out.splitlines():
        added, deleted, path = line.split("\t", 2)
        if added == "-" and deleted == "-":
            paths.append(path)
    return paths


def media_kind(repo: Path, path: str) -> str | None:
    suffix = Path(path).suffix.lower()
    if suffix in MEDIA_EXTENSIONS:
        return suffix
    full = repo / path
    if full.is_file():
        with full.open("rb") as f:
            return sniff(f.read(16))
    return None


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--repo", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    paths = added_binaries(args.repo, args.base)
    violations = []
    print(f"added binary files ({len(paths)}) relative to {args.base}:")
    for path in paths:
        kind = media_kind(args.repo, path)
        allowed = kind is None or path.startswith(ALLOWED_MEDIA_PREFIX)
        print(f"  {path}  [{kind or 'not media'}{'' if allowed else ', NOT ALLOWED'}]")
        if not allowed:
            violations.append(path)
    if violations:
        print(f"FAIL: {len(violations)} media file(s) added outside {ALLOWED_MEDIA_PREFIX}. Studio media is generated "
              "into .cache/media/studio by scripts/media/studio/render_studio.py; commit only its manifests.")
        return 1
    print("PASS: no media file added outside the bundled demo subset")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
