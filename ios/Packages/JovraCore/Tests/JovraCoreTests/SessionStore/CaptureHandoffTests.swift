import Foundation
import Testing
import JovraCore

@Test func captureHandoffAtomicallyKeepsExistingMarksAndStateFacetsAcrossRelaunch() async throws {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { root.deleteLastPathComponent() }
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(root: directory)
    let existing = SessionMark(id: "first", tMs: 500, kind: .point, note: "Keep edited note", provenance: .init(status: .manual, source: "captureMark", sample: true))
    let incoming = SessionMark(id: "second", tMs: 1000, kind: .point, provenance: .init(status: .manual, source: "captureMark", sample: true))
    document.marks = [existing]; document.sample = nil
    try await store.create(document)
    let segment = SessionSegment(id: "video", index: 0, file: .init(path: "originals/video.mp4"), startMs: 0, durationMs: 2000, frameRate: .init(num: 30, den: 1), width: 1280, height: 720, codec: .h264, hasAudio: false, finalized: true)
    let record = SessionRecording(mode: .simulatorFixture, durationMs: 2000, segments: [segment], gaps: [], microphone: .denied, mediaAvailable: true)
    try await store.saveCapture(record, marks: [existing, incoming], for: document.id)
    try await store.saveCapture(record, marks: [incoming], for: document.id)
    let reopened = try SessionStore(root: directory)
    let actual = try await reopened.load(document.id)
    #expect(actual.marks == [existing, incoming])
    #expect(actual.recording == record)
    #expect(actual.original?.state == .saved)
    #expect(actual.sample?.synthetic == true)
    #expect(actual.analysis == document.analysis)
    #expect(actual.review == document.review)
    #expect(actual.archive == document.archive)
    #expect(actual.match == document.match)
    #expect(actual.schemaVersion == .current)
}
