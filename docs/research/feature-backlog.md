# JOVRA feature backlog (research-derived)

Status: prioritized backlog, 2026-10-07. Input to the spec and ticket workflow (`docs/spec/`, GitHub Issues on
`Navigata1/jovra`). Every item traces to evidence in `competitive-analysis.md`, `technical-feasibility.md`,
`tennis-rules-and-stats.md` and the raw notes in `raw/`.

## How to read this

**Priorities**
- **P0** — must ship in iOS v1. Without it JOVRA is not the product Jon described or does not beat the incumbents'
  biggest failures.
- **P1** — ship in iOS v1 if feasible; otherwise the first update.
- **P2** — next (after v1), including the Android port.
- **Later** — needs a validated prerequisite (usually a labelled-footage model) or a business step.
- **Never** — deliberate non-goals. Keeping them out is part of the product.

**Honesty label** (what the UI shows next to any value the item produces; maps to ADR-0004 registry statuses)
- **Manual** — entered or confirmed by the user (`manual` / `reviewed` provenance).
- **Estimated** — computed automatically and shown with a badge and range/confidence; allowed only after the
  capability passes its minimum gate for the stated configuration (`estimated`).
- **Validated-after-benchmark** — hidden or Experimental until the gate in `technical-feasibility.md` passes; then
  Estimated, and unbadged only after the strict gate (`disabled` → `estimated` → `validated`).
- **n/a** — the item produces no metric (infrastructure, UX, policy).

**Screens** refer to `design-reference/brief/screens.json` (1 Welcome, 2 Onboarding, 3 Home, 4 Setup, 5 Calibration,
6 Live capture, 7 Import/queue, 8 Library, 9 Match overview, 10 Smart replay, 11 Shot map, 12 Serve Lab, 13 Stroke Lab,
14 Compare, 15 Coaching plan, 16 Progress, 17 Racket Vault, 18 String journal, 19 Storage/backup, 20 Settings).
"New surface" = not one of the 20.

**NEW** marks items that neither the founder's prompt nor the prior brief (`design-reference/brief/*`) contained;
they come from the gap-finder, community, review-mining and technical research.

**Where this backlog departs from the prior brief's sequencing** (`design-reference/brief/research.md`, "P0 capture /
P1 correction, export, equipment, Drive / P2 analysis"):
- **Point correction and clip export move to P0.** Correction pain is a top review theme (64 AI-accuracy reviews; "fixing
  a missed point takes as long as my own editor"), and the founder asked to replay and analyse, which needs both.
- **Google Drive archive moves to P0.** The founder named it explicitly ("upload them … to my Google Drive, using that as
  my cloud storage"); his words are the source of intent. It ships with an honest "awaiting configuration" state if the
  Google Cloud project, OAuth client and "In production" publishing status are not ready (brand verification is
  optional for `drive.file`; it only adds the name and logo to the consent screen).
- **Synced comparison (manual) moves to P0.** The founder asked for analysis "of how the swing or the serve … making the
  comp"; manual sync needs no ML.
- Equipment stays P1 (as the brief had it); founder did not name it, but the build prompt and screens 17–18 do.

---

## Summary

| ID | Item | Priority | Label | Screens | NEW |
|---|---|---|---|---|---|
| P0-01 | Crash-safe capture engine (segments + journal) | P0 | n/a | 5, 6 | |
| P0-02 | Pre-flight checklist with computed storage/battery/heat budget | P0 | Estimated (storage) | 4, 5 | |
| P0-03 | Heat ladder, court mode and "Saved through mm:ss" | P0 | n/a | 6 | NEW |
| P0-04 | Landscape layouts for calibration and live capture | P0 | n/a | 5, 6 | NEW |
| P0-05 | Framing guidance that says what to move | P0 | n/a | 5 | |
| P0-06 | Import from Photos, Files and Drive (via Files) | P0 | n/a | 7 | |
| P0-07 | Library with independent video/analysis/review/archive states (+ iCloud-backup setting) | P0 | n/a | 8, 19 | (backup setting NEW) |
| P0-08 | Three-tier frame-accurate replay | P0 | n/a | 10 | |
| P0-09 | Rules engine + live manual scoring + Mark point + undo | P0 | Manual | 4, 6, 9 | |
| P0-10 | Point correction in replay that propagates everywhere | P0 | Manual | 10 | |
| P0-11 | Fast Point Review deck + changeover checkpoint scoring | P0 | Manual / Estimated (auto-fill) | new surface, 6, 9 | NEW |
| P0-12 | Rally-only playback with visible gaps (from bookmarks) | P0 | Manual | 10 | NEW |
| P0-13 | Automatic rally detection (audio + motion), benchmark-gated | P0 (gated) | Validated-after-benchmark | 7, 10 | |
| P0-14 | Match overview and Home stats with denominators | P0 | Manual / Reviewed | 3, 9 | |
| P0-15 | Clip export, Save to Photos, share | P0 | n/a | 10, 19 | |
| P0-16 | Compare two recordings with manual contact sync + basic drawing | P0 | Manual | 14 | |
| P0-17 | Google Drive archive with verified, resumable backup + Space Saver | P0 | n/a | 7, 8, 19 | (Space Saver NEW) |
| P0-18 | Own-your-footage contract (no account, caps, ads, tracking, locks) | P0 | n/a | 1, 19, 20 | NEW |
| P0-19 | Handedness and backhand type for both players | P0 | Manual | 2, 4 | NEW (opponent) |
| P0-20 | Capability registry, provenance badges, Sample labelling | P0 | all | all | |
| P0-21 | VoiceOver-first review and honest accessibility declarations | P0 | n/a | all | NEW |
| P0-22 | Settings and permissions that state consequences | P0 | n/a | 20 | |
| P1-01 | Racket Vault + String Journal linked to sessions | P1 | Manual (+ computed hours) | 4, 17, 18 | |
| P1-02 | Performance by equipment setup (association only) | P1 | Estimated (association) | 16, 18 | NEW |
| P1-03 | Manual shot placement and shot map | P1 | Manual | 10, 11 | |
| P1-04 | Serve Lab (manual): serve stats, placement taps, toss-to-contact timer | P1 | Manual | 12 | |
| P1-05 | Stroke Lab (manual): key moments, contact strip | P1 | Manual | 13 | |
| P1-06 | Evidence-linked practice plan | P1 | Manual (rules from computed stats) | 15 | |
| P1-07 | Progress trends with pooled denominators and goals | P1 | Manual / Reviewed | 3, 16 | |
| P1-08 | Import with the Google Picker | P1 | n/a | 7 | |
| P1-09 | Share Pack for coach / opponent / partner | P1 | n/a | 9, 10, new sheet | NEW |
| P1-10 | Consent, competition and junior-parent mode | P1 | n/a | 4, 6, 20 | NEW |
| P1-11 | Open CSV/JSON export | P1 | n/a | 19, 20 | |
| P1-12 | Hands-free Mark point (volume, Action, Camera Control, AirPods) | P1 | Manual | 6 | NEW |
| P1-13 | Recording status on Lock Screen / Watch via Live Activity (spike-gated) | P1 | n/a | 6 | NEW |
| P1-14 | Highlight reel with burned-in score | P1 | Manual / Reviewed | 10 | |
| P1-15 | Pinned voice notes | P1 | n/a | 14 | |
| P1-16 | Full drawing toolset with annotation lifetime | P1 | Manual | 13, 14 | |
| P1-17 | Camera-moved detection and line-snap assist | P1 | Validated-after-benchmark | 5 | |
| P1-18 | All format presets + post-match format/session-type edit | P1 | n/a | 4, 9 | |
| P1-19 | Doubles manual scoring UI | P1 | Manual | 4, 6, 9 | |
| P1-20 | Head-to-head history (local) | P1 | Manual | 9 | NEW |
| P1-21 | In-app diagnostics bundle | P1 | n/a | 20 | NEW |
| P1-22 | HealthKit tennis workouts (opt-in) | P1 | n/a | 20 | |
| P1-23 | iPad review layout | P1 | n/a | 10, 14 | |
| P1-24 | Localization foundation and metric units | P1 | n/a | 20 | |
| P1-25 | Transparent pricing (decision) | P1 | n/a | 19, 20 | |
| P1-26 | App Intents / Siri / Shortcuts that open framing | P1 | n/a | 3 | |
| P2-01 | Android port | P2 | per capability | all | |
| P2-02 | 2D pose overlay on side-on clips | P2 | Validated-after-benchmark | 13 | |
| P2-03 | Automatic stroke classification (near player) | P2 | Validated-after-benchmark | 10, 13 | |
| P2-04 | Serve detection and serve speed | P2 | Validated-after-benchmark | 12 | |
| P2-05 | Automatic contact sync in compare | P2 | Validated-after-benchmark | 14 | |
| P2-06 | Voice-over walkthrough export + transcription | P2 | n/a | 14 | |
| P2-07 | Practice instant-replay / delay loop | P2 | n/a | new surface | NEW |
| P2-08 | Remote viewfinder from any second phone | P2 | n/a | 5, 6 | |
| P2-09 | Pitch check (relative string-bed change) | P2 | Validated-after-benchmark | 18 | NEW |
| P2-10 | On-device recap text | P2 | Estimated (numbers verified) | 9 | NEW |
| P2-11 | "Review the clip together" second-device viewer | P2 | n/a | 10 | NEW |
| P2-12 | UTR result copy / self-post link | P2 | n/a | 9 | |
| P2-13 | Practice counters from audio hits | P2 | Validated-after-benchmark | 12, 16 | |
| P2-14 | Pickleball mode | P2 | per capability | 4 | |
| P2-15 | Lock Screen quick record | P2 | n/a | 6 | |
| P2-16 | Apple Watch app (only if P1-13 spike fails) | P2 | n/a | new surface | |
| P2-17 | Mac review | P2 | n/a | 10, 14 | |
| L-01…L-10 | Ball tracking, video placement, multi-angle, doubles positioning, serve targets, padel, ITF PAT, AI auto-scoring, server analysis, rating integrations | Later | Validated-after-benchmark | various | |
| N-01…N-10 | Line calls, ads/tracking, locking own video, RPM/biomechanics/medical, pro library, tension sensor, dark-pattern pricing, live streaming, upload-before-review, MCP/competitor data | Never | — | — | |

---

## P0 — must ship in iOS v1

### P0-01 Crash-safe capture engine
- **User value:** a 1–2 hour match is never lost; a crash or interruption costs seconds, not the session.
- **Evidence:** reliability is mentioned in ≈37–44% of 289 ≤2★ reviews of five apps (classifier-dependent; tied with
  money as the top complaint group, competitive-analysis V2); 39 recording-failure reviews; SwingVision 11.9.47–11.9.67 fix
  "interrupted recordings saved without any playable video", early endings, interruption crashes; SevenSix screen lock
  during recording; community rank-6 wish "never lose a recording" (22 authors + 66 on heat/battery).
- **Approach:** `RecordingEngine` protocol; P0 = `AVCaptureMovieFileOutput` with `movieFragmentInterval ≈ 2 s` set before
  start; write-ahead journal; session = ordered segments + gaps; every interruption finalizes the segment and is
  recorded; recovery runs at next launch from the journal and fragmented files on disk (the finish delegate is not
  called on crash, jetsam or power loss) and is validated by decoding to the end; playability = nil error, else
  `AVErrorRecordingSuccessfullyFinishedKey`; `isIdleTimerDisabled` while recording only; physical ultra-wide
  camera, stabilization off, focus/exposure locked after framing; back camera default. P1 option: AVAssetWriter fMP4
  segments if the soak test fails (technical-feasibility §1).
- **Gate:** device soak test (≤3 s lost per crash, 0 unrecoverable sessions, journal within 1 frame).
- **Label:** n/a. **Screens:** 5, 6.

### P0-02 Pre-flight checklist with a computed budget
- **User value:** know before the first serve that the phone has room, charge and a sane setup.
- **Evidence:** SwingVision FAQ asks for ≥80% battery per 2 h and ≥10 GB; SwingVision added low-storage warnings in
  2026; screen 4's "Estimated space: 3.2 GB" must be computed (implementation-states.md); 3.2 GB ≈ 36 min at 90 MB/min.
- **Approach:** `volumeAvailableCapacityForImportantUsageKey` (declared in the privacy manifest) vs preset bitrate ×
  planned length × 1.2; after 30 s replace with the measured `recordedFileSize` slope (±15%); battery level and Low
  Power Mode; thermal state; Focus/Do Not Disturb hint; lens-smudge check on iOS 26.
- **Label:** Estimated (storage and minutes remaining, always shown as a range). **Screens:** 4, 5.

### P0-03 Heat ladder, court mode and "Saved through mm:ss" — NEW
- **User value:** recordings finish on hot days; the player can see from the baseline that the phone is still saving.
- **Evidence:** SwingVision notes 11.9.47/.65/.67 (heat), FAQ "System Pressure" stops; forums report shutdowns above
  ~85°F; Apple's ambient range is 0–35 °C; "watch said recording, phone saved nothing" (55 Watch/second-device reviews).
- **Approach:** observe `systemPressureState` / `thermalState`: helpers off → preview off (court mode: black screen, REC,
  timer, "Saved · 4 s ago") → 30 fps at critical → clean segment at shutdown; log every rung. No live inference on court.
- **Label:** n/a. **Screens:** 6 ("Phone warming · Analysis paused" already drawn).

### P0-04 Landscape calibration and live-capture layouts — NEW
- **User value:** the preview and controls are the right way up when the phone is on its side on a fence.
- **Evidence:** a full-court 16:9 frame from behind the baseline needs a landscape phone and the ultra-wide lens (≈90°
  HFOV needed vs 69° wide); screens 5–6 are drawn portrait (raw/ios-tech.md §1.9–1.10).
- **Approach:** `RotationCoordinator`; lock the rotation angle at record start; landscape variants of 5 and 6.
- **Label:** n/a. **Screens:** 5, 6.

### P0-05 Framing guidance that says what to move
- **User value:** setup in under two minutes without a Watch or a second online device.
- **Evidence:** setup/alignment complaints (18 reviews + 41 community authors: outline never turns green on tripods;
  audio setup removed in May 2026; second device needed); players record from fences "as high as possible" or 6–7 ft
  tripods.
- **Approach:** overlay a court guide; checklist "All four corners visible / Net centred / Far service line above net
  tape"; specific instructions ("raise the phone ~30 cm", "rotate left"); tripod and fence profiles; audio and haptic
  cues; optional 4-tap corner calibration that can also be done later on the recorded footage. Tell users up front what
  each placement can deliver (SwingVision's Ground / Fence / Stick tiers).
- **Label:** n/a. **Screens:** 4, 5.

### P0-06 Import from Photos, Files and Google Drive (via Files)
- **User value:** bring GoPro, Android or native-camera footage in; many players already record that way to avoid
  losing sessions.
- **Evidence:** community workflow "record in the native camera, import later"; SwingVision blocked 30 fps imports
  (2024) and rejected 50 fps footage; Onform auto-cropped and loaded vertical imports sideways.
- **Approach:** `PhotosPicker` (`preferredItemEncoding: .current`, no library auth), `UIDocumentPickerViewController`
  (reaches Drive with no Google scope); copy inside the handler; any common codec and frame rate; respect
  `preferredTransform`, never crop; duplicate detection by hash; stage timeline "Saved locally → Preparing replay →
  Analyzing → Backing up".
- **Label:** n/a. **Screens:** 7.

### P0-07 Library with independent states
- **User value:** always know what is on the phone, what is backed up, what needs review, and how much space each
  session uses.
- **Evidence:** product-brief rule (separate video/analysis/review/archive states); SwingVision's coupled pipeline (two
  years of fixes for sessions stuck in processing, uploads stuck at 100%, finished recordings reappearing in progress);
  80 GB phantom storage (135-point Reddit thread).
- **Approach:** session folders + `session.json` (ADR-0002); states per axis; per-session size; one-tap derived-cache
  cleanup; delete-to-trash with undo and explicit original retention. **iCloud device backup (NEW, forgotten by both
  briefs):** originals in the app container are included in iCloud/Finder device backups by default; Apple says not to
  exclude irreplaceable user content, but a 1080p60 hour is ≈5.4 GB and a 2 h 4K60 original ≈48 GB, which can break a
  user's iCloud backup. Ship a visible "Include originals in iCloud device backup" setting (`isExcludedFromBackup` on
  original files when off) with the trade-off stated, and point to Drive and "Save to Photos" as the durable copies
  (raw/ios-tech.md §1.7). Default is a decision for Jon (see Decisions).
- **Label:** n/a. **Screens:** 8, 19.

### P0-08 Three-tier frame-accurate replay
- **User value:** find the exact frame of contact or bounce without fighting the controls.
- **Evidence:** replay/self-review praise rising (2% → 7%, 1% → 6% of SwingVision reviews); Onform/SlowMo scrub failures
  (edge-gesture collisions, absolute bar imprecise for long 240 fps clips, jog disengaging into draw mode).
- **Approach:** event timeline + frame-quantized jog strip (≥44 pt, ≥16 pt from the timeline, above the transport, never
  on the bottom edge) + ±1-frame buttons; QA1820 chase-time seeking; `step(byCount:)`; 0.25×/0.5×/1×/2×, A–B loop;
  frame/time/fps readout; 10-second skip (requested 2025-01); pinch zoom; deferred edge gestures; VoiceOver adjustable
  frame stepping; iPad arrow keys.
- **Label:** n/a. **Screens:** 10 (pattern reused on 12, 13, 14).

### P0-09 Rules engine, live manual scoring, Mark point, undo
- **User value:** a correct scoreboard every time, with or without automation.
- **Evidence:** charting apps win on correctness (Tennis Math 4.61★ / 3,345 with fix-in-place and undo/redo); requests
  for service-winner, no-ad, 10-point tie-breaks; Scoreboard Pro reviews: never interrupt scoring, persist state.
- **Approach:** event-sourced fold (ADR-0003; `tennis-rules-and-stats.md`): ad/no-ad, set and match tie-breaks, doubles
  rotation in the engine from day one; live scoreboard with one-hand portrait or landscape taps; Mark point bookmarks;
  undo = `Void` + refold; end types incl. service winner and forced/unforced errors; "Ad / No-Ad" and "Tie-break at
  6–6 / Advantage set" labels; `pct()` integer rounding shared with Android via conformance fixtures.
- **Label:** Manual. **Screens:** 4, 6, 9.

### P0-10 Point correction in replay that propagates everywhere
- **User value:** fix any point in seconds, and trust that every later score, stat and export updates.
- **Evidence:** 64 AI-accuracy reviews; correction tools the community's rank-5 wish (27 authors; add/split/merge/delete,
  persistent edits, override score); SwingVision corrections did not survive reprocessing until 11.9.63; edit window
  ~20 s; editing jumps to random shots (2026-07).
- **Approach:** flip winner, add a missed point, split/merge, delete, nudge start/end, mark "Needs review", set outcome
  `unknown` (later scores provisional); conflict types `serverMismatch`, `tiebreakAppeared/Vanished`,
  `pointsAfterMatchEnd`, `matchIncomplete`; "as called on court" vs "rules-derived" score; Rules vs As-played mode;
  automatic result and user edit stored separately; bulk select/deselect.
- **Label:** Manual (Reviewed). **Screens:** 10.

### P0-11 Fast Point Review deck + changeover checkpoint scoring — NEW
- **User value:** turn an unscored or mis-scored match into a correct point-by-point record in about five minutes,
  without trusting AI.
- **Evidence:** "fixing a missed point takes about as long as my own editor" (2026-09); manual player ID 5–10 min and
  "works about 20%" (2026-03); 170+ player identifications in one match (2024-08); players dislike constant wrist scoring
  (forum 2025-12).
- **Approach:** a card per bookmarked or detected point with a 3–4 s loop (`AVPlayerLooper`); swipe right "I won", left
  "Opponent won", up "Let / not a point", down "Unsure"; undo bar; progress "41 / 124". Optional live entry of the game
  score at changeovers (~10 taps a match); the engine auto-fills point winners consistent with legal game lengths and
  flags only inconsistent stretches (`checkpointConflict`). VoiceOver custom actions per card.
- **Label:** Manual for swiped points; **Estimated** for auto-filled points until reviewed. **Screens:** new surface
  (reached from 9 "Review 8 flagged points" and 10); checkpoint entry on 6.

### P0-12 Rally-only playback with visible gaps — NEW (visible-gap behaviour)
- **User value:** watch a two-hour match in about 20 minutes and still see what was skipped.
- **Evidence:** dead-time removal is the most praised SwingVision feature (31 reviews; community rank-1, 79 authors);
  its failure mode (points cut off, ~2 minutes skipped with no way to view gaps) is a rising complaint (1% → 6%);
  effective playing time is 10–30% of match time.
- **Approach:** `AVMutableComposition` of point ranges over the untouched original, built from Mark-point bookmarks or
  P0-13 detections; collapsed gaps as tappable "+0:42" chips; pre/post-roll defaults ≈1.5 s / 2.5 s, adjustable per
  session and per clip; full untrimmed video one tap away; filters (my points, second-serve returns, ≤5-shot points,
  break points).
- **Label:** Manual (from bookmarks) / Estimated (from detections). **Screens:** 10.

### P0-13 Automatic rally detection (audio + motion), benchmark-gated
- **User value:** dead time removed without tapping anything, on the phone, with no upload or quota.
- **Evidence:** at least 9 products trim automatically (table stakes); on-device is the 2026 differentiator (TennisCut,
  SmartHit, RallyTrim); padel audio+video hit detection F1 ≈92% (broadcast, CVPRW 2024).
- **Approach:** after recording: spectral-flux onsets on the audio track (`vDSP`), travel-time correction, hit/bounce/
  other classification, motion corroboration; rallies = hits with gaps < ~3 s; point gaps > ~5 s. Mic optional; if off,
  this capability is unavailable and the UI says so. Build it in v1 and run the benchmark in v1.
- **Gate:** own-court hits P ≥ 0.95, R ≥ 0.90, MAE ≤ 10 ms; ≥99% of hits inside kept clips; boundary F1 ≥ 0.90 at ±1 s;
  ≥10 sessions at ≥3 venues (multi-court, indoor, wind).
- **Label:** Validated-after-benchmark (registry `disabled` until the gate passes; then Estimated). **Screens:** 7, 10.

### P0-14 Match overview and Home with reproducible stats
- **User value:** the numbers players love, each one traceable to its points.
- **Evidence:** stats are the most-praised theme (158 reviews) and the most distrusted (AI accuracy ≈4% → 18% of
  SwingVision reviews); reference copy already shows denominators ("28 of 40 first-serve points won").
- **Approach:** stats from `tennis-rules-and-stats.md` §6 (1st in %, 1st/2nd points won incl. DFs, aces, DFs, BP saved/
  converted, total points won, rally-length buckets, streaks); fraction one tap away; Point History list (score, how it
  ended, play button); butterfly bars for head-to-head stats; "Shots" defined (`strokeCount` recommended); Home tiles
  from pooled counts; all sample data badged "Sample".
- **Label:** Manual / Reviewed (Estimated only for values from gated capabilities). **Screens:** 3, 9.

### P0-15 Clip export, Save to Photos, share
- **User value:** get a point, a set or the whole condensed match out of the app in seconds.
- **Evidence:** Onform users asked for export to camera roll (2024); "sharing took 15 minutes and was too large to
  message" (2025-10); SwingVision capped exports at 5 min (Free) and trimmed full-match export by tier.
- **Approach:** passthrough `AVAssetExportSession` with `timeRange`; composition for rally-only files; Save to Photos
  with `shouldMoveFile` (no extra space) via add-only permission; `ShareLink`; no length caps; long exports via
  `BGContinuedProcessingTask` on iOS 26.
- **Label:** n/a. **Screens:** 10, 19.

### P0-16 Compare two recordings with manual contact sync and basic drawing
- **User value:** see the difference between today's serve and last month's, frame by frame.
- **Evidence:** side-by-side compare is Onform's most frequent praise (20 reviews) and the most fragile (sync "hit or
  miss" 2025-07; VisualEyes compare freeze 2026-04); founder asked for analysis and comparison of swing and serve.
- **Approach:** time-origin sync (`syncEventTime` + `captureFPS`, never frame index); Align (independent jogs) → Lock
  "Synced at Contact" → ±1-frame Nudge; play one side alone; stacked portrait, side-by-side landscape; basic tools (line,
  arrow, circle, 2D angle, freehand) in a sticky Draw mode where the jog still scrubs; save as a project without
  duplicating video; own recordings only.
- **Label:** Manual. **Screens:** 14.

### P0-17 Google Drive archive (verified, resumable) + Space Saver
- **User value:** the founder's cloud storage: originals and analysis in *his* Drive, with proof each backup is complete.
- **Evidence:** founder prompt; 0 of 347 tennis listings mention Google Drive; SwingVision upload failures (stuck for
  days, stuck at 100%, deleted at low storage); free Google accounts hold 15 GB shared ≈ three 54-min sessions at 1080p60.
- **Approach:** `drive.file` scope only (non-sensitive: once the Cloud project is "In production", no unverified-app
  screen and no 100-new-user cap; in Testing status it is limited to 100 listed test users whose tokens expire after
  7 days; brand verification optional, recommended for name/logo; Google API User Data Policy / Limited Use: no
  Drive-derived data to AI services or training without explicit consent); GoogleSignIn 10.0.0 for
  connect/refresh/disconnect with App Check; resumable uploads with persisted session URI, pre-generated file IDs and
  offsets; background uploads via `GTMSessionUploadFetcher`; Wi-Fi-only as a toggle; "Backed up" only after size + MD5
  (+ SHA-256) match; versioned `session.jovra.json` sidecar; archive folder re-discovered by `appProperties`; quota
  preflight (`about.get`); `storageQuotaExceeded` → `quota_blocked` with options; **Space Saver** = rally-only
  passthrough archive copy (≈1.7 GB vs ≈4.9 GB for the sample match) and a 30 fps practice preset; never delete an
  original without explicit confirmation and a verified backup. Consent-screen homepage and policy on an
  `islanddevcrew.com` path (IDC doctrine), support `hello@islanddevcrew.com`. If OAuth isn't configured, the screen says
  "Awaiting Google Drive setup" — never a fake "Connected".
- **Gate:** the ten archive acceptance checks (technical-feasibility §13.8).
- **Label:** n/a. **Screens:** 7, 8, 19 (Space Saver is NEW).

### P0-18 Own-your-footage contract — NEW
- **User value:** never lose access to a recording made on your own phone, whatever plan, quota or login state.
- **Evidence:** SwingVision Free shows only the last 7 days of recordings (announced 2026-01-15; the "on the device"
  part is UNVERIFIED in the current app), ads on personal video (Free tier shipped in 11.9.49, 2026-02-04), hour quotas (8/16/30/60 h), Usage Data used to track; Onform lapsed users locked out
  (2026-09) and forced logins; community: 127 authors ask for local-first ownership; App Store guideline 5.1.1(v) (no
  login without account-based features).
- **Approach:** architectural: originals in the app container, always-available "Save original to Photos/Files", no
  server; first recording works with no account; Sign in with Apple optional; no third-party analytics SDKs (target
  App Privacy "Data Not Collected"); a short written promise on Welcome and Storage ("Your videos stay yours: no hour
  limits, no ads").
- **Label:** n/a. **Screens:** 1, 19, 20.

### P0-19 Handedness and backhand type for both players — NEW (opponent)
- **User value:** left-handers (and their opponents) get correct forehand/backhand stats, filters and diagrams.
- **Evidence:** SwingVision FH/BH filters assumed right-handers (2025-04 review); PB Vision's handedness fix "planned"
  since Dec 2024; only one of 347 tennis listings mentions left-handed support.
- **Approach:** handedness + one/two-handed backhand on every Player; set in onboarding (self) and setup (opponent);
  mirrored side-view diagrams; stroke logic and filters read it.
- **Label:** Manual. **Screens:** 2, 4.

### P0-20 Capability registry, provenance badges and Sample labelling
- **User value:** every number says how it was made and how much to trust it.
- **Evidence:** CLAUDE.md hard rule 1 and ADR-0004; SevenSix scored a swing it didn't recognise; speed outliers;
  TennisServe (states what the camera couldn't measure) and AI Tennis Swing Coach (disclaimers) show the honest pattern.
- **Approach:** registry statuses `manual / estimated / validated / unsupported / disabled` with method/model version;
  each derived value records capability, confidence, calibration dependency and denominator; badges "Manual",
  "Estimated", "Reviewed", "Sample"; capability detail page explains the method and gate result.
- **Label:** defines them. **Screens:** all (esp. 9, 11, 12, 13, 15, 16).

### P0-21 VoiceOver-first review and honest accessibility declarations — NEW
- **User value:** blind, low-vision and motor-impaired players and coaches can review points, correct scores and read
  trends; everyone benefits at large text sizes.
- **Evidence:** SwingVision declares 4 of 9 App Store accessibility labels and not VoiceOver; SevenSix and Onform declare
  none (Onform claims VoiceOver only in release notes); only 5 of 347 tennis listings mention accessibility.
- **Approach:** VoiceOver rotor of points ("Point 42, 4–3, 30–15, Alex serving, 8 shots, Jon won, needs review"); custom
  actions on review cards; adjustable timeline; Dynamic Type without truncation; 44×44 pt targets; meaning never by
  colour alone; `performAccessibilityAudit` in UI tests; declare only labels that pass.
- **Label:** n/a. **Screens:** all.

### P0-22 Settings and permissions that state consequences
- **User value:** no surprises: what each permission does, and what turning it off costs.
- **Evidence:** a competitor where disabling the microphone silently produced no recording (community 2023); screen 20
  shows "Microphone · Optional · Off" (which would disable audio detection) and "Photos · Selected photos" (not a state
  PhotosPicker produces).
- **Approach:** camera requested on entering capture; mic optional with inline consequence ("Off: rally detection and
  auto contact-sync unavailable; video still records"); "Use audio for detection, remove it from shared exports";
  Photos "Not needed for import" / "Add-only"; Open iOS Settings link; Export my data; Delete data with explicit scope.
- **Label:** n/a. **Screens:** 20.

---

## P1 — iOS v1 if feasible, otherwise the first update

### P1-01 Racket Vault + String Journal linked to sessions
- **Value:** know exactly which racket and string job you played each session with, and how long the strings have been
  in. **Evidence:** none of the big three mention strings or rackets in their listings; only one tennis app has a string
  tracker; the founder strings his own rackets; stringing-log apps praise "clone last job" and hours-or-age reminders.
- **Approach:** data model from raw/equipment-stringing.md §11 (FrameModel, Racket, StringProduct, StringInventoryItem,
  StringJob/StringSegment, Measurement, SetupRating, EquipmentUse); free text always allowed; tension stored **as
  entered** (52 lb never round-tripped); diameter in mm is the maths field, gauge label is text; machine type and
  pre-stretch optional; "Log a restring" clones the last job; **logged court time** computed from sessions; user-set
  reminders (hours and/or days), never predictions; mark "String broke" at a video time.
- **Label:** Manual (hours: "Logged court time", computed). **Screens:** 4 (gear row), 17, 18.

### P1-02 Performance by equipment setup (association only) — NEW
- **Value:** "with Hyper-G at 52 lb my first-serve % was X vs Y at 48 lb". **Evidence:** nobody links setups to
  performance (white space, raw/landscape.md §6). **Approach:** same session type only; sample sizes shown; minimum
  3 sessions and 100 points per setup; wording "Association in your sessions — not proof the strings caused it".
- **Label:** Estimated (association). **Screens:** 16, 18.

### P1-03 Manual shot placement and shot map
- **Value:** where your shots land, without pretending the camera measured it. **Evidence:** placement heat maps are a
  SwingVision staple; far-court video placement is coarse (0.2–0.4 m per pixel). **Approach:** tap bounces on the
  top-down court during review (or on the frame through the 4-tap homography); Deep/Mid/Short bins; In / Out / Needs
  review legend with shapes, not colour; correct court geometry from ITF dimensions; screen 11 copy changes from
  "Estimated from calibrated video" to the real provenance.
- **Label:** Manual. **Screens:** 10, 11.

### P1-04 Serve Lab (manual)
- **Value:** serve consistency work with real counts. **Evidence:** serve stats and Serve Practice are core SwingVision
  modes; a toss-to-contact stopwatch is a feature users missed from Coach's Eye; ServeFix/TennisServe phase checks.
- **Approach:** serve stats by deuce/ad from the event log; placement taps on a mini service box; serve key moments
  (Toss release, Trophy, Racket drop, Contact, Landing) set by the user; toss-to-contact timer; toss-consistency onion
  skin at the user-confirmed toss peak (same camera); the "104 mph" tile is hidden until P2-04 passes.
- **Label:** Manual. **Screens:** 12.

### P1-05 Stroke Lab (manual)
- **Value:** pick five forehands, line up their contact frames, see the difference. **Evidence:** focused stroke
  feedback demand (SevenSix, AI Swing Coach); kinogram/contact-strip exports (Kinovea, Dartfish StroMotion, Coach Video
  Analysis). **Approach:** auto-clip strokes from bookmarks with padded boundaries (−1.0/+1.0 s, nudgeable); named key
  moments; "Review" statuses instead of scores; contact strip export; mirror for left-handers; capture purpose (match vs
  side-on technique) chosen in setup.
- **Label:** Manual. **Screens:** 13.

### P1-06 Evidence-linked practice plan
- **Value:** one useful practice action after each session. **Evidence:** "one fault, one fix, one drill" (AI Swing
  Coach), fault grouping (INTER TENNIS), drills scored 0–100 (Wingfield); community wants "so what" insights (57
  authors); the 2026 AI-coach flood argues against chatbot coaching. **Approach:** deterministic rules over computed
  stats (e.g. first-serve points won < threshold → toss and serve+1 drills) with the evidence row ("28 / 40 first-serve
  points won") and "Watch evidence" clips; editable plan; labelled "Suggested practice".
- **Label:** Manual (rules applied to Manual/Reviewed stats). **Screens:** 15.

### P1-07 Progress trends with pooled denominators and goals
- **Value:** see the work pay off without being fooled by small samples. **Evidence:** trends sparklines are a
  SwingVision staple; community trusts relative trends more than absolute numbers; review asks for cross-session
  aggregates (2024-12) and same-type comparisons (2023-04). **Approach:** pool numerators/denominators; compare similar
  session types; percentage-point deltas from displayed integers; 4W / 3M / Year; Audio Graph descriptors; goals.
- **Label:** Manual / Reviewed. **Screens:** 3, 16.

### P1-08 Import with the Google Picker
- **Value:** import from Drive when the Drive app isn't installed, with stable file IDs. **Evidence:** founder wants
  Drive as his storage; the 2026 mobile Picker grants `drive.file` access to picked files and settles the prior brief's
  open "validate the picker" item (raw/drive-android-tech.md §0 item 2). **Approach:** mobile Picker via
  AppAuth (`trigger_onepick=true`, `drive.file` only), read `picked_file_ids`, download, verify MD5. **Label:** n/a.
  **Screens:** 7.

### P1-09 Share Pack — NEW
- **Value:** send a coach, partner or opponent exactly the points that matter, without them needing an app or a
  $20–$60/month coach plan. **Evidence:** coach–player loop is the #2 praise theme (146); "I just want to share a swing
  with my coach" (Onform 2024); ITF U18 rules require giving the opponent the recording; community rank 9 (sharing that
  respects viewers, 117 authors) and rank 14 (coach workflow, 58). **Approach:** selected clips (720p proxy or
  rally-only), notes, `match.json`, `points.csv`, static `index.html` viewer; AirDrop/Files zip or a Drive folder link
  with person-specific expiring grants (whether `drive.file` can create permissions is an API spike); default private.
- **Label:** n/a. **Screens:** 9, 10, new sheet.

### P1-10 Consent, competition and junior-parent mode — NEW
- **Value:** record respectfully and within the rules. **Evidence:** ITF U18 (Aug 2025): written consent from both
  parents, recording stops and is deleted if consent is withdrawn, full copy to the opponent, no posting; USTA Eastern
  bans video at junior sanctioned events; Apple Watch not permitted in ITF competition; community norm "ask first"
  (63-upvote comment, 52 authors); junior-parent reviews uniformly positive.
- **Approach:** consent row in setup (informed / written form attached / not required); Competition mode (no live
  feedback, no Watch prompts, rules reminder); Parent mode (child profiles local, private by default); one-tap "Delete
  this recording" during capture; match exports without audio by default; optional on-device face blur for bystanders.
  Legal wording reviewed before any compliance claim (COPPA/GDPR implications UNVERIFIED).
- **Label:** n/a. **Screens:** 4, 6, 20.

### P1-11 Open CSV/JSON export
- **Value:** coaches use spreadsheets; players own their data. **Evidence:** SwingVision ships stats export (Pro+,
  a 2026 fix mentions an export crash); founder wants ownership via Drive (raw/gap-finder.md #12). **Approach:** export the same versioned JSON as the
  sidecar (ADR-0002) plus points/stats CSV; publish the schema. **Label:** n/a. **Screens:** 19, 20.

### P1-12 Hands-free Mark point — NEW
- **Value:** bookmark a point from the baseline without walking to the fence or owning a Watch. **Evidence:** "not
  everybody has an Apple Watch"; Watch desync complaints; hands-free recording asks (AXEL review). **Approach:**
  `AVCaptureEventInteraction` (iOS 17.2+): volume/Action/Camera Control; AirPods H2 stem clicks on iOS 26; mapped to
  Mark point only, never Stop; confirmation tone. Device spike: Bluetooth range from the far baseline (24–30 m).
- **Label:** Manual. **Screens:** 6.

### P1-13 Recording status on the Lock Screen / Watch via Live Activity (spike-gated) — NEW
- **Value:** "REC 32:10 · saved 4 s ago" on the wrist without a Watch app. **Evidence:** iPhone Live Activities appear in
  the Watch Smart Stack (iOS 18 / watchOS 11); SwingVision's Watch said "recording" while the phone wasn't.
  **Approach:** ActivityKit with `Text(timerInterval:)`, updated from the journal heartbeat. **Spike:** does it show
  while the app is foreground-recording? If not, P2-16 (Watch app) is reconsidered. **Label:** n/a. **Screens:** 6.

### P1-14 Highlight reel with burned-in score
- **Value:** a shareable 60–90 s reel with the scoreboard. **Evidence:** 61 highlight/sharing praise reviews; repeated
  "how do I add scores?" questions; ScoreCam (1,826 ratings). **Approach:** Core Animation overlay from the fold
  (corrections re-render), vertical crop, captions, favourites from Mark point. **Label:** Manual / Reviewed.
  **Screens:** 10.

### P1-15 Pinned voice notes
- **Value:** a coach's spoken note attached to the exact frame. **Evidence:** voice notes/voice-over are standard in
  Onform, CoachNow and myDartfish; Onform quotas athletes (raw/video-analysis-apps.md). **Approach:** audio clip pinned to a frame or sync event;
  no render; no quotas (Onform caps athletes at 5/month). **Label:** n/a. **Screens:** 14.

### P1-16 Full drawing toolset with annotation lifetime
- **Value:** lines and angles that can be edited and that appear only when relevant. **Evidence:** CoachView/SlowMo/V1
  users want adjustable endpoints and saved drawings; SlowMo users wanted arrows that appear in time. **Approach:**
  editable shapes with handles, frame-range lifetime (default +12 frames), autosaved sidecar, stopwatch, spotlight,
  Pencil-only on iPad. **Label:** Manual. **Screens:** 13, 14.

### P1-17 Camera-moved detection and line-snap assist
- **Value:** know when wind or a bump invalidated the court calibration. **Evidence:** Toach 1.9.2 fixed losing the court
  lock after a bump; stick rotation in wind and curtains (community). **Approach:** homographic registration against
  the calibration frame; contour-based snap of tapped corners. **Gate:** 1° nudge detected ≥99%, <1 false alarm/hour;
  snap within 2 px in ≥95% of frames. **Label:** Validated-after-benchmark. **Screens:** 5.

### P1-18 All format presets and post-match edits
- **Value:** play the formats people actually play. **Evidence:** 37 community authors (standalone tie-breaks, no-ad,
  Canadian/Australian doubles, practice sets); SwingVision session type can't be changed after starting. **Approach:**
  presets in `tennis-rules-and-stats.md` §1.5; format and session type editable after the match with recompute and a
  warning when results change; Fast4 only after primary rules are confirmed. **Label:** n/a. **Screens:** 4, 9.

### P1-19 Doubles manual scoring UI
- **Value:** correct doubles scoring with server rotation and receiving sides. **Evidence:** doubles is common but
  under-served (community F12, 47 authors); SwingVision gated AI Coaching to singles. **Approach:** engine already
  supports rotation (P0-09); UI for serving/receiving order per set, team stats, per-server serve stats; automatic
  per-player attribution is Later. **Label:** Manual. **Screens:** 4, 6, 9.

### P1-20 Head-to-head history — NEW
- **Value:** your record and patterns against each opponent. **Evidence:** logging apps (Slice, Rally) ship it;
  SwingVision added frequent hitting partners (Jun 2026). **Approach:** local queries over sessions. **Label:** Manual.
  **Screens:** 9.

### P1-21 In-app diagnostics bundle — NEW
- **Value:** support that can fix a problem in one exchange. **Evidence:** 37 support complaints; AI-bot gating.
  **Approach:** OSLog export + session manifest + thermal log, zipped and attached only when the user taps "Send
  diagnostics"; no telemetry SDK. **Label:** n/a. **Screens:** 20.

### P1-22 HealthKit tennis workouts (opt-in)
- **Evidence:** SwingVision saves workouts to Activity/HealthKit (parity); iOS 26 brings `HKWorkoutSession` to iPhone
  (raw/gap-finder.md #18). **Approach:** `HKWorkoutBuilder` with `.tennis`, start/end of the session, session ID metadata; never invent calories
  or heart rate; never block recording on Health permission. **Label:** n/a. **Screens:** 20.

### P1-23 iPad review layout
- **Evidence:** 79 community authors want big-screen editing; SwingVision iPad editing criticised. **Approach:** split
  view for Point Review, replay and compare; keyboard shortcuts. **Label:** n/a. **Screens:** 10, 14.

### P1-24 Localization foundation and metric units
- **Evidence:** SwingVision ships 9 languages, Onform 21 (Aug 2026), SevenSix added 7 on 2026-10-07; an Onform review
  asks for metric units (raw/gap-finder.md #21). **Approach:** String Catalogs from day one; `Measurement` units (mph/km·h, lb/kg, in²/cm²); Spanish first.
  **Label:** n/a. **Screens:** 20.

### P1-25 Transparent pricing (decision for Jon)
- **Evidence:** price is the #1 SwingVision theme in 2024–26 (59 keyword hits); willingness ≈$50/yr for trimming,
  "<$10/mo". **Straw man:** free forever = record, replay, manual scoring, Point Review, rally-only from bookmarks,
  export, Drive archive; paid (one-time or ≈$40–$80/yr) = gated automatic analysis, highlights, labs, recaps; Family
  Sharing; no hour caps, ads, weekly plans or silent trial-to-annual. StoreKit paywall with exact terms, restore,
  entitlement states (implementation-states.md). **Label:** n/a. **Screens:** 19, 20.

### P1-26 App Intents / Siri / Shortcuts
- **Evidence:** SwingVision supports Siri session start and background exports with a Live Activity (parity;
  raw/gap-finder.md #15). **Approach:** "Start singles recording" opens framing in the foreground (the camera cannot run in the background);
  "Show last match"; "Analyze when charging". Avoid Siri while recording (mic interruption risk). **Label:** n/a.
  **Screens:** 3.

---

## P2 — next (after iOS v1), including Android

### P2-01 Android port
- **Value:** the largest structural gap in the market. **Evidence:** no SwingVision/SevenSix/Toach on Play; Onform
  2.97★ on Android; 147 community authors ask; Tennis Math (a no-video scorekeeper) 4.61★ / 3,345 shows
  correction-friendly charting wins Android ratings ("absent from Play" rests on a no-JavaScript search: re-check
  before launch). **Approach:** Kotlin + Compose + CameraX 1.6.2 (60 fps via `SessionConfig` / `GroupableFeature.FPS_60`,
  available since 1.5.0 and device-dependent, checked with `isSessionConfigSupported`; crash-resilient Media3 muxer by
  default since 1.6.0)
  + Media3 1.11.1 + Transformer; target API 36, minSdk 29, 16 KB pages; AuthorizationClient + UIDT uploads (not a
  long `dataSync` foreground service: 6 h / 24 h shared budget when targeting 35+, handle `onTimeout`); same JSON
  schemas and conformance fixtures (ADR-0001); Pixel thermal soak. **Label:** per capability (same gates, run per
  platform). **Screens:** all.

### P2-02 2D pose overlay on side-on clips
- **Gate and approach:** technical-feasibility §11; confidence-thresholded joints only, L/R swap correction, "2D pose
  estimate", no degree decimals or norms. Near player only for match footage. **Label:** Validated-after-benchmark.
  **Screens:** 13.

### P2-03 Automatic stroke classification (near player)
- **Gate:** ≥300 strokes/class/end, ≥20% left-handers, held-out players; near ≥0.90 → Estimated; far < 0.80 →
  "Unknown". **Label:** Validated-after-benchmark. **Screens:** 10, 13.

### P2-04 Serve detection and serve speed
- **Evidence:** speed outliers are a running joke (120–140 mph rec serves); independent test ~6% error in-bounds, ~42%
  on net-cord serves. **Gate:** ≥200 serves vs radar, MAPE ≤ 7%, 90% within ±10%; speed defined as average flight speed;
  outliers flagged; otherwise relative-only. **Label:** Validated-after-benchmark. **Screens:** 12.

### P2-05 Automatic contact sync in compare
- **Approach:** audio impact transient and/or wrist-speed peak; always "Suggested · confirm". **Gate:** frame error at
  60/240 fps on labelled clips. **Label:** Validated-after-benchmark. **Screens:** 14.

### P2-06 Voice-over walkthrough export and transcription
- **Approach:** event-timeline recording (mic audio + playhead/rate/step/drawing events; ReplayKit can't capture
  AVPlayer); live preview with `AVSynchronizedLayer`; export with `AVMutableComposition` + the Core Animation tool or a
  custom `AVVideoCompositing` compositor (either is valid); optional face-cam; captions/transcripts with
  `SpeechAnalyzer` (iOS 26). **Evidence:** voice-over is Onform's/CoachNow's standard coaching tool and Onform added
  transcription in 4.7.0 (2026-09-26); Onform caps athlete voice-overs at 5/month (competitive-analysis §3.2). **Label:** n/a. **Screens:** 14.

### P2-07 Practice instant-replay / delay loop — NEW
- **Value:** see the last serve a few seconds later on a second device or the same phone between reps. **Evidence:**
  community rank 18 (12 authors across three venues; no incumbent serves it well); BaM Video Delay 4.77★.
  **Approach:** rolling buffer playback with N-second delay; works with recording off or on. **Label:** n/a.
  **Screens:** new surface.

### P2-08 Remote viewfinder from any second phone
- **Evidence:** TennisCut's two-phone remote with camera battery/storage telemetry; SwingVision's QR remote needs
  internet on both devices. **Approach:** local-network (Multipeer/Wi-Fi Aware) preview and Mark point; Android viewer
  later. **Label:** n/a. **Screens:** 5, 6.

### P2-09 Pitch check (relative string-bed change) — NEW
- **Value:** "your strings have dropped ~8% since you strung them". **Evidence:** RacquetTune reviewers value relative
  tracking and distrust absolute numbers; physics makes the ratio robust (`T/T₀ = (f/f₀)²`). **Gate:** bench protocol
  in technical-feasibility §15 + CN/EP/WO freedom-to-operate search; never called a sensor or meter; screen 18's v1
  copy ("No automated tension sensor") stays until a decision record changes it. **Label:** Validated-after-benchmark.
  **Screens:** 18.

### P2-10 On-device recap text — NEW
- **Evidence:** community wants "so what" insights (57 authors, P1-06); the 2026 AI-coach flood (~40 apps) and SevenSix
  removing its AI Coach argue for descriptive, evidence-linked text rather than coaching (raw/gap-finder.md #23).
- **Approach:** Foundation Models guided generation referencing computed stat IDs; every number post-checked against
  the fold, else template fallback; descriptive, not coaching. **Label:** Estimated (numbers verified). **Screens:** 9.

### P2-11 "Review the clip together" — NEW
- **Value:** the useful part of line challenges without officiating: both players can look at the replay on a second
  screen. **Evidence:** mid-match replay is widely seen as rude when one-sided (61-comment r/10s thread); agreed use
  among friends is fine. **Approach:** shareable last-point clip to a nearby device; no in/out verdict. **Label:** n/a.
  **Screens:** 10.

### P2-12 UTR result copy / self-post link — evidence: UTR self-posted casual scores count only after opponent confirmation; USTA Connect needs an established user base (raw/gap-finder.md #26). **Label:** n/a. **Screens:** 9.
### P2-13 Practice counters from audio hits (ball machine, rally streaks, serve counts) — evidence: SwingVision ships ball-machine, serve-practice and Goal Mode sessions (parity; raw/gap-finder.md #24, competitive-analysis §2.1). **Label:** Validated-after-benchmark (reuses P0-13). **Screens:** 12, 16.
### P2-14 Pickleball mode (sport-agnostic schema from day one) — evidence: SwingVision supports pickleball but its pickleball reviews average 3.37★ with attribution complaints; PB Vision and many 2026 apps (raw/gap-finder.md #27). **Label:** per capability. **Screens:** 4.
### P2-15 Lock Screen quick record (`LockedCameraCapture`) — evidence: iOS 18 lets third-party camera apps launch from the Lock Screen/Control Center/Action button; the extension has no network and must hand off (raw/gap-finder.md #28). **Label:** n/a. **Screens:** 6.
### P2-16 Apple Watch app (only if the P1-13 spike fails) — phone stays the source of truth; Watch shows recorder heartbeat, not an assumed state. **Label:** n/a. **Screens:** new surface.
### P2-17 Mac review (Catalyst or SwiftUI multiplatform) — evidence: SwingVision ships a Mac app; big-screen review requests (raw/gap-finder.md #22). **Label:** n/a. **Screens:** 10, 14.

---

## Later — needs a validated prerequisite

| ID | Item | Prerequisite | Label |
|---|---|---|---|
| L-01 | Ball tracking for match footage (TrackNet-class Core ML detector + Kalman/physics) | Labelled amateur fence-camera dataset; gate recall ≥0.9 near / ≥0.7 far | Validated-after-benchmark |
| L-02 | Video-derived bounce map and depth bins | L-01; median ≤0.3 m near / ≤0.8 m far | Validated-after-benchmark |
| L-03 | Two-phone multi-angle merge | Single-camera pipeline validated; audio-clap sync | Validated-after-benchmark |
| L-04 | Automatic doubles player attribution and positioning | Four-player tracking | Validated-after-benchmark |
| L-05 | Serve-target games with bounce localization | L-02 | Validated-after-benchmark |
| L-06 | Padel | Glass reflections; separate court model | Validated-after-benchmark |
| L-07 | ITF PAT approval for competition use | Stable product version; process | n/a |
| L-08 | AI auto-scoring of point winners | Winner is not inferable from audio; needs ball + pose + rules fusion | Validated-after-benchmark |
| L-09 | Optional server analysis (private object storage + async worker) | Only if on-device benchmarks fail; explicit opt-in, retention and cost disclosure | Validated-after-benchmark |
| L-10 | USTA Connect / rating integrations | Partner programme requires an established user base | n/a |

---

## Never — deliberate non-goals

| ID | Non-goal | Why (evidence) |
|---|---|---|
| N-01 | Line calls or challenge verdicts presented as officiating | Far baseline 0.2–0.4 m per pixel vs 5–10 cm lines; ITF approval of SwingVision explicitly does not certify accuracy; accuracy complaints outnumber praise |
| N-02 | Ads, cross-app tracking, default training-data sharing | The differentiator vs SwingVision (Free-tier ads, shipped 2026-02-04; Usage Data used to track); screen 20 already shows "Training data sharing · Off" |
| N-03 | Locking a user's own video by age, tier or lapse; hour caps on on-device work | SwingVision 7-day lock and caps; Onform lapsed lockout — top emotional complaints |
| N-04 | Spin RPM, numeric 3D biomechanics, injury or medical claims | Unsupported by single-camera evidence; brief and CLAUDE.md hard rule 1 |
| N-05 | Pro-player comparison library or likenesses | Licensing and likeness; brief bans unauthorized professional likeness |
| N-06 | String "tension sensor", string-life prediction, arm-health claims | Physics makes absolute readings unreliable (in-racket 30–40% below pull); screen 18 forbids; competitors' arm claims are unsupported |
| N-07 | Weekly plans; trials that convert to annual silently; annual price quoted as a misleading monthly | SwingVision trial/bundle complaints and the stale description quoting Pro at $14.99/mo vs the $24.99 Pro Monthly IAP (V1) |
| N-08 | Live streaming (v1) | Server cost; minors (ITF bans posting U18 footage) |
| N-09 | Requiring cloud upload before review | SwingVision's review-after-upload flow; CLAUDE.md hard rule 2–3 |
| N-10 | Shipping Match Charting Project data, or importing competitor string/tension databases without a licence | MCP is CC BY-NC-SA 4.0; TWU/RacquetTune/stringster databases carry no reuse licence |

---

## Decisions for Jon (blocking or shaping v1)

1. **iOS deployment target**: ADR-0005 says iOS 17; this research recommends iOS 26.0 (or 18.0 as a fallback) because
   older code paths cannot be tested on the build machine and key features are 26-only (technical-feasibility §16.1).
2. **Pricing model** (P1-25): free core forever vs SwingVision-style tiers.
3. **Google Cloud project, OAuth client and "In production" status** (homepage/policy on an `islanddevcrew.com`
   path), so P0-17 can leave "awaiting setup". Brand verification is optional (name/logo on the consent screen only).
4. **"Shots" definition, fixture first server, Point 42 timestamp** (`tennis-rules-and-stats.md` §9).
5. **Microphone default** for match sessions (detection value vs audio privacy).
6. **Equipment catalog strategy**: user-entered only in v1 (recommended) vs a curated, sourced catalog.
7. **Originals in iCloud device backup** (P0-07): include by default (Apple's guidance for irreplaceable content, but
   multi-GB backups) or exclude by default with disclosure and a Drive/Photos prompt.
8. **Pricing is partly blocked by a measurement gap**: we know price is one of the two biggest complaint groups, but not
   whether it outranks reliability (V2). Treat both as P0-grade concerns.

---

## Sources

All accessed 2026-10-07. This backlog synthesizes the research files below; their own Sources sections carry the
primary URLs.

| File / URL | What it supported |
|---|---|
| /Users/IDC2.5/jv/docs/research/competitive-analysis.md | Pros/cons, counts, praised/complaint tables |
| /Users/IDC2.5/jv/docs/research/technical-feasibility.md | Approaches, APIs, gates, registry statuses |
| /Users/IDC2.5/jv/docs/research/tennis-rules-and-stats.md | Scoring engine, stat definitions, fixture constraints |
| /Users/IDC2.5/jv/docs/research/raw/gap-finder.md | Ranked opportunities (Fast Point Review, checkpoint scoring, Space Saver, consent mode, VoiceOver-first, handedness) |
| /Users/IDC2.5/jv/docs/research/raw/community.md | Wishlist ranks and author counts; etiquette; instant-replay demand |
| /Users/IDC2.5/jv/docs/research/raw/review-mining.md | Love/pain counts and trends |
| /Users/IDC2.5/jv/docs/research/raw/swingvision.md | Steal/Improve/Avoid list; pricing and caps; release-note themes |
| /Users/IDC2.5/jv/docs/research/raw/video-analysis-apps.md | Scrub, draw, compare, voice-over specifications |
| /Users/IDC2.5/jv/docs/research/raw/equipment-stringing.md | Equipment data model and pitch-check gate |
| /Users/IDC2.5/jv/docs/research/raw/landscape.md | White space, pricing tiers, Android gap |
| /Users/IDC2.5/jv/docs/research/raw/ios-tech.md and raw/drive-android-tech.md | Platform constraints and gates |
| /Users/IDC2.5/jv/docs/handoff/JON-ORIGINAL-PROMPT.md | Founder intent (record, Drive, analyse, compare, iOS then Android) |
| /Users/IDC2.5/jv/design-reference/brief/research.md, product-brief.md, screens.json, implementation-states.md | Prior sequencing, screen spine, auxiliary states |
| https://www.itftennis.com/media/15017/itf-performance-analysis-video-u18-august-2025.pdf | ITF U18 recording rules (consent mode) |
| https://developer.apple.com/app-store/review/guidelines/ | 5.1.1(v) no-login rule |
| https://support.google.com/drive/answer/9312312 | 15 GB free Google storage |
