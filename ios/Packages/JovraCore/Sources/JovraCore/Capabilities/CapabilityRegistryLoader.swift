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

public enum CapabilityRegistryError: Error, Equatable, Sendable { case duplicateCapability }
