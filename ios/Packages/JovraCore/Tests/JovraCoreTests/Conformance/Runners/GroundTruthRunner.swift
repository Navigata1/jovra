// fixture-kind: jovra.groundTruth
import Foundation
@testable import JovraCore
struct GroundTruthRunner: FixtureRunner {
    let kind = "jovra.groundTruth"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(GroundTruthRecord.self, data: data, path: path) }
}
