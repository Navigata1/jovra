// fixture-kind: jovra.export
import Foundation
@testable import JovraCore
struct ExportRunner: FixtureRunner {
    let kind = "jovra.export"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(ExportManifest.self, data: data, path: path) }
}
