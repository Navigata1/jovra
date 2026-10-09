@Test func independentCaptureFaultKeepsRecordingMarksFacetsAndEditedNoteTogether() async throws {
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repo.deleteLastPathComponent() }
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repo.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let edited = SessionMark(id: "existing", tMs: 500, kind: .point, note: "User edited", provenance: .init(status: .manual, source: "user"))
    document.marks = [edited]; document.sample = nil
    let store = try SessionStore(root: folder); try await store.create(document)
    let metadata = folder.appendingPathComponent("sessions/\(document.id)/session.json")
    let before = try Data(contentsOf: metadata)
    var recording = document.recording; recording.mode = .simulatorFixture
    var stale = edited; stale.note = "Stale journal note"
    let incoming = SessionMark(id: "incoming", tMs: 1000, kind: .point, provenance: .init(status: .manual, source: "captureMark", sample: true))
    let failing = try SessionStore(root: folder, writeFault: { _ in throw CocoaError(.fileWriteOutOfSpace) })
    await #expect(throws: (any Error).self) { try await failing.saveCapture(recording, marks: [stale,incoming], for: document.id) }
    #expect(try Data(contentsOf: metadata) == before)
    try await store.saveCapture(recording, marks: [stale,incoming], for: document.id)
    let actual = try await store.load(document.id)
    #expect(actual.marks == [edited,incoming])
    #expect(actual.recording == recording)
    #expect(actual.analysis == document.analysis && actual.review == document.review && actual.archive == document.archive)
    #expect(actual.sample?.synthetic == true)
}
