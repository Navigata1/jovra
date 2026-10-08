# JOVRA Room v1 and the watch bridge (`spec/room/`)

Status: **proposal contract, 2026-10-07 (revision 2: verifier defects D1–D18 fixed the same day, see
[Defect register](#defect-register-2026-10-07)).** No transport, TLS stack, camera or watch API was implemented or exercised to
produce it. The schemas, reference and fixtures fix the *rules* that the native ports must agree on before any device
work starts. Passing `scripts/spec/validate_room.py` proves the rules are consistent and that the reference follows
them. It does not test a phone-to-phone transport, a paired-watch channel, background delivery or real capture. Those
are the native and physical gates in `design-reference/adaptive/brief/acceptance-matrix.md`.

Sources this turns into contracts:

- `design-reference/adaptive/brief/session-connectivity.md`: the room, invitations, freshness, commands, receipts and
  analysis envelope (the brief).
- `docs/research/studio/multicam-sync.md` §2: the "JOVRA Room v1" proposal (carriers, the QR, messages and telemetry).
- ADR-0017: the rule that only acknowledgements prove a start. The verification code itself now follows ADR-0027 §3
  as amended on 2026-10-07 (commit-then-reveal), which supersedes ADR-0017's "derived from the guest key" wording.
- ADR-0026 (watch companions, as amended 2026-10-07) and ADR-0027 (room transport and trust, as amended 2026-10-07).
- `design-reference/adaptive/brief/watch-snapshot.sample.json` and the handoff verifier
  `docs/handoff/adaptive-v3/scripts/verify_protocol_fixtures.py`.

This folder does not define a second protocol. The [reconciliation section](#reconciliation-with-jovra-room-v1-multicam-syncmd-2)
maps every message in the multicam-sync proposal onto these records.

```
spec/room/
  schemas/      JSON Schema 2020-12, one file per record, schemaVersion "jovra.room.<record>/1"
  reference/    jovra_room/ (Python 3 standard library) + generate_room_fixtures.py
  fixtures/     records/ (valid), invalid/ (patch cases), vectors/ (rule scenarios), acceptance-map.json
scripts/spec/validate_room.py   validates everything and re-runs the reference; non-zero exit on any failure
```

Run both from the repo root:

```
python3 spec/room/reference/generate_room_fixtures.py   # rewrites spec/room/fixtures (same bytes every run)
python3 scripts/spec/validate_room.py                   # add -v for detail
```

The validator is separate from `scripts/spec/validate.py` (core) and `scripts/spec/validate_studio.py` (Studio). It
imports neither. It reads `scripts/spec/jsonschema_subset.py`, the core `common.schema.json`, the capability registry
and the Studio camera-invite schemas **read-only**, for drift checks.

## What the validator checks (counts as of 2026-10-07)

| Check | Count |
|---|---|
| Schemas: only implemented keywords, every `$ref` resolves, ECMA-262 `$` anchors | 14 schemas, 3 self-tests |
| Drift: provenance labels = core `provenanceStatus`; `studioSlot` = Studio `placementSlot`; `displayCode` pattern = Studio's; analysis capability ids exist in `capability-registry.v1.json`; adapted watch fixture = adapter(design sample) | 5 |
| Valid records: schema-valid and pass their record rule | 27 |
| Invalid cases: rejected by the expected layer (schema, or reference with the exact code) | 103 (61 schema, 42 reference) |
| Rule vectors: freshness 14, watch sample 9, phone status 5, status rows 6, disconnect 1, snapshot 14, bridge 6, alerts 9, invitation 28, ledger 22, outbox 8, analysis 7 | 129 cases |
| The handoff verifier's assertions, ported onto the reference | 20 |
| Acceptance-matrix rows mapped, text-checked against the brief | 23 (14 yes, 6 partial, 3 native/physical only) |
| Secret hygiene: tokens only in the QR payload records and the Sample secrets block; the Sample hotspot passphrase only in its payload record; host logs never hold a token, proof or nonce | 2 |
| Determinism: regeneration reproduces every fixture byte for byte | 61 files |

All 232 named cases pass (OBSERVED, `python3 scripts/spec/validate_room.py`, 2026-10-07). Every command, receipt,
envelope, bridge payload, join request, challenge and reveal built inside a vector is also schema-checked. A vector
runner that raises fails the gate with a message.

**The gate can fail.** On 2026-10-07, 41 deliberate mutations of the reference were each run in scratch and each was
caught (non-zero exit with a named failing case); none is kept in the repository. They revert every defect fix below
one at a time: issuer binding (two), the higher-epoch latch, the host nonce in the verification code, the commitment
check, the volatile fingerprint field, the outbox age refresh, fail-open delivery (two), bridge replay, retired bridge
instance and pairing, capture-instance rollback, event-revision rollback, sequence reuse, host-device change, roster
update, enrolment from rows, the outbox epoch guard and draft chain, member-scoped command ids, per-source throttle
and attempt limit, `noTargets`, `finalizing`, canonical and alphabet QR checks, resolved-endpoint check, `alreadyMember`,
`Local` as fresh, the reboot rule, lookup expiry, watch capture refusal and grant sets; and seven AlertPolicy mutations
(raise and clear thresholds, re-alert cap, 45 s deferral, acknowledgement closing the outage, an Unknown camera made
critical, alerts for a camera that never recorded). The seven mutations from the
first revision (fresh threshold 6 s, unbounded treated as bounded, dedup by id only, viewer stop-all, no snapshot
replay protection, 1 h invitations, results always current) remain covered by the same vectors.

## Records

| Schema | `schemaVersion` | What it is |
|---|---|---|
| `room-common.schema.json` | (shared `$defs`) | Ids, hashes, tokens, the capture-state, role, receipt and freshness enums, the freshness policy, v1 capabilities, the score summary and source references |
| `invitation.schema.json` | `jovra.room.invitation/1` | The host's persisted invitation. It stores `joinTokenSha256` only, never the token. Single use, at most 10 minutes, bound to a session, `hostEpoch` and `hostKeySha256`. It has a lookup-only `displayCode`, a capture role, a command role and an optional Studio slot |
| `invitation-payload.schema.json` | `jovra.room.invitation-payload/1` | The QR payload, encoded as `jovra-room:1:` + unpadded base64url(canonical JSON). It carries the join token (at least 128 bits) and a nonce. Endpoints are a DNS-SD instance of `_jovra-room._tcp` or an IP literal, never a hostname or URL, and there is no URL field anywhere. An optional `network` block carries the court Wi-Fi an Android host created with LocalOnlyHotspot (SSID, WPA2/WPA3 passphrase; a secret like the token) |
| `join-request.schema.json` | `jovra.room.join-request/1` | The guest's first frame. It sends an HMAC proof instead of the token, plus the host key it actually observed, its own key fingerprint, a `guestCommitment` to a secret guest nonce, the requested roles and its consent. The display name is a claim only |
| `join-challenge.schema.json` | `jovra.room.join-challenge/1` | The host's fresh per-attempt `hostNonce`, sent only after the guest has committed |
| `join-reveal.schema.json` | `jovra.room.join-reveal/1` | The guest's `guestNonce`, opening its commitment; both screens then show the six-digit code |
| `device-status.schema.json` | `jovra.room.device-status/1` | A camera's own report: `deviceId`, `captureInstanceId`, `segmentId`, `deviceSeq`, `captureState` (Ready/Starting/Recording/Paused/Finalizing/Saved/Failed), `lastReportedElapsedMs`, and storage, battery and thermal observations. It has **no** freshness, "connected" or Unknown field |
| `room-snapshot.schema.json` | `jovra.room.snapshot/1` | The host's latest-state envelope: `schemaVersion`, `sessionId`, `hostDeviceId`, `hostEpoch`, `hostKeySha256`, `snapshotSeq`, `eventRevision`, `capabilities`, the `roster` (enrolled camera ids at a `rosterRevision`), `devices[]` (each with the host-measured `ageAtHostMs`) and `receipts[]` |
| `watch-bridge-snapshot.schema.json` | `jovra.room.watch-bridge/1` | What a paired phone forwards to its own watch: the bridge (`bridgeDeviceId` = the paired phone, `bridgeInstanceId`, `bridgeSeq`, channel WatchConnectivity or Wearable Data Layer), the `participant` (member, granted `commandRoles`, the `watchCommandTypes` left on), the roster, per-camera `ageAtBridgeMs`, `alerts[]` (critical or deferred), `latestServe` (a forwarded post-capture serve estimate or null) and receipts. It also has the `receiverObservation` that the watch writes on accept: delivery kind (`queued` is always unbounded, `interactive` always bounded), `transitBounded`/`transitMs`, `processBaselineId` and `acceptedAtMonoMs`. This is the single watch contract: ADR-0026 and `docs/spec/watch-v1-spec.md` use these names |
| `command.schema.json` | `jovra.room.command/1` | `commandId`, `sessionId`, `hostEpoch`, issuer (member, device, phone/watch surface and bridge), claimed `role`, issued-freshness context, expiry (`ttlMs`, and the volatile `ageAtSendMs` recomputed on every send), target scope, `baseEventRevision`, and a payload of one of: `PointWon`, `Undo`, `MarkForReview`, `StartRequest`, `StopOne`, `StopAllRequest` |
| `receipt.schema.json` | `jovra.room.receipt/1` | Pending/Accepted/Rejected/Expired/Conflicted with a stable reason code, the canonical event revision, the created event or mark id, conflict detail, and per-device results for capture requests (Pending/Accepted/Denied/Failed/TimedOut/Unknown) |
| `analysis-result.schema.json` | `jovra.room.analysis-result/1` | `resultId`, source references (device, capture instance, segment and frame range), `pointEventId`, `producedAt` and its revision, provenance `label`, model and calibration versions, `value` + `units` + `uncertainty` *or* an `unavailableReason`, `reviewState`, and `scoreEffect: "none"` |
| `watch-local.schema.json` | `jovra.room.watch-local/1` | Phone ↔ its own watch only, never room commands: the echo (`echoRequest`/`echoReply`, bounding transit), `ackAlert`, and the wearer's confirmed `stopOwnPhone` (no target field: a watch can only stop its own phone) with its result |
| `fixture.schema.json` | `jovra.room-fixture.*/1` | The shapes of the fixture files |

Conventions: the same as `spec/` and Studio. There is no `$id`; references are relative file references. A capture
state, receipt status and freshness value uses the brief's names (`Recording`, `Accepted`, `Fresh`). Provenance uses
the core wire values (`manual`, `estimated`, `reviewed`, `validated`), which display as Manual, Estimated, Reviewed and
Validated. Validate patterns with ECMA-262 semantics: `$` matches only at the very end, so ports must not use a regex
`$` that accepts a trailing newline.

## Rules (each one pinned by a fixture code)

### Freshness (`reference/jovra_room/freshness.py`)

- **Ages are chained, never wall-clock differences:**
  `age = senderAge (ageAtHostMs or ageAtBridgeMs) + known transit + receiver's monotonic time since accept`.
  Wall clocks from different devices are never subtracted.
- **Thresholds (proposal defaults to benchmark):** Fresh at 5,000 ms or less, Delayed above that up to 15,000 ms,
  Unknown above that. The boundaries are pinned: 5,000 is Fresh and 5,001 is Delayed; 15,000 is Delayed and 15,001 is
  Unknown.
- **Unknown regardless of age:** when transit is unbounded (a queued or background delivery, even one that "arrived just
  now"), or when the receiving process's baseline differs (restart). An interactive, acknowledged exchange that bounds
  transit is the only way back to Fresh.
- **Invalid input:** a negative age is an error (`negativeAge`), and a bounded transit without its bound is an error
  (`transitBoundMissing`).
- **Remote elapsed time:** a remote elapsed duration is always the last reported value. It is never extended with the
  receiver's clock, even while Fresh. Only the device's own UI runs its local timer. Stale rows (Delayed or Unknown)
  show the last-heard age, or none if it is unknown. They also say "may still be recording" when the last state was
  Starting, Recording, Paused or Finalizing.
- **Two paths, one rule:** a phone participant uses `ageAtHostMs` + host-to-phone transit + its time since accept
  (`observe_snapshot`); a watch uses `ageAtBridgeMs` + bridge-to-watch transit + its time since accept
  (`observe_bridge`).
- **Process baseline:** the receiver's `processBaselineId` must change on every process start and every reboot
  (include a boot id). If a reused id ever meets a clock that runs backwards, the age is Unknown; a receiver never
  crashes on its own clock.
- **Counts are separate and come from the roster:** `enrolled`, `fresh`, `delayed`, `unknown`, `reportedRecording`
  and `freshRecording`. `enrolled` is the roster's camera count, never the number of rows present; an enrolled camera
  with no row is Unknown. The device's own capture (`Local`) counts as fresh. Only freshly heard (or local) Recording
  devices count as fresh-recording, and `canClaimAllRecording` holds only when every enrolled camera does.
- **Design sample:** the watch snapshot gives 5 of 6 fresh, 5 fresh-recording and c3 Unknown, with c3 frozen at
  746,000 ms (12:26).
- **Room-link loss:** issues no command, leaves local capture as it is, and makes every cached remote row Unknown.

### Snapshot acceptance (`snapshot.py`)

The receiver is bound at join to the session, host epoch, host key, host device id and the roster it was admitted
under. **Nothing unauthenticated changes its state.** Checks run in this order, each with its own code:

| Order | Check | Code |
|---|---|---|
| 1 | Session | `wrongSession` |
| 2 | Older epoch | `staleEpoch` |
| 3 | Newer epoch: refused, state unchanged, the receiver stays live on its current host | `epochChangeRequiresReconciliation` |
| 4 | Host key | `hostKeyMismatch` |
| 5 | Host device changed under the same epoch and key | `hostDeviceChanged` |
| 6 | Non-increasing `snapshotSeq` | `replayOrOutOfOrder` |
| 7 | Decreasing `eventRevision` (the score cannot roll back) | `eventRevisionRegressed` |
| 8 | Lower `rosterRevision` | `rosterRegressed` |
| 9 | Same `rosterRevision`, different camera set | `rosterChangedWithoutRevision` |
| 10 | Device not on the roster (identity is the host's roster, not a name) | `unauthenticatedDevice` |
| 11 | Duplicate device | `duplicateDevice` |
| 12 | A capture instance the device has already left | `captureInstanceRetired` |
| 13 | `deviceSeq` going back within one `captureInstanceId` (a new capture instance may restart it) | `deviceSeqRegressed` |
| 14 | The same `deviceSeq` with different content (`ageAtHostMs`, the host's measurement, may differ) | `deviceSeqReused` |

An approved join or a departure reaches receivers as a higher `rosterRevision`, so a receiver never goes blind to a
camera the host admitted. `reconcile()` is called only after the transport has authenticated a host transfer: it
adopts a newer epoch for an approved host key and names the new host device (`epochNotNewer`, `hostNotAuthenticated`,
then `reconciled`); snapshot sequence and event revision restart with the new epoch. Sequence high-water marks,
retired capture instances and the roster survive a restart; the freshness baseline does not.

### Watch-side bridge acceptance (`bridge.py`)

The watch is bound at pairing to its own phone. In order: `notPairedBridge` (any other `bridgeDeviceId`),
`bridgeInstanceRetired` (an instance the watch has left), `replayOrOutOfOrder` (non-increasing `bridgeSeq` within the
instance), then within one session `staleEpoch`, and within one session and epoch `snapshotSeqRegressed` and
`eventRevisionRegressed`. A restarted bridge starts a new instance; a new session starts new marks; neither lets an
old payload back in. Replay marks persist across a watch restart. The schema ties `delivery: queued` to
`transitBounded: false` and `interactive` to `true`.

Record rules for the bridge payload: every device row is on the roster (`deviceNotInRoster`); `watchCommandTypes`
never contains a capture request (`watchCaptureCommand`) and never exceeds the member's roles (`watchExceedsGrant`);
an alert is `critical` exactly when it is the owner's own `ownRecordingFailed` or `ownStorageCritical`
(`alertSeverity`); `latestServe` needs `capabilities.serveSpeedResults` (`capabilityAbsent`), is a serve result
(`notServeResult`) of this session (`sessionMismatch`) and passes every analysis-result rule.

### Invitations (`invitation.py`)

**Decoding the QR.** Strict, so every port reads the same bytes the same way: the `jovra-room:1:` prefix
(`notJovraRoomCode`), the unpadded base64url alphabet only (`malformedPayload`), no duplicate JSON keys
(`duplicateKey`), and the JSON must equal its canonical re-encoding byte for byte (`nonCanonicalPayload`).

**Joiner side.** Before sending anything, the joiner checks:

- that a camera invitation never carries capture-controller: `cameraCannotControl`;
- the lifetime (`expiresAt` − `issuedAt`, both host timestamps), at most 600 s: `inviteLifetime`. The joiner never
  compares its own wall clock with the host's: expiry is the host's decision;
- the endpoints: RFC 1918, IPv4 link-local, IPv6 ULA or link-local, port 1024 or higher, otherwise `endpointNotAllowed`.
  The allow-list is explicit because Python's `is_private` includes documentation ranges. A DNS-SD instance is checked
  again after resolution (`check_resolved_endpoint`) with the same allow-list and port rule;
- the host key pinned in the QR against the key observed on TLS: `hostFingerprintMismatch`.

**Host side.** The host's checks, in order:

| Check | Code |
|---|---|
| Invitation exists | `unknownInvite` |
| Session | `wrongSession` |
| Epoch, and revoked on host transfer | `revoked` |
| Single use | `alreadyUsed` |
| One pending join at a time | `joinInProgress` |
| Expiry on the host's own clock (exactly at `expiresAt` is valid) | `expired` |
| Observed host key | `hostFingerprintMismatch` |
| Requested roles equal the invitation's roles | `roleMismatch` |
| HMAC-SHA256 proof over `sessionId\|inviteId\|nonce\|guestKeySha256\|guestCommitment` | `badProof` |
| The device or key is already a member (no second membership, no implicit role upgrade in v1) | `alreadyMember` |

**Verification code: commit, challenge, reveal.** When all of these pass, the host answers with a fresh random
`hostNonce` (`jovra.room.join-challenge/1`). Only then does the guest reveal `guestNonce`
(`jovra.room.join-reveal/1`); the host checks it against `guestCommitment` (`commitmentMismatch`) and both screens show
six digits from `SHA-256("jovra-room-sas|" hostKey|guestKey|qrNonce|hostNonce|guestNonce)` mod 10⁶. Because the guest
commits to its key before it sees `hostNonce`, a holder of a forwarded QR can no longer grind keys offline for a
matching code; each try costs one online attempt with a one-in-a-million chance.

`approve()` needs the host to confirm that the codes match (otherwise `verificationNotConfirmed`). It re-checks expiry,
epoch and membership, consumes the invitation and returns the grants. A rejected join grants nothing: no camera
permission and no originals. **Attempt limit:** three failed attempts by token holders (a declined comparison or a
commitment mismatch) revoke the invitation (`revokedReason: attemptsExhausted`), so a forwarded QR cannot raise
approval prompts without limit.

**Display code.** It is lookup-only: `authenticates: false`, and it never finds an expired invitation. Misses are
counted per requesting source in a 10-minute sliding window; after five, that source is throttled
(`lookupThrottled`) while everyone else, including the person with the right code, can still look it up.

**Host transfer.** `transferHost()` revokes every open invitation and pending join.

**Logs.** The host log never contains a token, proof, nonce, Wi-Fi passphrase or QR text.

**Grants:**

| Role | Grants |
|---|---|
| Camera (capture role) | `record-local`, `upload-own-source`, `view-own-preview` |
| Every participant | `view-room-status` |
| Command role | `command:<Type>`, from the role table below |

### Commands and receipts (`ledger.py`)

| Role | May issue |
|---|---|
| viewer | nothing |
| marker | MarkForReview |
| scorer | PointWon, Undo, MarkForReview |
| capture-controller | StartRequest, StopOne, StopAllRequest, MarkForReview |

A member holds a **set** of roles (the host typically holds `scorer` and `capture-controller`); an invitation grants
one. The host's order of checks:

1. **Channel authentication.** The transport passes the ledger the authenticated peer device (the TLS peer key bound to
   a device at join). No peer: `unauthenticatedChannel`. A peer that is no member's device: `notMember`.
2. **Issuer binding.** `issuer.memberId` must be the peer's member. A phone issuer's `deviceId` must be the peer; a
   watch issuer's `bridgeDeviceId` must be the peer and its `deviceId` one of that member's registered watches.
   Otherwise `issuerNotAuthenticated`. Steps 1–2 are security-logged.
3. **Session and epoch:** `wrongSession`, `staleEpoch`, `unknownEpoch`.

   Rejections from steps 1–3 are **never cached**: an unauthenticated or out-of-epoch submission cannot burn a
   commandId, and an honest retry after the host reaches that epoch applies.
4. **Idempotency, scoped to the authenticated member.** The key is `(memberId, commandId)`; the fingerprint is the
   canonical JSON (sorted keys, no whitespace) of the command **without** `expiry.ageAtSendMs`.
   - A retry with the same fingerprint returns the original receipt, with its current per-device state, even when its
     `ageAtSendMs` was refreshed.
   - The same key with different contents is `Rejected/commandIdReuse` and is security-logged; the stored receipt
     stands.
   - Issuers generate commandIds from a CSPRNG (at least 96 bits); member scoping means another member cannot burn
     yours anyway.
5. **Role granted:** the claimed role must be one of the member's roles: `roleNotGranted` (security-logged). A watch
   inherits its member's roles and gains nothing by pairing.
6. **Role permits the type:** `roleNotPermitted`. **A watch never issues a capture request:** `surfaceNotPermitted`
   (its "stop my phone" is local to the bridge phone, never a room command).
7. **Expiry**, without cross-device wall clocks: `age = expiry.ageAtSendMs + transport-observed transit + host
   holding time`.
   - The issuer recomputes `ageAtSendMs` from its own monotonic clock on **every** send, so time queued in an outbox
     or on a bridge counts. The host cannot see a frozen age, so this is an issuer conformance rule (Outbox vectors).
   - The host's own observation fails closed: no observation, `transitBounded` not exactly true, or a missing,
     negative or non-integer `transitMs`/`hostHoldMs` is unbounded transit. A negative value can never extend a TTL.
   - A capture request may live at most 30 s (`ttlTooLong`).
   - A capture request with unbounded transit is `Expired/unboundedTransit`.
   - Score and marker commands with unbounded transit are judged by revision instead.
8. **Targets:** a capture request needs at least one target (`noTargets`; never an Accepted receipt with nothing to
   wait for), and every target is an enrolled camera (`unknownTarget`).
9. **Score commands** need `baseEventRevision` equal to the current revision; otherwise the result is
   `Conflicted/baseRevisionStale` with both revisions, and nothing is applied. An `Undo` must name a live `PointWon`
   (`undoTargetInvalid`).
10. **Apply exactly once.**
   - **Points and undos** are appended to the event log. The tally is always recomputed from the log.
   - **Marks** are source-linked notes and never move the revision.
   - **Capture requests** return Accepted (the *request* was accepted), with a Pending result per target.

How a target phone answers a capture request:

| Device condition | Result |
|---|---|
| Unreachable | `TimedOut/unreachable` |
| No acknowledgement | `Unknown/noAcknowledgement` |
| Camera permission denied | `Denied/cameraPermissionDenied` |
| In the background | `Denied/foregroundRequired` |
| Start while the previous take is still finalizing | `Denied/finalizing` (never `Starting` over a finalizing take) |
| Finalizing fails | `Failed/finalizeFailed` |
| Start accepted | `Starting`. It is `Recording` only when the device itself reports it |

Final per-device results never change, and the banner is computed from them. `allConfirmed` needs every target
Accepted; otherwise the banner is `partial` (or `waiting` while everything is still Pending), never a blanket success.
`StopAllRequest` needs `confirmed: true` and a concrete `targetLabel`. A lost room link issues no command. A local
user's own stop is not a room command and is always available.

**Outbox (issuer side).**

- An offline command is `Pending/offlineDraft`, with no canonical revision, and the score does not move.
- Every send recomputes `ageAtSendMs` (time queued counts): a start request flushed 10 minutes later expires.
- A flush sends nothing while the outbox's epoch differs from the host's (reconcile first); drafts whose answer is
  transient (channel, session, epoch) stay queued. Nothing is dropped silently.
- Consecutive score drafts are a chain, each based on the previous draft's expected revision, so two offline points
  both apply. Once one is not Accepted, the later score drafts are held as `Pending/requiresResubmit` and are never sent
  against a revision their author did not see.
- A flush either applies the command or surfaces `Conflicted`.
- After an epoch change, receipts the new host holds are adopted. Unknown capture requests become
  `Expired/hostEpochChanged`; they are never replayed under a new host. Other drafts stay
  `Pending/requiresResubmit`.

### Watch alerts (`alerts.py`, vectors `alerts.json`)

The phone's AlertPolicy is the single source of watch alerts. `cameraUnknown` is raised only for a camera that was
freshly Recording and then Unknown for at least 3 s; it clears after 4 s Fresh; one alert per camera per outage (an
acknowledged alert stays closed for that outage); the same camera re-alerts at most once per 5 min. It is never
critical: its haptic waits for the next accepted point or 45 s, and pending alerts collapse into one haptic; a cleared
or acknowledged alert drops out. `ownRecordingFailed` and `ownStorageCritical` are critical: raised and vibrated at
once. No alert issues a command.

### Analysis results (`analysis.py`, `records.py`)

A result is shown only when the room capability exists. In v1, `liveServeSpeed` and `automatedLineCalls` are `const
false`. `serveSpeedResults` forwards phone-produced, post-capture `serveSpeed.manualAssisted` results (registry status
`estimated`). A v1 watch shows the last such result in `latestServe` with its own point and timestamp and its
Estimated label, never as live (`records/watch-bridge.with-serve.json`; ADR-0026 §3.3 as amended 2026-10-07).

**Presentation outcomes:**

| Situation | What is shown |
|---|---|
| The room capability is absent | Unavailable: `capabilityAbsent` |
| The registry lists the capability as unsupported or disabled | Unavailable: `capabilityUnsupported` |
| The value is null | Unavailable, with the record's `unavailableReason` |
| No calibration | Unavailable: `calibrationMissing` |
| The result is flagged for review | `reviewNeeded` |
| The result belongs to an earlier point | `previous`, keeping its own point and timestamp, never relabelled as current |

**Record rules:**

| Rule | Code |
|---|---|
| Exactly one of value and reason | `valueOrReason` |
| An estimated value carries its uncertainty | `uncertaintyMissing` |
| The value lies inside its uncertainty | `uncertaintyExcludesValue` |
| The capability id is in the registry | `unknownCapability` |
| No value for an unsupported capability (e.g. `bouncePlacement.auto`, `spinRpm`) | `capabilityUnsupported` |
| No `validated` label unless the registry entry is validated | `labelExceedsCapability` |

**Bounces.** An ambiguous bounce is a `MarkForReview` with reason `uncertainBounce`, or an unavailable hint; nothing
changes the score.

## Reconciliation with JOVRA Room v1 (multicam-sync.md §2)

INFERRED mapping. The research proposal and the connectivity brief describe the same room, and this contract adopts
both. Where they differ, the choice and the reason are recorded here.

| multicam-sync §2 | This contract |
|---|---|
| `roomId` | `sessionId` (the brief's term) |
| QR `jovra-room:1:<base64url(JSON)>` with `roomId`, `slot`, `exp`, `hostEndpoints`, `hostKeySha256`, `secret` (32 bytes), `nonce` | `jovra.room.invitation-payload/1`, with the same prefix and encoding: `sessionId`, `captureRole` + `commandRole` (+ Studio slot on the host record), `expiresAt`, `endpoints`, `hostKeySha256`, `joinToken` (at least 128 bits, the brief's minimum; 256 is allowed) and `nonce`. It also binds `hostEpoch` and `inviteId`, so host transfer can revoke and single use is enforceable |
| The joiner proves the secret with HMAC over `roomId‖slot‖nonce` | HMAC over `sessionId\|inviteId\|nonce\|guestKeySha256\|guestCommitment`. Binding the guest key and commitment stops a captured proof from being replayed by another device or with another commitment. ADR-0027 §3 is amended to this message |
| "One slot, one use", host approval tap | `singleUse`, `hostApprovalRequired`, `alreadyUsed` / `joinInProgress` / `alreadyMember`, a three-attempt limit, and `approve()` with the commit-then-reveal six-digit code |
| 6-digit manual code (warned: brute-forceable as TLS-PSK) | Never key material. The **display code** (`JVR-482`) is lookup-only and throttled. The **verification code** is a comparison shown on both screens and never typed in as a secret |
| `join` / `joinAccepted` / `roleAssigned` | `jovra.room.join-request/1` → `awaitingHostApproval` → `approve()` grants |
| `preflight`, `heartbeat` (every 2 s, stale after 3 missed beats) | `jovra.room.device-status/1` with observations. Staleness is the brief's receiver-side policy (Fresh up to 5 s, Delayed up to 15 s), so three missed 2 s beats land in Delayed, not "stopped" |
| `armIntent` / `startIntent` / `stopIntent` | `StartRequest` / `StopOne` / `StopAllRequest` commands with receipts and per-device results. Intent only: each phone decides locally |
| `recordingStarted` / `recordingStopped` acks | A device's own `captureState` reports, plus per-device receipt results. The host never shows "all started" from a button press |
| `mark` | `MarkForReview`, source-linked |
| `segmentEvent` | `segmentId` + `captureInstanceId` on `device-status`. Gap reasons stay in the capture journal (ADR-0010); this version adds no message |
| `still` (every 2–5 s, labelled with its age) | **Not in v1 of this contract.** A later `jovra.room.still/1` must carry the same chained-age fields; a still is never "live". Screens that show aged stills (A44, I72) or "Request a fresh still" stay behind that addition (`docs/spec/adaptive-open-findings.md` F-ROOM-STILL) |
| Android LocalOnlyHotspot court network (android-v1-spec story 225) | The optional `network` block of the QR payload (`records/invitation-payload.hotspot.json`); endpoints on it still pass the LAN allow-list |
| `clockPing` / `clockPong` | **Not in this contract.** Clock exchanges are capture-time hints for Studio's post-hoc SyncMap (ADR-0017, `spec/studio`), never alignment evidence and never a freshness input |
| Idempotent by `(deviceId, seq)` | `deviceSeq` per `captureInstanceId` (status) and `commandId` + fingerprint (actions) |
| Carriers: LAN TLS/TCP + DNS-SD, an Apple-only MultipeerConnectivity experiment, an opt-in Supabase Realtime cloud room | All carry the same records. Endpoint rules cover the LAN path only. The cloud room stays behind ADR-0014 gates with its own authorization, and is a later scope |

Android module naming follows `docs/research/android/toolchain-and-devices.md`. `:room-protocol` (JVM) implements
these records and rules, and `:room-transport` (Android) the carrier. They are never named `:room`, to avoid
confusion with androidx Room.

## Mapping to Studio's CameraInvite and roles (`spec/studio`, read-only)

Studio's `jovra.camera-invite/1` is the Build-your-match roster that a project stores. The room contract is the
protocol that fills it. The validator drift-checks the slot enum and the display-code pattern. The rest of this mapping
is INFERRED and should be confirmed by the Studio contracts owner. **No Studio file was edited.**

| Studio `camera-invite` | Room |
|---|---|
| `projectId` | The capture `sessionId` that the project's sources come from (one session per Build-your-match capture) |
| `hostDeviceId` | Snapshot `hostDeviceId`. A host change raises `hostEpoch` |
| `maxCameras: 6` | Snapshot `devices` `maxItems: 6` |
| `roles[].role: primary` | Device `captureRole: primary`, at most one (`primaryCount`). It is the host's own camera or an elected one, never invited |
| `roles[].role: camera` | Invitation and device `captureRole: camera` |
| `roles[].slot` (placementSlot) | Invitation `studioSlot` (same enum, drift-checked). `null` for non-camera participants (`slotWithoutCamera`) |
| `roles[].permissions` `record-local`, `upload-own-source`, `view-own-preview` | The identical grants for `captureRole: camera` |
| `roles[].permissions` `host-controls` (never for cameras) | Command role `capture-controller`, refused on camera invitations (`cameraCannotControl`) |
| `roles[].status` (`ready`, `waiting`, `reconnecting`, `disconnected`, `left`, `permission-denied`, `storage-low`, `thermal-warning`) | **Derived, not sender-asserted**: from receiver freshness (Fresh, Delayed → reconnecting, Unknown → disconnected), `captureState` (`Failed` + `cameraPermissionDenied` → permission-denied) and observations (`storageFreeBytes`/`estimatedMinutesLeft` → storage-low, `thermal` serious or critical → thermal-warning) |
| `roles[].recordingAcknowledged` | The device's own last report was `Recording`; "now" additionally requires Fresh (`freshRecording`) |
| `invites[].displayCode` `^JVR-[0-9]{3}$` | Invitation `displayCode`, same pattern (drift-checked), lookup-only |
| `invites[].tlsFingerprintSha256` | Invitation and payload `hostKeySha256` (TLS SPKI pin) |
| `invites[].singleUse`, `hostApprovalRequired`, at most 10 min | The same constants and rule (`inviteLifetime`) |
| `invites[].status` `issued`, `accepted`, `expired`, `revoked` | `issued`, `used`, `expired`, `revoked` (+ `revokedReason`) |
| `invites[].role: camera` | `captureRole: camera` + `commandRole` (default `viewer`) |

Recommendations for the Studio contracts owner (not made here):

- Derive the roster `status` from the room as above, rather than storing it as sender truth.
- Add `hostEpoch` to stored invites, so host transfer revocation is visible in the project record.
- Name the room `sessionId` in the project lock.

## Acceptance matrix coverage

`fixtures/acceptance-map.json` lists all 23 rows of the brief's matrix with their exact text, which the validator
checks.

**Protocol-testable (14 rows):** 4–11, 13, 14, 16 and 20–22. Each is covered by named cases that ran and passed.

**Partial (5 rows):** each has protocol cases that ran and passed, plus a native or physical part this contract
cannot test.

- Row 1: the no-duplicate-score part only.
- Row 3: baseline loss, persisted replay marks and outbox reconciliation; restoring the draft and screen after a real
  process death is native.
- Row 12: the ledger records an undo as an event and recomputes its tally. The full score, stat and export
  recomputation is pinned by the core `spec/fixtures` scoring cases.
- Row 15: start is a request with per-device Denied results; real OS camera, permission and background behaviour is a
  device gate.
- Row 17: no command on disconnect and authenticated reconciliation; that local originals survive and capture keeps
  running is native and physical.
- Row 19: the AlertPolicy (deduplication, deferral, critical kinds) and alert severity; real haptics, always-on and low
  power are watchOS/Wear OS runtime gates.

**Native or physical only (3 rows):**

- Row 2: hinge, occlusion and compact height.
- Row 18: watch shapes and fonts.
- Row 23: six-device endurance.

These rows need emulator, device or field evidence, which this contract cannot provide.

## Evidence labels

- **OBSERVED:** the validator output above (2026-10-07). The 23-row matrix and the watch sample were read from the
  design brief. The Studio slot enum and display-code pattern were read from `spec/schemas/studio/`. The capability
  statuses were read from `spec/contracts/capability-registry.v1.json`.
- **INFERRED:** the reconciliation and Studio mapping tables. The expiry model using chained command age. The
  capture-request TTL of 30 s. The five-miss, 10-minute, per-source lookup throttle and the three-attempt limit. The
  choice to derive Studio roster status from freshness. That a commit-then-reveal code over the pinned TLS channel gives
  the usual short-authentication-string bound (one online try, one-in-a-million chance) is the standard SAS argument
  (Bluetooth numeric comparison, ZRTP); no formal analysis was done here.
- **UNVERIFIED:** any native transport, TLS pinning, WatchConnectivity or Data Layer delivery and transit bounds,
  background behaviour, Android `ACCESS_LOCAL_NETWORK`/NSD behaviour, and real capture timing. The freshness thresholds
  are product defaults still to be benchmarked.

## For the ports (Swift `JovraCore`, Kotlin `:room-protocol`)

- **Fixtures in place:** read `spec/room/fixtures` directly, as with the core fixtures. Run one test per vector case
  and per invalid case, and fail on any unknown `kind` or `op`. The Android gate G-ROOM and the watch gate G-W-CONTRACT
  (`docs/spec/android-v1-spec.md`, `docs/spec/watch-v1-spec.md`) require this plus `validate_room.py` in CI before
  stage A2.
- **Peer binding:** the transport must hand the ledger the authenticated peer device for every frame; a port that
  calls the ledger without it fails `forged-issuer`.
- **Volatile field:** recompute `expiry.ageAtSendMs` on every send and exclude it from the fingerprint.
- **QR parsing:** strict base64url, duplicate-key rejection and the canonical byte comparison; never a lenient JSON
  parser.
- **Fingerprints:** compute them over canonical JSON (sorted keys, no whitespace, UTF-8, non-ASCII unescaped) and
  persist the receipt with its fingerprint across restarts.
- **Clocks:** use monotonic clocks that keep counting during sleep (`ContinuousClock`/`mach_continuous_time` on
  Apple, never `mach_absolute_time`, which pauses in sleep and would under-state age; `SystemClock.elapsedRealtime()`
  on Android) with a per-process baseline id that also changes on reboot. Never compute an age from two devices' wall
  clocks.
- **Secrets:** generate tokens and nonces with the platform CSPRNG. Keep tokens in Keychain or EncryptedSharedPreferences,
  compare proofs in constant time, and never log a token, proof or QR string.
- **Sample data:** the `secrets` block in `vectors/invitation.json` and the keys in all fixtures are derived from
  public strings. They are Sample data, not credentials. QR images in the design references are illustrative and must
  not be scanned.

## Defect register (2026-10-07)

An adversarial verifier ran two attack scripts against revision 1 of the reference (scratch, outside the repository).
Each defect below was confirmed by reading the revision-1 code path it names and by the verifier's recorded result
(OBSERVED: its `results.json` marks each as `DEFECT` with the actual outcome). None was rejected. Each fix has rejecting
fixtures, and reverting the fix makes the gate fail (the mutation run above).

| # | Defect (revision 1) | Fix | Pinned by |
|---|---|---|---|
| D1 HIGH | The ledger trusted `issuer.memberId` from the command body; a viewer could score or stop all as another member, or as an unregistered watch | `submit(command, delivery, peer)`: the issuer is bound to the authenticated channel peer, watches to the member's registered watch ids | `vectors/ledger.json#forged-issuer` |
| D2 HIGH | An unauthenticated higher-epoch envelope latched `reconciling` and locked the receiver | A newer epoch never changes state; `reconcile()` after an authenticated transfer adopts it | `vectors/snapshot.json#forged-higher-epoch-ignored`, `#epoch-change-reconcile` |
| D3 HIGH | The six-digit code used only QR data and the guest's key, so it could be ground offline | Commit, challenge (`hostNonce`), reveal; attempt limit | `vectors/invitation.json#commitment-mismatch`, `#host-nonce-binds-code`, `#attempts-exhausted`; `invalid/join-request.invalid.json#no-commitment` |
| D4 HIGH | Exact-byte resends froze the age; honest refreshed retries were treated as id reuse | `ageAtSendMs` is volatile: recomputed every send, excluded from the fingerprint | `vectors/ledger.json#honest-retry-refreshes-age`, `vectors/outbox.json#queued-capture-expires` |
| D5 HIGH | Missing, partial or negative transit observations failed open | `observed_extra_age` fails closed | `vectors/ledger.json#delivery-fails-closed` |
| D6 HIGH | No watch-side acceptance check; queued could claim bounded transit | `BridgeReceiver`; schema ties delivery kind to `transitBounded` | `vectors/bridge.json`; `invalid/watch-bridge.sample.invalid.json#queued-but-bounded` |
| D7 MEDIUM | Capture-instance rollback, revision rollback, sequence reuse, host-device change were accepted | Retired instances, `eventRevisionRegressed`, `deviceSeqReused`, `hostDeviceChanged` | `vectors/snapshot.json#capture-instance-rollback`, `#event-revision-rollback`, `#device-seq-reused`, `#host-device-changed` |
| D8 MEDIUM | Membership fixed at construction; enrolment counted from rows present | `roster` with `rosterRevision`; `counts(rows, roster)` | `vectors/snapshot.json#roster-grows`, `vectors/watch-sample.json#missing-camera-row` |
| D9 MEDIUM | `flush()` dropped drafts on an epoch mismatch; the second chained draft always conflicted | Epoch guard, transient answers stay queued, draft chains | `vectors/outbox.json#epoch-mismatch-keeps-drafts`, `#chained-drafts`, `#chain-broken-held` |
| D10 MEDIUM | Unauthenticated and transient rejections burned command ids | Authenticate, then session/epoch, then a member-scoped idempotency store | `vectors/ledger.json#unauthenticated-not-cached`, `#epoch-rejection-not-cached` |
| D11 MEDIUM | A global, permanent lookup throttle; unlimited approval prompts | Per-source sliding window; three-attempt revocation | `vectors/invitation.json#display-code-guessing`, `#attempts-exhausted` |
| D12 MEDIUM | StopAll with no cameras was Accepted with no results | `Rejected/noTargets` | `vectors/ledger.json#stop-all-no-cameras` |
| D13 MEDIUM | A start during Finalizing reported Starting | `Denied/finalizing` | `vectors/ledger.json#start-while-finalizing` |
| D14 LOW | The joiner compared its wall clock with the host's expiry | Removed: the host decides expiry | `vectors/invitation.json#joiner-side-checks` |
| D15 LOW | Lenient base64 and duplicate JSON keys | Strict alphabet, `duplicateKey`, `nonCanonicalPayload` | `vectors/invitation.json#strict-qr` |
| D16 LOW | DNS-SD endpoints skipped the LAN allow-list | `check_resolved_endpoint` after resolution | `vectors/invitation.json#dnssd-resolved-endpoint` |
| D17 LOW | A member could join again under a second invitation | `alreadyMember` (host's own key included) | `vectors/invitation.json#already-member`, `#host-is-member` |
| D18 LOW | No phone-path freshness; `Local` not counted; reboot crash; lookup ignored expiry | `observe_snapshot`, `Local` counts as fresh, Unknown instead of a raise, expiry-aware lookup | `vectors/phone-status.json`, `vectors/watch-sample.json#reboot-reused-baseline`, `vectors/invitation.json#lookup-ignores-expired` |

Residual, not fixable in a reference: a buggy issuer that never refreshes `ageAtSendMs` cannot be detected by the host
(D4a). The Outbox vectors make it an issuer conformance requirement for the Swift and Kotlin ports.
