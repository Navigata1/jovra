// fixture-kind: jovra.csvContract
import Foundation
@testable import JovraCore
struct CSVContractRunner: FixtureRunner {
    let kind = "jovra.csvContract"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(CSVContract.self, data: data, path: path) }
}
