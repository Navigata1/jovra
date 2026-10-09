// fixture-kind: jovra.practicePlan
import Foundation
@testable import JovraCore
struct PracticePlanRunner: FixtureRunner {
    let kind = "jovra.practicePlan"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(PracticePlanDocument.self, data: data, path: path) }
}
