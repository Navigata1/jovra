# Independent bounded clip Spec review

SPEC ACCEPT exact final candidate `39902dc96c55297776e6d0d865aa928ea02e3fd1`. Rebound from `c41d7b876f418fcc6e3b82012f713f9162a9c491`; independently checked the two declared source/test SHA-256 values and all six retained output sizes/hashes. Production and public tests are byte-identical to the prior reviewed candidate. Final changes are evidence only.

Bounded single-segment export matches the supplied half-open rational range on the AVFoundation track timeline, re-encodes for an external share, preserves the display transform, strips metadata, defaults to no audio and includes audio only explicitly. Staged output is completely decoded before publication, flushed and moved without overwriting; failed publication-directory acknowledgment preserves the completed file. Existing destination and invalid range controls preserve bytes.

Inspected final combined directory-package receipt: 76 Media tests pass in 7.152 seconds. Producer's independent ffmpeg/ffprobe controls verify all six retained synthetic files: burned frames 17...46 (30 frames) at 60 and 240 fps; audio off/on tracks; real FixtureCamera-produced source with raw mux offset and a normalized one-second, 30-frame silent exported clip. I independently verified file custody, not reran the native compiler or the full Media suite. No direct physical-device or power-loss acceptance is inferred.

No bounded Spec findings. Full T36 remains open for multi-segment export, persistent progress/relaunch, event-log-version export records, score overlays, clip sheet/Photos permissions, junior audio policy and visual/accessibility integration. Studio, backend, Android and watch work stay outside this acceptance.
