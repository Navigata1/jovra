#!/usr/bin/env bash
# Build the JOVRA Label app bundle and run its XCUITest (tools/label-tool/UITests) on this Mac.
#
# A Mac only runs UI tests when UI automation is allowed (hosted CI runners allow it). On a Mac where
# `automationmodetool` reports that Automation Mode needs authentication, Xcode asks for an administrator
# password; this script stops with exit 3 instead of leaving that dialog open, unless JOVRA_UI_TEST_PROMPT=1.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/tools/label-tool"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derivedData}"
SAMPLE="$ROOT/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["media"]["path"])' "$ROOT/spec/fixtures/media/sample/2026-09-09-match.truth.json")"
if [[ ! -f "$SAMPLE" ]]; then
  echo "label-tool-ui-test.sh: the synthetic sample video is not rendered. Run: python3 scripts/media/render.py --set sample" >&2
  exit 2
fi
if [[ "${JOVRA_UI_TEST_PROMPT:-0}" != "1" ]] && automationmodetool 2>&1 | grep -q "requires user authentication"; then
  echo "label-tool-ui-test.sh: this Mac asks for an administrator password before UI automation runs." >&2
  echo "Run it with JOVRA_UI_TEST_PROMPT=1 and approve the prompt, or rely on the hosted run (label-tool workflow)." >&2
  exit 3
fi
xcodegen generate --spec "$TOOL/project.yml" --project "$TOOL"
xcodebuild test -project "$TOOL/JovraLabel.xcodeproj" -scheme JovraLabel -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" -resultBundlePath "$DERIVED_DATA/label-tool-ui.xcresult"
