---
module: bundle
reference: [spec/reference/studio/bundle.py]
cases: [spec/reference/studio/cases/bundle_cases.py]
kinds: [sample-truth]
coverage: covered
swift: pending
kotlin: pending
---

# Bundle: the Sample project and its cross-record rules

`spec/reference/studio/bundle.py` checks the Sample project `sample-court-day` as a whole (the lock against the
manifest, sync coverage offered for cutting, plans against keepers and the reference catalog, quotes, reservations,
jobs and films bound to one output) and builds the trusted EDL context and the capture hints from stored records.
`spec/reference/studio/cases/bundle_cases.py` writes the `sample-truth` vectors and registers the self-test
`bundle-cross-record`: `bundle.check_all` accepts the Sample project and refuses each deliberate mutation in its
`MUTATIONS` list with the expected code (a later bundle ticket adds a mutation there, not in the validator). `python3
scripts/spec/validate_studio.py --list` prints the current case count of every kind below and its Swift and Kotlin
status.

## The Sample project's records

- **Records (31), project `sample-court-day`:**
  - Inputs: the source manifest (three 60-min match sources at 3.6 GB each, 10.8 GB in total, plus two B-roll
    sources), the sync map (Camera 2 fitted to +119.837 ms and 300.102 ppm, which rounds to +120 ms and 18 ms/min,
    reviewed after its start/middle/end checkpoints, while the fitter alone gives `estimated`, which is what screen 26
    shows before "Confirm sync"; Camera 3 left needs-review), the keeper and B-roll catalogs, the reference catalog
    (scores, stat, notes, cues, annotation, one narration consent, one music rights record) and the project lock.
  - Story briefs: Court Memories, and Progress (12/30 → 18/30, +20 percentage points).
  - Seven EDLs:
    - the screen-36 storyboard, with Camera 2 at 00:12.400–00:18.600 placed at 00:12.000–00:18.200 (6.2 s);
    - its clean alternate;
    - the final Court Memories film plan (04:18 with chapters of 42 + 141 + 75 s);
    - Coach's Cut, with a freeze, a ½× replay, a hold-bed and consented narration;
    - Rally Pulse 9:16, with a moving reframe, music under a rights record, and its clean alternate;
    - Match Broadcast, with strict order and a post-point far-baseline replay.
  - Other records: three observations, three lessons (4/2/3 clips; 10 and 20 drills done; a five-clip review
    pending), the camera roster (screen 23, invite code JVR-482), storage providers (screen 40), three quotes (the
    screen-37 illustrative $4–$8 with a $12 cap, which cannot be accepted, and two accepted test quotes), two
    reservations (Sample credits; no money moves), two jobs (the screen-38 queue at a Sample 42% of `preview_rendering`, and a ready job with a pause
    and a retry) and the delivered film (412 MB illustrative, verified, 24 h private link, YouTube prepared but not
    published).

## Vectors

- Implementation-states sample truth (10): sync, progress, chapter length, storyboard window, import size, the
  144-min upload, $0.0756 of seven-day storage, queue progress, lesson counts and the illustrative quote.

## Decision

- Cross-record coverage checks (`bundle.trusted_sources`) offer single-segment sources only: a match source is
   offered only when its manifest records one segment and its one sync piece maps exactly that segment. The sync map
   must carry exactly one piece per recorded segment of every match source (`unmappedSegment`), so a restarted
   segment can never be dropped and its frames cut through the first piece's transform. The EDL validator's
   piecewise coverage is pinned by the `edl-context` vectors (a two-interval Camera 2), and the fitter by S8.
