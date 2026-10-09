import AVFoundation
import Foundation
import Testing
import JovraCore
import JovraMedia
import JovraBenchmark

private actor DirectoryFaultSink: RecordingSink {
    var calls = 0
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws { calls += 1 }
}

/// A real fixture sample source pauses at the filesystem fault; no writer or fragment is mocked.
private final class MovingMediaClock: CaptureClock, @unchecked Sendable {
    private let lock = NSLock()
    private let folder: URL
    private let replaceFile: Bool
    private var time = CMTime.zero
    private var confirmedAfterMove: MediaTime?
    init(folder: URL, replaceFile: Bool) { self.folder = folder; self.replaceFile = replaceFile }
    func now() -> CMTime { lock.withLock { time } }
    var checkpoint: MediaTime? { lock.withLock { confirmedAfterMove } }
    func wait(until next: CMTime) async throws {
        try Task.checkCancellation()
        lock.withLock { time = next }
        guard next.seconds >= 4, checkpoint == nil else { return }
        let wal = folder.appendingPathComponent("capture-journal.json")
        let before = try CaptureJournal.open(url: wal).snapshot()
        guard before.lastConfirmedMediaTime != nil else { return }
        let originals = folder.appendingPathComponent("originals")
        try FileManager.default.moveItem(at: originals, to: folder.appendingPathComponent("retained-originals"))
        if replaceFile {
            try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: false)
            let path = try #require(before.segments.first?.file.path)
            try Data("replacement remains untouched".utf8).write(to: folder.appendingPathComponent(path))
        }
        // Let any fragment that was acknowledged before the move complete its WAL write.
        try await Task.sleep(for: .milliseconds(100))
        let after = try #require(CaptureJournal.open(url: wal).snapshot().lastConfirmedMediaTime)
        lock.withLock { confirmedAfterMove = after }
    }
}

@Test(arguments: [false, true])
func movingDeclaredMediaAfterFirstCheckpointRefusesFurtherAcknowledgment(replaceFile: Bool) async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let source = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = MovingMediaClock(folder: folder, replaceFile: replaceFile)
    let camera = FixtureCamera(url: source, duration: CMTime(value: 30, timescale: 1), clock: clock)
    let sink = DirectoryFaultSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "directory-fault", folder: folder)
    await #expect(throws: (any Error).self) { try await camera.waitUntilFinished() }
    let confirmed = try #require(clock.checkpoint, "The fault must follow an actual durable media checkpoint")
    // The asynchronous source-refusal callback closes the writer before exposing paused.
    let deadline = ContinuousClock.now + .seconds(5)
    while engine.status.phase == .pausing || engine.status.phase == .recording {
        guard ContinuousClock.now < deadline else { Issue.record("Source fault did not settle"); break }
        try await Task.sleep(for: .milliseconds(10))
    }
    let snapshot = try CaptureJournal.open(url: folder.appendingPathComponent("capture-journal.json")).snapshot()
    #expect(snapshot.lastConfirmedMediaTime == confirmed)
    #expect(snapshot.segments.allSatisfy { !$0.finalized })
    #expect(await sink.calls == 0)
    if replaceFile {
        let path = try #require(snapshot.segments.first?.file.path)
        #expect(try Data(contentsOf: folder.appendingPathComponent(path)) == Data("replacement remains untouched".utf8))
    }
}
