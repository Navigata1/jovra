# Shared Swift contracts (T03)

`DocumentModels.swift` contains named Codable structs/enums generated from the published schemas by
`python3 scripts/spec/generate_swift_models.py`. These are compiled model properties, not runtime schema
interpretation or generic document dictionaries. After T03 merges, changes here require a contract-fix PR.
The sole scoped opaque JSON field is `BenchmarkOutputValue`, because benchmark `clips[].outputs` explicitly
has no item schema. Required nullable fields use `ContractNullable`; absence is distinct from explicit null.

The public roots are `SessionDocument`, `EquipmentDocument`, `PracticePlanDocument`, `ArchiveManifest`,
`ExportManifest`, `CapabilityRegistry`, `SampleMediaManifest`, `GroundTruthRecord`, `BenchmarkRecord`,
`BenchmarkBindings`, and `CSVContract`. Session properties are mutable and every model has a public initializer;
optional properties default to nil. `SessionLogEvent` is a discriminated enum with `id`, `seq`, and `typeString`.
`SessionRecording`, `SessionSegment`, `SessionGap`, `SessionCaptureEvent`, and `SessionRecoveryReport` provide
capture/store handoffs. `RecordFileReference` and `RecordedFrameRate` carry stored media facts.

`ContractCodec.decode(_:from:)` refuses malformed/duplicate JSON, unsupported schema major versions,
numeric inputs Foundation Decimal cannot represent exactly, invalid rational media times, and any record
that would lose fields when decoded into the requested type. `CanonicalJSON.encode(_:)` produces ADR-0029
sorted, compact UTF-8 without a newline. This codec is **not a complete JSON Schema validator**: application
writers still need their domain invariants; conformance outputs are independently schema-validated by Python.
No timestamps are reformatted. `MediaTime` stores exact Int64 value/Int32 timescale, not binary seconds.

`Percent.pct(n:d:)`, `ratio`, `pool`, and `delta` implement one checked integer half-up rule (including Int.max
without multiplication overflow); undefined rates display an em dash. `Units.convert(_:from:to:places:)`
accepts/returns exact decimal strings, allows 0–20 output decimal places, and rounds half-up once. `display`
returns entered text unchanged for a matching unit, including leading/trailing zeroes. Converted display follows
the unit's documented step. Gauge ranges are hints with their source names, never a single inferred diameter.

The test-only SwiftPM build plugin discovers `Conformance/Runners/*Runner.swift` with one `fixture-kind`
marker and matching struct per file. It emits registrations deterministically and refuses duplicate ownership;
there is no handwritten central dispatch list. The runtime manifest discovers JSON by its `kind`, independently
of directory names. Pending kinds are exactly scoring/stats/sample until T04/T05 add their own runner files.

For independent byte and schema checks, set `JOVRA_REENCODED_DIR` to an isolated output folder when running
`swift test`, then run `python3 scripts/spec/validate.py --encoded-dir <folder>`. Output paths mirror source
fixture paths; the command requires matching source fixtures and refuses an empty folder. It checks every emitted
record against its schema and against the separate exact Python canonicalizer, preserving the original fixtures.
