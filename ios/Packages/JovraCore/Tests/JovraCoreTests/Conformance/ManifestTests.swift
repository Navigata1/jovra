import Foundation
import Testing
@testable import JovraCore

@Test func fixturesAreDispatchedByKindAndUnknownKindsFail() throws {
    let root = try FixtureManifest.repository()
    let kinds = generatedFixtureRunners.map(\.kind)
    let grouped = try FixtureManifest.discover(root: root, runnerKinds: kinds)
    #expect(grouped["jovra.fixture.pct"]?.count == 1) // Its folder is stats, not pct.
    #expect(FixtureManifest.pending == ["jovra.fixture.stats", "jovra.fixture.sample"])
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary.appendingPathComponent("spec/fixtures"), withIntermediateDirectories: true)
    try Data(#"{"kind":"jovra.fixture.unclaimed"}"#.utf8).write(to: temporary.appendingPathComponent("spec/fixtures/new.json"))
    #expect(throws: FixtureManifestError.unconsumedKind("jovra.fixture.unclaimed")) {
        try FixtureManifest.discover(root: temporary, runnerKinds: kinds)
    }
    #expect(throws: FixtureManifestError.duplicateRunner(kinds[0])) {
        try FixtureManifest.discover(root: root, runnerKinds: kinds + [kinds[0]])
    }
}
