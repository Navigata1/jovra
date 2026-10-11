# Shared pane-policy contract (`spec/adaptive/`)

Status: **proposal contract, 2026-10-11 (A14, finding F-PANE-VECTORS, gate G-PANE).** Pending review by the `spec/`
contracts owner. It turns ADR-0025 §1–§5 into golden vectors so the Android (A15, Kotlin) and iOS (W22, Swift) pane
policies cannot drift (ADR-0001: shared contracts, not code). Passing the validator proves the vectors, the ADR's
breakpoint table and the Python reference agree. It proves nothing about Compose or SwiftUI layouts, real hinges or
devices; those are A15/W22 and the layout gates in ADR-0025 §9.

```
spec/adaptive/
  pane-policy.vectors.json     golden vectors (110) + text-scale band cases (9)
  reference/pane_policy.py     Python 3 standard-library reference: decide(), text_scale_band(), BREAKPOINTS
scripts/spec/validate_adaptive.py   validates everything; --mutations proves the checks fail on known-bad inputs
.github/workflows/adaptive.yml      runs both on pull requests touching these files (ci.yml is not involved)
```

Run from the repo root:

```
python3 scripts/spec/validate_adaptive.py              # prints the vector count; -v lists categories
python3 scripts/spec/validate_adaptive.py --mutations  # each removed rule / broken vector must fail
```

## The function

```
(widthDp, heightDp, posture, hinge, textScaleBand, inputMode, task)
    -> (widthClass, heightClass, panes, navigation, arrangement, hingeBounds)
```

| Input | Values | Android source | iOS source |
|---|---|---|---|
| `widthDp`, `heightDp` | window size | `currentWindowAdaptiveInfo()` (dp) | the scene's container size (points) |
| `posture` | `none`, `flat`, `halfOpened` | `FoldingFeature.state`; `none` when no folding feature | always `none` (ADR-0025 §5) |
| `hinge` | `null` or `{orientation, separating, occluding}` | `FoldingFeature.orientation`, `isSeparating`, `occlusionType == FULL` (or `HingeInfo.isVertical/isSeparating/isOccluding`) | always `null` |
| `textScaleBand` | `default`, `accessibility` | font scale ≥ 1.5 | `DynamicTypeSize.isAccessibilitySize` |
| `inputMode` | `touch`, `keyboard`, `pointer` | input mode | input mode |
| `task` | `listDetail`, `supporting`, `player`, `workspace` | the screen's pane structure | same |

Never inputs: device model, brand, marketing name, diagonal, physical pixels, "is tablet", `userInterfaceIdiom`.

Tasks are the screen's pane structure, not the screen: `listDetail` (list ∣ detail: Sessions, Insights, Settings),
`supporting` (main ∣ supporting: quote 57, setup summaries), `player` (video ∣ supporting, the player has priority:
replay, player 47, storyboard 56) and `workspace` (list ∣ detail ∣ inspector: lesson 55, Studio sync 46, Studio Home).

| Output | Values | Meaning |
|---|---|---|
| `panes` | 1–3 | how many panes the screen shows; content beyond that goes to sheets or pushed panes |
| `navigation` | `bottomBar`, `rail` | the top-level five destinations' chrome |
| `arrangement` | `single`, `columns`, `splitAtHinge`, `tabletop` | `splitAtHinge`: the pane boundary is the hinge; `tabletop`: picture above the hinge, controls below |
| `hingeBounds` | `ignore`, `noControls`, `noContent` | `noControls`: no control or touch target in or beside a separating hinge; `noContent`: nothing at all inside an occluding hinge |

## Rules, in order (reference docstring has the same list)

1. Classify width and height by ADR-0025 §2 (`breakpoints` in the vectors; the validator checks it against the ADR).
2. Window table (§3): width compact 1; medium 2 only for a list-led task (`listDetail`, `workspace`) with height at
   least medium, else 1; expanded 2; large and extra-large up to 3; never more than the task's own panes.
3. Height compact: at most 2; a `player` gets 1 (supporting panels become sheets).
4. A separating vertical hinge (flat with `isSeparating`, or book posture): exactly 2, split at the hinge. Tabletop
   (half-opened, horizontal hinge) with a `player`: 2, picture above, controls below. A fold that does not separate is
   ignored.
5. Accessibility text band: one fewer pane, never below 1, unconditionally. Navigation unchanged.
6. Navigation: bottom bar on compact width unless height is compact; rail otherwise.

Input mode never changes panes or navigation.

## Tags and how the ports use them

Every vector has an `id`, `tags`, a `note`, `input` and `expected`. Font-scale vectors name their default-band
`baseline`; input-mode vectors share a `group`.

| Tag | Count | Checked by the validator |
|---|---|---|
| `matrix` | 60 | all 5 width classes × 3 height classes × 4 tasks are present |
| `boundary` | 14 | breakpoint edges (599, 599.9, 600, 839, 840, …; 479, 479.9, 480, 899, 900) |
| `compactHeight` | 7 | at most 2 panes; a player has 1 unless a separating vertical hinge splits the window |
| `fontScale` | 9 | exactly one fewer pane than the baseline, never below 1, same navigation; a reduction and a floor case exist |
| `inputMode` | 12 | each group covers touch, keyboard and pointer, differs only by input mode, expects one layout |
| `posture` | 15 | present **exactly** when the input has a posture or hinge; such ids also start with `posture-` |
| `separatingHinge`, `occludingHinge`, `nonSeparatingFold`, `tabletop` | 10, 2, 1, 3 | the matching arrangement and hinge bounds |

- **Android (A15):** run every vector, posture included (one dynamic test per vector).
- **iOS (W22):** run every vector without the `posture` tag; skip the 15 `posture` vectors by tag (their ids start
  with `posture-`) and list the reason (ADR-0025 §5: no posture input on iOS), never silently.

## Decisions for the contracts owner's review

These follow ADR-0025 but resolve wording the ADR leaves open; each is pinned by a vector so the ports agree.

1. **Medium width.** ADR-0025 §3: "1, or list/detail 2 when height is at least medium". `supporting` and `player`
   stay at 1 on medium width; `workspace` (list-led) gets 2. Some per-screen notes in `adaptive-screens.md` say
   "Medium+: start pane / end pane" for supporting layouts; the ADR wins here (vector
   `matrix-medium-medium-supporting`).
2. **Hinge before height.** A separating vertical hinge gives exactly 2 even for a player at compact height (vector
   `posture-separating-vertical-compact-height-player`): the hinge physically divides the window.
3. **Font scale after the hinge.** User story 204: an unfolded phone at a large font scale falls back from two panes to
   one (`posture-separating-vertical-font-scale`); the hinge-bounds rule still applies.
4. **Tabletop for non-player screens** keeps the table's columns and treats the hinge band as `noControls`
   (`posture-tabletop-listDetail-keeps-columns`).
5. **Navigation at compact height.** ADR-0025 §3 puts a rail on any compact-height window, including compact width
   (`compact-height-compact-width-supporting`). Material's default navigation-suite type for compact height and for
   tabletop may differ (recalled, UNVERIFIED here); A15 must set the type from this policy rather than the default.

## Changing the contract

A rule change lands here first, as a vector change, then in both ports. Keep vector ids stable (ports may name them in
skip lists). The validator fails if ADR-0025 §2's table and `breakpoints` disagree, so a breakpoint change edits the ADR
(as an amendment) and the vectors together.
