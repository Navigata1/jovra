#!/usr/bin/env bash
# Source-level mutation check for ios/Packages/JovraRoom (tickets W01 #267 and W02 #271): each mutation reverts one rule in the
# package sources, runs `swift test`, and must turn the suite red. Sources are restored after every mutation (and on
# exit). Prints a transcript; exits 1 if any mutation survives.
# Usage: scripts/ios/room-mutations.sh [--scratch-path DIR]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="$ROOT/ios/Packages/JovraRoom"
SRC="$PKG/Sources/JovraRoom"
SCRATCH=()
[ "${1:-}" = "--scratch-path" ] && SCRATCH=(--scratch-path "$2")
BACKUP="$(mktemp -d)"
cp -R "$SRC" "$BACKUP/src"
restore() { rm -rf "$SRC" && cp -R "$BACKUP/src" "$SRC"; }
trap 'restore; rm -rf "$BACKUP"' EXIT

# name | file (under Sources/JovraRoom) | literal text to find (every occurrence is replaced) | replacement
MUTATIONS=(
  "fresh threshold 6 s|Freshness/FreshnessRule.swift|public static let proposal = FreshnessPolicy(freshMaxMs: 5000|public static let proposal = FreshnessPolicy(freshMaxMs: 6000"
  "unbounded transit treated as bounded|Freshness/FreshnessRule.swift|guard transitBounded, baselineValid else { return nil }|guard baselineValid else { return nil }"
  "clock that stops during sleep|Freshness/MonotonicClock.swift|ContinuousClock.now|SuspendingClock.now"
  "snapshot replay accepted|Snapshot/SnapshotReceiver.swift|env.snapshotSeq <= lastSeq|env.snapshotSeq < lastSeq"
  "results always current|Analysis/ServeResultGate.swift|isCurrent ? .current : .previous|.current"
  "Local not counted as fresh|Status/StatusRow.swift|self == .fresh \|\| self == .local|self == .fresh"
  "remote elapsed extrapolated by age|Status/StatusRow.swift|elapsedMs: report.lastReportedElapsedMs, elapsedSource: .lastReported|elapsedMs: report.lastReportedElapsedMs + (ageMs ?? 0), elapsedSource: .lastReported"
  "unknown properties accepted|Records/RoomDecoding.swift|if let extra = all.allKeys|if false, let extra = all.allKeys"
  "command shape not checked|Records/RoomCommand.swift|try Self.checkShape(payload.type, target, baseEventRevision, c)|_ = c"
  # W02 (#271): invitations, ledger, outbox, bridge, health and alerts.
  "forged issuer: member not bound to the peer|Ledger/CommandLedger.swift|guard issuer.memberId == memberId else { return .failure(.issuerNotAuthenticated) }|_ = issuer.memberId"
  "unregistered watch accepted|Ledger/CommandLedger.swift|issuer.bridgeDeviceId == peer.deviceId && member.watchDeviceIds.contains(issuer.deviceId)|issuer.bridgeDeviceId == peer.deviceId"
  "watch may control capture|Ledger/CommandLedger.swift|if c.issuer.surface == .watch && type.isCaptureRequest|if c.issuer.surface == .phone && false"
  "send age in the fingerprint|Ledger/LedgerTypes.swift|expiry.removeValue(forKey: \"ageAtSendMs\") != nil|expiry[\"ageAtSendMs\"] != nil"
  "delivery fails open|Ledger/LedgerTypes.swift|guard transitBounded == true,|guard transitBounded != false,"
  "frozen send age|Outbox/Outbox.swift|command.expiry.ageAtSendMs = age|_ = age"
  "draft chain not held|Outbox/Outbox.swift|if chainBroken && type.isScoreCommand {|if false && type.isScoreCommand {"
  "replayed bridge payload accepted|Bridge/BridgeReceiver.swift|b.bridgeSeq <= bridgeSeq|b.bridgeSeq < bridgeSeq"
  "bridge marks lost on restart|Bridge/BridgeReceiver.swift|instance = state.instance|instance = nil"
  "enrolled counted from rows|Health/HealthSummary.swift|enrolled: bridge.roster.cameraDeviceIds|enrolled: bridge.devices.map(\\.deviceId)"
  "commitment not checked|Invitation/HostInvitations.swift|if !roomConstantTimeEquals(commitment, p.request.guestCommitment) {|if false {"
  "no attempt limit|Invitation/HostInvitations.swift|public static let maxJoinAttempts = 3|public static let maxJoinAttempts = 99"
  "non-canonical QR accepted|Invitation/InvitationQR.swift|guard canonical == Data(raw) else { throw .nonCanonicalPayload }|_ = raw"
  "alert raised after 2 s|Alerts/AlertPolicy.swift|public static let raiseAfterMs = 3000|public static let raiseAfterMs = 2000"
  "alert deferral 60 s|Alerts/AlertPolicy.swift|public static let deferMaxMs = 45_000|public static let deferMaxMs = 60_000"
)

survived=0
echo "JovraRoom mutation run, $(date -u +%Y-%m-%dT%H:%M:%SZ), $(swift --version 2>&1 | head -1)"
for entry in "${MUTATIONS[@]}"; do
  IFS='|' read -r name file find replace <<<"$(printf '%s' "$entry" | sed 's/\\|/\x01/g')"
  find="${find//$'\x01'/|}"; replace="${replace//$'\x01'/|}"
  target="$SRC/$file"
  if ! grep -qF -- "$find" "$target"; then
    echo "== $name: MUTATION NOT APPLIED (text not found in $file)"; survived=$((survived + 1)); continue
  fi
  FIND="$find" REPLACE="$replace" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(text.replace(os.environ["FIND"], os.environ["REPLACE"]))
PY
  out="$(cd "$PKG" && swift test ${SCRATCH[@]+"${SCRATCH[@]}"} 2>&1)"; status=$?
  echo "== $name ($file)"
  echo "   - $find"
  echo "   + $replace"
  if [ $status -eq 0 ]; then
    echo "   SURVIVED: swift test passed"; survived=$((survived + 1))
  elif ! printf '%s\n' "$out" | grep -qE "Executed [0-9]+ tests, with [1-9][0-9]* failures?"; then
    # A mutation only counts as killed by a failing test, never by a build break or a crashed runner.
    printf '%s\n' "$out" | grep -E "error:" | head -3 | sed 's/^/   /'
    echo "   NOT KILLED BY A TEST (swift test exit $status without test failures)"; survived=$((survived + 1))
  else
    printf '%s\n' "$out" | grep -E "error: -\[|error: .*XCTAssert|Executed [0-9]+ tests" | sed 's#^.*/Tests/#   Tests/#' | sort -u | head -8
    echo "   KILLED (swift test exit $status)"
  fi
  restore
done
echo "survivors: $survived of ${#MUTATIONS[@]}"
[ $survived -eq 0 ]
