# Shared settings for scripts/ios/*.sh. Source, do not execute.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT/ios"
# Keep derived data inside the checkout (disk on the build Mac is tight); delete it when done.
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derivedData}"
# iPhone 17 Pro, iOS 26.5 on the build Mac. Override with SIMULATOR_ID=<udid>.
SIMULATOR_ID="${SIMULATOR_ID:-83223876-0F7B-4B30-A051-AD9F08BD3C5E}"
DESTINATION="id=$SIMULATOR_ID"

boot_simulator() {
  xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
  xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null
}
