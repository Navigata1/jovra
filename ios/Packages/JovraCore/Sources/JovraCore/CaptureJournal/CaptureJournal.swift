import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum CaptureJournalError: Error, Equatable, Sendable {
    case alreadyExists, invalidSegment, invalidGap, regressingCheckpoint, unknownSegment, finished
    case filesystem(Int32)
}

public struct CaptureJournalSnapshot: Codable, Equatable, Sendable {
    public var formatVersion: Int = 1
    public var sessionID: String
    public var mode: SessionRecordingMode
    public var microphone: SessionRecordingMicrophone
    public var segments: [SessionSegment] = []
    public var gaps: [SessionGap] = []
    public var captureEvents: [SessionCaptureEvent] = []
    public var marks: [SessionMark]?
    public var lastConfirmedMediaTime: MediaTime?
    public var finished: Bool = false
    public var revision: Int = 0

    public var recording: SessionRecording {
        SessionRecording(mode: mode, durationMs: (segments.isEmpty && gaps.isEmpty) ? nil : max(segments.last.map { $0.startMs + $0.durationMs } ?? 0, gaps.last?.endMs ?? 0),
                         segments: segments, gaps: gaps, microphone: microphone,
                         mediaAvailable: segments.contains { $0.durationMs > 0 }, captureEvents: captureEvents)
    }
}

/// A single synchronous writer. A segment intent is durable before its media file is created. A checkpoint
/// advances only after the segment pipeline has synchronized actual fragment bytes to local storage.
/// Snapshot replacement never suspends, and a failed write leaves the previous in-memory state intact.
public final class CaptureJournal: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var state: CaptureJournalSnapshot
    private let beforeReplace: (@Sendable () throws -> Void)?

    public init(url: URL, sessionID: String, mode: SessionRecordingMode,
                microphone: SessionRecordingMicrophone, beforeReplace: (@Sendable () throws -> Void)? = nil) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CaptureJournalError.alreadyExists }
        self.url = url
        self.state = CaptureJournalSnapshot(sessionID: sessionID, mode: mode, microphone: microphone)
        self.beforeReplace = beforeReplace
        try Self.replace(state, at: url, beforeReplace: beforeReplace)
    }
    private init(url: URL, state: CaptureJournalSnapshot) {
        self.url = url; self.state = state; self.beforeReplace = nil
    }
    public static func open(url: URL) throws -> CaptureJournal {
        let state = try ContractCodec.decode(CaptureJournalSnapshot.self, from: Data(contentsOf: url))
        guard state.formatVersion == 1 else { throw CaptureJournalError.invalidSegment }
        return CaptureJournal(url: url, state: state)
    }
    public func snapshot() -> CaptureJournalSnapshot { lock.withLock { state } }

    public func beginSegment(_ segment: SessionSegment) throws {
        try update { state in
            let parts = segment.file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard segment.index == state.segments.count, !state.segments.contains(where: { $0.id == segment.id }),
                  !segment.finalized, segment.durationMs == 0, segment.startMs >= 0,
                  state.segments.allSatisfy({ $0.finalized }),
                  !state.segments.contains(where: { $0.file.path == segment.file.path }),
                  state.segments.last.map({ Decimal(segment.startMs) >= Decimal($0.startMs) + Decimal($0.durationMs) }) ?? true,
                  state.gaps.last.map({ segment.startMs >= $0.endMs }) ?? true,
                  !segment.file.path.hasPrefix("/"), !parts.contains(".."), !parts.contains("."),
                  !parts.contains(""), segment.width > 0, segment.height > 0,
                  segment.frameRate.num > 0, segment.frameRate.den > 0 else { throw CaptureJournalError.invalidSegment }
            state.segments.append(segment)
        }
    }
    public func confirmDurableMedia(segmentID: String, segmentDurationMs: Int, sessionTime: MediaTime, bytes: Int) throws {
        try update { state in
            guard let index = state.segments.firstIndex(where: { $0.id == segmentID }) else { throw CaptureJournalError.unknownSegment }
            guard !state.segments[index].finalized, segmentDurationMs >= state.segments[index].durationMs,
                  bytes >= (state.segments[index].file.bytes ?? 0), sessionTime.value >= 0, sessionTime.timescale > 0 else {
                throw CaptureJournalError.regressingCheckpoint
            }
            // Compare exact integer products, allowing the contract millisecond rounding only.
            let statedMs = Decimal(state.segments[index].startMs) + Decimal(segmentDurationMs)
            let delta = Decimal(sessionTime.value) * 1000 - statedMs * Decimal(sessionTime.timescale)
            guard abs(delta) <= Decimal(sessionTime.timescale) else { throw CaptureJournalError.regressingCheckpoint }
            if let previous = state.lastConfirmedMediaTime {
                let left = Decimal(sessionTime.value) * Decimal(previous.timescale)
                let right = Decimal(previous.value) * Decimal(sessionTime.timescale)
                guard left >= right else { throw CaptureJournalError.regressingCheckpoint }
            }
            state.segments[index].durationMs = segmentDurationMs
            state.segments[index].file.bytes = bytes
            state.lastConfirmedMediaTime = sessionTime
        }
    }
    public func finalizeSegment(id: String) throws {
        try update { state in
            guard let index = state.segments.firstIndex(where: { $0.id == id }) else { throw CaptureJournalError.unknownSegment }
            state.segments[index].finalized = true
        }
    }
    public func appendGap(_ gap: SessionGap) throws {
        try update { state in
            guard gap.startMs >= 0, gap.endMs >= gap.startMs else { throw CaptureJournalError.invalidGap }
            state.gaps.append(gap)
        }
    }
    public func appendMark(_ mark: SessionMark) throws {
        try update { state in
            guard mark.tMs >= 0 else { throw CaptureJournalError.invalidSegment }
            if state.marks == nil { state.marks = [] }
            state.marks?.append(mark)
        }
    }
    public func appendEvent(_ event: SessionCaptureEvent) throws { try update { $0.captureEvents.append(event) } }
    public func finish() throws { try update { $0.finished = true } }
    private func update(_ mutate: (inout CaptureJournalSnapshot) throws -> Void) throws {
        try lock.withLock {
            guard !state.finished else { throw CaptureJournalError.finished }
            var candidate = state
            try mutate(&candidate)
            candidate.revision += 1
            try Self.replace(candidate, at: url, beforeReplace: beforeReplace)
            state = candidate
        }
    }
    private static func replace(_ snapshot: CaptureJournalSnapshot, at url: URL,
                                beforeReplace: (@Sendable () throws -> Void)?) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".capture-\(UUID().uuidString).tmp")
        let data = try CanonicalJSON.encode(snapshot)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CaptureJournalError.filesystem(errno)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        try beforeReplace?()
        guard rename(temporary.path, url.path) == 0 else { throw CaptureJournalError.filesystem(errno) }
        #if canImport(Darwin)
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        #else
        let descriptor = Glibc.open(directory.path, O_RDONLY)
        #endif
        guard descriptor >= 0 else { throw CaptureJournalError.filesystem(errno) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw CaptureJournalError.filesystem(errno) }
    }
}
