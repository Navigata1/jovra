// fixture-kind: jovra.equipment
import Foundation
@testable import JovraCore
struct EquipmentRunner: FixtureRunner {
    let kind = "jovra.equipment"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(EquipmentDocument.self, data: data, path: path) }
}
