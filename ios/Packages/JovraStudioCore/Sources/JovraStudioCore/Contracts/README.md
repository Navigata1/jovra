# Studio contracts in Swift (S10, STU-01)

This folder reads and writes every `jovra.*` Studio record and the three contract data files
(`spec/studio/contracts/*.v1.json`). The shared contracts in `spec/schemas/studio` and `spec/studio` are the source of
truth; nothing here changes them.

| File | Holds |
|---|---|
| `Generated/StudioContractModels.swift` | Typed Codable models: one struct per object, Swift enums for schema choices, `ContractNullable` (JovraCore) for required nullable fields, discriminated enums for `oneOf` (for example `EditPlanSegment` by `op`), and JovraCore's `Provenance` for every provenance status. Each root conforms to `StudioContract` (its `schemaVersion` and schema location). |
| `Generated/StudioSchemaSource.swift` | The Studio schema files, byte for byte, so the decoder never reads `spec/` at runtime. |
| `StudioJSON.swift` | A strict JSON parser that keeps member order and exact number tokens (`744` and `744.0` stay different), refuses duplicate names, lone surrogates and numbers Decimal cannot hold. |
| `StudioSchemaSet.swift` | The JSON Schema subset of `scripts/spec/jsonschema_subset.py`, with ECMA-262 pattern anchors (`$` is end of input, so an id or hash ending in a newline is refused). One deliberate difference: `"type": "integer"` accepts only integer tokens, so an integral float is refused. |
| `StudioContractCodec.swift` | `StudioContractCodec.decode/encode/roundTrip`, the `StudioContractDecoder` registry entry and `StudioContracts.decoders` (this folder's registrations). |
| `StudioTime.swift` | SD7 time: exact rationals, integer microseconds and the one half-up rule (`frame = floor(t * fps + 1/2)`); `Percent.pct` in JovraCore is the same rule. |

## Reading and writing

```swift
let lock = try StudioContractCodec.decode(ProjectLock.self, from: data)   // strict
let bytes = try StudioContractCodec.encode(lock)                           // canonical (ADR-0029), schema-checked
```

Decoding checks, in order: well-formed strict JSON, the stated `schemaVersion`, the full schema (unknown properties,
types, patterns, ranges, every `if`/`then` rule), then the typed model through core T03's `ContractCodec`, which also
refuses a document the model would not reproduce. Encoding uses T03's canonical writer and checks the output against
the schema, so the codec never writes what it would refuse to read. The record rules of the Python reference
(`spec/reference/studio/*.py`, the "reference" layer of the invalid cases) are not here; each module ticket ports its
own.

## Regenerating

After any change under `spec/schemas/studio`:

```
python3 ios/Packages/JovraStudioCore/Tools/generate_contract_models.py           # rewrite Generated/
python3 ios/Packages/JovraStudioCore/Tools/generate_contract_models.py --check   # exit 1 when stale
```

`ContractsSchemaSetTests` fails when an embedded schema differs from `spec/schemas/studio` or the models were generated from
other bytes, so a schema change without a regeneration cannot pass `swift test`.

## Registering a consumer (no shared list)

The conformance tests run whatever the test target's consumers register. A module adds one file in its own test
folder, `Tests/JovraStudioCoreTests/<Module>/<Name>Consumer.swift`, declaring `struct <Name>Consumer:
StudioFixtureConsumer` with its `decoders` and `vectorCheckers`. The test-only `StudioConsumerDiscoveryPlugin` lists
every such file at build time. Two consumers registering the same kind fail the suite.

The manifest test (`ContractsFixtureManifestTests`) reads every module page's front matter. A fixture kind on no page fails; a
page that says `swift: consumed` fails unless every kind on it is registered by a consumer; `swift: pending` may stay
unconsumed. A ticket that starts consuming a module flips only that page's `swift:` line.
