@preconcurrency import AVFoundation
import Foundation
import JovraCore

public enum CapturePhase: String, Sendable { case idle, ready, recording, pausing, paused, stopping, stopped }
public enum CapturePreviewMode: String, Sendable { case normal, dimmed, courtMode }
public struct CaptureStatus: Sendable {
    public let phase: CapturePhase
    public let recordingTime: MediaTime?
    public let savedThrough: MediaTime?
    public let sourceLabel: String
    public let budget: DeviceBudgetSnapshot?
    public let helpersMayRun: Bool
    public let previewMode: CapturePreviewMode
}

/// Serial capture state; sample-buffer appends and transitions share one queue. Analysis, networking,
/// account and SessionStore are absent. The sole store handoff is the typed sink after stop/verification.
public final class CaptureEngine: @unchecked Sendable {
    public let activity = CaptureActivity()
    private let source: any CaptureSource
    private let clock: any CaptureClock
    private let sink: any RecordingSink
    private let budget: any DeviceBudget
    private var lastBudget: DeviceBudgetSnapshot?
    private let queue = DispatchQueue(label: "com.islanddevcrew.jovra.capture")
    private var phase = CapturePhase.idle
    private var preset: CapturePreset?
    private var format: CaptureSourceFormat?
    private var microphone = SessionRecordingMicrophone.notRequested
    private var journal: CaptureJournal?
    private var writer: CaptureSegmentWriter?
    private var segment: SessionSegment?
    private var sessionFolder: URL?
    private var sessionID: String?
    private var clockOrigin = CMTime.zero
    private var latestVideoTime = CMTime.zero
    private var pendingGap: (startMs: Int, reason: SessionGapReason)?
    private var continuations: [UUID: AsyncStream<CaptureStatus>.Continuation] = [:]

    public init(source: any CaptureSource, clock: any CaptureClock = RealtimeCaptureClock(), sink: any RecordingSink, budget: any DeviceBudget = LiveDeviceBudget()) {
        self.source = source; self.clock = clock; self.sink = sink; self.budget = budget
    }
    public var status: CaptureStatus { queue.sync { makeStatus() } }
    public var recordedMarks: [SessionMark] { queue.sync { journal?.snapshot().marks ?? [] } }
    public var statuses: AsyncStream<CaptureStatus> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            queue.sync { continuations[id] = continuation; continuation.yield(makeStatus()) }
            continuation.onTermination = { [weak self] _ in self?.queue.async { [weak self] in self?.continuations.removeValue(forKey: id) } }
        }
    }
    @discardableResult public func prepare(_ preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws -> PreflightReport {
        guard queue.sync(execute: { phase == .idle || phase == .stopped }) else { throw CaptureError.invalidState }
        guard preset.width > 0, preset.height > 0, preset.bitRate > 0, preset.bitRate <= 100_000_000,
              preset.frameRate.num > 0, preset.frameRate.num <= Int32.max, preset.frameRate.den > 0 else { throw CaptureError.unsupportedPreset }
        let format = try await source.prepare(preset: preset, microphone: microphone)
        let reading = try await budget.snapshot()
        queue.sync { self.preset = preset; self.format = format; self.microphone = microphone == .granted && !format.hasAudio ? .unavailable : microphone; self.lastBudget = reading; phase = .ready; emitStatus() }
        let estimate = Int64(preset.bitRate) * 3600 / 8
        var warnings: [CaptureWarning] = []
        if reading.freeBytes < 32 * 1024 * 1024 { warnings.append(.lowStorage) }
        if let battery = reading.batteryFraction, battery < 0.2 { warnings.append(.lowBattery) }
        if reading.lowPowerMode { warnings.append(.lowPowerMode) }
        if reading.thermalState == .serious || reading.thermalState == .critical { warnings.append(.phoneWarming) }
        return PreflightReport(format: format, supportedPresets: [preset], budget: reading,
                               estimatedStorageRange: estimate / 2 ... estimate + estimate / 5, warnings: warnings)
    }
    public func start(sessionID: String, folder: URL) async throws {
        try queue.sync {
            guard phase == .ready else { throw CaptureError.invalidState }
            guard (lastBudget?.freeBytes ?? 0) >= 32 * 1024 * 1024 else { throw CaptureError.storageUnavailable }
            self.sessionID = sessionID; self.sessionFolder = folder; self.clockOrigin = clock.now(); latestVideoTime = .zero
            journal = try CaptureJournal(url: folder.appendingPathComponent("capture-journal.json"), sessionID: sessionID,
                                         mode: source.mode, microphone: microphone)
            try openSegment(at: .zero)
            phase = .recording; emitStatus()
        }
        activity.setActive(true)
        do { try await startSource(at: .zero) }
        catch { try? await interrupt(reason: .cameraError); throw error }
    }
    private func startSource(at time: CMTime) async throws {
        try await source.start(at: time, onSample: { [weak self] sample in
            guard let self else { throw CaptureError.invalidState }
            try self.queue.sync {
                guard self.phase == .recording else { return }
                try self.writer?.append(sample)
                if sample.mediaType == .video {
                    self.latestVideoTime = captureVideoEnd(sample.buffer, frameRate: self.format!.frameRate)
                    self.emitStatus()
                }
            }
        }, onFailure: { [weak self] error in
            let reason: SessionGapReason = (error as? CaptureSourceFailure) == .interrupted ? .interruption : .cameraError
            Task { try? await self?.interrupt(reason: reason) }
        })
    }
    public func pause() async throws { try await interrupt(reason: .userPaused) }
    public func interrupt(reason: SessionGapReason) async throws {
        let closing = try queue.sync { () throws -> (CaptureSegmentWriter, SessionSegment) in
            guard phase == .recording, let writer, let segment else { throw CaptureError.invalidState }
            phase = .pausing
            pendingGap = (Int(latestVideoTime.convertScale(1000, method: .roundHalfAwayFromZero).value), reason)
            self.writer = nil; self.segment = nil; emitStatus()
            return (writer, segment)
        }
        await source.stop()
        do { try await closeSegment(closing.0, segment: closing.1) }
        catch { queue.sync { phase = .paused; emitStatus() }; throw error }
        queue.sync { phase = .paused; emitStatus() }
    }
    public func resume() async throws {
        let time = try queue.sync { () throws -> CMTime in
            guard phase == .paused, let journal, let gap = pendingGap else { throw CaptureError.invalidState }
            let now = CMTimeSubtract(clock.now(), clockOrigin)
            let end = max(gap.startMs, Int(now.convertScale(1000, method: .roundHalfAwayFromZero).value))
            try journal.appendGap(SessionGap(startMs: gap.startMs, endMs: end, reason: gap.reason))
            let time = CMTime(value: Int64(end), timescale: 1000)
            try openSegment(at: time); pendingGap = nil; latestVideoTime = time; phase = .recording; emitStatus()
            return time
        }
        do { try await startSource(at: time) }
        catch { try? await interrupt(reason: .cameraError); throw error }
    }
    @discardableResult public func stop() async throws -> SessionRecording {
        let closing = try queue.sync { () throws -> (CaptureSegmentWriter?, SessionSegment?) in
            guard phase == .recording || phase == .paused else { throw CaptureError.invalidState }
            phase = .stopping
            let result = (writer, segment); writer = nil; segment = nil; return result
        }
        await source.stop()
        do {
            if let writer = closing.0, let segment = closing.1 { try await closeSegment(writer, segment: segment) }
            let record = try queue.sync { () throws -> SessionRecording in
                guard let journal else { throw CaptureError.invalidState }
                if let gap = pendingGap {
                    let now = Int(CMTimeSubtract(clock.now(), clockOrigin).convertScale(1000, method: .roundHalfAwayFromZero).value)
                    try journal.appendGap(SessionGap(startMs: gap.startMs, endMs: max(gap.startMs, now), reason: gap.reason))
                    pendingGap = nil
                }
                try journal.finish(); phase = .stopped; emitStatus()
                return journal.snapshot().recording
            }
            activity.setActive(false)
            let handoff = queue.sync { (sessionID!, journal!.snapshot().marks ?? []) }
            try await sink.saveRecording(sessionID: handoff.0, recording: record, marks: handoff.1)
            return record
        } catch { queue.sync { phase = .stopped; emitStatus() }; activity.setActive(false); throw error }
    }
    @discardableResult public func refreshBudget() async throws -> SessionRecording? {
        let reading = try await budget.snapshot()
        let reaction = try queue.sync { () throws -> (stop: Bool, downgrade: Bool) in
            let previous = lastBudget
            lastBudget = reading
            guard phase == .recording || phase == .paused, let journal else { emitStatus(); return (false, false) }
            let tMs = Int(latestVideoTime.convertScale(1000, method: .roundHalfAwayFromZero).value)
            if previous?.thermalState != reading.thermalState {
                try journal.appendEvent(SessionCaptureEvent(tMs: tMs, kind: .thermalState, thermalState: reading.thermalState))
                if reading.thermalState == .serious { try journal.appendEvent(SessionCaptureEvent(tMs: tMs, kind: .courtModeOn)) }
                else if reading.thermalState == .nominal, previous?.thermalState == .serious || previous?.thermalState == .critical {
                    try journal.appendEvent(SessionCaptureEvent(tMs: tMs, kind: .courtModeOff))
                }
            }
            let lowSpace = reading.freeBytes < 32 * 1024 * 1024
            let lowBattery = reading.batteryFraction.map { $0 <= 0.02 } ?? false
            if lowSpace { try journal.appendEvent(SessionCaptureEvent(tMs: tMs, kind: .lowStorageStop)) }
            if lowBattery { try journal.appendEvent(SessionCaptureEvent(tMs: tMs, kind: .lowBatteryStop)) }
            emitStatus()
            let downgrade = reading.thermalState == .critical && phase == .recording &&
                (format.map { $0.frameRate.num > 30 * $0.frameRate.den } ?? false)
            return (reading.thermalState == .shutdown || lowSpace || lowBattery, downgrade)
        }
        if reaction.stop { return try await stop() }
        if reaction.downgrade {
            try await interrupt(reason: .thermal)
            var reduced = queue.sync { preset! }; reduced.frameRate = RecordedFrameRate(num: 30, den: 1)
            let newFormat = try await source.prepare(preset: reduced, microphone: queue.sync { microphone })
            try queue.sync {
                preset = reduced; format = newFormat
                try journal?.appendEvent(SessionCaptureEvent(tMs: Int(latestVideoTime.convertScale(1000, method: .roundHalfAwayFromZero).value),
                                                           kind: .frameRateChange, frameRate: newFormat.frameRate))
            }
            try await resume()
        }
        return nil
    }
    public func markPoint(note: String? = nil) throws -> MediaTime {
        try queue.sync {
            guard phase == .recording else { throw CaptureError.invalidState }
            let time = try MediaTime(value: latestVideoTime.value, timescale: latestVideoTime.timescale)
            try journal?.appendMark(SessionMark(id: UUID().uuidString.lowercased(),
                tMs: Int(latestVideoTime.convertScale(1000, method: .roundHalfAwayFromZero).value), kind: .point, note: note,
                provenance: RecordProvenance(status: .manual, source: "user", sample: source.mode == .simulatorFixture)))
            return time
        }
    }
    private func openSegment(at time: CMTime) throws {
        guard let journal, let preset, let format, let folder = sessionFolder else { throw CaptureError.invalidState }
        let index = journal.snapshot().segments.count
        let segment = SessionSegment(id: "segment-\(index)", index: index,
            file: RecordFileReference(path: "originals/segment-\(index).mp4", mimeType: "video/mp4"),
            startMs: Int(time.convertScale(1000, method: .roundHalfAwayFromZero).value), durationMs: 0,
            frameRate: format.frameRate, width: format.width, height: format.height, codec: .h264,
            hasAudio: format.hasAudio, finalized: false)
        let destination = folder.appendingPathComponent(segment.file.path)
        let rootPath = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard destination.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(rootPath) else { throw CaptureError.storageUnavailable }
        try journal.beginSegment(segment) // WAL intent precedes file creation.
        writer = try CaptureSegmentWriter(url: folder.appendingPathComponent(segment.file.path), segment: segment,
                                          preset: preset, format: format, sessionStart: time, journal: journal)
        self.segment = segment
    }
    private func closeSegment(_ writer: CaptureSegmentWriter, segment: SessionSegment) async throws {
        try await writer.finish()
        guard let folder = queue.sync(execute: { sessionFolder }), let journal = queue.sync(execute: { journal }) else { throw CaptureError.invalidState }
        let url = folder.appendingPathComponent(segment.file.path)
        let decoded = try await decodeCaptureToEnd(url)
        let handle = try FileHandle(forReadingFrom: url)
        try handle.synchronize(); try handle.close()
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let confirmed = CMTimeAdd(CMTime(value: Int64(segment.startMs), timescale: 1000), decoded.duration)
        try journal.confirmDurableMedia(segmentID: segment.id, segmentDurationMs: Int(decoded.duration.convertScale(1000, method: .roundHalfAwayFromZero).value),
            sessionTime: MediaTime(value: confirmed.value, timescale: confirmed.timescale), bytes: bytes)
        try journal.finalizeSegment(id: segment.id)
    }
    private func makeStatus() -> CaptureStatus {
        CaptureStatus(phase: phase, recordingTime: try? MediaTime(value: latestVideoTime.value, timescale: latestVideoTime.timescale),
                      savedThrough: journal?.snapshot().lastConfirmedMediaTime, sourceLabel: source.label, budget: lastBudget,
                      helpersMayRun: lastBudget?.thermalState == .nominal,
                      previewMode: (lastBudget?.thermalState == .serious || lastBudget?.thermalState == .critical || lastBudget?.thermalState == .shutdown) ? .courtMode : lastBudget?.thermalState == .fair ? .dimmed : .normal)
    }
    private func emitStatus() { let status = makeStatus(); for continuation in continuations.values { continuation.yield(status) } }
}
