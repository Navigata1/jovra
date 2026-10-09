# T12 bounded native component evidence

## Scope and custody

This is part of issue #14, not completion of the full component ticket. StateCard, DemoBanner, SampleBadge, FixtureBadge and compact/on-forest ProvenanceBadge support the authorized native recording-to-export flow. The opt-in DEBUG gallery is a test surface; actions report caller callbacks, not working recording/settings/export features.

Source candidate: `c8673d95567e466b720d244fe8e2dd4793ab9c0d`, integrating main `017d9da`. Isolated branch `codex/t12-core-state-components`; dedicated iPhone 17 Pro iOS 26.5 simulator `4265ADFD-39A3-4E71-8482-1945DDB5F899`. All native build products belong to this worktree. No shared device, original checkout or Claude branch was changed.

## Red controls and real failures

The missing empty-state Record action and missing Sample/fixture labels each failed before implementation (01/01b and 03 logs), then passed (02/04). The full first gallery audit at source `2ca5cc7` failed Dynamic Type on caption2 compact badges (06). Switching to caption cleared that finding; the next audit reported too-small hit areas on generic accessibility containers (08). Exposing the combined badges as read-only static text and keeping regular vertical padding corrected the semantic issue. The same unmodified `.all` accessibility audit then passed all badge appearances and explicit Sample action/label tests (09: 2 passed, zero failed). No audit category is ignored or waived.

The diagnostic raw receipts are retained locally in `diagnostic-xcresults.tar.gz`; the committed manifest records all eight receipts, original failed/passed status, SHA-256 and verified tar integrity. The 06/08 activity JSON and exported failure attachments preserve exact audit descriptions and app/element images. A green rerun does not erase earlier failures.

## Exact candidate verification

`SIMULATOR_ID=4265ADFD-39A3-4E71-8482-1945DDB5F899 DERIVED_DATA="$PWD/.derivedData" scripts/ios/test.sh` passed at c867: JovraCore 34, JovraMedia 63, hosted JovraTests 70, total 167 with zero failures. See 10-final-units.log.

`BRANCH=codex/t12-core-state-components BASE=origin/main scripts/l10n/check.sh` passed at c867: 32 localization tool tests + 12 iOS tool tests, zero literal/copy findings, one changed owned catalog and zero ownership problems. See 13-final-l10n.log. The earlier 05 log, run before committing, saw zero changed catalogs and is not the ownership proof.

At c867, the complete CoreComponentsUITests class passed 4/0, including all 15 scenario/appearance accessibility audits (11-final-gallery-ui.log). Inspected native AX5 empty state, AX5 badges and dark error screenshots: text scales, badges preserve full words, scrollable content stays legible, error action remains clear. This is a component-gallery visual review, not reference-screen or full-product approval.

Independent Spec review found a genuine interface mismatch: screens.md S03 requires DemoBanner “Make it yours” to lead toward onboarding, while the initial shared component hardcoded Leave sample. A focused CTA expectation failed (14: 0/1) before correction. Source 820782cd05f556907f6a1f44c69a65b931d5001a now exposes caller-owned actionTitle/action with localized Make it yours default; the gallery callback honestly says Onboarding requested. No T18 onboarding flow is claimed. Domain independently accepted this correction; Standards review has no source findings.

The first corrected action/badge run (15) is UNVERIFIED: xcodebuild could not write a receipt because mkstemp reported No space left on device. Info.plist is missing; receipt reading/export failed closed (exit64). It is not counted as a pass or an app defect. The broken receipt and console are archived alongside c867 baseline and the CTA red control. Only owned inactive SwiftPM/index artifacts were reclaimed before a fresh focused retry. The unchanged 167-unit pass remains bound to c867; final corrected UI compilation checks the changed view signature.

At corrected source 820782c, the focused action/badge retry passed 2/0 with a valid Passed receipt (17); three light/dark/AX5 badge audits and default CTA callback are green. Inspected t12-sample-cta.png shows Make it yours and honest Onboarding requested; inspected final AX5 badges remain full-word, scalable static text. Five-tab AX5 regression passed 1/0 at 820782c, auditing all five tabs with no waiver (18). The initial Home screenshot was inspected for the shared shell at AX5; its Sample header is below this screenshot viewport, so no Home-specific pill visual claim is made. The unchanged component itself is visually inspected at AX5 in the gallery. Total accepted UI executions are 4 baseline at c867 + 2 corrected components at 820782c + 1 corrected global AX5 at 820782c; these are not represented as seven tests all rerun on one head. Prior 09 badge pass was pre-commit and is not misrepresented as the final source candidate receipt.

## Remaining acceptance work

Production Capture/Library consumers follow in bounded slices. Full T12 remains pending: additional components/variants, fractions and zero denominators, capability registry detail/substitution, motion/haptics/announcements, whole-component gallery, regular-width proof and photographic asset scan. Numeric contrast tests pass for the reused color pairs; this slice does not establish an increased-contrast simulator runtime check. iOS 18 runtime, physical hardware and store readiness remain unverified. Studio/Android/watch/tablet work and step 5 remain held.
