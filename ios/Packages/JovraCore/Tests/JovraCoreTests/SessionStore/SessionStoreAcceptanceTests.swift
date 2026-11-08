import Foundation
import Testing
import JovraCore

/// T08 acceptance items not already pinned by SessionStoreTests: a batch interrupted after its rename is all
/// there, a deleted index regenerates byte-identical, and a 1.0.0 document written by an older app migrates
/// in place to the current version without losing a value. Expected versions are the schema's literals.
private func repository() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { url.deleteLastPathComponent() }
    return url
}

private let legacyFixture = "spec/fixtures/sample/jon-vs-alex.session.json"

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func reviewedPoint(_ index: Int) -> SessionLogEvent {
    .point(.init(id: "batch-\(index)", seq: index + 1, reviewed: .init(winner: index.isMultiple(of: 2) ? .a : .b,
        endType: .winner, provenance: .manual, source: "user"), reviewState: .reviewed))
}

private enum ProcessDeath: Error { case afterRename }

@Test func batchInterruptedAfterItsRenameKeepsAllFiveEvents() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repository().appendingPathComponent(legacyFixture)))
    document.match?.log = []
    try await SessionStore(root: root).create(document)
    let dying = try SessionStore(root: root, writeFault: { checkpoint in
        if case .documentRenamed = checkpoint { throw ProcessDeath.afterRename }
    })
    await #expect(throws: ProcessDeath.afterRename) { try await dying.append((0..<5).map(reviewedPoint), to: document.id) }

    let relaunched = try await SessionStore(root: root).load(document.id)
    #expect(relaunched.match?.log.map(\.id) == ["batch-0", "batch-1", "batch-2", "batch-3", "batch-4"])
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("sessions/\(document.id)").path)
    #expect(leftovers.filter { $0.hasSuffix(".tmp") }.isEmpty)
}

@Test func deletedIndexIsRebuiltByteForByteFromTheSessionFolders() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let base = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repository().appendingPathComponent(legacyFixture)))
    for (id, notes) in [("court-3-evening", "Court 3, hard. Second serve held up."), ("clay-morning", "Clay court. Work on return.")] {
        var document = base
        document.id = id; document.sample = nil; document.notes = notes
        try await store.create(document)
    }
    let index = root.appendingPathComponent("index.json")
    let before = try await store.list()
    let indexBefore = try Data(contentsOf: index)

    try FileManager.default.removeItem(at: index)
    let relaunched = try SessionStore(root: root)
    let after = try await relaunched.list()

    #expect(after == before)
    #expect(try Data(contentsOf: index) == indexBefore)
    #expect(try await relaunched.list(.init(search: "court 3")).map(\.id) == ["court-3-evening"])
}

@Test func version100DocumentOnDiskMigratesToTheCurrentVersionLosslessly() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let fixtureBytes = try Data(contentsOf: repository().appendingPathComponent(legacyFixture))
    let legacy = try ContractCodec.decode(SessionDocument.self, from: fixtureBytes)
    #expect(legacy.schemaVersion == (try SchemaVersion("1.0.0")))
    // An older app wrote this folder; the current store has never seen it.
    let folder = root.appendingPathComponent("sessions/\(legacy.id)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try fixtureBytes.write(to: folder.appendingPathComponent("session.json"))

    let store = try SessionStore(root: root)
    #expect(try await store.list().map(\.id) == [legacy.id])

    let migratedBytes = try Data(contentsOf: folder.appendingPathComponent("session.json"))
    let migrated = try ContractCodec.decode(SessionDocument.self, from: migratedBytes)
    #expect(migrated.schemaVersion == (try SchemaVersion("1.2.0")))
    #expect(migratedBytes == (try CanonicalJSON.encode(migrated)))
    var expected = legacy
    expected.schemaVersion = migrated.schemaVersion
    #expect(migrated == expected)
    #expect(try await store.quarantinedSessions().isEmpty)
    if let directory = ProcessInfo.processInfo.environment["JOVRA_MIGRATION_EVIDENCE_DIR"] {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try migratedBytes.write(to: output.appendingPathComponent("migrated-from-1.0.0.session.json"))
    }
}
