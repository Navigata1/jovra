import Foundation
import JovraStudioCore

/// What one Studio module's tests consume from the shared fixtures (S10). A module adds one `<Name>Consumer.swift`
/// file in its own test folder declaring `struct <Name>Consumer: StudioFixtureConsumer`; the test-only
/// StudioConsumerDiscoveryPlugin lists every such file in `generatedStudioConsumers`, so there is no shared list to
/// edit. The conformance suites run what the consumers register:
///
/// - every record under spec/studio/fixtures/records (and spec/studio/contracts) whose schemaVersion has a registered
///   decoder decodes and re-encodes byte-identically to its canonical form, and every schema-layer invalid case of
///   that schemaVersion is refused (ContractsRoundTripTests, ContractsInvalidCaseTests);
/// - every case of a vector file whose kind has a registered checker is run through it (ContractsVectorTests);
/// - the manifest test fails when a module page says `swift: consumed` for a kind no consumer registers
///   (ContractsFixtureManifestTests).
protocol StudioFixtureConsumer: Sendable {
    /// Strict decoders this module registers, one per schemaVersion.
    var decoders: [StudioContractDecoder] { get }
    /// Vector kind -> a check of one case (the case object of the vector file); it throws or records an Issue on a
    /// mismatch with the reference's stored expectation.
    var vectorCheckers: [String: @Sendable (StudioJSONValue) throws -> Void] { get }
}

extension StudioFixtureConsumer {
    var decoders: [StudioContractDecoder] { [] }
    var vectorCheckers: [String: @Sendable (StudioJSONValue) throws -> Void] { [:] }
}

/// The union of what the discovered consumers register, with every double registration found while merging.
struct StudioConsumption {
    let decoders: [String: StudioContractDecoder]
    let vectorCheckers: [String: @Sendable (StudioJSONValue) throws -> Void]
    let conflicts: [String]

    init(_ consumers: [any StudioFixtureConsumer]) {
        var decoders: [String: StudioContractDecoder] = [:]
        var checkers: [String: @Sendable (StudioJSONValue) throws -> Void] = [:]
        var owners: [String: String] = [:]
        var conflicts: [String] = []
        for consumer in consumers {
            let owner = String(describing: type(of: consumer))
            for decoder in consumer.decoders {
                if let first = owners[decoder.schemaVersion] {
                    conflicts.append("\(decoder.schemaVersion) is registered twice (\(first) and \(owner))")
                    continue
                }
                owners[decoder.schemaVersion] = owner
                decoders[decoder.schemaVersion] = decoder
            }
            for (kind, checker) in consumer.vectorCheckers {
                if let first = owners[kind] {
                    conflicts.append("\(kind) is registered twice (\(first) and \(owner))")
                    continue
                }
                owners[kind] = owner
                checkers[kind] = checker
            }
        }
        self.decoders = decoders
        self.vectorCheckers = checkers
        self.conflicts = conflicts
    }

    /// Every kind a consumer registers: schemaVersions with a decoder and vector kinds with a checker.
    var kinds: Set<String> { Set(decoders.keys).union(vectorCheckers.keys) }

    static let discovered = StudioConsumption(generatedStudioConsumers)
}
