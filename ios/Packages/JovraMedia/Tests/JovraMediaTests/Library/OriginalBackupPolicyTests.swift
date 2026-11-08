import Foundation
import Testing
import JovraCore
import JovraMedia

/// T08 / ADR-0009: originals are excluded from device backup by default, session documents are not, and the
/// "include originals" call flips every original in both directions. Expected flags are the ADR's literals.
private func excluded(_ url: URL) throws -> Bool {
    // A fresh URL: Foundation caches resource values per URL instance, which would hide a later flip.
    try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
}

private func sessionStore() async throws -> (SessionStore, String, URL) {
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repo.deleteLastPathComponent() }
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repo.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    document.id = "custody"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = try SessionStore(root: root)
    try await store.create(document)
    return (store, document.id, root)
}

@Test func originalsWrittenThroughTheLibraryAreExcludedFromBackupButTheSessionDocumentIsNot() async throws {
    let (store, id, root) = try await sessionStore(); defer { try? FileManager.default.removeItem(at: root) }
    let library = MediaLibrary(store: store)
    #expect(try await store.load(id).storage.includeInDeviceBackup == false)

    let first = try await library.reserveOriginalURL(sessionID: id, relativePath: "originals/segment-0.mp4")
    let nested = try await library.reserveOriginalURL(sessionID: id, relativePath: "originals/camera-b/segment-0.mp4")
    try Data([1, 2, 3]).write(to: first)
    try Data([4, 5]).write(to: nested)
    let adopted = try await library.adoptOriginal(sessionID: id, relativePath: "originals/segment-0.mp4")
    _ = try await library.adoptOriginal(sessionID: id, relativePath: "originals/camera-b/segment-0.mp4")

    let folder = root.appendingPathComponent("sessions/custody", isDirectory: true)
    #expect(adopted == first)
    #expect(try excluded(first) == true)
    #expect(try excluded(nested) == true)
    #expect(try excluded(nested.deletingLastPathComponent()) == true)
    #expect(try excluded(folder.appendingPathComponent("originals")) == true)
    #expect(try excluded(folder.appendingPathComponent("session.json")) == false)
    #expect(try excluded(folder) == false)
    #expect(try Data(contentsOf: first) == Data([1, 2, 3]))
}

@Test func includingOriginalsInDeviceBackupFlipsEveryOriginalAndBack() async throws {
    let (store, id, root) = try await sessionStore(); defer { try? FileManager.default.removeItem(at: root) }
    let library = MediaLibrary(store: store)
    let paths = ["originals/segment-0.mp4", "originals/segment-1.mp4", "originals/camera-b/segment-0.mp4"]
    var files: [URL] = []
    for path in paths {
        let url = try await library.reserveOriginalURL(sessionID: id, relativePath: path)
        try Data(path.utf8).write(to: url)
        files.append(try await library.adoptOriginal(sessionID: id, relativePath: path))
    }
    let folder = root.appendingPathComponent("sessions/custody", isDirectory: true)
    let cache = folder.appendingPathComponent("cache/preview.jpg")
    try Data([9]).write(to: cache)

    try await library.includeOriginalsInDeviceBackup(true, sessionID: id)

    for file in files { #expect(try excluded(file) == false) }
    #expect(try excluded(folder.appendingPathComponent("originals/camera-b")) == false)
    #expect(try excluded(folder.appendingPathComponent("cache")) == true)
    #expect(try excluded(folder.appendingPathComponent("session.json")) == false)
    #expect(try await store.load(id).storage.includeInDeviceBackup == true)

    // A file adopted while the policy is on follows the policy, not the default.
    let late = try await library.reserveOriginalURL(sessionID: id, relativePath: "originals/segment-2.mp4")
    try Data([7]).write(to: late)
    #expect(try excluded(try await library.adoptOriginal(sessionID: id, relativePath: "originals/segment-2.mp4")) == false)

    try await library.includeOriginalsInDeviceBackup(false, sessionID: id)

    for file in files + [late] { #expect(try excluded(file) == true) }
    #expect(try excluded(folder.appendingPathComponent("session.json")) == false)
    #expect(try await store.load(id).storage.includeInDeviceBackup == false)
}

@Test func adoptingAnOriginalRefusesPathsOutsideOriginalsAndMissingOrLinkedFiles() async throws {
    let (store, id, root) = try await sessionStore(); defer { try? FileManager.default.removeItem(at: root) }
    let library = MediaLibrary(store: store)
    let folder = try await library.recordingFolder(sessionID: id)
    try Data([1]).write(to: folder.appendingPathComponent("cache/preview.jpg"))
    let outside = root.appendingPathComponent("outside.mp4")
    try Data([2]).write(to: outside)
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("originals/link.mp4"), withDestinationURL: outside)

    for path in ["cache/preview.jpg", "originals/../session.json", "originals/missing.mp4", "originals/link.mp4", "originals"] {
        await #expect(throws: MediaLibraryError.self) { _ = try await library.adoptOriginal(sessionID: id, relativePath: path) }
    }
    #expect(try excluded(outside) == false)
}
