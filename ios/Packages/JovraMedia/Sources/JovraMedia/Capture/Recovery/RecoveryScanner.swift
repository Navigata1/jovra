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
private struct RecoveryReceipt: Codable {
    let formatVersion: Int
    let inputs: [String: RecoveryFingerprint]
    let result: RecoveredSession
}

/// Decode-confirmed handoff candidates. Scanning never changes raw journals or originals;
/// adoption is a separate atomic SessionStore operation. Torn-prefix recovery is a later slice.
public actor RecoveryScanner {
    private let root: URL
    public private(set) var refusals: [RecoveryRefusal] = []
    public init(root: URL) { self.root = root.standardizedFileURL }

    public func scan() async throws -> [RecoveredSession] {
        refusals = []
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
                guard FileManager.default.fileExists(atPath: journal.path) else { continue }
                results.append(try await recover(folder))
            } catch {
                refusals.append(.init(sessionID: folder.lastPathComponent, reason: String(describing: error)))
            }
        }
        return results
    }
    private func recover(_ folder: URL) async throws -> RecoveredSession {
        let files = RecoveryFiles(folder: folder)
        let (journalHash, bytes) = try files.read("capture-journal.json", retainingUpTo: 16_777_216)
        let snapshot = try ContractCodec.decode(CaptureJournalSnapshot.self, from: bytes)
        guard snapshot.formatVersion == 1, snapshot.sessionID == folder.lastPathComponent,
              snapshot.mode == .camera || snapshot.mode == .simulatorFixture,
              Set(snapshot.segments.map(\.id)).count == snapshot.segments.count,
              Set(snapshot.segments.map { $0.file.path }).count == snapshot.segments.count else { throw RecoveryError.invalidJournal }
        guard snapshot.finished, snapshot.segments.allSatisfy(\.finalized) else { throw RecoveryError.unfinishedRecording }
        guard !snapshot.segments.isEmpty else { throw RecoveryError.noVideo }
        var hashes = ["capture-journal.json": journalHash], segments: [SessionSegment] = [], savedThrough = 0
        for (index, original) in snapshot.segments.enumerated() {
            guard original.index == index, original.startMs >= savedThrough, original.durationMs >= 0,
                  original.file.path.hasPrefix("originals/") else { throw RecoveryError.invalidJournal }
            let fingerprint = try files.read(original.file.path).0
            let media = try files.url(original.file.path)
            let decoded = try await decodeCaptureToEnd(media)
            let milliseconds = decoded.duration.convertScale(1000, method: .roundHalfAwayFromZero).value
            guard milliseconds > 0, milliseconds <= Int64(Int.max) else { throw RecoveryError.invalidJournal }
            guard abs(Decimal(milliseconds) - Decimal(original.durationMs)) <= 1 else { throw RecoveryError.invalidJournal }
            let end = original.startMs.addingReportingOverflow(Int(milliseconds))
            guard !end.overflow else { throw RecoveryError.invalidJournal }
            let info = try await MediaProbe.probe(media)
            guard let video = info.video, video.isDecodable,
                  video.codedWidth == original.width, video.codedHeight == original.height,
                  let rate = video.frameRate else { throw RecoveryError.invalidJournal }
            guard try files.read(original.file.path).0 == fingerprint else { throw RecoveryError.changedFile }
            hashes[original.file.path] = fingerprint
            var segment = original
            segment.durationMs = Int(milliseconds); segment.file.bytes = fingerprint.bytes
            segment.file.sha256 = fingerprint.sha256; segment.file.md5 = nil
            segment.hasAudio = info.audio != nil
            segment.frameRate = .init(num: rate.frames, den: rate.perSeconds)
            switch video.codec { case .h264: segment.codec = .h264; case .hevc: segment.codec = .hevc; case .other: segment.codec = .other }
            segments.append(segment); savedThrough = end.partialValue
        }
        var previousGapEnd = 0
        for gap in snapshot.gaps {
            guard gap.startMs >= previousGapEnd, gap.endMs >= gap.startMs,
                  !segments.contains(where: { gap.startMs < $0.startMs + $0.durationMs && gap.endMs > $0.startMs }) else {
                throw RecoveryError.invalidJournal
            }
            previousGapEnd = gap.endMs
        }
        let duration = max(savedThrough, previousGapEnd)
        guard (snapshot.marks ?? []).allSatisfy({ $0.tMs >= 0 && $0.tMs <= duration }),
              try files.read("capture-journal.json").0 == journalHash else { throw RecoveryError.invalidJournal }
        let previous: RecoveryReceipt?
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("capture-recovery.json").path) {
            previous = try ContractCodec.decode(RecoveryReceipt.self, from: files.read("capture-recovery.json", retainingUpTo: 16_777_216).1)
        } else { previous = nil }
        let instant = previous.flatMap { $0.formatVersion == 1 && $0.inputs == hashes ? $0.result.recording.recovery?.recoveredAt : nil }
            ?? ISO8601DateFormatter().string(from: Date())
        let report = SessionRecoveryReport(recoveredAt: instant, outcome: .complete, savedThroughMs: savedThrough)
        let recording = SessionRecording(mode: snapshot.mode, durationMs: duration,
            segments: segments, gaps: snapshot.gaps, microphone: snapshot.microphone, mediaAvailable: true,
            captureEvents: snapshot.captureEvents, recovery: report)
        let result = RecoveredSession(sessionID: snapshot.sessionID, recording: recording, marks: snapshot.marks ?? [],
            original: .init(state: snapshot.gaps.isEmpty ? .saved : .savedWithGaps))
        let receipt = RecoveryReceipt(formatVersion: 1, inputs: hashes, result: result)
        let encoded = try CanonicalJSON.encode(receipt)
        if previous?.formatVersion != 1 || previous?.inputs != hashes || previous?.result != result { try files.writeReceipt(encoded) }
        return result
    }
}
