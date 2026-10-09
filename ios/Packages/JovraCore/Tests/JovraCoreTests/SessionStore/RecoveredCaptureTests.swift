import Foundation
import Testing
import JovraCore

@Test func recoveryAdoptionAtomicallyKeepsEditedMarksReportOriginalAndIndependentFacets() async throws {
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repo.deleteLastPathComponent() }
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repo.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let edited = SessionMark(id: "edited", tMs: 100, kind: .point, note: "Player correction", provenance: .init(status: .manual, source: "user"))
    document.marks = [edited]; document.sample = nil
    let store = try SessionStore(root: directory)
    try await store.create(document)
    let segment = SessionSegment(id: "retained", index: 0, file: .init(path: "originals/recovered.mp4"), startMs: 0, durationMs: 2000, frameRate: .init(num: 30, den: 1), width: 1280, height: 720, codec: .h264, hasAudio: false, finalized: true)
    let report = SessionRecoveryReport(recoveredAt: "2026-10-09T12:00:00Z", outcome: .partial, savedThroughMs: 2000, truncatedSegmentIds: [segment.id])
    let recording = SessionRecording(mode: .simulatorFixture, durationMs: nil, segments: [segment], gaps: [], microphone: .denied, mediaAvailable: true, recovery: report)
    let original = SessionOriginalState(state: .partial, reason: "Lost suffix duration unknown")
    var stale = edited; stale.note = "Old journal note"
    let incoming = SessionMark(id: "durable-mark", tMs: 1500, kind: .point, provenance: .init(status: .manual, source: "captureMark", sample: true))
    let metadata = directory.appendingPathComponent("sessions/\(document.id)/session.json")
    let before = try Data(contentsOf: metadata)
    let failing = try SessionStore(root: directory, writeFault: { _ in throw CocoaError(.fileWriteOutOfSpace) })
    await #expect(throws: (any Error).self) {
        try await failing.applyRecoveredCapture(recording, marks: [stale, incoming], original: original, for: document.id)
    }
    #expect(try Data(contentsOf: metadata) == before)
    try await store.applyRecoveredCapture(recording, marks: [stale, incoming], original: original, for: document.id)
    let actual = try await store.load(document.id)
    #expect(actual.recording == recording && actual.recording.recovery == report)
    #expect(actual.original == original && actual.marks == [edited, incoming])
    #expect(actual.match == document.match && actual.analysis == document.analysis)
    #expect(actual.review == document.review && actual.archive == document.archive)
    #expect(actual.storage.originals == .onDevice)
    #expect(actual.sample?.synthetic == true)
    let firstCommit = try Data(contentsOf: metadata)
    try await store.applyRecoveredCapture(recording, marks: [incoming], original: original, for: document.id)
    #expect(try Data(contentsOf: metadata) == firstCommit)
}
