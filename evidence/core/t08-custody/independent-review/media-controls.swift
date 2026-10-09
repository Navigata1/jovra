@Test func independentBackupOptInClearsEveryExistingOriginalExclusionFlag() async throws {
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repo.deleteLastPathComponent() }
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repo.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root); try await store.create(document)
    let library = MediaLibrary(store: store)
    let folder = try await library.recordingFolder(sessionID: document.id)
    var nested = folder.appendingPathComponent("originals/nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    var file = nested.appendingPathComponent("previously-excluded.mp4")
    try Data([1,2,3]).write(to: file)
    var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
    try nested.setResourceValues(excluded); try file.setResourceValues(excluded)
    try await library.includeOriginalsInDeviceBackup(true, sessionID: document.id)
    #expect(try nested.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
    #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
    #expect(try folder.appendingPathComponent("session.json").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true)
}
