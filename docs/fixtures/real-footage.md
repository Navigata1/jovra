# Real-footage fixtures (Jon's own recordings)

Provided by Jon on 2026-10-07 for testing import, replay, analysis benchmarks and Studio film journeys. Other people
(opponents, partners, players on adjacent courts) appear in these recordings, so the videos are **private test
material**. They are never committed to git, never uploaded to any service, never used as App Store or marketing
imagery, and never sent to a model API. Only the hashes and descriptions below live in the repo.

## Locations

- Originals (external drive, exFAT): `/Volumes/Backup Plus/JOVRA-media/old-match/`. Set `JOVRA_REAL_MEDIA_DIR` to this path.
- Constant-frame-rate excerpts for agents and tests (internal disk, so they work when the drive is unplugged):
  `/Users/IDC2.5/JOVRA-media/excerpts/`. Set `JOVRA_EXCERPTS_DIR` to this path.
- Tests that need real footage must **skip with a clear message** when the files are absent. CI never has them.

## Originals

| File | Source | Duration | Video | Audio | SHA-256 |
|---|---|---|---|---|---|
| `S1-3.5-Feb-28-2024-youtube-zZtqeG7J_kA.mp4` | Jon's YouTube upload "S1 3.5 Feb 28 2024" (primary) | 71:17.7 | H.264 1920×1080, 29.589 fps | AAC 44.1 kHz stereo | `07fbd86e2dc963fa047643a661c2cad91c2671d8ea2070a130051e2ff907f8ac` |
| `20260929_170141.mp4` | Jon's Drive (supplementary) | 15:26.5 | HEVC 1280×720, ~30 fps **VFR** (avg 29.98), Android 13 | AAC 48 kHz stereo | `156cf7568cf1e92d9fdba161c933c101dac20d14f8f6baf2218abd9c4cc267ac` |
| `20261004_125549.mp4` | Jon's Drive (supplementary) | 5:02.6 | HEVC 1280×720, ~30 fps **VFR** (avg 29.98), Android 13 | AAC 48 kHz stereo | `1682e5934c40dde2a5760261e6342356866483538cc5437546a078751d1dd03e` |

The YouTube file is a re-encode by YouTube, so its capture metadata and original frame clock are gone. The two Drive
files are untouched phone originals, which makes them the real VFR/HEVC fixtures for import normalisation.

## What each one shows (from inspected frames)

- **Feb 2024 match — primary-angle fixture.** Night, floodlit hard court. Elevated camera behind the near baseline
  (fence or pole height), whole court visible with all four corners and the net, singles (near player in a blue jacket,
  far player in white). Adjacent courts and other players are visible at the frame edges. This is the reference
  setup for calibration, live-style scoring review, rally segmentation, match films and Match Broadcast.
- **Sep 29 2026 — corner-angle fixture.** Daytime, low camera outside the court at a corner, oblique view, several
  people, washed-out exposure. Useful for the "unsuitable angle / unclear corners" calibration states and for a
  corner-camera Studio role.
- **Oct 4 2026 — side-view fixture.** Overcast, ground-level camera at the net post looking down the sideline, one
  player practising. Useful for Stroke Lab side-on review and the 2D pose estimate.

These are three different days. **They cannot validate multi-angle synchronisation**; that needs two or more phones
recording the same match (Studio S2/S3 field gate).

## Excerpts (H.264 720p, 30 fps CFR, AAC 48 kHz)

| File | From | Window | SHA-256 |
|---|---|---|---|
| `match-feb2024-14m00s-6min-720p30.mp4` | Feb 2024 match | 14:00–20:00 | `7cd8155bda9138c93130c7ad80556c48756ab696906cd8b357f47f8e2da84629` |
| `match-feb2024-14m00s-2min-720p30.mp4` | Feb 2024 match | 14:00–16:00 | `e2eaf5c1c4b27c564bb527e7c9cc5aadb85f9ec71c3bb02f45f6311968bd8fb2` |
| `corner-sep2026-3m00s-90s-720p30.mp4` | Sep 29 2026 | 3:00–4:30 | `af4e111d3dceaddd09ed8a01234226e27405387e91bb380604f263297e6543b2` |
| `sideview-oct2026-1m00s-90s-720p30.mp4` | Oct 4 2026 | 1:00–2:30 | `ea5a4498bb1ab68b6e441d33d86aa683c670f1da74cdf0cc05886b9aa2486403` |

Excerpt timestamps map back to the original by adding the window start (e.g. excerpt 00:12.0 = original 14:12.0).

## First observation (2026-10-07, not a benchmark)

A naive detector (2 kHz high-pass, 10 ms RMS envelope, peak > 8× median) on the 2-minute excerpt found 84 transients.
Many sit 0.26–0.47 s apart, which matches bounces, footsteps and adjacent-court noise rather than racket contacts
(rally hits on this court are mostly 0.9–1.7 s apart). Audio-only hit detection on this footage will over-count;
rally segmentation needs the benchmark-gated combination (audio onset + motion near the players + rally-timing
model) and must stay "Needs review" until a labelled benchmark on these excerpts passes.

## Labelling plan for the benchmark

Ground truth for the 6-minute excerpt: point start/end times, server, winner and racket-contact times. Labels are
produced by a human in JOVRA's own Fast Point Review and Mark tools (Jon, in the hardware phase) or by an agent that
verifies candidate contacts against frame strips and spectrograms, recorded as `labelled-by` with method. The
benchmark records precision/recall per capability with the method version, and a capability is only promoted from
`estimated` per ADR-0004 when the labelled result passes its gate.
