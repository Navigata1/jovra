import AVFoundation
import Foundation
import Testing
import JovraCore
@testable import JovraMedia
import JovraBenchmark

private actor CapturedRecordSink: RecordingSink {
    var received: SessionRecording?
    var receivedMarks: [SessionMark]?
    var calls = 0
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        received = recording; receivedMarks = marks; calls += 1
    }
}
@Test func fixtureSamplesReallyEncodeAndConfirmSixtySecondsOfDecodableMedia() async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let source = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: source, duration: CMTime(value: 60, timescale: 1), clock: clock)
    let sink = CapturedRecordSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720, frameRate: RecordedFrameRate(num: 30, den: 1)), microphone: .granted)
    try await engine.start(sessionID: "capture-test", folder: folder)
    #expect(engine.activity.isActive)
    try await camera.waitUntilFinished()
    let record = try await engine.stop()
    #expect(!engine.activity.isActive)
    #expect(record.mode == .simulatorFixture)
    #expect(record.segments.count == 1)
    #expect(record.segments[0].hasAudio)
    #expect(await sink.received == record)
    let media = folder.appendingPathComponent(record.segments[0].file.path)
    let info = try await MediaProbe.probe(media)
    #expect(info.video?.isDecodable == true)
    #expect(info.audio != nil)
    #expect(abs(info.duration.seconds - 60) <= 1.0 / 30)
    let decoded = try await decodeCaptureToEnd(media)
    #expect(decoded.videoFrames == 1800)
    let snapshot = try CaptureJournal.open(url: folder.appendingPathComponent("capture-journal.json")).snapshot()
    let confirmed = try #require(snapshot.lastConfirmedMediaTime)
    print("Captured duration=\(info.duration), decoded=\(decoded.duration), confirmed=\(confirmed), bytes=\(String(describing: snapshot.segments[0].file.bytes)), actual=\(try Data(contentsOf: media).count)")
    #expect(abs(Double(confirmed.value) / Double(confirmed.timescale) - decoded.duration.seconds) <= 1.0 / 30)
    #expect(snapshot.segments[0].finalized)
    #expect(snapshot.segments[0].file.bytes == (try Data(contentsOf: media).count))
    #expect(try Data(contentsOf: media) != Data(contentsOf: source))
    if let output = ProcessInfo.processInfo.environment["JOVRA_CAPTURE_EVIDENCE_DIR"] {
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CanonicalJSON.encode(snapshot).write(to: directory.appendingPathComponent("sample-journal.json"))
        if let mediaOutput = ProcessInfo.processInfo.environment["JOVRA_CAPTURE_VIDEO_EVIDENCE_DIR"] {
            let mediaDirectory = URL(fileURLWithPath: mediaOutput)
            try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            let target = mediaDirectory.appendingPathComponent("sample-fixture-60s.mp4")
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: media, to: target)
        }
        var session = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: catalog.root.appendingPathComponent("spec/fixtures/records/session.all-fields.json")))
        session.id = "capture-test"; session.title = "Sample fixture recording"; session.recording = record
        session.archive = SessionArchiveState(state: .localOnly); session.original = SessionOriginalState(state: .saved)
        session.capturePurpose = nil
        session.match = nil; session.sessionKind = .servePractice; session.sides = nil
        session.marks = nil; session.shots = nil; session.calibrations = nil; session.annotations = nil
        session.voiceNotes = nil; session.comparisons = nil; session.derivedValues = nil; session.equipmentUse = nil
        session.rallyPlayback = nil; session.serveMarks = nil; session.swings = nil; session.exports = nil
        session.analysis = nil; session.review = nil; session.consent = nil
        session.sample = SessionSampleInfo(synthetic: true, generator: "JOVRA FixtureCamera")
        try CanonicalJSON.encode(session).write(to: directory.appendingPathComponent("sample-session.json"))
    }
}

private final class ActivityObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func append(_ active: Bool) { lock.withLock { values.append(active) } }
    var recorded: [Bool] { lock.withLock { values } }
}
@Test func pauseAndInterruptionKeepOneSessionAndDeniedMicrophoneKeepsVideo() async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let url = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: url, duration: CMTime(value: 2, timescale: 1), clock: clock)
    let sink = CapturedRecordSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink)
    let observations = ActivityObservations()
    engine.activity.observe { observations.append($0) }
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "paused-test", folder: folder)
    try await camera.waitUntilFinished()
    try await engine.pause()
    #expect(engine.activity.isActive)
    clock.advance(by: CMTimeSubtract(CMTime(value: 5, timescale: 1), clock.now()))
    try await engine.resume()
    try await camera.waitUntilFinished()
    try await engine.interrupt(reason: .interruption)
    clock.advance(by: CMTimeSubtract(CMTime(value: 8, timescale: 1), clock.now()))
    let record = try await engine.stop()
    #expect(record.segments.count == 2)
    #expect(record.segments.map(\.startMs) == [0, 5000])
    #expect(record.gaps == [SessionGap(startMs: 2000, endMs: 5000, reason: .userPaused), SessionGap(startMs: 7000, endMs: 8000, reason: .interruption)])
    #expect(record.durationMs == 8000)
    #expect(record.microphone == .denied)
    #expect(record.segments.allSatisfy { !$0.hasAudio && $0.finalized })
    #expect(observations.recorded == [false, true, false])
    for segment in record.segments {
        let media = folder.appendingPathComponent(segment.file.path)
        #expect(try await MediaProbe.probe(media).audio == nil)
        #expect(try await decodeCaptureToEnd(media).videoFrames == 60)
    }
}

@Test func injectedDeviceBudgetIsVisibleBeforeRecordingAndLowStorageRefusesStart() async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let url = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let clock = VirtualCaptureClock()
    let budget = FakeDeviceBudget(DeviceBudgetSnapshot(freeBytes: 1024, batteryFraction: 0.12, lowPowerMode: true, thermalState: .serious))
    let engine = CaptureEngine(source: FixtureCamera(url: url, clock: clock), clock: clock, sink: CapturedRecordSink(), budget: budget)
    let report = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    #expect(report.budget.freeBytes == 1024)
    #expect(report.budget.batteryFraction == 0.12)
    #expect(report.budget.lowPowerMode)
    #expect(report.budget.thermalState == .serious)
    #expect(report.warnings.contains(.lowStorage))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    await #expect(throws: CaptureError.storageUnavailable) { try await engine.start(sessionID: "no-space", folder: folder) }
    #expect(!engine.activity.isActive)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
}

@Test func thermalBudgetRungsAreJournalledAndShutdownClosesPlayableMedia() async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let url = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: url, duration: CMTime(value: 2, timescale: 1), clock: clock)
    let budget = FakeDeviceBudget(DeviceBudgetSnapshot(freeBytes: 1_000_000_000, batteryFraction: 0.5, lowPowerMode: false, thermalState: .nominal))
    let engine = CaptureEngine(source: camera, clock: clock, sink: CapturedRecordSink(), budget: budget)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "thermal-test", folder: folder)
    try await camera.waitUntilFinished()
    for rung in [SessionCaptureEventThermalState.fair, .serious, .critical] {
        budget.set(DeviceBudgetSnapshot(freeBytes: 1_000_000_000, batteryFraction: 0.5, lowPowerMode: false, thermalState: rung))
        #expect(try await engine.refreshBudget() == nil)
    }
    #expect(engine.status.helpersMayRun == false)
    #expect(engine.status.previewMode == .courtMode)
    budget.set(DeviceBudgetSnapshot(freeBytes: 1_000_000_000, batteryFraction: 0.5, lowPowerMode: false, thermalState: .shutdown))
    let record = try #require(await engine.refreshBudget())
    #expect(record.captureEvents?.filter { $0.kind == .thermalState }.map(\.thermalState) == [.fair, .serious, .critical, .shutdown])
    #expect(record.segments[0].finalized)
    #expect(!engine.activity.isActive)
    #expect(try await decodeCaptureToEnd(folder.appendingPathComponent(record.segments[0].file.path)).videoFrames == 60)
}

@Test func injectedSourceInterruptionClosesSegmentAndCanResume() async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let url = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: url, duration: CMTime(value: 2, timescale: 1), clock: clock)
    let engine = CaptureEngine(source: camera, clock: clock, sink: CapturedRecordSink())
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    camera.injectFailure(at: CMTime(value: 1, timescale: 1), failure: .interrupted)
    try await engine.start(sessionID: "fault-test", folder: folder)
    await #expect(throws: CaptureSourceFailure.interrupted) { try await camera.waitUntilFinished() }
    for _ in 0..<1000 where engine.status.phase != .paused { try await Task.sleep(nanoseconds: 1_000_000) }
    #expect(engine.status.phase == .paused)
    clock.advance(by: CMTimeSubtract(CMTime(value: 3, timescale: 1), clock.now()))
    try await engine.resume()
    try await camera.waitUntilFinished()
    let record = try await engine.stop()
    #expect(record.segments.count == 2)
    #expect(record.gaps == [SessionGap(startMs: 1000, endMs: 3000, reason: .interruption)])
    #expect(try await decodeCaptureToEnd(folder.appendingPathComponent(record.segments[0].file.path)).videoFrames == 30)
}

@Test func liveMarkNoteSurvivesReopeningTheJournal() async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let url = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: url, duration: CMTime(value: 2, timescale: 1), clock: clock)
    let sink = CapturedRecordSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "marked-test", folder: folder)
    try await camera.waitUntilFinished()
    let markTime = try engine.markPoint(note: "Review the contact")
    #expect(markTime.value == 2 * Int64(markTime.timescale))
    let marks = try #require(CaptureJournal.open(url: folder.appendingPathComponent("capture-journal.json")).snapshot().marks)
    #expect(marks.count == 1)
    #expect(marks[0].note == "Review the contact")
    #expect(marks[0].tMs == 2000)
    #expect(marks[0].provenance.status == .manual)
    let record = try await engine.stop()
    #expect(await sink.calls == 1)
    #expect(await sink.received == record)
    #expect(await sink.receivedMarks == marks)
}

private final class ResumeRefusingSource: CaptureSource, @unchecked Sendable {
    let mode = SessionRecordingMode.simulatorFixture
    let label = "Simulator fixture with resume refusal"
    let camera: FixtureCamera
    private let lock = NSLock()
    private var starts = 0
    init(_ camera: FixtureCamera) { self.camera = camera }
    func prepare(preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws -> CaptureSourceFormat {
        try await camera.prepare(preset: preset, microphone: microphone)
    }
    func start(at time: CMTime, onSample: @escaping @Sendable (CaptureSample) throws -> Void,
               onFailure: @escaping @Sendable (any Error) -> Void) async throws {
        let number = lock.withLock { starts += 1; return starts }
        if number > 1 { throw CaptureError.sourceFailed("resume refused") }
        try await camera.start(at: time, onSample: onSample, onFailure: onFailure)
    }
    func stop() async { await camera.stop() }
}
@Test func resumedSourceFailureReturnsToPausedAndKeepsPreviouslyConfirmedMedia() async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    let url = try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: url, duration: CMTime(value: 2, timescale: 1), clock: clock)
    let engine = CaptureEngine(source: ResumeRefusingSource(camera), clock: clock, sink: CapturedRecordSink())
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "resume-refused", folder: folder)
    try await camera.waitUntilFinished(); try await engine.pause()
    clock.advance(by: CMTimeSubtract(CMTime(value: 3, timescale: 1), clock.now()))
    await #expect(throws: CaptureError.sourceFailed("resume refused")) { try await engine.resume() }
    #expect(engine.status.phase == .paused)
    let saved = try CaptureJournal.open(url: folder.appendingPathComponent("capture-journal.json")).snapshot()
    #expect(saved.segments[0].finalized)
    #expect(saved.lastConfirmedMediaTime == (try MediaTime(value: 1200, timescale: 600)))
    #expect(try await decodeCaptureToEnd(folder.appendingPathComponent(saved.segments[0].file.path)).videoFrames == 60)
}
