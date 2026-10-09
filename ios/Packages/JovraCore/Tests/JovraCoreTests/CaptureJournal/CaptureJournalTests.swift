import Foundation
import Testing
@testable import JovraCore

@Test func durableJournalReopensWithOnlyConfirmedMediaAndSegmentIntent() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("capture-journal.json")
    let journal = try CaptureJournal(url: url, sessionID: "capture-test", mode: .simulatorFixture, microphone: .denied)
    let segment = SessionSegment(id: "segment-0", index: 0, file: RecordFileReference(path: "originals/segment-0.mp4"), startMs: 0, durationMs: 0, frameRate: RecordedFrameRate(num: 30, den: 1), width: 1280, height: 720, codec: .h264, hasAudio: false, finalized: false)
    try journal.beginSegment(segment)
    let intended = try CaptureJournal.open(url: url).snapshot()
    #expect(intended.segments.count == 1)
    #expect(intended.lastConfirmedMediaTime == nil)
    try journal.confirmDurableMedia(segmentID: segment.id, segmentDurationMs: 2000, sessionTime: MediaTime(value: 2, timescale: 1), bytes: 4096)
    let confirmed = try CaptureJournal.open(url: url).snapshot()
    #expect(confirmed.lastConfirmedMediaTime == (try MediaTime(value: 2, timescale: 1)))
    #expect(confirmed.segments[0].file.bytes == 4096)
    #expect(confirmed.segments[0].finalized == false)
    try journal.finalizeSegment(id: segment.id)
    try journal.appendGap(SessionGap(startMs: 2000, endMs: 5000, reason: .userPaused))
    try journal.finish()
    let saved = try CaptureJournal.open(url: url).snapshot()
    #expect(saved.recording.segments[0].finalized)
    #expect(saved.recording.gaps == [SessionGap(startMs: 2000, endMs: 5000, reason: .userPaused)])
    #expect(saved.recording.microphone == .denied)
    #expect(saved.recording.mediaAvailable)
}

private final class JournalWriteFault: @unchecked Sendable {
    private let lock = NSLock()
    private var fail = false
    func enable() { lock.withLock { fail = true } }
    func check() throws { if lock.withLock({ fail }) { throw CocoaError(.fileWriteOutOfSpace) } }
}
@Test func failedJournalReplacementPreservesPreviouslyDurableSnapshot() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("capture-journal.json")
    let fault = JournalWriteFault()
    let journal = try CaptureJournal(url: url, sessionID: "capture-test", mode: .camera, microphone: .notRequested, beforeReplace: { try fault.check() })
    fault.enable()
    #expect(throws: (any Error).self) { try journal.appendGap(SessionGap(startMs: 0, endMs: 1000, reason: .interruption)) }
    #expect(journal.snapshot().gaps.isEmpty)
    #expect(try CaptureJournal.open(url: url).snapshot().gaps.isEmpty)
    #expect(throws: CaptureJournalError.alreadyExists) { try CaptureJournal(url: url, sessionID: "other", mode: .camera, microphone: .granted) }
}

@Test func journalRefusesOverlappingSegmentsAndUnrelatedSavedThroughTime() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let journal = try CaptureJournal(url: folder.appendingPathComponent("journal.json"), sessionID: "guard-test", mode: .camera, microphone: .denied)
    let first = SessionSegment(id: "first", index: 0, file: RecordFileReference(path: "originals/first.mp4"), startMs: 0, durationMs: 0, frameRate: RecordedFrameRate(num: 30, den: 1), width: 1280, height: 720, codec: .h264, hasAudio: false, finalized: false)
    try journal.beginSegment(first)
    let prior = journal.snapshot()
    #expect(throws: CaptureJournalError.regressingCheckpoint) {
        try journal.confirmDurableMedia(segmentID: "first", segmentDurationMs: 2000, sessionTime: MediaTime(value: 10, timescale: 1), bytes: 4096)
    }
    #expect(journal.snapshot() == prior)
    try journal.confirmDurableMedia(segmentID: "first", segmentDurationMs: 2000, sessionTime: MediaTime(value: 20005, timescale: 10000), bytes: 4096)
    try journal.finalizeSegment(id: "first")
    var overlap = first; overlap.id = "second"; overlap.index = 1; overlap.startMs = 1000; overlap.file.path = "originals/second.mp4"
    #expect(throws: CaptureJournalError.invalidSegment) { try journal.beginSegment(overlap) }
    #expect(journal.snapshot().segments.count == 1)
}
