import AVFoundation
import Foundation
import Testing
import JovraCore
@testable import JovraMedia
import JovraBenchmark

// T15 acceptance controls that sit beside CapturePipelineTests. Every expected value below is a literal from
// the ticket (#17) or the fixture's committed ground truth, never recomputed the way the engine computes it.

private actor ReceivingSink: RecordingSink {
    private(set) var received: [(String, SessionRecording, [SessionMark])] = []
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        received.append((sessionID, recording, marks))
    }
}

private final class ObservedActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func append(_ value: Bool) { lock.withLock { values.append(value) } }
    var recorded: [Bool] { lock.withLock { values } }
}

private func fixtureCameraURL() throws -> URL {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    return try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
}

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("t15-\(UUID().uuidString)")
}

@Test func oneSharedCaptureActivityTellsWorkersAboutEveryRecordingAcrossEngines() async throws {
    let url = try fixtureCameraURL()
    let shared = CaptureActivity()
    let worker = ObservedActivity()
    shared.observe { worker.append($0) }
    for index in 0..<2 {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: url, duration: CMTime(value: 1, timescale: 1), clock: clock)
        let engine = CaptureEngine(source: camera, clock: clock, sink: ReceivingSink(), activity: shared)
        #expect(engine.activity === shared)
        _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
        #expect(!shared.isActive)
        try await engine.start(sessionID: "shared-activity-\(index)", folder: folder)
        #expect(shared.isActive)
        try await camera.waitUntilFinished()
        _ = try await engine.stop()
        #expect(!shared.isActive)
    }
    // The initial observation, then exactly one start and one stop per recording: a processing or upload
    // worker subscribed once at launch sees both sessions without re-subscribing to each engine.
    #expect(worker.recorded == [false, true, false, true, false])
}

@Test func criticalHeatAbove30fpsJournalsTheFrameRateChangeAndContinuesAt30fpsInTheSameSession() async throws {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    // fc-060: 640 x 360, 60 fps, 120 frames (2 s), no audio (spec/fixtures/media/frameCounter/fc-060.truth.json).
    let url = try catalog.mediaURL(for: catalog.truth(id: "frameCounter/fc-060"))
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: url, duration: CMTime(value: 2, timescale: 1), clock: clock)
    let budget = FakeDeviceBudget(DeviceBudgetSnapshot(freeBytes: 1_000_000_000, batteryFraction: 0.8, lowPowerMode: false, thermalState: .nominal))
    let sink = ReceivingSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink, budget: budget)
    _ = try await engine.prepare(CapturePreset(width: 640, height: 360, frameRate: RecordedFrameRate(num: 60, den: 1)), microphone: .denied)
    try await engine.start(sessionID: "heat-downgrade", folder: folder)
    try await camera.waitUntilFinished()
    budget.set(DeviceBudgetSnapshot(freeBytes: 1_000_000_000, batteryFraction: 0.8, lowPowerMode: false, thermalState: .critical))
    #expect(try await engine.refreshBudget() == nil)
    #expect(engine.status.phase == .recording)
    try await camera.waitUntilFinished()
    let record = try await engine.stop()
    #expect(record.segments.map(\.frameRate) == [RecordedFrameRate(num: 60, den: 1), RecordedFrameRate(num: 30, den: 1)])
    #expect(record.segments.map(\.startMs) == [0, 2000])
    #expect(record.gaps.map(\.reason) == [.thermal])
    let events = try #require(record.captureEvents)
    #expect(events.map(\.kind) == [.thermalState, .frameRateChange])
    #expect(events[0].thermalState == .critical)
    #expect(events[1].frameRate == RecordedFrameRate(num: 30, den: 1))
    #expect(events[1].tMs == 2000)
    // Both segments are real, decodable media: 2 s at 60 fps, then the same 2 s source re-encoded at 30 fps.
    let frames = try await record.segments.asyncMap { try await decodeCaptureToEnd(folder.appendingPathComponent($0.file.path)).videoFrames }
    #expect(frames == [120, 60])
    #expect(record.segments.map(\.durationMs) == [2000, 2000])
    #expect(await sink.received.count == 1)
}

extension Sequence {
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}

/// An injected clock the test releases step by step, so "while recording" is a state the test can stop in
/// without waiting in wall time.
private final class GatedCaptureClock: CaptureClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = CMTime.zero
    private var released = CMTime.zero
    func now() -> CMTime { lock.withLock { current } }
    func release(through time: CMTime) { lock.withLock { released = time } }
    func wait(until time: CMTime) async throws {
        while true {
            try Task.checkCancellation()
            let ready = lock.withLock { () -> Bool in
                guard CMTimeCompare(time, released) <= 0 else { return false }
                if CMTimeCompare(time, current) > 0 { current = time }
                return true
            }
            if ready { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private func seconds(_ time: MediaTime?) -> Double? { time.map { Double($0.value) / Double($0.timescale) } }

/// Polls the journal on disk (the only place high-frequency state lives) until `condition` holds.
private func journalOnDisk(_ folder: URL, until condition: (CaptureJournalSnapshot) -> Bool) async throws -> CaptureJournalSnapshot {
    let url = folder.appendingPathComponent("capture-journal.json")
    for _ in 0..<2000 {
        if let snapshot = try? CaptureJournal.open(url: url).snapshot(), condition(snapshot) { return snapshot }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    return try CaptureJournal.open(url: url).snapshot()
}

@Test func savedThroughHeartbeatAdvancesInTwoSecondFragmentsWhileRecordingAndNeverRunsAheadOfTheMedia() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = GatedCaptureClock()
    let camera = FixtureCamera(url: try fixtureCameraURL(), duration: CMTime(value: 10, timescale: 1), clock: clock)
    let engine = CaptureEngine(source: camera, clock: clock, sink: ReceivingSink())
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "heartbeat", folder: folder)
    clock.release(through: CMTime(value: 7, timescale: 1))
    let midway = try await journalOnDisk(folder) { (seconds($0.lastConfirmedMediaTime) ?? 0) >= 4 }
    let savedThrough = try #require(seconds(midway.lastConfirmedMediaTime))
    // Only 7 s of media has been fed. The heartbeat is a whole 2 s fragment boundary that has been synchronized
    // to disk (4 s or 6 s), never the 7 s that was merely appended to the encoder.
    #expect([4.0, 6.0].contains { abs(savedThrough - $0) <= 1.0 / 30 })
    #expect(!midway.finished && !midway.segments[0].finalized)
    let bytesOnDisk = try Data(contentsOf: folder.appendingPathComponent(midway.segments[0].file.path)).count
    #expect(try #require(midway.segments[0].file.bytes) <= bytesOnDisk)
    #expect(engine.status.phase == .recording)
    clock.release(through: CMTime(value: 60, timescale: 1))
    try await camera.waitUntilFinished()
    let record = try await engine.stop()
    let final = try CaptureJournal.open(url: folder.appendingPathComponent("capture-journal.json")).snapshot()
    #expect(abs((seconds(final.lastConfirmedMediaTime) ?? 0) - 10) <= 1.0 / 30)
    #expect(record.durationMs == 10_000)
}

@Test func processDeathLeavesAnUnfinishedJournalWhoseSavedThroughIsBackedBySynchronizedBytes() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = GatedCaptureClock()
    let camera = FixtureCamera(url: try fixtureCameraURL(), duration: CMTime(value: 10, timescale: 1), clock: clock)
    let sink = ReceivingSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .granted)
    try await engine.start(sessionID: "process-death", folder: folder)
    clock.release(through: CMTime(value: 7, timescale: 1))
    let beforeDeath = try await journalOnDisk(folder) { (seconds($0.lastConfirmedMediaTime) ?? 0) >= 4 }
    await engine.simulateProcessDeath()
    // Nothing runs after a crash: no segment close, no journal finish, no sink handoff, no activity left on.
    let after = try CaptureJournal.open(url: folder.appendingPathComponent("capture-journal.json")).snapshot()
    #expect(!after.finished)
    #expect(after.segments.count == 1 && !after.segments[0].finalized)
    #expect(after.gaps.isEmpty)
    #expect((seconds(after.lastConfirmedMediaTime) ?? 0) >= (seconds(beforeDeath.lastConfirmedMediaTime) ?? 0))
    #expect((seconds(after.lastConfirmedMediaTime) ?? 99) <= 7)
    let bytesOnDisk = try Data(contentsOf: folder.appendingPathComponent(after.segments[0].file.path)).count
    #expect(try #require(after.segments[0].file.bytes) <= bytesOnDisk)
    #expect(await sink.received.isEmpty)
    #expect(!engine.activity.isActive)
    await #expect(throws: CaptureError.invalidState) { _ = try await engine.stop() }
}

/// A standalone, visibly Sample practice session carrying `recording`, built from the all-fields record so
/// every remaining field is contract-shaped. Used for the reference-validator evidence only.
func sampleCaptureSession(id: String, title: String, recording: SessionRecording, marks: [SessionMark]?) throws -> SessionDocument {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    var session = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: catalog.root.appendingPathComponent("spec/fixtures/records/session.all-fields.json")))
    session.id = id; session.title = title; session.recording = recording
    session.archive = SessionArchiveState(state: .localOnly); session.original = SessionOriginalState(state: .saved)
    session.capturePurpose = nil
    session.match = nil; session.sessionKind = .servePractice; session.sides = nil
    session.marks = marks; session.shots = nil; session.calibrations = nil; session.annotations = nil
    session.voiceNotes = nil; session.comparisons = nil; session.derivedValues = nil; session.equipmentUse = nil
    session.rallyPlayback = nil; session.serveMarks = nil; session.swings = nil; session.exports = nil
    session.analysis = nil; session.review = nil; session.consent = nil
    session.sample = SessionSampleInfo(synthetic: true, generator: "JOVRA FixtureCamera")
    return session
}

@Test func pauseAndResumeMakeTwoSegmentsAndOnePausedGapAndTheSinkReceivesEverySegmentAndGapFromTheJournal() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: try fixtureCameraURL(), duration: CMTime(value: 3, timescale: 1), clock: clock)
    let sink = ReceivingSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .granted)
    try await engine.start(sessionID: "pause-resume", folder: folder)
    try await camera.waitUntilFinished()
    _ = try engine.markPoint(note: "Changeover")
    try await engine.pause()
    clock.advance(by: CMTimeSubtract(CMTime(value: 90, timescale: 1), clock.now()))   // a 87 s changeover
    try await engine.resume()
    try await camera.waitUntilFinished()
    _ = try await engine.stop()
    let journal = try CaptureJournal.open(url: folder.appendingPathComponent("capture-journal.json")).snapshot()
    let received = try #require(await sink.received.first)
    #expect(await sink.received.count == 1)
    #expect(received.0 == "pause-resume")
    // Two segments, one gap whose contract reason for "paused" is userPaused, all in one session.
    #expect(received.1.segments.map(\.startMs) == [0, 90_000])
    #expect(received.1.segments.map(\.durationMs) == [3000, 3000])
    #expect(received.1.segments.allSatisfy { $0.finalized && $0.hasAudio })
    #expect(received.1.gaps == [SessionGap(startMs: 3000, endMs: 90_000, reason: .userPaused)])
    #expect(received.1.durationMs == 93_000 && received.1.mediaAvailable && received.1.microphone == .granted)
    // The handoff is the journal folded, nothing more and nothing less.
    #expect(journal.finished)
    #expect(received.1 == journal.recording)
    #expect(received.2 == (journal.marks ?? []))
    #expect(received.2.map(\.tMs) == [3000])
    if let output = ProcessInfo.processInfo.environment["JOVRA_CAPTURE_EVIDENCE_DIR"] {
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CanonicalJSON.encode(journal).write(to: directory.appendingPathComponent("pause-resume-journal.json"))
        let session = try sampleCaptureSession(id: "sample-capture-pause-resume", title: "Sample fixture recording with a changeover",
                                               recording: received.1, marks: received.2)
        try CanonicalJSON.encode(session).write(to: directory.appendingPathComponent("pause-resume-session.json"))
    }
}

/// Re-arms a media-services reset one second into every stream it is rebuilt for.
private final class RecurringResetCamera: CaptureSource, @unchecked Sendable {
    let fixture: FixtureCamera
    private let lock = NSLock()
    private var prepares = 0
    init(fixture: FixtureCamera) { self.fixture = fixture }
    var mode: SessionRecordingMode { fixture.mode }
    var label: String { fixture.label }
    var prepareCount: Int { lock.withLock { prepares } }
    func prepare(preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws -> CaptureSourceFormat {
        lock.withLock { prepares += 1 }
        fixture.injectFailure(at: CMTime(value: 1, timescale: 1), failure: .mediaServicesReset)
        return try await fixture.prepare(preset: preset, microphone: microphone)
    }
    func start(at sessionTime: CMTime, onSample: @escaping @Sendable (CaptureSample) throws -> Void,
               onFailure: @escaping @Sendable (any Error) -> Void) async throws {
        try await fixture.start(at: sessionTime, onSample: onSample, onFailure: onFailure)
    }
    func stop() async { await fixture.stop() }
}

// T16 (#18): the engine rebuilds after a reset on its own (CrashRecoveryTests). A reset that keeps recurring
// is rebuilt a bounded number of times, then the engine waits paused with the gap pending for the player.
@Test func recurringMediaServicesResetsStopBeingRebuiltAfterTheLimitAndLeaveTheRecordingPausedNotEnded() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let fixture = FixtureCamera(url: try fixtureCameraURL(), duration: CMTime(value: 2, timescale: 1), clock: clock)
    let camera = RecurringResetCamera(fixture: fixture)
    let sink = ReceivingSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "media-reset-limit", folder: folder)
    let journalURL = folder.appendingPathComponent("capture-journal.json")
    for _ in 0..<4000 {
        if engine.status.phase == .paused, camera.prepareCount == 4,
           (try? CaptureJournal.open(url: journalURL).snapshot()).map({ $0.segments.count == 4 && $0.segments.allSatisfy(\.finalized) }) == true { break }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(camera.prepareCount == 4, "the first prepare plus three automatic rebuilds")
    #expect(engine.status.phase == .paused && engine.activity.isActive)
    let paused = try CaptureJournal.open(url: journalURL).snapshot()
    #expect(paused.segments.count == 4 && paused.segments.allSatisfy { $0.finalized && $0.durationMs == 1000 })
    #expect(paused.gaps.count == 3 && paused.gaps.allSatisfy { $0.reason == .cameraError })
    try await engine.resume()   // The player's choice; this stream is not re-armed.
    try await fixture.waitUntilFinished()
    let record = try await engine.stop()
    #expect(record.segments.map(\.durationMs) == [1000, 1000, 1000, 1000, 2000])
    #expect(record.gaps.count == 4 && record.gaps.allSatisfy { $0.reason == .cameraError })
    #expect(await sink.received.count == 1)
}

@Test(arguments: [("lowStorage", SessionCaptureEventKind.lowStorageStop), ("lowBattery", .lowBatteryStop)])
func runningOutOfStorageOrBatteryMidRecordingStopsCleanlyWithPlayableMedia(_ name: String, _ expected: SessionCaptureEventKind) async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: try fixtureCameraURL(), duration: CMTime(value: 2, timescale: 1), clock: clock)
    let healthy = DeviceBudgetSnapshot(freeBytes: 8_000_000_000, batteryFraction: 0.9, lowPowerMode: false, thermalState: .nominal)
    let budget = FakeDeviceBudget(healthy)
    let sink = ReceivingSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink, budget: budget)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: "budget-\(name)", folder: folder)
    try await camera.waitUntilFinished()
    #expect(try await engine.refreshBudget() == nil)
    var exhausted = healthy
    if expected == .lowStorageStop { exhausted.freeBytes = 10 * 1024 * 1024 } else { exhausted.batteryFraction = 0.01 }
    budget.set(exhausted)
    let record = try #require(try await engine.refreshBudget())
    #expect(record.captureEvents?.map(\.kind) == [expected])
    #expect(record.segments.count == 1 && record.segments[0].finalized && record.segments[0].durationMs == 2000)
    #expect(engine.status.phase == .stopped && !engine.activity.isActive)
    #expect(await sink.received.count == 1)
    #expect(try await decodeCaptureToEnd(folder.appendingPathComponent(record.segments[0].file.path)).videoFrames == 60)
}

@Test func deviceBudgetFakeDrivesEveryReadingAndTheLiveAdapterReadsThisMachine() async throws {
    let fake = FakeDeviceBudget(DeviceBudgetSnapshot(freeBytes: 5_000_000_000, batteryFraction: 0.64, lowPowerMode: false, thermalState: .nominal))
    #expect(try await fake.snapshot() == DeviceBudgetSnapshot(freeBytes: 5_000_000_000, batteryFraction: 0.64, lowPowerMode: false, thermalState: .nominal))
    fake.set(DeviceBudgetSnapshot(freeBytes: 12, batteryFraction: nil, lowPowerMode: true, thermalState: .fair))
    let changed = try await fake.snapshot()
    #expect(changed.freeBytes == 12 && changed.batteryFraction == nil && changed.lowPowerMode && changed.thermalState == .fair)
    let live = try await LiveDeviceBudget(volume: FileManager.default.temporaryDirectory).snapshot()
    #expect(live.freeBytes > 0)
    #if os(macOS)
    #expect(live.batteryFraction == nil)   // macOS has no UIDevice battery reading; iOS reads UIDevice.
    #endif
    #expect(live.thermalState != .shutdown)  // ProcessInfo never reports the shutdown rung.
}
