# JOVRA Room v1: authenticated encrypted LAN transport, discovery is not trust, epochs, receiver-owned freshness and receipts

Status: accepted (2026-10-07); **amended 2026-10-07 (Amendment 1, below)**: the contract now exists as `spec/room`
(14 schemas, fixtures and a Python reference, `scripts/spec/validate_room.py`), and points 3, 5, 6, 7 and the test list
follow it. Extends ADR-0017, which made the room coordination only (never synchronization) and
named its carriers; this ADR records the **trust and freshness model** the room and the watch bridges (ADR-0026) rely
on. It defines no second protocol: the message set stays `multicam-sync.md` §2.5 and spec SD10, carried as 4-byte
length-prefixed JSON over TLS/TCP. *Amended:* the records are `spec/room`'s `jovra.room.<record>/1` family, which
reconciles every multicam-sync message (`spec/room/README.md` §Reconciliation); "`jovra.room/1`" below means that
family. Nothing here is implemented or exercised; every timing number is a product default to benchmark.

Two research sources describe the room. `docs/research/studio/multicam-sync.md` §2 (carriers, QR payload, messages,
stills) and `design-reference/adaptive/brief/session-connectivity.md` (host epochs, freshness, roles, commands,
receipts). They differ in three places, reconciled here: approval is by a key-derived comparison code, not the
guest's device name (ADR-0017 and SD10 already say so; multicam-sync §2.4 predates it); the invite secret is at least 128 random bits (the
brief's floor; ports generate 32 bytes, and the contract accepts 128 to 256 bits); and the heartbeat's "stale after 3 missed beats" is expressed as the three
freshness bands below.

## Decision

**1. Transport: TLS 1.3 over TCP on the local network, both sides authenticated.** The host generates a key pair and
pins it to joiners through the QR (`hostKeySha256`, the TLS SPKI hash). Each guest generates a P-256 key in the Secure
Enclave or Android Keystore. A guest's `deviceId` in the room is bound to its key thumbprint at approval; every later
message is attributed by the authenticated channel, never by a name or ID inside the payload. Messages are JSON in
4-byte length-prefixed frames. Android implements this in `:room-transport` with platform APIs only (`NsdManager`,
`SSLSocket` with a pinned `X509TrustManager`, `LocalOnlyHotspot` for an Android-hosted court network); iOS with
Network.framework and Bonjour (ADR-0024; spec SD10).

**2. Discovery is not trust.** Bonjour/DNS-SD and NSD only produce a candidate endpoint. The advertised service
instance carries an opaque random room hint, never a player name, project title or device owner, because every phone
on the network can read it (INFERRED). A discovered endpoint is trusted only when it presents the key pinned by the QR,
or after the comparison step in point 3. A QR never makes the app fetch a URL, follow a redirect, accept an unpinned
certificate or contact an unrelated service: its payload is the custom scheme `jovra-room:1:<base64url(JSON)>`
handled only by the in-app scanner, and any endpoint in it must be a local address (private, link-local or the
resolved service) or it is refused. On Android the guest prefers the NSD system picker, which needs no local-network
permission; a raw IP from the QR is the fallback that does (OBSERVED rule for apps targeting SDK 37, so gate
G-TARGET37). iOS asks Local Network permission with `NSLocalNetworkUsageDescription` and declared `NSBonjourServices`.

**3. Invitations.** One QR per camera slot: single use, expires within 10 minutes, bound to the session, invitation,
slot, `hostEpoch` and the host key, carrying a random secret of at least 128 bits (ports generate 32 bytes) and a
nonce. *Amended:* the joiner proves the secret with an HMAC over
`sessionId|inviteId|nonce|guestKeySha256|guestCommitment` inside the pinned TLS channel (binding the guest key and its
commitment stops a captured proof being replayed by another device). Approval then requires the host to tap Approve
after **both phones show the same six-digit code**, derived by **commit-then-reveal**: the guest commits to
`H(guestKey, guestNonce)` in its join request, the host then sends a fresh random `hostNonce`, the guest reveals
`guestNonce`, and the code is `SHA-256(hostKey|guestKey|qrNonce|hostNonce|guestNonce)` mod 10⁶. A code derived only
from values in the QR and the guest's own key (this ADR's first wording, and ADR-0017's "derived from the guest key")
can be ground offline by anyone holding a forwarded QR: a verifier found a matching key in seconds (2026-10-07). Three
failed attempts by token holders revoke the invitation. The guest's device label is shown but is never the basis for
approval. A device that is already a member cannot join again under a second invitation. The display code (`JVR-482` style, `jovra.camera-invite/1`) is a lookup label, never a
secret, is rate-limited and never logged; neither is the QR secret. Revoking a slot closes the connection and voids
its invite. Host transfer voids every outstanding invite.
- **Typed-code fallback (refinement, INFERRED):** a guest that joins by typing a code has no pinned host key, so a
  comparison code derived only from the guest key would not detect a man in the middle. On that path the comparison
  code must be derived from the TLS channel binding (both keys, e.g. a TLS exporter value); otherwise the path is
  refused. Recommended to the contracts owner for `jovra.room/1`; a 6-digit code is never used as a TLS pre-shared key
  (offline brute force, multicam-sync §2.4).

**4. Host epochs.** `hostEpoch` is an integer that increases every time a room host starts, restarts or changes.
Every message carries `roomId`, `hostEpoch` and a per-sender `seq`. Receivers reject a wrong room, an older epoch and a
non-increasing `seq` for that sender. On a new epoch, guests re-authenticate (the same host phone presents its pinned
key; a different host phone needs new invitations and approvals in v1), and the host reconciles before acting: it
re-reads each participant's capture state and replays no pending command. A claimed host is never accepted because it
says so, and a previous epoch is never fresh authority.

**5. Freshness is owned by the receiver.** Each receiver measures age on its own monotonic clock
(`SystemClock.elapsedRealtimeNanos()` on Android; `mach_continuous_time` / `ContinuousClock` on Apple platforms.
*Amended:* not `mach_absolute_time`, which pauses while the device sleeps and would under-state age, so a stale row could
read Fresh); wall clocks from other devices are never
subtracted. Heartbeats every 2 s. Bands: **fresh** up to 5 s, **delayed** above 5 s up to 15 s, **Unknown** above 15 s,
or whenever transit cannot be bounded or the receiver's process restarted. Unknown is something a receiver concludes,
never a state a sender asserts. A silent camera keeps its last reported elapsed time frozen and is shown as "No contact
for 0:42 · may still be recording", never "Stopped". "Recording on n of m" counts only freshly acknowledged Recording
devices, and the model keeps enrolled, fresh and recording counts separate. These thresholds are proposals to
benchmark on devices, not OS guarantees.

**6. Roles and grants are separate.** A **slot role** says what a phone records: `primary` or `camera`
(`jovra.camera-invite/1`). **Grants** say what a participant may do: `viewer` (default for everyone), `marker`,
`scorer` and `capture-controller`. The host phone holds `scorer` and `capture-controller` unless it hands them over; a
camera guest gets `record-local`, `view-own-preview` and nothing more until the host grants it. Grants are explicit,
visible and revocable, and are checked by the host on every command. *Amended:* a member holds a **set** of command
roles (an invitation grants one; the host holds two), and each command claims one role from that set; the host binds
every command to the authenticated channel peer, never to the member or device named in its body (`spec/room`
ledger checks 1–2). A watch never issues a room capture request (ADR-0026 §6 as amended). A watch inherits at most its phone's grants
(ADR-0026). Recommended to the contracts owner: map the roster's existing `host-controls` permission to
`capture-controller` and add the other three, rather than adding a parallel role list.

**7. Commands are idempotent and answered with receipts.** Every command carries `commandId`, issuer, claimed grant,
`roomId`, `hostEpoch`, expiry, target scope and `baseEventRevision` where it applies. The host persists command IDs with
a payload hash and the final result across retries and restarts: the same ID with the same payload returns the
original receipt; the same ID with a different payload is rejected and logged as a security event. *Amended:* the
store is scoped to the authenticated member; the hash excludes the volatile send age (`expiry.ageAtSendMs`, which the
issuer recomputes on every send so time spent queued counts towards expiry); and rejections from authentication,
session or epoch checks are never stored, so they cannot burn an ID. Receipts go
Pending → Accepted, Rejected, Expired or Conflicted, with per-device results for a fan-out. Two scorers writing against
the same revision produce one accepted point and one visible conflict. A successful send is never a receipt; a
"start" is an intent, and only `recordingStarted` acknowledgements count (ADR-0017).

**8. No remote stop-all on disconnect.** Losing the host, the network or a peer never stops, pauses or deletes any
local recording. Every phone keeps its own Stop. "Stop all" is a deliberate, confirmed fan-out request that names its
targets and reports each device's Accepted, Failed or Unknown result; there is no blanket success banner. A remote
start may need the target phone unlocked, in the foreground and with camera permission, so it can end Pending or
Rejected; JOVRA never implies it can force a camera on in the background.

**9. Carriers beyond the LAN.**
- **MultipeerConnectivity** is an Apple-only experiment behind a flag. It must carry the same envelopes and pass the
  same trust vectors, and it is never the shared contract (no Android implementation, OBSERVED).
- **Wi-Fi Aware** waits for an iPhone↔Android interop spike (UNVERIFIED interop).
- **The cloud room** (Supabase Realtime private channels authorized by RLS) comes later, opt-in, behind ADR-0014's
  activation gates, with its own authorization and retention review. Stills never travel through it by default, and
  its round trips make clock pings there a coarse prior only (multicam-sync §2.8).
- **No network** is a first-class path: every phone records alone and alignment is post-hoc (ADR-0017).

**10. What travels.** Room traffic is metadata, acknowledgements, telemetry, clock pings and small preview stills
labelled with their age. Originals never travel over the room. Stills are previews, not project media. Logs never
contain the QR secret, keys, or tokens.

**Tests that must be able to fail** (*amended:* golden vectors in `spec/room/fixtures`, run by
`scripts/spec/validate_room.py` in CI and by Kotlin `:room-protocol` and its Swift twin; transport cases on devices): expired, reused and revoked invites; a QR with a
public or arbitrary endpoint; a wrong host key; a mismatched comparison code; wrong room, old epoch and replayed or
non-increasing `seq`; same `commandId` with a different payload; two scorers on one revision; a viewer attempting score
or stop-all; Recording reported but nothing heard (frozen elapsed, delayed then Unknown); host loss with every local
capture surviving; partial stop-all fan-out (`design-reference/adaptive/brief/acceptance-matrix.md`).

## Amendment 1 (2026-10-07)

`spec/room` landed the same day with the records, a Python reference and 153 fixture cases. An adversarial review then
found eighteen defects in that reference (`spec/room/README.md` §Defect register, D1–D18), four of which change this
ADR's wording: the comparison code (point 3: commit-then-reveal), the clock (point 5: a clock that counts during
sleep), grants as a set bound to the authenticated peer (point 6), and the idempotency store (point 7). The rest are
contract rules this ADR already implied: an unauthenticated higher-epoch envelope never changes a receiver's state
(point 4: "a claimed host is never accepted because it says so"), a resolved DNS-SD address passes the same LAN
allow-list (point 2), strict QR parsing so ports cannot disagree on the pinned key (point 2), a roster revision for
membership changes, and enrolment counted from the roster (point 5).

Still not in Room contract v1, and therefore not shippable on any screen until the contract adds them (open finding
F-ROOM-STILL in `docs/spec/adaptive-open-findings.md`): preview stills (point 10) and clock pings. The Android court
network (point 1, `LocalOnlyHotspot`) now travels in the QR's optional `network` block.

## Considered Options

- **MultipeerConnectivity as the room.** Rejected: Apple-only, and the room must mix iPhone and Android.
- **Cloud-first room.** Rejected for v1: needs accounts and Internet at the court, and the backend is not live
  (ADR-0014).
- **A 6-digit PSK or a display code as the secret.** Rejected: brute-forceable offline from one captured handshake.
- **Trust on first use, or approval by device name.** Rejected: a stranger can name a phone "Jon's iPhone".
- **Freshness from sender timestamps.** Rejected: phone wall clocks disagree and queued delivery hides delay.
- **Auto stop-all when the host disappears.** Rejected: it turns a Wi-Fi blip into lost footage.

## Consequences

Pairing takes a scan and one comparison tap per phone. The UI shows ages, Unknown and Pending everywhere instead of
optimistic states. Raising Android's targetSdk to 37 requires re-verifying this transport (G-TARGET37). Two-phone
behaviour, permissions, background limits, heat and six-device endurance can only be proven on physical devices;
fixture-room UI tests prove logic, not wireless timing.

Sources: `docs/research/studio/multicam-sync.md` §§0, 2.1–2.8, 3; `design-reference/adaptive/brief/session-connectivity.md`,
`acceptance-matrix.md`; `docs/spec/studio-v1-spec.md` SD10, ST23–ST24 stories 33–53, STU-30/31;
`spec/schemas/studio/camera-invite.schema.json`; `docs/backend/security-model.md` §8.2;
`docs/research/android/toolchain-and-devices.md` §§4.3, 5.2; `docs/adr/0010`, `0014`, `0017`, `0024`, `0026`;
`spec/room/README.md` (contract, defect register D1–D18);
https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy ;
https://developer.android.com/reference/android/net/nsd/NsdManager ;
https://developer.android.com/privacy-and-security/local-network-permission ; https://supabase.com/docs/guides/realtime/authorization .
