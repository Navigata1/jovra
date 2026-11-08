# JovraRoom

The Foundation-only Swift port of `spec/room` (JOVRA Room v1 and the watch bridge). It builds and tests on Linux and
depends on JovraCore only for the canonical JSON writer (ADR-0029). It has no transport, camera or watch API: it is
the rules the phone and watch apps call.

| Folder | What it holds | Reference |
|---|---|---|
| `Records/` | Strict decoders and canonical encoders for all twelve `jovra.room.*/1` records, `RoomRecord.decode`, and the record rules (`RoomRuleViolation` codes) | `records.py` |
| `Freshness/` | `FreshnessPolicy`, `FreshnessRule` (chained ages), `MonotonicClock` / `ContinuousMonotonicClock`, `ProcessBaseline`, `FreshnessClock` | `freshness.py` |
| `Snapshot/` | `SnapshotReceiver`: session, epoch, key, host, roster and per-device replay protection; `reconcile`; persisted `State` | `snapshot.py` |
| `Status/` | `StatusRow` (frozen remote elapsed, "may still be recording"), `RoomCounts`, `RoomStatusBoard` (phone path, room-link loss) | `freshness.py` |
| `Analysis/` | `ServeResultGate.present`: unavailable with a reason, review-needed, current or previous | `analysis.py` |
| `Bridge/` | `BridgeReceiver`: watch-side acceptance of bridge payloads, persisted replay marks | `bridge.py` |
| `Health/` | `HealthSummary`: the watch's roster counts and frozen rows | `freshness.py` |
| `Alerts/` | `AlertPolicy`: the phone's single source of watch alerts | `alerts.py` |
| `Ledger/` | `CommandLedger` (host), `AuthenticatedPeer`, `DeliveryObservation`, `CommandFingerprint`, `CaptureFanOutSummary` | `ledger.py` |
| `Outbox/` | `Outbox`: the issuer's offline drafts, send-age refresh, epoch guard and chains | `ledger.py` |
| `Invitation/` | `HostInvitations`, `InvitationJoiner`, `InvitationQR`, `InvitationCrypto`, `RoomSHA256` | `invitation.py` |

Clocks: ages are measured on `ContinuousClock`, which keeps counting while the device sleeps. Never use
`mach_absolute_time` or `SuspendingClock`, and never subtract two devices' wall clocks.

Copy: the package returns numbers and states (`elapsedText` "12:26", `lastHeardSeconds`, `mayStillBeRecording`).
Sentences such as "May still be recording" belong to the app's String Catalogs.

## Public API used by the watch app

Every type here is a value type with no I/O. The app owns persistence, the companion channel and the UI; it calls these
with what it received and stores what they return. All times are monotonic milliseconds from the device's own
`FreshnessClock`; no call takes a wall clock from another device.

### FreshnessClock (`Freshness/MonotonicClock.swift`)

```swift
let clock = FreshnessClock.live                     // ContinuousClock + this process's baseline id
let observation = clock.accept(transitMs: 40)       // stamp a payload as it arrives (nil = queued: unbounded)
let (freshness, ageMs) = try clock.read(senderAgeMs: device.ageAtBridgeMs, observation)
```

- `accept(transitMs:)` returns the `ReceiverObservation` to store with the payload: the transport-observed transit
  bound (`nil` for a queued `transferUserInfo`/application-context delivery), the process baseline and the accept time.
- `read(senderAgeMs:_:)` chains `senderAge + transit + time since accept` and classifies it with the policy: Fresh at
  5,000 ms or less, Delayed to 15,000 ms, Unknown above that, when transit was unbounded, after a process restart, or
  when the clock appears to run backwards. Throws `FreshnessInputError.negativeAge` / `.transitBoundMissing`.
- Tests inject a fake `MonotonicClock`; the production clock must keep counting during sleep.

### BridgeReceiver (`Bridge/BridgeReceiver.swift`)

```swift
var receiver = BridgeReceiver(restoring: savedState) // or BridgeReceiver(pairedPhoneId:) at pairing
switch receiver.accept(payload) {
case .accepted: save(receiver.state)                 // persist the replay marks on every accept
default: break                                       // a refusal changes nothing; drop the payload
}
```

- Accepts a `WatchBridgeSnapshot` only from the paired phone (`notPairedBridge`), never from a bridge instance the
  watch has left (`bridgeInstanceRetired`), with a strictly increasing `bridgeSeq` within the instance
  (`replayOrOutOfOrder`: a re-delivery is a replay, not a refresh), and within one session never an older epoch
  (`staleEpoch`) or, in one epoch, a lower `snapshotSeq`/`eventRevision`.
- `state` (`BridgeReceiver.State`, Codable) survives a watch restart. Freshness does not: restore the marks, but read
  cached rows as Unknown until a new payload is stamped by the new process.

### HealthSummary (`Health/HealthSummary.swift`)

```swift
let health = try HealthSummary.watch(payload, clock: .live)
health.freshRecording; health.enrolled               // the headline, e.g. "5/6"
health.canClaimAllRecording                          // true only when every enrolled camera is fresh and Recording
health.rows                                          // StatusRow: elapsedText "12:26", mayStillBeRecording, lastHeardSeconds
```

- `enrolled` is the roster's camera count, never the rows present; an enrolled camera with no row is Unknown.
- Rows show `lastReportedElapsedMs` exactly as last reported (floored), never advanced by the watch clock.
- `watch(_:nowMonoMs:currentBaselineId:)` is the same read at an explicit time (tests, previews). A payload without a
  `receiverObservation` reads as all Unknown.
- `init(rows:enrolled:)` builds a summary from rows the caller has already classified.

### Outbox (`Outbox/Outbox.swift`)

```swift
var outbox = Outbox(hostEpoch: 3, knownRevision: 42)       // or Outbox(restoring: savedState)
let pending = outbox.submitOffline(command, nowMonoMs: now) // Pending/offlineDraft: shown, never applied to the score
let receipts = try outbox.flush(to: &host, nowMonoMs: now, delivery: observed, peer: authenticatedPeer)
let outcome = outbox.reconcile(newEpoch: 4, hostReceipts: heldByNewHost)
```

- Every send recomputes `expiry.ageAtSendMs` from the issuer's monotonic clock (`Outbox.outgoing`), so queued time
  counts toward the TTL; a clock that runs backwards throws before anything is sent.
- `flush` sends nothing while the outbox's epoch differs from the host's; transient answers (channel, session, epoch)
  stay queued. Consecutive score drafts are a chain: after one is not Accepted the rest come back
  `Pending/requiresResubmit` and are not sent ("Score changed on the phone… Send Jon point again?").
- `reconcile` adopts receipts the new host holds, expires unknown capture requests (`hostEpochChanged`) and keeps the
  rest Pending for resubmission. `receipts` holds the latest receipt per commandId; persist `state`.
- `host` is any `RoomCommandHost`: the phone's `CommandLedger`, or the carrier adapter that relays to it.

### AlertPolicy (`Alerts/AlertPolicy.swift`)

```swift
var policy = AlertPolicy()
policy.status(at: now, deviceId: "c3", freshness: .unknown, captureState: .recording)
policy.tick(at: now); policy.pointAccepted(at: now)
try policy.own(at: now, kind: .ownRecordingFailed, deviceId: "c1")
policy.acknowledge(at: now, alertId: "alert-1")       // from the watch's ackAlert
policy.events                                        // raise / clear / ack / haptic, in order
policy.openAlerts                                    // what to forward in the bridge payload's alerts[]
```

- `cameraUnknown` only after a freshly Recording camera has been Unknown for 3 s; cleared after 4 s Fresh; one per
  camera per outage (an acknowledgement closes it for the outage); at most once per camera per 5 min. Never critical:
  its haptic waits for the next accepted point or 45 s, and pending alerts collapse into one haptic.
- `ownRecordingFailed` / `ownStorageCritical` are critical and vibrate at once; any other kind throws.
- `commandsIssued` is always empty: no alert stops or starts anything.

### ServeResultGate (`Analysis/ServeResultGate.swift`)

```swift
let shown = ServeResultGate.present(result, capabilities: payload.capabilities, registry: registry,
                                    currentPointEventId: currentPoint)
```

- Unavailable with a reason (`capabilityAbsent`, `capabilityUnsupported`, `calibrationMissing`, or the record's own),
  `reviewNeeded`, `current`, or `previous` (an earlier point keeps its own point and timestamp, never relabelled as
  current). `scoreEffect` is always `"none"`; the label (Estimated) always travels with the value.

## Host and joiner API (phone app)

- `CommandLedger.submit(_:delivery:peer:)`: the `peer` argument has no default. The carrier passes the
  `AuthenticatedPeer` bound to the TLS key for **every** frame, or `nil` if it could not authenticate one
  (`unauthenticatedChannel`). The ledger binds the issuer to that peer (D1); a watch is bound through its bridge phone
  and its member's registered watches, and never issues a capture request. Persist `state` across process death.
- `HostInvitations`: `validateJoin(_:now:)` (draws a CSPRNG host nonce), `reveal`, `approve`, `lookup`,
  `transferHost`. Tokens and nonces come from the host's secure store; `log` holds ids and codes only.
- `InvitationJoiner.verify(_:observedHostKey:)` and `checkResolvedEndpoint(address:port:)` run before the guest sends
  anything; `InvitationQR.decode` is strict (prefix, base64url alphabet, duplicate keys, canonical bytes) and then
  schema-checks the payload. `InvitationCrypto` builds the guest's commitment and proof and the six-digit code.
- `RoomSHA256` is a plain-Swift SHA-256/HMAC-SHA256 (no CryptoKit, so Linux builds), pinned by FIPS 180-4 and
  RFC 4231 known answers and, on Apple platforms, a CryptoKit cross-check.

Still out of scope here (cross-DAG finding 1): the Swift carrier that authenticates the peer on every frame (S69/S70).

## Tests

```sh
swift test --package-path ios/Packages/JovraRoom     # every spec/room fixture, read in place
scripts/ios/room-mutations.sh                        # source mutations that must turn the suite red
```

`Tests/Part1` (W01, #267) runs the records, invalid cases and the freshness, snapshot, phone-status, display,
disconnect and analysis vectors. `Tests/Part2` (W02, #271) runs the watch-sample, bridge, alerts, invitation, ledger
and outbox vectors, the room mutation set (forged issuer, replayed bridge payload, frozen send age) and the digest
known answers. `FixtureManifestTests` fails on any unknown kind, changed case count or unconsumed fixture file. CI:
`.github/workflows/room.yml` (Linux, `swift:6.1`).
