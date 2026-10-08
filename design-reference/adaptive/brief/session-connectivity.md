# Session room and watch bridge: proposed contract

Design proposal, 2026-10-07. No transport was implemented or exercised by this design handoff. A future ADR must select and verify the transport against native lifecycle constraints.

## One room, independent recordings

One elected phone hosts the session metadata room. One to six consenting camera phones record original media independently, using capture-instance IDs and segment IDs. The primary camera is the baseline analysis source. Extra cameras increase available evidence; they do not guarantee precise clocks, calibration, coverage or live analysis. A host loss leaves participant recordings intact and makes room status Unknown until reconnection. Recover a room with a new host epoch; never accept a previous epoch as fresh authority.

QR invites are session joins, not Bluetooth pairing, video-publication permission or frame sync. Proposed invitations have a cryptographically random 128-bit secret, 10-minute expiry, a single-use join token and an explicit role. A six-character human code such as JVR-482 is display/lookup data, not an authentication secret. Verify host identity, user consent and permitted network scope before exchanging capture metadata. Bind tokens to the selected host/session; rotate/revoke them on host transfer. Protect code lookup against guessing and never log token/QR secrets. Rendered QR patterns in these references are illustrative and must not be scanned as credentials.

Select an authenticated, encrypted cross-platform LAN transport with discovery separate from trust. Bonjour/mDNS can advertise a room but cannot authenticate a participant. A QR must not make the client fetch an arbitrary URL, trust arbitrary certificates or contact unrelated services. Explicitly validate any allowed endpoint and host fingerprint. Native local-network discovery, camera, microphone and notification permissions remain separate. A relay, account-backed discovery or Internet room is a later backend scope with its own authorization and retention model.

Each camera publishes actual state: Ready / Starting / Recording / Paused / Finalizing / Saved / Failed, with captureInstanceId, segmentId, sequence, acknowledged elapsed duration and storage/battery/thermal observations where available. Unknown is a receiver-derived freshness state, never a sender's assertion that its connection is healthy. Local capture may continue in every room-disconnected state. Device clock/recording durations can differ and are not media alignment evidence.

## Watch path

Apple Watch uses its paired iPhone bridge via WatchConnectivity. Wear OS uses its paired Android bridge via Wearable Data Layer. The phone bridge obtains room snapshots, then forwards only small status/result metadata to its paired watch. A watch does not open six video streams or become the room host. A Galaxy Watch can see an iPhone camera indirectly through its Android room participant, and an Apple Watch can see an Android camera indirectly through its iPhone participant. This mixed-room behaviour still requires a working, authorized phone-to-phone transport.

Use latest-state replacement for snapshots and reliable acknowledged messages for actions, respecting each OS's background rules. A reachable interactive channel can be used for a quick request; queued delivery remains Pending until an actual receipt. Cached native watch snapshots can survive offline periods but cannot be described as real-time. Never enable a fake workout to keep communications alive. Do not schedule a constant stream of haptics or animations in always-on mode.

## Freshness and replay protection

The room envelope includes schemaVersion, sessionId, hostEpoch, snapshotSeq, eventRevision, capabilities, devices and receipts. Each device entry includes deviceId, captureInstanceId, segmentId, deviceSeq and lastReportedElapsedMs. Bind received identities to authenticated membership, not a caller-supplied device name. Reject snapshots from the wrong session, old host epoch or non-increasing sequence. On epoch change require reconciliation, rather than silently overriding pending commands or accepting a claimed host.

Freshness uses receiver-owned monotonic clocks within a process. Never subtract wall clocks from different devices. The paired phone forwards its conservatively calculated per-camera ageAtBridgeMs and snapshot age. The watch adds time since the bridge payload was accepted on its own monotonic clock. Include known delivery transit age when transport provides it. If delay cannot be bounded, freshness is Unknown until a foreground reachability/acknowledgement exchange establishes it. A delayed queued context is not fresh merely because it arrived just now. Process restart invalidates a previous monotonic baseline and marks cached status Unknown until renewed; wall-clock text remains only informational.

Proposed foreground policy: report approximately every 2 seconds when supported; fresh at 0–5 seconds, delayed above 5–15 seconds, Unknown above 15 seconds. These are product defaults to benchmark, not OS scheduling guarantees. A bridge outage can make every camera Unknown even if the room host heard them recently. Count only freshly acknowledged Recording devices in the fresh-recording numerator. Distinguish enrolled count, fresh count and recording count in the data model. Freeze last-reported remote elapsed duration when no update is confirmed; do not extend it using the watch clock. Local on-device elapsed time can use the local capture timer. Show last-heard age and “May still be recording” on stale rows.

## Actions and receipts

Roles are viewer, marker, scorer and capture-controller; a viewer watch gains no write privilege simply by pairing. Each command carries commandId, issuer identity, authorized role, sessionId, hostEpoch, issued freshness context, expiry, target scope and baseEventRevision where applicable. Authenticate and authorize it at the host/device. Persist command IDs and final results over retries/restarts. The same command ID with different contents is rejected; identical retry returns the original receipt. Do not infer success from a successful send call.

Receipts: Pending → Accepted / Rejected / Expired / Conflicted, with target device results and canonical event revision where relevant. A room-wide stop is a request fan-out: retain individual accepted, denied, timed-out and Unknown states. Starting recording may need the foreground phone, unlocked interaction and camera permissions. Do not imply remotely forcing camera capture in the background. A local user's explicit stop always remains available. Disconnect never automatically stops all cameras.

Point/undo commands enter the authoritative event log exactly once after authorization and revision checks. Two scorers writing against the same revision produce a visible conflict and reconciliation, not two unnoticed points. An offline point is a pending draft. Undo/correction records the affected event and recomputes later scores/statistics; it does not mutate cached totals alone. Mark-for-review is a source-linked note with receipt and point/time/angle references. “Stop recording” in a phone mockup requires a concrete target label and confirmation for any all-device operation in implementation.

## Analysis result envelope

Optional metrics carry resultId, sessionId, source device/segment/frame ranges, pointEventId, producedAt, label (Manual / Estimated / Reviewed / Validated), model/calibration version, units, uncertainty or unavailable reason, and review state. Deliver only when the active capability exists. Current capture v1 has no live serve speed. The sample 74 mph is a layout illustration for a later capability. Retain old-result timestamps; never silently relabel a past serve as current. Wrist movement is not ball speed. Multi-view calibration and time synchronization must be measured before using derived speed or bounce hints.

Automatic In/Out classification is outside the initial slice. Mark uncertain bounces for phone review. More cameras alone cannot establish officiating accuracy, and any later hint must support abstention and leave score changes explicit.

## Sources

- [Apple WatchConnectivity WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Wear OS Data Layer overview](https://developer.android.com/training/wearables/data/overview)
- [Wear OS data items](https://developer.android.com/training/wearables/data/data-items)

The room envelope, invite policy, freshness thresholds and command rules above are JOVRA proposals. The sources describe native companion mechanisms, not a completed JOVRA session service.
