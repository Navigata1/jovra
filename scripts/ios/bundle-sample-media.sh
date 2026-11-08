#!/usr/bin/env bash
# The app's sample-media bundling step (T11): copies the rendered synthetic sample media into the app bundle
# as SampleMedia/<fileName> with the sample media manifest beside it. Run by the Jovra target's build phase;
# runnable by hand as `scripts/ios/bundle-sample-media.sh <destination folder>`.
#
# It fails, naming the files and the command to run, when the sample media is not rendered for the current
# renderer version, and when the files add up to more than the 60 MB budget. Debug builds that do not need
# the demo video may set JOVRA_SKIP_SAMPLE_MEDIA=YES (a warning, and SampleMedia/bundle-status.json says
# "skipped"); Release builds never skip.
set -euo pipefail

ROOT="${JOVRA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
if [[ $# -ge 1 ]]; then
  DEST="$1"
else
  DEST="${TARGET_BUILD_DIR:?run from Xcode or pass a destination}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/SampleMedia"
fi
SKIP="NO"
if [[ "${JOVRA_SKIP_SAMPLE_MEDIA:-NO}" == "YES" ]]; then
  if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
    echo "error: JOVRA_SKIP_SAMPLE_MEDIA is not allowed in Release builds: the demo needs its sample video." >&2
    exit 1
  fi
  SKIP="YES"
fi

exec /usr/bin/env python3 - "$ROOT" "$DEST" "$SKIP" <<'PY'
import json, shutil, sys
from pathlib import Path

root, dest, skip = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] == "YES"
BUDGET = 60_000_000
manifest_path = root / "spec/fixtures/sample/media-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
truths = {}
for path in sorted((root / "spec/fixtures/media/sample").glob("*.truth.json")):
    doc = json.loads(path.read_text(encoding="utf-8"))
    truths[doc["sampleMedia"]["mediaId"]] = doc
dest.mkdir(parents=True, exist_ok=True)
# The build phase may write only the files its output list declares (user script sandboxing).
declared = [line.rsplit("/", 1)[1] for line in (root / "scripts/ios/sample-media-outputs.xcfilelist").read_text().split()]
expected = [m["fileName"] for m in manifest["media"]] + ["media-manifest.json", "bundle-status.json"]
if declared != expected:
    print("error: scripts/ios/sample-media-outputs.xcfilelist does not list the sample media manifest's files "
          "(one line per fileName, then media-manifest.json and bundle-status.json); update it with the manifest.",
          file=sys.stderr)
    sys.exit(1)
if skip:
    print("warning: JOVRA_SKIP_SAMPLE_MEDIA=YES: the app is built without its sample video (the demo shows none).")
    (dest / "bundle-status.json").write_text(json.dumps({"status": "skipped"}) + "\n", encoding="utf-8")
    sys.exit(0)
missing, files = [], []
for entry in manifest["media"]:
    doc = truths.get(entry["mediaId"])
    source = root / doc["media"]["path"] if doc else None
    if source is None or not source.is_file() or source.name != entry["fileName"]:
        missing.append(entry["fileName"])
    else:
        files.append((source, entry["fileName"]))
if missing:
    print(f"error: Sample media is not rendered for this renderer version ({len(missing)} of {len(manifest['media'])} files "
          f"missing: {', '.join(missing[:3])}{' ...' if len(missing) > 3 else ''}). "
          "Run: python3 scripts/media/render.py --set sample   (about 5 minutes; needs ffmpeg)", file=sys.stderr)
    sys.exit(1)
total = sum(source.stat().st_size for source, _ in files)
if total > BUDGET:
    print(f"error: Sample media is {total / 1_000_000:.2f} MB, over its {BUDGET / 1_000_000:.0f} MB budget.", file=sys.stderr)
    sys.exit(1)
for source, name in files:
    target = dest / name
    if not target.exists() or target.stat().st_size != source.stat().st_size or target.stat().st_mtime < source.stat().st_mtime:
        shutil.copyfile(source, target)
shutil.copyfile(manifest_path, dest / "media-manifest.json")
keep = {name for _, name in files} | {"media-manifest.json", "bundle-status.json"}
for stale in dest.iterdir():
    if stale.name not in keep:
        try:
            stale.unlink()
        except PermissionError:
            print(f"warning: could not remove stale {stale.name} from the bundle (clean the build folder)")
(dest / "bundle-status.json").write_text(json.dumps({"status": "bundled", "files": len(files), "bytes": total}) + "\n",
                                         encoding="utf-8")
print(f"Bundled {len(files)} sample media files, {total / 1_000_000:.2f} MB of the {BUDGET / 1_000_000:.0f} MB budget")
PY
