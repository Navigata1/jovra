# T16 crash recovery: forced termination, torn segments, partial reports and media-services reset

Issue #18. Package evidence for `ios/Packages/JovraMedia` on macOS (`swift test`), with the synthetic fixture
camera only. Every movie here was produced by `FixtureCamera` through the real `AVAssetWriter` segment
pipeline; no real footage, frame or audio is involved, and no movie is committed (journals, receipts and
session JSON only).

## What each acceptance criterion rests on

| Criterion | Test (`Tests/JovraMediaTests/Capture/…`) | Result |
| --- | --- | --- |
| Forced termination mid-segment recovers every complete fragment, ≤ 3 s lost, decode-to-end, `savedWithGaps` | `Recovery/CrashRecoveryTests.swift` `forcedTerminationMidSegmentRecoversEveryCompleteFragmentWithAtMostThreeSecondsLost` | crashed at 7.0 s, heartbeat 6.0 s, recovered 6.0 s, **measured seconds lost 1.0**; 180 frames decoded independently by `AVAssetReader`; gap `6000–7000 other`; `savedWithGaps` |
| Torn segment truncated, not discarded | `tornSegmentIsTruncatedToItsLastCompleteFragmentNotDiscarded` × `torn-mid-fragment`, `zero-filled-tail` | file kept, cut exactly at the last complete fragment (bytes equal the torn file's prefix), 120 frames decode, `truncatedSegmentIds: ["segment-0"]` |
| Unrecoverable segment reported with its reason, others kept (`partial`) | `unrecoverableSegmentIsReportedWithItsReasonWhileEveryPlayableSegmentIsKept` | `segment-1` kept (60 frames), `originals/segment-0.mp4` named with its reason and left on disk byte-for-byte, outcome `partial`, original facet `partial` |
| Media-services reset rebuilds the session and resumes into a new segment with a gap | `mediaServicesResetRebuildsTheCaptureSessionAndResumesIntoANewSegmentWithARecordedGap`; bound: `CaptureEngineAcceptanceTests.swift` `recurringMediaServicesResetsStopBeingRebuiltAfterTheLimitAndLeaveTheRecordingPausedNotEnded` | no caller resume; segments `[0, 1500]`, gap `1000–1500 cameraError`, source prepared twice; a recurring reset is rebuilt 3 times, then the engine waits paused (recording not ended) |
| Scanning twice is idempotent | `runningTheScannerTwiceChangesNothingTheSecondTime` | second result equal; every file's bytes and modification date unchanged (torn case, so the truncation itself is covered) |

## Files

- `01-crash-recovery-red.txt`: the five new tests before the implementation, all failing (unfinished journals
  were refused; nothing rebuilt after a reset). The red run trapped on an unguarded index in the reset test's
  arrangement; that arrangement now uses `#require` and fails without trapping.
- `02-media-full.txt`: `swift test --no-parallel` for the whole package with this change (`JovraMediaTests` 72
  tests, `JovraBenchmarkTests` 45). One unrelated case failed in that run: `DecodedFrameHashTests` for
  `corpus/static-s133` decoded 26 999 of 27 000 frames while the machine's load average was above 200. The same
  file decodes all 27 000 frames in a standalone `AVAssetReader` count, and `render.py --check` reproduced its
  committed hash. `05-decoded-frame-hash-rerun.txt` is the suite rerun alone.
- `03-reference-validator-recovered-sessions.txt`: `scripts/spec/validate.py --document` over the three adopted
  sessions below: PASS. `04-reference-validator-negative-control.txt`: the partial session with an empty
  unrecoverable reason is refused (the check can fail).
- `forced-termination/`, `torn-segment/`, `partial-recovery/`: the journal exactly as the killed engine left it
  (`capture-journal.json`, `finished: false`), the scanner's receipt (`capture-recovery.json`, the
  partial-recovery report with its input fingerprints and, for the torn case, the torn and kept byte counts and
  the torn file's SHA-256) and `recovered-session.json` (the result as a visibly Sample session document).
- `06-app-startup-recovery.txt`: the hosted `StartupRecoveryTests` on the `JOVRA-T16` simulator, run because the
  app's launch reconciliation calls this scanner: 1 passed.
- `07-recovery-tests-final.txt`: every recovery and crash test (14 tests, 27 cases) on the final source, after the
  test-arrangement guards; the JSON folders come from this run.

## How recovery decides

- A finalized segment is never altered: it decodes whole and agrees with the journal within 1 ms, or it is
  reported unrecoverable.
- A segment the process was still writing is checked with `FragmentedMovieLayout`. With an incomplete tail (a
  partial fragment, or a zero-filled extent after the last saved fragment), its prefix is cloned (APFS
  copy-on-write), truncated and decoded to the end. The receipt is written, then the clone replaces the torn
  file in one atomic rename, after a check that the torn file did not change. Only bytes after the last complete
  fragment are dropped; if that prefix does not decode, the file is left as it is and reported.
- After a forced termination the unsaved stretch is a gap (`other`) from the end of the saved media to the latest
  point the journal proves (a mark, an event or the heartbeat). Its true length is unknowable, so it can be zero.
- Fixed reason text and the receipt's carried-over truncations keep a repeated scan byte-identical.

## Not established here

- The hardware crash-loss bound (ADR-0010) and power-loss safety: device-pending. These runs use the engine's
  in-process crash hook and a fixture camera, not a killed app on an iPhone.
- A real `AVCaptureSession` media-services reset: device-pending. The fixture injects the same
  `CaptureSourceFailure.mediaServicesReset` the camera adapter raises.
- The relaunch UI for recovered, partial and torn sessions is T17. The app adopts complete-outcome recoveries
  at launch through the existing path; partial outcomes are still counted as needing attention there.
