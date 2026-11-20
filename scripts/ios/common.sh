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
  stop_leftover_test_daemon
}

# After an accessibility audit times out (XCTest error -56, "Audit failed to complete in time"), the
# testmanagerd inside the simulator keeps computing: seen at 3 to 11 cores for hours after the run ended,
# which slows every other simulator on the Mac until their audits time out too. This stops this
# simulator's daemon; the simulator starts a fresh one for the next run. It does nothing while another
# xcodebuild is using the simulator. Called before a run (boot_simulator) and after it.
stop_leftover_test_daemon() {
  if pgrep -f "xcodebuild .*$SIMULATOR_ID" >/dev/null 2>&1; then return 0; fi
  local pids
  pids="$(ps -AEo pid=,command= | awk -v id="SIMULATOR_UDID=$SIMULATOR_ID" \
    'index($0, "/usr/libexec/testmanagerd") && index($0, id) && !index($0, "awk") { print $1 }')"
  if [ -n "$pids" ]; then
    echo "==> stopping leftover testmanagerd in $SIMULATOR_ID (pid $(echo $pids | tr '\n' ' '))"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
  fi
}
