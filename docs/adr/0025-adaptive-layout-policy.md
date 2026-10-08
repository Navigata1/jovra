# Adaptive layout: choose panes from the window, posture and text size, never the device; layout changes never repeat side effects

Status: accepted (2026-10-07). Applies to the iOS app (iPhone, iPad, any future foldable iPhone) and the Android app
(phones, tablets, foldables). Watch layouts are ADR-0026's, not this ADR's. The breakpoint numbers below are Android's
published window size classes (OBSERVED); the pane counts and the text-size rule are JOVRA decisions (INFERRED from
the adaptive brief) and are tested by the shared pane-policy vectors proposed below.

Jon's Adaptive/Watch v3 direction targets Pixel 10-class and Galaxy S26-class phones, the Pixel 10 Pro Fold's cover
and inner displays, Android tablets and an adaptive iOS layout, while keeping the five phone destinations
(`docs/handoff/adaptive-v3/CLAUDE-ADAPTIVE-WATCH-PROMPT.md`, OBSERVED). A named device is a moving target and lies
about the space an app actually has (split screen, freeform windows, Stage Manager, a half-opened fold). So layout is
a pure function of the window and its posture, and everything a user is in the middle of is state that outlives any
layout.

## Decision

**1. Inputs, and what is never an input.** A layout is chosen from: available window **width** and **height** (dp on
Android, points on iOS), folding **posture** and hinge **occlusion** where the platform reports them, input mode
(touch, keyboard, pointer) and the user's **text size**. Device model, brand, marketing name, screen diagonal,
physical pixels and an "is tablet" flag are never inputs. Android's guidance says the same: window size classes "are
not intended for isTablet-type logic" and are "determined by the window size available to your application", and they
change during the app's life (OBSERVED, developer.android.com window size classes).

**2. One breakpoint table for both platforms** (Android's classes, OBSERVED; applied to iOS points as INFERRED parity):

| Width | Range | Height | Range |
|---|---|---|---|
| Compact | < 600 | Compact | < 480 |
| Medium | 600–839 | Medium | 480–899 |
| Expanded | 840–1199 | Expanded | ≥ 900 |
| Large | 1200–1599 | | |
| Extra-large | ≥ 1600 | | |

Android reads them from `currentWindowAdaptiveInfo()` (never hard-coded viewport sizes). iOS computes the same class
from the scene's container size in points, with horizontal size class as a cross-check; it does not route on
`userInterfaceIdiom`.

**3. Pane counts by width AND height.**

| Window | Panes | Navigation |
|---|---|---|
| Width compact | 1, sequential flows; supporting content in a sheet | Bottom bar (5 destinations) |
| Width medium | 1, or list/detail 2 when height is at least medium | Rail |
| Width expanded | 2 (list/detail or main/supporting) | Rail |
| Width large or extra-large | up to 3 (lesson workspace, Studio editor + inspector) when height is at least medium | Rail or sidebar |
| **Height compact, any width** | at most 2; the player keeps priority and supporting panels become sheets | Rail |
| Accessibility text sizes (Android font scale ≥ 1.5; iOS accessibility Dynamic Type sizes) | one fewer than the table, never below 1 | unchanged |

A diagonal size never earns a third pane by itself. Every extra pane must improve the task (replay + notes, sync
review + angle list, editor + inspector); a stretched phone card is not a pane. The five phone destinations (Home,
Sessions, Record, Insights, Profile) stay the top-level structure at every size; Studio workspaces may add a
contextual tool rail.

**4. Posture and hinges (Android, and any platform that reports them).** From `FoldingFeature` (OBSERVED fields:
`state` FLAT/HALF_OPENED, `orientation`, `isSeparating`, `occlusionType` NONE/FULL):
- a separating hinge splits panes on the hinge; no control or touch target sits within or beside its bounds
  (Android: "Don't place UI controls too close to a fold or hinge when isSeparating is true", OBSERVED);
- `occlusionType == FULL` means no content inside the hinge bounds;
- **tabletop** (HALF_OPENED, horizontal hinge): the player above, transport controls and marks below;
- **book** (HALF_OPENED, vertical hinge): list/detail across the hinge;
- a posture is a hint for arrangement only. It never starts, stops or pauses capture or playback.

**5. iOS foldables: generic adaptive layouts only, until a verified API exists.** On 2026-10-07 the build Mac has
Xcode 26.6 (17F113) with the iOS 26.5 and watchOS 26.5 simulator runtimes; `simctl` lists 125 device types and none is
a foldable iPhone ("iPhone Duo"); and the iOS 26.5 SDK's UIKit headers and SwiftUI interface contain no hinge, fold or
posture symbol (all OBSERVED locally). Apple's September 2026 announcement and the October 23 retail date are
UNVERIFIED here. Therefore iOS handles a cover↔expanded change exactly as any other resize: the same breakpoint table,
the same preserved state, no hinge avoidance, no tabletop mode, and no Android folding concepts ported across.
References 71–72 are layout studies, not a tested integration. When an Xcode/SDK release provides a simulator profile
or a documented posture API, an amendment to this ADR adds it as an input, after inspection.

**6. Preserved-state contract.** These survive resize, split screen, fold/unfold, rotation, cover↔inner/expanded,
backgrounding and process death:

| State | Where it lives | On restore |
|---|---|---|
| Selected destination, session, project, angle, pane | Saveable back stack of serializable keys (Android Navigation 3; iOS scene storage) holding **IDs**, never view objects | Same selection, rebuilt into whatever panes the new window allows |
| Playhead | Rational media time per session/project (never a frame index or pixel offset) | Same instant; paused if it was paused |
| Unsaved notes, draft cuts, edit-plan drafts, bookmark text | Draft documents autosaved to the project folder (ADR-0002), debounced and on background | Restored from disk after process death |
| Pending command IDs, quote IDs, job IDs, idempotency keys | Persisted **before** the request is sent | Reconciled with the server or room; never re-minted |
| Local capture | Segments and journal (ADR-0010) | Recovery scan, as for any interruption |
| Remote status (room, watch, cloud job) | Cache only | **Unknown** until renewed; never restored as fresh |

**7. A layout change never repeats a side effect.** Rendering is idempotent. No film job, cloud quote acceptance,
credit reservation, purchase, score event, invite, upload or camera command is ever issued from composition, a view
appearing, a lifecycle callback or a configuration change; only from an explicit user action, carrying an ID minted
and stored at that action (ADR-0019 idempotent reservation, ADR-0003 point events, ADR-0027 commands). A re-created
screen finds the stored ID and shows its current receipt instead of sending again. A confirmation sheet that was open
during the change is restored still unconfirmed. Recording is **not** promised to survive a particular fold or
rotation: if the platform interrupts the camera, the segment closes and a gap is journalled (ADR-0010), and the UI says
so; a display change is never permission to stop recording silently.

**8. Shared pane-policy vectors (proposal for the contracts owner).** The rule in §3–§4 is a pure function
`(widthDp, heightDp, posture, hinge, textScaleBand, task) → (panes, navigation)`. It should live as golden vectors
under `spec/` and be implemented in Kotlin and Swift like any other contract (ADR-0001), so the two apps cannot drift.
This ADR does not create that file; `spec/` and `spec/studio/` belong to their owners.

**9. Evidence levels, reported separately.** Layout evidence names the installed emulator or simulator profile and
the window it produced (OBSERVED profiles: `pixel_9`, `pixel_9_pro_fold`, `pixel_tablet`, a custom 360 dp phone;
iPhone 17 family and iPad simulators). Approximations (Pixel 10, Galaxy S26, Pixel 10 Pro Fold outer display, any
foldable iPhone) are labelled approximations. Each layout gate covers compact→expanded→compact, rotation, split screen,
fold/unfold, process death (Android "Don't keep activities" or `adb shell am kill`; iOS terminate and relaunch),
largest text size, TalkBack/VoiceOver and keyboard. Hinge timing, camera continuity across a fold and thermals are
physical-device evidence only.

## Note (2026-10-07): where this ADR is applied

No decision changes. A review found three documents applying this ADR inconsistently; they were corrected the same
day to follow it: `docs/spec/adaptive-screens.md` §0.2 (height compact allows two panes; font scale ≥ 1.5 removes one
pane unconditionally), its iOS study I71 (three columns only at width Large and height at least Medium; no hinge or
crease precaution on iOS, per §5), and `docs/spec/android-v1-spec.md` AD15 (input mode as an input; the unconditional
font-scale rule). §8's shared pane-policy vectors now have an owner ticket and a gate (G-PANE, android-v1-spec), and
the iOS core and Studio screens are mapped onto §2–§3 with a preserved-state test plan in adaptive-screens §4.5.

## Considered Options

- **Branch on device model or "is tablet".** Rejected: wrong in split screen and freeform windows, wrong on the next
  device, and Android's guidance rejects it.
- **Pane count from width alone.** Rejected: a wide landscape phone or a half-height split window has no room for a
  player plus two panels. Height and text size are inputs.
- **Separate breakpoints per platform.** Rejected: the same window would get different layouts on iOS and Android with
  nothing to test parity against.
- **Wait for a foldable iPhone API before any iOS adaptive work.** Rejected: iPad windows, Stage Manager and rotation
  already need the generic path, and the generic path is the correct fallback whatever Apple ships.
- **Keep state in views and rely on configuration-change retention.** Rejected: it does not survive process death,
  and re-created views are where duplicate submissions come from.

## Consequences

Every screen is designed in at least three widths and the compact-height case. Studio editors gain real workspaces on
tablets and unfolded phones without a separate codebase. Drafts are written to disk continuously, which costs some
I/O, in exchange for surviving process death. A future iOS posture API arrives as an amendment, not a rewrite.

Sources: https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes (breakpoints and
quotes, accessed 2026-10-07); https://developer.android.com/develop/ui/compose/layouts/adaptive/foldables/make-your-app-fold-aware
(FoldingFeature fields, tabletop/book, hinge guidance, accessed 2026-10-07);
https://developer.android.com/develop/adaptive-apps/guides/canonical-layouts ; local `xcodebuild -version`,
`xcrun simctl list runtimes`, `xcrun simctl list devicetypes` and a grep of `iPhoneOS26.5.sdk` UIKit headers and the
SwiftUI interface (OBSERVED 2026-10-07); `design-reference/adaptive/brief/platform-and-device-plan.md`,
`acceptance-matrix.md`; `.claude/skills/jovra-adaptive-native-ui/SKILL.md`;
`docs/research/android/toolchain-and-devices.md` §§1.4, 4.1, 7; `docs/adr/0002`, `0003`, `0010`, `0019`, `0024`.
