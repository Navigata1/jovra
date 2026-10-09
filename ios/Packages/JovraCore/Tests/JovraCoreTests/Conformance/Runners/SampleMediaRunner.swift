// fixture-kind: jovra.sampleMediaManifest
import Foundation
@testable import JovraCore
struct SampleMediaRunner: FixtureRunner {
    let kind = "jovra.sampleMediaManifest"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(SampleMediaManifest.self, data: data, path: path) }
}
