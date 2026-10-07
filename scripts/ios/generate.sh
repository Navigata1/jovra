#!/usr/bin/env bash
# Generates ios/Jovra.xcodeproj from ios/project.yml (the project file is never committed).
set -euo pipefail
source "$(dirname "$0")/common.sh"
command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
xcodegen generate --spec "$IOS_DIR/project.yml" --project "$IOS_DIR"
