---
module: multiangle-generator
reference: [scripts/media/studio/multiangle/generate.py, scripts/media/studio/multiangle/recover.py]
cases: [spec/reference/studio/cases/multiangle_cases.py]
kinds: [jovra.studio-multiangle-truth/1, jovra.studio-multiangle-rig/1]
coverage: covered
swift: pending
kotlin: pending
---

# Multi-angle generator: one synthetic scene, a rig of up to six phones, per-camera videos with ground truth

The synthetic multi-angle fixtures (multicam-sync research 8.1, ticket S58). One scene is recorded by a rig of up to
six phones at the club-fence placements. Each phone has its own clock, frame timing, orientation, colour, view and
microphone, and is rendered into per-camera videos. **Media is generated at test time** into the git-ignored cache
`.cache/media/studio/multiangle-<hash16>/`. Only the ground truth is committed, under
`spec/studio/fixtures/media/multiangle/`:

- one `<profile>.json` (`jovra.studio-multiangle-truth/1`) per profile;
- `rig.json` (`jovra.studio-multiangle-rig/1`) for the placements and the sound-delay tables.

The generator builds on S08 and never forks it:

- S08's barcode, click track, angle badge and render/verify pipeline;
- through S08, T10's renderer core (the encoder settings, the signature-margin refusal and the decoded-frame proof);
- T11's court scene and sample play;
- syncfit's exact sound-delay rule.

```
python3 scripts/media/studio/multiangle/generate.py                     # render what the cache lacks, write the ground truth
python3 scripts/media/studio/multiangle/generate.py --check             # verify every file; fail unless the committed truth reproduces
python3 scripts/media/studio/multiangle/generate.py --force --sha256-log run.txt   # re-encode all; list each file's SHA-256
python3 scripts/media/studio/multiangle/recover.py                      # every frame's match time from ids + ground truth
python3 -m unittest discover -s scripts/media/studio/multiangle -p 'test_*.py' -v
```

A cold render of all 46 files (about 110,000 frames) takes about 70 s on the build Mac with 8 jobs. They total
72 MB in the cache.

## The scene

The scene is the first 120 s of T11's Jon vs Alex sample play. That is points 1 to 6 of the core sample match, the
rules-coherent point log the S08 coherent match is built on.

- **Events.** There are 40 events: 20 racket contacts (`serveContact` and `hit`) and 20 bounces. Each sits at an
  exact 48 kHz sample of the scene clock.
- **Positions.** Each event's position comes from the ball arcs T11 draws. A contact is the start of the arc a hit
  launches; a bounce is where an arc lands. Positions are converted to the Studio court frame (`positionMm`) in whole
  millimetres.
- **The match clock.** The scene clock is the match clock: light time on the reference camera, which records from
  scene time 0 at rate 1.
- **Sound.** Racket contacts are heard: S08's 1 kHz click stands in for the impact. Bounces are visual events only.

## The rig and the camera clock

The six placements are the research 4.4 club-fence positions: BS and BN on the baselines, CSW, CSE, CNW and CNE at
the corners. Each has a microphone at 1.5 m. `rig.json` holds:

- the delay from each of the six research table events to each placement (36 delays);
- the pairwise bias rows (BS−BN, BS−CSE, BS−CNE).

Both use syncfit's `sound_delay_us` at 343 m/s. The validator checks every entry against the research numbers the
sound-delay vectors carry (`docTableMs`), within 0.1 ms.

Each camera's host clock maps to the match clock as `t_match = A + rate · t_host`, where `rate = (1e9 + driftPpb) / 1e9`.
That makes `driftPpm = (rate − 1)·10⁶`, the research 4.1 model. Segment `k` (one recorded file) starts at host time
`h_k`, so its true piece is `t_match = a_k + rate · t_src` with `a_k = A + rate · h_k`.

- **Restarts.** A restart is a second segment after a host-clock gap.
- **The journal.** When present, the capture journal records each `h_k`, so one host map covers every segment. An
  import has no journal (`journal: null`), though the true pieces are still stated.
- **The picture.** Each frame is drawn at its own match time, `a_k + rate · t_src(n)`, never at `n / fps`. So drift,
  phase, restarts and VFR are in the picture, not only in the numbers.
- **Audio arrival.** A contact's sound reaches a camera at `light + delay(event → placement) + λ`. That instant is
  mapped back to the camera's clock and rounded to a 48 kHz sample of its file.
- **When a hit is not heard.** A hit is heard only when the microphone is present and the onset is at least 100 ms
  inside the file. Otherwise its `reason` is `notRecording`, `muted` or `fileEdge`.

## Profiles

| Profile | Cameras | What it holds |
|---|---|---|
| `drift-default` | all six placements | drifts of +20, −8, +1, +50 and −35 ppm, start phases from 0.06 s to 0.73 s, audio latencies of 0–2.5 ms |
| `drift-stress-300ppm` | BS + CSE | +300 ppm (18 ms a minute) |
| `restart-41s-journal` | BS + CNE | a 41 s host gap between two segments, with the journal's file zeros |
| `restart-41s-no-journal` | BS + CNW | the same, imported: `journal: null` |
| `late-start` | BS + BN | BN starts at 47.3 s |
| `shake` | BS + CSW | a knocked tripod across three racket contacts (match 56.98–60.48 s), then the view settles 1° off |
| `muted` | BS + CSE | an AAC track holding only the noise floor |
| `mixed-fps` | BS 30 + CSE 60 + CNW 240 | compare times, never frame indices |
| `vfr-rotated-hdr` | BS + BN VFR + CSW rotated 90 + CNE HLG | normalization inputs (S59) |
| `no-shared-coverage` | BS 0–50 s + BN 70.25–118.6 s | `sharedCoverage[].matchUs` is null |
| `opposite-baseline-audio-only` | BS + BN, both lenses covered | no visual events; the baseline bias swings by about 69 ms with the hitter's end |

The shake stretch is drawn from views nudged by whole degrees, changing every 2 frames. It is marked three ways:

- in frames: `shake.fromFrame` and `shake.toFrame`;
- on the match clock: `shake.matchUs`;
- on every visible event: `visualEvents[].inShake`.

So an anchor test can assert that anchors inside the stretch are down-weighted or trimmed (the S62 sync engine).

## Files: coded and clean

Every camera segment is two H.264 files at 640x360, plus a 10-bit HEVC pair for HLG:

- **coded** carries S08's 40-bit frame barcode in the bottom 20 px: source id 64–127, segment and frame index;
- **clean** has no barcode.

Both variants share the picture, the "Sample video (synthetic)" label (top left), the placement name (top right) and
the click track. Algorithms run on clean; verification reads coded.

- **VFR** uses T10's phone cycle: one 25 ms frame and one 41.7 ms frame in every ten.
- **Rotated** sets the tkhd display matrix.
- **HLG** frames are the 8-bit picture scaled to 10 bits and tagged BT.2020 HLG. This is a format variant, not a
  graded HDR picture.
- **Covered** is a flat dark field.

## What a render proves

`generate.py` renders through S08's pipeline. It then decodes every file in full, and fails unless:

- every barcode reads back as its frame index;
- every heard click is detected within one frame, with no click extra;
- the VFR presentation times are the cycle;
- the rotation side data is the camera's;
- the match times the painter drew hash to the segment's `frameTimesSha256`.

The files' own SHA-256 values are printed in the run log and the `--sha256-log` list. A second `--force` run must
reproduce them byte for byte; the media test does that on a restarted camera. They are not committed: x264 and AAC
differ between ffmpeg builds (S08's rule). What every machine reproduces is committed as `hashes`: the drawn frames,
the decoded-frame signature and the click PCM.

`recover.py` reads only the committed ground truth and the media, never the generator's code. For each coded file:

1. It decodes every frame and reads the barcode.
2. It finds that camera and segment, takes the frame id's presentation time from `frameTiming`, and applies the
   segment's transform.
3. The result must equal the time the frame was painted at, within half an output frame (16.7 ms at 30 fps). The
   decoded presentation time must also equal the ground-truth one.
4. Each detected click, mapped to the match clock, minus its sound delay and latency, must land within 0.25 ms of its
   event's light time.

On the build Mac, every frame of all 31 coded files (83,690 frames) recovers within 0.5 µs, which is rounding only.
All 427 clicks map back within 86 µs. The mutation tests show the check can fail:

- an offset one output frame wrong;
- a 300 ppm drift dropped;
- VFR read as CFR;
- a sound delay 1 ms wrong;
- a restart's second piece replaced by the first.

## What the cases module checks

These checks run on every validator run, without media:

- both schemas;
- every segment's `frameTimesSha256` re-derived from its own transform and frame timing;
- coverage, gaps and host gaps;
- the shared device rate and the one host map;
- the reference's identity piece;
- every arrival re-derived from the event position, the placement and syncfit's delay, and its source sample;
- every visible event's frame, and its shake mark;
- shared coverage;
- every profile showing the condition it is named for;
- the rig against research 4.4.

The plan part of every file is recomputed from the generator, so a change that is not re-rendered is stale. The
hashes must be rendered from the current source.

## Not covered yet

- **Swift and Kotlin do not read these files yet** (`swift: pending`). S59 (ProxyNormalizer) reads the VFR, rotated,
  HDR and mixed-fps angles; S62 (anchor extraction) reads the drift, restart, late-start, shake, muted, no-overlap and
  audio-only profiles; S91 reuses them on the render host.
- **Not modelled:** rolling shutter, reverberation, crowd noise, wind, 1/d attenuation, dropped or stalled frames,
  audio sample-rate offset, 25 and 30000/1001 fps, and a capture-hint error model. Fixtures prove pipeline logic only.
  Sync on real footage needs the research 8.4 protocol.
- **No slate.** The sample match has no net-centre clap; slates are a later variant.
