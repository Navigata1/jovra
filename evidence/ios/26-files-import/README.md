# Safe Files import evidence · 2026-11-08

Native source tested at `d3049a830e81b0e65c08b3d8ab906d8714ab50d4`.
The publication merge with main preserved the complete tested tree.

- iPhone 18 Pro simulator (iOS 27.2, Xcode 27.2): 11 passed, zero failed.
  CoreFlow, native Files picker cancellation and accessibility, viewport
  controls, five hosted import tests, and startup recovery.
- iPhone 15 Pro Max (iOS 27.0.1): all five signed hosted import tests passed.
  A separate startup recovery test in that run failed on a path alias and
  passed in the focused rerun for PR #395.
- Refusal tests cover a symlink, invalid media, a substituted staged original,
  and cancellation before publication. Interrupted staging cleanup and staged
  original substitution failed before their respective fixes. Active staging is preserved.
- The attached synthetic session is actual encoder output from the copy,
  reopen, and replay test. Independent checks verified its session schema,
  canonical bytes, original byte count and SHA-256 against the 12-second fixture.

Actual external-provider selection, Photos and batch import, duplicate
resolution, explicit iCloud waiting, the broader accessibility matrix,
and real match footage remain follow-ups to issue #28. Raw test bundles
are retained locally.
