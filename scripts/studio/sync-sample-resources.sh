#!/usr/bin/env bash
# Refreshes the app's bundled copy of the Studio sample records (S13): every spec/studio/fixtures/records/*.json is
# copied byte for byte to ios/Jovra/Resources/StudioSample/, and files no longer in the fixtures are removed.
# StudioSampleContent installs the Studio sample from that bundled copy; the JovraStudioCore test
# `SampleContentResourcesTests` fails when the copy and the fixtures differ by a single byte.
#
#   scripts/studio/sync-sample-resources.sh           copy, then print one sha256 line per file
#   scripts/studio/sync-sample-resources.sh --check   change nothing; exit 1 and name each difference
#
# Run it after regenerating the Studio fixtures (python3 spec/reference/studio/generate_studio_fixtures.py).
set -euo pipefail

ROOT="${JOVRA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SRC="$ROOT/spec/studio/fixtures/records"
DEST="$ROOT/ios/Jovra/Resources/StudioSample"
MODE="${1:-sync}"
case "$MODE" in sync|--check) ;; *) echo "usage: $0 [--check]" >&2; exit 2 ;; esac

exec /usr/bin/env python3 - "$SRC" "$DEST" "$MODE" <<'PY'
import hashlib, shutil, sys
from pathlib import Path

src, dest, mode = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if not src.is_dir():
    sys.exit(f"error: {src} not found")
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
wanted = {p.name: p for p in sorted(src.glob("*.json"))}
present = {p.name: p for p in sorted(dest.glob("*.json"))} if dest.is_dir() else {}
missing = sorted(set(wanted) - set(present))
extra = sorted(set(present) - set(wanted))
changed = sorted(n for n in set(wanted) & set(present) if digest(wanted[n]) != digest(present[n]))

if mode == "--check":
    for name in missing: print(f"missing  {name}")
    for name in extra: print(f"extra    {name}")
    for name in changed: print(f"changed  {name}")
    if missing or extra or changed:
        print(f"FAIL: {dest.relative_to(src.parents[3])} differs from spec/studio/fixtures/records; "
              "run scripts/studio/sync-sample-resources.sh", file=sys.stderr)
        sys.exit(1)
    print(f"OK: {len(wanted)} bundled sample records are byte-identical to spec/studio/fixtures/records")
    sys.exit(0)

dest.mkdir(parents=True, exist_ok=True)
for name in extra:
    (dest / name).unlink()
for name, path in wanted.items():
    shutil.copyfile(path, dest / name)
for name in sorted(wanted):
    assert digest(wanted[name]) == digest(dest / name), name
    print(f"{digest(dest / name)}  {name}")
print(f"synced {len(wanted)} records ({len(missing)} added, {len(changed)} updated, {len(extra)} removed) "
      f"into {dest.relative_to(src.parents[3])}")
PY
