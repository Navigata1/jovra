@preconcurrency import AVFoundation
import Foundation
import JovraBenchmark
import JovraCore
@testable import JovraMedia
import Testing

// T16 (#18) acceptance at the package seams: RecoveryScanner.scan() after a forced termination, and the
// CaptureEngine's own reaction to a media-services reset. Expected values are literals from the ticket
// (≤ 3 s lost, savedWithGaps, partial) or from an independent AVAssetReader frame count in this file.
// The forced termination is the engine's in-process crash hook; it proves the recovery pipeline on the
// fixture camera, never the hardware crash-loss bound (ADR-0010).

private actor HandoffSink: RecordingSink {
    private(set) var received: [(String, SessionRecording)] = []
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        received.append((sessionID, recording))
    }
}

private final class HeldClock: CaptureClock, @unchecked Sendable {
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

/// The real fixture camera; a rebuild completes at media time 1.5 s, as rebuilding AVCaptureSession takes a moment.
private final class RebuildingCamera: CaptureSource, @unchecked Sendable {
    let fixture: FixtureCamera
    let clock: VirtualCaptureClock
    private let lock = NSLock()
    private var prepares = 0
    init(fixture: FixtureCamera, clock: VirtualCaptureClock) { self.fixture = fixture; self.clock = clock }
    var mode: SessionRecordingMode { fixture.mode }
    var label: String { fixture.label }
    var prepareCount: Int { lock.withLock { prepares } }
    func prepare(preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws -> CaptureSourceFormat {
        let rebuild = lock.withLock { prepares += 1; return prepares > 1 }
        if rebuild { clock.advance(by: CMTimeSubtract(CMTime(value: 1500, timescale: 1000), clock.now())) }
        return try await fixture.prepare(preset: preset, microphone: microphone)
    }
    func start(at sessionTime: CMTime, onSample: @escaping @Sendable (CaptureSample) throws -> Void,
               onFailure: @escaping @Sendable (any Error) -> Void) async throws {
        try await fixture.start(at: sessionTime, onSample: onSample, onFailure: onFailure)
    }
    func stop() async { await fixture.stop() }
}

private func fixtureCamera() throws -> URL {
    let catalog = MediaFixtureCatalog.repository(filePath: #filePath)
    return try catalog.mediaURL(for: catalog.truth(id: "fixtureCamera/fixture-camera"))
}

private func libraryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("t16-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    return root
}

private func journal(_ folder: URL) throws -> CaptureJournalSnapshot {
    try CaptureJournal.open(url: folder.appendingPathComponent("capture-journal.json")).snapshot()
}

private func until(_ condition: () throws -> Bool) async throws {
    for _ in 0..<4000 {
        if (try? condition()) == true { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    Issue.record("condition never held")
}

/// Independent of the scanner: count decoded frames with AVAssetReader.
private func decodedFrames(_ url: URL) async throws -> Int {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    #expect(reader.startReading())
    var frames = 0
    while let sample = output.copyNextSampleBuffer() { if CMSampleBufferGetImageBuffer(sample) != nil { frames += 1 } }
    #expect(reader.status == .completed)
    return frames
}

private func seconds(_ time: MediaTime?) -> Double { time.map { Double($0.value) / Double($0.timescale) } ?? 0 }

/// Records 7 s of a 10 s fixture, waits until the 0–6 s fragments are synchronized, marks a point, then kills
/// the engine the way a forced termination does. Returns the crash moment in media seconds.
private func crashMidSegment(id: String, root: URL) async throws -> (folder: URL, crashedAt: Double) {
    let folder = root.appendingPathComponent("sessions/\(id)")
    let clock = HeldClock()
    let camera = FixtureCamera(url: try fixtureCamera(), duration: CMTime(value: 10, timescale: 1), clock: clock)
    let engine = CaptureEngine(source: camera, clock: clock, sink: HandoffSink())
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .granted)
    try await engine.start(sessionID: id, folder: folder)
    // Frames through 6.967 s are fed, so the recording reaches exactly 7 s of media.
    clock.release(through: CMTime(value: 209, timescale: 30))
    try await until { seconds(try journal(folder).lastConfirmedMediaTime) >= 6 - 1.0 / 30 }
    try await until { seconds(engine.status.recordingTime) >= 7 - 1.0 / 120 }
    _ = try engine.markPoint(note: "Crash point")
    let crashedAt = seconds(engine.status.recordingTime)
    await engine.simulateProcessDeath()
    let left = try journal(folder)
    #expect(!left.finished && left.segments.count == 1 && !left.segments[0].finalized)
    return (folder, crashedAt)
}

/// The journal left on disk, the scanner's receipt (its partial-recovery report) and the adopted session as a
/// visibly Sample document for the reference validator. Synthetic fixture-camera media only; no movie is copied.
private func evidence(_ name: String, folder: URL, result: RecoveredSession) throws {
    guard let path = ProcessInfo.processInfo.environment["JOVRA_RECOVERY_EVIDENCE_DIR"] else { return }
    let destination = URL(fileURLWithPath: path).appendingPathComponent(name)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for file in ["capture-journal.json", "capture-recovery.json"] {
        try FileManager.default.copyItem(at: folder.appendingPathComponent(file), to: destination.appendingPathComponent(file))
    }
    var session = try sampleCaptureSession(id: "sample-recovered-\(name)", title: "Sample recovered recording",
                                           recording: result.recording, marks: result.marks.isEmpty ? nil : result.marks)
    session.original = result.original
    try CanonicalJSON.encode(session).write(to: destination.appendingPathComponent("recovered-session.json"))
}

@Test func forcedTerminationMidSegmentRecoversEveryCompleteFragmentWithAtMostThreeSecondsLost() async throws {
    let root = try libraryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let (folder, crashedAt) = try await crashMidSegment(id: "forced-termination", root: root)
    let heartbeat = seconds(try journal(folder).lastConfirmedMediaTime)

    let scanner = RecoveryScanner(root: root)
    let result = try #require(try await scanner.scan().first)
    #expect(await scanner.refusals.isEmpty)
    let report = try #require(result.recording.recovery)
    let savedThrough = Double(try #require(report.savedThroughMs)) / 1000
    let lost = crashedAt - savedThrough
    print("T16 forced termination: crashed at \(crashedAt) s, heartbeat \(heartbeat) s, recovered \(savedThrough) s, measured seconds lost \(lost)")
    #expect(lost <= 3.0)
    #expect(savedThrough >= heartbeat - 1.0 / 30, "every synchronized fragment the journal confirmed is kept")
    #expect(report.outcome == .complete && (report.unrecoverable ?? []).isEmpty)
    #expect(result.original.state == .savedWithGaps)

    let segment = try #require(result.recording.segments.first)
    #expect(result.recording.segments.count == 1)
    #expect(segment.finalized && segment.recoveredAfterInterruption == true)
    // Decode-to-end, measured independently: 30 fps × the recovered seconds.
    let frames = try await decodedFrames(folder.appendingPathComponent(segment.file.path))
    #expect(frames == 180)
    #expect(segment.durationMs == 6000 && report.savedThroughMs == 6000)
    // The stretch after the last saved fragment is a gap, never silently closed up; the mark made just
    // before the crash stays on the timeline inside it.
    #expect(result.recording.gaps == [SessionGap(startMs: 6000, endMs: 7000, reason: .other)])
    #expect(result.recording.durationMs == 7000)
    #expect(result.marks.map(\.note) == ["Crash point"])
    try evidence("forced-termination", folder: folder, result: result)
}

@Test(arguments: ["torn-mid-fragment", "zero-filled-tail"])
func tornSegmentIsTruncatedToItsLastCompleteFragmentNotDiscarded(_ tear: String) async throws {
    let root = try libraryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let (folder, _) = try await crashMidSegment(id: tear, root: root)
    let media = folder.appendingPathComponent("originals/segment-0.mp4")
    // Tear the last fragment as a kill during its write would (keep only half of its bytes), or as power
    // loss can (the file was extended but its last fragment never reached storage: a zero-filled extent).
    let ends = try FragmentedMovieLayout.inspect(media).completeFragmentEnds
    try #require(ends.count == 3)
    let keep = ends[ends.count - 2]
    let cut = tear == "zero-filled-tail" ? keep : keep + (ends[ends.count - 1] - keep) / 2
    let handle = try FileHandle(forWritingTo: media)
    try handle.truncate(atOffset: cut)
    if tear == "zero-filled-tail" { try handle.seekToEnd(); try handle.write(contentsOf: Data(count: 4096)) }
    try handle.close()
    let tornBytes = try Data(contentsOf: media)

    let scanner = RecoveryScanner(root: root)
    let result = try #require(try await scanner.scan().first)
    let report = try #require(result.recording.recovery)
    #expect(report.truncatedSegmentIds == ["segment-0"])
    #expect(report.outcome == .complete && result.original.state == .savedWithGaps)
    // Truncated, not discarded: the segment is still listed, its file still exists, ends exactly at the
    // last complete fragment and decodes to the end.
    let segment = try #require(result.recording.segments.first)
    let kept = try Data(contentsOf: media)
    #expect(kept.count == Int(keep) && kept == tornBytes.prefix(Int(keep)))
    #expect(segment.file.bytes == Int(keep))
    #expect(try await decodedFrames(media) == 120)
    #expect(segment.durationMs == 4000 && report.savedThroughMs == 4000)
    #expect(result.recording.gaps == [SessionGap(startMs: 4000, endMs: 7000, reason: .other)])
    if tear == "torn-mid-fragment" { try evidence("torn-segment", folder: folder, result: result) }
}

@Test func unrecoverableSegmentIsReportedWithItsReasonWhileEveryPlayableSegmentIsKept() async throws {
    let root = try libraryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let id = "partial"
    let store = try SessionStore(root: root)
    var draft = try sampleCaptureSession(id: id, title: "Sample pending recording",
        recording: .init(mode: .simulatorFixture, segments: [], gaps: [], microphone: .notRequested, mediaAvailable: false),
        marks: nil)
    draft.original = .init(state: .recording)
    try await store.create(draft)
    let folder = root.appendingPathComponent("sessions/\(id)")
    let clock = VirtualCaptureClock()
    let camera = FixtureCamera(url: try fixtureCamera(), duration: CMTime(value: 3, timescale: 1), clock: clock)
    let engine = CaptureEngine(source: camera, clock: clock, sink: HandoffSink())
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    try await engine.start(sessionID: id, folder: folder)
    try await camera.waitUntilFinished()
    try await engine.pause()
    clock.advance(by: CMTimeSubtract(CMTime(value: 10, timescale: 1), clock.now()))
    try await engine.resume()
    try await camera.waitUntilFinished()
    try await until { (try journal(folder).segments.last?.durationMs ?? 0) >= 2000 }
    _ = try engine.markPoint(note: "Retained capture mark")
    await engine.simulateProcessDeath()
    // Explicit invalid bytes standing in for a damaged first segment, never a claimed capture.
    let damaged = folder.appendingPathComponent("originals/segment-0.mp4")
    try Data("not a movie".utf8).write(to: damaged)

    let scanner = RecoveryScanner(root: root)
    let result = try #require(try await scanner.scan().first)
    let report = try #require(result.recording.recovery)
    #expect(report.outcome == .partial)
    #expect(result.original.state == .partial && !(result.original.reason ?? "").isEmpty)
    let unrecoverable = try #require(report.unrecoverable)
    #expect(unrecoverable.map(\.path) == ["originals/segment-0.mp4"])
    #expect(unrecoverable.allSatisfy { !$0.reason.isEmpty && $0.reason.count <= 300 })
    #expect(result.recording.segments.map(\.id) == ["segment-1"])
    #expect(result.recording.segments.map(\.startMs) == [10_000])
    #expect(try await decodedFrames(folder.appendingPathComponent("originals/segment-1.mp4")) == 60)
    #expect(result.recording.gaps == [SessionGap(startMs: 0, endMs: 3000, reason: .other),
                                      SessionGap(startMs: 3000, endMs: 10_000, reason: .userPaused),
                                      SessionGap(startMs: 12_000, endMs: 13_000, reason: .other)])
    #expect(try Data(contentsOf: damaged) == Data("not a movie".utf8), "unrecoverable media is kept, never deleted")
    try evidence("partial-recovery", folder: folder, result: result)

    // Startup uses the same store transaction after a separate scan. Preserve edits written after scanning.
    let damagedWitness = try #require(await scanner.adoptionWitness(for: id))
    try Data("not a movie".utf8).write(to: damaged, options: .atomic)
    #expect(throws: RecoveryError.changedFile) { try damagedWitness.verify(in: folder) }
    try FileManager.default.removeItem(at: damaged)
    let missing = try #require(try await scanner.scan().first)
    #expect(missing.recording.recovery?.unrecoverable?.first?.reason == UnrecoverableReason.missing)
    let missingWitness = try #require(await scanner.adoptionWitness(for: id))
    try Data("not a movie".utf8).write(to: damaged)
    #expect(throws: RecoveryError.changedFile) { try missingWitness.verify(in: folder) }
    let current = try #require(try await scanner.scan().first)
    let witness = try #require(await scanner.adoptionWitness(for: id))
    try await store.update(id, facet: .review(.init(state: .inProgress)))
    let recoveredMovie = folder.appendingPathComponent(result.recording.segments[0].file.path)
    let movieBytes = try Data(contentsOf: recoveredMovie)
    let journalURL = folder.appendingPathComponent("capture-journal.json")
    let journalBytes = try Data(contentsOf: journalURL)
    #expect(try await store.reconcileCaptureRecovery(current.recording, marks: current.marks, original: current.original,
                                                     for: id, verifyOriginals: witness.verify))
    let adopted = try await store.load(id)
    #expect(adopted.original?.state == .partial)
    #expect(adopted.recording == current.recording)
    #expect(adopted.marks?.map(\.note) == ["Retained capture mark"])
    #expect(adopted.review?.state == .inProgress)
    #expect(try Data(contentsOf: recoveredMovie) == movieBytes)
    #expect(try Data(contentsOf: damaged) == Data("not a movie".utf8))
    #expect(try Data(contentsOf: journalURL) == journalBytes)
    if let path = ProcessInfo.processInfo.environment["JOVRA_RECOVERY_EVIDENCE_DIR"] {
        let destination = URL(fileURLWithPath: path).appendingPathComponent("partial-recovery/adopted-session.json")
        try Data(contentsOf: folder.appendingPathComponent("session.json")).write(to: destination)
    }

    let state = try folderState(folder)
    let reopened = try SessionStore(root: root)
    let rescan = RecoveryScanner(root: root)
    let repeated = try #require(try await rescan.scan { try await reopened.needsCaptureRecovery($0) }.first)
    let repeatedWitness = try #require(await rescan.adoptionWitness(for: id))
    #expect(try await !reopened.reconcileCaptureRecovery(repeated.recording, marks: repeated.marks,
        original: repeated.original, for: id, verifyOriginals: repeatedWitness.verify))
    #expect(try await reopened.load(id) == adopted)
    let repeatedState = try folderState(folder)
    #expect(Set(repeatedState.keys) == Set(state.keys))
    for (file, original) in state {
        let repeatedFile = try #require(repeatedState[file])
        #expect(repeatedFile.0 == original.0 && repeatedFile.1 == original.1)
    }
}

private func folderState(_ folder: URL) throws -> [String: (Data, Date)] {
    var state: [String: (Data, Date)] = [:]
    let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]))
    for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        let modified = try #require(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        state[url.path.replacingOccurrences(of: folder.path, with: "")] = (try Data(contentsOf: url), modified)
    }
    return state
}

@Test func runningTheScannerTwiceChangesNothingTheSecondTime() async throws {
    let root = try libraryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let (folder, _) = try await crashMidSegment(id: "twice", root: root)
    let media = folder.appendingPathComponent("originals/segment-0.mp4")
    let last = try #require(try FragmentedMovieLayout.inspect(media).completeFragmentEnds.last)
    let handle = try FileHandle(forWritingTo: media)
    try handle.truncate(atOffset: last - 100)
    try handle.close()

    let first = try await RecoveryScanner(root: root).scan()
    #expect(first.first?.recording.recovery?.truncatedSegmentIds == ["segment-0"])
    let afterFirst = try folderState(folder)
    let second = try await RecoveryScanner(root: root).scan()
    #expect(second == first)
    let afterSecond = try folderState(folder)
    #expect(Set(afterSecond.keys) == Set(afterFirst.keys))
    for (path, value) in afterFirst {
        #expect(afterSecond[path]?.0 == value.0, "\(path) bytes changed")
        #expect(afterSecond[path]?.1 == value.1, "\(path) was rewritten")
    }
}

@Test func mediaServicesResetRebuildsTheCaptureSessionAndResumesIntoANewSegmentWithARecordedGap() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("t16-reset-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let clock = VirtualCaptureClock()
    let fixture = FixtureCamera(url: try fixtureCamera(), duration: CMTime(value: 2, timescale: 1), clock: clock)
    let camera = RebuildingCamera(fixture: fixture, clock: clock)
    let sink = HandoffSink()
    let engine = CaptureEngine(source: camera, clock: clock, sink: sink)
    _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .denied)
    fixture.injectFailure(at: CMTime(value: 1, timescale: 1), failure: .mediaServicesReset)
    try await engine.start(sessionID: "media-reset", folder: folder)
    // No caller resumes: the engine rebuilds the source itself and keeps recording.
    try await until { try journal(folder).segments.count == 2 && seconds(engine.status.recordingTime) >= 3.5 - 1.0 / 30 }
    try await fixture.waitUntilFinished()
    #expect(engine.status.phase == .recording)
    let record = try await engine.stop()
    #expect(camera.prepareCount == 2)
    #expect(record.segments.map(\.startMs) == [0, 1500])
    #expect(record.segments.map(\.durationMs) == [1000, 2000])
    #expect(record.gaps == [SessionGap(startMs: 1000, endMs: 1500, reason: .cameraError)])
    try #require(record.segments.count == 2)
    #expect(try await decodedFrames(folder.appendingPathComponent(record.segments[1].file.path)) == 60)
    #expect(await sink.received.count == 1)
}
