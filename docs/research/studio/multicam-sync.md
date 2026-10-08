# JOVRA Studio: multi-camera capture and synchronization

Research for the "Build your match" layer of JOVRA Studio: up to six independent phones (primary baseline, opposite
baseline, four corners) and imported footage, brought onto one match clock with honest uncertainty. Written
2026-10-07. This is a design study, not a claim that anything is built. No service was provisioned, no device was
tested and no field footage exists yet.

Every factual claim carries one of three labels:

- **OBSERVED**: read in a primary source (Apple, Android, FFmpeg, Supabase, an RFC or paper, the repo, or the
  founder's editor), or measured in a scratch run described here.
- **INFERRED**: reasoned from observed facts. Needs a fixture or device test before it is relied on.
- **UNVERIFIED**: plausible, not checked. Do not build on it without checking.

The scratch measurements in §4.10 and §6.4 used synthetic media in a temporary scratch folder. They are not
committed, they are not field evidence, and they are labelled Synthetic in the ADR-0012 sense.

---

## 0. Summary and recommended decisions

1. **Record first, align later.** Each phone records to its own storage through the existing segment and journal
   pipeline (ADR-0010). Pairing, the host's "start all" and clock exchange are coordination and *hints*. Alignment
   is computed after capture from anchors in the footage, then reviewed. A shared start button is not frame
   synchronization (expansion prompt, OBSERVED).
2. **Transport: one room protocol, several carriers.** The shared contract is "JOVRA Room v1": small framed JSON
   messages for roles, acknowledgements, telemetry, stills and clock pings. Carriers are, in order:
   - (a) LAN TLS/TCP, discovered with Bonjour/DNS-SD on both platforms, with a QR code as the join path;
   - (b) an optional Apple-only MultipeerConnectivity experiment;
   - (c) an opt-in Supabase Realtime cloud room, behind the backend activation gates.
   No carrier is required to record (INFERRED from the product contract).
3. **Match clock = light time.** The match clock is the moment light left the scene. It is anchored to the
   primary's video clock, origin at the earliest covered instant. Each source maps onto it through piecewise affine
   maps `t_match = a + b·t_source`. A map never extrapolates into a gap (INFERRED).
4. **Correct sound travel, or don't use audio.** Between the two baseline cameras, the propagation bias flips sign
   with the hitter: about ±69 ms at 343 m/s, more than 4 frames at 60 fps. Audio anchors must be corrected with
   court geometry, or paired symmetrically. Otherwise the result is flagged and never auto-approved. A clap or ball
   bounce at the net centre is nearly equidistant from all six standard placements (computed in §4.4).
5. **Drift is real; fit it.** Independent phone clocks differ by parts per million. At 20 ppm a one-hour match
   drifts 72 ms, more than 2 frames at 30 fps. Fit offset and drift by robust regression on anchors spread across
   start, middle and end. Report residuals and a 95% prediction band. Approve only when the band stays under half
   an output frame everywhere the map is used (INFERRED target; §4.8).
6. **Two proxy classes.** An *analysis proxy* keeps the original PTS. A *render proxy* is CFR, rotation-baked, SDR,
   zero-start, has a ≤ 1 ms timebase and ships with an explicit original-PTS ↔ proxy-frame table. Originals are
   never touched (skills, OBSERVED).
7. **The founder's editor needs normalization, and is picture-only for Studio.** On copies of its code, a perfectly
   CFR 30 fps clip with an iPhone-style 1/600 timescale was rejected, and a normalized proxy passed (§6.4, OBSERVED
   scratch run). Its per-segment audio concatenation cannot keep a continuous primary audio bed across angle cuts
   (`production_preview.py:402-412`, OBSERVED). A JOVRA adapter must add a bed stage.
8. **Fixtures before footage.** Build a synthetic multi-angle generator with exact ground truth before any real
   footage arrives. It models court geometry, light time vs sound time, offset, drift, frame phase, VFR jitter,
   rotation, HDR flags, restarts and missing audio, and embeds frame IDs. Mutation tests must prove that a one-frame
   error is caught. Two-view real footage then gives Reviewed evidence. Six-device endurance can only be proved on
   physical devices (expansion prompt, OBSERVED).

---

## 1. What JOVRA already decided (repo, OBSERVED)

| Fact | Where |
|---|---|
| A recording is ordered segments with recorded gaps. Replay and analysis work in session time, never file time. | `docs/adr/0010-capture-durability-segments-and-journal.md` |
| v1 capture uses an `AVAssetWriter` fragmented-MP4 segment pipeline. `AVCaptureMovieFileOutput` is the fallback. The journal records last confirmed media time, thermal rungs and frame-rate changes. | `docs/spec/ios-v1-spec.md` §CaptureEngine (lines 741-757) |
| Media times are stored as rationals (value/timescale) so frame accuracy survives serialization. | `docs/spec/ios-v1-spec.md:878` |
| The shared schema's `timeMs` is an **integer ≥ 0**, with 0 = start of the first recording segment. A segment has `frameRate` {num, den}, `rotationDegrees`, `hasAudio`. | `spec/schemas/common.schema.json:153-167`, `spec/schemas/session.schema.json:371-399` |
| Comparison sync uses time, not frame index (60 vs 240 fps), with `syncEventTime` + `captureFPS`, ±1-frame nudge. | spec line 797, `GLOSSARY.md` "Sync point" |
| Sound-travel correction for hit detection: about 18 ms near baseline, 51 ms at the net, 86 ms far baseline. | `docs/research/technical-feasibility.md:241-242` |
| `fileOutput(_:didStartRecordingTo:startPTS:from:)` (iOS 18.2) gives start PTS on the session's `synchronizationClock`. | `docs/research/technical-feasibility.md:123-124, 673` |
| Studio sync sample: Camera 2 offset +120 ms, drift 18 ms/min, "estimates for UI layout, not measured". | `design-reference/studio/brief/implementation-states.md` |
| First sync target: reviewed two-camera visible anchors agree within one output frame. Unclear pairs flagged. | expansion prompt §Synchronization |
| The starter edit-plan validator requires every source to equal the output FPS and dimensions ("normalize first"). | `tools/studio-plan/scripts/validate_edit_plan.py:47-49` |

Two tensions to record (INFERRED):

- **Integer ms vs rational time.** Core `timeMs` is an integer ≥ 0, which is fine for one camera. A Studio match
  clock needs signed offsets between sources, since a secondary may start before the primary, and resolution finer
  than 1 ms: half a frame at 240 fps is 2.08 ms.
  - Recommendation: keep the core schema untouched. Give the Studio SyncMap integer **microseconds** for match
    time, which matches the sibling `film-engine.md` §2.1. Keep source times as rationals.
  - Put the match-clock origin at the earliest covered instant, so every match time is ≥ 0.
- **The UI sample's drift is unrealistically large.** 18 ms/min is 300 ppm. Measured smartphone audio sampling
  drift in the literature is around 8 ppm (§4.6). Keep 300 ppm as a stress fixture, not a default.

---

## 2. Pairing and transport

### 2.1 Requirements, distilled

From the expansion prompt and `implementation-states.md` (OBSERVED):

- project-scoped, expiring, revocable invitations with role slots;
- real per-device recording acknowledgements;
- secondary stills that may be stale and show their age;
- no six high-resolution live streams;
- lost host or network never stops local capture;
- Android must interoperate, and an Apple framework must not be assumed to work with CameraX.

### 2.2 Carrier options

| Carrier | Platforms | Facts | Fit for JOVRA |
|---|---|---|---|
| **MultipeerConnectivity** | Apple only | Sessions support up to 8 peers including the local peer. On iOS it uses infrastructure Wi-Fi, peer-to-peer Wi-Fi and Bluetooth. Needs `NSLocalNetworkUsageDescription` and `NSBonjourServices` (OBSERVED, Apple docs). | Six phones fit. Useful as an Apple-only experiment. **Cannot** be the shared contract: it has no Android implementation (INFERRED). Clock-ping jitter over peer-to-peer Wi-Fi or Bluetooth is UNVERIFIED. |
| **Network.framework + Bonjour (iOS) / NsdManager (Android) + TLS/TCP or WebSocket** | Both | `NWListener`/`NWBrowser` advertise and browse DNS-SD. `NWProtocolWebSocket` exists from iOS 13 (OBSERVED). Apple's TicTacToe sample uses Bonjour plus TLS between nearby devices (OBSERVED). Android `NsdManager.registerServiceInfoCallback` is API 34+, and the older `resolveService` is deprecated in 34 (OBSERVED). DNS-SD is a shared standard, so the two can find each other (INFERRED; test on devices). | **Recommended LAN carrier.** Needs a network both phones can reach (§2.3). |
| **Wi-Fi Aware (NAN)** | iOS 26+ (iPhone 12 and later); Android since 8.0 | Apple's framework offers "secure, authenticated, and encrypted peer-to-peer connections" without an access point. It pairs through DeviceDiscoveryUI/AccessorySetupKit (OBSERVED, Apple docs). Press coverage says it is an open standard that Android has supported since 8.0 (OBSERVED secondary). | Attractive for courts with no Wi-Fi. Apple's docs target certified *accessories*; iPhone-to-Android-phone pairing is **UNVERIFIED**. A later spike, not a v1 dependency. |
| **Android LocalOnlyHotspot + iOS `NEHotspotConfiguration`** | Android host, any guest | `startLocalOnlyHotspot` (API 26) creates a hotspot with no Internet for co-located devices and hands the app the SSID and credentials. "Communicating this information is up to the application" (OBSERVED). iOS can join a configured network with `NEHotspotConfiguration` (OBSERVED; it needs the Hotspot Configuration entitlement, UNVERIFIED for this app). | Lets an Android host create the court network and put the SSID and passphrase in the QR. Google's 2019 software-sync paper reports an Android limit of 11 hotspot clients (OBSERVED). An iPhone host cannot create a local-only hotspot programmatically (INFERRED). Personal Hotspot is a manual user step. |
| **Supabase Realtime cloud room** | Both, Internet required | Private channels are authorized by RLS on `realtime.messages`, using `realtime.topic()` and the `extension` field (OBSERVED). Limits are in §2.8. | Optional, opt-in. Good for status and acks when phones are on cellular. Poor for clock sync and stills (§2.8). |

### 2.3 Network topologies at a court (INFERRED)

1. **Venue Wi-Fi.** Bonjour discovery plus the QR fallback. Client isolation on public Wi-Fi can block peer
   traffic. Detect it, and fall back to a QR with the host's IP and port, then to independent recording.
2. **Android host hotspot.** `LocalOnlyHotspot`, with the SSID and passphrase in the QR.
3. **iPhone Personal Hotspot.** A manual step. The app explains it and does not depend on it.
4. **Wi-Fi Aware.** Future, after an interop spike.
5. **No network.** Every phone records alone and alignment is entirely post-hoc. This must be a first-class,
   well-designed path, not an error state, because it is also the import path for old footage.

### 2.4 QR join codes and security (INFERRED design)

- **The payload is not a web URL.** Use a versioned custom-scheme string handled only by the in-app scanner, so the
  secret never reaches a web server, link preview or analytics:
  `jovra-room:1:<base64url(JSON)>`, with fields `roomId`, `slot` (role), `exp` (≤ 10 min), `hostEndpoints`
  (Bonjour name and/or `ip:port`), `hostKeySha256` (TLS SPKI pin), `secret` (32 random bytes), `nonce`.
- **One slot, one use.** A code is valid for one slot. The host approves each joiner on screen, showing device model
  and chosen name, before the role is bound. Revoking a slot closes that connection and invalidates its code.
- **Transport security.** TLS 1.3 with a host-generated key pinned via `hostKeySha256`:
  - iOS: `sec_protocol_options_set_verify_block`; Android: a custom `TrustManager`.
  - The joiner proves possession of `secret` in its first frame, as HMAC over `roomId‖slot‖nonce`.
  - A 6-digit manual code is weaker: TLS-PSK from 6 digits can be brute-forced offline from a captured handshake.
    Use it only as a short-range fallback that still requires the host's approval tap.
- **Permissions.**
  - iOS: Local Network privacy prompts on the first local operation. It needs `NSLocalNetworkUsageDescription` and
    the declared `NSBonjourServices` types (OBSERVED, TN3179 and the MultipeerConnectivity docs).
  - Android 16: local network protection is opt-in, via `NEARBY_WIFI_DEVICES` (OBSERVED).
  - Android 17, apps targeting SDK 37+: it is **mandatory**. The permission is `ACCESS_LOCAL_NETWORK`, and "local
    network is blocked by default" (OBSERVED).
  - Addresses resolved through the NSD system picker (`FLAG_SHOW_PICKER` plus `registerServiceInfoCallback`) do not
    need the permission (OBSERVED). A QR-supplied raw LAN IP does (INFERRED from the same page's rule that traffic
    to and from a local network address requires the permission).
  - So the Android guest should prefer the NSD picker path and treat a QR IP as the fallback that asks for the
    permission.
- **Privacy manifest.** Using `mach_absolute_time` for clock pings means declaring a required-reason API in
  `PrivacyInfo.xcprivacy` (OBSERVED on the API page). The exact category and reason code must be chosen from
  Apple's list (UNVERIFIED here).

### 2.5 Room messages (INFERRED; every message has `roomId`, `deviceId`, `seq`, `sentMonoNs`)

| Message | Direction | Content | Note |
|---|---|---|---|
| `join` / `joinAccepted` / `roleAssigned` | guest ↔ host | slot, device model, OS, app version | Host approval required |
| `preflight` | guest → host | supported presets, chosen preset, free bytes, estimated minutes left, battery %, charging, Low Power Mode, thermal state, mic permission | Same fields as `CaptureEngine.prepare` (spec) |
| `armIntent` / `startIntent` / `stopIntent` | host → all | intent id | Intent only. Each device decides locally and can always start or stop alone |
| `recordingStarted` (ack) | guest → host | `intentId`; `segmentId`; `fileZeroHostNs` (§3.2); `wallClockAtStart`; preset; fps {num, den}; timescale; orientation lock | **Evidence that the device reports recording.** The host shows "Recording on 4 of 5", never "all started" on a button press |
| `heartbeat` | guest → host, every 2 s | saved-through media time, segment index, free bytes, battery, thermal, dropped-frame count | Age shown on the host. Stale after 3 missed beats |
| `still` | guest → host, every 2–5 s | small JPEG/HEIC, capture `monoNs` | Labelled with age, never "live" |
| `mark` | any → host | match-clock hint, note | Same semantics as Mark point |
| `segmentEvent` | guest → host | interruption, gap start/end and reason, segment rollover | Mirrors the journal |
| `clockPing` / `clockPong` | guest ↔ host | t1, t2, t3 (t4 local) | §3.3 |
| `recordingStopped` (ack) | guest → host | segment list, durations, byte sizes, optional SHA-256 later | The file itself, at import, is the final evidence |

Framing: 4-byte length-prefixed JSON over TLS/TCP. Use `NWProtocolFramer` on iOS and plain sockets on Android, or
WebSocket frames if one stack is shared with a cloud relay. Messages are idempotent by `(deviceId, seq)` (INFERRED).

### 2.6 Preview stills: cadence and bandwidth (INFERRED arithmetic; image sizes UNVERIFIED until measured)

Assume a 640×360 JPEG at moderate quality is 20–60 KB for a real court scene. Use 40 KB for planning.

| Secondaries | Cadence | Throughput | Notes |
|---|---|---|---|
| 5 | every 5 s | 5 × 40 KB / 5 s = 40 KB/s ≈ 0.32 Mbit/s | Default |
| 5 | every 2 s | 100 KB/s ≈ 0.8 Mbit/s | While framing, before start |
| 5 | every 1 s | 200 KB/s ≈ 1.6 Mbit/s | Only while the host is looking at one camera |
| 6 | heartbeat only, 400 B every 2 s | 1.2 KB/s | Always |
| 5 | live 720p30 video | 5 × ~2.5 Mbit/s ≈ 12.5 Mbit/s, plus encoder heat on every phone | Rejected by the brief |

Rules (INFERRED):

- A secondary encodes a still only when its thermal state is ≤ fair. It stops stills first under the heat ladder,
  before recording quality changes.
- The host can ask one camera for a fresher still.
- Stills never travel through the cloud room by default (§2.8).

### 2.7 Device telemetry

| Signal | iOS (OBSERVED API) | Android (OBSERVED API) |
|---|---|---|
| Thermal | `ProcessInfo.thermalState` (nominal/fair/serious/critical). `AVCaptureDevice.systemPressureState`: at `shutdown` the session is interrupted, and Apple suggests lowering `activeVideoMinFrameDuration` | `PowerManager.getCurrentThermalStatus()` (API 29). `getThermalHeadroom(forecastSeconds)` (API 30): 1.0 = severe throttling; no benefit from calling it more than about once per second |
| Battery | `UIDevice.batteryLevel` / `batteryState` (monitoring must be enabled), Low Power Mode | `BatteryManager`, `PowerManager.isPowerSaveMode()` |
| Storage | `volumeAvailableCapacityForImportantUsageKey` (a required-reason API, already in the spec) | `StatFs` |
| Clock | `mach_absolute_time` / `CMClockGetHostTimeClock()` | `SystemClock.elapsedRealtimeNanos()` |

The host shows each value with its age. Minutes remaining use the spec's existing estimate: bitrate × planned length
× 1.2, then the measured slope after 30 s. A device that falls silent keeps recording; the host marks it "no
contact for 0:42", never "stopped".

### 2.8 The opt-in cloud room (Supabase Realtime)

Plan limits (OBSERVED, Supabase docs, checked 2026-10-07):

| Plan | Concurrent connections | Messages/s | Broadcast payload | Presence msgs/s |
|---|---|---|---|---|
| Free | 200 | 100 | 256 KB | 20 |
| Pro | 500 | 500 | 3,000 KB | 50 |
| Team | 10,000 | 2,500 | 3,000 KB | 1,000 |

- **Authorization.** Use private channels with RLS policies on `realtime.messages`, for example membership in
  `project_members` for the topic (OBSERVED). Anonymous sign-ins use the `authenticated` role and can be told apart
  by the `is_anonymous` JWT claim (OBSERVED), so a tester room needs no permanent accounts. Live activation still
  follows the backend gates.
- **Bandwidth and limits.** Heartbeats and acks fit easily: 6 devices at 0.5 Hz is about 3 messages/s. How fan-out
  counts against the messages/s quota is UNVERIFIED. Stills would be base64 (+33%) and compete with that quota.
  Keep them on the LAN, or later upload occasional thumbnails to private R2 by reference.
- **Clock pings.** Over cellular, round trips of tens to hundreds of ms bound the offset error at δ/2 (§3.3). That
  is a coarse prior only, though still enough to resolve rally-rhythm ambiguity (§4.3).

---

## 3. Clock alignment at capture time (hints, not truth)

### 3.1 The clocks on a phone

| Clock | Behaviour | Source |
|---|---|---|
| Wall clock (`Date`, `System.currentTimeMillis()`) | Network-set and can jump backwards or forwards. Only for "when" in human terms | Android `SystemClock` docs (OBSERVED) |
| iOS `mach_absolute_time` | Monotonic. "Does not increment while the system is asleep." Prefer `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` | Apple (OBSERVED) |
| iOS `mach_continuous_time` | Monotonic and counts sleep (`CLOCK_MONOTONIC_RAW`) | Apple (OBSERVED) |
| `CMClockGetHostTimeClock()` | Host time clock. On macOS it uses `mach_absolute_time` in a large timescale (OBSERVED). That iOS uses the same basis is INFERRED | Apple |
| `AVCaptureSession.synchronizationClock` (iOS 15.4+) | "All capture output sample buffer timestamps are on the synchronization clock's timebase." It replaces `masterClock` | Apple (OBSERVED) |
| `CMSyncConvertTime(t, from:, to:)` | Converts between clocks and timebases. With different host clocks it "compensates for measured drift" | Apple (OBSERVED) |
| Android `elapsedRealtimeNanos` | Monotonic, includes deep sleep, recommended for interval timing | Android (OBSERVED) |
| Camera2 `SENSOR_TIMESTAMP` | "Time at start of exposure of first row." Comparable to `elapsedRealtimeNanos` only when `SENSOR_INFO_TIMESTAMP_SOURCE == REALTIME`; with `UNKNOWN` it is comparable only within the same camera | Android (OBSERVED) |
| Camera2 `SENSOR_ROLLING_SHUTTER_SKEW` | First-row to (last+1)-row exposure-start skew, ≈ frame readout time. Scale by used rows N/H. Optional; may be null | Android (OBSERVED) |

Recommendation (INFERRED): store every capture hint on the device's **monotonic** clock: `mach_absolute_time`
(uptime) on iOS, matching host time, and `elapsedRealtimeNanos` on Android. Store the wall clock beside it for
humans only. Recording keeps the phone awake, so uptime clocks do not pause mid-recording.

### 3.2 Mapping file time to the device clock

- **iOS asset-writer path, which the spec chose.** `startSession(atSourceTime:)`: "the first session begins at movie
  time 0, so a sample you append with timestamp T plays at movie time (T − startTime)" (OBSERVED). The app picks
  `startTime` from the first sample buffer's PTS, which is on `synchronizationClock`. So:
  `fileZeroHostNs = CMSyncConvertTime(startTime, from: session.synchronizationClock, to: CMClockGetHostTimeClock())`.
  This is an exact source → host map. Journal it per segment. Each new segment writer records its own value, which
  links segments of one device on one clock (INFERRED; the core of §4.7).
- **Movie-file-output fallback.** `fileOutput(_:didStartRecordingTo:startPTS:from:)`, iOS 18.2+, gives the start PTS
  (OBSERVED). On iOS 18.0–18.1 use the research's `recordedDuration` workaround, about 1 frame of error (UNVERIFIED).
- **Android CameraX.** The release notes describe a `CameraUseInconsistentTimebaseQuirk`: on one chipset under
  Android 12, recorded audio was "offset by the amount of time the device is in a suspended state" (OBSERVED). This
  is evidence that per-device A/V offsets are real and need a fixture.
  - A public CameraX API that exposes the recording's first-frame sensor timestamp was not found (UNVERIFIED).
  - Options: log `SENSOR_TIMESTAMP` through Camera2 interop capture callbacks and match the first encoded frame
    (fragile), or write an own Camera2 + `MediaCodec` + muxer pipeline where every frame's sensor timestamp is
    known.
  - Decide in the Android port. Post-hoc alignment (§4) does not depend on this.
- **Imports (old footage).** Only container metadata is available: QuickTime creation date, usually 1 s resolution
  (UNVERIFIED for all sources), which may be in the wrong timezone. Use it as a weak prior, ±seconds.

### 3.3 NTP-style offset estimation over the room (OBSERVED equations, RFC 5905)

The guest sends at t1 (guest clock). The host receives at t2 and replies at t3 (host clock). The guest receives at
t4.

```
offset  θ = ((t2 − t1) + (t3 − t4)) / 2        host − guest
delay   δ = (t4 − t1) − (t3 − t2)
|error(θ)| ≤ δ / 2          (path asymmetry bound; RFC 5905 "synchronization distance")
```

- **Filter.** Send K pings in a burst and keep the minimum-δ sample. The Google software-sync paper used a min-filter
  with K = 300, under 1 s per device, on a dedicated hotspot. It reports about 32 µs mean absolute clock error and
  under 250 µs overall capture sync on Pixel phones (OBSERVED, Ansari et al. 2019).
- **App-level reality.** A 2014 smartphone microphone-array paper notes that signalling-based network sync on
  commodity phones reaches only millisecond granularity, because of OS scheduling jitter (OBSERVED, Sur et al.).
  JOVRA's own ping over TLS in user space should be expected at the ms level (INFERRED), and must be measured.
- **Drift during capture.** Repeat bursts at join, at arm, every 60 s and at stop. Regress `θ(t)` on host time to
  get an initial drift estimate (same equations as §4.6).
- **What to keep.** Store `{tHostNs, θ, δ_min, K}` samples in the journal of each device, with no interpretation. The
  hint's prior uncertainty for §4 is σ_hint = max(δ_min / 2, 1 ms) on LAN. In the cloud room it is σ_hint = δ_min / 2,
  typically tens of ms (INFERRED).

### 3.4 What hints buy, and what they do not

- They give a **prior** that collapses the search window, from ±minutes to ±10 ms on LAN. It also resolves
  rally-rhythm ambiguity: hits come every ~1 s, so cross-correlation without a prior can land a whole hit interval
  off (§4.3, §4.10).
- They do **not** give frame accuracy:
  - capture pipelines add per-device latency between exposure and PTS (UNVERIFIED magnitude on iOS);
  - frame phase is uncontrolled, so two 30 fps cameras sample up to half a frame (16.7 ms) apart;
  - the Android frame-phase trick in Ansari et al. (injecting a longer frame) has no public iOS equivalent
    (UNVERIFIED).
- Hint-only alignment is therefore a draft state, `estimated · from capture hints`, never `reviewed`.

---

## 4. Post-hoc alignment

### 4.1 Model

Define, per source `s` and segment `k`:

```
t_match = a_{s,k} + b_s · t_src            (affine; one rate b per device clock)
```

- The reference is the primary's first segment, with `a = 0`, `b = 1`. Its origin shift to "earliest coverage" is
  applied at the end.
- An observed anchor `j` is the event's true scene time `t_e(j)` plus a modality-specific delay:

```
visual:  a_{s,k} + b_s · v_s(j) = t_e(j) + ε_v          v = exposure-centre time of the frame (rolling-shutter corrected)
audio:   a_{s,k} + b_s · u_s(j) = t_e(j) + d_s(j)/c(T) + λ_s + ε_a
         d_s(j) = ‖p_j − m_s‖  (event position to the phone's microphone), λ_s = device audio-vs-video latency
```

- `t_e(j)` are nuisance unknowns, eliminated by pairing the same event across sources.
- `λ_s` is identifiable only from events seen both visually and audibly on the same device, or from a slate
  calibration (§8.3). Until measured, `λ_s = 0` with an uncertainty term (INFERRED).
- Speed of sound: `c(T) ≈ 331.3·√(1 + T/273.15)` m/s, 343 m/s at 20 °C. Humidity raises it by about 0.1–0.6%
  (OBSERVED, Wikipedia). Across 23.77 m that is 70.5 ms at 10 °C and 67.6 ms at 35 °C, a 2.9 ms spread (computed).
  Use 343 m/s by default, and the user's temperature when given.

### 4.2 Anchor catalogue and error budget

| Anchor | How detected | Random error (1σ) | Bias risks |
|---|---|---|---|
| Racket–ball impact (audio) | Spectral-flux onset (the spec's HitDetector), refined by GCC-PHAT on a 50–200 ms window | sub-ms at 48 kHz for a clean onset (INFERRED) | Sound travel 16–96 ms (§4.4). Device latency λ. Far-court hits are ~13 dB quieter (repo research) |
| Serve contact (visual) | Frame where racket meets ball at the top of the toss | frame quantization T/√12: 9.6 ms at 30 fps, 4.8 ms at 60 fps (computed) | Rolling shutter: the row time differs from frame time by up to the readout skew. Contact itself lasts about 4–5 ms (Brody, cited by tennisplayer.net; OBSERVED secondary) |
| Bounce (visual) | Direction change / deformation of the ball | same | A far ball is ≈1.6 px at 1080p ultra-wide (repo research), so near-court bounces only |
| Net-centre slate (clap / hard ball drop at the net) | Audio and visual | sub-ms audio, frame-limited visual | Almost equal distance to all six standard placements: 50.6–56.4 ms at the club fence (§4.4). Best calibration anchor |
| Manual marker | User taps the same moment in two views | ≥ 1 frame | Human; recorded as `manual` provenance |
| Capture hint | §3 | ms (LAN), tens of ms (cloud), seconds (imports) | Pipeline latency, frame phase |

- **Sub-frame visual timing** is possible by fitting the ball's trajectory before and after contact and intersecting
  (INFERRED). It needs ball tracking, a separately benchmarked capability. Not v1.
- **Rolling-shutter correction:** `t_row = t_frameStart + (y / H)·skew + exposure / 2`. Android exposes the skew
  (OBSERVED). iOS has no public equivalent (UNVERIFIED). Treat it as error there, typically on the order of 10–30 ms
  of readout (UNVERIFIED).

### 4.3 Audio cross-correlation (GCC-PHAT)

From Knapp & Carter (1976) (OBSERVED reference; the formulation is standard):

```
G_xy(f)  = X(f) · Y*(f)
R(τ)     = IFFT[ W(f) · G_xy(f) / |G_xy(f)| ](τ)        PHAT weighting; W(f) = band mask 0.5–8 kHz
τ̂        = argmax_τ R(τ)          (positive τ̂: x lags y)
sub-sample peak (parabolic):  δ = (R[k−1] − R[k+1]) / (2·(R[k−1] − 2R[k] + R[k+1])),   τ̂ = (k + δ)/fs
```

Practice for tennis (INFERRED; §4.10 shows why):

- **Correlate per event, not per hour.** Detect onsets in each source. Pair them using the prior, meaning the hint
  plus the expected geometric lag. Then refine each pair's lag with GCC-PHAT on a short window. Landmark-fingerprint
  matching (Bryan, Mysore & Smaragdis 2012) and audio-based multi-camera sync (Shrestha et al. 2007) are the
  established methods for consumer recordings (OBSERVED references). Tennis adds two traps:
  - **Rhythm aliasing.** Rally hits are quasi-periodic, about 1.0–1.3 s apart. A window-level correlation can lock
    onto "my near hit ↔ your near hit one shot later". In the synthetic run, the strongest global GCC-PHAT peak was
    1,178 ms from the truth.
  - **Near-side dominance.** Each phone hears its own end loudly. Its loud onsets are a different set of events from
    the other phone's loud onsets.
- **Search window** = σ_prior × 4 + the maximum pairwise geometric bias. That bias is up to about ±87 ms, between
  diagonal corners, for events anywhere in the doubles court and up to 2 m behind the baselines (computed; §4.4).
- **Report the second-best peak ratio** as a confidence feature. Pairs with ambiguous peaks are dropped, not guessed.

### 4.4 Speed-of-sound bias across a court: quantified per placement

Geometry (ITF dimensions, OBSERVED):

- court 23.77 × 10.97 m;
- club-level run-back 5.48 m and side run 3.05 m;
- international 6.40 m and 3.66 m.

Phones on the fence: baselines BS (south, primary) and BN (north), corners CSW, CSE, CNW, CNE. Phone height 1.5 m,
impact height 1.0 m, c = 343 m/s. Arrival delay after the event, in ms (computed, club fence):

| Event | BS | BN | CSW | CSE | CNW | CNE |
|---|---|---|---|---|---|---|
| South baseline, centre | 16.0 | 85.3 | 29.6 | 29.6 | 88.8 | 88.8 |
| South baseline, wide (singles sideline) | 20.0 | 86.1 | 40.2 | 20.6 | 92.9 | 86.3 |
| South service T | 32.0 | 69.3 | 40.5 | 40.5 | 73.6 | 73.6 |
| **Net centre** | **50.6** | **50.6** | **56.4** | **56.4** | **56.4** | **56.4** |
| North service T | 69.3 | 32.0 | 73.6 | 73.6 | 40.5 | 40.5 |
| North baseline, centre | 85.3 | 16.0 | 88.8 | 88.8 | 29.6 | 29.6 |

At the international fence every entry grows by about 2.7–3.3 ms. The pairwise biases are unchanged to within
0.5 ms.

Pairwise bias that an *uncorrected* audio lag would add to the clock offset, `(d_A − d_B)/c` in ms (computed):

| Hit position | BS − BN | BS − CSE | BS − CNE |
|---|---|---|---|
| South baseline centre | −69.2 | −13.6 | −72.8 |
| South service T | −37.3 | −8.5 | −41.6 |
| Net centre | 0.0 | −5.8 | −5.8 |
| North service T | +37.3 | −4.3 | +28.8 |
| North baseline centre | +69.2 | −3.6 | +55.7 |

Consequences (INFERRED):

1. For opposite baselines the bias swings across about **139 ms**, 8 frames at 60 fps, depending on who hit.
   Uncorrected, a global audio lag is a mixture of two peaks. The synthetic run found them at −67 ms and +77 ms
   around the truth (§4.10).
2. **Correct with geometry.** `lag_corrected(j) = lag_measured(j) − (d_A(j) − d_B(j))/c`. Positions come from:
   - (i) the homography (Calibration) plus player or ball detection, when that capability exists;
   - (ii) role priors that need no vision. The point-event log knows the server and the deuce/ad court. The ends
     follow from changeovers. So a **serve contact** sits near a known baseline at x ≈ ±0.5–2.5 m from the centre
     mark. Rally hits alternate ends;
   - (iii) the camera position, from the calibration pose or the chosen placement slot. A 1 m position error costs
     2.9 ms (computed).
3. **Symmetric pairing.** For BS/BN with equal run-backs, the mean of the south-hit lag and the north-hit lag cancels
   the propagation term: (−69.2 + 69.2)/2 = 0. Use it as a geometry-free cross-check, not as the estimator. It
   averages drift over the window and depends on symmetric placement.
4. **Corner pairs on the same end** (BS–CSE) have small biases, ≤ 14 ms. Opposite-end corner pairs behave like
   baselines.
5. **Film audio, which is not a sync error.** With a continuous primary bed from BS, a hit by the far (north) player
   is heard about 85 ms after it is seen, even when the picture is cut to BN. ITU-R BT.1359 puts the detectability
   threshold for audio lagging video at about −125 ms and acceptability at about −185 ms (−190 in some summaries)
   (OBSERVED secondary). An 85 ms lag is inside detectability. A small sports-specific study also found higher
   acceptability thresholds for sports than for speech (OBSERVED, Ebenezer 2022). So do **not** shift the bed per
   cut. Align pictures to light time and keep the bed natural, as heard from the primary's position.
6. **Wind** adds its along-path component to sound speed. 5 m/s along 24 m changes travel time by about 1 ms
   (INFERRED). Ignore it, but keep it in the error budget.

### 4.5 Visual anchors

- **Serve contact** is the best visual anchor: high, isolated, and once per point. It can be predicted from the
  event log (which point, which server), so a reviewer jumps straight to candidates. Bounces near each camera are
  second best (INFERRED).
- **Quantization.** Each view stamps the anchor at the exposure-centre time of the frame containing it. The error is
  uniform within ±T/2, σ = T/√12. Two views at the same frame rate with independent phase disagree by up to
  1 frame even when the map is perfect (INFERRED). This is why the brief's target is "within one output frame",
  not "same frame".
- **Different frame rates** (60 vs 30 vs 240): compare times, never frame indices. This was already decided for
  Compare (spec).

### 4.6 Drift estimation by regression

- **Evidence that drift matters.** Five Galaxy Nexus phones drifted up to 22 samples (499 µs) in 60 s of audio
  recording, about **8.3 ppm** (OBSERVED, Sur et al., MobiSys 2014). Consumer-video sync work also treats
  independent time bases as drifting (OBSERVED, Bryan et al. 2012).
- **Device clocks.** iOS converts timestamps between capture clocks with measured-drift compensation
  (`CMSyncConvertTime`, OBSERVED), so *within* a phone, video and audio share one timeline. *Between* phones, each
  timeline runs on its own oscillator (INFERRED).

| Drift | Per hour | Reaches ½ frame at 60 fps (8.3 ms) | 1 frame at 60 fps | 1 frame at 30 fps |
|---|---|---|---|---|
| 5 ppm | 18 ms | 28 min | 56 min | 111 min |
| 10 ppm | 36 ms | 14 min | 28 min | 56 min |
| 20 ppm | 72 ms | 7 min | 14 min | 28 min |
| 50 ppm | 180 ms | 2.8 min | 5.6 min | 11 min |
| 300 ppm (UI sample, 18 ms/min) | 1,080 ms | 0.5 min | 0.9 min | 1.9 min |

Fit, for each non-reference device, over paired anchors `(x_j = t_src, y_j = t_match,ref)` with corrected lags:

```
y_j = a + b·x_j + r_j,          drift_ppm = (b − 1)·10^6
OLS:  b̂ = Σ(x−x̄)(y−ȳ) / Σ(x−x̄)²,   â = ȳ − b̂·x̄,   s² = Σ r_j² / (n − 2)
95% prediction half-width at x0:  t_{0.975,n−2} · s · √(1 + 1/n + (x0 − x̄)²/Sxx)
```

- **Robustness.** Use a Huber IRLS, or Theil–Sen with a RANSAC pre-pass, to discard mispaired anchors. Report
  inliers, outliers and why (INFERRED).
- **Shared slope.** All segments of one device share `b_s` (same oscillator) and have their own intercepts, unless
  the host-clock journal links them (§4.7). Fit jointly:
  `y = a_{s,k} + b_s·x`, a block design with one slope and K intercepts (INFERRED).
- **Leverage.** Prediction error grows with distance from x̄. Require anchors in the first, middle and last thirds of
  every piece, as the skill demands ("review offset and drift at start/middle/end"). Never extrapolate beyond the
  outermost anchors by more than a configured margin (e.g. 60 s). Beyond it the map is `extrapolated` and needs
  review.

### 4.7 Piecewise maps across restarts and gaps

- **Same device, journal present.** Each segment's `fileZeroHostNs` (§3.2) puts all its segments on one host clock.
  Then one affine map host → match covers every segment, and gaps are simply uncovered host intervals (INFERRED).
- **Same device, no journal** (imports, crash-recovered files without start data): each segment gets its own
  intercept with the shared slope. A segment with too few anchors inherits the slope and gets a wide intercept
  uncertainty. It stays `needsReview`.
- **Gaps** are first-class. A request for match time inside a gap returns "no coverage from this angle". A crossfade
  never bridges it, and nothing seeks into it (expansion prompt, OBSERVED).
- **Thermal frame-rate changes** at a heat-ladder rung change the frame rate, not the clock. A new segment starts
  per the spec, and its map continues on the same clock (INFERRED).

### 4.8 Residuals, confidence and review states

Per piece, store: anchor list (modality, source time, reference time, correction applied, residual, weight,
inlier), `n`, residual RMS and max, drift with 95% CI, maximum 95% prediction half-width over the covered interval,
and coverage of first/middle/last thirds.

| State | Rule (INFERRED; tune on fixtures) | Provenance |
|---|---|---|
| `fromHints` | Only capture hints, no anchors | `estimated` |
| `estimated` | ≥ 8 inlier anchors, all three thirds covered, PI95 ≤ ½ output frame everywhere used, no bimodal residuals | `estimated` |
| `needsReview` | Any rule above failed, uncorrected audio only, an ambiguous peak, `extrapolated`, or a single modality across opposite ends | `estimated` |
| `reviewed` | A person confirmed the start/middle/end checkpoints (and each restart) in a side-by-side view, possibly after ±1-frame nudges | `reviewed` (a human checked; ADR-0004) |
| `manual` | Markers only | `manual` |
| `failed` / `noOverlap` | No shared coverage, or the fit is unstable | none, angle not offered for cross-cuts |

`validated` is reserved for the **sync capability**, never for one map. It needs a benchmark of the method on real
multi-view footage against ground truth (ADR-0004, ADR-0012).

### 4.9 One-frame tolerance targets

| Output fps | 1 frame | ½ frame (internal map goal) | Visual anchor σ (1 view) |
|---|---|---|---|
| 30 | 33.3 ms | 16.7 ms | 9.6 ms |
| 60 | 16.7 ms | 8.3 ms | 4.8 ms |
| 120 | 8.3 ms | 4.2 ms | 2.4 ms |
| 240 | 4.2 ms | 2.1 ms | 1.2 ms |

- **Acceptance (brief, OBSERVED):** matched visible anchors in two reviewed views agree within one output frame
  after alignment.
- **Internal goal (INFERRED):** the map's 95% band stays ≤ ½ output frame, so nearest-frame selection at a cut picks
  the correct frame.
- **What breaks it.** An uncorrected baseline-to-baseline audio bias (69 ms) breaks either target at every frame
  rate. Ten frame-quantized anchors at 30 fps are borderline (§4.10).

### 4.10 Synthetic check (OBSERVED, scratch run, not field evidence)

Setup:

- 10 minutes, two phones at the club fence (BS and BN);
- 158 hits alternating ends, positions jittered ±4 m across and −0.5…+1.5 m behind the baseline;
- the same waveform reaches both microphones, with 1/d attenuation and white noise;
- true offset 1.2345 s, true drift 20 ppm, c = 343 m/s, fs = 48 kHz.

| Method | Result |
|---|---|
| Global GCC-PHAT on 120 s (0.5–8 kHz) | Strongest peak **1,178 ms off** (rally-rhythm alias). Local peaks at −67.3 ms and +76.9 ms from the truth, the two hitter ends, each about 0.45–0.49 of the global maximum. Only 0.12 of the maximum at the truth itself |
| Event pairing with a 35 ms-wrong capture hint, **uncorrected** lags, OLS | Offset error 0.8 ms (only because south and north hits were balanced), drift 22.8 ppm, but residual RMS **71 ms**, max 79 ms (bimodal). Must be flagged |
| Same, **geometry-corrected** with a role prior (hitter at own baseline centre) | Offset error **0.4 ms**, drift 18.6 ppm (true 20), residual RMS 4.0 ms, max 8.6 ms (residual comes from the unknown lateral position) |
| Symmetric midpoint of median south/north lags | 5.9 ms from the start-time offset, consistent with 20 ppm × the 300 s mid-window |
| Visual anchors only, frame-quantized, random phase, map error at start/mid/end | 30 fps, N=10: p95 17.2 ms, max 46.7 ms. 30 fps, N=40: p95 7.9 ms. 60 fps, N=10: p95 8.7 ms. 60 fps, N=40: p95 3.8 ms, max 10.6 ms |

Readings (INFERRED from the run):

- a prior is required;
- geometry correction turns an unusable audio fit into a sub-frame one;
- at 30 fps, aim for 30–40 visual anchors, or combine modalities;
- the simulation omits rolling shutter, device latency λ, reverberation and crowd noise, so real numbers will be
  worse.

### 4.11 Recommended alignment pipeline (INFERRED)

1. Load the SourceManifest: hashes, decoded PTS index, segments, journal hints.
2. Build the prior from capture hints, or creation time for imports, with σ.
3. Detect audio onsets per source. Pair them within the prior window, using the expected geometric lag per role
   prior.
4. Refine each pair's lag with GCC-PHAT. Apply the geometric correction.
5. Detect or suggest visual anchors: serve contacts from the event log, near-camera bounces, slates.
6. Fit robust piecewise affine maps with a shared slope per device.
7. Compute residuals, PI95 and coverage. Assign the state (§4.8).
8. Review UI: start/middle/end and each restart side by side, with ±1-frame nudge, "Synced at serve 3", and the
   residual list. The user's review moves the state to `reviewed`.
9. Emit SyncMap revision N+1. Any change invalidates edit plans bound to revision N (starter contract, OBSERVED).

---

## 5. Normalization

### 5.1 Two proxy classes (INFERRED design, consistent with the skills)

| | Analysis proxy | Render proxy |
|---|---|---|
| Purpose | Scrubbing, onsets, pose, anchors | Input to the deterministic assembler/renderer |
| Timestamps | **Original PTS preserved** (VFR allowed); short GOP for backward stepping (spec) | **CFR** at the project render rate, zero start, timebase ≤ 1 ms |
| Geometry | Rotation applied or recorded; low resolution | Rotation baked in, display matrix removed, square pixels, identical dimensions across sources |
| Colour | Whatever is fastest to analyse; record the transform | SDR BT.709 8-bit 4:2:0 for H.264 output (or an HDR master path later) |
| Audio | Mono 48 kHz analysis track | 48 kHz, zero start, 1–2 channels or none |
| Mapping | Identity on PTS | **Explicit table** original PTS ↔ proxy frame, stored beside the proxy and hashed |

### 5.2 VFR → CFR with an original-PTS table

- **Why.** Phone video can be VFR. In the scratch fixture, ffprobe reported `avg_frame_rate == r_frame_rate == 30/1`
  for a file with irregular timestamps (OBSERVED). The editor already warns that equal average and nominal FPS do
  not qualify a source (`PIPELINE.md:44`, OBSERVED).
- **ffmpeg semantics.**
  - `-fps_mode cfr`: "frames will be duplicated and dropped to achieve exactly the requested constant frame rate".
  - `passthrough`: keeps the demuxer timestamps.
  - The `fps` filter has a `round` option, default `near` (OBSERVED, ffmpeg docs).
- **Observed selection rule** (scratch run, FFmpeg 9.0.1, embedded frame IDs):
  - Round each input PTS to the nearest output tick, with **ties going up**.
  - Output slot `k` shows the last input frame whose rounded tick ≤ `k`.
  - This predicted 184/184 slots at 30 fps, 368/368 at 60 fps and 153/153 at 25 fps.
  - "Nearest frame" matched only 137/184, 274/368 and 106/153. Ties-even or ties-down failed at 25 fps.
- **Recommendation (INFERRED).**
  - Never *assume* the resampler's rule. Either produce the table by construction (iOS: an `AVAssetReader` →
    `AVAssetWriter` loop that chooses each output slot's source frame explicitly and writes exact CFR PTS), or
    compute it with the observed rule.
  - **Verify it** on every pinned FFmpeg version with the embedded-ID fixture (§8.2).
  - Store the table run-length encoded: `(proxyFrameStart, count, originalPtsValue, timescale)`.
  - Analysis and sync always use **original PTS**, never the proxy slot time. Slot time can be up to half an output
    frame away from capture, plus source jitter.
- **Timebase.** Write render proxies with track timescale `lcm(fps_num, 1000)`: 3000 for 24, 30, 60 and 120 fps;
  30000 for 30000/1001. This mirrors the founder editor's own output setting (`production_preview.py:491`, OBSERVED).
  On iOS set `AVAssetWriterInput.mediaTimeScale` (OBSERVED API; it cannot be set after writing starts).

### 5.3 Rotation

- iPhone files carry rotation in the track matrix (repo research, OBSERVED). ffprobe exposes it as side data, as in
  the scratch file's `rotation=90`.
- ffmpeg applies the display rotation at the filtering stage when transcoding with `-autorotate`, the default
  (OBSERVED docs). The scratch proxy came out 240×320 with no rotation side data.
- Rule (INFERRED): rotate pixels exactly once in the render proxy and store `rotationApplied` in the mapping
  sidecar. A portrait angle in a landscape film is an explicit framing operation in the edit plan, never an implicit
  crop or pad (editor: "cropping is never implicit", `production_preview.py:329`, OBSERVED).

### 5.4 HDR → SDR

- iPhone HDR video is HLG/Dolby Vision. The import pipeline keeps HDR in originals (spec, OBSERVED).
- Tools:
  - ffmpeg: `tonemap` works only on linear light and needs `zscale` (libzimg) around it, e.g.
    `zscale=transfer=linear,tonemap=…,zscale=transfer=bt709`. `libplacebo` offers peak detection and tone mapping
    (OBSERVED docs).
  - Android: Media3 Transformer's `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL`, Android 10+ (OBSERVED).
  - Apple: WWDC20 "Export HDR media in your app with AVFoundation" covers HDR export (OBSERVED). The exact SDR
    conversion path through `AVVideoColorPropertiesKey` was not confirmed here (UNVERIFIED).
- Rules (INFERRED):
  - tone-map all angles of one film with the **same** method and parameters;
  - record the method and version in proxy provenance;
  - review mixed HDR/SDR angles for consistency;
  - never use a grade as analysis evidence (storycraft skill, OBSERVED);
  - cloud (ffmpeg) and device (VideoToolbox) tone maps differ, so a film's look depends on the renderer. Pin it per
    film revision.

### 5.5 Differing frame rates

- **Output rate.** The default is the primary's capture rate. Never above a source's rate by duplication without
  saying so (sibling `film-engine.md` §2.1).
- **60 → 30** keeps frames nearest the output instants by original PTS. **30 → 60** duplicates frames and labels the
  angle "30 fps source". No optical-flow interpolation by default, and when used it is labelled (INFERRED;
  storycraft rule).
- **120/240 fps practice clips:** sync uses real-time PTS. Slow motion is a labelled replay operation, not the
  source clock (INFERRED; the Photos slo-mo time-mapping details are UNVERIFIED).
- **NTSC rates** (30000/1001) are valid inputs. Normalize a film's angles to one rate. The founder editor's handoff
  `fps` is a float compared within 0.001 (`production_handoff.py:48`; `production_preview.py:326`, OBSERVED), so
  prefer integer project rates where possible.

### 5.6 Audio

- **The match clock follows the primary.** The primary's audio bed needs no resampling. A secondary's audio is used
  only for sync analysis, unless a user deliberately selects it as a source. Then its drift `b_s` is applied by
  resampling at rate `b_s` (INFERRED).
- Resample to 48 kHz once and record it. Never silently replace a missing audio track: "no audio" is a source
  state, and silence in a film is an explicit choice (editor rule, OBSERVED).

---

## 6. Mapping onto the founder's editor (`garnet-remotion`, read-only)

### 6.1 Its constraints (OBSERVED, `production_preview.py` and `production_handoff.py`)

| Constraint | Line(s) |
|---|---|
| ≤ 128 segments, ≤ 32 distinct sources, each ≤ 4 h (`MAX_SOURCE_FRAMES = 120·4·3600`) | 33–35, 313 |
| Container suffix .mp4/.mov/.m4v/.mkv/.webm; regular file; `O_NOFOLLOW`; FIFO rejected | 100–117 |
| Exactly one video stream, ≤ 1 audio stream | 205 |
| `avg_frame_rate == r_frame_rate`, 1–120 fps, measured `nb_frames`, **video `time_base` ≤ 1/1000**, duration within ½ frame of frames/fps | 218 |
| Even width and height ≤ 8192 | 220 |
| `start_time` 0 (±1 µs), SAR 1:1, **no rotation side data** | 222 |
| Audio start 0, 1–2 channels | 232 |
| Every decoded frame within ½ tick of `index/fps`; durations ⌊ or ⌈ ticks-per-frame ⌉; no duplicates; count = `nb_frames` | 239–277 |
| Any ffprobe stderr output rejects the source; decoded-clock probe timeout 600 s | 288–292 |
| Source FPS = planned FPS within 0.001; aspect = planned (16:9, 9:16, 1:1, 4:5); all sources share dimensions and exact FPS | 326–333; handoff 50 |
| Planned boundaries are integer ms, contiguous, ≤ 14,400,000 ms, ≤ 500 segments in a handoff | handoff 45–71 |
| `ms → frame` uses Python `round(Fraction)`, which is **round-half-even** (`round(Fraction(3,2)) = round(Fraction(5,2)) = 2`, OBSERVED locally) | 334–337 |
| Audio per segment: `"source"` (that segment's own source window) or `"silent"`, concatenated with the video segment by segment | 340, 402–412 |
| Output: `-fps_mode passthrough`, `enc_time_base 1/fps`, track timescale `lcm(fps_num, 1000)`, libx264 CRF 23 yuv420p, AAC 192k 48 kHz stereo; output audio within 25 ms of the planned duration; empty-stderr full decode | 408, 489–513 |

### 6.2 How JOVRA render proxies satisfy it (INFERRED)

| Editor requirement | Render-proxy rule |
|---|---|
| CFR, `time_base` ≤ 1 ms | CFR at the project rate, track timescale `lcm(fps_num, 1000)` |
| Clean decoded clock | Write exact PTS `k/fps`, no B-frame timestamp irregularity; verify with the same check before mapping |
| Zero start, no rotation, SAR 1:1 | Rotation baked; container edit lists flattened; audio and video start at 0 |
| Same dimensions and FPS across sources | One project canvas (e.g. 1920×1080 at 30 or 60). A portrait or odd-shaped angle is a *declared* framing op |
| ≤ 4 h, 600 s probe timeout | **Per-keeper excerpt proxies** (e.g. one per point plus margin) instead of whole-match proxies. A 60-min 60 fps source is 216,000 frames to decode in one probe, and whether that fits in 600 s on the render host is UNVERIFIED |
| Integer `sourceStartMs`, half-even rounding | Emit `sourceStartMs = ⌊k·1000/fps + ½⌋` for the intended proxy frame `k`. Locally, `round(ms·fps/1000) == k` held for every tested `k` at 24, 25, 30, 50, 60, 120 and 240 fps (OBSERVED). This avoids the ties at 30 fps (ms ≡ 50 mod 100) and 60 fps (ms ≡ 25 mod 50) where half-even would pick the other frame |
| SHA-256 per mapped file | Hash of the **proxy**. The JOVRA manifest links proxy hash → original hash, mapping-table hash and normalization version |
| Audio per segment from the same source | **Gap.** Studio needs one continuous primary bed across angle cuts (expansion prompt; sibling `film-engine.md` §3.7, §4.3). Options below |

Audio options (INFERRED; decision needed):

- (1) Use the editor as a **picture assembler**: every segment `audioMode: "silent"`. Then a new, separately verified
  JOVRA step muxes the primary bed, cut through the SyncMap to the film's match interval, and re-runs full decode and
  A/V duration checks.
- (2) Build per-segment proxies that already carry the primary bed's audio for that window. This works with the
  editor unchanged, but multiplies derived files.
- (3) A new JOVRA composition or assembler with a bed graph, in a new folder.

Recommendation: (1) for the S2 two-view slice, so the editor's custody and verification are reused as they are, and
(3) as the long-term engine. The sibling film-engine research reaches the same conclusion about replacing the
per-segment audio concat.

### 6.3 SyncMap → editor media map (INFERRED)

For each EDL segment (source, match window), the adapter:

- (a) inverts the SyncMap piece to the source time window and checks it is inside coverage;
- (b) maps it to render-proxy frames through the PTS table;
- (c) emits `{segmentId, localPath (proxy, project-relative), sourceStartMs (round-trip-safe), sha256 (proxy),
  audioMode}`.

The editor binds this to the exact plan bytes with `planSha256` (OBSERVED). Any SyncMap revision forces a new plan
and a new map. Imported approvals never transfer (expansion prompt, OBSERVED).

### 6.4 Scratch check against copies of the editor's code (OBSERVED, synthetic media)

| Input | Editor result |
|---|---|
| CFR 30 fps, 120 frames, **track timescale 600** (iPhone-style; ffmpeg trac #2958 documents iPhone's 600 timescale in 2013, so currency on new iPhones is UNVERIFIED) | **Rejected**: "Source must have consistent constant-frame-rate metadata; normalize VFR explicitly first". 1/600 s > 1/1000 s fails the timebase test at line 218 |
| VFR (jittered PTS) + `rotation=90`, timescale 600 | Rejected (same message) |
| Normalized proxy: autorotate, `fps=30`, `-fps_mode cfr`, timescale 3000 | **Accepted**. Decoded clock passed for 120/120 frames, max PTS deviation 0.0 ms |

So even CFR native iPhone files will likely need at least a remux to a finer timescale before the editor accepts them
(INFERRED). Normalization is not optional.

---

## 7. SyncMap contract sketch (proposal; reconcile with `spec/` before use)

```json
{
  "schemaVersion": "jovra.sync-map/0-proposal",
  "projectId": "proj-…",
  "revision": 3,
  "sample": false,
  "matchClock": {"unit": "us", "origin": "earliestCoverage", "referenceSourceId": "cam-bs", "referenceSegmentId": "seg-0"},
  "speedOfSound": {"mps": 343.0, "temperatureC": null, "method": "default-20C"},
  "sources": [{
    "sourceId": "cam-bn", "sourceManifestRevision": 2, "originalSha256": "…64 hex…",
    "placement": {"slot": "oppositeBaseline", "courtXYZm": [0.0, 17.365, 1.5], "from": "slot-default | calibration"},
    "audioLatencyUs": {"value": null, "status": "unmeasured"},
    "pieces": [{
      "segmentId": "seg-0",
      "sourceCoverage": {"start": {"value": 0, "timescale": 600}, "end": {"value": 2160000, "timescale": 600}},
      "matchCoverageUs": [1234500, 3601306500],
      "transform": {"kind": "affine", "offsetUs": 1234500, "rate": {"num": 1000020, "den": 1000000}},
      "fit": {"method": "huber-wls/1", "nInliers": 37, "nOutliers": 2, "residualRmsUs": 3900, "residualMaxUs": 8600,
              "driftPpm": 18.6, "driftPpmCi95": [15.1, 22.0], "pi95MaxHalfWidthUs": 6200,
              "thirdsCovered": [true, true, true], "extrapolatedUs": 0},
      "anchors": [{"id": "a-serve-14", "kind": "serveContact", "modality": "visual", "sourceTimeUs": 512345,
                   "referenceMatchUs": 1746880, "correctionUs": 0, "residualUs": -2100, "inlier": true, "reviewed": true}],
      "state": "reviewed", "reviewedAt": "2026-…", "checkpoints": ["start", "middle", "end"]
    }],
    "gaps": [{"matchUs": [1803000000, 1844000000], "reason": "restart"}]
  }],
  "provenance": {"capability": "studio.multiCameraSync", "method": "jovra-sync", "methodVersion": "0.1", "status": "reviewed"}
}
```

Notes (INFERRED):

- Rates are rationals, so Swift, Kotlin and Python agree byte for byte.
- One rounding function for time → frame: `frame = ⌊(t − t0)·fps + ½⌋` in exact rational arithmetic. This is the time
  analogue of ADR-0011, and differs on purpose from Python's default half-even.
- Conformance fixtures are shared across platforms (ADR-0001).
- Proposed glossary terms (not added here): **Match clock**, **SyncMap**, **Anchor**, **Render proxy**,
  **PTS table**.

---

## 8. Test-fixture strategy

### 8.1 Synthetic multi-angle generator (proposal: a repo script beside the ADR-0012 sample generator)

Inputs: a scene file and a camera rig file.

- **Scene:** ITF court geometry; an event list (hits, bounces, serve contacts, slates) with positions and *light*
  times, derived from a rules-coherent point-event fixture where possible.
- **Per camera:**
  - placement slot or xyz;
  - start offset and **drift ppm** (realistic 1–50, stress 300);
  - fps (24, 25, 30, 30000/1001, 60, 120, 240) and **frame phase**;
  - VFR jitter σ, stalls and dropped frames;
  - rolling-shutter skew;
  - rotation flag; HDR flag (10-bit HLG tags);
  - audio present, absent or muted spans; audio sample-rate offset; device audio latency λ;
  - mic gain and noise;
  - restarts and gaps with journal hints, or without them (import mode);
  - a capture-hint error model (LAN or cloud).

Outputs:

- One video per camera.
  - Picture: simple perspective court plus figures and a ball.
  - Audio: the **same** impulse waveform per event reaching each camera at `t_e + d/c + λ`, attenuated 1/d, plus
    noise.
- A **coded** variant with a per-frame machine-readable strip (camera ID, frame ID, exact capture ns) and a
  **clean** variant without it. Algorithms run on clean; verification reads coded.
- A ground-truth manifest: true maps per piece, event times per modality per camera, and per-frame capture times.
- Every artifact says "Sample video (synthetic)" (ADR-0012).

### 8.2 Normalization fixtures (embedded-ID method, already proven in scratch)

Encode the source frame index in luma: low part in the left half, high part in the right half, written in limited
range. Read it back from the Y plane without range conversion. Then:

- the normalizer's emitted PTS table must match the decoded IDs 100%;
- it must pass the editor-equivalent checks (§6.1);
- rotation must be applied once (output dimensions swapped, no side data);
- the HDR flag must be tone-mapped with the declared method.

### 8.3 Acceptance tests (each must be able to fail)

| ID | Case | Pass criterion |
|---|---|---|
| S1 | Two views, offset only, 30/30 fps | Map error ≤ ½ frame at start/mid/end; state `estimated` |
| S2 | 20 ppm drift over 60 min | Drift within ±3 ppm; end error ≤ ½ frame |
| S3 | **Mutation:** shift camera B by +1 frame after fitting | The anchor-agreement check fails |
| S4 | **Mutation:** apply a correct map but select frames with half-even rounding at a tie | The frame-selection test fails |
| S5 | Opposite baselines, audio only, no geometry correction | State `needsReview` (bimodal residuals detected), never auto-approved |
| S6 | Same with geometry correction plus role priors | ≤ ½ frame at 60 fps; residual RMS reported |
| S7 | Rally-rhythm alias: no prior | The algorithm refuses ("needs capture hint or manual marker") rather than locking an alias |
| S8 | Restart with a 41 s gap, journal present | One host-clock map; queries in the gap return no coverage; no crossfade across it |
| S9 | Same, journal absent (import) | Per-segment intercepts with a shared slope; low-anchor segment `needsReview` |
| S10 | Camera C has no audio | Visual or manual anchors only; with < 8 anchors → `needsReview` |
| S11 | Mixed 60/30/240 fps | All comparisons by time; the 30→60 angle labelled |
| S12 | VFR + rotation + HDR source → render proxy | Editor-equivalent checks pass; PTS table matches IDs 100% |
| S13 | Six placements | The geometry function reproduces the §4.4 tables within 0.1 ms |
| S14 | No shared coverage between two angles | State `noOverlap`; the angle is not offered for cross-cuts |
| S15 | Cross-platform | Swift, Kotlin and Python produce byte-identical SyncMap JSON on the fixture set |
| S16 | SyncMap revision bump | Edit plans bound to the old revision are rejected as stale (starter contract) |

### 8.4 Real-footage protocol (after the old match; the two-view stage)

1. A single old match validates import, normalization and one-angle films only. It cannot validate sync (source
   assessment, OBSERVED).
2. **Two phones**, baselines or one baseline plus one corner, locked fps, both with microphones.
   - Before play, at mid-match and at the end: a **net-centre slate** (a clap, plus one hard ball drop at the net
     strap) visible to both.
   - Optional calibration: an LED flash and click 1 m from each phone, to measure λ per device model.
3. Two reviewers independently mark ≥ 20 serve contacts and near bounces in each view.
4. Compute anchor agreement. Report: pass rate within one output frame, residual distribution, drift, failures and
   why. This is `reviewed` evidence for the method on that footage, not `validated`.
5. **Six devices:** endurance, thermal, storage, disconnects and host loss on physical phones (§S3 stage of the
   brief). Simulators and emulators prove nothing about camera timing (expansion prompt, OBSERVED).

---

## 9. Risks and open questions

- **iOS capture latency** between exposure and PTS, and its variation per device model: UNVERIFIED. Needs the LED
  fixture.
- **Rolling-shutter readout** on iPhone is not exposed publicly (UNVERIFIED). Near-frame-edge anchors carry extra
  error.
- **CameraX start-PTS access** for Android capture hints: UNVERIFIED. It may need an own Camera2 pipeline.
- **Wi-Fi Aware iPhone↔Android interop:** UNVERIFIED. Spike before promising courts without Wi-Fi to mixed groups.
- **Venue Wi-Fi client isolation** makes LAN discovery fail often (INFERRED). The QR IP fallback and independent
  recording must feel normal.
- **Six-phone thermal behaviour** with stills and heartbeats on: needs physical tests.
- **Cloud-room message accounting** for fan-out under Supabase quotas: UNVERIFIED.
- **Reverberation and fences** (chain-link resonance) may smear onsets (UNVERIFIED). Tune on real courts.
- **Match-clock origin and signed offsets** need a contract decision (§1 and §7).

---

## Sources

Repository and founder editor (read-only, OBSERVED):

- `/Users/IDC2.5/jv/docs/handoff/studio/CLAUDE-STUDIO-EXPANSION-PROMPT.md`,
  `CLAUDE-STUDIO-BRIDGE-PROMPT.md`, `ENGINE-BOUNDARY.md`
- `/Users/IDC2.5/jv/design-reference/studio/brief/implementation-states.md`, `backend-media-design.md`,
  `source-assessment.md`, `feasibility-findings.json`
- `/Users/IDC2.5/jv/.claude/skills/jovra-media-ingest-sync/SKILL.md` and the other five `jovra-*` skills;
  `/Users/IDC2.5/jv/.claude/skills/jovra-edit-plan/references/contract.md`
- `/Users/IDC2.5/jv/tools/studio-plan/scripts/validate_edit_plan.py`
- `/Users/IDC2.5/jv/docs/adr/0001…0013` (notably 0002, 0004, 0010, 0011, 0012);
  `/Users/IDC2.5/jv/docs/spec/ios-v1-spec.md`;
  `/Users/IDC2.5/jv/spec/schemas/common.schema.json`, `session.schema.json`; `/Users/IDC2.5/jv/GLOSSARY.md`
- `/Users/IDC2.5/jv/docs/research/technical-feasibility.md`;
  `/Users/IDC2.5/jv/docs/research/studio/film-engine.md` (sibling)
- `/Users/IDC2.5/Desktop/you-link-x/garnet-remotion/PIPELINE.md`, `production_preview.py`,
  `production_handoff.py` (copied to scratch for the §6.4 check; the original untouched)

Apple (OBSERVED):

- MultipeerConnectivity: https://developer.apple.com/documentation/multipeerconnectivity
- MCSession: https://developer.apple.com/documentation/multipeerconnectivity/mcsession
- kMCSessionMaximumNumberOfPeers:
  https://developer.apple.com/documentation/multipeerconnectivity/kmcsessionmaximumnumberofpeers
- Building a custom peer-to-peer protocol (TicTacToe sample):
  https://developer.apple.com/documentation/network/building-a-custom-peer-to-peer-protocol
- NWProtocolWebSocket: https://developer.apple.com/documentation/network/nwprotocolwebsocket
- TN3179 Understanding local network privacy:
  https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Wi-Fi Aware framework: https://developer.apple.com/documentation/wifiaware
- NEHotspotConfiguration: https://developer.apple.com/documentation/networkextension/nehotspotconfiguration
- AVCaptureSession.synchronizationClock:
  https://developer.apple.com/documentation/avfoundation/avcapturesession/synchronizationclock
- AVCaptureSession.masterClock: https://developer.apple.com/documentation/avfoundation/avcapturesession/masterclock
- fileOutput(_:didStartRecordingTo:startPTS:from:):
  https://developer.apple.com/documentation/avfoundation/avcapturefileoutputrecordingdelegate/fileoutput(_:didstartrecordingto:startpts:from:)
- AVAssetWriter.startSession(atSourceTime:):
  https://developer.apple.com/documentation/avfoundation/avassetwriter/startsession(atsourcetime:)
- AVAssetWriterInput.mediaTimeScale:
  https://developer.apple.com/documentation/avfoundation/avassetwriterinput/mediatimescale
- CMClockGetHostTimeClock: https://developer.apple.com/documentation/coremedia/cmclockgethosttimeclock()
- CMSyncConvertTime: https://developer.apple.com/documentation/coremedia/cmsyncconverttime(_:from:to:)
- mach_absolute_time: https://developer.apple.com/documentation/kernel/1462446-mach_absolute_time
- mach_continuous_time: https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time
- AVCaptureDevice.systemPressureState:
  https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.property
- ProcessInfo.thermalState: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property
- WWDC20 10010 Export HDR media in your app with AVFoundation: https://developer.apple.com/videos/play/wwdc2020/10010/

Android (OBSERVED):

- CaptureResult (SENSOR_TIMESTAMP, SENSOR_ROLLING_SHUTTER_SKEW, SENSOR_FRAME_DURATION):
  https://developer.android.com/reference/android/hardware/camera2/CaptureResult
- CameraCharacteristics (SENSOR_INFO_TIMESTAMP_SOURCE):
  https://developer.android.com/reference/android/hardware/camera2/CameraCharacteristics
- SystemClock: https://developer.android.com/reference/android/os/SystemClock
- NsdManager: https://developer.android.com/reference/android/net/nsd/NsdManager
- WifiManager.startLocalOnlyHotspot: https://developer.android.com/reference/android/net/wifi/WifiManager
- PowerManager (thermal status, headroom): https://developer.android.com/reference/android/os/PowerManager
- Local network permission: https://developer.android.com/privacy-and-security/local-network-permission
- CameraX releases (CameraUseInconsistentTimebaseQuirk): https://developer.android.com/jetpack/androidx/releases/camera
- CameraCaptureSessionInterop:
  https://developer.android.com/reference/androidx/camera/camera2/interop/CameraCaptureSessionInterop
- Media3 Transformer tone mapping: https://developer.android.com/media/media3/transformer/tone-mapping

Supabase (OBSERVED, checked 2026-10-07):

- Realtime limits: https://supabase.com/docs/guides/realtime/limits
- Realtime authorization: https://supabase.com/docs/guides/realtime/authorization
- Anonymous sign-ins: https://supabase.com/docs/guides/auth/auth-anonymous

FFmpeg (OBSERVED; local FFmpeg 9.0.1 used for the scratch runs):

- ffmpeg options (-fps_mode, -autorotate, -display_rotation): https://ffmpeg.org/ffmpeg.html
- Filters (fps, tonemap, zscale, libplacebo): https://ffmpeg.org/ffmpeg-filters.html
- iPhone 600 timescale (trac #2958): https://fftrac-bg.ffmpeg.org/ticket/2958

Standards, papers and references:

- RFC 5905, NTPv4: https://www.rfc-editor.org/rfc/rfc5905
- Knapp & Carter, "The generalized correlation method for estimation of time delay", IEEE TASSP 24(4), 1976:
  https://doi.org/10.1109/TASSP.1976.1162830
- Ansari, Wadhwa, Garg, Chen, "Wireless Software Synchronization of Multiple Distributed Cameras", ICCP 2019:
  https://arxiv.org/abs/1812.09366 (also https://research.google/pubs/wireless-software-synchronization-of-multiple-distributed-cameras/)
- Sur, Wei, Zhang, "Autodirective Audio Capturing Through a Synchronized Smartphone Array", MobiSys 2014:
  https://syrex.cse.sc.edu/wp-content/uploads/2022/04/Dia_MobiSys14.pdf
- Bryan, Mysore, Smaragdis, "Clustering and synchronizing multi-camera video via landmark cross-correlation",
  ICASSP 2012: https://ccrma.stanford.edu/~njb/research/icassp2012-multicamera.pdf
- Shrestha, Barbieri, Weda, "Synchronization of multi-camera video recordings based on audio", ACM MM 2007:
  https://dblp.org/pid/17/22
- Ebenezer, "A subjective study of the perceptual acceptability of audio-video desynchronization in sports videos",
  2022: https://arxiv.org/abs/2212.01686
- ITU-R BT.1359 thresholds (secondary summaries): https://www.tvtechnology.com/opinions/av-synchronization-how-bad-is-bad,
  https://www.forasoft.com/learn/audio-for-video/articles-audio/lip-sync-itu-r-bt-1359-tolerance-windows
- Speed of sound: https://en.wikipedia.org/wiki/Speed_of_sound
- ITF court size and run-off: https://www.itftennis.com/media/9026/court-size-org-requirements.pdf;
  https://tennis.com.au/learn/courts-and-surfaces/dimensions
- Racket–ball contact time (Brody, via tennisplayer.net):
  https://old.tennisplayer.net/members/biomechanics/paul_hamori/10000_frames/contact
- Wi-Fi Aware press coverage (iOS 26, Android interop claim):
  https://9to5mac.com/2025/06/20/ios-26-to-let-third-party-apps-build-their-own-airdrop-alternative/,
  https://developer.espressif.com/blog/2026/08/wifi-aware-esp-to-iphone/
