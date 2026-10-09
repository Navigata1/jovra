# T08 atomic transaction slice

This is a partial T08 implementation; query/index, quarantine, migration, Trash and MediaLibrary custody remain separate slices. It does not close issue10.

Seams: SessionStore create/load, batch append, independent facet update and recording handoff. Transactions have no suspension point. Public crash injection checkpoints occur after temp-file synchronization and after rename. A post-rename sync refusal means a fresh load may see the new document, but the caller cannot acknowledge durability.

Independent review caught seq=0 and ignored directory-sync errors; both corrected. The zero/negative refusal test failed before correction. Interrupted batch/relaunch tests and1000concurrent append/facet interleavings pass; corrected final gate ran6XCTest plus31SwiftTesting tests. A later duplicate sequence/ID refusal check also passes. Simulator, physical-camera and hardware endurance are not tested by this package slice.

Legacy version correction: a new original facet failed the1.1 stamp expectation before the write mutation was corrected. Creates preserve an existing1.0 document; mutations stamp the current supported contract (now1.2) before persisting new fields, preserving match data. Targeted public test passes; fresh Linux CI runs the full suite on this head. The current-version stamp was reconciled after ADR0030 merged.

Positive storage events now carry a manual outcome with the contract source `user`. Missing outcomes are refused. Independent schema validation caught an initially wrong test source literal; it is corrected before merge. Full local gate with outcome blocks passes6XCTest plus31SwiftTesting tests; independent validation of the emitted1005-event document passes the session schema and exact canonical-byte comparison.
