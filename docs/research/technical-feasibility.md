# Technical feasibility: capture, review, analysis, archive and the Android port

Status: synthesized reference, 2026-10-07. Inputs: `raw/ios-tech.md` (iOS capture and analysis, including a local
crash experiment), `raw/video-analysis-apps.md` (scrubbing, compare, voice-over, pose UX and Apple APIs),
`raw/drive-android-tech.md` (Google Drive archive and Android stack), `raw/equipment-stringing.md` (acoustic string-bed
estimate), `raw/gap-finder.md` (platform extras), plus ADR-0001…0005 and `CLAUDE.md`.

**Labels.** **OBSERVED** = in a cited primary source (Apple / Google / Android documentation, SDK headers, papers) or
a local experiment. **INFERRED** = engineering reasoning or arithmetic. **UNVERIFIED** = plausible, not confirmed;
each one is listed as a device or API spike. No part of this document was run on an iPhone or a Pixel; the only
executed evidence is the macOS AVAssetWriter crash experiment, the Swift rounding run and the SoundAnalysis label
listing done by the raw researchers.

**Capability-registry statuses** follow ADR-0004: `manual` (user-entered, always allowed), `estimated` (passed the
minimum gate for a stated configuration band; shown with a badge and range), `validated` (passed the strict gate;
method still documented), `disabled` (built but hidden or behind an Experimental toggle until its gate passes),
`unsupported` (deliberately not built). "Initial status" below is what the registry should say when iOS v1 ships
**before** any benchmark has run.

---

## 0. Summary

| # | Capability | Single-phone feasibility | Main risk | Validation gate (minimum for `estimated`) | Initial registry status |
|---|---|---|---|---|---|
| 1 | Durable capture (1–2 h) | High, with engineering | Heat, interruptions, storage | Soak test: ≤3 s media lost per crash, 0 unrecoverable sessions | n/a (core) — must pass before release |
| 2 | Import (Photos, Files, Drive provider) | High | Temp-file lifetime, HDR/rotation | Fixture suite of codecs/fps/orientations | n/a (core) |
| 3 | Replay, scrub, frame step | High | Backward stepping on long-GOP HEVC | Seek/step latency on oldest supported device | n/a (core) |
| 4 | Clip / highlight export with burned-in score | High | Re-encode time, heat | Export matches source timecodes ±1 frame | n/a (core) |
| 5 | Audio hit detection (own court) | High near, medium far | Neighbour courts, wind, soft shots | P ≥ 0.95, R ≥ 0.90, MAE ≤ 10 ms on held-out sessions | `disabled` |
| 6 | Rally / point segmentation | High for trimming, medium for boundaries | Feeds, lets, warm-up | ≥99% of hits kept; boundary F1 ≥ 0.90 at ±1 s | `manual` (bookmarks) + auto `disabled` |
| 7 | Ball trajectory | Low from behind baseline; good side-on | Ball 1.6–3 px far court, blur | Recall ≥ 0.9 near, ≥ 0.7 far; ≤5% identity swaps | `disabled` (match); `disabled` (side-on) |
| 8 | Court calibration + camera-moved | High near half, coarse far half | Taps in wrong space, fence drift | Line RMSE ≤ 3 px; ≤ 0.10 m near-half ground error | `manual` (4-tap) |
| 9 | Bounce / shot placement | Manual: high. From video: medium near, low far | Resolution 0.2–0.4 m/px far | Median ≤ 0.3 m near, ≤ 0.8 m far | `manual`; video-derived `disabled` |
| 10 | Serve speed | Low–medium (±10% best case) | Drag/spin conversion, timing | MAPE ≤ 7% vs radar, 90% within ±10% | `disabled` |
| 11 | 2D pose / Stroke Lab overlays | Near player and side-on clips only | L/R swaps at contact, far player 4% of frame | Joint keypoint agreement on labelled frames; swap rate | `disabled` (overlay); manual key moments `manual` |
| 12 | Stroke classification (FH/BH/serve/volley) | Medium-high near, low far | Lefties, occlusion, run-arounds | Accuracy ≥ 0.90 near (≥300 strokes/class, ≥20% lefties) | `disabled`; manual tags `manual` |
| 13 | Google Drive archive | High | OAuth config, 308 in background, quota | 10 falsifiable archive checks (§13.8) | n/a (feature; "awaiting configuration" until OAuth set up) |
| 14 | Android equivalents | High for capture/replay/export; same ML limits | Fragmentation, thermals, 16 KB pages | Same gates per platform + conformance suite | — |
| 15 | String-bed acoustic estimate | Feasible as **relative** change only | Wrong vibration mode, hybrids, iOS audio regressions | Bench gate (§15.5) + patent FTO | `unsupported` in v1 (P2 candidate) |
| — | Line calls / officiating | **Not feasible** (far baseline 0.2–0.4 m per pixel vs 5 cm lines) | — | none | `unsupported` (never build) |
| — | Spin RPM, 3D biomechanics, injury claims | Not supported by single-camera evidence | — | none | `unsupported` |

**Three platform decisions to make before P0 code (see §16):** deployment target (ADR-0005 says iOS 17; the raw notes
argue for 18 or 26), capture orientation (screens 5–6 are portrait but full-court capture needs landscape), and the
microphone default (screen 20 shows "Off", which disables every audio-based capability).

---

## 1. Durable capture (iOS)

**Approach.** A `RecordingEngine` protocol with two implementations (raw/ios-tech.md §0, §1):

- **Option A (P0): `AVCaptureMovieFileOutput` with `movieFragmentInterval ≈ 2 s`**, set **before** `startRecording`
  (default is 10 s; changing it mid-recording is allowed but "will not affect" the file currently being written, so
  it only applies from the next file; an extra fragment is also cut at 2 GB; Apple suggests ≥10 s for best performance
  on external storage, so measure the 2 s cost in the soak test). OBSERVED (Apple docs, iOS 26.5 SDK headers;
  re-verified 2026-10-07). There is **no** short-first-fragment property on the movie output;
  `initialMovieFragmentInterval` exists only on `AVAssetWriter` (iOS 17+; default `kCMTimeInvalid`; no effect unless
  the writer's own `movieFragmentInterval` is set, which itself defaults to **off**; cannot be set after writing
  starts). OBSERVED. *Contradiction resolved:*
  raw/gap-finder.md suggested "about 1 s for the first fragment" on the movie output; the SDK headers in
  raw/ios-tech.md win — use a uniform ~2 s interval on Option A.
- **Option B (P1 candidate): `AVAssetWriter` writing fMP4/CMAF segments** (`AVAssetWriter(contentType:)` with no URL,
  `outputFileTypeProfile = .mpeg4AppleHLS`, `preferredOutputSegmentInterval` 2–6 s, delegate
  `assetWriter(_:didOutputSegmentData:segmentType:segmentReport:)`). Loss bounded to the in-flight segment, no repair
  needed, segments can be backed up while recording, exact "saved through mm:ss". Cost: the app owns A/V sync,
  back-pressure (`alwaysDiscardsLateVideoFrames` defaults true), priming and interruption offsets. OBSERVED APIs.
- **Session = ordered list of recording segments plus gaps**, journalled with atomic temp-then-rename writes
  (ADR-0002). Every interruption ends the current file; it is never fatal to the session (INFERRED).

**Local evidence (OBSERVED, macOS 26.6.2, writer killed after 9 s without `finishWriting`):** fragmented `.mov` kept
7.10 s (214 frames) playable; joined fMP4 segments kept 7.90 s video + 7.956 s audio. A torn last segment reported
9.00 s duration but only 255 frames decoded, so **validate recovery by decoding to the end, not by reading
`duration`**. This used AVAssetWriter on macOS; equivalence for `AVCaptureMovieFileOutput` on iOS is UNVERIFIED.

**Interruptions (OBSERVED reasons; JOVRA behaviour INFERRED).** `AVCaptureSession.wasInterruptedNotification` reasons:
`videoDeviceNotAvailableInBackground` (incl. side button), `audioDeviceInUseByAnotherClient` (calls, alarms),
`videoDeviceInUseByAnotherClient`, `videoDeviceNotAvailableWithMultipleForegroundApps` (iPad multitasking),
`videoDeviceNotAvailableDueToSystemPressure`, `sensitiveContentMitigationActivated`. The delegate
`fileOutput(_:didFinishRecordingTo:from:error:)` is called for every recording request that ends normally or with an
error, but **not** if the process crashes, is jetsam-killed or loses power — exactly the cases crash safety is for, so
recovery must scan the journal and fragmented files on disk at next launch, never wait for the delegate (INFERRED from
the header guarantee; device behaviour UNVERIFIED until the soak test). Playability: `error == nil` → success;
otherwise read `error.userInfo[AVErrorRecordingSuccessfullyFinishedKey]` (an NSNumber BOOL meaning "playable"; the
`maxRecordedDuration`, `maxRecordedFileSize` and `minFreeDiskSpaceLimit` stops all arrive with an error yet may be
playable). Apple's own AVCam sample treats any error as failure; do not copy that. `didStartRecording` may not be called
at all.
On resume: "Recording stopped at 41:12 — Resume?" and auto-resume only if opted in. `runtimeErrorNotification` with
`.mediaServicesWereReset` → rebuild the session.

**Heat ladder (INFERRED from OBSERVED APIs).** Observe `AVCaptureDevice.systemPressureState` (nominal/fair/serious/
critical/shutdown; factors include `batteryStress` = shutdown within ~30 s) and `ProcessInfo.thermalState`.
`fair` → stop live helpers, dim preview; `serious` → preview off ("court mode"), show "Phone warming"; `critical` →
30 fps via `activeVideoMinFrameDuration` (whether this keeps the same file or raises `.mediaChanged` is UNVERIFIED);
`shutdown` → system interrupts, segment saved. Log every rung into session metadata so analysis knows fps changed.
Apple's ambient operating range is 0–35 °C (OBSERVED, support.apple.com/118431); summer courts exceed it.

**Storage and power.** Free space from `volumeAvailableCapacityForImportantUsageKey` (a required-reason API; declare it
in `PrivacyInfo.xcprivacy`). Pre-flight `estimatedBytes × 1.2`; `minFreeDiskSpaceLimit ≈ 1.5 GB`; re-project remaining
minutes every 30 s from the slope of `recordedFileSize`. Keep the screen awake only while recording
(`isIdleTimerDisabled`); "court mode" = black overlay + lower brightness (persists until device lock; use the window
scene's screen, `UIScreen.main` is deprecated in iOS 26). Originals never in `tmp/` or `Caches`.

**File sizes (OBSERVED secondary, iOS Settings per-minute figures via videoproc.com 2024-02-01; verify on device):**
1080p30 HEVC 60 MB/min; **1080p60 HEVC 90 MB/min (5.4 GB/h)**; 1080p120 170; 4K30 170; 4K60 400 (24 GB/h);
1080p60 H.264 175. Estimate method: read `outputSettings(for:)` bitrate if present (UNVERIFIED that it is), else
table; after 30 s replace with the measured slope ±15%.

**Format and lens.** Use the **physical** `.builtInUltraWideCamera` (not virtual multi-cam devices, which switch
lenses on their own); lock fps with equal min/max frame durations; turn off `isAutoVideoFrameRateEnabled` (iOS 18+;
when on, setting durations throws); stabilization **off** on a mount (it warps geometry); keep geometric distortion
correction on; cap `activeMaxExposureDuration` (~1/500 s, needs tuning) for ball-friendly frames; sRGB colour space.
Framing math from ITF dimensions: seeing both near doubles corners from the 5.48 m club run-back needs ≈90° HFOV; the
wide lens has ≈69°, ultra-wide ≈108° → **ultra-wide effectively required** (INFERRED). At 1080p ultra-wide the far
baseline ball is ≈1.6 px and one pixel covers ≈0.41 m of depth; 4K halves that.

**Orientation.** `AVCaptureDevice.RotationCoordinator` (iOS 17+); the movie output records rotation in the track
matrix. Lock the angle at record start. **Screens 5 and 6 need landscape variants** (INFERRED; a full-court 16:9 frame
needs a landscape phone).

**Timing alignment.** `fileOutput(_:didStartRecordingTo:startPTS:from:)` (iOS 18.2+) gives the start PTS on the
session `synchronizationClock`; map taps (Mark point, manual score) to media time from it. Before 18.2, sample
`recordedDuration` (≈1 frame error, UNVERIFIED).

**Pause.** `pauseRecording()` / `resumeRecording()` / `isRecordingPaused` are iOS 18.0+ (macOS 10.7+), unavailable on
visionOS and watchOS; on iOS 17, "pause" = close segment + new file. A format or device change stops the recording
even while paused, and `didPause` is not guaranteed if the recording stops (OBSERVED, SDK headers).

**Failure modes.** Phone call/Siri takes the mic and interrupts the whole session (exact ringing-phase behaviour
UNVERIFIED); side-button lock backgrounds the app; Control Center; low storage; thermal shutdown; front-camera
default (a SwingVision regression, raw/swingvision.md); focus hunting (SwingVision fixed refocusing on iPhone 16+ in
11.9.56) → lock focus/exposure/white balance after framing.

**Validation gate (raw/ios-tech.md §1.13).** Per engine, on a minimum-spec and a current device, outdoors in sun and
indoors: 3 × 2-hour recordings at 1080p60 (and 4K60 where storage allows); 20 forced terminations; 10 interruptions of
each kind (call, alarm, background, lock, Control Center, other camera app); thermal soak with Xcode Device
Conditions "serious"; a 2 GB-free run. Pass: ≤3 s media lost per crash; 0 unrecoverable sessions; journal and video
agree within one frame; gap per interruption ≤ 1.5 s + interruption length; battery drain per mode recorded.

**Competitor evidence this targets.** SwingVision 11.9.47–11.9.67 release notes fix system-pressure crashes,
"interrupted recordings being saved without any playable video", recordings ending early and crashes on camera
interruptions (OBSERVED); reliability (crash, recording failure, stuck upload, cloud playback) is mentioned in ≈37–44%
of 289 ≤2★ reviews of five apps depending on the coder, tied with money as the top complaint group
(raw/review-mining.md; competitive-analysis Verification log V2).

---

## 2. Import

**Approach (OBSERVED APIs).** `PhotosPicker` / `PHPickerViewController` run out of process and need **no photo-library
authorization**; pass `preferredItemEncoding: .current` to avoid transcoding; `loadFileRepresentation`'s temp copy is
deleted when the handler returns, so move it inside the handler. `UIDocumentPickerViewController` reaches Google Drive
through the Files app with **no Google scope** (Drive in Files since 2017). Photos Slo-mo: request
`PHVideoRequestOptionsVersion.original` to get the raw high-fps timeline (UNVERIFIED on device). Respect
`preferredTransform`; never auto-crop; allow manual 90° rotation (Onform 2021–2022 complaints).

**Reliability.** High. **Failure modes:** HDR/HLG sources (convert only on export), 50 fps footage under 50 Hz light
(SwingVision rejected it, raw/community.md F13), 30 fps imports (SwingVision blocked them in 2024), variable frame
rate, iCloud-only originals, duplicate imports. SwingVision's iOS import must stay foreground with the screen unlocked
(OBSERVED import guide) — JOVRA should copy and then process asynchronously.

**Gate.** Fixture suite (HEVC/H.264, 24/25/30/50/60/120/240 fps, portrait/landscape, HDR, GoPro, Android MP4)
imports, plays and seeks frame-accurately; duplicates detected by content hash.

**Screen 20 copy fix.** "Photos · Selected photos" is not a state PhotosPicker produces; show "Not needed for import"
and "Add-only" if saving to Photos is enabled (INFERRED).

---

## 3. Replay, scrubbing and frame stepping

**Approach.** `AVPlayer.seek(to:toleranceBefore:toleranceAfter:)` with `.zero` for sample accuracy (extra decode
cost; a new seek cancels the previous one); QA1820 chase-time pattern (one seek in flight, remember the latest
target); during a drag use ~0.1–0.5 s tolerance, on release `.zero`. `AVPlayerItem.step(byCount:)` for ±1 frame
(`canStepForward/Backward` fixed once ready). `defaultRate` (iOS 16+) for 0.25×/0.5×, check `canPlaySlowForward`.
Frame-accurate thumbnails via `AVAssetImageGenerator` with `.zero` tolerance only for "Contact" freeze frames.
`preferredScreenEdgesDeferringSystemGestures` on analysis screens. All OBSERVED APIs.

**UX spec (raw/video-analysis-apps.md §5.1; INFERRED design from OBSERVED failures):** three tiers everywhere (#10,
#12, #13, #14): (1) event timeline with point/stroke markers; (2) a frame-quantized jog strip ≥44 pt tall, ≥16 pt from
the timeline, above the transport row, never on the bottom edge, engages on touch-down, lifting a finger never changes
mode, vertical drag-down for single-frame precision; (3) ±1-frame buttons with hold-to-repeat. Readout
`f 412 / 1,440 · 1.717 s · 240 fps`, tappable, with zero/origin reset. VoiceOver adjustable element steps one frame;
iPad keys ←/→, ⇧←/⇧→, space.

**Rate arithmetic (INFERRED).** A 240 fps clip at 0.25× shows 60 fps; a 60 fps clip at 0.25× shows 15 fps. Recommend
120/240 fps for serve/stroke practice clips.

**Failure modes (OBSERVED in competitor reviews).** Bottom-edge scrubber triggers the app switcher (Onform 2023,
SlowMo 2018/2023); absolute bar imprecise for long 240 fps clips (Onform 2022); coarse and fine controls too close;
jog disengages on lift and flips into drawing (Onform 2022). Long-GOP HEVC makes backward steps decode from the
previous key frame (INFERRED); the movie output's key-frame interval may not be settable (UNVERIFIED).

**Gate.** On the oldest supported device: forward/backward step latency and seek latency on 60 and 240 fps HEVC; if
backward step > ~100 ms, generate a short-GOP **analysis proxy** for lab clips (keep the original untouched).

---

## 4. Clip, highlight and voice-over export

**Approach (OBSERVED APIs).**
- Plain clip: `AVAssetExportSession` + `AVAssetExportPresetPassthrough` + `timeRange`; async `export(to:as:isolation:)`
  is back-deployed to iOS 13 with the iOS 26 SDK; progress via `states(updateInterval:)` (iOS 18+), else poll
  `progress`. Passthrough cuts may rely on edit lists that some players ignore (UNVERIFIED) — use re-encode for clips
  shared outside the app if privacy-sensitive.
- Rally-only / highlight reel: `AVMutableComposition` inserting each point's time range; copy `preferredTransform`.
- Burned-in scoreboard: `AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:in:)` with a `CATextLayer`
  driven by the **derived** score at each point (never typed). Rules: begin at `AVCoreAnimationBeginTimeAtZero`,
  `isRemovedOnCompletion = false`, no UIView-owned layers, **export-only, not AVPlayer**. For live replay overlays use
  `AVSynchronizedLayer` or SwiftUI. API churn: `AVMutableVideoComposition` deprecated in iOS 26 in favour of
  `AVVideoComposition(configuration:)`; the tool's init is deprecated in iOS 27 — branch on `#available`.
- Save to Photos without a copy: `.addOnly` + `PHAssetResourceCreationOptions.shouldMoveFile = true`.
- Share: `ShareLink` + `FileRepresentation`.
- Long exports: `BGContinuedProcessingTask` (iOS 26, user-initiated, system Live Activity progress, must report
  progress). `configureForResumableExport()` is iOS 27 only and absent from the 26.5 SDK (OBSERVED grep).
- **Voice-over**: ReplayKit's `RPScreenRecorder` **cannot record AVPlayer video** (OBSERVED, Apple class overview), so
  do not plan on screen-recording a review session. Record a voice-over as an **event timeline** (mic audio +
  playhead/rate/pause/step/zoom/drawing events). Preview it live with `AVSynchronizedLayer` over the `AVPlayerLayer`
  (Apple's documented route for layers timed to an `AVPlayerItem`). Export it either with `AVMutableComposition` + the
  Core Animation tool (one valid route) or with a custom `AVVideoCompositing` compositor / Metal or Core Image frames
  written by `AVAssetWriter` (equally valid; INFERRED). The same layer tree can serve preview and export. Caveat:
  `AVPlayerItem.videoComposition` works only with file-based media, not HLS (OBSERVED) — relevant if replays are ever
  streamed. No quotas (raw/video-analysis-apps.md §5.4).

**Reliability.** High. **Failure modes:** heat during long re-encodes (run after recording, ideally on power);
SwingVision export complaints (dark/over-compressed after an update, 4K dropping to 30 fps, blurry overlays) show
what to regression-test.

**Gate.** Exported clip start/end within ±1 frame of source timecodes; overlay score at every point equals the fold;
correcting a point re-renders overlays (CLAUDE.md hard rule 4).

---

## 5. Audio hit detection (racket–ball impacts)

**Approach (INFERRED, from onset-detection practice; APIs OBSERVED).** Decode with `AVAssetReader` to mono 48 kHz
Float32; Hann window (`vDSP.window`), `vDSP.FFT`; spectral flux over ~1–8 kHz with log compression (or HFC); adaptive
threshold (moving median + δ·MAD); 150 ms refractory; refine to ~1 ms on a high-pass envelope; classify onset as
hit / bounce / other with band ratios, centroid and decay time or a small Core ML model (`MLSoundClassifier`).
**Correct for sound travel** using player distance from the homography: ≈18 ms near baseline, ≈51 ms at the net,
**≈86 ms far baseline** (≈5 frames at 60 fps). The built-in SoundAnalysis classifier includes a `playing_tennis` label
(minimum window 0.5 s; OBSERVED local run) — useful only as a coarse play/idle prior.

**Literature (none is a phone on a fence):** broadcast tennis atomic events F1 92.39% (IBM, via search summary);
padel broadcast CRNN F1 92% with a 250 ms collar, misses mostly slices, false alarms from frame hits, stomps, glass
(Decorte et al. CVPRW 2024, OBSERVED); table tennis P 91% / R 73%; wrist audio P 85% / R 75%, fused with IMU P 97.3% /
R 93.9% (OBSERVED).

**Expected reliability (UNVERIFIED).** Near-court hits high recall; far-court ≈13 dB quieter (inverse square, 29.4 m
vs 6.3 m) → lower recall; **neighbouring courts are the dominant false-positive source**; soft slices, drop shots and
volleys missed. Mitigations: visual corroboration (wrist-speed peak at onset), optional stereo/ambisonic direction of
arrival (`multichannelAudioMode`, iOS 18+; benefit UNVERIFIED), "noisy side" exclusion tap. Keep
`configuresApplicationAudioSessionToMixWithOthers = false` so court music does not contaminate detection. Whether
`isWindNoiseRemovalEnabled` dulls transients is UNVERIFIED — A/B before enabling.

**Microphone policy (contradiction resolved).** Screen 20 shows "Microphone · Optional · Off"; raw/ios-tech.md notes
that "Off" disables hit, rally and contact-sync analysis; raw/community.md reports a competitor where disabling the
mic silently produced *no recording*; raw/gap-finder.md proposes "audio analyzed then discarded". Resolution: the mic
stays **optional and never blocks video** (CLAUDE.md hard rule 3); the setting states the consequence inline; offer
"Use audio for detection, don't keep it in exports" (strip audio on export/share by default for match sessions). Audio
privacy is an observed community concern (raw/community.md §10).

**Gate.** ≥10 courts/conditions held out (day, night, indoor, wind, adjacent play); own-court P ≥ 0.95, R ≥ 0.90,
timing MAE ≤ 10 ms after travel correction → `estimated`; ≥ 0.98 / 0.95 → `validated`. Report near and far ends
separately.

**Initial status:** `disabled` (Experimental toggle for footage collection).

---

## 6. Rally / point segmentation and dead-time removal

**Approach (INFERRED).** Rally = hits with gaps < ~3 s (typical rally gaps 1–2 s); gap > ~5 s starts a new point;
pre-roll ≈1.5–2 s and post-roll ≈1.5–2.5 s, adjustable per session and per clip (TennisCut users complained of clips
starting early and ending 1–2 s short; SwingVision users of clips cut too soon; Smashpoint pads 2 s past point end).
Rule facts: ≤25 s between points, 90 s changeovers, 120 s set breaks (Rule 29a). Effective playing time is ~20–30% of
match time on clay and 10–15% on fast courts (Fernandez et al. 2006, OBSERVED), which bounds the achievable trim.
**Point winner is not inferable from audio**; manual scoring stays the source of truth.

**Works without ML from day one:** manual "Mark point" bookmarks (live, hardware button, or review) produce the same
rally-only composition; automatic detection only improves the candidate list.

**Reliability.** High for dead-time removal (missing one hit rarely loses a rally); moderate for point boundaries
(serve faults, lets, feeds between points, warm-up rallies). Broadcast audio reached ~80% P/R for boundaries with
umpire and crowd cues amateur audio lacks (OBSERVED via summary).

**Failure modes.** Ball fed between points scored as a point (SwingVision review 2024-08); dropped rallies (SwingVision
2025-05: 1–3 rallies dropped per video); far-court-only rallies; music; doubles four-player chatter.

**Gate.** ≥99% of labelled own-court hits inside kept clips; boundary F1 ≥ 0.90 within ±1.0 s; ≥60% dead time removed.
raw/gap-finder.md's product-level gate (≥95% of real points covered, ≤10% false segments, ≥10 sessions at ≥3 venues)
is compatible and should be reported alongside. Below gate → label "Auto-trim (review)".

**Initial status:** `manual` (bookmark-based trimming ships); automatic segmentation `disabled`.

**UX invariant (INFERRED from OBSERVED complaints).** Collapsed gaps remain visible as tappable "+0:42" chips; the full
untrimmed video is always one tap away (CLAUDE-BUILD-PROMPT; SwingVision 2025-05 review had no way to watch gaps).

---

## 7. Ball trajectory

**Approach (OBSERVED API facts).** `VNDetectTrajectoriesRequest` (iOS 14+) is **stateful** (one instance over
timestamped consecutive buffers), uses frame differencing so it needs a **fixed camera and static background**,
fits `y = ax² + bx + c` in normalized image space, needs `trajectoryLength ≥ 5`, splits at every bounce or
frame exit, size filter `objectMinimum/MaximumNormalizedRadius`, `targetFrameTime` for real-time budgets; Apple notes a
tennis ball may need 1080p. Offline via `VNVideoProcessor` / Swift `VideoProcessor` (iOS 18+).

**Fit (INFERRED).** Behind-baseline match footage: paths are near-vertical in the image (y(x) degenerates), the far
ball is 1.6–3 px and blurs into a streak, players/rackets/flags/LED flicker create difference noise, bounces fragment
tracks. Side-on serve/stroke practice at 120–240 fps (ball crossing the frame close to camera): plausible.
Match tracking needs a **custom TrackNet-class heatmap detector** (3 stacked 640×360 frames; 99.7%/97.3% P/R on one
broadcast match but **95.3% / 75.7%** in 10-video cross-validation — OBSERVED) converted to Core ML with a
Kalman/physics fit, trained on a labelled amateur fence-camera dataset (does not exist yet). Compute: gate vision to
windows around audio hits (−0.6 s/+0.4 s) ≈5× less work for a 90-min match (≈60,000 vs 324,000 frames) (INFERRED).

**Gate.** Per-shot detection recall ≥ 0.9 near half, ≥ 0.7 far half on held-out sessions; ≤5% identity swaps. Until
then no ball trails in match replay, or "Experimental" only.

**Initial status:** `disabled` (both match and side-on). Competitor note: SwingVision ships "Ball Tracer" (11.9.60);
JOVRA should not imitate it until gated.

---

## 8. Court calibration, line snapping and camera-moved detection

**Approach (INFERRED, standard projective geometry; ITF dimensions OBSERVED).** Court coordinates in metres with origin
at the near-left doubles corner: doubles corners (0,0) (10.97,0) (10.97,23.77) (0,23.77); singles sidelines x = 1.37 and
9.60; net y = 11.885; service lines y = 5.485 and 18.285; centre service line x = 5.485 from y = 5.485 to 18.285; net
height 0.914 m centre / 1.07 m posts. Four tapped corners → homography H by normalized DLT (Hartley normalization, SVD
via Accelerate) or least squares + RANSAC with extra points. Convert taps to **video pixels**
(`captureDevicePointConverted(fromLayerPoint:)` then rotation), not view points; magnifier loupe. H maps only points
**on the ground plane** (feet, bounces, shadows). Camera pose from K⁻¹H for 3D checks (net-top projection).

**Built-in check (a check that can fail):** project the untapped lines (service lines, centre line, singles
sidelines) and measure distance to detected line pixels; accept RMSE ≤ 3 px at 1080p, else ask to re-tap.

**Line snapping.** `VNDetectContoursRequest` around each tap at full resolution: set `detectsDarkOnLight = false`
for white lines and raise `maximumImageDimension` (default 512 erases thin far lines); RANSAC lines; snap to their
intersection. `VNDetectRectanglesRequest` cannot find a court in strong perspective (quadrature tolerance ≤45°).
Fully automatic court finding works on broadcast footage (Farin et al. 2004) but is UNVERIFIED on amateur courts.

**Camera moved.** `VNTrackHomographicImageRegistrationRequest` (iOS 17+) or translational registration against the
calibration reference, masked to stable regions, every N s; drift > ~2 px → "calibration stale from mm:ss". (Toach
1.9.2 fixed losing court lock after a bump — OBSERVED in its notes — so this is a real field problem.)

**Failure modes.** Pickleball lines on tennis courts (common in the US), worn/clay tape lines, shadows, night glare,
players on lines, zoom/format changes (bind calibration to lens, format and zoom), wind on the fence.

**Gates.** Calibration: reprojection RMSE ≤ 3 px on held-out lines; on 20 courts, median error of 30 ground-truth
points ≤ 0.10 m on the near half, far half reported separately. Snapping: within 2 px of hand labels in ≥95% of 200
frames over ≥3 surfaces. Camera moved: detect a 1° nudge in ≥99% of trials, < 1 false alarm per hour of wind-only
footage.

**Initial status:** 4-tap calibration `manual`; auto-snap and camera-moved `disabled`.

---

## 9. Bounce location and shot placement (screen 11)

**Manual path (ships first).** During review the user taps the bounce on the top-down court diagram (or on the frame,
projected through H⁻¹). Provenance `manual`. Screen 11's "Estimated from calibrated video" copy must change to match
provenance.

**Video path (INFERRED).** Bounce = sign change of vertical image velocity or a trajectory break, optionally
confirmed by an audio bounce onset; project through H⁻¹. Error budget: pixel footprint (§1), ±8 ms time quantization at
60 fps (±0.12–0.2 m at 15–25 m/s), blur-streak centre. Expect ±0.2–0.3 m near half; ±0.5–1 m far half on ultra-wide
1080p (about half that at 4K). **Never make in/out calls**; use Deep/Mid/Short bins with uncertainty-aware edges and a
"Needs review" state near edges (matches screen 11's legend).

**Gate.** Median error ≤ 0.3 m near half and ≤ 0.8 m far half against hand-marked bounce frames or a second higher
camera; bin accuracy ≥ 90% near half, else hide far-half bins.

**Initial status:** manual placement `manual`; video-derived placement `disabled` (depends on §7).

---

## 10. Serve speed (screen 12 "104 mph · Estimated")

**Method (INFERRED).** Average horizontal speed = projected contact-to-bounce ground distance ÷ (bounce time − contact
time); contact time from the travel-corrected audio onset, bounce time from video; optional drag model to a peak /
radar-like number (spin-dependent, largest error).

**Error budget, near-end server, ultra-wide 1080p (INFERRED).** Bounce location ±2 px × 0.27 m/px ≈ ±0.54 m over
~18.3 m (±3%); bounce timing ±8.3 ms over ~0.47 s (±1.8%); contact time ±0.4%; contact position ±1.6% → ≈±4% for
average speed; drag/spin conversion adds ±5–8% (UNVERIFIED) → **≈±10% overall at best**. Side-on practice: a ±1 m
depth offset at 8 m is ±12% unless scaled.

**Competitor reality (OBSERVED).** SwingVision defines speed as average along the flight, ~10% below radar (FAQ);
community tests found ~6% error on in-bounds serves but ~42% on net-cord serves vs Pocket Radar (YouTube 2025-06);
recreational players see 120–140 mph serves (a running joke on r/10s); near-side player reads 4–5 mph faster.
*Contradiction resolved:* Tennis.com (2022) said ~20% below peak; the current vendor FAQ (~10%) is the newer primary
statement and wins for describing SwingVision's own definition.

**Gate.** ≥200 serves vs a radar gun across ≥10 players: MAPE ≤ 7% and 90% within ±10% → `estimated` with a ± range
and an explicit definition ("average flight speed"); otherwise show only relative comparisons ("faster than your
average"). Outlier flag for net-cord serves.

**Initial status:** `disabled`. The 104 mph on screen 12 is sample copy and must carry the "Sample" label.

---

## 11. 2D pose and the Stroke Lab (screen 13)

**APIs (OBSERVED).** `VNDetectHumanBodyPoseRequest` (iOS 14+): 19 joints with confidence, origin bottom-left, several
people; Apple advises subject height ≥ ⅓ of the image and a region of interest. Swift `DetectHumanBodyPoseRequest`
(iOS 18+) adds `detectsHands`. `VNDetectHumanBodyPose3DRequest` (iOS 17+): most prominent person only, 17 joints or
none, metres relative to root, `bodyHeight` assumed 1.8 m without LiDAR. **No racket, ball or hand-on-racket points.**

**Fit (INFERRED).** Behind-baseline: near player ≈23% of frame height on ultra-wide (more with a per-player ROI on
full-resolution frames; 4K helps); far player ≈4% — below Apple's guidance. Side-on practice clips: good. 3D pose:
qualitative only, no degree numbers.

**Evidence that 2D pose fails where tennis cares (OBSERVED).** ServeFix 2.1 (2026-10-07) fixed limbs drawn on the wrong
side at serve contact; SevenSix scored an unrecognized swing 81 (2024). Every tennis app with a racket path claims a
custom model (unvalidated).

**Stroke Lab design rules (raw/video-analysis-apps.md §5.5; INFERRED).** Draw only joints above a confidence
threshold, never interpolate fake joints; enforce temporal L/R consistency with a one-tap "swap sides"; label "2D pose
estimate"; angles are on-screen 2D, no decimals, no norms; "Review" statuses instead of scores; named key moments
(Ready, Unit turn, Racket drop, Contact, Finish; serve: Toss release, Trophy, Racket drop, Contact, Landing), each
user-correctable; capture purpose chosen in setup (match vs side-on technique).

**Compare sync (screen 14).** Each clip stores `syncEventTime` + `captureFPS`; shared playhead τ relative to the sync
event; never sync by frame index (60 vs 240 fps). States Align (independent jogs, amber "Unlocked") → Lock ("Synced at
Contact", one jog) → Nudge ±1 frame without unlocking (Dartfish/Kinovea models, OBSERVED docs). Auto-suggest the
contact frame from the audio transient and/or a wrist-speed peak, always "Suggested · confirm" (gate: frame error at
60/240 fps on labelled clips, UNVERIFIED). Overlay mode with opacity, mirror and a "needs similar camera position"
warning. Drawing: explicit sticky Draw mode in which the jog still works; `PKCanvasView.drawingPolicy = .pencilOnly`
on iPad with Pencil; every shape editable with handles, attached to a frame range, autosaved.

**Gate.** Keypoint agreement vs hand labels on held-out side-on clips; L/R swap rate at contact < a threshold to be set
from the first benchmark; per-end availability for match footage. 3D angles: ±10° vs a two-camera or marker reference
on 50 swings before any number appears.

**Initial status:** manual key moments, manual compare sync and drawing → `manual`; pose overlay `disabled`; 3D
`unsupported` for v1.

---

## 12. Stroke classification

**Approach (INFERRED).** Per player via court side from H⁻¹ (near/far; left/right in doubles); at the audio-derived
contact frame: dominant wrist on the dominant side of the shoulder/hip midline → forehand; non-dominant → backhand;
wrists close together on the non-dominant side → two-handed backhand; wrist above head → serve/overhead (rally
context separates them); inside the service line with short swing → volley; far player facing camera → mirror. Later a
Create ML action classifier (`MLActionClassifier`, macOS; Apple asks ≥50 videos per action plus a negative class;
horizontal-flip augmentation valid for FH/BH because a mirrored right-hander forehand is a left-hander forehand).
**Handedness for both players is a hard input** (PB Vision's right-hand assumption has been "planned" to fix since
Dec 2024, OBSERVED; SwingVision FH/BH filters assumed right-handers, 2025-04 review).

**Gate.** Confusion matrix on ≥300 labelled strokes per class per court end with ≥20% left-handers, held-out players:
near end ≥0.90 → `estimated`, ≥0.95 → `validated`; far end below 0.80 → "Unknown", not a guess.

**Initial status:** `disabled`; manual stroke tags `manual`.

---

## 13. Google Drive archive (founder requirement)

**Scope (OBSERVED).** Request only `https://www.googleapis.com/auth/drive.file`: non-sensitive, recommended; covers
files the app creates and files the user opens/picks with the app. A project **in production** using only
`drive.file` (plus basic profile scopes) gets no "unverified app" screen and no 100-new-user cap — both apply only to
sensitive/restricted scopes (support.google.com/cloud/answer/7454865). In **Testing** status the project is still
limited to 100 test users listed on the consent screen, whatever the scopes, and test users' consent and refresh
tokens for `drive.file` expire 7 days after consent (only the name/email/profile subset is exempt; answer/15549945) →
publish to "In production" before any real user connects. Brand verification is **optional** for non-sensitive scopes
(answer/13463073): it is needed only to show JOVRA's name and logo on the consent screen (homepage + privacy policy on a
verified domain; logo 120×120, ≤1 MB). Recommended for a consumer app, not a launch blocker (INFERRED). All Google API
use must also follow the Google API Services User Data Policy incl. Limited Use: no Drive-derived data to AI services or
model training without explicit, prominent consent (raw/drive-android-tech.md A2). Do **not** request `drive`, `drive.readonly`, `drive.metadata*` (restricted → annual security
assessment) or `drive.appdata` (hidden, deleted with the app, can't be shared, and can't be combined with the Picker).
Per IDC doctrine: homepage/policy on a **path** of `islanddevcrew.com` (e.g. `/jovra`), support address
`hello@islanddevcrew.com`, and do not submit until those URLs resolve (raw/drive-android-tech.md A2).

**iOS auth.** GoogleSignIn-iOS **10.0.0** (2026-09-04; AppAuth 3.0.0 / GTMAppAuth 6.0.0; **iOS 15+**; 9.2.0 if older
OS needed) for connect/refresh/disconnect + App Check (App Attest; debug provider in Simulator/CI). It cannot add
custom authorization parameters, so the **mobile Google Picker** (import from Drive) uses AppAuth directly with
`scope=drive.file`, `trigger_onepick=true`, `prompt=consent`, `mimetypes`, `allow_multiple`, then reads
`picked_file_ids`. Redirect: reversed client ID (Google's docs conflict on custom schemes; the 2026-03-22 iOS SDK
guide still uses it — monitor). Revocation removes **every** scope granted to the project across clients, so
"Disconnect" on iPhone also invalidates Android. Refresh tokens die after 6 months unused, on revoke, or beyond 100
per account per client → handle `invalid_grant` as "Needs reconnect". All OBSERVED.

**Upload protocol (OBSERVED, Drive v3 guide 2026-09-03).** `POST …/upload/drive/v3/files?uploadType=resumable` with
`X-Upload-Content-Type/Length` and metadata (`name`, `parents`, `appProperties`, optional pre-generated `id`) → 200 +
`Location` session URI (valid ~1 week). Prefer one PUT; chunks must be multiples of **256 KiB** (262,144 bytes) except
the final chunk. Status query: empty
PUT with `Content-Range: bytes */total` → 200/201 done; **308 Resume Incomplete** + `Range: bytes=0-N` = N+1 bytes
received, resume at offset N+1 (e.g. `bytes=0-42` → next byte offset 43; no Range header = nothing stored, restart at
0); 404 = session expired. 5xx/403 rate/429 → exponential backoff; other 4xx → new session; **403
`storageQuotaExceeded` → terminal `quota_blocked`, no retry loop** (INFERRED). Pre-generated IDs from
`files.generateIds` make retries return 409 instead of duplicates. Google's samples PUT to the session URI without an
Authorization header (token expiry mid-upload may not matter — UNVERIFIED, test >90-min upload).

**Persisted state machine (INFERRED):** `queued → hashing → session_created(sessionUri, driveFileId, createdAt) →
uploading(lastConfirmedOffset) → verifying → backed_up | failed(reason) | needs_reconnect | quota_blocked`, written
before any network I/O. *Contradiction resolved:* raw/drive-android-tech.md suggests SQLite/SwiftData (iOS) and Room
(Android) for this queue; **ADR-0002 (JSON document store, SQLite rejected for v1) wins** — persist each queue item as
an atomic JSON journal next to the session folder; revisit only via a new ADR.

**Background uploads (iOS).** Background `URLSession` uploads survive app exit **only from files**; redirects are always
followed; a 308 "Resume Incomplete" inside a background session is undocumented (UNVERIFIED). Prefer Google's
`GTMSessionUploadFetcher` (gtm-session-fetcher 5.3.1; via GoogleAPIClientForREST 5.4.0) with `useBackgroundSession`,
which writes temporary chunk files and speaks the `X-Goog-Upload-*` dialect (used by Google's own client but not
documented on the Drive guide — low but non-zero risk). Wi-Fi only = `allowsExpensiveNetworkAccess = false`,
`allowsConstrainedNetworkAccess = false`, `waitsForConnectivity = true`. iOS 17 resumable-upload APIs need a server
implementing the IETF draft; Drive does not document it — don't use. Never upload while recording.

**Verification (OBSERVED fields; rule INFERRED).** "Backed up" only when Drive `size` = local size **and** `md5Checksum`
= local MD5 (plus `sha256Checksum` when present); hashes computed in one streaming pass at finalize (CryptoKit
`Insecure.MD5`, `SHA256`). Optional ranged GET of first/last 1 MiB as a restore probe.

**Archive layout.** Folder via `files.create` (folder MIME, pre-generated id), re-discovered after reinstall by
`appProperties has { key='jovraRole' and value='archiveRoot' }` (limits: 30 private props per app per file, 124 bytes
per key+value). `JOVRA/2026/2026-10-06 Jon vs Alex/original.mp4`, `session.jovra.json` (the same versioned JSON as
ADR-0002), optional `clips/`.

**Quota and cost (OBSERVED).** New Cloud projects since 2026-05-01: 1,000,000 units/min/project, 325,000/min/user,
**1 TB/day egress** before charges, billing details "later in 2026" with 90 days' notice. Uploads are cheap; restores
are the exposure (≈312 full 3.2 GB restores/day across all users) → restore via the Drive app's Files provider where
possible. Free Google accounts hold **15 GB shared** with Gmail/Photos: at ~90 MB/min a 54-min session is ≈4.9 GB, so
≈3 sessions fit. **Space Saver** (rally-only passthrough copy ≈1.7 GB for the sample match; raw/gap-finder.md #9)
makes the archive workable. Preflight with `about.get?fields=storageQuota(...)` (documented as allowed with
`drive.file` — *contradiction resolved*: raw/gap-finder.md marked this UNVERIFIED; the Drive reference in
raw/drive-android-tech.md wins as OBSERVED, still include it in the spike).

**Sharing (open).** Drive permissions support `expirationTime` for user/group grants (max one year). Whether
`drive.file` can create permissions on app-created folders is UNVERIFIED (API spike) — gates the P1 Share Pack.

### 13.8 Archive acceptance checks (falsifiable; raw/drive-android-tech.md A15)

1. Kill at 10/50/99% of a 3 GB upload; relaunch resumes from Range+1 with no duplicate (pre-generated id).
2. Upload >90 min: data PUTs succeed after the access token expires, or refresh happens cleanly.
3. iOS background session: observe how a 308 status-query response is delivered.
4. Simulated 404 session: `files.get` checked before a new session.
5. <1 GB free account: `storageQuotaExceeded` → `quota_blocked`, no retry storm.
6. Revoke at myaccount.google.com: iOS `invalid_grant` and Android `hasResolution`/401 → "Needs reconnect".
7. Create on iOS, list from Android in one Cloud project (per-project vs per-client grants are UNVERIFIED).
8. Picker import on both platforms: `picked_file_ids` resolve and MD5 matches.
9. Reinstall → archive folder found by `appProperties`.
10. "Wi-Fi only": zero cellular bytes.

---

## 14. Android equivalents (port after iOS gates; ADR-0001)

| Concern | Android approach (OBSERVED APIs unless marked) | Notes |
|---|---|---|
| SDK levels | `compileSdk 37`, `targetSdk 36`, `minSdk 29` (INFERRED) | Play has required **target API 36** for new apps and updates since 2026-08-31 (extension to 2026-11-01 on request; Wear OS/Automotive need 35+, TV/XR 34+; existing apps need 35+ to stay visible to new users on newer OS versions). The original "target 35" is out of date. Target 36: edge-to-edge mandatory, predictive back on, orientation/resizability ignored at sw ≥ 600 dp → recording/replay must handle any orientation on tablets/foldables. **16 KB pages** required; updates blocked from 2027-02-01 (AGP 8.5.1+, NDK r28+; check ML Kit/MediaPipe alignment) |
| Capture | CameraX **1.6.2**: `SessionConfig.Builder.setFrameRateRange`, `CameraInfo.getSupportedFrameRateRanges(sessionConfig)`, `GroupableFeature.FPS_60`, `isSessionConfigSupported`; `HighSpeedVideoSessionConfig` for 120/240 fps practice (all of these first shipped in **1.5.0**, 2025-09-10) | 60 fps support is device-dependent: check `isSessionConfigSupported`; an unsupported `requiredFeatureGroup` throws, a `preferredFeatureGroup` is dropped by priority. 1.6.0 stable (2026-03-25) uses the **Media3 muxer by default with crash resilience** (data preserved if the app crashes; migration in 1.6.0-beta02). Latest listed: 1.7.0-alpha03 (2026-08-12). Fixed [60,60] can be darker in low light. HEVC via `setVideoMimeType`, bitrate via `setTargetVideoEncodingBitRate` (12 Mbps planning value). Keyframe spacing not configurable (UNVERIFIED impact on stepping) |
| Recording errors | `VideoRecordEvent.Finalize` codes 0–10 | A file **is still produced** for `FILE_SIZE_LIMIT_REACHED`, may be for `DURATION_LIMIT_REACHED`/`SOURCE_INACTIVE`, may or may not for `INSUFFICIENT_STORAGE` → always check the output URI. `asPersistentRecording()` survives re-binds. Lifecycle-bound: leaving the activity → `SOURCE_INACTIVE` |
| Audio | `withAudioEnabled()` (needs `RECORD_AUDIO`), `AudioStats` (`SOURCE_SILENCED` when the dialer takes the mic), `Recording.mute()` | Mic off must degrade audio features visibly |
| Thermal | `PowerManager.getCurrentThermalStatus()` + listener (API 29, levels NONE…SHUTDOWN), `getThermalHeadroom()` (API 30; NaN if called > ~1/s), thresholds (35), headroom listener (36) | Ladder: MODERATE pause analysis; SEVERE warn / 30 fps at next re-bind; CRITICAL+ finalize |
| Output location | `FileOutputOptions` (app-specific, **deleted on uninstall**) vs `MediaStoreOutputOptions` (survives) | Record app-specific; offer "Also save to Movies/JOVRA"; say plainly on screen 19 that uninstall deletes local-only originals |
| Replay | Media3 **1.11.1** ExoPlayer: `SeekParameters.EXACT` (default), `setScrubbingModeEnabled(true)` (1.8+), `setPlaybackSpeed` | **No frame-step API**: pause + `seekTo(pos ± 1e6/fps µs)` EXACT; `VideoFrameMetadataListener` to sync overlays; short-GOP proxy via Transformer if backward steps are slow |
| Frames / thumbnails | `media3-inspector-frame` `FrameExtractor.getFrame/getThumbnail` (1.10+); `MetadataRetriever` | Colour caveat outside BT.601 limited on < API 33 |
| Export | Media3 Transformer: `ClippingConfiguration`, `experimentalSetTrimOptimizationEnabled`, `OverlayEffect` + `TextOverlay.getText(presentationTimeUs)` (burned-in live score), `BitmapOverlay` (drawings), `setRemoveAudio`, `getProgress` | Don't use MP4 edit-list trims for privacy-sensitive or external shares (pre-roll can show). Long exports as `mediaProcessing` FGS (6 h / 24 h limit, API 35+) |
| Pose | ML Kit Pose **beta** (18.0.0-beta5): 33 landmarks, **one person, face must be visible**; MediaPipe Pose Landmarker (`VIDEO` mode, `numPoses` 1–4) | Neither fits behind-baseline match footage; use MediaPipe on side-on clips; per-platform gate (iOS Vision and Android models will disagree) |
| Audio decode | `MediaExtractor` → `MediaCodec` (async), PCM 16-bit or float; `MediaExtractorCompat` | Same onset algorithm and conformance fixtures as iOS |
| Import | Photo Picker `PickVisualMedia(VideoOnly)` (Android 11+, backported to 19–29 via Play services); `takePersistableUriPermission` (5,000-grant cap); disable HDR→SDR transcoding via `setMediaCapabilitiesForTranscoding`; SAF `ACTION_OPEN_DOCUMENT` reaches Drive | **Do not request `READ_MEDIA_VIDEO`** (Play policy, enforced since 2025-05-28) |
| Drive auth | `AuthorizationClient` (`play-services-auth` 22.0.0); Picker via `PICKER_OAUTH_TRIGGER`; `revokeAccess` revokes all scopes | Device never holds a refresh token; background worker re-calls `authorize()` and marks "Needs reconnect" if `hasResolution()` (UNVERIFIED headless behaviour). AppAuth-Android unsuitable (custom schemes unsupported for Android clients) |
| Background upload | **UIDT** (`JobInfo.Builder.setUserInitiated(true)`, API 34+, `RUN_USER_INITIATED_JOBS`, notification) for "Back up now"; WorkManager 2.12 (UNMETERED, battery-not-low) with 32–64 MiB chunk checkpoints for automatic backup; OkHttp streaming body from a `FileChannel` offset | *Correction to the original assumption:* for apps targeting Android 15+, `dataSync` foreground services share a 6 h per 24 h budget (reset when the user brings the app to the foreground); at the limit the system calls `Service.onTimeout(int, int)` and the service must `stopSelf()` within seconds or a `RemoteServiceException` is thrown; Android 16 also counts long workers against job quota. WorkManager has no UIDT API — use `JobScheduler` directly |
| Persistence | Same JSON documents as iOS (ADR-0002); DataStore for preferences | Room is optional later; not for v1 (ADR-0002) |
| UI / nav | Compose BOM 2026.09.00; Navigation 3 1.2.0 | Predictive back required at target 36 |
| Live status | Android 16 `Notification.ProgressStyle` (Live Updates) | Equivalent of the iOS progress Live Activity |
| Testing | JVM (scoring, upload state machine with MockWebServer 308/404/5xx/403/429), instrumented (exact-seek frame accuracy on a frame-counter fixture), emulator `-camera-back videofile:court.mp4`, Maestro cli-2.11.0 (no physical iOS) | The emulator cannot prove fps, heat or encoder throughput; Pixel soak required |
| Distribution | Android developer verification: 2026-09-30 in four countries, global 2027 | Whether an `adb`-installed debug build is exempt: UNVERIFIED |

**Market note.** Android is the clearest structural gap: no SwingVision, SevenSix or Toach on Google Play; Onform is
2.97/309 on Android vs 4.79/8,666 on iOS; the best-rated Android tennis tool is the manual charting app Tennis Math
(4.61/3,345, 100K+) — a scorekeeping/stats app with no video, so not a like-for-like tracker; "absent from Play"
rests on a no-JavaScript search plus guessed package names (strong evidence, not exhaustive proof). The SwingVision CEO has publicly said Android hardware can't run its 60 fps real-time model for 2 h
without overheating (raw/community.md F1). JOVRA's capture-first, analysis-later architecture sidesteps that constraint
(INFERRED) — but the Pixel thermal soak must prove it.

---

## 15. String-bed acoustic estimate ("Pitch check")

**Physics (OBSERVED, Cross & Bower 2001; Cross 2006).** `f = (1/(2L))·√(T/μ)`, `L = √A`, `μ = ρπD²/4` →
`T = π·ρ·D²·A·f²`. Typical 500–700 Hz; a 10% tension drop ≈ 5% frequency drop. In-racket tension right after
stringing is ≈30% (nylon) / ≈40% (polyester) **below the machine pull tension**, so an honest reading never matches the
dialled number. Frame modes (≈133–152 Hz) are easy to exclude with a 350–1100 Hz search band. A dampener (or any
attached mass; 2.2 g lowered frequency 15.7%) must be removed.

**What is robust (INFERRED).** For one racket and one string job, `T/T₀ = (f/f₀)²` — diameter, density and area cancel.
Absolute error budget: +0.03 mm diameter → +4.9%; gauge mislabel 1.25→1.30 mm → +8.2%; density blend → −6.7%; wrong
head variant → ±2–3%; without per-racket calibration ±10–15% at best.

**Signal processing (INFERRED, synthetic simulation).** 48 kHz, 0.4 s Hann window, zero-padded FFT, parabolic peak:
frequency SD ≤ 0.36 Hz even at SNR 5 dB → precision is **not** the bottleneck. Real failure modes: locking onto the
1.593× or 2.136× mode (→ 2.54× or 4.6× tension error; matches RacquetTune "30 to 60 lb" reviews), hybrid mains/crosses
splitting peaks (≈10% flip between taps in simulation), ambient noise, hand damping, iOS audio regressions
(RacquetTune broke on iOS 26.4 and fixed it in 7.7 — OBSERVED).

**APIs.** `AVAudioEngine` input tap, `AVAudioSession` category `.record`, mode **`.measurement`** (minimizes system
processing, primary mic — OBSERVED), `vDSP` DFT; Android `MediaRecorder.AudioSource.UNPROCESSED` (API 24; falls back to
DEFAULT if unsupported — OBSERVED). Onset > 20 dB above noise floor; ≥5 accepted taps; median; reject if MAD > 2 Hz or a
mode-guard trips; store Hz + quality, never audio.

**Display (INFERRED, within the brief's "no tension sensor / no loss prediction" rule):** first "Change since your
fresh-string baseline: −8% (Estimated)"; optionally an in-racket estimate with a range and the explanation why it is
below the machine number. Never "tension meter", never "your strings are dead", never arm/injury claims.

**Gate (§10.7 of the raw note).** ≥3 frames, ≥3 strings (incl. a hybrid), pulls 45/52/58 lb on a known machine, ≥2
iPhone generations, load-cell or ERT reference over 2 weeks: test-retest spread ≤1% in frequency; relative-change error
≤3 percentage points; mode-error < 1% of accepted readings; hybrids pass or are explicitly unsupported; re-run on every
iOS beta. Plus a **CN/EP/WO freedom-to-operate search** (US 5,007,294 and US 5,406,827 are expired; active US patents
found are mechanical/stringing-apparatus, not acoustic — not legal advice).

**Initial status:** `unsupported` in iOS v1 (screen 18 forbids a sensor). Candidate P2 behind the gate.

---

## 16. Platform decisions and cross-cutting items

### 16.1 Deployment target — decision needed (contradiction across sources)

| Source | Position |
|---|---|
| ADR-0005 (current repo) | iOS 17 |
| raw/ios-tech.md | Consider iOS 18: unlocks `pauseRecording()`, `isAutoVideoFrameRateEnabled` control, Swift Vision API, export `states(updateInterval:)`, `AVCaptureControl`, `LockedCameraCapture`, multichannel audio; SwingVision already requires 18.0 |
| raw/gap-finder.md | iOS 26: `BGContinuedProcessingTask`, `SpeechAnalyzer`, iPhone `HKWorkoutSession`, AirPods capture events, Foundation Models, lens-smudge detection |
| Facts | iOS 26 on **79%** of all iPhones and 86% of iPhones from the last four years (Apple, measured 2026-06-07); Onform requires 18.6; the build machine has **only the iOS 26.5 simulator runtime**, so iOS 17/18 code paths cannot be executed locally (OBSERVED) |

**Recommendation (INFERRED):** raise the floor to **iOS 26.0** for v1 and record it in a new ADR superseding the
target line of ADR-0005. Reasons: (1) CLAUDE.md hard rule 9 ("a check that could fail has passed") cannot be met for
iOS 17/18 branches that no available simulator or device runs; (2) the features that make analysis and export
continue safely after leaving the app (`BGContinuedProcessingTask`) and hands-free marking (AirPods H2) are 26-only;
(3) the excluded ~20% skews to older, hotter devices that would struggle with 1–2 h capture anyway. Fallback if Jon
wants reach: iOS 18.0 with every 26-only feature behind `#available`, plus an iOS 18 device in the QA matrix.

### 16.2 Analysis scheduling

Capture only on court (no live inference); analyse after recording, at thermal state ≤ `fair`, preferably on power.
iOS 26+: user-tapped `BGContinuedProcessingTaskRequest` with system progress (background GPU needs the `gpu` resource
and entitlement; a forum report says `supportedResources` lacks `.gpu` on tested iPhones on iOS 26 — UNVERIFIED for
iOS 27, benchmark CPU/ANE). Overnight: `BGProcessingTaskRequest(requiresExternalPower: true)`. Below 26: foreground with
resumable checkpoints; screen 7 must then say "Analysis pauses if you leave JOVRA".

### 16.3 Hands-free input and status

`AVCaptureEventInteraction` (UIKit iOS 17.2+; SwiftUI `onCameraCaptureEvent` 18+): volume down / Action / Camera
Control = primary, volume up = secondary; **AirPods H2 stem clicks** arrive through the same API on iOS 26 (user-enabled
Remote Camera Capture). Map presses to **Mark point only, never Stop**, with a confirmation tone. Bluetooth range from
the far baseline (24–30 m) is UNVERIFIED. Live Activity (ActivityKit; ≤8 h active + 4 h on Lock Screen; 4 KB) mostly
duplicates the in-app UI while recording, but iPhone Live Activities appear in the Apple Watch Smart Stack (iOS 18 /
watchOS 11) — **whether they show while the app is foreground-recording is UNVERIFIED** and decides whether "recording
status on the wrist without a Watch app" is possible. Avoid Siri while recording (mic interruption risk).

### 16.4 Other APIs worth knowing

HealthKit `HKWorkoutActivityType.tennis` + `HKWorkoutBuilder` (iOS 12+; live iPhone sessions iOS 26) — never invent
calories/heart rate. Swift Charts (iOS 16+; `chartXSelection` 17+) with `accessibilityChartDescriptor` Audio Graphs.
XCUITest `performAccessibilityAudit(for:)` (iOS 17+) and `xcresulttool export attachments` for the 20-screen evidence
pack. `SpeechAnalyzer` (iOS 26) for on-device voice-note transcription. Foundation Models (iOS 26) only for descriptive
recaps whose every number is verified against computed stats.

---

## 17. iOS API cheat-sheet

| Need | API | Min iOS | Gotcha | Source |
|---|---|---|---|---|
| Record to file | `AVCaptureMovieFileOutput` | 4.0 | Delegate called on every normal/error stop but not on crash or kill; nil error = success, else read `AVErrorRecordingSuccessfullyFinishedKey` | Apple docs, SDK headers |
| Crash-tolerant file | `movieFragmentInterval` | 4.0 | Default 10 s; set ≈2 s before `startRecording` (mid-recording changes apply to the next file only); extra fragment at 2 GB | Apple docs |
| Guards | `maxRecordedDuration`, `maxRecordedFileSize`, `minFreeDiskSpaceLimit` | 4.0 | Stop with an error at the limit | Apple docs |
| Live size | `recordedFileSize`, `recordedDuration` | 4.0 | Bitrate slope → remaining minutes | Apple docs |
| Pause | `pauseRecording()` / `resumeRecording()` | **18.0** | iOS 17: stop + new file; not on visionOS/watchOS | Apple docs |
| Rotation of files | `startRecording(to:)` | 4.0 | iOS must stop first → gap | Apple docs |
| Start PTS | `fileOutput(_:didStartRecordingTo:startPTS:from:)` | **18.2** | On `synchronizationClock` (15.4) | Apple docs |
| Writer segments | `AVAssetWriter(contentType:)`, `outputFileTypeProfile`, `preferredOutputSegmentInterval`, `flushSegment()`, segment delegate | 14.0 | Implementing the delegate stops file output; encoding mode required | Apple docs, WWDC20 10011 |
| Writer fragments | `movieFragmentInterval`, `initialMovieFragmentInterval` | 4.1 / **17.0** | Both off by default; initial has no effect unless the interval is set; not settable after writing starts | Apple docs |
| Data + movie outputs together | data outputs + movie output | 16.0 (link) | Check `hardwareCost` < 1 | Apple docs, WWDC22 |
| Interruptions | `wasInterruptedNotification`, `InterruptionReason`, `runtimeErrorNotification` | 4.0 / 9.0 | Rebuild on `.mediaServicesWereReset` | Apple docs |
| Pressure / thermal | `systemPressureState`; `ProcessInfo.thermalState` | 11.1 / 11.0 | Throttle `activeVideoMinFrameDuration`; test with Device Conditions | Apple docs |
| Free space | `volumeAvailableCapacityForImportantUsageKey` | 11.0 | Required-reason API in privacy manifest | Apple docs |
| Keep awake / dim | `isIdleTimerDisabled`; scene screen `brightness` | 2.0 / 5.0 | `UIScreen.main` deprecated in 26 | Apple docs |
| Format / fps | `activeFormat`, `videoSupportedFrameRateRanges`, `activeVideoMin/MaxFrameDuration` | 7.0 | Setting format → preset `.inputPriority` | Apple docs |
| Auto fps off | `isAutoVideoFrameRateEnabled` | **18.0** | When true, setting durations throws | Apple docs |
| Motion blur | `activeMaxExposureDuration` | 12.0 | Resets on format change | Apple docs |
| Lens | `.builtInUltraWideCamera` (physical) | 13.0 | Virtual devices auto-switch lenses | Apple docs |
| Distortion / stabilization | `isGeometricDistortionCorrectionEnabled` (on); `preferredVideoStabilizationMode` (off) | 13.0 / 8.0 | Stabilization warps homography | Apple docs |
| Intrinsics | `videoFieldOfView`; `isCameraIntrinsicMatrixDeliveryEnabled` | 7.0 / 11.0 | Set before `startRunning` | Apple docs |
| Smudge check | `setCameraLensSmudgeDetectionEnabled(_:detectionInterval:)` | **26.0** | Before `startRunning` | Apple docs |
| Rotation | `RotationCoordinator`, `videoRotationAngle` | **17.0** | Lock at record start | Apple docs |
| Mic mixing / multichannel | `configuresApplicationAudioSessionToMixWithOthers`; `multichannelAudioMode`, `isWindNoiseRemovalEnabled` | 18.0 | Keep mixing false; wind removal needs non-`.none` | Apple docs |
| Exact seek | `seek(to:toleranceBefore:toleranceAfter:)` | 5.0 | Chase-time (QA1820) | Apple docs, QA1820 |
| Frame step | `AVPlayerItem.step(byCount:)` | 6.0 | Pause first | Apple docs |
| Slow motion | `defaultRate`, `canPlaySlowForward` | 16.0 / 6.0 | Don't start with `rate = 1` | Apple docs |
| Thumbnails | `AVAssetImageGenerator.image(at:)` | 16.0 | `.zero` tolerance for exact frames | Apple docs |
| Edge gestures | `preferredScreenEdgesDeferringSystemGestures` | 11.0 | On analysis screens | Apple docs |
| Drawing | `PKCanvasView.drawingPolicy` (`.pencilOnly`) | 14.0 | iPad Pencil policy | Apple docs |
| Clip export | `AVAssetExportSession.export(to:as:isolation:)` + `timeRange` | 13.0 (back-deployed) | Progress `states(updateInterval:)` 18.0 | Apple docs |
| Burn-in overlay | `AVVideoCompositionCoreAnimationTool` | 4.0 | Export-only; `AVCoreAnimationBeginTimeAtZero` | Apple docs |
| New composition | `AVVideoComposition(configuration:)` | **26.0** | `AVMutableVideoComposition` deprecated in 26 | Apple docs |
| Live overlay | `AVSynchronizedLayer` | 4.0 | For AVPlayer; `videoComposition` not for HLS | Apple docs |
| Voice-over | `AVAudioRecorder`/`AVAudioEngine` + event log → `AVMutableComposition` + animation tool, or custom `AVVideoCompositing` / `AVAssetWriter` | — | `RPScreenRecorder` can't capture AVPlayer | Apple docs |
| Import | `PhotosPicker(…, preferredItemEncoding: .current)`; `UIDocumentPickerViewController` | 16.0 / 11.0 | No library auth; copy temp file in handler | Apple docs |
| Save to Photos | `.addOnly` + `shouldMoveFile` | 14.0 / 9.0 | Moves, no copy | Apple docs |
| Share | `ShareLink` + `FileRepresentation` | 16.0 | — | Apple docs |
| Trajectories | `VNDetectTrajectoriesRequest` | 14.0 | Stateful; length ≥5; fixed camera | Apple docs |
| 2D / 3D pose | `VNDetectHumanBodyPoseRequest` / `VNDetectHumanBodyPose3DRequest` | 14.0 / 17.0 | 19 joints; subject ≥⅓; 3D most prominent only | Apple docs |
| Contours / registration | `VNDetectContoursRequest`; `VNTrackHomographicImageRegistrationRequest` | 14.0 / 17.0 | `maximumImageDimension` 512 default | Apple docs |
| Sound classes | `SNClassifySoundRequest(classifierIdentifier: .version1)` | 15.0 | `playing_tennis`; window ≥0.5 s | Apple docs, local run |
| FFT / decode | `vDSP.FFT`, `vDSP.window`; `AVAssetReader` | 13.0 / 4.1 | Float32 mono | Apple docs |
| Measurement audio | `AVAudioSession.Mode.measurement` | — | Minimal processing, primary mic | Apple docs |
| Hardware buttons | `AVCaptureEventInteraction` / `onCameraCaptureEvent` | **17.2** / 18.0 | AirPods on 26; foreground camera only | Apple docs, WWDC25 253 |
| Camera Control | `AVCaptureControl`, `AVCaptureSlider` | 18.0 | `session.supportsControls` | Apple docs |
| Lock-screen capture | `LockedCameraCapture`, `CameraCaptureIntent` | 18.0 | Extension, no network | Apple docs |
| Live Activity | `Activity.request(attributes:content:pushType:)` | 16.2 | 8 h + 4 h; 4 KB | Apple docs |
| Background work | `BGContinuedProcessingTaskRequest`; `BGProcessingTaskRequest.requiresExternalPower` | **26.0** / 13.0 | Report progress; GPU entitlement | Apple docs, WWDC25 227 |
| Background upload | `URLSessionConfiguration.background`; `GTMSessionUploadFetcher` | 7.0 | File-only uploads; 308 untested | Apple docs, gtm-session-fetcher |
| Hashes | CryptoKit `Insecure.MD5`, `SHA256` | 13.0 | One streaming pass | Apple docs |
| Workout | `HKWorkoutBuilder` + `.tennis` | 12.0 / 8.0 | Live iPhone session 26.0 | Apple docs |
| Charts / a11y | Swift Charts; `accessibilityChartDescriptor`; `performAccessibilityAudit` | 16.0 / 15.0 / 17.0 | — | Apple docs |
| Transcription / recap | `SpeechAnalyzer`; `SystemLanguageModel` | 26.0 | Device eligibility for FM | Apple docs, WWDC25 277 |

## 18. Android API cheat-sheet

| Need | API / library | Min API | Gotcha |
|---|---|---|---|
| 60 fps capture | CameraX 1.6.2 `SessionConfig.Builder.setFrameRateRange`, `getSupportedFrameRateRanges`, `GroupableFeature.FPS_60` | 23 (lib) | Fixed 60 darker in low light |
| High-speed | `HighSpeedVideoSessionConfig`, `Recorder.getHighSpeedVideoCapabilities` | 23 | No mirror, ViewPort or effects |
| Recording output | `FileOutputOptions` / `MediaStoreOutputOptions`, `setFileSizeLimit` | 23 | App-specific deleted on uninstall |
| Recording errors | `VideoRecordEvent.Finalize` (0–10), `CameraState` errors | 23 | Check the URI before declaring failure |
| Persistent recording | `PendingRecording.asPersistentRecording()` | 23 | Survives re-binds |
| Thermal | `PowerManager.getCurrentThermalStatus`, `getThermalHeadroom` | 29 / 30 | Headroom NaN if polled > ~1/s |
| Keep screen on | `FLAG_KEEP_SCREEN_ON` | 1 | Scope to recording |
| Exact seek / scrub | Media3 1.11.1 `SeekParameters.EXACT`, `setScrubbingModeEnabled` | 23 | No frame-step API |
| Frame extraction | `FrameExtractor` (`media3-inspector-frame`) | 23 | Colour caveat < 33 |
| Trim / overlay export | Transformer `ClippingConfiguration`, `OverlayEffect`, `TextOverlay`, `BitmapOverlay` | 23 | Edit-list trims leak pre-roll |
| Audio decode | `MediaExtractor` + `MediaCodec` (async) | 16 / 21 | PCM float only if confirmed |
| Measurement mic | `MediaRecorder.AudioSource.UNPROCESSED` | 24 | Falls back to DEFAULT |
| Pose | MediaPipe Pose Landmarker (`VIDEO`, `numPoses`); ML Kit Pose (beta) | 23 | ML Kit: one person, face visible |
| Import | Photo Picker `PickVisualMedia.VideoOnly`; SAF `ACTION_OPEN_DOCUMENT` | 19+ (backport) | No `READ_MEDIA_VIDEO`; persistable URIs capped at 5,000 |
| Drive auth | `Identity.getAuthorizationClient().authorize()`; `PICKER_OAUTH_TRIGGER`; `revokeAccess`; `clearToken` | Play services | No device refresh token |
| User-initiated upload | `JobInfo.Builder.setUserInitiated(true)` (UIDT) | 34 | Notification required; schedule while visible |
| Automatic upload | WorkManager 2.12 + `setForeground(dataSync)` | 24 | 6 h / 24 h shared cap when targeting 35+, resets on foreground; handle `onTimeout`; job quotas (36) |
| Live progress | `Notification.ProgressStyle` | 36 | Android 16+ |
| Nav / UI | Navigation 3 1.2.0; Compose BOM 2026.09.00 | 23 | Predictive back mandatory at target 36 |
| Emulator video camera | `emulator -camera-back videofile:<file>` | — | No real fps/heat evidence |
| UI flows | Maestro cli-2.11.0 | — | No physical iOS |

---

## Sources

All accessed 2026-10-07. Primary Apple, Google and Android documentation was read by the raw researchers; this
synthesis cites it through their notes, re-checking listing facts live (iTunes lookup, App Store IAP page) on the same
date.

| URL / file | What it supports |
|---|---|
| https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput/moviefragmentinterval | Fragment semantics, 10 s default |
| https://developer.apple.com/documentation/avfoundation/avcapturefileoutput | Guards, pause on iOS 18, iOS stop-before-restart rule |
| https://developer.apple.com/documentation/avfoundation/averror-swift.struct/code | Recording error codes, playable flag |
| https://developer.apple.com/documentation/avfoundation/avassetwriter and https://developer.apple.com/videos/play/wwdc2020/10011/ | fMP4 segments, initial fragment interval, encoding mode |
| https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason | Interruption reasons |
| https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.property | Pressure levels, factors, throttling advice |
| https://support.apple.com/118431 | 0–35 °C ambient operating range |
| https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey | Free-space key (required-reason API) |
| https://www.videoproc.com/iphone-video-processing/iphone-video-size-per-minute.htm | Per-minute file sizes (secondary; verify on device) |
| https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf | Court dimensions, run-back, ball size, line widths, rest maxima |
| https://www.itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf | SwingVision 60 fps, 1–2 devices, backend, accuracy not certified |
| https://developer.apple.com/library/archive/qa/qa1820/_index.html | Chase-time scrubbing |
| https://developer.apple.com/documentation/avfoundation/avplayeritem/step(bycount:) | Frame stepping |
| https://developer.apple.com/documentation/replaykit/rpscreenrecorder | Cannot record AVPlayer video |
| https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool | Burn-in rules; iOS 26/27 deprecations |
| https://developer.apple.com/documentation/photosui/photospicker | No-auth import, no-transcode encoding |
| https://developer.apple.com/documentation/vision/vndetecttrajectoriesrequest and https://developer.apple.com/documentation/vision/identifying-trajectories-in-video | Trajectory API constraints; tennis ball needs 1080p |
| https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images | 19 joints, subject ≥⅓ |
| https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest | 3D pose constraints |
| https://developer.apple.com/documentation/vision/vndetectcontoursrequest | Contour defaults |
| https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest | Built-in sound classes |
| https://openaccess.thecvf.com/content/CVPR2024W/CVsports/papers/Decorte_Multi-Modal_Hit_Detection_and_Positional_Analysis_in_Padel_Competitions_CVPRW_2024_paper.pdf | Padel hit detection F1 92% |
| https://arxiv.org/abs/1907.03698 | TrackNet precision/recall |
| https://pmc.ncbi.nlm.nih.gov/articles/2653872/ | Effective playing time 10–30% |
| https://developer.apple.com/videos/play/wwdc2025/253/ | Capture events, AirPods H2 |
| https://developer.apple.com/videos/play/wwdc2025/227/ and https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest | Continued processing, GPU entitlement |
| https://developer.apple.com/forums/thread/816774 | Background GPU missing on tested iPhones (forum, UNVERIFIED) |
| https://developer.apple.com/videos/play/wwdc2024/10068 | Live Activities in the Watch Smart Stack |
| https://developer.apple.com/support/app-store/ | iOS 26 adoption 79% / 86% |
| https://developers.google.com/workspace/drive/api/guides/api-specific-auth | `drive.file` classification |
| https://developers.google.com/workspace/drive/api/guides/manage-uploads | Resumable protocol, 256 KiB, 308/Range, 404, generated ids |
| https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker | Mobile Picker parameters |
| https://developers.google.com/identity/protocols/oauth2/native-app | iOS client, PKCE, redirects, revocation |
| https://support.google.com/cloud/answer/15549945 and /15549049 | Testing-mode 7-day expiry, brand verification |
| https://github.com/google/GoogleSignIn-iOS/releases | 10.0.0, iOS 15, no custom parameters |
| https://github.com/google/gtm-session-fetcher | Background resumable uploads |
| https://developers.google.com/workspace/drive/api/guides/limits | 2026-05-01 quotas, 1 TB/day egress |
| https://developers.google.com/workspace/drive/api/reference/rest/v3/files | Checksums, appProperties |
| https://developers.google.com/workspace/drive/api/reference/rest/v3/about/get | storageQuota with drive.file |
| https://support.google.com/drive/answer/9312312 | 15 GB free shared storage |
| https://developer.apple.com/documentation/foundation/downloading-files-in-the-background | Background session rules |
| https://developer.android.com/google/play/requirements/target-sdk | Target API 36 from 2026-08-31 |
| https://developer.android.com/guide/practices/page-sizes | 16 KB pages, 2027-02-01 |
| https://developer.android.com/jetpack/androidx/releases/camera | CameraX 1.6.2, Media3 muxer crash resilience |
| https://developer.android.com/reference/androidx/camera/video/VideoRecordEvent.Finalize | Finalize error codes |
| https://developer.android.com/reference/android/os/PowerManager | Thermal APIs |
| https://developer.android.com/jetpack/androidx/releases/media3 | Media3 1.11.1, scrubbing mode, FrameExtractor |
| https://developer.android.com/media/media3/transformer/transformations | Clipping, overlays, edit-list caveat |
| https://developers.google.com/ml-kit/vision/pose-detection | ML Kit beta, one person, face visible |
| https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker | MediaPipe `num_poses` |
| https://developer.android.com/identity/authorization | AuthorizationClient |
| https://developer.android.com/develop/background-work/background-tasks/uidt and https://developer.android.com/develop/background-work/services/fgs/timeout | UIDT; 6 h dataSync cap |
| https://developer.android.com/training/data-storage/shared/photo-picker and https://support.google.com/googleplay/android-developer/answer/14115180 | Photo Picker; READ_MEDIA policy |
| https://developer.android.com/studio/run/emulator-commandline | `-camera-back videofile:` |
| https://www.physics.usyd.edu.au/~cross/CrossBower.pdf and https://www.physics.usyd.edu.au/~cross/StringTension.pdf | String-bed physics, in-racket vs pull tension |
| https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement | Measurement audio mode |
| https://patents.google.com/patent/US5007294 | Expired acoustic tension patent |
| /Users/IDC2.5/jv/docs/research/raw/ios-tech.md | Crash experiment, framing math, error budgets, gates, iOS cheat-sheet |
| /Users/IDC2.5/jv/docs/research/raw/video-analysis-apps.md | Scrub/compare/voice-over/pose UX and constraints |
| /Users/IDC2.5/jv/docs/research/raw/drive-android-tech.md | Drive and Android detail, acceptance checks |
| /Users/IDC2.5/jv/docs/research/raw/equipment-stringing.md | Acoustic estimate, simulation, gate, patents |
| /Users/IDC2.5/jv/docs/research/raw/gap-finder.md | Platform extras, Space Saver arithmetic, iOS 26 recommendation |
| /Users/IDC2.5/jv/docs/adr/0001…0005, /Users/IDC2.5/jv/CLAUDE.md | Registry statuses, JSON store, native-per-platform, iOS 17 target to revisit |
| /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVCaptureFileOutput.h, AVAssetWriter.h, AVError.h (re-read by the verifier 2026-10-07) | Fragment-interval semantics, delegate guarantee scope, `AVErrorRecordingSuccessfullyFinishedKey`, pause availability, writer fragment defaults |
| https://developer.apple.com/documentation/avfoundation/avsynchronizedlayer and https://developer.apple.com/documentation/avfoundation/avplayeritem/videocomposition | Live overlay route for AVPlayer; videoComposition file-based only, not HLS |
| https://developer.apple.com/documentation/avfoundation/avvideocomposition/animationtool | Animation tool is for offline rendering with AVAssetExportSession, not AVPlayer |
| https://support.google.com/cloud/answer/7454865 and https://support.google.com/cloud/answer/13463073 | Unverified-app screen and 100-new-user cap only for sensitive/restricted scopes; verification optional for non-sensitive scopes, brand verification only for name/logo |
| https://developer.android.com/reference/androidx/camera/core/featuregroup/GroupableFeature | FPS_60 feature groups, required vs preferred behaviour (since CameraX 1.5.0) |
| https://developer.android.com/develop/background-work/services/fgs/timeout | dataSync 6 h / 24 h shared budget for apps targeting 35+, reset on foreground, `onTimeout` |
