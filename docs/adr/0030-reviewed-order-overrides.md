# ADR-0030: Reviewed serving and receiving order in Rules and As-Played views

Status: proposed; shared reference pairs must be independently accepted before this amendment merges.

## Problem and authority

The iOS specification promises Rules and As-Played views, but the 1.1 contract/reference accepts only an observed
`recordedServer` and always uses the rules-derived order. Native-only override types would break shared conformance.

ITF 2026 Rule 27c distinguishes a mid-game service correction from a completed game whose altered order remains;
27d distinguishes even and odd tie-break discovery; 27e keeps an altered doubles receiving order until that game's
end. The primary source is the [2026 Rules of Tennis](https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf),
printed pages 12–13, verified 2026-10-09. These rules motivate explicit reviewed observations. The app does not
infer when an error was discovered, adjudicate open faults or provide automated officiating.

## Additive shared contract

Session schema 1.2.0 adds optional `match.resolutionMode: rules | asPlayed`; absence means rules. Engine input takes
the same optional field; the public fold may override it explicitly. Existing 1.0/1.1 records/fixtures remain byte
identical. The 1.0/1.1 version guards refuse these new fields/events. Swift exposes `SchemaVersion.current` as 1.2.0;
other document kinds retain their existing independent version defaults.

Two closed, concrete log events share id, positive increasing seq, optional at/note, provenance (`manual` or
`reviewed` only), source, and same-type supersedes. They do not consume a point slot or change score counts.

- `serverOverride`: targetPointId, server, continuation (`pointOnly`, `completedStandardGame`, `oddTiebreak`).
  `pointOnly` changes only that target's observed identity in As-Played. Persistent continuation requires
  discoveryAfterPointId equal to targetPointId: the recorded discovery endpoint is explicit, rather than inferred.
  The target must close a standard game for completedStandardGame, or be an odd positive tie-break point count
  for oddTiebreak. Earlier wrong-server points require their own reviewed pointOnly observations.
  Singles continuation records the observed side as the serving-order anchor. Doubles continuation additionally
  requires a reviewed `rotation` of exactly four distinct players, alternating teams, beginning with `server`.
  The rotation is recorded in full; the engine never guesses partner order from a single identity.
- `receiverOverride`: targetPointId, receivingSide (`A`/`B`), deuceReceiver. As-Played uses that team's deuce/ad mapping
  from the target through the end of that game, including a tie-break as one game; the next receiving game resumes
  the configured set order. The player must belong to the named team. Singles receiver overrides are refused.

An override targets a prior logged point event, not its numeric timeline index. Unknown/missing/non-point/forward
references and invalid team/rotation shapes have stable structural codes. Every player reference is validated even
on a voided override, matching reference decision 21. Latest active same-target override wins in effective log order.
Undo, redo and same-type supersede preserve originals. A voided or superseded target makes its override inert;
the override never silently attaches to the replacement. Re-entering it for the replacement is an explicit action.

## Fold behavior and conflicts

Rules always derives serving/receiving order strictly. It retains serverMismatch for disagreeing observed facts,
and adds receiverMismatch for an active disagreeing receiver override. As-Played adopts explicit active reviewed
identities and rotation anchors. Both views keep the same point winners, ends, scoring format and point count.
Point calls, service attribution and pressure flags use that view's effective server. Game server records continue
using the game's first point server; mixed-server games retain point-level attribution.

A persistent standard-game anchor changes the next game's due server and later order. A tie-break anchor retains
the ordinary 1–2–2 block lengths and current point-block phase; the provided server is the anchor of the block
containing the target. Post-tie-break serving follows the opposite side to the effective tie-break first-server
anchor. New doubles sets use explicit new-set team orders if present, otherwise carry each team's reviewed order.
Receiver overrides expire at a game boundary; a later explicit override may replace one before that boundary.

Corrections may move the discovery target off a valid boundary. This must not make an originally foldable log
unfoldable (reference decision 13): emit `overrideContextChanged`, keep the point observation, ignore the persistent
anchor, and refold all later states. A target after an unknown outcome similarly cannot establish an inferred
boundary. Malformed event data is structurally rejected; derived context changes are conflicts, not guesses.

## Independent fixture gate

Before extending native scoring, add hand-derived paired Rules/As-Played expectations for:

1. Singles wrong server for a completed first game: Rules next Alex; As-Played next Jon. Score 1–0 unchanged.
2. Mid-game pointOnly observation: observed point identity differs, later due server remains Rules order.
3. Doubles same-team partner and opposite-team completed-game continuations with two explicit rotations.
4. Tie-break odd endpoint retains anchor; even endpoint cannot persist it and uses pointOnly correction instead.
5. Receiver mapping changes during a standard game, expires before the next receiving game; same for a tie-break.
6. Override void/redo/supersede, target void/supersede inertness, multiple overrides, correction-created invalid boundary.
7. Unknown player, missing/non-point/forward target, wrong receiving team, repeated/nonalternating/incomplete rotation,
   persistent singles rotation, receiver override in singles, and malformed continuation metadata refusals.
8. New-set carry and explicit new-set order take precedence; Rules fixture outputs remain unchanged.

The pairs include hand-computed servers, receivers, next state, conflict type, score counts and point count; generated
full output is accepted only if these independent assertions pass. T04 compares the complete fold; T05 later compares
stats over it. Existing scoring/stats/sample fixtures stay intact and their counts remain part of the gate.
