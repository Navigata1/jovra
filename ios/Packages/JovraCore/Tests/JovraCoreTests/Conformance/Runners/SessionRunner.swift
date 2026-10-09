// fixture-kind: jovra.session
import Foundation
@testable import JovraCore
struct SessionRunner: FixtureRunner {
    let kind = "jovra.session"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(SessionDocument.self, data: data, path: path) }
}
