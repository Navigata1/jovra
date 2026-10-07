# iOS capture and analysis feasibility for JOVRA (raw research notes)

Researcher pass: 2026-10-07. Scope: whether the iOS app can capture, review, analyze and integrate as planned, given a **deployment target of iOS 17**, built with **Xcode 26.6 and the iOS 26.5 SDK**. This file builds on `design-reference/brief/research.md`, which recommended AVFoundation and Vision but gave no API-level detail or limits, and it checks the 20 screens in `screens.json` against what the platform can actually do.

**Labels.** Each claim carries one of these tags:
- **OBSERVED**: seen in a primary source (Apple docs, the SDK headers, the ITF rules, a paper) or in a local experiment. The `[S#]` number points to the Sources list.
- **INFERRED**: my own reasoning or arithmetic from observed facts.
- **UNVERIFIED**: plausible but not confirmed in this pass. Treat it as a hypothesis to test on a device.

**Toolchain facts that constrain the build**
- `xcodebuild -version` reports Xcode 26.6 (17F113), and the only installed simulator runtime is iOS 26.5. The SDK on disk is `iPhoneOS26.5.sdk` (OBSERVED [S68]). The iOS 17 and 18 code paths behind `#available` checks therefore **cannot be run in a simulator on this machine** until an older runtime is downloaded or an older physical device is used (INFERRED).
- Apple's live documentation now lists some **iOS 27** symbols, including `AVCaptureMovieFileOutput.usesProVideoStorage`, `AVAssetExportSession.configureForResumableExport()` and Vision `DownloadableAssetsRequest` (OBSERVED [S2][S32][S42]). A grep of the iOS 26.5 SDK headers finds **no** `usesProVideoStorage` or `configureForResumableExport` (OBSERVED [S5]), so they are out of reach with Xcode 26.6. Apple's current AVCam sample itself is marked iOS 27 / Xcode 27 (OBSERVED [S25]).
- iOS adoption: Apple reports **iOS 26 on 79% of all iPhones** and 86% of iPhones introduced in the last four years, measured 2026-06-07 from App Store transactions (OBSERVED [S67]). SwingVision 11.9.67 requires **iOS 18.0** (OBSERVED [S26]).
  - **INFERRED decision input:** raising the floor from iOS 17 to iOS 18 unlocks several useful APIs: `pauseRecording()`, the SwiftUI `onCameraCaptureEvent`, the Swift-native Vision API, export `states(updateInterval:)`, `AVCaptureControl`, `LockedCameraCapture`, and multichannel audio. The cost looks small, since SwingVision already requires 18. This is worth a product decision before P0 code is written.

---

## 0. Bottom line (decision summary)

1. **Capture engine.** Put capture behind a `RecordingEngine` protocol.
   - **P0:** ship `AVCaptureMovieFileOutput` with `movieFragmentInterval` of about 2 s, plus a crash journal and automatic new-file-on-resume.
   - **P1:** build an `AVAssetWriter` engine that writes fragmented-MP4 segments (CMAF / `mpeg4AppleHLS` profile, 2–6 s segments). This is the structurally more robust design for 1–2 h recordings: loss is bounded to the current segment, no single file grows to tens of GB, nothing needs repair after a crash, and finished segments can be backed up while recording continues.
   - **Gate:** choose between the two with a device soak test (§1.13).
   - Locally on macOS 26.6.2, a writer killed mid-recording kept playable media in both modes: a fragmented `.mov` and joined fMP4 segments with audio and video (OBSERVED, local experiment [S9]).
2. **Interruptions end the current file; they are not fatal to the session.** Every interruption (going to the background, a phone call or alarm taking the audio hardware, thermal shutdown, another app taking the camera) stops `AVCaptureMovieFileOutput`. The recording delegate is still called, and its error carries `AVErrorRecordingSuccessfullyFinishedKey`, which says whether the file is playable (OBSERVED [S3][S4][S5]). Model a JOVRA session as an ordered list of recording segments plus gaps, not as a single file (INFERRED).
3. **Heat is the main real-world risk.** SwingVision's 2026-09-27 release notes list "improved recording stability in high temperatures", a crash fix for camera interruptions, and a new low-storage warning (OBSERVED [S26]). JOVRA needs a throttling ladder keyed to `systemPressureState`, a live free-space projection, and keep-awake plus screen-dim handling from day one (INFERRED).
4. **Framing math says the ultra-wide lens is effectively required.** Seeing both near doubles corners from the minimum club run-back of 5.48 m needs about 90° of horizontal field of view. The wide lens has about 69°; the ultra-wide has about 108° (INFERRED from ITF dimensions [S28] and the camera focal lengths).
   - The price is resolution. At 1080p on the ultra-wide, a ball at the far baseline is about **1.6 px** wide and each pixel covers about **0.41 m** of court depth (INFERRED, §1.9).
   - So far-court ball metrics are coarse, and line calling is not feasible. The screens already avoid line calls.
5. **Audio is the cheapest, most reliable signal.** Racket-ball impacts are short transients.
   - Spectral-flux onset detection with `vDSP` on the recorded track should find near-court hits well. Ball tracking is much harder.
   - Published audio hit detectors reach roughly F1 0.9 on broadcast or close-mic audio (OBSERVED [S49][S50]). Nobody has published results for a phone mounted on the fence, so that remains UNVERIFIED.
   - Correct for the speed of sound: a far-court hit reaches the phone about **86 ms** (about 5 frames at 60 fps) after it happens on video (INFERRED).
   - The built-in SoundAnalysis classifier, run on this Mac, includes the label **`playing_tennis`**, with a minimum window of 0.5 s (OBSERVED, local run [S44]). That gives a free coarse play/idle detector.
6. **`VNDetectTrajectoriesRequest` suits side-on practice clips, not behind-the-baseline match tracking.**
   - It needs a fixed camera, finds parabolas by frame differencing, and models the path in image space as y = ax² + bx + c (OBSERVED [S36][S37]).
   - From behind the baseline, rally balls move mostly vertically in the image, the ball is tiny far away, and every bounce splits the trajectory (INFERRED).
   - Match ball tracking needs a custom detector (TrackNet-class), which in turn needs labeled data (OBSERVED: TrackNet [S55]).
7. **Pose works on the near player; the far player is too small.** Apple advises a subject at least one third of the image height (OBSERVED [S39]). The near player fills about 23% of the frame height on the ultra-wide lens and the far player about 4% (INFERRED). Forehand/backhand detection from 2D pose is plausible for the near player only, and only after validation.
8. **Every derived number ships as "Estimated"** until it passes a capability-specific gate on held-out footage (§3.14). Speed, depth and placement are especially coarse for the far half of the court (INFERRED).
9. **Conflicts between the screens and the platform** (INFERRED; details in §5):
   - The capture screens (#5, #6) are drawn in portrait, but full-court capture needs a landscape phone.
   - The Pause control on #6 needs iOS 18 (`pauseRecording()`).
   - "Microphone · Optional · Off" (#20) would disable audio analysis.
   - "Photos · Selected photos" (#20) is not a status PhotosPicker produces.

---

## 1. Durable capture

### 1.1 Option A: `AVCaptureMovieFileOutput` with movie fragments

- **What a fragment interval means.** `movieFragmentInterval` (a `CMTime`, iOS 4+) is the number of seconds of output written per fragment. The default is **10 s**, and `.invalid` disables fragments, which Apple calls "not typically recommended" (OBSERVED [S1]).
  - Apple's explanation: a QuickTime file is unreadable without its sample table, and that table can only be written once recording completes. Periodically inserted "movie fragments" build the table up incrementally, so if writing is cut short, the file stays usable up to the last fragment written (OBSERVED [S1]).
  - The SDK header adds three details (OBSERVED [S5], `AVCaptureFileOutput.h`):
    - changing the interval does **not** affect a file already being written;
    - for external storage, an interval of ≥10 s performs best;
    - an extra fragment is inserted at the 2 GB mark when a fragment would reach 2 GB.
- **There is no "short first fragment" option on the movie output.** That property, `initialMovieFragmentInterval`, exists only on `AVAssetWriter` (iOS 17+; §1.2). With the default 10 s interval, a crash in the first 10 s leaves nothing playable (OBSERVED [S6], wording on AVAssetWriter). **Recommendation:** set `movieFragmentInterval` to about 2 s **before** `startRecording` (INFERRED). The overhead is one small `moof` box per fragment, which is negligible next to an 8–50 Mbps stream (INFERRED).
- **Completion semantics.**
  - `fileOutput(_:didFinishRecordingTo:from:error:)` is "always called for each recording request, even if no data is successfully written", on an unspecified thread (OBSERVED [S3]).
  - A non-nil `error` does **not** mean the file is bad. Check `AVErrorRecordingSuccessfullyFinishedKey`, an NSNumber BOOL "indicating whether the recording is playable" (OBSERVED [S5], `AVError.h`).
  - Apple's current AVCam sample treats any error as a failure (OBSERVED [S25]). JOVRA should not copy that (INFERRED).
- **Guards (all on `AVCaptureFileOutput`).** The output stops and calls the delegate with an error when it reaches any of these limits (OBSERVED [S2]):
  - `maxRecordedDuration` (default: no limit);
  - `maxRecordedFileSize` (default 0, meaning no limit);
  - `minFreeDiskSpaceLimit`.
  - `recordedFileSize` and `recordedDuration` are live while recording.
  - The matching error codes include `.diskFull`, `.maximumDurationReached`, `.maximumFileSizeReached`, `.sessionWasInterrupted`, `.mediaServicesWereReset` and `.noDataCaptured` (OBSERVED [S4]).
- **Rotating files on iOS leaves a gap.** On macOS you can call `startRecording(to:)` while a recording is in progress and samples are preserved across files. On iOS you must call `stopRecording()` first (OBSERVED [S2]). Splitting a long match into fixed 10-minute files would therefore drop frames at each boundary. The size of that gap is UNVERIFIED and must be measured.
- **Pause and resume.** `pauseRecording()` and `resumeRecording()` are available on iOS **18.0+** only (OBSERVED [S2][S5]). On iOS 17, the "pause" on screen #6 must be implemented as stop plus a new file (INFERRED).
- **Codec choice.** `availableVideoCodecTypes` lists what the output can write; the first entry is the default. Change it with `setOutputSettings(_:for:)`. On iOS the settings dictionary may contain only keys from `supportedOutputSettingsKeys(for:)`, and `AVVideoCompressionPropertiesKey` may be a sparse dictionary (OBSERVED [S18]). Whether a custom `AVVideoAverageBitRateKey` or key-frame interval is honored is UNVERIFIED.
- **Running analysis while recording.** For apps linked on iOS 16 or later, `AVCaptureVideoDataOutput` and `AVCaptureAudioDataOutput` can run alongside `AVCaptureMovieFileOutput`. Before iOS 16 the movie output "won" and the data outputs were disabled (OBSERVED [S5] `AVCaptureSession.h`; [S17] WWDC22; contrast the pre-iOS-16 forum answer [S69]).
  - Check `hardwareCost`. A value above 1.0 means the configuration cannot run, and the cost is only non-zero when such combinations are present (OBSERVED [S17]).
  - So live helpers (a framing check, a "camera moved" detector) can share the session with the movie output (INFERRED).

### 1.2 Option B: `AVAssetWriter` writing fragments or segments

- **Fragmented file.** `AVAssetWriter.movieFragmentInterval` is disabled (`.invalid`) by default (OBSERVED [S6]). `initialMovieFragmentInterval` (iOS 17+) sets a shorter first fragment; Apple suggests about 1 s, then 10 s (OBSERVED [S6]).
- **Segment mode.** This is fMP4/CMAF, available on iOS 14+.
  - Create the writer with `AVAssetWriter(contentType: UTType(AVFileType.mp4.rawValue)!)`, which takes **no URL** (OBSERVED [S6][S7]).
  - Set `outputFileTypeProfile = .mpeg4AppleHLS` or `.mpeg4CMAFCompliant`, `preferredOutputSegmentInterval` (for example 2–6 s), and `initialSegmentStartTime` (it must be numeric when the interval is numeric).
  - Implement `AVAssetWriterDelegate.assetWriter(_:didOutputSegmentData:segmentType:segmentReport:)`. Implementing it **stops normal file writing**; your code receives each segment as `Data` (OBSERVED [S6]).
  - Segment types: `.initialization` (the `ftyp` and `moov` boxes) and `.separable` (one `moof` plus `mdat`) (OBSERVED [S7]).
  - With `preferredOutputSegmentInterval = .indefinite`, you cut segments manually with `flushSegment()` (OBSERVED [S6][S7]).
- **Encoding mode is required.** When the writer encodes, it forces a sync sample at each segment interval. In passthrough mode, only one input is allowed and segments wait for the next sync sample (OBSERVED [S7]). Capture uses encoding mode with audio and video inputs.
  - AAC priming handling differs by profile: the Apple HLS profile shifts samples, while CMAF uses edit lists (OBSERVED [S7]).
- **iOS 26 additions.** Swift receiver APIs such as `inputReceiver(for:)` are available on iOS 26+ only (OBSERVED [S6]). Keep using the classic `append` API for iOS 17 (INFERRED).
- **Data source.** Buffers come from `AVCaptureVideoDataOutput` and `AVCaptureAudioDataOutput`.
  - Use `recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:)` (iOS 11+) and `recommendedAudioSettingsForAssetWriter(writingTo:)`. Apple says these produce output "comparable to" `AVCaptureMovieFileOutput`, but only once the session is fully configured (OBSERVED [S18]).
  - `alwaysDiscardsLateVideoFrames` defaults to true. If the delegate queue blocks, frames are dropped (OBSERVED [S18]). That is your bug surface with this option.

### 1.3 Local crash experiment (macOS 26.6.2, AVFoundation; a proxy for iOS)

Scripts and outputs are in `/private/tmp/claude-502/-Users-IDC2-5-jv/ios-tech/exp/` [S9]. The input was synthetic HEVC 1280×720 at 30 fps (plus AAC for the audio-and-video run). The writer was killed with `exit(0)` after 9 s of input, without calling `finishWriting`.

| Mode | Settings | Crash result | Clean result |
|---|---|---|---|
| Fragmented `.mov` written by `AVAssetWriter` | `movieFragmentInterval` 2 s, `initialMovieFragmentInterval` 1 s | Playable. Duration **7.10 s**, 214 frames decoded. The file was 4.47 MB, but only 3.14 MB survived a passthrough remux: bytes after the last fragment are orphaned. | 9.00 s, 274 frames |
| fMP4 segments, video only | `.mpeg4AppleHLS`, 2 s segments, each written to a temp file and atomically renamed | init (742 B) plus 4 segments joined by byte concatenation: playable, **7.90 s**, 241 frames | 9.00 s, 274 frames |
| fMP4 segments, video + AAC | as above | Joined file has 2 tracks: video 7.900 s, audio 7.956 s, both starting at 0 | — |
| Last segment cut in half (simulated torn write) | — | Metadata says **9.00 s**, but only **255** frames decode. Duration metadata is not proof that the media is intact. | — |

Findings (all OBSERVED locally [S9]; the iOS equivalence is INFERRED):
1. Both approaches keep media up to the last fragment or segment boundary.
2. A passthrough `AVAssetExportSession` remux turns the crashed file into a normal one in milliseconds at this size. Time and free space scale with file size: a 10 GB file needs about 10 GB free to remux (INFERRED).
3. Write each segment atomically (write to a temp file, then rename), and validate recovered media by **decoding to the end**, not by reading `duration`.

This experiment used `AVAssetWriter`, not `AVCaptureMovieFileOutput` on iOS. The two share the QuickTime fragment mechanism, but proving it on device belongs to the gate in §1.13.

### 1.4 Which is more robust for 1–2 hour recordings? (INFERRED, from §1.1–1.3)

| Criterion | MovieFileOutput + fragments | AVAssetWriter fMP4 segments |
|---|---|---|
| Worst-case loss on crash | Last ~fragment interval, plus encoder buffering (≈2 s observed) | The in-flight segment (≈1–2 s observed) |
| Post-crash work | Optional remux; needs as much free space as the file | None: concatenate segments, or play an index |
| Largest single file (1080p60 HEVC, 2 h) | ≈10.8 GB as one file (see §1.8) | Thousands of small files |
| Durable "saved through mm:ss" indicator | Approximate (`recordedDuration` minus the interval) | Exact (segment callback) |
| Back up during recording | No (the file is still being written) | Yes, per segment, on Wi-Fi |
| Engineering risk | Low: Apple owns sync, encoding and timing | Higher: your code owns A/V sync, back-pressure, dropped frames, interruption offsets and audio priming |
| Pause and seamless file rotation | Pause on iOS 18+; rotation leaves gaps | Built in (stop appending, offset timestamps) |
| Battery and heat | Presumed lower (fully system-managed) | UNVERIFIED (one extra buffer hop to the app) |

**Recommendation:** P0 uses MovieFileOutput (fast to ship, low risk). Build the fMP4 engine in P1 and switch only if the soak test (§1.13) shows MovieFileOutput losses or repair costs above threshold, or when backing up during recording becomes a requirement.

### 1.5 Interruptions and runtime errors

`AVCaptureSession.InterruptionReason` values, delivered through `wasInterruptedNotification` with `AVCaptureSessionInterruptionReasonKey` (OBSERVED [S10][S5]):

| Reason | Trigger | JOVRA behavior (INFERRED) |
|---|---|---|
| `videoDeviceNotAvailableInBackground` | App sent to the background, including the user pressing the lock button. The header says the session resumes automatically on returning to the foreground if you didn't call `stopRunning` (OBSERVED [S5]). | Finalize the segment and record a gap in the journal. On return, show "Recording stopped at 41:12 — Resume?" and **auto-resume only if the user opted in**. |
| `audioDeviceInUseByAnotherClient` | Phone call, alarm and similar (OBSERVED [S10]) | Same handling. Note that audio analysis has a gap. |
| `videoDeviceInUseByAnotherClient` | Another capture session took the camera | Same; prompt the user. |
| `videoDeviceNotAvailableWithMultipleForegroundApps` | iPad Slide Over, Split View, PiP or Stage Manager without multitasking camera access (OBSERVED [S10][S5]) | Explain that full screen is required. iPhone is not affected. |
| `videoDeviceNotAvailableDueToSystemPressure` | Thermal or power shutdown (pressure level `.shutdown`) (OBSERVED [S10][S11]) | Show "Phone too hot — recording saved through mm:ss". Resume after cool-down. |
| `sensitiveContentMitigationActivated` | Sensitive-content analyzer (iOS 26-era addition) (OBSERVED [S10]) | Not relevant; log it. |

- **Runtime errors.** `runtimeErrorNotification` carries `AVCaptureSessionErrorKey` (OBSERVED [S10]). For `.mediaServicesWereReset`, rebuild the session and restart; for anything else, stop and surface the error (INFERRED).
- **iPad multitasking.** `isMultitaskingCameraAccessSupported` (iOS 16+) is true only in three cases: Stage Manager with an external display, apps linked on iOS 18+ that declare the `voip` background mode, or apps holding the multitasking-camera entitlement (OBSERVED [S24]). JOVRA should not ask for that entitlement (INFERRED).
- **Phone calls are a design problem.** An incoming call or Siri activation may take the microphone and interrupt the **whole** session, which stops the movie file (INFERRED from reason 2; the exact behavior during the ringing phase is UNVERIFIED). Avoid encouraging "Hey Siri, mark point" while recording; use hardware capture events instead (§4.3). Recommend Focus/Do Not Disturb in the pre-record checklist (INFERRED).
- **Other audio.** `configuresApplicationAudioSessionToMixWithOthers` (iOS 18+) lets other apps' audio keep playing while capturing; the default `false` interrupts it (OBSERVED [S24]). Leave it `false`: court music picked up by the mic would contaminate hit detection (INFERRED).
- **Finishing the file after backgrounding.** The movie output writes its remaining data "in the background" after stop (OBSERVED [S2]). Request `UIApplication.beginBackgroundTask` when recording starts so the file can finish if the app is backgrounded (INFERRED; older AVCam versions did this, UNVERIFIED for the current sample).
- **File protection.** Keep the capture directory at the default protection, `completeUntilFirstUserAuthentication`, never `.complete`. Otherwise a device lock during finalization could block writes (INFERRED).

### 1.6 Heat, system pressure and battery

- **System pressure.** `AVCaptureDevice.systemPressureState` (iOS 11.1+, KVO-observable) has levels `nominal`, `fair`, `serious`, `critical` and `shutdown`. At `shutdown` the session is interrupted until pressure eases (OBSERVED [S11]).
  - Factors: `systemTemperature`, `peakPower`, `depthModuleTemperature`, `cameraTemperature`, and `batteryStress`, which means the device will shut down within about 30 s unless load drops (OBSERVED [S11]).
  - Apple's recommended mitigation is to throttle frame rate by lowering `activeVideoMinFrameDuration` (OBSERVED [S11]).
- **Thermal state.** `ProcessInfo.thermalState` (iOS 11+) reports nominal, fair, serious or critical, with a notification on change. Xcode can simulate these on a device through "Device Conditions" ("Test under adverse device conditions") (OBSERVED [S12]).
- **Throttling ladder (INFERRED).** Each rung is reversible and every transition is logged into session metadata so analysis knows the frame rate changed. The fps change happens inside the same file, because changing frame duration does not require a new file (UNVERIFIED: whether MovieFileOutput tolerates it without `.mediaChanged`).
  - `fair`: stop live helpers (the video data output); dim the preview.
  - `serious`: turn the preview off (curtain mode); show "Phone warming".
  - `critical`: drop to 30 fps by setting `activeVideoMinFrameDuration = 1/30`, if it is in the format's ranges.
  - `shutdown`: the system interrupts; the segment is saved.
- **Keeping the screen on.** Set `UIApplication.isIdleTimerDisabled = true` only while recording and reset it afterwards (Apple says to set it only when necessary) (OBSERVED [S15]).
  - If the user presses the side button, the app goes to the background and recording stops. The UI must say "Don't lock the phone — use Screen Dim" (INFERRED).
  - Screen Dim: a black overlay plus lower `UIScreen.brightness`. The brightness change persists until the device locks, even if the app closes (OBSERVED [S15]). Use the window scene's screen; `UIScreen.main` is deprecated in iOS 26 (OBSERVED [S15]).
- **Battery and Low Power Mode.** `UIDevice.batteryLevel` returns −1 unless monitoring is enabled (OBSERVED [S15]). `ProcessInfo.isLowPowerModeEnabled` changes are announced by `NSProcessInfoPowerStateDidChange` (OBSERVED [S15]).
  - Battery drain per mode is **UNVERIFIED**. Measure it in the soak test and feed the result into the "enough battery for 90 min?" pre-check (INFERRED).

### 1.7 Storage checks

- **Free space.** Read `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` (iOS 11+). It is a **required-reason API**: it must be declared in `PrivacyInfo.xcprivacy` under the disk-space category (OBSERVED [S13]).
  - Reason codes reported secondhand: **E174.1** (check there is enough space to write files, with user-observable behavior) and **85F4.1** (display disk space to the user; Apple's wording allows units like minutes of HD video). Neither may be sent off the device (OBSERVED via secondary source [S14]; check against Apple's reason list before submission).
- **Policy (INFERRED).**
  - Pre-flight check: `estimatedBytes(planned duration, measured rate) × 1.2` against the important-usage capacity. Also read `volumeAvailableCapacityKey` and show the conservative minimum. Important-usage capacity counts purgeable space the system may need time to reclaim.
  - Set `minFreeDiskSpaceLimit` to something like 1.5 GB, so the system stops cleanly before `.diskFull`.
  - Re-project the remaining minutes every 30 s from the slope of `recordedFileSize` (§1.8).
- **Where originals live.** Never in `tmp/` or `Library/Caches`, because the system purges those (OBSERVED [S66]).
  - Apple says not to exclude irreplaceable user content from backup (OBSERVED [S66]).
  - A 2 h 4K60 original (≈48 GB) can still break a user's iCloud backup. **Product decision:** offer a visible "Include originals in iCloud device backup" toggle, defaulting to **off with disclosure** or on, and point to the Drive archive and "Save to Photos" (moved, not copied; §2.6) as the durable copies (INFERRED).

### 1.8 Formats, frame rates, codecs and an honest GB/hour estimate

**Choosing a format (API pattern; INFERRED from OBSERVED APIs [S16][S17]):**
- Use the **physical** device: `builtInUltraWideCamera` or `builtInWideAngleCamera` from a `DiscoverySession`, not the virtual triple or dual-wide device. That keeps the lens, intrinsics and homography fixed. Virtual devices switch lenses on their own with zoom and light (OBSERVED [S20]). If a virtual device is used, restrict switching with `setPrimaryConstituentDeviceSwitchingBehavior` or the movie output's restricted switching for recording (OBSERVED, topic list [S20]).
- Go through `device.formats` and keep a format only if:
  - its dimensions match (`CMVideoFormatDescriptionGetDimensions(format.formatDescription)`);
  - some `videoSupportedFrameRateRanges` entry has `maxFrameRate` ≥ the target;
  - `unsupportedCaptureOutputClasses` does not contain `AVCaptureMovieFileOutput` (some high-resolution photo formats exclude it, OBSERVED [S16]);
  - it is an 8-bit SDR 420v/420f pixel format, not x420 HLG.
- Prefer binned formats when heat matters (`isVideoBinned`: more light sensitivity, less resolution) (OBSERVED [S16]).
- Apply the choice inside `beginConfiguration()` and `commitConfiguration()` with `lockForConfiguration()`: set `activeFormat`, then `activeVideoMinFrameDuration` and `activeVideoMaxFrameDuration` set to the same value to lock fps. Setting `activeFormat` moves the session preset to `.inputPriority` (OBSERVED [S16]).
- **Turn off `isAutoVideoFrameRateEnabled`** (iOS 18+). When on, it moves 60→30→24 fps in low light, and setting min/max frame durations then **throws** (OBSERVED [S16]). It resets to false whenever the format changes (OBSERVED [S16]).
- Check `session.hardwareCost < 1` after adding outputs (OBSERVED [S17]).
- **Motion blur.** In auto-exposure modes, cap `activeMaxExposureDuration` (iOS 12+) at about 1/500 s for a "ball-friendly" mode. This trades noise for less blur and resets when the format changes (OBSERVED [S16]; the 1/500 value is INFERRED and needs tuning).
- **Color.** `activeColorSpace`: set `automaticallyConfiguresCaptureDeviceForWideColor = false`, then use `.sRGB` for consistent analysis. Changing color space mid-session ends any movie capture in progress (OBSERVED [S16]).
- **Stabilization.** `preferredVideoStabilizationMode` defaults to `.off`. Any stabilization mode adds latency and per-frame warping, which breaks a fixed court homography. Keep it **off** for mounted capture (OBSERVED default [S20]; consequence INFERRED).
- **Distortion correction.** Keep `isGeometricDistortionCorrectionEnabled` on (it defaults to on where supported) so court lines stay straight for the homography. The corrected FOV is `geometricDistortionCorrectedVideoFieldOfView` (OBSERVED [S20]).

**Estimated file sizes.** These figures are the per-minute sizes iOS shows in Settings › Camera › Record Video, taken from a secondary source dated 2024-02-01 (OBSERVED secondary [S19]). They are not Apple API values. Conversions are INFERRED (GB = 10⁹ bytes, video only).

| Mode | MB/min | GB/hour | ≈Mbps | 2-hour total |
|---|---|---|---|---|
| 1080p30 HEVC | 60 | 3.6 | 8.0 | 7.2 GB |
| **1080p60 HEVC** | **90** | **5.4** | **12.0** | **10.8 GB** |
| 1080p120 HEVC | 170 | 10.2 | 22.7 | 20.4 GB |
| 1080p240 HEVC | 480 | 28.8 | 64.0 | 57.6 GB |
| 4K30 HEVC | 170 | 10.2 | 22.7 | 20.4 GB |
| 4K60 HEVC | 400 | 24.0 | 53.3 | 48.0 GB |
| 1080p60 H.264 | 175 | 10.5 | 23.3 | 21.0 GB |
| 4K30 H.264 | 350 | 21.0 | 46.7 | 42.0 GB |

- **An honest estimate method (INFERRED):**
  1. Before recording, read `movieOutput.outputSettings(for: connection)`. On iOS it is always fully populated (OBSERVED [S18]). Use `AVVideoCompressionPropertiesKey › AVVideoAverageBitRateKey` if present (UNVERIFIED that it is). Otherwise use the table above for the codec, resolution and fps. Add AAC at about 0.1 GB/h (INFERRED).
  2. After 30 s, replace that with the measured slope of `recordedFileSize` (OBSERVED API [S2]), shown as a range (±15%) because scene complexity changes bitrate.
  3. Label the number "Estimated" and recompute it continuously.
- **Context.** The mock's "1080p · 60 fps · 3.2 GB" equals about 36 min at 90 MB/min, while the 54-min sample match would be about 4.9 GB (INFERRED). That value must come from the method above (`implementation-states.md` already forbids hard-coding it).
- **H.264 or HEVC.** HEVC is about half the size. H.264 is more compatible on old Android or desktop players. Keep HEVC for originals and offer H.264 only as an **export** option (INFERRED).
- **Which frame rate (INFERRED).** SwingVision records matches at **60 fps** (OBSERVED in the ITF PAT report [S27]).
  - Ball travel per frame: about 0.33 m at 20 m/s and 0.75 m at 45 m/s (a fast serve) at 60 fps; at 240 fps, 0.08 m and 0.19 m.
  - **Matches:** 1080p60 HEVC (5.4 GB/h).
  - **"High detail" match mode:** 4K60 when there is enough storage and heat headroom (24 GB/h).
  - **Serve or stroke practice clips (short):** 1080p120 or 240, which also forces exposure ≤1/240 s.
- **Lens smudges (iOS 26+).** `setCameraLensSmudgeDetectionEnabled(_:detectionInterval:)` reports `cameraLensSmudgeDetectionStatus`. Enabling it causes a lengthy pipeline reconfiguration, so do it before `startRunning` (OBSERVED [S21]). There is also a Vision `DetectLensSmudgeRequest` (iOS 26) for imported video (OBSERVED [S42]). This is a cheap pre-record check for outdoor phones (INFERRED).

### 1.9 Lens and framing geometry (why the ultra-wide, and what it costs)

**Inputs.**
- Court (OBSERVED [S28]): 23.77 m × 10.97 m doubles (8.23 m singles); service lines 6.40 m from the net.
- Run-back behind the baseline (OBSERVED [S28]): at least **5.48 m** recommended for club play, 6.40 m for international play.
- Ball (OBSERVED [S28]): 6.54–6.86 cm in diameter.
- Camera assumed 5.5 m behind the baseline, 3.0 m high.
- Assumed horizontal FOVs: wide about 69° (26 mm-equivalent); ultra-wide about 108° (13 mm-equivalent). At runtime, read `activeFormat.videoFieldOfView`, which is horizontal in degrees (OBSERVED [S16]).
- Pixel focal length f = (W/2) / tan(HFOV/2). Everything below is INFERRED arithmetic.

**Horizontal FOV needed to see both near corners from the fence:**
- 5.48 m run-back: **90°** (doubles) or 74° (singles).
- 6.40 m run-back: 81° or 66°.
- 8.0 m run-back: 69° or 54°.
- So the wide lens cannot frame a club court's near doubles corners; the **ultra-wide is effectively mandatory**. This matches industry practice, since SwingVision mounts at the back fence with a full-court view (OBSERVED [S27]).

**Ball size in pixels / court depth per vertical pixel on the ground:**

| Configuration | Near baseline | Net | Far service line | Far baseline |
|---|---|---|---|---|
| Wide 1080p (f≈1397) | 14.9 px / 0.01 m | 5.3 / 0.07 | 3.9 / 0.14 | 3.2 / 0.21 |
| Ultra-wide 1080p (f≈697) | 7.5 / 0.02 | 2.6 / 0.15 | 1.9 / 0.27 | **1.6 / 0.41** |
| Ultra-wide 4K (f≈1395) | 14.9 / 0.01 | 5.3 / 0.07 | 3.9 / 0.14 | 3.2 / 0.21 |

**Player height as a share of frame height** (Apple advises at least ⅓ for pose, OBSERVED [S39]):
- Ultra-wide: near player about **23%**, far player about **4%**.
- Wide: 47% and 8%.

**What follows (INFERRED):**
1. Ultra-wide 4K gives the far court the same pixel density that wide 1080p gives it. 4K is the main lever for far-court metrics, and it costs 2–4× the storage.
2. In/out calls at the far baseline are impossible: one pixel covers 0.2–0.4 m, against ITF lines 2.5–10 cm wide (OBSERVED [S28]).
3. A higher mount helps: at 4 m height the far-baseline depth per pixel improves to about 0.31 m (ultra-wide 1080p).

### 1.10 Orientation

- Use `AVCaptureDevice.RotationCoordinator` (iOS 17+) with `videoRotationAngleForHorizonLevelCapture` and `videoRotationAngleForHorizonLevelPreview`, and `AVCaptureConnection.videoRotationAngle`. Only 0, 90, 180 and 270 are valid; check `isVideoRotationAngleSupported`. A movie-output connection records the rotation **in the track matrix and does not rotate pixels**. A video-data output rotates every buffer, so set the angle before `startRunning` or set it to 0 and handle rotation yourself. With `AVAssetWriter`, set the input `transform` instead (OBSERVED [S22]). `videoOrientation` is deprecated (INFERRED).
- **Lock the angle when recording starts** (INFERRED). A phone tilted down on a fence can flip its sensed orientation, and a matrix change mid-recording would corrupt analysis coordinates. `setRecordsVideoOrientationAndMirroringChangesAsMetadataTrack` exists if changes must be tracked (OBSERVED topic [S1]).
- **Landscape UI is required for capture.** Screens #5 and #6 are portrait compositions, but a full-court 16:9 recording means a physically landscape phone. Build landscape variants of Calibration and Live Recording, or the preview and controls will be sideways (INFERRED).

### 1.11 Aligning manual score, bookmarks and video time

- `fileOutput(_:didStartRecordingTo:startPTS:from:)` (iOS **18.2+**) gives the PTS of the first buffer on the session's `synchronizationClock` (iOS 15.4+) (OBSERVED [S23]).
- **Mapping a tap to video time:** media time ≈ `CMClockGetTime(session.synchronizationClock)` − `startPTS` − (paused durations) (INFERRED).
- On iOS 17–18.1, fall back to sampling `recordedDuration` at the moment of the tap (OBSERVED API [S2]); expect about one frame of error (UNVERIFIED).
- With `AVAssetWriter`, the PTS of the buffer is known exactly (INFERRED).

### 1.12 Audio configuration for analysis

- **The microphone is required for audio analysis** (hit and rally detection, automatic contact sync in Compare). Screen #20's "Microphone · Optional · Off" must explain that turning it off removes those features (INFERRED).
- **Multichannel audio.** `AVCaptureDeviceInput.multichannelAudioMode` supports `.stereo` and `.firstOrderAmbisonics` (iOS 18+). Wind-noise removal (`isWindNoiseRemovalEnabled`, iOS 18+) is available only when the multichannel mode is not `.none` (OBSERVED [S24][S5]).
  - Stereo or ambisonics could give a direction of arrival, which would help reject hits from neighboring courts. This is INFERRED and UNVERIFIED.
  - Whether wind-noise removal dulls the hit transients is UNVERIFIED. Run an A/B test before enabling it by default.

### 1.13 Device soak-test gate for the capture engine (INFERRED proposal)

Run per engine (Option A and Option B), on a minimum-spec device and a current device, outdoors in sun and indoors:
- 3 × 2-hour continuous recordings, each at 1080p60 and at 4K60 where storage allows;
- 20 forced terminations (`kill` from Xcode, plus memory pressure);
- 10 interruptions of each kind (incoming call, alarm, backgrounding, lock button, Control Center pull-down, another camera app);
- thermal soak with Xcode Device Conditions set to "serious" (OBSERVED tool [S12]);
- a low-storage run (fill the device to 2 GB free).

Pass criteria:
- media lost per crash ≤ 3 s;
- 0 unrecoverable sessions;
- journal and video agree within one frame;
- gap per interruption ≤ 1.5 s plus the duration of the interruption itself;
- battery drain recorded per mode.

---

## 2. Review: playback, scrubbing, clips and sharing

### 2.1 Frame-accurate seeking and smooth scrubbing

- `AVPlayer.seek(to:toleranceBefore:toleranceAfter:)` lands within [time − before, time + after]. Passing `.zero` for both asks for sample-accurate seeking, at the cost of extra decoding. An async variant exists. A new seek **cancels** the previous one, whose completion then returns `false` (OBSERVED [S29]).
- **Scrubbing pattern** (Apple QA1820, "chase time"): never fire seeks back to back. Keep one seek in flight and remember the latest target (OBSERVED [S29]).
- **Recommended policy (INFERRED):** during a drag, seek with a tolerance of about 0.1–0.5 s, which lands on key frames quickly. When the drag ends, and for point jumps, seek with `.zero` tolerance.
- Long-GOP HEVC makes backward frame stepping costlier (each step decodes from the previous key frame). Whether the capture output's key-frame interval can be set is UNVERIFIED (§1.1).

### 2.2 Frame stepping and slow motion

- `AVPlayerItem.step(byCount:)`: a positive count steps forward, a negative one backward, and step size depends on the enabled tracks (one video frame for video). Check `canStepForward` and `canStepBackward`, whose values don't change once the item is ready (OBSERVED [S30]).
- **Rates.** `AVPlayer.rate` controls speed. `defaultRate` (iOS 16+) is what `play()` uses; Apple says not to start playback by setting `rate = 1` (OBSERVED [S30]).
  - Check `canPlaySlowForward` before offering 0.25×.
  - `audioTimePitchAlgorithm` controls pitch-preserving audio at scaled rates (OBSERVED [S30]). Mute audio below 0.5× (INFERRED).
- **Frame-rate arithmetic.** High-frame-rate capture is stored at its real timestamps (INFERRED: unlike the Camera app's slo-mo there is no time-mapping track; UNVERIFIED). A 240 fps clip at 0.25× therefore shows 60 fps, while a 60 fps clip at 0.25× shows 15 fps (INFERRED arithmetic). For the 0.25× serve comparison on screen #14, recommend 120 or 240 fps practice capture.

### 2.3 Thumbnails and filmstrips

- `AVAssetImageGenerator.image(at:)` and `images(for:)` (async, iOS 16+). Set `appliesPreferredTrackTransform = true` and `maximumSize` to limit decode cost. `requestedTimeToleranceBefore` and `After` default to +infinity; `.zero` gives frame-accurate frames at extra cost (OBSERVED [S31]).
- **Policy (INFERRED):** filmstrip and library thumbnails use the default tolerance; "Contact" freeze frames (Stroke Lab #13) use `.zero`.

### 2.4 Clip export and a burned-in scoreboard

- **Plain clip.**
  - `AVAssetExportSession(asset:presetName: AVAssetExportPresetPassthrough)` with `timeRange` copies without re-encoding (OBSERVED [S32]).
  - `export(to:as:isolation:)` is async throws; it is **back-deployed to iOS 13** when built with the iOS 26 SDK (`@backDeployed(before: iOS 26.0)`) (OBSERVED [S32]).
  - Progress comes from `states(updateInterval:)` on iOS 18+. On iOS 17, poll the deprecated `progress` (OBSERVED [S32]; fallback INFERRED).
  - Passthrough cut points may rely on edit lists rather than exact frames, and some players ignore edit lists (UNVERIFIED).
- **Composed clip (multiple points or a highlight reel).** Use `AVMutableComposition`: call `insertTimeRange` per point on the video and audio composition tracks and copy `preferredTransform` (INFERRED standard pattern).
- **Scoreboard burn-in.**
  - Use `AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:in:)` with a parent `CALayer` containing the video layer and a `CATextLayer` scoreboard (OBSERVED [S33]).
  - Rules (OBSERVED [S33]):
    - start animations at `AVCoreAnimationBeginTimeAtZero`, not 0;
    - set `isRemovedOnCompletion = false`;
    - don't use layers that belong to a `UIView`;
    - the animation tool is for **offline rendering with AVAssetExportSession only, not AVPlayer**.
  - For the live replay overlay (#10), use an `AVSynchronizedLayer` tied to the player item (OBSERVED [S33]).
  - Burn-in forces re-encoding: use an HEVC or H.264 preset, not passthrough (INFERRED).
- **API churn.** `AVMutableVideoComposition` is **deprecated in iOS 26** in favor of `AVVideoComposition(configuration:)` with `AVVideoComposition.Configuration` (iOS 26+). The tool's `init(postProcessingAsVideoLayer:in:)` is deprecated in iOS **27** in favor of `init(configuration:)` (iOS 26+) (OBSERVED [S33]). With an iOS 17 floor, branch with `#available(iOS 26, *)` (INFERRED).
- **Resumable export** (`configureForResumableExport`) is iOS 27 only and not in the 26.5 SDK (OBSERVED [S32][S5]). Long exports should run in a `BGContinuedProcessingTask` on iOS 26+ (§4.9).

### 2.5 Importing video

- `PhotosPicker` (SwiftUI, iOS 16+) and `PHPickerViewController` (iOS 14+) run in a separate process. **No photo-library authorization is needed** to pick items (OBSERVED [S35]).
- Pass `preferredItemEncoding: .current` so the HEVC original is not transcoded (OBSERVED [S35]).
- `NSItemProvider.loadFileRepresentation` writes a **temporary copy that is deleted when the completion handler returns**, so copy or move the file inside the handler (OBSERVED [S35]).
- **Status row on screen #20 (INFERRED).** "Photos · Selected photos" is not a state PhotosPicker produces. Show "Not needed for import" and, if saving to Photos is enabled, "Add-only".

### 2.6 Sharing and saving

- `ShareLink` (iOS 16+) shares any `Transferable`. Use `FileRepresentation` for video files so Mail, Messages and AirDrop appear (OBSERVED [S34]).
- **Save to Photos.**
  - Request `PHPhotoLibrary.requestAuthorization(for: .addOnly)` with `NSPhotoLibraryAddUsageDescription` (OBSERVED [S34][S35]).
  - Add the video with `PHAssetCreationRequest.addResource(with: .video, fileURL:, options:)` and **`shouldMoveFile = true`**. Photos then moves the file instead of copying it, using no extra space; this fails if the file is open or hard-linked (OBSERVED [S34]).
  - This gives a zero-cost durable copy of a finished original (INFERRED).

---

## 3. On-device analysis: one card per capability

**How these are scheduled (INFERRED).** Run analysis after the session, from the recorded file:
- read audio with `AVAssetReader` as mono 48 kHz Float32 PCM, and video in time-range windows (OBSERVED API [S46]);
- run audio analysis first: it is cheap and finds the hits;
- run expensive vision only in windows around each hit, for example −0.6 s to +0.4 s. The padel study did the same, running ball detection only near hits found from audio (OBSERVED [S50]).

Rough budget: a 90-min match at 60 fps is 324,000 frames. About 1,000 hits × 1 s × 60 fps is roughly 60,000 frames, about **5×** less work (INFERRED). Per-frame Vision timings are **UNVERIFIED**; benchmark them per device.

### 3.1 Court calibration from four tapped corners (homography)

**Approach (INFERRED; standard projective geometry).**
- **Court coordinates in meters** (from ITF dimensions [S28]). Origin at the near-left doubles corner:
  - doubles corners (0,0), (10.97,0), (10.97,23.77), (0,23.77);
  - singles sidelines at x = 1.37 and x = 9.60;
  - net at y = 11.885;
  - service lines at y = 5.485 and y = 18.285;
  - centre service line at x = 5.485, running from y = 5.485 to y = 18.285.
- **Taps to pixels.** Convert taps into video pixel coordinates, not view points.
  - Preview: `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)` gives normalized coordinates in sensor orientation; then apply the rotation.
  - Recorded video: map through the `AVPlayerLayer` video rect.
  - Offer a magnifier loupe. Optionally snap each tap to nearby line edges (§3.2).
- **Homography H (3×3, eight degrees of freedom):** s·[u v 1]ᵀ = H·[X Y 1]ᵀ.
  - Each correspondence (Xᵢ,Yᵢ)→(uᵢ,vᵢ) gives two rows of A·h = 0:
    `[−X, −Y, −1, 0, 0, 0, uX, uY, u]` and `[0, 0, 0, −X, −Y, −1, vX, vY, v]`.
  - Four points give an 8×9 system; h is the right singular vector for the smallest singular value (SVD via Accelerate LAPACK). Alternatively fix h₃₃ = 1 and solve the 8×8 system directly.
  - **Normalize first** (Hartley): move points to their centroid and scale the mean distance to √2, separately for image and court points, then de-normalize: H = T_img⁻¹ · Ĥ · T_court.
  - With more than four points (net posts, service-line T's), use least squares and RANSAC.
- **Using it.**
  - Court point to image: H. Image ground point to court: H⁻¹, applied to feet, bounces and the ball's ground shadow.
  - It only holds for points **on the court plane**. A ball in the air is not on the plane.
- **Camera pose, for 3D work.**
  - Intrinsics K: fx = fy = (W/2)/tan(HFOV/2), (cx, cy) at the image center, with HFOV from `videoFieldOfView` (OBSERVED API [S16]). Alternatively take `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix` from a data output with `isCameraIntrinsicMatrixDeliveryEnabled`, which must be set before `startRunning` (OBSERVED [S16]).
  - Compute B = K⁻¹H = λ[r₁ r₂ t] with λ = 1/‖b₁‖, then r₃ = r₁ × r₂, and re-orthonormalize R by SVD.
  - Project 3D points as x = K[R|t]X. This lets you check the **net top** (0.914 m at the center, 1.07 m at the posts, OBSERVED [S28]) against the image, and turn ball image points into rays for 3D fitting.
- **Built-in validation (INFERRED).** After calibration, project the lines that were *not* tapped (service lines, centre service line, singles sidelines) and measure their distance to the actual line pixels. Accept if RMSE ≤ about 3 px at 1080p; otherwise ask the user to re-tap. This is an automatic check that could fail, which is what the build methodology asks for.

**Reliability (INFERRED).**
- Near-court precision is high: about 0.01–0.03 m per pixel near the near baseline.
- Far-court precision is poor: a 2 px tap error at the far baseline is about 0.8 m of court depth on ultra-wide 1080p (§1.9).

**Failure modes.**
- Taps in preview points instead of pixels.
- Lens distortion with distortion correction off.
- The phone moving after calibration: wind on the fence, bumps (§3.3).
- Zoom or format changes. The calibration must be bound to the format, the zoom factor and the physical lens (INFERRED).

**Gate.**
- Reprojection RMSE ≤ 3 px on held-out lines.
- On 20 courts, the median error of 30 ground-truth chalk or cone points per half court is ≤ 0.10 m on the near half, with far-half values reported separately.
- The UI says "Calibrated" or "Calibration estimate low quality".

### 3.2 Line detection and tap snapping (`VNDetectContoursRequest`)

- **API facts (OBSERVED [S41]).**
  - `VNDetectContoursRequest` (iOS 14+) defaults: `contrastAdjustment` 2.0 (range 0–3); `maximumImageDimension` 512, so a 4K frame is downscaled and thin far lines disappear unless you raise it; `detectsDarkOnLight = true`, which must be **false** for white lines on a dark court.
  - Contours can be simplified with `polygonApproximation(epsilon:)` (Ramer-Douglas-Peucker).
  - `VNDetectRectanglesRequest.quadratureTolerance` allows at most 45° of corner deviation, so it won't find a court seen in strong perspective (INFERRED).
- **Approach (INFERRED).**
  - Run contours in a small region around each tap at full resolution.
  - Fit lines with RANSAC.
  - Snap the tap to the intersection of the two fitted lines.
  - Fully automatic court finding (Hough-style line candidates fitted to a court model) is a solved problem for broadcast footage, robust to occlusion and shadows (OBSERVED, Farin et al. [S56]). On amateur courts it remains UNVERIFIED.
- **Failure modes (INFERRED).**
  - **Pickleball lines painted on tennis courts**, which are common in the US.
  - Worn lines; clay with tape lines; strong shadows; night lighting glare; players standing on lines.
- **Gate.** Snapped corners within 2 px of hand labels in ≥ 95% of 200 frames over at least 3 surfaces. Ship "assisted snap" first, fully automatic later.

### 3.3 Detecting that the camera moved

- `VNTranslationalImageRegistrationRequest` and `VNHomographicImageRegistrationRequest` (iOS 11+), plus the stateful `VNTrackHomographicImageRegistrationRequest` (iOS 17+), which compares each frame with the previous one (OBSERVED [S41]). Action & Vision used translational registration to decide when the scene was stable (OBSERVED [S38]).
- **Approach (INFERRED).** Every N seconds, register the current frame against the calibration reference frame, masked to the court surface or the fence regions. If drift is more than about 2 px, flag the calibration "stale from mm:ss" and optionally re-estimate H.
- **Gate.** Detect a deliberate 1° nudge in at least 99% of trials, with false alarms below 1 per hour of wind-only footage.

### 3.4 Racket-ball hit detection from the audio track

**Signal facts.**
- The impact sound is a fast-decaying impulsive part plus a lower-level ringing part (OBSERVED, search summary of tennis acoustics studies [S54]).
- Stringbed modes sit at about 0.58–1.58 kHz and frame bending modes at about 146–862 Hz (OBSERVED [S54]).
- Table-tennis bounce energy sits around 11 kHz (OBSERVED [S53]), a different ball, so not transferable (INFERRED).

**Approach (INFERRED, following onset-detection practice [S47]).**
1. Decode PCM with `AVAssetReader` and `AVAssetReaderTrackOutput` (Float32, mono, 48 kHz).
2. Frame the signal: N = 1024 (21.3 ms) with a hop of 256 (5.3 ms), or N = 512 with a hop of 128 for finer timing. Apply a Hann window (`vDSP.window(ofType:usingSequence: .hanningDenormalized, count:isHalfWindow:)`), then `vDSP.FFT(log2n:radix:ofType:)` and `forward(input:output:)` (OBSERVED APIs, iOS 13+ [S45]).
3. Compute the onset function. Spectral flux: SF(t) = Σₖ max(0, |X_t(k)| − |X_{t−1}(k)|) over about 1–8 kHz, with log compression. Alternatively high-frequency content, HFC = Σ k·|X(k)|² (both described in [S47]).
4. Pick peaks against an adaptive threshold (moving median ± δ·MAD), with a refractory period of about 150 ms.
5. Refine the time to about 1 ms with the peak of a high-pass envelope.
6. Classify each onset as hit, bounce, or other (footsteps, voices, neighbor court) using band ratios, spectral centroid and decay time, or a small Core ML model trained on labeled onset windows.
   - The built-in sound classifier is too coarse for this: on macOS 26.6.2 its window range is 0.5 s to about 15 s, with a 3.0 s default and 0.5 overlap (OBSERVED, local run [S44]).
   - `MLSoundClassifier` (Create ML) trains on audio files (OBSERVED [S43]); per-onset inference latency is UNVERIFIED.
7. **Correct for sound travel.** Subtract distance/343 m/s using the player position from the homography: about **18 ms** for the near baseline, about 51 ms at the net, and about **86 ms** for the far baseline (INFERRED). Without this, far-court contact frames are off by about 5 frames at 60 fps.

**Expected precision.**
- **Timing:** about 1–3 ms internally; after travel correction, alignment to video is limited by the frame period (16.7 ms at 60 fps) (INFERRED).
- **Detection, from the literature** (none of it is phone-at-the-fence):
  - broadcast tennis atomic events: F1 **92.39%**; point boundaries about 80% precision and recall (OBSERVED via search summary [S49]; the primary page was unreachable);
  - padel broadcast, CRNN: **F1 92%** (σ 1.6%) with a 250 ms collar. Misses were mostly slices; false alarms came from rackets hitting frames, stomping and players hitting the glass (OBSERVED [S50]);
  - table-tennis energy-peak plus MFCC-SVM: precision 91%, recall 73% (OBSERVED [S51]);
  - wrist-worn audio only: P 85% / R 75%; fused with IMU: P 97.3% / R 93.9% (OBSERVED [S52]);
  - broadcast tennis with GMM and language models (Huang & Cox 2010) (OBSERVED [S48]).
- **JOVRA expectation (UNVERIFIED):**
  - near-court hits: high recall;
  - far-court hits: about **13 dB** quieter (29.4 m vs 6.3 m, inverse square, INFERRED), so lower recall;
  - neighboring courts: comparable distances and loudness, so they are the dominant **false-positive** source (INFERRED);
  - quiet slices, drop shots and soft volleys: misses, consistent with [S50].
- **Mitigations (INFERRED).**
  - Require visual corroboration: a near or far player's wrist moving fast at the onset time.
  - Optionally estimate direction of arrival from stereo or ambisonic capture (iOS 18+, §1.12).
  - Let the user exclude a neighbor court by tapping a "noisy side".

**Gate.**
- Held-out sessions from at least 10 courts and conditions (day, night, indoor, wind, adjacent play).
- Own-court hits: precision ≥ 0.95, recall ≥ 0.90, timing MAE ≤ 10 ms after travel correction. Passing this allows shot counts labeled **"Estimated"**.
- At ≥ 0.98 / 0.95 the badge can be dropped.
- Report near and far ends separately.

### 3.5 Rally and point segmentation, and dead-time removal

- **Rule facts (OBSERVED [S28]):** at most **25 s** between points, 90 s at changeovers, 120 s at set breaks.
- **Approach (INFERRED).**
  - A rally is a sequence of hits whose gaps are under about 3 s; typical rally gaps are about 1–2 s for 20–30 m of travel at 15–25 m/s. A gap over about 5 s starts a new point.
  - The built-in SoundAnalysis label **`playing_tennis`** (present among the 303 labels of the macOS 26.6.2 classifier, OBSERVED [S44]) can provide a coarse "play vs idle" prior at 0.5–3 s resolution.
  - Pad each rally by about −2 s and +1.5 s for highlight clips.
- **Reliability (INFERRED).** High for dead-time removal: missing one hit rarely loses a whole rally.
  - Moderate for point boundaries: serve-fault sequences, let serves and warm-up rallies confuse the rules.
  - Broadcast audio reached about 80% precision and recall for point boundaries, with umpire and crowd cues that amateur audio lacks (OBSERVED via [S49]).
  - **Point winner is not inferable from audio. Manual scoring remains the source of truth.**
- **Gate.** ≥ 99% of labeled own-court hits fall inside kept clips; point-boundary F1 ≥ 0.90 within ±1.0 s; dead time removed ≥ 60%. Below that, show "Auto-trim (review)".

### 3.6 Serve detection (INFERRED heuristics; all UNVERIFIED until gated)

1. The first own-court hit after a gap of more than 5–6 s.
2. The hitter's feet, projected through H, are behind the baseline (within about 0.5 m) and between about 0 and 4.1 m from the centre mark. The lateral side gives deuce or ad, which should alternate between points.
3. Pose at the contact frame: the dominant wrist is above the nose by at least about half the torso length, and both arms were raised during the toss 0.5–1.5 s earlier.
4. Optionally, a rising-then-falling ball blob above the server (the toss).
5. Second serve: a serve with no own-court return within about 2.5 s, followed by a serve from the same position within about 5–25 s.

Reliability: plausible for the near server; the far server's pose is weak (4% of frame height on the ultra-wide). Gate: precision ≥ 0.95 and recall ≥ 0.90 on the near end; on the far end, report the numbers and hide anything below 0.85.

### 3.7 Ball trajectories with `VNDetectTrajectoriesRequest`

**How it works and its parameters (OBSERVED [S36][S37][S38]).**
- It is a **stateful** request (a `VNStatefulRequest` subclass, iOS 14+): create **one** instance and perform it on consecutive `CMSampleBuffer`s that carry timestamps. It works by looking at frame differences, so it **needs a fixed camera on a tripod and a static background**.
- It detects several simultaneous trajectories, including objects "only a few pixels" in size. Every bounce, and every exit from and re-entry to the frame, starts a new trajectory.
- `init(frameAnalysisSpacing:trajectoryLength:completionHandler:)`:
  - `frameAnalysisSpacing` is a `CMTime`; `.zero` analyzes every frame;
  - `trajectoryLength` must be **≥ 5** points.
- `objectMinimumNormalizedRadius` and `objectMaximumNormalizedRadius` (iOS 14+; the older `minimumObjectSize` and `maximumObjectSize` are deprecated). Apple's sample uses diameter in pixels divided by video width, and advises setting the minimum slightly small and the maximum slightly large.
- `targetFrameTime` (iOS 15+): for real time, the request trades accuracy to stay within a per-frame budget. The default `.indefinite` keeps maximum accuracy.
- `regionOfInterest` reduces noise.
- Results are `VNTrajectoryObservation`:
  - `detectedPoints` (observed centroids) and `projectedPoints` (the ideal parabola);
  - `equationCoefficients`, a `simd_float3` for **y = ax² + bx + c** in normalized image coordinates;
  - `movingAverageRadius` (iOS 15+), plus a UUID and time range.
- The completion handler is called with **no observations** until there is a confident trajectory of the requested length.
- Apple's guidance: small objects **"like a tennis or cricket ball"** may need **1080p**; Vision downscales based on the minimum object size.
- Offline: `VNVideoProcessor` (iOS 14+), whose `cadence` defaults to every frame, or the Swift `VideoProcessor` and `DetectTrajectoriesRequest` (iOS 18+) (OBSERVED [S36][S42]).
- **Action & Vision sample:** a Core ML board detector, `VNDetectContoursRequest` for the board, translational registration for stability, body pose for the player, trajectories for the throw, and a Create ML action classifier for throw type. It treats a throw as complete after 20 frames with no observations, and computes speed from known board size and trajectory duration. It requires A12 or later on iOS 14 (OBSERVED [S38]).

**Limits for tennis (INFERRED).**
1. **The geometry is wrong from behind the baseline.** Rally and serve paths are mostly toward or away from the camera, so they are near-vertical in the image. A model of y as a function of x degenerates for them, and perspective bends a true 3D parabola.
2. **The ball is tiny.** About 1.6–3 px at the far baseline (ultra-wide 1080p, or wide and ultra-wide 4K), and blur stretches it into a streak several ball-lengths long at auto exposure.
3. **Moving things create noise.** Frame differencing also fires on players, rackets, flags, shadows, and **LED or fluorescent flicker** indoors.
4. **Bounces fragment the track.**

**Where it fits.** Side-on serve or stroke practice clips (Serve Lab #12, Compare #14), where the ball moves across the frame horizontally, close to the camera, at 120–240 fps.

**For match tracking.** Train a heatmap detector of the TrackNet class: three stacked frames at 640×360 input; 99.7% precision and 97.3% recall on one broadcast match, but **95.3% / 75.7%** in cross-validation over 10 videos (OBSERVED [S55]). Convert it to Core ML, and follow it with a Kalman filter or a physics fit. This needs a labeled amateur fence-camera dataset (INFERRED).

**Gate.**
- Per-shot detection recall ≥ 0.9 near half and ≥ 0.7 far half on held-out sessions.
- Trajectory association: ≤ 5% identity swaps.
- Until then, show no ball trails in match replay, or show them as "Experimental".

### 3.8 Bounce location (shot map #11) and depth metrics

- **Approach (INFERRED).** A bounce is a sign change in the vertical image velocity of the ball track, or the break between two trajectories, optionally confirmed by a bounce onset in audio. Project the contact pixel through H⁻¹.
- **Error budget (INFERRED).**
  - Pixel resolution: §1.9.
  - Time quantization: ±8 ms at 60 fps; at 15–25 m/s horizontal speed that is ±0.12–0.2 m.
  - Blur-streak center versus the actual contact point.
- **Reliability.** Near half: about ±0.2–0.3 m is plausible. Far half: ±0.5–1 m on ultra-wide 1080p, roughly half that on 4K. **Never** make in/out calls (consistent with screen #5's "no pretend line calls").
- **UI.** Use "Deep / Mid / Short" bins with uncertainty-aware edges, and a "Needs review" state for points near bin edges. That matches the legend already on #11.
- **Gate.** Median error ≤ 0.3 m near half and ≤ 0.8 m far half against ground truth from a second, higher camera or hand-marked bounce frames. Bin accuracy ≥ 90% near half, else hide far-half bins.

### 3.9 Serve and shot speed (Serve Lab #12 "104 mph · Estimated")

**Method (INFERRED).**
- Average horizontal speed = ground distance from the contact point (projected) to the bounce ÷ (bounce time − contact time).
- Contact time comes from the audio onset corrected for travel time; bounce time from video.
- Convert to a "peak" or radar-like speed with a drag model. The ratio depends on spin, so this adds the largest error.

**Error budget, ultra-wide 1080p, near-end server (INFERRED):**
- bounce location ±2 px × 0.27 m/px ≈ ±0.54 m over an ~18.3 m path, about ±3%;
- bounce timing ±8.3 ms over ~0.47 s, about ±1.8%;
- contact time from audio, about ±0.4%;
- position of the contact point, about ±1.6%.
- Combined, about ±4% for the average speed. The drag and spin conversion adds roughly ±5–8% (UNVERIFIED), for about **±10% overall**.

**Side-on practice view.** Speed in the image plane needs a scale reference at the ball's depth. A ±1 m depth offset at 8 m distance is ±12%; 120–240 fps helps the timing (INFERRED).

**Gate.**
- At least 200 serves measured against a radar gun across ≥ 10 players.
- Mean absolute percentage error ≤ 7% and 90% of serves within ±10% → show as **"Estimated"** with a ± range.
- Otherwise show only relative comparisons ("faster than your average"). This matches #12's "Camera calibration affects speed".

### 3.10 2D body pose and forehand/backhand classification

- **API facts (OBSERVED [S39][S42]).**
  - `VNDetectHumanBodyPoseRequest` (iOS 14+): **19** body points with per-point confidence; ignore points with confidence 0. Coordinates are normalized with the origin at **bottom-left**. Several people can be detected, one observation each.
  - Accuracy tips from Apple: subject height ≥ ⅓ of the image; most joints visible; loose clothing and crowds hurt; **set a region of interest** for better accuracy.
  - The Swift `DetectHumanBodyPoseRequest` (iOS 18+) adds `detectsHands`.
- **Approach (INFERRED).**
  - Find people with `VNDetectHumanRectanglesRequest`.
  - Track identity per court side using the foot position from H⁻¹: near or far, and for doubles, left or right.
  - Run pose with a **region of interest around each player on full-resolution frames**. 4K helps here even if the analysis itself runs at lower resolution.
  - At the contact frame (audio onset minus travel delay), with handedness from onboarding:
    - near player, seen from behind: dominant wrist on the dominant side of the shoulder/hip midline → forehand; on the non-dominant side → backhand;
    - wrists within about 0.25 × torso length of each other on the non-dominant side → two-handed backhand;
    - wrist above head → serve or overhead (separate them by rally context and position: overheads happen mid-rally near the net);
    - feet inside the service line with little swing travel → volley;
    - **far player, facing the camera:** reverse left and right.
- **Reliability (INFERRED).** Plausibly good for the near player: about 23% of frame height on the ultra-wide, more with a region of interest. Poor for the far player at about 4%, below Apple's guidance.
  - Hard cases: inside-out and run-around forehands, open versus closed stances, the wrist hidden behind the body, left-handers, and doubles occlusion.
- **Gate.** Confusion matrix on ≥ 300 labeled strokes per class, per court end, with ≥ 20% left-handers.
  - Near end: accuracy ≥ 0.90 for **Estimated**, ≥ 0.95 to drop the badge.
  - Far end: if below 0.80, label the stroke "Unknown", not a guess.

### 3.11 3D body pose (`VNDetectHumanBodyPose3DRequest`)

- **API facts (OBSERVED [S40]).** iOS 17+, a stateful request.
  - Only the **most prominent person**, as a single observation, with **all 17 joints or none**. Positions are in meters relative to the root joint (between the hips).
  - `bodyHeight` is measured only with LiDAR depth; otherwise it is a **1.8 m reference**.
  - `cameraRelativePosition(_:)` and `pointInImage(_:)` are provided. Depth data improves accuracy but is not required.
- **Fit (INFERRED).**
  - Not useful for match footage: wrong subject, tiny far player, no rear-camera depth at court range.
  - Possibly useful in close side-on practice clips for qualitative trunk rotation. Show it as a "3D estimate" without degree numbers, which screen #13 already avoids.
- **Gate.** Agreement with a 2-camera or marker reference within ±10° for the shoulder-hip separation angle on 50 swings before showing any numeric angle.

### 3.12 Create ML action classifier for stroke types

- **Facts (OBSERVED [S43]).**
  - Built in the Create ML app on macOS 11+ (`MLActionClassifier` is macOS-only). Training extracts body-pose landmarks with Vision and learns the sequences.
  - Apple asks for **at least 50 videos per action** plus a **negative class**. Each video should clearly show **one person**; with several people, the subject must be the largest.
  - The classifier's frame rate must match the app's; the prediction window equals frame rate × action duration.
  - Horizontal-flip augmentation is optional.
- **Fit (INFERRED).**
  - Feed it pose sequences from the per-player region of interest. Horizontal flip is fine for forehand/backhand labels, because a mirrored right-hander forehand is a left-hander forehand.
  - Classes: forehand, backhand (one- or two-handed), serve, volley, overhead, negative (walking, ball pickup, bouncing the ball before a serve).
  - Data needs: hundreds to thousands of labeled windows from fence cameras across players. This is a P2 data project; Apple's minimum of 50 is a floor, not a target.
- **Gate.** Same as §3.10, on held-out players (no player in both train and test).

### 3.13 Compute, heat and background execution for analysis (INFERRED plan)

- Run analysis only after recording stops, never during capture, when the device is at or below `fair` and on power when possible.
- **iOS 26+:** a `BGContinuedProcessingTaskRequest` started by a user tap ("Analyze now").
  - The system shows progress in a Live Activity, and the user can cancel there.
  - You must report progress; tasks showing little progress are terminated first.
  - Background GPU use needs the `gpu` resource, a check of `BGTaskScheduler.supportedResources`, and the background-GPU entitlement.
  - Submission strategy can be `.queue` or `.fail`.
  - (All OBSERVED [S64].)
- **iOS 17–25:** analysis runs in the foreground; leaving the app pauses it (resumable checkpoints per window). Optionally schedule a `BGProcessingTask` that requires external power for overnight runs (INFERRED).
- **Screen #7's copy** "Recording is safe. You can leave this screen" is right for the screen. For leaving the *app* it must say "Analysis pauses if you leave JOVRA" on iOS < 26 (INFERRED).

### 3.14 Validation-gate framework and display states (INFERRED proposal)

| Display state | Rule |
|---|---|
| **Hidden** | No gate run, or it failed below the minimum |
| **Experimental** | Behind a settings toggle; gate not yet passed |
| **Estimated** (badge with a ± range or confidence) | Passed the minimum gate on held-out footage for **this configuration band** (lens, resolution, fps, camera height and distance band, surface, light) |
| **Reviewed** | The user confirmed or corrected it (the "Needs review" flow) |
| Unbadged | Passed the strict gate; the method is still described on a detail page |

- **Dataset rules.** At least 20 sessions, 8 courts, 3 surfaces, day and night, at least 12 players including left-handers, both court ends. Split by session and court so nothing leaks between train and test.
- **Re-gating.** Re-gate whenever the model, thresholds or capture defaults change. Store the gate result ID in each metric record so the UI can show what the number rests on.

| Capability | Single-phone feasibility (INFERRED) | Minimum gate for "Estimated" |
|---|---|---|
| Court calibration (4 taps) | High near half; coarse far half | Held-out line RMSE ≤ 3 px; ground points ≤ 0.10 m near half |
| Camera-moved detection | High | 99% detection of a 1° nudge; < 1 false alarm per hour |
| Audio hit detection (own court) | High near, medium far, neighbor-court false positives | P ≥ 0.95, R ≥ 0.90, MAE ≤ 10 ms |
| Rally and point segmentation | High (trim), medium (boundaries) | ≥ 99% hits kept; boundary F1 ≥ 0.90 at ±1 s |
| Serve detection | Medium-high near, low far | P ≥ 0.95, R ≥ 0.90 near |
| Forehand/backhand | Medium-high near, low far | Accuracy ≥ 0.90 near; far below 0.80 → "Unknown" |
| Ball tracking (Vision trajectories) | Low from behind the baseline; good side-on | Recall ≥ 0.9 near, ≥ 0.7 far |
| Bounce map and depth bins | Medium near, low far | Median ≤ 0.3 m near and ≤ 0.8 m far |
| Serve speed | Low-medium (±10%) | MAPE ≤ 7% and 90% within ±10% against radar |
| 3D pose angles | Low (qualitative only) | ±10° against a reference before numbers appear |
| Line calls | **Not feasible** (0.2–0.4 m per pixel far) | None; do not build |

---

## 4. Platform extras

### 4.1 Live Activities (ActivityKit)
- **Facts (OBSERVED [S59]).** ActivityKit is iOS 16.1+; `Activity.request(attributes:content:pushType:)` is 16.2+ and must be called from the foreground, unless the activity is started through a `LiveActivityIntent`.
  - A Live Activity can be active for up to **8 h**, then stays on the Lock Screen up to 4 h more (12 h maximum).
  - Static plus dynamic data is limited to **4 KB**. Use `staleDate` for out-of-date content.
- **Fit (INFERRED).** Recording needs JOVRA in the foreground, so a Live Activity *during* recording mostly duplicates the in-app UI. Its value is:
  - after an interruption: "Recording stopped at 41:12 — tap to resume", updated while background time remains;
  - for backup and analysis progress (on iOS 26, `BGContinuedProcessingTask` already provides a system Live Activity [S64]).
  - Use `Text(timerInterval:)` for elapsed time so no updates are needed. Add `NSSupportsLiveActivities` to Info.plist.

### 4.2 App Intents and Siri ("Start recording")
- **Facts (OBSERVED [S60]).**
  - `AppShortcutsProvider` and `AppShortcut` are iOS 16+.
  - `openAppWhenRun` is **deprecated in iOS 26** in favor of `supportedModes` (iOS 26+): use `.foreground(.immediate)` to open the app before the action runs.
  - `ForegroundContinuableIntent` (16.4+) is deprecated in 26 in favor of `.foreground(.dynamic)`.
- **Fit (INFERRED).**
  - The camera cannot run in the background, so "Start recording" must foreground the app: `openAppWhenRun = true` on iOS 17–25, `supportedModes` on 26+.
  - It should open the framing check, not start blind.
  - App Shortcut phrases need the app name token (`\(.applicationName)`; UNVERIFIED in this pass).
  - **Avoid voice commands while recording**: Siri activation can interrupt capture audio (§1.5, UNVERIFIED).

### 4.3 Hardware buttons and Camera Control
- **Capture events.** `AVCaptureEventInteraction` (UIKit, iOS **17.2+**) and SwiftUI `onCameraCaptureEvent` (iOS 18+) (OBSERVED [S57]).
  - Events arrive only while the app is **actively using the camera in the foreground**.
  - Adopting it overrides the buttons' default behavior, so disable the interaction (`isEnabled = false`) whenever you can't respond.
- **Which buttons map where (WWDC25 session 253, OBSERVED [S57]):** volume down, the Action button and **Camera Control** send *primary* events; volume up sends *secondary* (or primary if no secondary handler is set). **AirPods stem clicks** (H2 chip, iOS 26, user-enabled under Remote Camera Capture) arrive through the same API with no extra code, and an `event.shouldPlaySound` / `defaultSoundDisabled` option controls the feedback tone.
- **Camera Control controls.** `AVCaptureControl`, `AVCaptureSlider` and `AVCaptureSystemZoomSlider` (iOS 18+) let the Camera Control adjust settings, added with `session.addControl` after checking `supportsControls` (OBSERVED [S58]).
- **Fit (INFERRED). This is a real differentiator:**
  - **"Mark point" from the baseline** with an AirPods stem click or a volume press, without walking to the fence.
  - Map hardware presses to **bookmark only, never Stop**, to prevent accidental endings. Play the tone so the player knows it registered.
  - Requires iOS 17.2 for UIKit and iOS 26 for AirPods.

### 4.4 Lock Screen and Control Center launch
- `LockedCameraCapture` (iOS 18+) lets an extension launch your camera experience from the Lock Screen, Control Center or the Action button. `CameraCaptureIntent` (iOS 18+) marks the intent (OBSERVED [S58]); AVCam adopts both (OBSERVED [S25]).
- Fit: a P3 "quick record" path. The extension's restrictions on data access and the handoff into the app add work (INFERRED; restrictions UNVERIFIED in this pass).

### 4.5 HealthKit tennis workouts
- **Facts (OBSERVED [S61]).** `HKWorkoutActivityType.tennis` (iOS 8+).
  - `HKWorkoutBuilder(healthStore:configuration:device:)` (iOS 12+): call `beginCollection(withStart:)`, `endCollection(withEnd:)`, then `finishWorkout`. This is the iOS 17 path for saving a workout afterwards.
  - On iPhone, `HKWorkoutSession(healthStore:configuration:)` and `HKLiveWorkoutBuilder` exist only from **iOS 26**. Heart rate on iPhone needs an external sensor.
- **Fit (INFERRED).** Write a tennis workout with the session's start and end. **Do not invent calories or heart rate**; add them only from a Watch or sensor in a future version. Needs the HealthKit capability and `NSHealthUpdateUsageDescription`. Make it opt-in in Settings.

### 4.6 PhotosPicker without full library access
- See §2.5 (OBSERVED [S35]). Use add-only access for saving (§2.6).

### 4.7 Swift Charts
- **Facts (OBSERVED [S62]).** Swift Charts is iOS 16+. `chartXSelection` and `chartScrollableAxes` are iOS 17+, as is `SectorMark`. `LinePlot` (function plots) is iOS 18+. `Chart3D` is iOS 26+. `accessibilityChartDescriptor` (iOS 15+) provides an accessible chart description and audio graph.
- **Fit (INFERRED).** All the Progress and Home charts work on an iOS 17 floor. Add a chart descriptor with explicit units and denominators, as `implementation-states.md` already requires.

### 4.8 Accessibility audits and screenshot automation in XCUITest
- **Accessibility audits (OBSERVED [S63]).** `XCUIApplication.performAccessibilityAudit(for:_:)` runs on iOS 17+ (introduced at WWDC23, session 10035).
  - `XCUIAccessibilityAuditType` covers `.contrast`, `.dynamicType`, `.elementDetection`, `.hitRegion`, `.sufficientElementDescription`, `.textClipped`, `.trait`, `.action`, `.parentChild` and `.all`.
  - Issues fail the test unless the handler returns `true` to ignore them.
- **Screenshots.**
  - `XCUIScreen.main.screenshot()` or `element.screenshot()`, wrapped in `XCTAttachment(screenshot:)` with `lifetime = .keepAlways` (OBSERVED [S63]).
  - Export with `xcrun xcresulttool export attachments`. The subcommand exists in Xcode 26.6; `export object` is deprecated (OBSERVED locally [S68]).
  - Fix the status bar with `xcrun simctl status_bar <dev> override --time …` (OBSERVED locally [S68]).
- **Camera in the simulator.** The simulator has no camera; Apple says AVCam needs a device (OBSERVED [S25]).
  - Inject a `CaptureSource` that plays a fixture video, and enable it with launch arguments in UI tests.
  - Audit each of the 20 routes in light and dark mode at the largest accessibility text size (pass the content-size launch argument; the mechanism is UNVERIFIED in this pass).
  - The iOS 17 runtime is not installed (§0), so audits run on iOS 26.5 locally (INFERRED).

### 4.9 Background continuation for export, backup and analysis
- See §3.13 (OBSERVED [S64]). Apple names video export as an example workload.
- Drive uploads should use a background `URLSession` independent of this (INFERRED; Drive is covered in another research file).

### 4.10 Optional: on-device language model for session summaries
- The Foundation Models framework (`SystemLanguageModel`, iOS 26+, with an `availability` check) runs an on-device model (OBSERVED [S65]).
- Fit: turn already-validated numbers into a short plain-language summary, offline and on device, with no new measured claims. Only on Apple-Intelligence-capable devices, with a fallback template (INFERRED; device eligibility UNVERIFIED).

---

## 5. Screens that conflict with platform facts (INFERRED unless noted)

| Screen | Conflict or implication | Fix |
|---|---|---|
| #4 Setup: "Estimated space: 3.2 GB" | Must be computed. At 1080p60 HEVC, 3.2 GB is about 36 min; the 54-min sample match would be about 4.9 GB at Apple's 90 MB/min estimate [S19] | Show "≈5.4 GB per hour · measured after 30 s" |
| #5 and #6 Calibration and Recording (portrait mockups) | A full-court 16:9 frame needs a landscape phone with the ultra-wide lens | Landscape layouts for these two routes |
| #6 Pause icon | `pauseRecording()` is iOS 18+ [S2] | On iOS 17, pause = close the segment and start a new one |
| #6 "Video saved on this iPhone" | True only up to the last fragment or segment | "Saved through 12:40": exact with fMP4, approximate with MovieFileOutput |
| #6 "Phone warming · Analysis paused" | Matches the throttling ladder (§1.6) | Keep; also show the fps drop if it happens |
| #7 "You can leave this screen" | True for the screen; leaving the app pauses analysis below iOS 26 | Add "Analysis pauses if you leave JOVRA" (or BGContinuedProcessingTask on 26+) |
| #10 Replay overlay scoreboard | The animation tool is export-only [S33] | Use `AVSynchronizedLayer` or SwiftUI overlays during playback |
| #11 "Estimated from calibrated video" | Far-half resolution is 0.2–0.4 m per pixel | Uncertainty-aware bins; "Needs review" near edges |
| #12 "104 mph … Estimated" | ±10% at best, and only after radar validation (§3.9) | Show a ± range; hide until the gate passes |
| #13 "2D pose estimate" | Near player only; far player too small | Per-end availability |
| #14 "Sync at contact" | Feasible from audio onsets (§3.4) | Automatic sync with manual nudge |
| #20 "Microphone · Optional · Off" | Off disables hit, rally and sync analysis | State the consequence inline |
| #20 "Photos · Selected photos" | PhotosPicker needs no authorization [S35] | "Not needed for import" / "Add-only" |

---

## 6. API cheat-sheet

| Need | API | Minimum iOS | Key parameters and gotchas | Source |
|---|---|---|---|---|
| Record to file | `AVCaptureMovieFileOutput` | 4.0 | Delegate always called; check `AVErrorRecordingSuccessfullyFinishedKey` | [S1][S3][S5] |
| Crash-tolerant file | `movieFragmentInterval` | 4.0 | Default 10 s; set ≈2 s **before** recording; extra fragment at 2 GB | [S1][S5] |
| Recording guards | `maxRecordedDuration` / `maxRecordedFileSize` / `minFreeDiskSpaceLimit` | 4.0 | Stops with an error when reached | [S2] |
| Live size and duration | `recordedFileSize`, `recordedDuration` | 4.0 | Source for bitrate slope and remaining-time estimate | [S2] |
| Pause / resume | `pauseRecording()` / `resumeRecording()` | **18.0** | iOS 17: stop plus new file | [S2][S5] |
| File rotation | `startRecording(to:)` | 4.0 | On iOS, must `stopRecording()` first, so there is a gap | [S2] |
| Start PTS | `fileOutput(_:didStartRecordingTo:startPTS:from:)` | **18.2** | PTS on `synchronizationClock` | [S23] |
| Sync clock | `AVCaptureSession.synchronizationClock` | 15.4 | Map taps to media time | [S23] |
| Codec choice | `availableVideoCodecTypes`, `setOutputSettings(_:for:)` | 10.0 | Only keys from `supportedOutputSettingsKeys` (12.0) | [S18] |
| Writer fragments | `AVAssetWriter.movieFragmentInterval`, `initialMovieFragmentInterval` | 4.1 / **17.0** | Disabled by default; can't change after start | [S6] |
| fMP4 segments | `AVAssetWriter(contentType:)`, `outputFileTypeProfile`, `preferredOutputSegmentInterval`, `initialSegmentStartTime`, `flushSegment()` | 14.0 | `.mpeg4AppleHLS` / `.mpeg4CMAFCompliant`; segments delivered to the delegate | [S6][S7] |
| Segment data | `assetWriter(_:didOutputSegmentData:segmentType:segmentReport:)` | 14.0 | Implementing it stops normal file output | [S6] |
| Writer settings | `recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:)` | 11.0 | Query after the session is configured | [S18] |
| Data and movie together | Video/audio data output + movie output | 16.0 (link) | Watch `hardwareCost` (16.0) | [S5][S17] |
| Interruptions | `wasInterruptedNotification`, `interruptionEndedNotification`, `InterruptionReason` | 4.0 / 9.0 | Six reasons incl. system pressure | [S10][S5] |
| Runtime errors | `runtimeErrorNotification` + `AVCaptureSessionErrorKey` | 4.0 | Rebuild the session on `.mediaServicesWereReset` | [S10][S4] |
| Camera pressure | `systemPressureState` (level, factors) | 11.1 | Throttle `activeVideoMinFrameDuration`; `.shutdown` interrupts | [S11] |
| Thermal | `ProcessInfo.thermalState` + notification | 11.0 | Test with Xcode Device Conditions | [S12] |
| Free space | `volumeAvailableCapacityForImportantUsageKey` | 11.0 | Required-reason API (E174.1 / 85F4.1) | [S13][S14] |
| Keep awake | `isIdleTimerDisabled` | 2.0 | Reset after recording | [S15] |
| Screen dim | `UIScreen.brightness` (via the scene's screen) | 5.0 | Persists until the device locks; `UIScreen.main` deprecated in iOS 26 | [S15] |
| Battery | `UIDevice.batteryLevel` (enable monitoring), `isLowPowerModeEnabled` | 3.0 / 9.0 | Returns −1 if monitoring is off | [S15] |
| Format | `activeFormat`, `videoSupportedFrameRateRanges`, `unsupportedCaptureOutputClasses` | 7.0 / 11.0 | Setting the format moves the preset to `.inputPriority` | [S16] |
| Lock fps | `activeVideoMin/MaxFrameDuration` | 7.0 | Needs `lockForConfiguration` | [S16] |
| Auto fps off | `isAutoVideoFrameRateEnabled` | **18.0** | When true, setting frame durations throws | [S16] |
| Less blur | `activeMaxExposureDuration` | 12.0 | Resets on format change | [S16] |
| Ultra-wide | `.builtInUltraWideCamera` via `DiscoverySession` | 13.0 | Use the physical device for a stable homography | [S20] |
| Distortion | `isGeometricDistortionCorrectionEnabled` | 13.0 | On by default; keep it on | [S20] |
| FOV for intrinsics | `Format.videoFieldOfView` | 7.0 | Horizontal degrees | [S16] |
| Stabilization | `preferredVideoStabilizationMode` | 8.0 | Default `.off`; keep it off on a mount | [S20] |
| Smudge check | `setCameraLensSmudgeDetectionEnabled(_:detectionInterval:)` | **26.0** | Set before `startRunning` | [S21] |
| Rotation | `RotationCoordinator`, `videoRotationAngle` | **17.0** | The movie output writes a matrix; lock it at record start | [S22] |
| Mix audio | `configuresApplicationAudioSessionToMixWithOthers` | 18.0 | Keep false for analysis | [S24] |
| Stereo/FOA mic | `multichannelAudioMode`, `isWindNoiseRemovalEnabled` | 18.0 | Wind removal needs a non-`.none` mode | [S24][S5] |
| Exact seek | `seek(to:toleranceBefore:toleranceAfter:)` | 5.0 | `.zero` costs decode time; chain seeks (QA1820) | [S29] |
| Frame step | `AVPlayerItem.step(byCount:)`, `canStepForward/Backward` | 6.0 | Pause first | [S30] |
| Slow motion | `rate`, `defaultRate`, `canPlaySlowForward` | — / 16.0 / 6.0 | Use `play()` and `defaultRate` | [S30] |
| Thumbnails | `AVAssetImageGenerator.image(at:)` / `images(for:)` | 16.0 | Tolerance `.zero` for exact frames | [S31] |
| Clip export | `AVAssetExportSession.export(to:as:isolation:)`, `timeRange` | 13.0 (back-deployed) | Progress via `states(updateInterval:)` on 18.0 | [S32] |
| Burn-in overlay | `AVVideoCompositionCoreAnimationTool` | 4.0 | Offline only; `AVCoreAnimationBeginTimeAtZero` | [S33] |
| Composition (new) | `AVVideoComposition(configuration:)` | **26.0** | `AVMutableVideoComposition` deprecated in 26 | [S33] |
| Live overlay | `AVSynchronizedLayer` | 4.0 | For AVPlayer playback | [S33] |
| Import | `PhotosPicker(…, preferredItemEncoding: .current)` | 16.0 | No authorization; avoids transcode | [S35] |
| Save to Photos | `.addOnly` + `PHAssetResourceCreationOptions.shouldMoveFile` | 14.0 / 9.0 | Moves the file without a copy | [S34] |
| Share | `ShareLink` + `FileRepresentation` | 16.0 | — | [S34] |
| Trajectories | `VNDetectTrajectoriesRequest(frameAnalysisSpacing:trajectoryLength:)` | 14.0 | Stateful; length ≥ 5; fixed camera; timestamped buffers | [S36][S37] |
| Trajectory size filter | `objectMinimum/MaximumNormalizedRadius`, `targetFrameTime` | 14.0 / 15.0 | `min/maximumObjectSize` deprecated | [S36] |
| Offline video | `VNVideoProcessor` / Swift `VideoProcessor` | 14.0 / 18.0 | Cadence defaults to every frame | [S36][S42] |
| 2D pose | `VNDetectHumanBodyPoseRequest` / `DetectHumanBodyPoseRequest` | 14.0 / 18.0 | 19 points; subject ≥ ⅓ of the frame; use a region of interest | [S39][S42] |
| 3D pose | `VNDetectHumanBodyPose3DRequest` | 17.0 | Most prominent person only; 17 joints or none | [S40] |
| Contours | `VNDetectContoursRequest` | 14.0 | `maximumImageDimension` 512 by default; `detectsDarkOnLight` true by default | [S41] |
| Registration | `VNHomographicImageRegistrationRequest` / `VNTrackHomographicImageRegistrationRequest` | 11.0 / 17.0 | Camera-moved detection | [S41] |
| Sound classes | `SNClassifySoundRequest(classifierIdentifier: .version1)` | 15.0 | Includes `playing_tennis`; window ≥ 0.5 s | [S44] |
| FFT | `vDSP.FFT`, `vDSP.window`, `vDSP.DiscreteFourierTransform` | 13.0 / 15.0 | Spectral flux / HFC onsets | [S45] |
| Audio decode | `AVAssetReader` + `AVAssetReaderTrackOutput` | 4.1 | PCM Float32 mono | [S46] |
| Action model | Create ML Action Classification (`MLActionClassifier`, macOS) | — | ≥ 50 videos per class plus a negative class | [S43] |
| Live Activity | `Activity.request(attributes:content:pushType:)` | 16.2 | 8 h active / 12 h total; 4 KB | [S59] |
| Siri / Shortcuts | `AppShortcutsProvider`; `openAppWhenRun` → `supportedModes` | 16.0 / 26.0 | Camera needs the foreground | [S60] |
| Hardware buttons | `AVCaptureEventInteraction` / `onCameraCaptureEvent` | **17.2** / 18.0 | AirPods on iOS 26; volume up = secondary | [S57] |
| Camera Control | `AVCaptureControl`, `AVCaptureSlider` | 18.0 | `session.supportsControls` | [S58] |
| Lock-screen capture | `LockedCameraCapture`, `CameraCaptureIntent` | 18.0 | Extension target | [S58] |
| Workout | `HKWorkoutBuilder` + `.tennis` | 12.0 / 8.0 | Live session on iPhone needs 26.0 | [S61] |
| Charts | Swift Charts; `chartXSelection`; `Chart3D` | 16.0 / 17.0 / 26.0 | `accessibilityChartDescriptor` (15.0) | [S62] |
| Accessibility tests | `performAccessibilityAudit(for:_:)` | 17.0 | Audit types listed in §4.8 | [S63] |
| Screenshots | `XCUIScreenshot`, `XCTAttachment`; `xcresulttool export attachments` | — | Use `.keepAlways` | [S63][S68] |
| Background work | `BGContinuedProcessingTaskRequest` | **26.0** | User-initiated; report progress; GPU entitlement | [S64] |
| On-device summary | `SystemLanguageModel` (Foundation Models) | 26.0 | Check `availability` | [S65] |

---

## 7. Open questions and UNVERIFIED items to test on a device

1. The gap at a MovieFileOutput stop-and-start on iOS (ms) and the interruption-to-resume latency.
2. Whether changing `activeVideoMinFrameDuration` mid-recording keeps the same file or raises `.mediaChanged`.
3. Whether a crashed **iOS** `AVCaptureMovieFileOutput` file plays and seeks in AVPlayer **and** in Drive's web player without a remux.
4. Whether the movie output honors a custom bitrate or key-frame interval, and whether `outputSettings(for:)` contains `AVVideoAverageBitRateKey`.
5. Measured bitrate of `AVCaptureMovieFileOutput` per mode against the Settings estimates; battery drain per hour per mode; time to thermal throttle in direct sun.
6. Behavior with an incoming call that rings but is not answered, Siri, Control Center, and Notification Center (does the camera keep running while the app is inactive?).
7. Whether wind-noise removal or stereo capture changes hit transients; whether the built-in `playing_tennis` label fires reliably on phone audio.
8. Per-frame cost of `VNDetectHumanBodyPoseRequest` and of a trajectory request on the minimum-spec device.
9. Spectral-flux precision and recall on real fence-mounted recordings with neighbor courts.
10. Whether to move the floor from iOS 17 to iOS 18 (product decision; see Toolchain facts).

---

## Sources

Accessed 2026-10-07 unless noted. "doc" means developer.apple.com documentation, read through its DocC JSON or `.md` renderings.

- **[S1]** https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput/moviefragmentinterval and https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput: fragment semantics, the 10 s default, sample-table explanation, topics (orientation metadata track, codec settings).
- **[S2]** https://developer.apple.com/documentation/avfoundation/avcapturefileoutput (maxRecordedDuration, maxRecordedFileSize, minFreeDiskSpaceLimit, recordedFileSize, startRecording(to:recordingDelegate:), stopRecording(), pauseRecording()) and …/avcapturemoviefileoutput/usesprovideostorage: guards, the iOS stop-before-restart rule, pause on iOS 18, iOS 27 symbol.
- **[S3]** https://developer.apple.com/documentation/avfoundation/avcapturefileoutputrecordingdelegate/fileoutput(_:didfinishrecordingto:from:error:): always called, even when no data was written.
- **[S4]** https://developer.apple.com/documentation/avfoundation/averror-swift.struct/code and …/averrorrecordingsuccessfullyfinishedkey: error codes and the playable flag.
- **[S5]** Local iOS 26.5 SDK headers, `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/` (AVCaptureFileOutput.h, AVCaptureSession.h, AVError.h, AVCaptureInput.h, AVCaptureDevice.h, AVAssetWriter.h): fragment-interval details, iOS 16 output combinations, interruption reasons, recording-successful key, absence of iOS 27 APIs, wind-noise prerequisite.
- **[S6]** https://developer.apple.com/documentation/avfoundation/avassetwriter (movieFragmentInterval, initialMovieFragmentInterval, producesCombinableFragments, init(contentType:), preferredOutputSegmentInterval, initialSegmentStartTime, outputFileTypeProfile, flushSegment(), inputReceiver(for:)) and …/avassetwriterdelegate/assetwriter(_:didoutputsegmentdata:segmenttype:segmentreport:): writer fragment and segment APIs with availability.
- **[S7]** https://developer.apple.com/videos/play/wwdc2020/10011/ (WWDC20 "Authoring fragmented MPEG-4 with AVAssetWriter"): segment types, encoding versus passthrough, sync samples, priming, playlist notes.
- **[S8]** https://developer.apple.com/documentation/avfoundation/writing-fragmented-mpeg-4-files-for-http-live-streaming: Apple's fmp4Writer sample.
- **[S9]** Local experiment, 2026-10-07, macOS 26.6.2: `/private/tmp/claude-502/-Users-IDC2-5-jv/ios-tech/exp/` (writer.swift, writerav.swift, reader.swift, remux.swift, tracks.swift). Crash survival of fragmented .mov and fMP4 segments, A/V segments, truncated-segment metadata trap, passthrough remux.
- **[S10]** https://developer.apple.com/documentation/avfoundation/avcapturesession/wasinterruptednotification, …/interruptionendednotification, …/runtimeerrornotification, …/avcapturesession/interruptionreason: interruption and runtime error model and reasons.
- **[S11]** https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.property and …/systempressurestate-swift.class (level, factors): pressure levels, factors, `batteryStress`, frame-rate throttling advice.
- **[S12]** https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property and …/thermalstate-swift.enum; https://help.apple.com/xcode/mac/current/#/dev308429d42 ("Test under adverse device conditions"): thermal states and device-condition testing.
- **[S13]** https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey and https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api: free-space key and privacy-manifest requirement.
- **[S14]** https://ptkd.com/journal/how-to-fix-missing-api-declaration-for-disk-space-2026 and https://tessl.io/registry/dpearson2699/swift-ios-skills/3.6.1/files/skills/app-store-review/references/privacy-manifest.md (secondary, via search summary): disk-space reason codes E174.1 / 85F4.1 wording.
- **[S15]** https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled, …/uikit/uiscreen/brightness, …/uikit/uiscreen/main, …/foundation/processinfo/islowpowermodeenabled, …/uikit/uidevice/batterylevel: keep-awake, brightness persistence, `UIScreen.main` deprecation, power APIs.
- **[S16]** https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat, …/activevideominframeduration, …/avframeraterange, …/avcapturedevice/format/unsupportedcaptureoutputclasses, …/isautovideoframerateenabled, …/activemaxexposureduration, …/activecolorspace, …/format/isvideobinned, …/format/videofieldofview, …/isvideohdrenabled, …/avcaptureconnection/iscameraintrinsicmatrixdeliveryenabled: format, fps, exposure, color, FOV, intrinsics.
- **[S17]** https://developer.apple.com/documentation/avfoundation/avcapturesession/hardwarecost and https://developer.apple.com/videos/play/wwdc2022/110429/: hardware cost; iOS 16 simultaneous movie and data outputs.
- **[S18]** https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput/setoutputsettings(_:for:), …/supportedoutputsettingskeys(for:), …/availablevideocodectypes, …/avcapturevideodataoutput/recommendedvideosettings(forvideocodectype:assetwriteroutputfiletype:), …/recommendedvideosettingsforassetwriter(writingto:), …/alwaysdiscardslatevideoframes, …/avcaptureaudiodataoutput/recommendedaudiosettingsforassetwriter(writingto:): codec and settings rules.
- **[S19]** https://www.videoproc.com/iphone-video-processing/iphone-video-size-per-minute.htm (secondary, dated 2024-02-01): per-minute sizes as shown in iOS Camera settings.
- **[S20]** https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/builtinultrawidecamera, …/builtintriplecamera, …/builtindualwidecamera, …/virtualdeviceswitchovervideozoomfactors, …/isgeometricdistortioncorrectionenabled, …/format/geometricdistortioncorrectedvideofieldofview, …/avcaptureconnection/preferredvideostabilizationmode, plus the AVCaptureDevice topic list: lenses, switching, distortion correction, stabilization.
- **[S21]** https://developer.apple.com/documentation/avfoundation/avcapturedevice/setcameralenssmudgedetectionenabled(_:detectioninterval:), …/iscameralenssmudgedetectionenabled, …/cameralenssmudgedetectionstatus: lens smudge detection (iOS 26).
- **[S22]** https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator, …/avcaptureconnection/videorotationangle, …/isvideorotationanglesupported(_:): rotation (iOS 17).
- **[S23]** https://developer.apple.com/documentation/avfoundation/avcapturefileoutputrecordingdelegate/fileoutput(_:didstartrecordingto:startpts:from:) and …/avcapturesession/synchronizationclock: start PTS (18.2), sync clock (15.4).
- **[S24]** https://developer.apple.com/documentation/avfoundation/avcapturesession/configuresapplicationaudiosessiontomixwithothers, …/ismultitaskingcameraaccesssupported, …/avcapturedeviceinput/ismultichannelaudiomodesupported(_:), …/multichannelaudiomode, …/avcapturemultichannelaudiomode, …/iswindnoiseremovalenabled: audio session mixing, multitasking camera, multichannel and wind-noise APIs.
- **[S25]** https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app (`.md`): current AVCam (marked iOS 27 / Xcode 27), capture service, movie recording flow, LockedCameraCapture adoption, device-only.
- **[S26]** https://itunes.apple.com/lookup?id=989461317&country=us: SwingVision 11.9.67 (released 2026-09-27), minimum iOS 18.0, release notes on heat, interruption crash and low storage.
- **[S27]** https://www.itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf: ITF PAT-25-037 (issued 2025-10-31); fence-mounted iPhone, 60 fps, ML ball/court/player tracking; approval does not establish accuracy.
- **[S28]** https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf: court dimensions, line widths, net heights, ball diameter, run-back recommendations (6.40 m international / 5.48 m club), 25/90/120 s rule.
- **[S29]** https://developer.apple.com/documentation/avfoundation/avplayer/seek(to:tolerancebefore:toleranceafter:completionhandler:) and https://developer.apple.com/library/content/qa/qa1820/_index.html (via search summary): exact seeking and the chase-time scrubbing pattern.
- **[S30]** https://developer.apple.com/documentation/avfoundation/avplayeritem/step(bycount:), …/canstepforward, …/canplayslowforward, …/avplayer/rate, …/avplayer/defaultrate, …/avplayeritem/audiotimepitchalgorithm: stepping and rates.
- **[S31]** https://developer.apple.com/documentation/avfoundation/avassetimagegenerator (image(at:), images(for:), requestedTimeToleranceBefore): thumbnails.
- **[S32]** https://developer.apple.com/documentation/avfoundation/avassetexportsession (export(to:as:isolation:), states(updateInterval:), timeRange, configureForResumableExport()) and …/avassetexportpresetpassthrough: export APIs, back-deployment, iOS 27 resumable export.
- **[S33]** https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool (incl. init(postProcessingAsVideoLayer:in:), Configuration), …/avvideocomposition/configuration, …/avmutablevideocomposition, …/avvideocomposition/animationtool, …/avsynchronizedlayer, …/avcoreanimationbegintimeatzero: overlay burn-in rules and iOS 26/27 deprecations.
- **[S34]** https://developer.apple.com/documentation/swiftui/sharelink, …/photos/phassetresourcecreationoptions/shouldmovefile, …/photos/phaccesslevel/addonly, …/photos/phphotolibrary/requestauthorization(for:handler:): sharing and saving.
- **[S35]** https://developer.apple.com/documentation/photosui/photospicker, …/photosui/photospickeritem/encodingdisambiguationpolicy/current, …/photosui/phpickerviewcontroller, https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app, …/foundation/nsitemprovider/loadfilerepresentation(fortypeidentifier:completionhandler:): picker privacy, no-transcode, temp-file lifetime.
- **[S36]** https://developer.apple.com/documentation/vision/vndetecttrajectoriesrequest (+ init, trajectoryLength, objectMinimum/MaximumNormalizedRadius, minimumObjectSize, targetFrameTime), …/vntrajectoryobservation (detectedPoints, projectedPoints, equationCoefficients, movingAverageRadius), …/vnstatefulrequest, …/vnvideoprocessor, …/vnvideoprocessor/requestprocessingoptions/cadence, …/detecttrajectoriesrequest: trajectory API facts.
- **[S37]** https://developer.apple.com/documentation/vision/identifying-trajectories-in-video: stable-camera requirement, frame differencing, bounces create new trajectories, parameters, tennis ball needs 1080p.
- **[S38]** https://developer.apple.com/documentation/vision/building-a-feature-rich-app-for-sports-analysis: the Action & Vision pipeline (WWDC20 10099).
- **[S39]** https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images: 19 points, accuracy guidance (≥ ⅓ height, region of interest).
- **[S40]** https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images and …/vndetecthumanbodypose3drequest: 3D pose constraints.
- **[S41]** https://developer.apple.com/documentation/vision/vndetectcontoursrequest (+ contrastAdjustment, maximumImageDimension, detectsDarkOnLight), …/vncontour/polygonapproximation(epsilon:), …/vndetectrectanglesrequest/quadraturetolerance, …/minimumaspectratio, …/vnhomographicimageregistrationrequest, …/vntrackhomographicimageregistrationrequest: contours and registration.
- **[S42]** https://developer.apple.com/documentation/vision (`.md` symbol index) plus …/vision/videoprocessor, …/detectlenssmudgerequest, …/detecthumanbodyposerequest(/detectshands), …/generatepersoninstancemaskrequest, …/downloadableassetsrequest, …/trackobjectrequest: Swift Vision API availability (iOS 18 / 26 / 27).
- **[S43]** https://developer.apple.com/documentation/createml/creating-an-action-classifier-model, …/createml/mlactionclassifier, …/createml/mlsoundclassifier: Create ML action and sound classifiers.
- **[S44]** https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest (+ init(classifierIdentifier:), windowDuration, knownClassifications), …/snclassifieridentifier/version1, …/snaudiofileanalyzer; **plus a local run** on macOS 26.6.2 (`/private/tmp/claude-502/-Users-IDC2-5-jv/ios-tech/sa.swift`): 303 labels incl. `playing_tennis`, `playing_table_tennis`, `tap`, `thump_thud`; window 0.5–≈15 s, default 3.0 s, overlap 0.5.
- **[S45]** https://developer.apple.com/documentation/accelerate/vdsp/fft, …/vdsp/fft/init(log2n:radix:oftype:), …/vdsp/fft/forward(input:output:), …/vdsp/window(oftype:usingsequence:count:ishalfwindow:), …/vdsp/discretefouriertransform: DSP building blocks.
- **[S46]** https://developer.apple.com/documentation/avfoundation/avassetreader: decoding audio and video for offline analysis.
- **[S47]** Bello et al., "A Tutorial on Onset Detection in Music Signals," IEEE TSAP 13(5) 2005, https://www.cs.bu.edu/fac/snyder/cs583/Literature%20and%20Resources/bello_onset_tutorial.pdf (via search summary): spectral flux, HFC, peak picking.
- **[S48]** Huang & Cox, ICASSP 2010, https://kahlan.cvssp.org/acasva/Publications/ICASSP_2010.pdf, and Interspeech 2010, https://kahlan.cvssp.org/acasva/Publications/Interspeech-2010.pdf: broadcast tennis audio event detection (hits, umpire, crowd).
- **[S49]** IBM / Baughman et al., "Detection of tennis events from acoustic data" (SenSys 2019), https://researchweb.draco.res.ibm.com/publications/detection-of-tennis-events-from-acoustic-data (page unreachable; figures via search summary): F1 92.39% atomic events; about 80% point boundaries; CNN on MFCC with 20 ms frames.
- **[S50]** Decorte et al., "Multi-Modal Hit Detection and Positional Analysis in Padel Competitions," CVPRW 2024, https://openaccess.thecvf.com/content/CVPR2024W/CVsports/papers/Decorte_Multi-Modal_Hit_Detection_and_Positional_Analysis_in_Padel_Competitions_CVPRW_2024_paper.pdf: 2,377 annotated hits, SED-net CRNN, F1 92% at a 250 ms collar, error sources, audio-gated video detection.
- **[S51]** Zhang et al., "Ball hit detection in table tennis games based on audio analysis," ICPR 2006, https://web.ee.tsinghua.edu.cn/douweibei/en/lwcg/2276/content/5254.htm: energy peaks plus MFCC refinement, P 91% / R 73%.
- **[S52]** Sharma et al., "Wearable Audio and IMU Based Shot Detection in Racquet Sports," arXiv 1805.05456, https://ar5iv.arxiv.org/html/1805.05456: audio-only versus fused precision and recall.
- **[S53]** Gossard et al., "Sound-Based Spin Estimation in Table Tennis," arXiv 2409.11760v2, https://arxiv.org/html/2409.11760v2: high-pass onset timing (0.09–0.2 ms), related-work summary.
- **[S54]** D. Russell, tennis racket vibration modes, https://www.acs.psu.edu/drussell/Demos/tennis/tennis-1.html, plus a search summary of tennis impact-acoustics studies (https://sam.ensam.eu/handle/10985/26207, https://jcaa.caa-aca.ca/index.php/jcaa/article/download/948/669/1059): frame and stringbed mode frequencies; impulsive plus ringing structure.
- **[S55]** Huang et al., "TrackNet," arXiv 1907.03698, https://arxiv.org/abs/1907.03698: tennis ball tracking precision and recall (single video versus 10-video cross-validation), 640×360 input.
- **[S56]** Farin et al., "Robust camera calibration for sport videos using court models," SPIE 5307 (2004), https://research.tue.nl/en/publications/robust-camera-calibration-for-sport-videos-using-court-models/ (via search summary): Hough line candidates fitted to a court model; robust to occlusion and shadows.
- **[S57]** https://developer.apple.com/documentation/avkit/avcaptureeventinteraction (`.md`), …/avkit/avcaptureeventinteraction/init(primary:secondary:), …/swiftui/view/oncameracaptureevent(isenabled:action:), https://developer.apple.com/videos/play/wwdc2025/253/: hardware capture events, button mapping, AirPods (iOS 26), sounds.
- **[S58]** https://developer.apple.com/documentation/avfoundation/avcapturecontrol, …/avcaptureslider, …/avcapturesystemzoomslider, …/lockedcameracapture, …/appintents/cameracaptureintent: Camera Control and Lock Screen capture (iOS 18).
- **[S59]** https://developer.apple.com/documentation/activitykit, …/activitykit/displaying-live-data-with-live-activities, …/activitykit/activity/request(attributes:content:pushtype:), …/activitycontent/staledate: Live Activity rules and limits.
- **[S60]** https://developer.apple.com/documentation/appintents/appintent/openappwhenrun, …/appintent/supportedmodes, …/foregroundcontinuableintent, …/appshortcutsprovider, …/appshortcut: intent foreground modes and deprecations.
- **[S61]** https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype/tennis, …/hkworkoutbuilder (+ init(healthStore:configuration:device:)), …/hkworkoutsession (+ init(healthStore:configuration:)), …/hkliveworkoutbuilder: workout writing and iOS 26 iPhone sessions.
- **[S62]** https://developer.apple.com/documentation/charts, …/charts/chart3d, …/swiftui/view/chartxselection(value:), …/chartscrollableaxes(_:), …/charts/lineplot, …/charts/sectormark, …/swiftui/view/accessibilitychartdescriptor(_:): chart API availability.
- **[S63]** https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:), …/xcuiautomation/xcuiaccessibilityaudittype, …/xcuiautomation/xcuiscreenshot, …/xctest/xctattachment, https://developer.apple.com/videos/play/wwdc2023/10035/ (and https://wwdcnotes.com/notes/wwdc23/10035): accessibility audits and screenshots.
- **[S64]** https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest, …/bgcontinuedprocessingtask, …/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados: continued processing (iOS 26), GPU entitlement, progress and cancellation.
- **[S65]** https://developer.apple.com/documentation/foundationmodels and …/foundationmodels/systemlanguagemodel(/availability): on-device language model (iOS 26).
- **[S66]** https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup: purgeable directories; don't exclude content that is hard to re-create.
- **[S67]** https://developer.apple.com/support/app-store/: iOS 26 on 79% of all iPhones / 86% of recent iPhones (measured 2026-06-07).
- **[S68]** Local toolchain on this machine, 2026-10-07: `xcodebuild -version` (Xcode 26.6, 17F113); `xcrun simctl list runtimes` (only iOS 26.5); `xcrun xcresulttool export --help` (`attachments` subcommand present; `object` deprecated); `xcrun simctl status_bar --help`.
- **[S69]** https://developer.apple.com/forums/thread/98113: the pre-iOS 16 limitation (movie output and video data output not simultaneous), superseded by [S5]/[S17].
