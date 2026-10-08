#!/usr/bin/env bash
# Builds the app for the simulator, unsigned (no development team), and checks what the build carries:
#   1. without ios/Config/Drive.xcconfig: an empty Drive client id and the inert placeholder redirect scheme;
#   2. with scripts/ios/fixtures/Drive.test.xcconfig in its place: the reversed client id is a URL scheme;
# and in both builds the Sign in with Apple and HealthKit entitlements and every v1 Info.plist key.
# Finally it installs and launches the default build on the simulator to show it runs unsigned.
# Refuses to run if a real ios/Config/Drive.xcconfig exists (it would be overwritten).
# Usage: SIMULATOR_ID=<udid> scripts/ios/check-build-config.sh
set -euo pipefail
source "$(dirname "$0")/common.sh"

DRIVE="$IOS_DIR/Config/Drive.xcconfig"
FIXTURE="$ROOT/scripts/ios/fixtures/Drive.test.xcconfig"
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Jovra.app"
EXPECTED_SCHEME="com.googleusercontent.apps.000000000000-jovratest"
PLACEHOLDER_SCHEME="com.islanddevcrew.jovra.drive-unconfigured"   # DriveClientConfiguration.unconfiguredScheme
[ -e "$DRIVE" ] && { echo "ios/Config/Drive.xcconfig exists; move it aside first" >&2; exit 2; }
trap 'rm -f "$DRIVE"' EXIT
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
pass() { echo "ok:   $*"; }

build() {
  echo "==> xcodebuild build ($1), DEVELOPMENT_TEAM empty"
  xcodebuild build \
    -project "$IOS_DIR/Jovra.xcodeproj" -scheme Jovra -configuration Debug \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED_DATA" -quiet
  echo "    team: '$(xcodebuild -project "$IOS_DIR/Jovra.xcodeproj" -target Jovra -showBuildSettings 2>/dev/null | awk -F' = ' '/ DEVELOPMENT_TEAM =/{print $2}')'"
}

plist() { plutil -extract "$1" raw -o - "$APP/Info.plist" 2>/dev/null || echo "<missing>"; }
schemes() { plutil -convert json -o - "$APP/Info.plist" | python3 -c 'import json,sys; print(" ".join(s for t in json.load(sys.stdin).get("CFBundleURLTypes",[]) for s in t.get("CFBundleURLSchemes",[])))'; }
# Every URL type registers exactly one scheme, and every scheme is valid (RFC 3986: ALPHA *(ALPHA / DIGIT
# / "+" / "-" / ".")); an empty scheme is invalid and App Store validation can reject it.
check_schemes_valid() {
  local report
  if report="$(plutil -convert json -o - "$APP/Info.plist" | python3 -c '
import json, re, sys
types = json.load(sys.stdin).get("CFBundleURLTypes", [])
bad = []
for t in types:
    name, schemes = t.get("CFBundleURLName"), t.get("CFBundleURLSchemes", [])
    if len(schemes) != 1:
        bad.append(f"{name}: {len(schemes)} schemes")
    bad += [f"{name}: invalid scheme {s!r}" for s in schemes if not re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]*", s)]
print("; ".join(bad) or f"{len(types)} URL type(s), all valid")
sys.exit(1 if bad else 0)
')"; then pass "URL schemes valid: $report"; else fail "URL schemes: $report"; fi
}

check_common() {
  local entitlements
  # Simulator builds carry their entitlements in the executable's __TEXT,__entitlements section (the
  # ad-hoc code signature itself has none), which is what the simulator grants at launch.
  entitlements="$(python3 - "$APP/Jovra" <<'PY'
import json, plistlib, re, subprocess, sys
binary = sys.argv[1]
load = subprocess.run(["xcrun", "otool", "-l", binary], capture_output=True, text=True, check=True).stdout
match = re.search(r"sectname __entitlements\s+segname __TEXT\s+addr \S+\s+size (0x[0-9a-f]+)\s+offset (\d+)", load)
if not match:
    print("{}")
    sys.exit()
size, offset = int(match.group(1), 16), int(match.group(2))
with open(binary, "rb") as handle:
    handle.seek(offset)
    print(json.dumps(plistlib.loads(handle.read(size)), sort_keys=True))
PY
)"
  echo "    entitlements (__TEXT,__entitlements): $entitlements"
  echo "    code signature: $(codesign -dv "$APP" 2>&1 | grep -E '^(Signature|TeamIdentifier)' | tr '\n' ' ')"
  python3 - "$entitlements" <<'PY' && pass "Sign in with Apple and HealthKit entitlements are in the unsigned simulator build" || fail "entitlements missing"
import json, sys
e = json.loads(sys.argv[1])
sys.exit(0 if e.get("com.apple.developer.applesignin") == ["Default"] and e.get("com.apple.developer.healthkit") is True else 1)
PY
  for key in NSCameraUsageDescription NSMicrophoneUsageDescription NSPhotoLibraryAddUsageDescription NSHealthUpdateUsageDescription; do
    [ -n "$(plist "$key" | grep -v '<missing>')" ] && pass "$key: $(plist "$key")" || fail "$key missing"
  done
  plutil -extract BGTaskSchedulerPermittedIdentifiers json -o - "$APP/Info.plist" | grep -q 'processing.overnight' && pass "BGTaskSchedulerPermittedIdentifiers: $(plutil -extract BGTaskSchedulerPermittedIdentifiers json -o - "$APP/Info.plist")" || fail "background task identifiers missing"
  plutil -extract UIBackgroundModes json -o - "$APP/Info.plist" | grep -q '"processing"' && pass "UIBackgroundModes: processing" || fail "processing background mode missing"
}

"$(dirname "$0")/generate.sh" >/dev/null
boot_simulator

build "no Drive.xcconfig"
check_common
[ "$(plist JovraDriveClientID)" = "" ] && pass "JovraDriveClientID is empty" || fail "JovraDriveClientID is '$(plist JovraDriveClientID)'"
[ "$(plist JovraDriveRedirectScheme)" = "$PLACEHOLDER_SCHEME" ] && pass "JovraDriveRedirectScheme is the inert placeholder" || fail "JovraDriveRedirectScheme is '$(plist JovraDriveRedirectScheme)'"
echo "    URL schemes: '$(schemes)'"
check_schemes_valid
schemes | grep -q googleusercontent && fail "a Google Drive URL scheme is registered without Drive.xcconfig" || pass "no Google Drive URL scheme registered"
schemes | tr ' ' '\n' | grep -qx "$PLACEHOLDER_SCHEME" && pass "the Drive URL type carries the placeholder scheme" || fail "the Drive URL type does not carry the placeholder scheme"
echo "==> install and launch the unsigned build on $SIMULATOR_ID"
xcrun simctl install "$SIMULATOR_ID" "$APP"
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.islanddevcrew.jovra && pass "launched on the simulator" || fail "did not launch"
sleep 3
pid="$(xcrun simctl spawn "$SIMULATOR_ID" launchctl list | awk '/UIKitApplication:com.islanddevcrew.jovra\[/{print $1}')"
[ -n "$pid" ] && [ "$pid" != "-" ] && pass "still running after 3 s (pid $pid)" || fail "not running after 3 s"
xcrun simctl terminate "$SIMULATOR_ID" com.islanddevcrew.jovra || true

cp "$FIXTURE" "$DRIVE"
build "with scripts/ios/fixtures/Drive.test.xcconfig as Drive.xcconfig"
check_common
echo "    URL schemes: '$(schemes)'"
check_schemes_valid
schemes | tr ' ' '\n' | grep -qx "$EXPECTED_SCHEME" && pass "reversed client id is a URL scheme" || fail "reversed client id is not a URL scheme"
[ "$(plist JovraDriveClientID)" = "000000000000-jovratest.apps.googleusercontent.com" ] && pass "JovraDriveClientID is the test client id" || fail "JovraDriveClientID is '$(plist JovraDriveClientID)'"

rm -f "$DRIVE"
echo "==> rebuild without Drive.xcconfig so later runs use the default chain"
build "no Drive.xcconfig"
[ "$(plist JovraDriveClientID)" = "" ] && pass "back to an empty client id" || fail "client id still set"

echo "==> $failures failure(s)"
[ "$failures" -eq 0 ]
