---
module: progress
reference: [spec/reference/studio/progress.py]
cases: [spec/reference/studio/cases/progress_cases.py]
kinds: [progress-comparison]
coverage: covered
swift: pending
kotlin: pending
---

# Progress: Progress Story comparability

`spec/reference/studio/progress.py` is the reference for `ProgressStoryBuilder.compare` (Studio spec, Domain modules;
user stories 134–137). `spec/reference/studio/cases/progress_cases.py` writes the `progress-comparison` vectors and
registers their checker and one self-test. `python3 scripts/spec/validate_studio.py --list` prints the current case
count and the Swift and Kotlin status. Swift ticket S36 flips `swift:` here when its tests reproduce every vector.

## The rule

`compare(statDefinitionId, earlier, later)` takes two dated scopes of one stat. A scope carries `date` (YYYY-MM-DD),
`sessionIds`, `sessionKind`, `statDefinitionId`, `methodId`, `methodVersion`, `capabilityVersion` (or null),
`selectionRule` (`all`, `seeded-random` or `user-chosen`), `numerator`, `denominator` and `provenance`. The result:

- **Fractions.** Each side keeps its numerator and denominator, the core integer `pct(n, d) = (200n + d) div 2d`
  (half up, never Python's half-even `round`) and the display `"12 / 30 · 40%"`; `0 / 0` shows an em dash.
- **Comparable** only when the stat definition is the requested one on both sides, the method (`methodId`,
  `methodVersion`, `capabilityVersion`) matches, the session kind matches, the selection rule matches and both sides
  are at least Reviewed (`reviewed` or `validated`), and neither sample is empty.
- **Reasons**, every one that applies, in this order: `statDefinitionChange`, `methodChange`, `sessionKindChange`,
  `differingSelection`, `notReviewed`, `emptySample`.
- **Delta.** Only when comparable: `deltaPercentagePoints` is the later displayed integer minus the earlier displayed
  integer (1 / 8 shown 13% and 5 / 16 shown 31% give 18, not the exact 18.75 rounded to 19), with the core wording
  (`+20 percentage points`, `+1 percentage point`, `0 percentage points`, `-10 percentage points`) and the summary line
  `"12 / 30 · 40% → 18 / 30 · 60%, +20 percentage points"` (story 134). `claim` is `change` or `no-change`.
- **Not comparable** means the comparison is dropped (story 135): no delta, no summary, and `claim: chronology`, so the
  film falls back to a lesson chronology (story 137). The fractions stay as dated facts.
- **Hand-picked examples** carry `selectionLabel: "Examples you chose"` on that side (story 136).
- A percentage "improvement" of a proportion is never produced; the checker fails any output that words one.
- **Refusals:** a later date that is not after the earlier one (`notChronological`), a numerator outside
  `0..denominator` (`badFraction`), and a malformed scope (`badScope`).

## Vectors

The base case is the Sample progress brief's comparison (`records/story-brief.progress.json`, `cmp-first-serve`): the
serve practice of 2026-09-09 (12 / 30) and 2026-10-07 (18 / 30), both Reviewed, selection `all`. The brief does not
store a session kind or a method version, so the cases add `practice` and `1` (the method id is `manual-tagging-v1`).
Every other case changes one or more fields of that comparison: a later method or capability version, one or both
sides user-chosen, seeded-random against all, estimated or manual evidence, validated evidence, match against
practice, another stat definition, several reasons at once, no change, a decline, a one-point change, a delta from
displayed integers, half-up ties, an empty earlier sample, dates out of order and a numerator above the denominator.

Each case stores `expect` (the reference output) and an `assert` block worked by hand from the stories and the `pct`
rule; the checker compares both. The self-test `progress-brief-display` checks that the display strings the Sample
brief stores (`12 / 30 · 40%`, `18 / 30 · 60%`, `+20 percentage points`) are what `compare` gives for its scopes.

## Decisions

- Both sides `user-chosen` is comparable (the rules match, as the spec states), and both sides are labelled.
- A capability version change counts as a method change.
- The session kind and method version of the Sample comparison are vector inputs, because the story-brief record
  has no field for them.

## Not covered yet

- `journey(lessons) -> [Milestone]` (lesson order with focus lines) has no vectors yet.
- The comparison's scopes are inputs: nothing here derives the numerator and denominator from stored events. The core
  StatsEngine owns that; S36 wires it.
