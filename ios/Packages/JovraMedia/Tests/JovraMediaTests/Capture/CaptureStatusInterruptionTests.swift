import AVFoundation
import Foundation
import Testing
import JovraCore
@testable import JovraMedia
import JovraBenchmark

// T17: the recording screen reads what the journal holds, never a guess. The status says which interruption
// is pending ("Recording stopped at 00:03 — Resume?") and lists every recorded gap ("Gap 00:03–00:20 ·
// interruption"). Expected values are literals from the fixture's 3 s clip and the injected clock.

private actor DiscardingSink: RecordingSink {
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {}
}

private func fixtureURL() throws -> URL {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    return try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
}

@Test func anInterruptionIsPendingInTheStatusUntilResumeRecordsItAsAGap() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("t17-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: try fixtureURL(), duration: CMTime(value: 3, timescale: 1), clock: clock)
    let engine = CaptureEngine(source: camera, clock: clock, sink: DiscardingSink())
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    #expect(engine.status.interruption == nil)
    #expect(engine.status.gaps.isEmpty)

    try await engine.start(sessionID: "interruption-status", folder: folder)
    try await camera.waitUntilFinished()
    try await engine.interrupt(reason: .interruption)

    let interrupted = engine.status
    #expect(interrupted.phase == .paused)
    #expect(interrupted.interruption == CaptureInterruption(startMs: 3000, reason: .interruption))
    #expect(interrupted.gaps.isEmpty, "A pending interruption is not a recorded gap until the player resumes or stops")

    clock.advance(by: CMTimeSubtract(CMTime(value: 20, timescale: 1), clock.now()))
    try await engine.resume()
    let resumed = engine.status
    #expect(resumed.phase == .recording)
    #expect(resumed.interruption == nil)
    #expect(resumed.gaps == [SessionGap(startMs: 3000, endMs: 20_000, reason: .interruption)])
    try await camera.waitUntilFinished()
    _ = try await engine.stop()
}

@Test func aPlayerPauseIsNotReportedAsAnInterruption() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("t17-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: try fixtureURL(), duration: CMTime(value: 1, timescale: 1), clock: clock)
    let engine = CaptureEngine(source: camera, clock: clock, sink: DiscardingSink())
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "pause-status", folder: folder)
    try await camera.waitUntilFinished()
    try await engine.pause()
    #expect(engine.status.phase == .paused)
    #expect(engine.status.interruption == nil)
    _ = try await engine.stop()
    #expect(engine.status.gaps.map(\.reason) == [.userPaused])
}
