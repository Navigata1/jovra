#!/usr/bin/env bash
# Renders ios/Jovra/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png from the brand vector.
# Usage: scripts/ios/render-app-icon.sh [proof.png]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -O \
  -o "$WORK/render-app-icon" \
  "$ROOT/scripts/ios/app-icon/main.swift" \
  "$ROOT/ios/Jovra/DesignSystem/Brand/BrandGeometry.swift"
"$WORK/render-app-icon" "$ROOT/ios/Jovra/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" ${1:+"$1"}
