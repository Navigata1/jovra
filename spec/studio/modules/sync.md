---
module: sync
reference: [spec/reference/studio/syncfit.py]
cases: [spec/reference/studio/cases/sync_cases.py]
kinds: [jovra.sync-map/1, sync-fit, sound-delay]
coverage: covered
swift: pending
kotlin: pending
---

# Sync: the sync map and the sync fitter

`spec/reference/studio/syncfit.py` holds the speed of sound, sound-travel delays, the piecewise sync-map fitter and
its review-state rules; the sync-map record rule (`check_sync_map` in `spec/reference/studio/records.py`) refits every
non-reference device with it. `spec/reference/studio/cases/sync_cases.py` writes the `sync-fit` and `sound-delay`
vectors and the sync-map invalid cases. `python3 scripts/spec/validate_studio.py --list` prints the current case count
of every kind below and its Swift and Kotlin status.

| Schema | Record | What the reference adds beyond the schema |
|---|---|---|
| `sync-map` | Per device: pieces per recorded segment with an affine transform, fit statistics, anchors (modality, source/reference times, event position, sound delays, residual, inlier, reviewed), match coverage, gaps, review state, checkpoints; speed of sound; placements; method version | **Refits every non-reference device** with `syncfit.fit_device` and requires identical transforms, statistics, delays and residuals; stored state must equal the rule state, or be `reviewed` with start/middle/end checkpoints; coverage equals the transform over the file; gaps are exactly the uncovered spans; origin is the earliest coverage; provenance never `validated` |

### Sync fitter (`syncfit.py`, method `robust-trimmed-ols/1`)

- **Model:** `t_match = offset_k + rate · t_src`, with one rate per device and one offset per recorded segment
  (piecewise across restarts; gaps stay uncovered). A robust start (the exact median of all within-piece pairwise
  slopes, Theil–Sen, and per-piece median intercepts), one trim of residuals larger than 3 output frames, then an
  exact pooled OLS on the inliers. The rate is rounded half-up to 1 ppb, and offsets and residuals to 1 µs. RMS uses
  an integer square root. (The retired `trimmed-ols/1` started from plain OLS: one anchor 2 s off could drag the line
  so far that every anchor was trimmed while the map stayed reviewable.)
- **Guards:** every anchor lies inside its piece (`0 ≤ sourceTimeUs < sourceDurationUs`, else `badAnchor`); a piece
  with fewer than two inliers is `failed` with no transform and no statistics; a fitted rate outside 0.9–1.1 fails
  the device. Drift plausibility is a reviewable reason, never a rejection (multicam-sync.md §4.6: phones measure
  about 8 ppm, realistic is 1–50 ppm, 300 ppm is the stress fixture): above 303 ppm (the 300 ppm stress ceiling plus
  the ±3 ppm drift tolerance of research S2) the piece needs review; above 1000 ppm (exactly 30 vs 29.97 fps) the
  reason names a likely frame-rate or timebase mislabel. The Sample Camera 2 (300.102 ppm) stays `estimated`. A piece has `matchCoverage` exactly when it has a transform (schema `if`/`then` and the reference).
- **Speed of sound:** audio anchors subtract the sound travel from the event position to each phone before fitting.
  The delay, `sqrt(d²)·10⁶ / c`, is computed exactly with `isqrt`, with c = 343 m/s or `331.3·√(1 + T/273.15)` m/s
  rounded to mm/s.
- **States:**
  - `estimated` needs at least 8 inlier anchors, all three thirds covered, a maximum residual of half an output
    frame, no trimmed outliers and no uncorrected audio.
  - Otherwise the state is `needs-review`, with reasons.
  - `manual` means markers only; `from-hints` means a capture hint only, derived from the SourceManifest
    (`bundle.capture_hints`: the journal's `fileZeroHostNs` plus `roomOffsetUs`, the room clock minus the host
    clock) and checked against it, never trusted; `failed` means nothing to fit, which includes no shared coverage
    (there is no separate `no-overlap` state).
  - On the reference device only `referenceSegmentId` is `reference` (rate 1). A restarted reference segment is
    `from-hints` from its own journal (rate 1, offset derived, never invented) or `failed`; it is shown, not cut.
  - Only a person sets `reviewed`, and only on a fit with at least three inliers (with two, an outlier is invisible)
    (`reviewOfWeakFit`). An implausible drift does not bar review: a correct fit through a mislabelled timebase is a
    real map, and the checkpoints are the safeguard. `validated` is never given to a single map.

## Vectors

- Sync fits (17; research S1, S2, S5–S10, S14, hint-only, manual, a 2 s gross outlier recovered by the robust start,
  two inconsistent clusters that fail, two anchors that cannot be reviewed, 400 ppm and 1500 ppm drifts flagged for
  review but still reviewable, and 303 ppm at the ceiling still estimated).
- Sound delays (48), reproducing the multicam research §4.4 tables within 0.1 ms, including pairwise biases and
  c(T).

## Decision

- The match clock is light time on the primary's video clock, with its origin at the earliest coverage, in integer
   µs. It sits separately from the core integer-ms session timeline, which is untouched.

## Not covered yet

- **Sync on real footage:** Huber weighting, prediction-interval gates, rolling-shutter correction, and audio latency
  λ calibration (the Theil–Sen start is now in `robust-trimmed-ols/1`).
- **Sync:** the 95% prediction-interval gate (a planned S2 tightening of SD9).
