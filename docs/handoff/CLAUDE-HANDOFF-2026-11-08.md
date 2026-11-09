# JOVRA · Claude → Codex handoff, November 8 (evening)

Claude ran the v4 ticket pipeline from 02:30 to about 21:00 CST on 2026-11-08 and
then paused it, after the S58 merge landed, at Jon's request so Codex can continue. This note picks up where
[CODEX-CONTINUATION-2026-11-08.md](CODEX-CONTINUATION-2026-11-08.md) left off.
Read that first for the Codex-owned slices (T16/T17/T26 device work, S88).

Every merge below went through the same gate: one implementer, an adversarial
verifier (up to four rounds), a fix agent for each blocking finding, then a
serialized squash merge on green required CI. Simulator results are reported
separately from device results. Agents did not install to or run on physical
devices. Every device-only acceptance item is listed under
[Device-pending](#device-pending) and counts as **unverified**.

## Merged by this run (25 tickets)

| Ticket | PR | What landed |
| --- | --- | --- |
| T08 | [#384](https://github.com/Navigata1/jovra/pull/384) | Session store: single-writer document store, state facets, index, Trash, purge, retention, backup custody |
| S77 | [#380](https://github.com/Navigata1/jovra/pull/380) | Migration 2: sources, manifests, sync, calibration, event revisions, RLS |
| S04 | [#379](https://github.com/Navigata1/jovra/pull/379) | Studio packages, project wiring, Studio Info.plist keys, Studio CI |
| T04 | [#386](https://github.com/Navigata1/jovra/pull/386) | Scoring engine: re-analysis protection (decision 24), recalculation diff, `sideMismatch` from observed `servedFromSide` (decision 25, session schema 1.2.0) |
| T11 | [#391](https://github.com/Navigata1/jovra/pull/391) | Synthetic sample video, practice clips, benchmark corpus |
| W01 | [#387](https://github.com/Navigata1/jovra/pull/387) | Swift JovraRoom part 1: spec/room records and invalid cases |
| T15 | [#399](https://github.com/Navigata1/jovra/pull/399) | Capture engine: segment pipeline, write-ahead journal, fixture camera |
| S78 | [#398](https://github.com/Navigata1/jovra/pull/398) | Migration 3: quotes, reservations, jobs, attempts, artifacts, grants |
| S10 | [#400](https://github.com/Navigata1/jovra/pull/400) | JovraStudioCore Codable models for every `jovra.*` Studio contract |
| T32 | [#402](https://github.com/Navigata1/jovra/pull/402) | Rally segmentation core and rally-only composition |
| T05 | [#405](https://github.com/Navigata1/jovra/pull/405) | Stats engine, JSON and CSV data export, pooled trends |
| W02 | [#406](https://github.com/Navigata1/jovra/pull/406) | JovraRoom part 2: commit-then-reveal invitations, ledger |
| T09 | [#411](https://github.com/Navigata1/jovra/pull/411) | Sample library: eight sample sessions, equipment, practice plans |
| S79 | [#414](https://github.com/Navigata1/jovra/pull/414) | Gateway command functions with actor re-checks |
| S11 | [#418](https://github.com/Navigata1/jovra/pull/418) | EDL validator in Swift with parity to `edl.py` |
| S08 | [#409](https://github.com/Navigata1/jovra/pull/409) | Studio media fixtures: barcode and click sources at 24/30/60 fps |
| T60 | [#416](https://github.com/Navigata1/jovra/pull/416) | Live Activity spike decision report: drop from v1 |
| T16 | [#420](https://github.com/Navigata1/jovra/pull/420) | Crash recovery: RecoveryScanner, torn segments, gap reports, media-services rebuild (simulator) |
| S12 | [#425](https://github.com/Navigata1/jovra/pull/425) | Job and quote/consent state machines, reservation ledger, parity with Python |
| T40 | [#429](https://github.com/Navigata1/jovra/pull/429) | Sample analysis content: stroke tags, placements, calibrations, serve marks, swing moments |
| T12 | [#421](https://github.com/Navigata1/jovra/pull/421) | Design-system extensions: state components, provenance and sample badges, capability detail, hero art |
| S13 | [#427](https://github.com/Navigata1/jovra/pull/427) | StudioProjectStore and removable Studio sample content |
| S80 | [#430](https://github.com/Navigata1/jovra/pull/430) | Orchestrator command functions: lease-fenced `*_for_attempt` commands |
| S09 | [#436](https://github.com/Navigata1/jovra/pull/436) | Barcode-court trusted context and compile vectors over the S08 media |
| S58 | [#438](https://github.com/Navigata1/jovra/pull/438) | Synthetic multi-angle fixture generator with ground truth, drift, restarts, late starts, shake, muted cameras |

Simulator gate on main before this run: `CoreFlowUITests` 1/1 passed on iOS 27.2
(iPhone 17 Pro simulator `JOVRA-HW-Gate-Sim`). It has not been rerun on the
newest main.

## Open PRs, by state

| PR | Ticket | State | What it needs |
| --- | --- | --- | --- |
| [#441](https://github.com/Navigata1/jovra/pull/441) | T13 court calibration | CI green, verify round 1 was in progress at pause | Re-run the verifier, then merge |
| [#440](https://github.com/Navigata1/jovra/pull/440) | S14 CloudClient + demo | CI green, verify round 1 was in progress at pause | Re-run the verifier, then merge |
| [#442](https://github.com/Navigata1/jovra/pull/442) | T14 playback core | Implemented, CI was still running at pause | Let CI finish, then verify and merge |
| [#443](https://github.com/Navigata1/jovra/pull/443) | S35 Studio keepers and staleness | Opened by the implementer just before the pause; **not verified** | Run the adversarial verify, then merge |
| [#444](https://github.com/Navigata1/jovra/pull/444) | S36 Studio lessons core | Opened by the implementer just before the pause; **not verified** | Run the adversarial verify, then merge |
| [#407](https://github.com/Navigata1/jovra/pull/407) | W03 watchOS target | Blocked after 4 verify rounds | (1) **Core-owner review of the `ios/project.yml` diff** (Jon). (2) `HarnessSelfTests.testAcknowledgeClosesTheAlertSheet` failed on the clean rerun. (3) Embedding the watch app in the phone app moved to follow-up [#419](https://github.com/Navigata1/jovra/issues/419) |
| [#374](https://github.com/Navigata1/jovra/pull/374) | A14 pane-policy vectors | Blocked after 4 verify rounds | Issue #192 AC 4b: **a recorded review from the spec/ contracts owner** (Jon). The code itself verified clean |
| [#378](https://github.com/Navigata1/jovra/pull/378) | A01 Android foundation | Draft, blocked after 4 verify rounds | Issue #179 merge gate: link a merged F-ADR-0001 header note and a merged ADR/amendment ([#375](https://github.com/Navigata1/jovra/issues/375), [#376](https://github.com/Navigata1/jovra/issues/376)). Every Android ticket and the Pixel test wait on this |
| [#389](https://github.com/Navigata1/jovra/pull/389) / [#394](https://github.com/Navigata1/jovra/pull/394) | S88 planner adapter | **Codex-owned** | Claude excluded S88 and did not touch #389. Codex decides which branch to adopt and closes the other |

Owner-review gates (W03, A14, A01) are governance gates, not code defects. The
pipeline cannot clear them alone. Jon records the review on GitHub, or a
ticket amendment drops the criterion.

## Ready next (all dependencies merged)

Core: T13 #15, T14 #16, T17 #19, T18 #20, T19 #21, T20 #22, T21 #23, T26 #28,
T27 #29, T47 #49, T48 #50, T49 #51, T51 #53, T56 #58.
Studio: S14 #83, S35 #104 and S36 #105 (PRs open), S40 #109, S82 #151, S88 #157 (Codex).
Android/Watch: A01 #179, A14 #192, W03 #280. All three are gated as above.

State at pause: 290 tickets, 41 closed, 249 open (core 46, studio 80,
android+watch 123). T17, T26 and T16's device slices remain Codex's per the
earlier handoff.

## Device-pending

Nothing on this list has been run on hardware. Each item is **unverified**
until a signed device run records evidence.

- **T15 capture, iPhone 15 Pro Max:** CameraSource lens choice (ultra-wide when
  the court needs it), locked frame rate, stabilization off, focus/exposure/WB
  locks. Real interruptions (call, alarm, Siri, another camera app). Live
  DeviceBudget (battery, Low Power, thermal) and the critical-heat 60→30 fps
  downgrade. Crash-loss budget after a real kill, AV sync, endurance.
- **T16 recovery:** the ≤ 3 s crash-loss bound (ADR-0010) and power-loss safety:
  record, force-quit or jetsam mid-segment, relaunch, compare. A real
  `mediaServicesWereReset` (Developer → Reset Media Services) rebuilding into a
  new segment with a `cameraError` gap.
- **T12 haptics:** feel `.selection/.success/.warning` on the phone. Only a unit
  mapping test covers them today.
- **S04 Studio:** the Local Network prompt, `_jovra-room._tcp` Bonjour advertising,
  and acceptance of the `continued.studio-render` BG task.
- **W01/W02 Room:** freshness across real sleep on a paired watch and phone.
- **W03 watch:** install through the companion flow on the paired Apple Watch
  once #419 embeds it.
- **T60 (spike, dropped from v1):** the hardware questions are recorded in the
  decision report in case Live Activities are revisited.

The signed device build that worked earlier today:

```bash
xcodebuild -project ios/Jovra.xcodeproj -scheme Jovra -configuration Debug \
  -destination 'id=00008130-001834312E31001C' -derivedDataPath .derivedData \
  DEVELOPMENT_TEAM=C8Z4ABP78D CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates build
```

Run `xcodegen` in `ios/` first. UI Automation is enabled on the iPhone; Codex's
signed run passed six tests.

## Pipeline mechanics (if Codex or Claude resumes it)

- Script: `/Users/IDC2.5/JOVRA-media/pipelines/implement-workflow-v4.js`.
  Ticket DAG: `/Users/IDC2.5/JOVRA-media/pipelines/all-tickets-compact.json`.
- The paused run is `wf_e62580b9-b7c`. Resume it with the same args (including
  `exclude: ["S88"]`) and cached results replay. Re-running with fresh args
  starts from the ticket DAG and skips closed issues.
- Ticket worktrees live in `/Users/IDC2.5/jv/.claude/worktrees/<slug>`. Each
  open PR above has one. Delete `.derivedData*` folders inside them when done,
  because disk is tight.
- All GitHub calls go through `/Users/IDC2.5/.local/bin/gh-navigata1`.
- Leave the KindlyCrew simulator, the OlamyPixel AVD and `~/.colima` alone.
