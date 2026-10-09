// fixture-kind: jovra.benchmarkRecord
import Foundation
@testable import JovraCore
struct BenchmarkRunner: FixtureRunner {
    let kind = "jovra.benchmarkRecord"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(BenchmarkRecord.self, data: data, path: path) }
}
