# ADR0030 shared order-contract amendment evidence

Scope is the missing shared contract/reference boundary required by T04, not completion of the native scorer or
any Studio/Android/watch/officiating capability. Base is merged T03 main1b4b481. Original1.0/1.1 fixture and
contract files are unchanged, including all74 prior scoring fixtures and the Jon-vs-Alex sample.

- 01: eight independent public fold pairs fail on unsupported events before any reference edit.
- 02/04: those pairs pass after the reviewed observation/rotation/receiver implementation; public checks expand
  to13 cases with schema version guards, closed object controls, inactive targets and structural refusals.
- 13/14: explicit public fold mode override fails before its API is added, then all14 focused tests pass.
- 15: deterministic generator now writes22 paired Rules/As-Played scoring fixtures, seven structural refusals,
  and one real typed1.2 session record. Every paired fixture has hand-derived assertions, including unchanged
  score/point count and changed service attribution; full fold/stat outputs are generated only after they agree.
- 16: all103 scoring fixtures,147 documents and589 hand assertions pass the independent schema/reference gate.
- 17/18: existing Studio and Room contract validators pass; their capability/implementation scope is unchanged.
- 07/11:31 Swift tests pass, including round-trip of the new concrete session fields/event and37 outputs validated
  against independent Python schemas/canonical values. No generic JSON passthrough was added.
- 19:96 Python tooling tests pass (82 existing plus14 new public controls).

Schema1.2 adds resolutionMode and two closed reviewed-event objects, with1.0/1.1 field/event refusals; current
Swift session version is exposed as SchemaVersion.current. Other document kinds keep their own versions.
Correction-created invalid derived contexts are conflicts, not structural errors; reviewed observations stay
intact and rotation is not guessed. Persistent doubles order always contains the reviewed four-player rotation.

The native scoring/stat runners remain pending until T04/T05; this amendment does not suppress their pending
status or claim a native complete fold. Fresh required Linux/spec CI and independent exact-head review remain
necessary before merge. No push, PR or merge is included in this local review candidate.

Reference-integrity follow-up: ordinary session records also reject dangling override target, discovery endpoint,
server, receiver and rotation player references. 22 records the failing public integrity test; 23 passes all15
focused controls after this change; 24 repeats the full schema/reference gate and25 reports97 Python tests.
This adds ordinary record cross-reference checks; it does not broaden the codec into runtime schema validation.
