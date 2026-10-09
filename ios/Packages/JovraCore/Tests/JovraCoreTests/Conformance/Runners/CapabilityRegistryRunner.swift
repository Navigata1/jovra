// fixture-kind: jovra.capabilityRegistry
import Foundation
@testable import JovraCore
struct CapabilityRegistryRunner: FixtureRunner {
    let kind = "jovra.capabilityRegistry"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(CapabilityRegistry.self, data: data, path: path) }
}
