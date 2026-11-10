# JOVRA · whole-project reassessment, 2026-11-09

Written by Claude after the founder asked for the whole application and its
build process to be reconsidered. Every number below was read from the live
repository at main `88a579c` on 2026-11-09. Nothing here is a completion
percentage.

## The short version

1. **The app specified for v1 is not the app the founder asked for.** The
   founder wants his own version of an automatic tennis analysis app. Spec
   decision D10 (`docs/spec/ios-v1-spec.md`) puts ball tracking, automatic
   stroke classification, automatic serve detection and speed, automatic
   bounce maps and automatic scoring **out of scope** and marks them
   `unsupported`. The repository contains no Vision or Core ML code. As
   specified, v1 is a careful manual-tagging and review tool.
2. **The app on main is a shell around strong engines.** 14 of the 23 feature
   folders under `ios/Jovra/Features` are placeholders of about 11 lines
   (Calibration, Point Review, Point Editor, Processing, Highlights, Onboarding
   and others). Home, Library, Capture, Replay and Export are real. The engines
   underneath (contracts, scoring, stats, capture journal, recovery) are solid
   and tested.
3. **The process now produces evidence faster than product.** 63 pull requests
   are open and 54 of them are drafts, stacked up to 13 deep, some on a base
   that cannot merge until an owner review is recorded. Of the 23 commits that
   reached main in the last day, 18 are "Record …" documentation commits.
4. **The path to completion is narrower, not broader:** finish one platform
   (iPhone) end to end, add a real analysis engine with benchmark gates, and
   only then port. Section 4 is the plan.

## 1. What is strong and should be kept

- **Contracts and engines.** Session schema, canonical JSON, one rounding
  function, scoring and stats engines with byte parity against a Python
  reference. Corrections propagate. Provenance is carried on every number.
- **Capture durability.** Segmented recording with a write-ahead journal,
  startup recovery, torn-segment recovery.
- **Physical iPhone proof.** A 71-minute match imported on the device with the
  retained original matching the source, and a signed build that survived
  background, return, resume, save and Replay.
- **The honesty model.** Capability registry, `manual / estimated / reviewed /
  validated` provenance, Sample labels. This is what will let automatic
  analysis ship without overclaiming.

## 2. What is wrong

### 2.1 Product: the analysis engine does not exist and is not planned

| Capability a player expects | v1 spec status | Code on main |
| --- | --- | --- |
| Automatic rally and point detection | Audio hits only, benchmark-gated (T34) | Rally segmentation core from bookmarks; no detector |
| Shot detection and stroke type | `unsupported` (D10) | None |
| Ball tracking | `unsupported` (D10) | None |
| Shot placement / bounce map | Manual marking only | Placeholder screen |
| Serve speed | Manual-assisted estimate | None |
| Pose overlays | On demand, "not benchmarked" | None |
| Automatic court calibration | 4 manual taps; line-snap assist optional | Geometry maths in an open PR |

The research (`docs/research/technical-feasibility.md`) was right about the
physics: from behind the baseline at 720p–1080p the far-court ball is 2–3
pixels and officiating-grade line calls are not achievable. It then chose the
most conservative response, which was to build none of it. The commercial
references prove a middle path works on a single phone: high mounting, 1080p60
or 4K capture, a heatmap ball detector, court keypoints, pose, and results
shown as estimates the player can correct.

### 2.2 Depth: screens are placeholders

Real: Home (102 lines), Sessions (371), Capture and Record (396), Replay (396),
Export (210), Insights (109). Placeholder: everything else. The reviewed
point-correction UI in Replay still edits raw milliseconds in text fields.

### 2.3 Process

- **Spec-to-code ratio.** `spec/` holds 302,566 lines and `docs/` 61,512. The
  app target holds 17,298 lines of Swift; the five Swift packages hold about
  30,000 lines of source.
- **Draft stacks.** Playback (T14) has 15 open pull requests representing three
  successive attempts. Android A04 is a 13-deep stack on A01, and A01 cannot
  merge until ADR issues #375 and #376 are decided.
- **Owner-review gates in a one-person company.** W03 #407, A14 #374 and A01
  #378 are verified but blocked on a recorded owner review. Automation cannot
  clear them.
- **CI does not build the app.** The `ios-app` job runs only on manual
  dispatch. Its comment says macOS minutes are scarce on a private repo; the
  repo has been public since 2026-10-11, so that reason no longer holds. The
  hosted runner uses an older Xcode than the build Mac, which is what broke
  #517's manual run.
- **No server-side protection on main.** The merge policy in ADR-0006 is a
  convention only.
- **Disk.** 120 git worktrees of this repository exist across the internal
  disk, a temp folder and external volumes, on a machine with 20 GB free. Low
  disk is already blocking the iPad audit run.

### 2.4 Breadth

iPhone, iPad, Android phone/tablet/foldable, Apple Watch, Wear OS, Studio
multi-camera films and a cloud backend are all open at once: 99 Android, 84
Studio, 46 core and 25 watch issues. No `android/` directory exists on main.
ADR-0001 already says Android ports **after** the iOS gates.

## 3. Failing tests and their causes

| Failure | Cause | Fix |
| --- | --- | --- |
| Hosted macOS build of JovraMedia (#517 manual run) | Two Swift type-inference sites the older hosted Xcode cannot solve | **Fixed.** #519 merged as `88a579c` after green automatic and manual runs |
| iPad Replay accessibility audit on iOS 27.2 (error −56) | Not diagnosed. #453 (Dynamic Type transport) and #456 (Export backdrop) are candidate fixes | Free disk, run the unchanged full audit on each candidate, land the one that passes |
| watchOS suite: Series 11 and SE 3 at 18/19 | One harness test; focused reruns pass, full suite does not. Likely ordering or timing in the fake bridge (#522 addresses ordering) | Run the full 19 on #522's head on all three watch sizes |
| W03 `testAcknowledgeClosesTheAlertSheet` | Same family as above | Same run |
| #502 and #504 CI "internal error" | GitHub infrastructure, not code | Re-run once; do not open duplicates |
| Physical Files picker cancel/swipe | Real defect or test-automation limit on device; unresolved | Reproduce by hand on the iPhone with #517 installed |

## 4. The plan

### Phase 0 · Stabilize (first)

1. Land the reviewed iPhone drafts on current main: playback foundation #512,
   then timeline #514, then Files duplicates #517. Close the superseded T14
   drafts with a pointer to the PR that replaced them.
2. Make `ios-app` run automatically on pull requests that touch `ios/`, on a
   runner image with a current Xcode. Turn on branch protection for main with
   the required checks.
3. Clear the three owner gates in one sitting (section 5, decision C).
4. Reclaim disk: remove worktrees whose branches are merged or closed.
5. One rule for evidence: it goes in the pull request that changes the code.
   No standalone "Record …" commits. Maximum stack depth of two.

### Phase 1 · A complete iPhone loop

Replace placeholders along the path a player actually walks, one vertical
slice per pull request, each ending with a signed run on the iPhone:

`T21 setup → T23 framing and calibration → T17 record → T24 live scoring →
T28 smart replay → T30 fast review → T29 point editor → T22 match overview →
T19 home → T36/T37 export`

### Phase 2 · The analysis engine (new "V" track; needs decision A)

Each stage ships as `estimated`, always reviewable, and is switched on only
when its benchmark gate passes. The gates already exist in the feasibility
table.

| Stage | What it adds | Approach | Gate |
| --- | --- | --- | --- |
| V1 | Labelled benchmark | A local labelling tool over the founder's three recordings (hits, bounces, strokes, court corners). Footage never leaves the Mac | Label set exists and is hashed |
| V2 | Automatic court calibration | Court-line keypoint model → homography; manual 4-tap stays as fallback | Line RMSE ≤ 3 px |
| V3 | Player tracking and pose | Vision body-pose on the near player; far player box only | Keypoint agreement on labelled frames |
| V4 | Ball detection | Heatmap detector (TrackNet class) converted to Core ML, run only in windows around audio hits; `VNDetectTrajectoriesRequest` for side-on practice clips | Recall ≥ 0.9 near, ≥ 0.7 far |
| V5 | Shot and rally detection | Fuse audio onsets, ball direction change and wrist speed → hits → rallies → point candidates | Hit P ≥ 0.95, R ≥ 0.90 |
| V6 | Stroke type | Small temporal classifier over pose windows (forehand, backhand, serve, volley) | Accuracy ≥ 0.90 near player |
| V7 | Placement and serve speed | Bounce → court coordinates through the homography; speed as a range | Median ≤ 0.3 m near half; speed within ±10% |

Line calls, spin and biomechanics stay `unsupported`. Capture guidance changes
to 1080p60 or 4K with a high mount, because ball detection depends on it.

### Phase 3 · Port and extend

Android (phone first), then the watch remote, then Studio. Each starts when
the iPhone phase it mirrors has passed its device gate.

## 5. Decisions only the founder can make

**Answered 2026-11-09:** the founder said yes to A and B. They are recorded in
[ADR-0031](../../adr/0031-automatic-analysis-in-v1-and-iphone-first.md). C is
still open.

- **A. Reverse D10** and add the V track, so that automatic analysis is in v1
  as `estimated` capabilities behind benchmark gates.
- **B. Sequence iPhone first.** Pause new Android, watch and Studio tickets
  until Phase 1 and V1–V5 pass on the iPhone. Open drafts stay as they are.
- **C. Owner gates.** Either record the three reviews (W03 #407, A14 #374,
  A01 #378 with ADR #375/#376), or authorize the lead agent to record owner
  review after an adversarial verification passes.

## 6. Evidence labels for this document

Repository counts, CI results and the #519 merge are **verified** against
GitHub and the working tree. The Phase 2 approach is a **plan**: no model has
been trained or measured on the founder's footage yet, and accuracy targets
are gates, not results.
