# T15 capture engine: closing the package acceptance gaps

Ticket #17. Package code only: no screen, no simulator and no physical device were used.

## What already existed on main (Codex PRs #337, #338, #340, #341)

CaptureEngine, CaptureJournal (write-ahead, atomic replace with fsync), CaptureSegmentWriter (fMP4 fragments
about 2 s long, checkpoint only after the bytes are synchronized), FixtureCamera (virtual clock, injected
interruptions), CameraSource (device adapter), DeviceBudget with FakeDeviceBudget and LiveDeviceBudget,
CaptureActivity, RecordingSink, and the app's `LocalCaptureLibrary` sink, which writes to SessionStore. Earlier
evidence is in `evidence/ios/t15-capture`, `t15-stack` and `t15-directory-durability`.

## What this change adds

| Gap on main | Change | Red | Green |
|---|---|---|---|
| The thermal frame-rate downgrade could never run: FixtureCamera refused any rate other than the source rate | FixtureCamera decimates whole-number ratios (60 to 30 fps) with retimed frame durations | 03 | 04 |
| Every engine had its own CaptureActivity, so a processing or upload worker had to resubscribe per recording | `CaptureEngine(..., activity:)` accepts one app-lifetime signal | 01 | 02 |
| No crash hook | `simulateProcessDeath()` (internal, tests only): the segment is not closed, the journal is not finished, the sink is not called | 05 | 06 |
| The saved-through heartbeat was only checked at stop | A gated injected clock stops the test mid-recording and reads the journal on disk | 05 | 06 |
| The emitted session was validated by a probe that copied a file into `spec/` | `scripts/spec/validate.py --document <path>` (repeatable) plus `test_validate_document.py` | 07 | 08 |

These controls passed on their first run because the behaviour already existed: pause and resume alone, the
full journal fold reaching the sink, a media-services reset, low storage or low battery mid-recording, and the
fake and live DeviceBudget readings (09). They are acceptance controls with literal expectations.

## Files

- `10-media-full.txt`: `swift test --package-path ios/Packages/JovraMedia --no-parallel`. JovraMediaTests 64
  tests in 9 suites, JovraBenchmarkTests 37 tests in 7 suites, all passing. 23 of these are capture tests: 16 for
  the engine (8 new) and 7 for recovery.
- `12-core-full.txt`: JovraCore, 67 Swift Testing tests in 5 suites and 12 XCTest tests, all passing.
- `13-spec-tooling-tests.txt`: 103 Python contract-tooling tests, OK. `14-spec-validate.txt`: the repository validator passes.
- `11-reference-validator-emitted-sessions.txt`: the two emitted sessions, validated together with every
  repository fixture, PASS, with 2 external documents.
- `15-compile-generic-platform-iOS.txt` and `15-compile-generic-platform-iOS-Simulator.txt`: `xcodebuild build
  -scheme JovraMedia` for `arm64-apple-ios17` and the simulator, including the UIKit branch of LiveDeviceBudget.
  BUILD SUCCEEDED for both. This shows that the code compiles, not that it behaves correctly on a device.
- `16-repeat-runs.txt`: the 8 new tests, run 3 times, all passing.
- `sample-journal.json`: the journal of the 60 s FixtureCamera recording. It is labelled Sample and is synthetic.
  `lastConfirmedMediaTime` is 36000/600 = 60.000 s, and there are 1,800 decoded frames.
- `pause-resume-journal.json`: two segments, one `userPaused` gap from 3000 to 90000 ms, and one manual mark.
- `sample-session.json` and `pause-resume-session.json`: those recordings in a visibly Sample practice session,
  as RecordingSink received them.

No media binaries are committed.

## Reproduce

```sh
python3 scripts/media/render.py --check
JOVRA_CAPTURE_EVIDENCE_DIR="$PWD/evidence/ios/t15-capture-engine" \
  swift test --package-path ios/Packages/JovraMedia --no-parallel
python3 scripts/spec/validate.py --document evidence/ios/t15-capture-engine/sample-session.json \
  --document evidence/ios/t15-capture-engine/pause-resume-session.json
```

## UNVERIFIED

Device capture is UNVERIFIED until the hardware phase. That covers CameraSource, ultra-wide lens selection,
the locked frame rate, stabilization off, and focus, exposure and white-balance locks after framing. It also
covers real interruptions (calls, Siri, other camera apps), a real media-services reset, real thermal, battery
and Low Power Mode readings, AV sync, endurance, and the crash-loss budget after a killed process.
`simulateProcessDeath` emulates a crash inside one process. It is not a process kill or a power loss. Recovering
the torn prefix it leaves behind is T16.
