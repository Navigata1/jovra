---
module: room
reference: [spec/reference/studio/room.py]
cases: [spec/reference/studio/cases/room_cases.py]
kinds: [jovra.room/1, jovra.room-transcript/1, room]
coverage: covered
swift: pending
kotlin: pending
---

# Room: JOVRA Room v1 messages, the join code, comparison codes and host transcripts

`spec/reference/studio/room.py` is the Python reference for the JOVRA Room v1 wire protocol (`jovra.room/1`, SD10;
`docs/research/studio/multicam-sync.md` §§2.4–2.7; ADR-0027 as amended 2026-10-07). It holds the 4-byte
length-prefixed framing, the strict QR join-payload decoder, the guest commitment, the join proof, both comparison
codes, the grant table, receiver-owned freshness, per-device receipt results and a host state machine that replays a
transcript. `spec/reference/studio/cases/room_cases.py` writes four transcripts, their invalid cases, the `room`
vectors and four self-tests. `python3 scripts/spec/validate_studio.py --list` prints the current case count of every
kind below and its Swift and Kotlin status.

Status: **proposal plus checked fixtures.** No transport, TLS stack, Bonjour/NSD, camera or device was used to produce
it. Passing the validator proves the rules are consistent, that the reference follows them, and that the shared
formulas agree with `spec/room`. It does not prove anything about a real LAN, background delivery, heat or timing.

| Schema | Record | What the reference adds beyond the schema |
|---|---|---|
| `room` (`jovra.room/1`) | One message: `roomId`, `hostEpoch`, sender `deviceId`, per-sender `seq`, the sender's own `sentMonoNs`, `type` and a typed `body` | Nothing on its own; every message is checked in the context of a transcript |
| `room` (`jovra.room-transcript/1`) | One host's ordered view: the room it starts with, then `invite`, `in`, `out`, `local`, `comparison`, `restart` and `observe` steps. Each `in` step declares the verdict the host must reach | `room.check_transcript` replays it. It raises the rule's code at the first step where the host accepted what it must refuse (or the reverse), sent what it may not send, emitted a receipt the commands and acknowledgements do not give, or showed a screen state the room state does not give. Every command must be answered by a receipt (`missingReceipt`) |

## How this relates to `spec/room` (read this first)

`spec/room` (the `jovra.room.<record>/1` family and `scripts/spec/validate_room.py`) landed on 2026-10-07, after this
ticket was written. ADR-0027's amendment says "`jovra.room/1`" means that family. This module does **not** fork the
trust rules. Where `spec/room` already fixes a byte, this module uses the same byte, and the self-test
`room-spec-room-drift` fails if the two references ever disagree:

- **QR payload:** exactly `spec/room`'s `jovra.room.invitation-payload/1` (`sessionId` carries the room id), with
  strict decoding (prefix, unpadded base64url, no duplicate keys, canonical bytes). Every QR in the transcripts
  validates against `spec/room/schemas/invitation-payload.schema.json` and decodes identically with `spec/room`'s
  decoder.
- **LAN allow-list:** RFC 1918, IPv4 link-local, IPv6 ULA and link-local, port 1024 or higher. It is compared with
  `spec/room` address by address (including CGNAT, loopback, multicast and documentation ranges).
- **Guest commitment, join proof and comparison code:** the same strings and the same digest-to-digits rule (the
  first 32 bits mod 10⁶), compared on fixed inputs.
- **Grant names** equal `spec/room`'s `commandRole` enum, the display-code and nonce patterns are equal, and the
  freshness thresholds equal its default policy (5,000 and 15,000 ms).

What this module adds to `spec/room` is the **capture message set** that `spec/room` leaves out
(`recordingStarted`, `heartbeat`, `still` metadata, `segmentEvent`, `recordingStopped`, `commandResult`), the
envelope (`roomId`, `hostEpoch`, `deviceId`, `seq`, `sentMonoNs`) with 4-byte framing, the **typed-code
channel-binding** comparison code, and host transcripts for the ST23/ST24 fixture room. Whether S69–S72 should build
on this envelope or on `spec/room`'s records is the open "S68–S72 rescope decision" in
`docs/spec/android-watch-tickets.md` (cross-DAG finding 1). Nothing here decides it.

## Messages (`jovra.room/1`)

Framing: a 4-byte big-endian length, then the message's UTF-8 JSON. Transcripts record the canonical length (sorted
keys, no whitespace). A receiver refuses a declared length over 65,536 bytes before it reads the body
(`frameTooLong`). It also refuses a stream that ends inside a frame (`truncatedFrame`), a body that is not one JSON
object or holds a floating-point number (`malformedFrame`), and a duplicate key (`duplicateKey`). In a transcript, the
declared length must equal the canonical length (`frameLengthMismatch`).

| Type | Direction | Body |
|---|---|---|
| `hello` | both | role, app version, platform, protocol 1; the host's carries the opaque room hint |
| `join` | guest → host | QR path: `inviteId`, guest key, commitment, observed host key, HMAC proof. Typed path: display code and `channelBinding: tls-exporter`. Display name and model are the guest's own claims |
| `approvalRequest` | host → guest | QR path: the host's fresh nonce, sent only after the guest committed. Typed path: no nonce |
| `joinReveal` | guest → host | The guest nonce that opens the commitment |
| `approve` / `decline` | host → guest | Approve names the guest **key** and the basis (`comparisonCode` or `channelBindingCode`), never a name. Decline gives `codesDidNotMatch`, `hostDeclined` or `attemptsExhausted` |
| `revoke` | host → guest | Removes a member (its connection closes, its code is void) or withdraws an open code |
| `roleAssigned` / `grantChanged` | host → guest | Slot, slot role (`primary` only for the host, `camera` otherwise), command grants, capabilities |
| `readiness` | guest → host | Camera and microphone permission, preset support, battery %, charging, Low Power Mode, free bytes, minutes left, thermal |
| `recordingIntent`, `stopOne`, `stopAll`, `bookmark` | any member → host; host → targets (relay) | Commands: `commandId`, `issuer`, `claimedGrant`, `expiry` (`ttlMs`, `ageAtSendMs`), `target` (scope and device ids), `baseEventRevision`; plus `intentId` (start), `confirmed: true` and `targetLabel` (stop all), match-clock hint and note (Mark point) |
| `recordingStarted` | guest → host | The acknowledgement: `intentId` (null for a start made on that phone), segment, `fileZeroHostNs`, wall clock at start, preset, fps, timescale, orientation lock |
| `heartbeat` | guest → host, every 2 s | Capture state, segment, saved-through time, free bytes, battery, thermal, dropped frames |
| `still` | guest → host, every 5 s (2 s while framing) | Metadata only (id, capture time on the sender's clock, size, hash). Only at thermal nominal or fair (`stillWhileHot`), and never more often than its cadence (`stillCadence`) |
| `segmentEvent` | guest → host | Interruption, gap start or end, rollover, with a reason; only from a recording camera |
| `recordingStopped` | guest → host | The stop acknowledgement with its segments (`commandId` null for a stop made on that phone) |
| `commandResult` | guest → host | A target's `Failed` or `Denied` result for a relayed command, with a reason |
| `receipt` | host → issuer | `Pending`, `Accepted`, `Rejected`, `Expired` or `Conflicted`, a reason code, `securityEvent`, the capture revision and per-device results |

## Rules (each pinned by a code)

### Join code and approval

- **Host side, in order:** `unknownInvite` → `inviteRevoked` (revoked, superseded by a new code for the slot,
  attempts exhausted, or voided by a host restart or transfer) → `inviteUsed` → `inviteExpired` (on the host's own
  clock; exactly at the deadline is still valid) → `slotFull` → `roomFull` (six phones) → `joinInProgress` →
  `alreadyMember` → `guestKeyNotChannelKey` → QR path: `hostKeyMismatch`, `badProof`; typed path:
  `typedCodeNeedsChannelBinding`.
- **Commit-then-reveal (QR path):** the guest commits to `SHA-256("jovra-room-commit|" guestKey "|" guestNonce)`.
  The host sends its nonce only after that (`approvalRequest`), and the guest reveals (`revealBeforeChallenge`,
  `commitmentMismatch`). Three failed attempts revoke the code. Both screens show
  `SHA-256("jovra-room-sas|" hostKey|guestKey|qrNonce|hostNonce|guestNonce)` → first 32 bits mod 10⁶.
- **Typed-code path:** a typed code pins no host key, so its six digits come from the TLS channel binding:
  `SHA-256("jovra-room-sas-tls|" exporter|hostKey|guestKey)` → first 32 bits mod 10⁶. A man in the middle terminates
  two channels with two exporter values, so the screens disagree. A typed join without a binding is refused.
- **The comparison step** records both screens and the tap. Each screen must show the code its side's keys and nonces
  give (`comparisonCodeWrong`). Allow on codes that differ is refused (`comparisonCodeMismatch`). A decline counts an
  attempt and must give its reason (`declineReasonMismatch`).
- **Approve** needs that comparison (`approvalWithoutComparison`), names the joining key and device
  (`approvalKeyMismatch`), uses its path's basis (`approvalBasisMismatch`) and re-checks expiry. A slot role is bound
  only after approval (`roleBeforeApproval`).
- **Slot roles and grants:** the first `roleAssigned` gives the invitation's slot (`slotMismatch`), `viewer`, and only
  `record-local` and `view-own-preview` (`cameraGrantExceeded`). Later assignments keep the grants
  (`grantMismatch`); only `grantChanged` changes them, and everyone keeps `viewer`. Only the host holds `primary`.
  The roster's `host-controls` permission is `capture-controller`.
- **The QR the host shows** names this room, epoch, host key, invitation and code. It gives `viewer` only
  (`payloadMismatch`). Its secret is 32 bytes (`secretLength`) and its window at most 10 minutes (`inviteLifetime`).
  Its DNS-SD instance is the room's opaque hint `jovra-` + 10 random characters (`roomHintMismatch`; the room header's
  pattern makes a name a schema error). Its endpoints are local (`endpointNotAllowed`). A new code for a slot voids the
  old one. A code for a slot that already has a phone is refused (`slotOccupied`).

### Every inbound frame

Order: framing → `revokedPeer` (revoke closes the connection) → `wrongRoom` → `staleEpoch` / `unknownEpoch` → the
channel binding (`senderNotChannelPeer`, `notApproved`, and `reauthRequired` until a member says hello in a new
epoch) → `hostOnlyMessage` → `seqNotIncreasing` (per channel per epoch). A refused frame changes nothing and is not
contact.

### Commands and receipts

Order: `issuerNotSender` → idempotency per issuer → `grantNotHeld` (security event) → `grantNotPermitted` → expiry
(capture commands: `ttlTooLong` over 30 s, `Expired/unboundedTransit` when the transport cannot bound transit,
`Expired/commandExpired`) → targets (`noTargets`, `unknownTarget`, `targetScope`, `stopAllTargetsIncomplete` (stop all
names every enrolled camera), `targetLabelMismatch`) → `Conflicted/baseRevisionStale` for capture commands against an
older capture revision → Accepted.

- **Idempotency:** the host keeps `(issuer, commandId)` with the SHA-256 of the canonical command minus
  `expiry.ageAtSendMs`. A retry with the same payload is answered with the original receipt. A different payload under
  the same id is `Rejected/commandIdReuse` with `securityEvent: true`, and the stored receipt stands.
- **Per-device results:** `Accepted` from the target's `recordingStarted` (for the intent) or `recordingStopped`
  (naming the command); `Failed` or `Denied` from its `commandResult`; `Pending` until the command's deadline on the
  host's clock, then `Unknown/noAcknowledgement`. A final result never changes. A host restart turns open results into
  `Unknown/hostEpochChanged`, and nothing is replayed.
- A start is an intent. A receipt saying a camera started without its acknowledgement is refused (`receiptMismatch`).

### Freshness and the screen

- Age is measured on the host's own monotonic clock since it last accepted a frame from that phone. Fresh ≤ 5,000 ms
  < Delayed ≤ 15,000 ms < Unknown. A phone not heard since the host's process restarted is Unknown with no age. The
  host's own camera is `Local`.
- Stale rows read `No contact for M:SS`, plus ` · may still be recording` when the last report was Starting,
  Recording, Paused or Finalizing. **Silence is never a stop:** a row shown `Stopped` without that phone's own stop
  report is `stopInferredFromSilence`.
- **Recording on n of m:** m counts the cameras holding a slot. n counts the Local or Fresh ones whose last
  acknowledgement is `recordingStarted` for the current intent and that still report Recording
  (`recordingCountMismatch`).
- A still's age is chained: the host's time since it arrived, plus the sender's own lag between capture and send
  (`stillAgeMismatch`). Ready follows the phone's own readiness report (`readyMismatch`).

## The approval-code vector (computed by hand)

Fixed public keys: the host key is the SPKI of the P-256 generator point (the public key of private key 1), and the
guest key is the public key of RFC 6979 appendix A.2.5. Both were checked on-curve with `openssl pkey -pubcheck`. Their
SPKI SHA-256 values are `5cd252fb…7cd3` and `5a7a78cc…ecd4`. The nonces are `qrNonceFixedVector0001`,
`hostNonceFixedVector01` and `guestNonceFixedVector1`. `printf 'jovra-room-sas|…' | shasum -a 256` gives
`23a8dc13…`; `0x23a8dc13` = 598,268,947, and mod 10⁶ that is **268947** (computed with `bc` on 2026-10-08). The typed
path's code from exporter `0011…eeff` is **654318**. The man in the middle's other channel shows **032799**.

## Transcripts (`records/room-transcript.*.json`)

| Transcript | Screen | What it shows |
|---|---|---|
| `st23-lobby` | 23 | The ST23 demo: Camera 1 Jon's iPhone ready, Camera 2 Alex's phone approved by matching codes and ready, Camera 3 Corner left waiting on JVR-482 (10 min) |
| `st23-trust` | 23 | A forwarded code reused (`inviteUsed`, with the same display name as Alex's), a typed code without binding refused, a man in the middle declined, a typed code approved by its channel-binding code, an expired code, a full slot, revoke (connection and code), a host restart (old epoch, re-authentication, codes void) and a host transfer (codes void) |
| `st24-director` | 24 | The ST24 demo: REC 12:34, Recording on 3 of 3 phones from three acknowledgements, stills aged 8 s and 12 s, Mark point |
| `st24-contact-lost` | 24 | A camera silent for 42 s (Unknown, `No contact for 0:42 · may still be recording`, 3 of 4), an old epoch and a replayed seq refused, a viewer's stop-all refused, a claimed grant (security event), retry and reuse of one command id, a stale revision (`Conflicted`), unbounded transit (`Expired`) and a partial stop-all (Accepted, Accepted, Failed, Unknown) |

## Vectors (`vectors/room.json`, kind `room`)

The approval code from fixed public keys; the typed-path and man-in-the-middle codes; framing (encode with a
hand-counted prefix, two frames, over the maximum, truncated, not an object, a float, a duplicate key); freshness
bands at the 5,000 and 15,000 ms boundaries, the 42 s silent camera, and a phone unheard since a restart;
per-device results for a partial stop-all before and after the deadline; the grant mapping and permit matrix; the
joiner's QR checks (public, CGNAT and loopback endpoints, a low port, IPv6 link-local, a web URL, padding,
non-canonical JSON, 11 minutes, a 16-byte secret, a camera code with control, a wrong host key); and the ADR-0027
behaviours named by transcript step (`transcriptStep`).

## Invalid cases

Each transcript has an invalid-case file. The cases include the acceptance list: an expired code, a reused code, a role
bound before approval, approval by display name (schema) and approval of another key with the same name, an
acknowledgement counted without `recordingStarted`, a stop inferred from silence, and a frame over the maximum
length. There are also many more for proofs, commitments, epochs, sequence numbers, grants, receipts, stills, QR
endpoints, lifetimes and secrets.

## Self-tests

- `room-spec-room-drift`: the shared bytes and formulas agree with `spec/room` (see above).
- `room-camera-invite-drift`: `host-controls` maps to `capture-controller` on the Sample `jovra.camera-invite/1`
  record, the transcripts' starting grants agree with it, and the display-code pattern is the same.
- `room-message-schema`: every transcript message is a valid `jovra.room/1` message on its own, and an unknown type, a
  body of another type and a zero `seq` are refused.
- `room-secret-hygiene`: a QR secret appears only inside the QR text of its own invite step.

## Decisions taken here

1. **Approval code:** ADR-0027 §3 as amended (commit-then-reveal), not the "derived from the guest key's thumbprint"
   wording in the ticket, ADR-0017 and `docs/spec/studio-screens.md` ST23 (open finding F-ADR-0017). A code from the
   QR and the guest key alone can be ground offline. The vector still reproduces a hand-computed code from fixed
   public keys.
2. **Typed-code comparison code:** `SHA-256("jovra-room-sas-tls|" exporter|hostKey|guestKey)`, from the TLS exporter
   with label `EXPORTER-jovra-room-sas`. The label and exporter length are proposals for S70 to confirm on
   Network.framework and Android `SSLSocket` (UNVERIFIED).
3. **Camera start grants:** `record-local` and `view-own-preview` only (the ticket and ADR-0027 §6). `spec/room`'s
   `grants_for` also gives `upload-own-source` at join, and so does the Sample camera-invite record. This is recorded
   for the owners and not resolved here.
4. **Maximum frame:** 65,536 bytes. Stills travel as their own blob after their metadata, never inside a control frame.
5. **Room hint:** `jovra-` plus 10 lower-case letters or digits. `spec/room`'s sample instance name (`JOVRA Court 3`)
   passes its own looser pattern. ADR-0027 §2 asks for an opaque random hint.
6. **Stop all** targets every enrolled camera, including the host's own, and is labelled `Stop all cameras (n)`.
7. **Bookmark** is permitted to `marker`, `scorer` and `capture-controller`, never moves the capture revision, and its
   `baseEventRevision` is null.

## Not covered yet

- The transport: TLS 1.3, key pinning, the exporter, Bonjour/NSD, reconnect and the Local Network permission (S70).
  Nothing here was run between two phones.
- Clock pings (`clockPing`/`clockPong`) and the still image bytes. The fresher-still request is not modelled.
- Pausing and resuming capture over the room. `segmentEvent` checks only that the camera is recording.
- How S69–S72 consume this module versus `spec/room` (the rescope decision above). Until it is taken, a native port
  that builds both must keep the drift self-test green.
