# T16 recovery — bounded container-layout prerequisite

This slice adds a public, streaming fragmented-MP4 container boundary checker. It reads only fixed-size box headers, rejects unbounded/overflowed or malformed extents, refuses a final symbolic link, and reports complete moof/mdat prefix boundaries plus an incomplete suffix. It does not decode video, adopt session metadata, change the original journal, infer crash duration or establish playback/recovery success. The literal test bytes describe container boundaries only; they are explicitly not playable-video fixtures.

- `01-layout-red.txt`: activated public missing-API compiler failure, FragmentedMovieLayout not found, exit 1.
- `02-layout-green.txt`: 2 Swift Testing public controls pass after adding the minimal bounded checker; selected XCTest runner correctly has zero cases. macOS package, jobs 2, warm cache.

Scanner, raw fingerprints/unchanged-byte custody, separate stable recovery receipt, decoded-prefix verification, atomic metadata adoption, force-kill loss measurement and media-services-reset recovery remain pending. Physical power loss and device crash-loss limits remain unverified. No T16 closure claimed by this prerequisite.
