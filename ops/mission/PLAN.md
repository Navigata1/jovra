# Authorized continuation: JOVRA core recording-to-export flow

Founder authorization (2026-10-09): “proceed with 1-4 and hold for 5 , when you get there ill give the green light to proceed”.

1. Preserve Claude worktrees and reconcile current main.
2. Independently review and finish T02 / PR 66 and T07 / PR 321.
3. Resolve contract inconsistencies affecting the core flow and add coverage for existing Studio reference validators. This is verification of existing code, not expansion of Studio functionality.
4. Deliver and test one native iOS flow: record → durable local save → session library → replay → reviewed scoring → clip and data export. Existing ticket acceptance criteria remain authoritative; completing this flow does not close unrelated or partially fulfilled feature tickets.

Hold before step 5: no Studio film creation implementation, Android, foldable/tablet expansion, or watch companions. No hosted activation or paid processing. Physical device and store readiness remain separate gates.

Read CLAUDE.md, docs/spec/ios-v1-spec.md, docs/spec/screens.md, docs/spec/tickets.md, GLOSSARY.md and the relevant ADR before each feature. Use a dedicated simulator and derived data; preserve original media.

## Step 5 green light and repository visibility (2026-10-11)

Founder authorization (2026-10-11): "green light step 5, you take over core while also merging the 7 waiting codex prs".
Claude Code now drives the core track and step 5 (Studio, Android, adaptive and watch tickets) through the ticket DAGs
in `docs/spec/`. Codex PRs #365–#371 are merged in dependency order after fresh green CI.

The repository was made public on 2026-10-11 at the founder's request, so GitHub Actions on standard runners is no
longer blocked by the account billing limit recorded in `ops/mission/evidence/github-actions-payment-gate.json`.
Public visibility does not change the hard rules in `CLAUDE.md`: real footage, secrets and personal addresses never
enter the repository. Hosted activation, paid processing, physical-device and store readiness remain separate gates.
