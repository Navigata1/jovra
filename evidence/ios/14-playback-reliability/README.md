# T14: playback reliability follow-up

This follow-up is based on the exact PR #442 head `f765423e1cf14197d324567885515dcc9bedddbf`. The tested source is `343bc5eadb5e3b1a4f618f99e47ad8dd3c1c6466`. The original PR and its checkout were not changed.

- **Frame identity:** the proxy presented burned-in frame 399. The red control confirmed that frame remained over the player after a forward step to 400 and a scrub to 410. Both now settle with no stale still and the expected decoded player frame. The original same-frame handoff test still passes.
- **Cancellation:** the red control closed a controller before proxy publication and found a leftover file. Cancellation now reaches the encoder, and the completed cancellation leaves neither a final proxy nor a partial file. The controller also refuses to start a late proxy build after closure.
- **Item clock:** a passthrough MOV with a verified half-second leading empty edit reproduced an end time of 25/60 instead of 55/60 and no video frame at the requested A. The green control checks the decoded frame at A, the item-clock stop time, and an actual wrap from near frame 24 back to frame 6. The zero-start loop still passes.

The complete serial macOS run exited 0: 97 media tests in 15 Swift Testing suites, 45 benchmark tests in 8 suites, and one XCTest timing check. The timing iterations averaged 7.61–8.78 ms per backward step on this Mac; the controller measured 6.91 ms. The full Media suite took 281.882 seconds. New tests use existing synthetic fixture bytes and do not add media to Git.

```sh
swift test --package-path ios/Packages/JovraMedia --scratch-path "$PWD/.scratch/media-build" --jobs 2 --no-parallel
```

`results.txt` preserves key lines from the focused red and green runs and the full serial suite. The first shifted-fixture setup probe is retained separately in `.scratch/06-shifted-loop-red.log`; it exposed how AVFoundation counts an empty leading edit and is not the behavioral red. The behavioral red is `.scratch/07-shifted-loop-red.log`.

No simulator, physical device, or current-main integration run was performed. The original PR's accessibility evidence remains separate, including the hosted substitute for its requested VoiceOver XCUITest and the timeline increment gap. This slice does not close issue #16.

## Ordered proxy publication

The boundary correction is tested at `49da8e17793876456a4c069699d7730fdb7aece6`. A 240 fps synthetic encode produced a complete movie while the controller was held on its main actor and still showed `building`. Before the fix, the worker published the movie and Close left it behind. Now the worker returns a temporary movie, and the controller accepts it and atomically renames it on the same actor as Close. Closing before handoff discards the temporary movie. Closing after handoff preserves the same cached bytes.

The final focused macOS run passed 15 Swift Testing tests in two suites and one XCTest timing test. The controller averaged 6.27 ms per backward step. This run covers the controller Close boundary. Standalone proxy builds retain cooperative task cancellation.

```sh
swift test --package-path ios/Packages/JovraMedia --scratch-path "$PWD/.scratch/media-build" --jobs 2 --no-parallel --filter 'ShortGOPProxyTests|ProxyBackwardStepTimingTests|PlaybackControllerTests'
```

The full Media and benchmark receipts above remain tied to the earlier source. The first boundary probe, which observed the movie before the worker returned and passed before the fix, is retained as `.scratch/10-proxy-handoff-red.log`. The actual pre-fix failure is `.scratch/11-proxy-handoff-red.log`. The final focused run is `.scratch/13-proxy-handoff-final.log`.
