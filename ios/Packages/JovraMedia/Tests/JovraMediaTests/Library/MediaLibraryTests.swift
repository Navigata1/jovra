import Foundation
import Testing
import JovraCore
import JovraMedia

@Test func mediaCustodyConfinesOriginalsAndKeepsCachesOutOfBackup() async throws {
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repo.deleteLastPathComponent() }
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repo.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await store.create(document)
    let library = MediaLibrary(store: store)
    let folder = try await library.recordingFolder(sessionID: document.id)
    let file = try await library.reserveOriginalURL(sessionID: document.id, relativePath: "originals/video.mp4")
    #expect(!FileManager.default.fileExists(atPath: file.path))
    try Data([1, 2, 3]).write(to: file)
    let cache = folder.appendingPathComponent("cache", isDirectory: true)
    try Data([4, 5]).write(to: cache.appendingPathComponent("preview"))
    #expect(try await library.fileURL(sessionID: document.id, relativePath: "originals/video.mp4") == file)
    let counts = try await library.byteCounts(sessionID: document.id)
    #expect(counts.originals == 3 && counts.cache == 2 && counts.exports == 0)
    #expect(try folder.appendingPathComponent("originals").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    try await library.includeOriginalsInDeviceBackup(true, sessionID: document.id)
    #expect(try folder.appendingPathComponent("originals").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
    #expect(try cache.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    #expect(try await store.load(document.id).storage.includeInDeviceBackup == true)
    for path in ["../outside", "/tmp/outside", "originals/../outside", "originals//bad", "cache/video.mp4"] {
        await #expect(throws: MediaLibraryError.self) { try await library.reserveOriginalURL(sessionID: document.id, relativePath: path) }
    }
    let outside = root.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("originals/link"), withDestinationURL: outside)
    await #expect(throws: MediaLibraryError.self) {
        try await library.reserveOriginalURL(sessionID: document.id, relativePath: "originals/link/leak.mp4")
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
}
