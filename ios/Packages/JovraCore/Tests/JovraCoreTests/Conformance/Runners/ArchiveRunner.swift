// fixture-kind: jovra.archiveManifest
import Foundation
@testable import JovraCore
struct ArchiveRunner: FixtureRunner {
    let kind = "jovra.archiveManifest"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(ArchiveManifest.self, data: data, path: path) }
}
