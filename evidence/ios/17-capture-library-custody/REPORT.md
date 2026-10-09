# Bounded native capture coordinator and library custody

Part of T17/T20 and the authorized native core flow; full tickets remain open. One existing SessionStore actor is shared with MediaLibrary. Read-only filtered list and confined file/folder access preserve originals. A native observable coordinator controls the existing capture engine and atomic sink, with explicit chosen setup/preset/microphone and real status; a saved result is published only after stop verification and sink commit.

Public TDD evidence:
-01 missing folder/file/query compiler RED;02 service GREEN4 passed/0 failed.
-03 initial coordinator RED also caught a test async-autoclosure syntax mistake; repaired before03b qualifying absent NativeCaptureCoordinator compiler RED.
-04 initial implementation failed strict actor deinitializer checking; repaired with an owned ARC subscription that cancels its task without crossing actor isolation.
-04b compilation caught a non-Sendable XCTest self crossing to an async helper; the independent decoder helper is now static.
-04c GREEN5 passed/0 failed/0 skipped, result Passed, two classes: LocalCaptureLibraryTests4 and NativeCaptureCoordinatorTests1. All failed receipts/logs are preserved.

Owned native simulator: JOVRA-Codex-T07, iPhone17Pro/iOS26.5,4265ADFD-39A3-4E71-8482-1945DDB5F899; own .derivedData; xcodebuild test -jobs2 selecting only these two classes. Accepted receipts were parsed failclosed with scripts/ios/xcresult-summary.py.

The actual capture test streams the bundled synthetic FixtureCamera through the same AV writer, records4s, stops, reopens the app library and fully decodes120 saved frames. Video is finalized, saved, silent when microphone permission is denied, mandatory Sample and has no inherited sample match points. Output differs from source bytes. This proves simulator capture/service integration, not native screen UI, AX, physical camera or endurance.

The236KB source MP4 and truth/render JSON are byte-for-byte from the existing synthetic corpus and hash-bound in source-custody.json. Source is copied only into app resources; captured sessions re-encode its decoded samples. No network/account/analysis runs. Plain-byte custody test is separate and makes no video-playability claim.

After04c, main's published directory durability fixes were integrated in c74dcaf5f2e8acb54a03cf9e00078e3a78037a7d. App source hashes are unchanged, but the changed Core/Media durability code requires a focused exact-head rerun before publication acceptance. 05 exact-head GREEN now closes that qualifier:5 passed/0 failed/0 skipped, result Passed, at6fa5c86330836d3c2b7420b2134a893d1407fd36 with main3ae5caa directory durability compiled. Production source did not change after05; publication adds evidence only.

Capture UI, library/replay consumers, correction and all exports remain pending; step5/Studio/Android/watch held.

## Transport repair

The first push was rejected by GitHub because the raw native archive reached111MB. No PR/remote branch was created. Old reviewed/tested source6fa5c863 and evidence-headddcf3db are retained locally on codex/t17-capture-custody-raw-proof; full raw receipts and archive remain local. The unpublished transport history is rebuilt from main3ae5caa with the same application/test/resource bytes, readable logs, both reviews and SHA256 manifest; raw tar is excluded from Git transport. New-source-head review/test rebinding is required before final publication acceptance. No claim transfers solely from byte identity.

## Rebuilt-head publication acceptance

Independent Standards and Spec explicitly rebound source to1882946822a7b5641e31411871b4fe8878c6a5f4 against main3ae5caa, with zero findings. 06 exact native rerun at that head passed5/0failed/0skipped, two genuine classes, with the same actual four-second/120-frame fully decoded recording control. The result was parsed failclosed. No iOS source/test/resource bytes changed between6fa5c863 and1882946. Readable proof and a SHA256 manifest travel in Git; both raw native archives remain local and were read back fully. Publication adds evidence only. No full ticket, UI, AX or physical-device acceptance is inferred.
