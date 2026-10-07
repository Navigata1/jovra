# Starter edit-plan contract

`jovra.edit-plan/1` is a handoff starter, not the existing repository schema. Reconcile the name/version with `spec/` before implementation. The sample is a fictional 8-second, two-shot, 30/1 FPS court-sound draft. It renders nothing.

| Field | Meaning |
|---|---|
| `projectId`, `sample` | Project binding and visible fictional-data marker |
| `sourceManifestRevision`, `syncRevision`, `eventRevision` | Revisions whose changes invalidate a plan |
| `profileId`, `profileRevision` | Versioned editorial treatment |
| `output` | Rational FPS, even dimensions, total frames, fixed container/codecs |
| `sources` | Planning metadata snapshot: IDs, SHA-256, proxy FPS/dimensions/frame count and audio availability |
| `segments` | Ordered contiguous output frame windows with exact source frame windows, 1× speed and supported transition |
| `audio` | One continuous `primary-bed` window or explicit `silence` |
| `overlayRefs` | Stored-event references and provenance rather than copied numbers |

The helper checks this small subset strictly: unknown fields fail, all sources match output FPS/dimensions, segments cover the output once in order, source windows fit the declared proxy, original speed is preserved, audio coverage is sufficient, metric/score references use the current event revision, and only known profile/provenance/transition values are allowed. IDs and hashes are data, not paths or approval. Declared duration/hash/rights can lie; this helper cannot establish their truth.

In production, load trusted source manifests independently and compare actual bytes, decoded clocks, permissions and current revisions. A source snapshot supplied by an LLM/client must never be the source of authority. Convert source proxy windows through the SyncMap before cross-angle use. Validate coverage and alignment uncertainty around every cut.

Extend deliberately for `replay`, `freeze`, `title-card`, effect primitives, reframing, layered audio and captions: define duration/coverage semantics, bounds, labelled replay copy, provenance and visual/audio verification first. Do not smuggle those operations into a prose string. A source map needs a rational timebase and original timestamp mappings; source-frame indices alone cannot reconstruct variable-frame originals.

Authorizations and charges live in a separate trusted job/reservation record. An edit plan has no `approved`, `paid`, `renderAllowed`, endpoint, command or secret field. Validation is neither spending permission nor final approval.
