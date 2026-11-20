#!/usr/bin/env bash
# Refreshes the app's bundled copy of the demo library (T18, "Explore a demo"): spec/fixtures/sample/library
# (sessions, equipment, practice plan), spec/fixtures/sample/analysis (the analysis overlays) and
# spec/fixtures/sample/media-manifest.json are copied byte for byte into ios/Jovra/Resources/SampleLibrary.bundle,
# keeping their folders, and files no longer in the fixtures are removed. A `.bundle` folder is copied into the app as
# one resource, so the layout SampleLibrary.load(from:) reads survives. The hosted test SampleLibraryBundleTests fails
# when the copy and the fixtures differ by one byte.
#
#   scripts/ios/sync-sample-library.sh           copy, then print one sha256 line per file
#   scripts/ios/sync-sample-library.sh --check   change nothing; exit 1 and name each difference
set -euo pipefail

ROOT="${JOVRA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MODE="${1:-sync}"
case "$MODE" in sync|--check) ;; *) echo "usage: $0 [--check]" >&2; exit 2 ;; esac

exec /usr/bin/env python3 - "$ROOT" "$MODE" <<'PY'
import hashlib, shutil, sys
from pathlib import Path

root, mode = Path(sys.argv[1]), sys.argv[2]
sample = root / "spec/fixtures/sample"
dest = root / "ios/Jovra/Resources/SampleLibrary.bundle"
# Bundled path -> fixture path. Only what SampleLibrary.load reads; the oracles (*.expected.json) stay in spec/.
wanted = {}
for path in sorted((sample / "library").rglob("*.json")):
    if not path.name.endswith(".expected.json"):
        wanted[Path("library") / path.relative_to(sample / "library")] = path
for path in sorted((sample / "analysis/sessions").glob("*.analysis.json")):
    wanted[Path("analysis/sessions") / path.name] = path
wanted[Path("media-manifest.json")] = sample / "media-manifest.json"

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

present = {p.relative_to(dest): p for p in dest.rglob("*") if p.is_file()} if dest.is_dir() else {}
problems = [f"{rel}: missing from the bundled copy" for rel in sorted(set(wanted) - set(present))]
problems += [f"{rel}: not in spec/fixtures/sample" for rel in sorted(set(present) - set(wanted))]
problems += [f"{rel}: differs from {wanted[rel].relative_to(root)}" for rel in sorted(set(wanted) & set(present))
             if digest(wanted[rel]) != digest(present[rel])]
if mode == "--check":
    for line in problems:
        print(f"error: {line}", file=sys.stderr)
    sys.exit(1 if problems else 0)
if dest.exists():
    shutil.rmtree(dest)
for rel, source in wanted.items():
    (dest / rel).parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest / rel)
for rel in sorted(wanted):
    print(f"{digest(dest / rel)}  {rel}")
PY
