# T26 import evidence · 2026-11-19

Simulator only: JOVRA-T26 (iPhone 17 Pro, iOS 27.2, Xcode 27.2). No physical device was used.
All media is synthetic: the committed import fixture set (T10) and passthrough copies of it tagged
"Sample Camera" with a Sample creation date of Oct 6, 2026. No real footage.

| File | What it shows |
|---|---|
| `swift-test-import.log` | `swift test --package-path ios/Packages/JovraMedia --no-parallel --filter "ImportPipelineTests\|FilesImport\|ImportFixtureProbeTests"`: 22 tests in 4 suites passed (durations normalised) |
| `ui-test.log` | `scripts/ios/ui-test.sh -only-testing JovraUITests/ImportSourcesUITests -only-testing JovraUITests/FilesImportUITests`: 7 passed, 0 failed (local paths removed) |
| `s07-*.jpg`, `reviews.txt`, `side-by-side.html` | light, dark and AX5 screenshots beside `design-reference/screens/07-import-processing.png`, one reviewer line each |

What the UI tests use instead of the system pickers: the `-importSelection` launch argument hands the
app the files a player would have picked, through the same pipeline and store. The real Files picker
presentation and cancellation is `FilesImportUITests`. The Photos picker was not driven in a test.

The interrupted-import UI test stalls one import just before publication (`-importStall`), confirms
its partial folder exists in the app container, terminates the app, relaunches it and confirms the
folder is gone and the session never appears.

The earlier Files-only evidence for #393 remains in `evidence/ios/26-files-import/`.
