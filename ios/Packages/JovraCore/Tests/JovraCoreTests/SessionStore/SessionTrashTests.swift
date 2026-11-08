import Foundation
import Testing
import JovraCore

/// T08 Trash, restore, purge and retention (user stories 129, 131). Expected values are literals
/// from the spec: the original facet becomes `trashed`, purge needs a store-issued token, and
/// nothing is auto-emptied unless the retention flag is on.
private func fixture(id: String, original: SessionOriginalState? = .init(state: .saved, updatedAt: "2026-10-01T10:00:00Z")) throws -> SessionDocument {
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repo.deleteLastPathComponent() }
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repo.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    document.id = id
    document.sample = nil
    document.schemaVersion = .current
    document.original = original
    return document
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func day(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

@Test func trashHidesSessionFromLibraryAndRestoreRoundTripsTheDocument() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let kept = try fixture(id: "kept")
    let binned = try fixture(id: "binned", original: .init(state: .savedWithGaps, reason: "Interrupted twice", updatedAt: "2026-10-02T09:00:00Z"))
    try await store.create(kept); try await store.create(binned)
    let original = Data("original-bytes".utf8)
    let media = root.appendingPathComponent("sessions/binned/originals", isDirectory: true)
    try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
    try original.write(to: media.appendingPathComponent("segment-0.mov"))

    try await store.trash("binned", at: day("2026-10-05T12:00:00Z"))

    let trashed = try await store.load("binned")
    #expect(trashed.original == SessionOriginalState(state: .trashed, updatedAt: "2026-10-05T12:00:00Z"))
    #expect(trashed.match == binned.match && trashed.review == binned.review && trashed.archive == binned.archive)
    #expect(try await store.list().map(\.id) == ["kept"])
    #expect(try await store.list(.init(original: .trashed)).map(\.id) == ["binned"])
    #expect(try await store.list(.init(includeTrashed: true)).map(\.id).sorted() == ["binned", "kept"])
    #expect(try Data(contentsOf: media.appendingPathComponent("segment-0.mov")) == original)

    try await store.restoreFromTrash("binned")

    #expect(try await store.load("binned") == binned)
    #expect(try await store.list().map(\.id).sorted() == ["binned", "kept"])
    await #expect(throws: SessionStoreError.notInTrash) { try await store.restoreFromTrash("binned") }
}

@Test func restoreSurvivesRelaunchBetweenTrashAndUndo() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let document = try fixture(id: "relaunch", original: .init(state: .partial, reason: "Recording contains unconfirmed media"))
    try await SessionStore(root: root).create(document)
    try await SessionStore(root: root).trash("relaunch", at: day("2026-10-05T12:00:00Z"))
    let relaunched = try SessionStore(root: root)
    try await relaunched.restoreFromTrash("relaunch")
    #expect(try await relaunched.load("relaunch") == document)
}

@Test func interruptedTrashLeavesSessionInTheLibrary() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let document = try fixture(id: "interrupted")
    try await SessionStore(root: root).create(document)
    let crashing = try SessionStore(root: root, writeFault: { checkpoint in
        if case .temporaryFileFlushed(let url) = checkpoint, url.lastPathComponent.hasPrefix(".session-") { throw CocoaError(.fileWriteUnknown) }
    })
    await #expect(throws: CocoaError.self) { try await crashing.trash("interrupted", at: day("2026-10-05T12:00:00Z")) }
    let store = try SessionStore(root: root)
    #expect(try await store.load("interrupted") == document)
    #expect(try await store.list().map(\.id) == ["interrupted"])
}

@Test func purgeIsRefusedWithoutAStoreIssuedConfirmationToken() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await store.create(try fixture(id: "doomed")); try await store.create(try fixture(id: "other"))
    let folder = root.appendingPathComponent("sessions/doomed", isDirectory: true)

    await #expect(throws: SessionStoreError.notInTrash) { _ = try await store.purgeConfirmation(for: "doomed") }
    try await store.trash("doomed", at: day("2026-10-05T12:00:00Z"))
    try await store.trash("other", at: day("2026-10-05T12:00:00Z"))

    await #expect(throws: SessionStoreError.confirmationRequired) { try await store.purge("doomed", confirmation: nil) }
    let otherToken = try await store.purgeConfirmation(for: "other")
    await #expect(throws: SessionStoreError.confirmationRequired) { try await store.purge("doomed", confirmation: otherToken) }
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("session.json").path))

    let token = try await store.purgeConfirmation(for: "doomed")
    try await store.purge("doomed", confirmation: token)

    #expect(!FileManager.default.fileExists(atPath: folder.path))
    await #expect(throws: SessionStoreError.notFound) { _ = try await store.load("doomed") }
    #expect(try await store.list(.init(includeTrashed: true)).map(\.id) == ["other"])
    #expect(try await store.quarantinedSessions().isEmpty)
    await #expect(throws: SessionStoreError.self) { try await store.purge("doomed", confirmation: token) }
}

@Test func restoringASessionInvalidatesItsPurgeToken() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await store.create(try fixture(id: "undone"))
    try await store.trash("undone", at: day("2026-10-05T12:00:00Z"))
    let token = try await store.purgeConfirmation(for: "undone")
    try await store.restoreFromTrash("undone")
    try await store.trash("undone", at: day("2026-10-06T12:00:00Z"))
    await #expect(throws: SessionStoreError.confirmationRequired) { try await store.purge("undone", confirmation: token) }
    #expect(try await store.load("undone").original?.state == .trashed)
}

@Test func trashNeverAutoEmptiesOriginalsUnlessTheRetentionFlagIsSet() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    for id in ["old-trash", "recent-trash", "old-live"] { try await store.create(try fixture(id: id)) }
    let original = root.appendingPathComponent("sessions/old-trash/originals/segment-0.mov")
    try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("irreplaceable".utf8).write(to: original)
    try await store.trash("old-trash", at: day("2025-01-01T00:00:00Z"))
    try await store.trash("recent-trash", at: day("2026-10-01T00:00:00Z"))
    let now = day("2026-10-11T00:00:00Z")

    #expect(TrashRetention.default.autoEmpty == false)
    #expect(try await store.emptyTrash(retention: .default, now: now).isEmpty)
    #expect(try Data(contentsOf: original) == Data("irreplaceable".utf8))
    #expect(try await store.list(.init(includeTrashed: true)).count == 3)

    let purged = try await store.emptyTrash(retention: .init(autoEmpty: true, afterDays: 30), now: now)

    #expect(purged == ["old-trash"])
    #expect(!FileManager.default.fileExists(atPath: original.path))
    #expect(try await store.list(.init(includeTrashed: true)).map(\.id).sorted() == ["old-live", "recent-trash"])
}

@Test func crashBetweenTempWriteAndRenameKeepsPreviousDocumentAndIgnoresTheTempFile() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let document = try fixture(id: "steady")
    let store = try SessionStore(root: root)
    try await store.create(document)
    let before = try await store.list()
    let crashing = try SessionStore(root: root, writeFault: { checkpoint in
        if case .temporaryFileFlushed = checkpoint { throw CocoaError(.fileWriteUnknown) }
    })
    await #expect(throws: CocoaError.self) { try await crashing.update("steady", facet: .review(.init(state: .complete))) }
    let folder = root.appendingPathComponent("sessions/steady")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".tmp") }
    #expect(leftovers.count == 1)
    let relaunched = try SessionStore(root: root)
    #expect(try await relaunched.load("steady") == document)
    #expect(try await relaunched.list() == before)
    #expect(try await relaunched.quarantinedSessions().isEmpty)
}
