// fixture-kind: jovra.benchmarkBindings
import Foundation
@testable import JovraCore
struct BenchmarkBindingsRunner: FixtureRunner {
    let kind = "jovra.benchmarkBindings"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(BenchmarkBindings.self, data: data, path: path) }
}
