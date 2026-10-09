import AVFoundation
import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

private actor FailedFinalHandoff: RecordingSink {
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

private func finishedStaleRecording(in root: URL) async throws -> (SessionStore, String, URL) {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let source = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let store = try SessionStore(root: root)
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: catalog.root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    document.id = "finished-stale"; document.match = nil; document.sides = nil
    document.sessionKind = .servePractice
    document.recording = .init(mode: .simulatorFixture, segments: [], gaps: [], microphone: .denied, mediaAvailable: false)
    document.marks = nil
    try await store.create(document)
    let folder = try await store.sessionDirectory(document.id)
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: source, duration: CMTime(value: 2, timescale: 1), clock: clock)
    let engine = CaptureEngine(source: camera, clock: clock, sink: FailedFinalHandoff())
    _ = try await engine.prepare(.init(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: document.id, folder: folder)
    try await camera.waitUntilFinished()
    await #expect(throws: (any Error).self) { _ = try await engine.stop() }
    return (store, document.id, folder)
}

@Test func finishedJournalWithFailedFinalHandoffRecoversVerifiedMediaWithoutChangingRawCustody() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, sessionID, folder) = try await finishedStaleRecording(in: root)
    let journalURL = folder.appendingPathComponent("capture-journal.json")
    let rawJournal = try Data(contentsOf: journalURL)
    let snapshot = try CaptureJournal.open(url: journalURL).snapshot()
    #expect(snapshot.finished)
    let rawURL = folder.appendingPathComponent(try #require(snapshot.segments.first).file.path)
    let rawMovie = try Data(contentsOf: rawURL)
    let scanner = RecoveryScanner(root: root)
    let recovered = try await scanner.scan()
    let result = try #require(recovered.first)
    #expect(recovered.count == 1 && result.sessionID == sessionID)
    #expect(result.recording.recovery?.outcome == .complete)
    #expect(result.recording.recovery?.savedThroughMs == 2000)
    #expect(result.recording.durationMs == 2000 && result.original.state == .saved)
    let retained = folder.appendingPathComponent(try #require(result.recording.segments.first).file.path)
    let asset = AVURLAsset(url: retained)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output); #expect(reader.startReading())
    var frames = 0
    while let sample = output.copyNextSampleBuffer() {
        #expect(CMSampleBufferGetImageBuffer(sample) != nil); frames += 1
    }
    #expect(reader.status == .completed && frames == 60)
    try await store.applyRecoveredCapture(result.recording, marks: result.marks, original: result.original, for: result.sessionID)
    let sessionBytes = try Data(contentsOf: folder.appendingPathComponent("session.json"))
    let second = try await scanner.scan()
    #expect(second == recovered)
    try await store.applyRecoveredCapture(result.recording, marks: result.marks, original: result.original, for: result.sessionID)
    #expect(try Data(contentsOf: folder.appendingPathComponent("session.json")) == sessionBytes)
    #expect(try Data(contentsOf: journalURL) == rawJournal)
    #expect(try Data(contentsOf: rawURL) == rawMovie)
    if let path = ProcessInfo.processInfo.environment["JOVRA_RECOVERY_EVIDENCE_DIR"] {
        let destination = URL(fileURLWithPath: path).appendingPathComponent(sessionID)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder, to: destination)
    }
}

@Test func brokenMediaPeersAreExplicitlyRefusedWithoutHidingHealthyCapture() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, healthyID, healthyFolder) = try await finishedStaleRecording(in: root)
    let rawJournal = try Data(contentsOf: healthyFolder.appendingPathComponent("capture-journal.json"))
    let snapshot = try ContractCodec.decode(CaptureJournalSnapshot.self, from: rawJournal)
    let rawMedia = try Data(contentsOf: healthyFolder.appendingPathComponent(snapshot.segments[0].file.path))
    for id in ["missing-peer", "corrupt-peer"] {
        let folder = root.appendingPathComponent("sessions/\(id)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("originals"), withIntermediateDirectories: true)
        var invalid = snapshot; invalid.sessionID = id
        try CanonicalJSON.encode(invalid).write(to: folder.appendingPathComponent("capture-journal.json"))
        // Explicit invalid bytes, never a claimed camera capture or playable fixture.
        if id == "corrupt-peer" { try Data("not a movie".utf8).write(to: folder.appendingPathComponent(invalid.segments[0].file.path)) }
    }
    let scanner = RecoveryScanner(root: root)
    let results = try await scanner.scan()
    #expect(results.map(\.sessionID) == [healthyID])
    let refused = await scanner.refusals
    #expect(Set(refused.map(\.sessionID)) == ["missing-peer", "corrupt-peer"])
    #expect(refused.allSatisfy { !$0.reason.isEmpty })
    #expect(try Data(contentsOf: healthyFolder.appendingPathComponent("capture-journal.json")) == rawJournal)
    #expect(try Data(contentsOf: healthyFolder.appendingPathComponent(snapshot.segments[0].file.path)) == rawMedia)
    #expect(try Data(contentsOf: root.appendingPathComponent("sessions/corrupt-peer/originals/segment-0.mp4")) == Data("not a movie".utf8))
}

@Test(arguments: ["negative-mark", "future-mark", "overlapping-gap", "negative-gap", "backwards-gap", "overlapping-gaps"])
func corruptLedgerTimesCannotBeAdoptedAsVerifiedCapture(fault: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, id, folder) = try await finishedStaleRecording(in: root)
    let journalURL = folder.appendingPathComponent("capture-journal.json")
    var snapshot = try CaptureJournal.open(url: journalURL).snapshot()
    switch fault {
    case "overlapping-gap": snapshot.gaps = [.init(startMs: 500, endMs: 1000, reason: .cameraError)]
    case "negative-gap": snapshot.gaps = [.init(startMs: -1, endMs: 0, reason: .cameraError)]
    case "backwards-gap": snapshot.gaps = [.init(startMs: 3000, endMs: 2000, reason: .cameraError)]
    case "overlapping-gaps": snapshot.gaps = [.init(startMs: 2000, endMs: 3000, reason: .cameraError), .init(startMs: 2500, endMs: 4000, reason: .cameraError)]
    default: snapshot.marks = [.init(id: "bad-time", tMs: fault == "negative-mark" ? -1 : 2001, kind: .point,
                                   provenance: .init(status: .manual, source: "captureMark", sample: true))]
    }
    let corrupted = try CanonicalJSON.encode(snapshot)
    try corrupted.write(to: journalURL)
    let scanner = RecoveryScanner(root: root)
    #expect(try await scanner.scan().isEmpty)
    #expect(await scanner.refusals.map(\.sessionID) == [id])
    #expect(try Data(contentsOf: journalURL) == corrupted)
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("capture-recovery.json").path))
}
