import AVFoundation
import Foundation
import JovraCore

public struct RecoveredSession: Codable, Equatable, Sendable {
    public let sessionID: String
    public let recording: SessionRecording
    public let marks: [SessionMark]
    public let original: SessionOriginalState
}
public struct RecoveryRefusal: Equatable, Sendable {
    public let sessionID: String
    public let reason: String
}
/// The bytes a torn segment lost: its file before truncation, and the decode-verified prefix that was kept.
struct RecoveryTruncation: Codable, Equatable, Sendable {
    let segmentID: String
    let path: String
    let tornBytes: Int
    let tornSHA256: String
    let keptBytes: Int
}
private struct RecoveryReceipt: Codable {
    let formatVersion: Int
    let inputs: [String: RecoveryFingerprint]
    let result: RecoveredSession
    var truncations: [RecoveryTruncation]?
}

/// Words the player reads (schema maxLength 300). Fixed text keeps a repeated scan byte-identical.
enum UnrecoverableReason {
    static let missing = "The segment file was never saved to this iPhone."
    static let noFragment = "No complete part of this segment was saved before recording stopped."
    static let undecodable = "This segment could not be played to the end, so it was kept but not used."
}

/// One journal segment after verification.
private enum SegmentVerdict {
    case kept(SessionSegment, RecoveryFingerprint, MediaFileIdentity, PendingTruncation?)
    case unrecoverable(String)
}
private struct PendingTruncation {
    let clonePath: String
    let source: MediaFileIdentity
    let record: RecoveryTruncation
    let kept: RecoveryFingerprint
}

/// Launch-time reconciliation of capture journals with the files on disk (ADR-0010). Every kept segment is
/// decoded to its end. A segment the process was still writing when it died is truncated to its last complete
/// fragment (never discarded), and the unsaved stretch after it is a gap. A segment that cannot be played is
/// named with its reason while every playable segment is kept. Journals are never changed; the only change to
/// an original is dropping a torn tail after the kept prefix decoded, recorded in `capture-recovery.json`.
/// Adoption into the session is a separate atomic SessionStore operation. Scanning twice changes nothing.
public actor RecoveryScanner {
    private let root: URL
    private var witnesses: [String: MediaAdoptionWitness] = [:]
    public private(set) var refusals: [RecoveryRefusal] = []
    public init(root: URL) { self.root = root.standardizedFileURL }

    public func adoptionWitness(for id: String) -> MediaAdoptionWitness? { witnesses[id] }

    public func scan(eligible: @Sendable (String) async throws -> Bool = { _ in true }) async throws -> [RecoveredSession] {
        refusals = []
        witnesses = [:]
        try RecoveryFiles.refuseLink(root)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try RecoveryFiles.refuseLink(sessions)
        guard FileManager.default.fileExists(atPath: sessions.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var results: [RecoveredSession] = []
        for folder in folders {
            let journal = folder.appendingPathComponent("capture-journal.json")
            do {
                try RecoveryFiles.refuseLink(folder); try RecoveryFiles.refuseLink(journal)
                guard FileManager.default.fileExists(atPath: journal.path),
                      try await eligible(folder.lastPathComponent) else { continue }
                results.append(try await recover(folder))
            } catch {
                refusals.append(.init(sessionID: folder.lastPathComponent, reason: String(describing: error)))
            }
        }
        return results
    }

    private func recover(_ folder: URL) async throws -> RecoveredSession {
        let files = RecoveryFiles(folder: folder)
        let identity = try DurableDirectory.identity(of: folder)
        try files.removeAbandonedClones()
        let (journalHash, bytes, journalIdentity) = try files.read("capture-journal.json", retainingUpTo: 16_777_216)
        let snapshot = try ContractCodec.decode(CaptureJournalSnapshot.self, from: bytes)
        guard snapshot.formatVersion == 1, snapshot.sessionID == folder.lastPathComponent,
              snapshot.mode == .camera || snapshot.mode == .simulatorFixture,
              Set(snapshot.segments.map(\.id)).count == snapshot.segments.count,
              Set(snapshot.segments.map { $0.file.path }).count == snapshot.segments.count else { throw RecoveryError.invalidJournal }
        guard !snapshot.segments.isEmpty else { throw RecoveryError.noVideo }
        let previous = try receipt(in: folder, files)
        var hashes = ["capture-journal.json": journalHash], identities = ["capture-journal.json": journalIdentity]
        var kept: [SessionSegment] = [], gaps = snapshot.gaps, pending: [PendingTruncation] = []
        var unrecoverable: [SessionRecoveryReportUnrecoverableItem] = []
        var claimedEnd = 0
        for (index, original) in snapshot.segments.enumerated() {
            let end = original.startMs.addingReportingOverflow(original.durationMs)
            guard original.index == index, original.startMs >= claimedEnd, original.durationMs >= 0, !end.overflow,
                  original.file.path.hasPrefix("originals/") else { throw RecoveryError.invalidJournal }
            claimedEnd = end.partialValue
            switch try await verify(original, files) {
            case let .kept(segment, fingerprint, fileIdentity, truncation):
                kept.append(segment); hashes[segment.file.path] = fingerprint; identities[segment.file.path] = fileIdentity
                if let truncation { pending.append(truncation) }
            case let .unrecoverable(reason):
                unrecoverable.append(.init(path: original.file.path, reason: reason))
                gaps.append(SessionGap(startMs: original.startMs, endMs: claimedEnd, reason: .other))
            }
        }
        guard let last = kept.last else { throw RecoveryError.noVideo }
        let savedThrough = last.startMs + last.durationMs
        gaps.sort { ($0.startMs, $0.endMs) < ($1.startMs, $1.endMs) }
        var previousGapEnd = 0
        for gap in gaps {
            guard gap.startMs >= previousGapEnd, gap.endMs >= gap.startMs,
                  !kept.contains(where: { gap.startMs < $0.startMs + $0.durationMs && gap.endMs > $0.startMs }) else {
                throw RecoveryError.invalidJournal
            }
            previousGapEnd = gap.endMs
        }
        let timelineEnd = max(savedThrough, previousGapEnd)
        if !snapshot.finished {
            // Forced termination: what was captured after the last saved fragment is gone and its length
            // unknowable, so the gap runs only as far as the journal proves the recording went (a mark, an
            // event or the heartbeat), possibly zero. It is still a gap: the recording stopped unexpectedly.
            let evidence = ([snapshot.lastConfirmedMediaTime.map(Self.milliseconds) ?? 0]
                + (snapshot.marks ?? []).map(\.tMs) + snapshot.captureEvents.map(\.tMs)).max() ?? 0
            let interrupted = snapshot.segments.last.map { !$0.finalized } ?? false
            if interrupted || evidence > timelineEnd {
                gaps.append(SessionGap(startMs: timelineEnd, endMs: max(timelineEnd, evidence), reason: .other))
            }
        }
        let duration = max(timelineEnd, gaps.last?.endMs ?? 0)
        for event in snapshot.captureEvents {
            guard event.tMs >= 0, event.tMs <= duration,
                  event.kind != .thermalState || event.thermalState != nil,
                  event.kind != .frameRateChange || event.frameRate != nil,
                  event.frameRate.map({ $0.num > 0 && $0.den > 0 }) ?? true else {
                throw RecoveryError.invalidJournal
            }
        }
        guard (snapshot.marks ?? []).allSatisfy({ $0.tMs >= 0 && $0.tMs <= duration }),
              try files.read("capture-journal.json").0 == journalHash else { throw RecoveryError.invalidJournal }

        // A truncation from an earlier scan stays reported while the kept prefix is the file on disk.
        var truncations = pending.map(\.record)
        for earlier in previous?.truncations ?? [] where !truncations.contains(where: { $0.segmentID == earlier.segmentID }) {
            if hashes[earlier.path]?.bytes == earlier.keptBytes,
               kept.contains(where: { $0.id == earlier.segmentID && $0.file.path == earlier.path }) { truncations.append(earlier) }
        }
        let order = snapshot.segments.map(\.id)
        truncations.sort { (order.firstIndex(of: $0.segmentID) ?? 0) < (order.firstIndex(of: $1.segmentID) ?? 0) }
        let instant = previous.flatMap { $0.formatVersion == 1 && $0.inputs == hashes ? $0.result.recording.recovery?.recoveredAt : nil }
            ?? ISO8601DateFormatter().string(from: Date())
        let report = SessionRecoveryReport(recoveredAt: instant, outcome: unrecoverable.isEmpty ? .complete : .partial,
            savedThroughMs: savedThrough, truncatedSegmentIds: truncations.isEmpty ? nil : truncations.map(\.segmentID),
            unrecoverable: unrecoverable.isEmpty ? nil : unrecoverable)
        let recording = SessionRecording(mode: snapshot.mode, durationMs: duration,
            segments: kept, gaps: gaps, microphone: snapshot.microphone, mediaAvailable: true,
            captureEvents: snapshot.captureEvents, recovery: report)
        let state: SessionOriginalState
        if !unrecoverable.isEmpty {
            let count = snapshot.segments.count
            state = .init(state: .partial, reason: "\(unrecoverable.count) of \(count) \(count == 1 ? "segment" : "segments") could not be recovered. Every playable segment was kept.")
        } else { state = .init(state: gaps.isEmpty ? .saved : .savedWithGaps) }
        let result = RecoveredSession(sessionID: snapshot.sessionID, recording: recording, marks: snapshot.marks ?? [], original: state)
        let receipt = RecoveryReceipt(formatVersion: 1, inputs: hashes, result: result, truncations: truncations.isEmpty ? nil : truncations)
        // The receipt names the kept prefix before the torn file is replaced, so a crash in between is redone.
        if previous?.formatVersion != 1 || previous?.inputs != hashes || previous?.result != result || previous?.truncations != receipt.truncations {
            try files.writeReceipt(try CanonicalJSON.encode(receipt))
        }
        for truncation in pending { identities[truncation.record.path] = try files.commit(truncation.clonePath, over: truncation.record.path, source: truncation.source, kept: truncation.kept) }
        let witness = MediaAdoptionWitness(directory: identity, files: identities)
        try witness.verify(in: folder)
        witnesses[result.sessionID] = witness
        return result
    }

    private func receipt(in folder: URL, _ files: RecoveryFiles) throws -> RecoveryReceipt? {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("capture-recovery.json").path) else { return nil }
        return try ContractCodec.decode(RecoveryReceipt.self, from: files.read("capture-recovery.json", retainingUpTo: 16_777_216).1)
    }

    private func verify(_ original: SessionSegment, _ files: RecoveryFiles) async throws -> SegmentVerdict {
        let path = original.file.path
        let first: (RecoveryFingerprint, Data, MediaFileIdentity)
        do { first = try files.read(path) } catch RecoveryError.filesystem(ENOENT) { return .unrecoverable(UnrecoverableReason.missing) }
        let media = try files.url(path)
        guard !original.finalized else {
            // A closed segment is never altered: it decodes whole and agrees with the journal, or it is reported.
            guard let decoded = try? await decodeCaptureToEnd(media) else { return .unrecoverable(UnrecoverableReason.undecodable) }
            let segment = try await describe(original, media: media, decoded: decoded, fingerprint: first.0)
            guard abs(segment.durationMs - original.durationMs) <= 1 else { throw RecoveryError.invalidJournal }
            return try unchanged(files, path, first, then: .kept(segment, first.0, first.2, nil))
        }
        guard let layout = try? FragmentedMovieLayout.inspect(media) else { return .unrecoverable(UnrecoverableReason.noFragment) }
        guard layout.hasIncompleteTail, let prefix = layout.completeFragmentEnds.last else {
            guard let decoded = try? await decodeCaptureToEnd(media) else { return .unrecoverable(UnrecoverableReason.undecodable) }
            var segment = try await describe(original, media: media, decoded: decoded, fingerprint: first.0)
            segment.finalized = true; segment.recoveredAfterInterruption = true
            return try unchanged(files, path, first, then: .kept(segment, first.0, first.2, nil))
        }
        let clonePath = try files.truncatedClone(of: path, length: prefix)
        do {
            let clone = try files.url(clonePath)
            guard let decoded = try? await decodeCaptureToEnd(clone) else {
                try files.remove(clonePath); return .unrecoverable(UnrecoverableReason.undecodable)
            }
            let kept = try files.read(clonePath).0
            var segment = try await describe(original, media: clone, decoded: decoded, fingerprint: kept)
            segment.finalized = true; segment.recoveredAfterInterruption = true
            let record = RecoveryTruncation(segmentID: original.id, path: path, tornBytes: first.0.bytes,
                                            tornSHA256: first.0.sha256, keptBytes: kept.bytes)
            return try unchanged(files, path, first, then: .kept(segment, kept, first.2,
                PendingTruncation(clonePath: clonePath, source: first.2, record: record, kept: kept)))
        } catch { try? files.remove(clonePath); throw error }
    }

    /// The source must not have changed while it was decoded.
    private func unchanged(_ files: RecoveryFiles, _ path: String, _ first: (RecoveryFingerprint, Data, MediaFileIdentity),
                           then verdict: SegmentVerdict) throws -> SegmentVerdict {
        let again = try files.read(path)
        guard again.0 == first.0, again.2 == first.2 else { throw RecoveryError.changedFile }
        return verdict
    }

    /// The segment as decoded: duration from the last decoded frame, format from the probe.
    private func describe(_ original: SessionSegment, media: URL, decoded: DecodedCapture,
                          fingerprint: RecoveryFingerprint) async throws -> SessionSegment {
        let milliseconds = decoded.duration.convertScale(1000, method: .roundHalfAwayFromZero).value
        guard milliseconds > 0, milliseconds <= Int64(Int.max - original.startMs) else { throw RecoveryError.invalidJournal }
        let info = try await MediaProbe.probe(media)
        guard let video = info.video, video.isDecodable,
              video.codedWidth == original.width, video.codedHeight == original.height,
              let rate = video.frameRate else { throw RecoveryError.invalidJournal }
        var segment = original
        segment.durationMs = Int(milliseconds); segment.file.bytes = fingerprint.bytes
        segment.file.sha256 = fingerprint.sha256; segment.file.md5 = nil
        segment.hasAudio = info.audio != nil
        segment.frameRate = .init(num: rate.frames, den: rate.perSeconds)
        switch video.codec { case .h264: segment.codec = .h264; case .hevc: segment.codec = .hevc; case .other: segment.codec = .other }
        return segment
    }

    private static func milliseconds(_ time: MediaTime) -> Int {
        Int(CMTime(value: time.value, timescale: time.timescale).convertScale(1000, method: .roundHalfAwayFromZero).value)
    }
}
