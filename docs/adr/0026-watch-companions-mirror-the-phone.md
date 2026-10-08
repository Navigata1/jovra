# Watch companions mirror their paired phone: native bridges, five surfaces, snapshots plus acknowledged commands

Status: accepted (2026-10-07); **amended 2026-10-07 (Amendment 1, below)**: the room contract now exists as
`spec/room` (`jovra.room.*/1`, validated by `scripts/spec/validate_room.py`), and points 2, 3.3, 6 and 8 were
reconciled with it and with `docs/spec/watch-v1-spec.md`. Nothing here is built or tested.
`design-reference/adaptive/brief/watch-snapshot.sample.json` is layout-only Sample data; its contract form is
`spec/room/fixtures/records/watch-bridge.sample.json`.

Jon approved native watch companions: SwiftUI on watchOS for Apple Watch and Compose for Wear OS for Galaxy Watch
(references 61–70, decisions addendum item 4, OBSERVED). A watch is a small, intermittently connected screen whose
background delivery is not guaranteed by either OS. The decision is what a watch is allowed to be: a mirror of what its
own phone knows, never a second room member, never a video client.

## Decision

**1. One bridge per ecosystem, through the paired phone.**

| | Apple Watch | Wear OS (Galaxy Watch) |
|---|---|---|
| App | watchOS SwiftUI app target in `ios/project.yml` (XcodeGen), companion to the iOS app | `:wear` Compose for Wear OS, same applicationId and signing key as `:app` (ADR-0024) |
| Bridge | WatchConnectivity (`WCSession`) to the paired iPhone | Wearable Data Layer to the paired Android phone |
| Latest state | `updateApplicationContext`: "replaces the previous dictionary", may be called when the counterpart is not reachable (OBSERVED) | `DataClient` data item at one fixed path, replaced on each update |
| Commands | `sendMessage` when reachable (delivered in order; from the iPhone it "does not wake up" the watch app, OBSERVED); otherwise `transferUserInfo`, queued and delivered in order, continuing while suspended (OBSERVED) | `MessageClient` to the phone node found by `CapabilityClient` |
| Glanceable | WidgetKit complications (ClockKit complications "are deprecated in watchOS 10 and later", OBSERVED) | Tiles and complication data sources |

The watch never joins the camera room, never hosts it, never talks to another camera and never receives video or
stills. Cross-ecosystem status works only through a phone: a Galaxy Watch sees an iPhone camera because its Android
phone is a room participant, and an Apple Watch sees an Android camera through its iPhone. The Data Layer itself "is
only available on Wear OS watches and paired Android devices" (OBSERVED), and WatchConnectivity is Apple-only, so
neither is ever the cross-platform transport (that is ADR-0027's room).

**2. The watch mirrors the phone's aggregate.** The phone bridge projects its room view (or, with no room, its own
session) into a small versioned **watch snapshot**: session ID, host epoch, snapshot sequence, event revision,
capabilities, per-camera rows (device ID, capture instance, segment, device sequence, capture state, `ageAtBridgeMs`,
last reported elapsed), the score derived from accepted point events, the latest capability-gated result if one exists,
and command receipts. It is a projection of the room envelope, not a new protocol. *Amended:* the contract is
`jovra.room.watch-bridge/1` in `spec/room` (with `jovra.room.command/1` and `jovra.room.receipt/1` for commands and
receipts); the names `jovra.watch-snapshot/1`, `jovra.watch-command/1` and `jovra.watch-receipt/1` are retired. Golden
vectors are run by `:room-protocol` and its Swift twin. No images, no media paths, no tokens, no player contact
details.

**3. Five surfaces, the same on both watches, laid out natively** (rectangular on watchOS, round-safe on Wear OS):

1. **Camera health**: per-camera acknowledged state, frozen last-reported elapsed time, last-heard age, storage,
   battery and thermal flags, and counts that state their basis (enrolled, fresh, fresh-and-recording).
2. **Score**: the authoritative point-derived score with its revision, server when known, point and undo buttons for a
   holder of the scorer grant, and visible Pending/offline state.
3. **Latest serve**: a source-linked, phone-produced result with units, provenance label, point and age, only when that
   capability is enabled. v1 has no live serve speed (capability `liveServeSpeed: false`). *Amended:* when the phone
   has produced a post-capture Serve speed estimate (`serveSpeed.manualAssisted`, registry status `estimated`) and the
   room capability `serveSpeedResults` is on, v1 shows that last result with its point, age and "Estimated" label
   (`latestServe` in the bridge payload), never as live and never relabelled as the current serve. Otherwise it shows
   the single string "Not measured live" with "Serve speed estimates are made on the phone after you mark contact and
   bounce." Wrist motion is never ball speed.
4. **Mark for review**: bookmarks a point, serve or uncertain bounce, with a receipt; review happens on the phone
   (ADR-0028). No In/Out decision appears on a watch.
5. **Connection alert**: which camera or the phone bridge is stale, when it was last heard, and that local recording
   may continue. Deduplicated with hysteresis, easy to acknowledge.

**4. Freshness is computed by the receiver, and arrival is not freshness.** The phone sends each camera's age as
it measured it on its own monotonic clock; the watch adds the time since it accepted the payload on **its** monotonic
clock, plus any known transit age. Cross-device wall clocks are informational only. Fresh, delayed and Unknown use
ADR-0027's thresholds. A queued delivery (`transferUserInfo`, a Data Layer sync after reconnect) has unbounded transit,
so its rows are Unknown until an interactive exchange bounds the delay. A watch process restart loses its monotonic
baseline, so cached rows become Unknown until renewed. Remote elapsed times stay frozen at their last reported value;
the watch never animates them forward. Always-on and ambient modes show a timestamped snapshot with no per-second
remote timers.

**5. Commands are requests until a receipt says otherwise.** A watch command (point, undo, mark, and later
capture-controller requests) carries `commandId`, the issuing participant, the role it claims, session ID, host
epoch, expiry, target and `baseEventRevision` where it applies. It is persisted on the watch before sending and shows
Pending until a receipt (Accepted, Rejected, Expired or Conflicted) arrives in a reply or in the snapshot's `receipts`.
A send that succeeds is not a receipt. The authoritative point-event log lives on the phone that owns the session
document (the room host in Build your match; otherwise the recording phone), never on the watch (ADR-0003). Duplicates
apply once; a stale base revision is a visible conflict; offline points stay pending drafts.

**6. Pairing a watch grants nothing.** A watch acts with at most the grants of its own phone's room participant.
Scorer, marker and capture-controller are explicit grants (ADR-0027). *Amended:* the watch's default is exactly its
member's grants (a viewer participant's watch is a viewer; a scorer's watch may mark); the watch abilities sheet on the
phone can only narrow them ("Score from watch" is off until the scorer turns it on). **A watch never issues a room
capture request, with or without the controller grant:** no start, no stop-one, no stop-all (`surfaceNotPermitted` in
the contract). Its only capture action is the wearer's own-phone stop, a confirmed request to its own paired phone that
never travels as a room command (watch spec WD11, stage A3c). No automatic stop of anything on disconnect.

**7. No fake workouts; health is a separate, optional feature.** JOVRA never starts an `HKWorkoutSession`, a Health
Services exercise or an ongoing activity to keep the watch app running or the radio awake. Optional training data
(heart rate, workout recording) is a later, separately consented feature, off by default, with its own privacy label
entry; it never gates any of the five surfaces.

**8. Haptics are sparse and deduplicated.** *Amended:* critical alerts, which vibrate at once, are only the wearer's
own phone failing to record (`ownRecordingFailed`) or running out of storage (`ownStorageCritical`, under 5 minutes
left). Another camera going Unknown is **not** critical: Unknown means "not heard", and the camera may still be
recording; its alert is deferred until the next accepted point event or 45 s, whichever comes first, and collapses with
other deferred alerts into one haptic. A command the wearer just issued gets its own one-tap Accepted or failure
pattern; that is feedback, not an alert. Repeated alerts for the same condition are suppressed until it clears
(watch spec "Haptics and alerts"; contract rule `alertSeverity`).

**9. Evidence levels.** Watch UI can be proven on simulators and emulators: the build Mac has the watchOS 26.5
runtime with Apple Watch Ultra 3 (49 mm) and SE 3 (40 mm) device types (OBSERVED), so both watchOS sizes are testable;
Wear OS needs gate G-WEARIMG first (no Wear image is installed, OBSERVED) and tests `wearos_xl_round` and
`wearos_small_round`. Bridge behaviour is separate: Apple says to "always test Watch Connectivity data transfers on
paired devices" and that the Simulator does not support `transferUserInfo` (OBSERVED); Wear emulator pairing needs
gate G-WEARPAIR, where Jon signs in himself. Without pairing, UI tests use a fake bridge and the result is labelled
"unverified on transport". Suspension, background delivery timing and haptics are physical-watch evidence.

## Amendment 1 (2026-10-07): one contract, decisions reconciled

A review on 2026-10-07 found this ADR, `docs/spec/watch-v1-spec.md` and `spec/room` using three names for one watch
contract and disagreeing on four decisions. Resolved as follows (the watch spec and `spec/room/README.md` carry the
detail):

| Topic | Was | Now |
|---|---|---|
| Contract names | `jovra.watch-snapshot/1`, `jovra.watch-command/1`, `jovra.watch-receipt/1` (this ADR and the watch spec) | `jovra.room.watch-bridge/1`, `jovra.room.command/1`, `jovra.room.receipt/1` (`spec/room`, fixtures and reference) |
| Command types | `scorePoint`, `undoLast`, `markForReview`, `ackAlert`, `requestRefresh`, `stopOwnPhone`, `requestStill` | Room commands `PointWon`, `Undo`, `MarkForReview`. `ackAlert`, the echo (`requestRefresh`) and `stopOwnPhone` are bridge-local messages between a phone and its own watch, never room commands. `requestStill` is out of v1 (stills are not in Room contract v1) |
| Reason codes | `idReuse`, `roleDenied` | `commandIdReuse`, `roleNotGranted`, `roleNotPermitted`, `surfaceNotPermitted` |
| Bridge fields the watch needs | — | `bridgeInstanceId`, `participant` (member, roles, watch abilities), `roster`, `alerts[]`, `latestServe` added to the bridge schema; the watch-side acceptance rules are `spec/room/reference/jovra_room/bridge.py` |
| Default watch role (§6) | "viewer by default" here; "viewer + marker" in the watch spec | the member's grants, narrowed by the watch abilities sheet |
| Watch stop-all (§6) | possible with the controller grant here; forbidden in the watch spec | never; enforced by the contract |
| Critical haptics (§8) | a camera gone Unknown was critical here; not in the watch spec | own-phone recording failure and storage only |
| Latest serve in v1 (§3.3) | "Not available" | the last post-capture estimate when one exists, else "Not measured live" |

## Considered Options

- **A standalone watch app that joins the camera room over Wi-Fi.** Rejected: it duplicates trust, drains the battery,
  fails whenever the watch's radio sleeps and breaks the one-aggregate model.
- **Direct watch-to-phone pairing across ecosystems.** Not available: the Data Layer is Android-only and
  WatchConnectivity is Apple-only (OBSERVED). The mixed room goes through phones.
- **A fake workout session for background runtime.** Rejected: misuses the user's health data permissions, and the
  brief forbids it.
- **Streaming stills or video to the watch.** Rejected: no task on the five surfaces needs a picture.
- **Treating a delivered snapshot as current.** Rejected: queued delivery can be minutes late; arrival time cannot
  establish freshness.

## Consequences

The watch is useful only while its phone is in the session, which is the honest limit. Every watch screen has
first-class Pending, Unknown, Not available and offline states. One snapshot contract and one command contract serve
both watches, with transport code written per OS.

Sources: https://developer.apple.com/documentation/watchconnectivity/wcsession and its `updateApplicationContext(_:)`,
`sendMessage(_:replyHandler:errorHandler:)`, `transferUserInfo(_:)` and `transferCurrentComplicationUserInfo(_:)` pages
(Apple documentation JSON, accessed 2026-10-07); https://developer.apple.com/documentation/clockkit (deprecation note,
accessed 2026-10-07); https://developer.apple.com/documentation/healthkit/hkworkoutsession ;
https://developer.android.com/training/wearables/data/overview (accessed 2026-10-07); local `xcrun simctl list runtimes`
and `devicetypes` (OBSERVED 2026-10-07); `docs/research/android/toolchain-and-devices.md` §§4.4, 7.3;
`design-reference/adaptive/brief/session-connectivity.md`, `acceptance-matrix.md`, `watch-snapshot.sample.json`,
`visual-review.md`; `.claude/skills/jovra-watch-companion/SKILL.md`; `docs/adr/0003`, `0004`, `0024`, `0027`, `0028`;
`spec/room/README.md` and `spec/contracts/capability-registry.v1.json` (`serveSpeed.manualAssisted` status
`estimated`, OBSERVED 2026-10-07).
