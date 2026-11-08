import Foundation

extension CapabilityRegistry {
    public static func load(from data: Data) throws -> CapabilityRegistry {
        let registry = try ContractCodec.decode(CapabilityRegistry.self, from: data)
        guard Set(registry.capabilities.map(\.id)).count == registry.capabilities.count else {
            throw CapabilityRegistryError.duplicateCapability
        }
        return registry
    }
    public func capability(id: String) -> CapabilityCapability? {
        capabilities.first { $0.id == id }
    }
}

public enum CapabilityRegistryError: Error, Equatable, Sendable { case duplicateCapability, missingBundledRegistry }

extension CapabilityRegistry {
    /// The registry shipped with the app: a byte-identical copy of spec/contracts/capability-registry.v1.json
    /// (checked by `BundledCapabilityRegistryTests` and CI). Badges and capability pages read it (ADR-0004).
    public static func bundledData() -> Data? {
        guard let url = Bundle.module.url(forResource: "capability-registry.v1", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func bundled() throws -> CapabilityRegistry {
        guard let data = bundledData() else { throw CapabilityRegistryError.missingBundledRegistry }
        return try load(from: data)
    }
}
