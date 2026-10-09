# T16 recovery — bounded container-layout prerequisite

This slice adds a public, streaming fragmented-MP4 container boundary checker. It reads only fixed-size box headers, rejects unbounded/overflowed or malformed extents, refuses a final symbolic link, and reports complete moof/mdat prefix boundaries plus an incomplete suffix. It does not decode video, adopt session metadata, change the original journal, infer crash duration or establish playback/recovery success. The literal test bytes describe container boundaries only; they are explicitly not playable-video fixtures.

- `01-layout-red.txt`: activated public missing-API compiler failure, FragmentedMovieLayout not found, exit 1.
- `02-layout-green.txt`: 2 Swift Testing public controls pass after adding the minimal bounded checker; selected XCTest runner correctly has zero cases. macOS package, jobs 2, warm cache.

Scanner, raw fingerprints/unchanged-byte custody, separate stable recovery receipt, decoded-prefix verification, atomic metadata adoption, force-kill loss measurement and media-services-reset recovery remain pending. Physical power loss and device crash-loss limits remain unverified. No T16 closure claimed by this prerequisite.

## Atomic metadata-adoption prerequisite

`SessionStore.applyRecoveredCapture` now atomically persists an explicit recording recovery report, original facet and available marks. It shares the existing capture persistence transaction, preserves player-edited marks and unrelated facets, retains nil unknown total duration, and forces Sample for synthetic camera capture. This seam trusts the scanner to verify media; it does not itself decode or scan.

- `03-atomic-adoption-red.txt`: missing public method, activated compiler failure.
- `04-atomic-adoption-green.txt`: one public fault/retry/adoption/idempotence control passes.
- `05-capture-handoff-regression.txt`: both new adoption and existing normal capture handoff pass (2 Swift Testing cases). Out-of-space preserves previous metadata bytes; retry carries the report and explicit unknown-suffix reason with edited and durable marks.
