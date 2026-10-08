import Foundation

/// The research gates in `spec/contracts/capability-registry.v1.json`. A benchmark record that names a
/// capability is judged against that capability's gate and nothing else (ADR-0004), so the harness reads the
/// gate from the registry rather than trusting a floor the caller chose.
public enum CapabilityRegistryGates {
    public static let path = "spec/contracts/capability-registry.v1.json"

    struct Registry: Decodable {
        struct Capability: Decodable {
            struct Gate: Decodable { let metrics: [Floor.Metric] }
            let id: String
            let gate: Gate?
        }
        let capabilities: [Capability]
    }

    /// Every capability id with its gate metrics (nil for a capability without a gate).
    public static func load(from catalog: MediaFixtureCatalog) throws -> [String: [Floor.Metric]?] {
        let data = try Data(contentsOf: catalog.root.appendingPathComponent(path))
        let registry = try JSONDecoder().decode(Registry.self, from: data)
        return Dictionary(registry.capabilities.map { ($0.id, $0.gate?.metrics) }, uniquingKeysWith: { first, _ in first })
    }
}

extension Floor {
    /// The floor a record naming `capabilityId` must use: that capability's registry gate.
    public static func capabilityGate(_ capabilityId: String, catalog: MediaFixtureCatalog) throws -> Floor {
        let gates = try CapabilityRegistryGates.load(from: catalog)
        guard let entry = gates[capabilityId] else { throw HarnessError.unknownCapability(capabilityId) }
        guard let metrics = entry, !metrics.isEmpty else { throw HarnessError.capabilityHasNoGate(capabilityId) }
        return Floor(source: "\(CapabilityRegistryGates.path) gate of \(capabilityId)", metrics: metrics)
    }
}
