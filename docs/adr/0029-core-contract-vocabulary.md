# ADR-0029: Reconcile core coordinate, key-moment and canonical JSON vocabulary

Date: 2026-10-09. Status: accepted for the founder-authorized core implementation continuation.

## Context

T02 identified conflicting court origins, two stroke key-moment vocabularies, and T03 found that the cosmetic fixture
printer was being mistaken for the sorted canonical serialization required by the iOS specification. Native ports
need one interpretation before persisted records and score exports are built.

## Decisions

1. `common.point2` remains unchanged: court metres originate at the centre of the net; x runs across and y towards
   the far baseline. Normalized image points originate top-left. The glossary is corrected to the existing contract.
2. New stroke key-moment UI follows the glossary and story 243: Ready, Unit turn, Racket drop, Contact, Finish.
   Existing alternate names remain accepted by the completed T02 schema for compatibility. Do not automatically
   relabel stored moments: an older name can have a different meaning. Serve names remain unchanged.
3. Canonical conformance compares sorted, compact UTF-8 JSON of the parsed fixture values, without a trailing newline;
   source fixture indentation and insertion order are not canonical bytes. Unicode and `/` remain unescaped; standard
   JSON control escaping applies. Numeric formatting must preserve values, decimal strings and integer rational
   times. Expected bytes are produced independently of Swift, using the reference tooling or Python's sorted compact
   JSON serialization of the parsed expectation. The cosmetic fixture printer and the original fixture files remain
   unchanged. Swift-encoded documents still undergo schema validation.

## Consequences

No schema-version bump, coordinate migration, image/reference redraw or synthetic metric promotion is needed.
T03 consumes canonicalized expectations; later court and Stroke Lab tickets use the clarified vocabulary.
