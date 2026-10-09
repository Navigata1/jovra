# Bounded local clip export

The public primitive exports one local video segment over an exact half-open `CMTimeRange`, relative to the AVFoundation video track timeline. It re-encodes, preserves the display transform, strips source metadata and omits audio unless explicitly selected. It refuses an existing destination, fully decodes staged output, flushes its file bytes, publishes without overwrite, and flushes the parent directory before acknowledging completion. Failed publication flush leaves the completed file intact and throws.

Public TDD: intended absent-API compiler red is retained in01. First implementation compile failed on an Apple API argument label (02), corrected in03. The three focused tests (five parameter cases) passed: frame-counter exports contain exactly17...46 at60 and240fps, explicit/default audio tracks are correct, and invalid range/existing destination preserve bytes.

The added real2second FixtureCamera source test initially asserted a nonzero AVFoundation track start. Full suite04 honestly failed that assumption. AVFoundation applies an edit list while ffprobe sees the raw0.043333 mux offset. Corrected test inspects the actual one-second/30-frame exported media. Full suite05 passes75tests. Exporter production code did not change for this test repair.

Independent ffmpeg complete decode, burned-counter inspection and ffprobe track checks passed on all six retained outputs (06); hashes and byte counts are in retained-media-manifest.json. Actual captured source has60 frames/raw0.043333 start; its exported clip has30 frames, starts0 and lasts1second without audio. This proof uses synthetic media, no private player footage.

Latest main directory-durability code3ae5caa is integrated. The fresh combined Media gate07 passes76tests in14suites; independent ffmpeg inspection08 passesall6integratedfiles. Retained final synthetic MP4s are under media/ with integrated-media-manifest.json hashes. Earlier75-test evidence remains bound to its previous package composition. Production source is unchanged from reviewedc41d7b8; separate final Standards/Spec rebind precedes publication.

FullT36 remains open: multi-segment selection, durable progress/relaunch status, per-session event-log-version export records, clip sheet/Photos permissions/junior copy policy and full visual/accessibility criteria require further integration. No Studio/cloud/Android/watch work or physical-device/signing/store readiness is claimed.
