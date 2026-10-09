# Bounded T17 native capture service

Scope: fresh singles capture metadata and the application RecordingSink transaction, part of #19 and the authorized core flow. No Capture screen, playback, library consumer, recovery, export, physical camera or full T17 completion is claimed.

Current main custody49856d2 is integrated in branch codex/t17-core-capture-service (integration ec553202f1426e88516ba96e8ba0ea427be7f061). T12 merged as35117e1 and is now integrated in 70617f786db1ee65654a8298fa54464d73c1a4bb; the application source tree did not change in this merge.

Native tests use only dedicated JOVRA-Codex-T07, iPhone17Pro/iOS26.5, UDID4265ADFD-39A3-4E71-8482-1945DDB5F899; own .derivedData; xcodebuild test -jobs2 -only-testing:JovraTests/LocalCaptureLibraryTests. Every accepted result was parsed by scripts/ios/xcresult-summary.py.

- 01 fresh-session compiler RED: application service API absent.
- 02 first GREEN attempt failed compilation because sport enum case was mistaken; retained as failed evidence.
- 02b corrected fresh-session GREEN:1 passed/0 failed. This intermediate seed still used fixed format/toss.
- 03 explicit-setup compiler RED: seed initializer lacked caller format/toss.
- 04 explicit-setup GREEN:2 passed/0 failed; choices preserved and camera origin is not Sample.
- 05 sink compiler RED: LocalCaptureLibrary did not conform to RecordingSink.
- 06 sink GREEN:3 passed/0 failed/0 skipped, result Passed. Reopening preserves recording, marks, Sample, blank match log and honest partial original state. The test intentionally has no video file and does not claim playable media.

- 07 exact integrated head1cb1648 native GREEN:3 passed/0 failed/0 skipped, result Passed. Current-main ScoringEngine and TimelineDiff compiled with the app service. This closes the earlier integration qualifier. The following publication commit only preserves this evidence.

Final tested source SHA256:
- Platform/Capture/LocalCaptureLibrary.swift:6564196b7ebab9e0d8c17d7b199627e4b315d09ff39dd5927c1ea68e164a96cc
- JovraTests/Capture/LocalCaptureLibraryTests.swift:8df2e3fce379e1c57986fb967295e2efbc6c7cef2529b563e047f9c8578f9983

The three tests use public service interfaces and isolated real temporary directories. Implementation hands recording and marks to one accepted SessionStore.saveCapture call. There is no analysis/network/account request. Fixture origin is mandatory Sample and new recording metadata never inherits sample match points.

Full native integration, full ticket acceptance and physical-device proof remain pending. Earlier T12 unit baseline does not prove this new service; this slice has focused hosted XCTest evidence only. Step5/Studio/Android/watch remains held.
