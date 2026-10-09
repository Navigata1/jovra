# T15 bounded capture package review

This is a package implementation candidate, not a completed T15/device acceptance verdict. It adds the real sample-buffer capture pipeline, atomic capture journal, synthetic FixtureCamera, device-budget policy seams, and typed recording handoff. Native UI wiring, T16 startup recovery scanning, T14 playback, and physical-device acceptance remain separate work.

## Implemented boundary

CameraSource and FixtureCamera both send CMSampleBuffer video/audio through CaptureEngine to the same AVAssetWriter encoder. The fixture is decoded and encoded again; its MP4 is not copied to stand in for capture. H.264/AAC fragmented MP4 bytes are synchronized before journal confirmation advances. The writer uses the muxed Apple HLS MP4 profile; the single-track CMAF profile failed with audio and is not used.

CaptureJournal writes canonical typed JSON by temporary-file write, file synchronization, atomic POSIX rename, and directory synchronization. Segment intent precedes file creation. Reopening, injected pre-replace failure, denied microphone, visible userPaused/interruption gaps, activity notifications, thermal events, court preview policy, clean budget shutdown and durable manual notes are exercised. Stop decodes every video frame before final metadata is handed to RecordingSink. Audio track presence is checked; audio synchronization accuracy is not claimed.

Public integration: prepare returns PreflightReport; start accepts a precreated session ID/folder; statuses supplies bounded updates; pause/resume/interrupt/stop manage segments; refreshBudget is explicitly called by the owner; markPoint adds journal marks. RecordingSink.saveRecording receives SessionRecording and the final durable journal marks in one callback. The owning route must persist both in one SessionStore transaction; it must preserve preexisting marks and deduplicate mark IDs. engine.recordedMarks remains available for preview. CaptureActivity stays active through pause and closes before the asynchronous store handoff. Originals are excluded from device backup when their directory is created; existing backup choices are preserved.

## Evidence and reproduction

Before latest-main reconciliation: 28-media-final.txt has 69 passing media tests across 13 suites; 25-core-full.txt has 33 passing core tests across 4 suites. 17-fixtures-check.txt verifies all 19 source fixture hashes. 29-recorded-session-reference-green.txt independently validates the emitted sample session through the Python schema/reference validator. Latest-main reconciliation against approved main 5456fbf is in 30–32. Final authoritative results after the atomic recording/marks handoff and root review corrections are 39 (34 Core tests), 40 (70 media tests), 41 (full reference validator), and 36 (97 Python tests). The resumed-source failure control is red in 38 and green in 40; journal time semantics are red in 37 and green in 39. 33 is atomic handoff interface red; 34 is its first full green run.

Run from the isolated worktree:

```sh
python3 scripts/media/render.py --check
swift test --package-path ios/Packages/JovraCore --scratch-path .build/core-capture
JOVRA_CAPTURE_EVIDENCE_DIR="$PWD/evidence/ios/t15-capture" swift test --package-path ios/Packages/JovraMedia --scratch-path .build/media-capture
```

sample-journal.json and sample-session.json are actual emitted typed metadata, labeled synthetic Sample. captured-media-manifest.json records the retained local output hash, size, decoded frames and saved-through time. The video is retained locally at .cache/capture-evidence/sample-fixture-60s.mp4 (gitignored); it is not a committed binary or user footage. The test records 60 seconds by looping the 12-second source five times through the writer with a virtual clock. It yields 1,800 decoded video frames and exactly 60 seconds of confirmed video; the AAC asset tail is approximately 9 milliseconds longer.

The temporary reference-validation probe copies sample-session.json to an otherwise absent spec/fixtures/records/session.capture-probe.json, runs scripts/spec/validate.py, then removes only that temporary file. Original fixtures are unchanged. The initial probe (26) failed because its test scaffold inherited unrelated calibration/derived/sample bundle references; the corrected emitted standalone practice session is validated in 29.

## Red/green custody

Retain unsuccessful attempts as diagnostic evidence. 01 and 06 are missing-interface red tests; 12 is pause/gap red; 14 is budget-interface red; 19 is thermal-interface red; 22 is durable-mark red. Corresponding successful slices are 03/04, 11, 13, 15, 20 and 23. File 02 is an unsuccessful compile despite its green filename (POSIX open name collision); 05 is stale merge markers; 07–10 are writer/profile/timing attempts; 16 is a macOS/iOS conditional compile error fixed in 18. Files 24/25/28 are full successful suites. Filenames alone are not pass claims.

## Explicit remaining acceptance

No iOS native build, simulator UI run, or physical camera test was performed in this slice. Camera permission flows, actual lenses/focus/exposure/WB locks, media-services reset, physical interruption behavior, portrait/orientation policy and native preview integration still require native/device verification. Critical thermal downgrade above 30 fps is implemented but not exercised by the fixed 30 fps fixture. The storage estimate currently describes one hour at the requested bit rate; supportedPresets contains the selected preset, not an exhaustive native format inventory. Runtime budget observation/timing and helper suspension are owner responsibilities.

A source refusing to restart is now returned to paused with prior finalized media intact; its newly intended segment remains unfinalized for T16 recovery disposition. Journal public controls reject overlap, duplicate paths, unfinalized predecessor segments and checkpoints inconsistent with the segment timeline (exact integer-product comparison within one millisecond).

Process-kill crash recovery, decodeable truncation, the physical <=3-second loss budget, force-kill fault tests, power-loss durability, audio/video synchronization, low-power behavior and battery/endurance tests are unverified. A complete fragment being fsynced is the durable journal basis; this is not proof of a process-killed file being recoverable. T16 must reconcile unfinished AND finished journals when SessionStore metadata is stale (including a failed sink handoff). Capture stop failure preserves the journal and source files but does not yet expose a recovery scanner or retry workflow. CaptureActivity integration with background import/analysis/export is a subsequent owner task. This candidate must not close the whole T15 ticket based on package tests alone.
