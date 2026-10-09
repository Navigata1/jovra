# Authorized continuation: JOVRA core recording-to-export flow

Founder authorization (2026-10-09): “proceed with 1-4 and hold for 5 , when you get there ill give the green light to proceed”.

1. Preserve Claude worktrees and reconcile current main.
2. Independently review and finish T02 / PR 66 and T07 / PR 321.
3. Resolve contract inconsistencies affecting the core flow and add coverage for existing Studio reference validators. This is verification of existing code, not expansion of Studio functionality.
4. Deliver and test one native iOS flow: record → durable local save → session library → replay → reviewed scoring → clip and data export. Existing ticket acceptance criteria remain authoritative; completing this flow does not close unrelated or partially fulfilled feature tickets.

Hold before step 5: no Studio film creation implementation, Android, foldable/tablet expansion, or watch companions. No hosted activation or paid processing. Physical device and store readiness remain separate gates.

Read CLAUDE.md, docs/spec/ios-v1-spec.md, docs/spec/screens.md, docs/spec/tickets.md, GLOSSARY.md and the relevant ADR before each feature. Use a dedicated simulator and derived data; preserve original media.
