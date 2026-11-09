---
module: barcode-court
reference: [spec/reference/studio/framemap.py, scripts/media/studio/barcode_court.py]
cases: [spec/reference/studio/cases/barcode_court_cases.py]
kinds: [barcode-court]
coverage: covered
swift: pending
kotlin: pending
---

# Barcode court: trusted contexts and compile vectors over the S08 media

The renderers (S41 and S42 on the device, S92 in the cloud) and FilmVerifier (S40) need edit plans bound to real
media files, with real hashes and PTS tables, so a renderer test can decode every output frame, read its barcode and
compare it with the plan. The sample-court-day context has no media. This module builds two Sample projects over the
S08 media fixtures (media-fixtures.md) and compiles plans over them with the S07 compiler (compile.md), covering every
operation of the S1 stage allowlist.

The media is never committed. It is generated at test time by the S08 generator into the git-ignored cache. What is
committed is the context records (with the media hashes) and the vectors.

```
python3 scripts/spec/validate_studio.py                               # contexts, vectors, coverage, staleness
JOVRA_STUDIO_MEDIA=1 python3 scripts/spec/validate_studio.py          # also regenerates the media and compares bytes
python3 scripts/media/studio/barcode_court.py --check                 # the media comparison on its own
python3 scripts/media/studio/barcode_court.py --measure               # re-measure, then regenerate the fixtures
```

## The two projects

| Project | Sources | What it is for |
|---|---|---|
| `sample-barcode-court-60` (`court-60`) | `bc-060`: the 60 fps barcode source, 1280x720, 10 s, eight clicks | A 1/2x replay of real 60 fps frames at 30 fps output, at stage S1 (one angle, so the 60 fps camera is the primary) |
| `sample-barcode-court-match` (`court-match`) | `match`: the coherent synthetic match, 640x360 at 30 fps, 54:00, a click at each of its 440 hits; `broll-push`, `broll-drop`, `broll-pan` (6 s each, 30 fps) | Coach's Cut, Court Memories and Match Broadcast lengths, the point-event fold, B-roll |

Each project's records live in `spec/studio/fixtures/records/barcode-court/`, named `<project>.<kind>.json`:

- **SourceManifest.** Each source's original *is* the generated file: its real SHA-256 and size, the track timescale
  of its decoded video, its frame count and rate (from the S08 manifest). Its render proxy is the same file (CFR, SDR,
  unrotated, at its own rate), so the proxy's SHA-256 equals the original's and `ptsTableSha256` is the hash of the
  project's `pts-table.<source>` record. The one segment is `import` with no capture journal.
- **PTS table** (`jovra.pts-table/1`, normalization.md): the decoded PTS index of the file (ffprobe, counted from the
  first frame) and the half-up selection of the proxy, which is the identity here. The table's `proxy.timescale` is the
  normalizer's track timescale (`lcm(fps, 1000)`), what a normalized proxy would carry; the file's own track timescale
  is the original's.
- **SyncMap.** Identity: the one camera is the reference (`seg-0`, state `reference`, offset 0, rate 1), so session time
  is the file's own presentation time. Its provenance is `estimated`, as records.check_sync_map requires of a map with no
  fitted device.
- **KeeperCatalog.** `court-60`: three keepers tile the 600 frames (`k-01` 0-240, `k-02` 240-446, `k-03` 446-600);
  their edges lie between clicks (18, 60, 102, 194, 285, 376, 517, 566), so a 6-frame transition's handles never reach a
  contact's protected window. `court-match`: one keeper per point of the S08 log that lasts at least 10 s (37 of the
  124), session window = the point's `tStartMs`-`tEndMs`, view = its `startFrame`-`endFrame`; every click frame inside is
  a stored contact.
- **BrollCatalog.** `court-match`: the three B-roll clips, each window frames 15-165 (5 s of the 6 s), leaving
  half-second handles for a dip or dissolve.
- **ReferenceCatalog.** A score reference per kept point (origin `point-event`, provenance from the fold); in
  `court-match` also `stat-first-serve-in` (metric, reviewed), `cue-01` (cue, reviewed) and `ann-01` (annotation,
  reviewed), both on point 29 (the longest rally, 18.2 s), and six user notes for the cards and the caption.

The trusted EDL context is `bundle.edl_context` over these records, exactly as for the sample-court-day project; the
compile context adds the planning context, the media index (primary, the one slot, keeper views, B-roll windows),
stage S1 and a renderer that supports every SD6b operation.

## The vectors (`vectors/barcode-court.json`)

- `media`: per source, the S08 manifest, the S08 generator's current source hash, the S08 barcode source id and frame
  map hash, and `measured`: what a render on the build machine gave (SHA-256, size, video timescale, decoded PTS runs,
  encoder, and the generator source it was measured from). `barcode_court.py --measure` writes it; the fixture
  generator carries it over, like the S08 manifests' `hashes`.
- `context-court-60`, `context-court-match`: the compile context, the barcode table (per source: S08 barcode source
  id and frame map runs), the click onsets (48 kHz samples on each source's audio) and, for the match, the point-event
  fold of every kept point (`spec/reference/jovra_ref/scoring.py`: set, game, server, the score before the point, its
  call and winner), which S42 compares with the score bug's text.
- `compile` cases: a hand-written StoryPlan and a request, compiled by compile.py. `expect` holds the compiler's result
  and what a renderer test compares:
  - `frameMap` (`framemap.frame_map`): runs `{outFrame, count, picture, ...}`, `picture` one of `source` (`sourceId`,
    `barcode: [source, segment, frameId]` of the run's first frame, `step` per output frame, 0 for a freeze), `card`
    (`templateId`), `dissolve` (`from`, `to`), `dip-out`, `dip-in` (`through: #092A25`); and `frameMapSha256`;
  - `clickMap`: every click a sounding bed piece carries, on the output clock (`outSample`, `outFrame`), and `faded`:
    the clicks that start inside a piece's fade, which a verifier neither requires nor forbids;
  - `overlays`: the overlay log a renderer must write (every overlay reference over its segment, the Replay and
    Paused labels, the card templates, the Sample badge);
  - `operations`: what the plan exercises;
  - `cleanAlternate`: for a plan with a dissolve or dip, `edl.clean_alternate` of it with the same four maps.

### The frame map rules (`spec/reference/studio/framemap.py`)

Output frame `o` of a live, B-roll or replay segment shows source frame `sourceInFrame + floor((o - outputInFrame) *
k)`, `k = sourceFps * speed / outputFps` (the latest source frame presented at or before the output frame). A freeze
shows `sourceFrame`; a card shows no source picture. A dissolve or dip of `n` frames into segment B at its first frame
`b`: `n - n // 2` frames before `b` already show B and `n // 2` from `b` still show A (edl.py's handle rule). A dissolve
blends A, continued past its out-point on its own clock, with B, started before its in-point; a dip fades A to forest
(#092A25) over the frames before `b` and B up from forest from `b`. A run's step is a whole number of frame ids per
output frame; a plan that would need a fractional step is refused (`fractionalStep`), never approximated (every
barcode-court plan has k = 1 or 2).

### Cases

| Case | Project | What it pins |
|---|---|---|
| `rally-60-portrait` | court-60 | Rally Pulse at 30 fps, 9:16 (720x1280, letterboxed): each keeper live at 1x (every other 60 fps frame) then a labelled 1/2x replay of every 60 fps frame of it, dissolves into s03 and s04, a dip to forest into s05, the accent card; 945 frames; primary bed under live play, silence under the replays (the keepers tile the recording, so there is no dead time to hold) |
| `rally-60-s41` | court-60 | The same plan at 16:9 (1280x720, fill) for a renderer with only live, B-roll, replay, transitions and the bed (S41's first set): the card is omitted (`notInThisBuild`), 900 frames = 30 s remain |
| `coach-court` | court-match | Coach's Cut: goal card, sixteen examples with their score bug, the metric chip, the cue chip and a pause with the annotation on point 29, its 1/2x replay omitted (`cleanFrame`, a 30 fps camera at 30 fps output), two 12-frame dissolves, the drill and next-checkpoint cards, hold-bed over dead time |
| `memories-court` | court-match | Court Memories: B-roll with the caption note (silent at S1: no `alt-bed`), the date card, nine moments (the score bug on the highlight), two 15-frame dips to forest and a dissolve, the dedication card; the warm grade is omitted (`notInThisStage`) |
| `broadcast-court` | court-match | Match Broadcast: the players card, all 37 kept points in order with their score bugs, an 8-frame dissolve, the final score card (point coverage complete, no restart) |
| `contact-blend-refused` | court-60 | With a stored contact two frames before k-02, the requested dissolve would blend it: `contactProtected`, a typed rejection |

Every `assert` block is worked by hand: the court-60 cut lists and frame probes from the keeper windows (live 240 /
206 / 154 source frames at k = 2 are 120 / 103 / 77 output frames; the 1/2x replays at k = 1 are 240 / 206 / 154; the
card 45), and for the match cases the transitions, omissions, labels, overlay kinds and first and last cards.

## What the checker and self-tests check

- **media**: the context is **stale** when any bound file was measured from another S08 generator source than the
  generator's code has now (one changed parameter changes the set's source hash), when the S08 frame map changed, or
  when a file was never measured; the SourceManifest must bind the measured SHA-256 and the PTS table must be the
  decoded index. With `JOVRA_STUDIO_MEDIA=1` the `barcode-court-media` self-test regenerates every bound file into the
  cache with the S08 pipeline and compares its SHA-256, size and decoded PTS index (`barcode_court.compare`). Without
  it, the count line says the bytes were **not** regenerated.
- **context**: each stored context equals the one rebuilt from the records on disk; the barcode and click tables equal
  the S08 manifests; the fold equals the core fold.
- **compile**: the compiler reproduces `expect` (determinism: a second compile gives the same canonical bytes) and does
  not change its input; the plan passes the story-brief schema; every compiled EDL and its clean alternate pass
  `edl.validate` and the edit-plan schema; **every output frame** of the frame map equals what an independent
  frame-by-frame reading of the plan shows (an implementation in the cases module that shares no code with framemap.py);
  the clean alternate keeps the same cuts and has no transitions; the hand `assert` block.
- **barcode-court-coverage**: every operation of `compile.S1_OPS` and every feature the ticket names (cut, dissolve,
  dip, title card, score, metric, cue, annotation, provenance chip, Replay and Paused labels, Sample badge, a 1/2x
  replay from 60 fps at 30 fps, 9:16 letterbox, 16:9, clean alternate) appears in at least one compiled vector; the
  count lines print the table, operation then vector ids, and a missing one fails.
- **barcode-court-records**: the records pass their schemas, reference rules and the cross-record rules
  (`check_sync_against_manifest`, `check_catalogs`, the sync refit), and `bundle.edl_context` offers exactly the
  project's sources for cutting.
- **barcode-court-mutations**: a frame map is caught when its plan shifts a replay by one frame or turns the dip into
  a cut, and a measurement from another generator source is reported stale.

## Decisions

- **Two projects, not one.** S1 allows one angle, and a 1/2x replay at 30 fps needs 60 fps capture, so the 60 fps
  barcode source must be a primary. Its 10 s cannot fill Coach's Cut, Court Memories or Match Broadcast, which need the
  54-minute match. A second angle would need a fitted, reviewed SyncMap, and anchors between unrelated synthetic files
  would be invented.
- **Media hashes are per encoder build.** x264 and the AAC encoder differ between ffmpeg builds (media-fixtures.md), so
  `measured` names the encoder. On a machine with another build the media check reports the hashes as not comparable
  (a failure only when `JOVRA_STUDIO_MEDIA=1` asks for it); the structural and staleness checks run everywhere.
  Measured on the build Mac with `ffmpeg version 9.0.1`.
- **Storyboard transitions.** compile.py gained one request key, `transitions` (`{beatId: {type, frames}}`), the
  player's storyboard choice, applied as that beat's incoming transition with the bed fades the audio dip needs
  (compile.md). Existing compile vectors are byte-identical.

## What is not covered yet

- **The recording-gap card** (`card.recording-gap`). `bundle.trusted_sources` offers no restarted source (a source
  with two or more manifest segments is never offered), and S08's restart is 10 s, which cannot fill Match
  Broadcast's 5-minute minimum at S1. It needs a longer restarted barcode capture (S08) and a reviewed trust rule for
  restarted sources. The coverage table lists it as NOT COVERED.
- Swift, Kotlin and the TypeScript compiler (S88) do not reproduce these vectors yet (`swift: pending`); a port needs
  compile.py's `transitions` request key.
- Rendering: nothing here renders a film. S40 (FilmVerifier) and S41/S42/S92 (renderers) consume the frame, click and
  overlay maps.
