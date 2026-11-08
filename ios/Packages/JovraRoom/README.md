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

Clocks: ages are measured on `ContinuousClock`, which keeps counting while the device sleeps. Never use
`mach_absolute_time` or `SuspendingClock`, and never subtract two devices' wall clocks.

Copy: the package returns numbers and states (`elapsedText` "12:26", `lastHeardSeconds`, `mayStillBeRecording`).
Sentences such as "May still be recording" belong to the app's String Catalogs.

## Tests

```sh
swift test --package-path ios/Packages/JovraRoom     # every spec/room fixture, read in place
scripts/ios/room-mutations.sh                        # source mutations that must turn the suite red
```

`Tests/Part1` (W01, #267) runs the records, invalid cases and the freshness, snapshot, phone-status, display,
disconnect and analysis vectors. The bridge, watch-sample, alerts, invitation, ledger and outbox kinds belong to W02
(#271); `FixtureManifestTests` fails on any unknown kind or unconsumed fixture file. CI: `.github/workflows/room.yml`.
