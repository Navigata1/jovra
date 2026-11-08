@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import JovraCore

public enum RallyCompositionError: Error, Equatable, Sendable {
    /// The plan has no ranges (no points or marks, or every clip deselected).
    case nothingToPlay
    /// A source file is missing or is not a local file.
    case invalidSource
    /// A source has no video track.
    case noVideo
}

/// One segment of the session's recording and where it starts on the session clock (`recording.segments[].startMs`).
public struct RallySource: Sendable, Equatable {
    public let url: URL
    public let sessionStartMs: Int

    public init(url: URL, sessionStartMs: Int) {
        self.url = url
        self.sessionStartMs = sessionStartMs
    }
}

/// Rally-only playback (screens.md N7, ios-v1-spec PlaybackController): an `AVMutableComposition` that inserts each of
/// a `RallyOnlyPlan`'s ranges, in order, from the original's segments. Nothing is re-encoded and the original is never
/// touched. A range that crosses a recording gap plays only the media on each side of it, so the composition's length
/// is the sum of the plan's ranges less any recording gaps inside them.
public struct RallyComposition: @unchecked Sendable {
    /// One inserted stretch: session time and where it sits on the composition's timeline.
    public struct Piece: Equatable, Sendable {
        public let sessionRange: MediaRange
        public let compositionStart: CMTime
        public let duration: CMTime
    }

    public let composition: AVMutableComposition
    public let pieces: [Piece]

    /// The session time on screen at `time`, for the readout that always shows the full video's time. Nil past the end.
    public func sessionTimeMs(atCompositionTime time: CMTime) -> Int? {
        guard let piece = pieces.last(where: { CMTimeCompare($0.compositionStart, time) <= 0 }),
              CMTimeCompare(time, CMTimeAdd(piece.compositionStart, piece.duration)) < 0 else { return nil }
        let offset = CMTimeConvertScale(CMTimeSubtract(time, piece.compositionStart), timescale: 1_000, method: .roundTowardZero)
        return piece.sessionRange.fromMs + Int(offset.value)
    }

    public static func build(plan: RallyOnlyPlan, sources: [RallySource]) async throws -> RallyComposition {
        guard !plan.ranges.isEmpty else { throw RallyCompositionError.nothingToPlay }
        let loaded = try await sources.sorted { $0.sessionStartMs < $1.sessionStartMs }.asyncMap(LoadedSource.init)
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RallyCompositionError.noVideo
        }
        video.preferredTransform = loaded.first?.transform ?? .identity
        let audio = loaded.contains { $0.audio != nil }
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil

        var pieces: [Piece] = []
        var cursor = CMTime.zero
        for planned in plan.ranges {
            let wanted = CMTimeRange(start: milliseconds(planned.range.fromMs), end: milliseconds(planned.range.toMs))
            for source in loaded {
                let covered = CMTimeRangeGetIntersection(wanted, otherRange: source.sessionCoverage)
                guard covered.duration > .zero else { continue }
                let offset = CMTimeSubtract(covered.start, source.sessionCoverage.start)
                let sourceRange = CMTimeRange(start: CMTimeAdd(source.videoRange.start, offset), duration: covered.duration)
                try video.insertTimeRange(sourceRange, of: source.video, at: cursor)
                if let audio, let sourceAudio = source.audio {
                    let audioRange = CMTimeRangeGetIntersection(sourceRange, otherRange: source.audioRange)
                    if audioRange.duration > .zero {
                        try audio.insertTimeRange(audioRange, of: sourceAudio,
                                                  at: CMTimeAdd(cursor, CMTimeSubtract(audioRange.start, sourceRange.start)))
                    }
                }
                let from = Int(CMTimeConvertScale(covered.start, timescale: 1_000, method: .roundTowardZero).value)
                let to = Int(CMTimeConvertScale(covered.end, timescale: 1_000, method: .roundTowardZero).value)
                pieces.append(Piece(sessionRange: MediaRange(fromMs: from, toMs: to), compositionStart: cursor, duration: covered.duration))
                cursor = CMTimeAdd(cursor, covered.duration)
            }
        }
        guard !pieces.isEmpty else { throw RallyCompositionError.nothingToPlay }
        return RallyComposition(composition: composition, pieces: pieces)
    }

    private static func milliseconds(_ value: Int) -> CMTime { CMTime(value: Int64(value), timescale: 1_000) }

    private struct LoadedSource: @unchecked Sendable {
        /// Held for as long as the composition is built: a track does not keep its asset alive.
        let asset: AVURLAsset
        let video: AVAssetTrack
        let videoRange: CMTimeRange
        let audio: AVAssetTrack?
        let audioRange: CMTimeRange
        let transform: CGAffineTransform
        /// Where the segment's video sits on the session clock.
        let sessionCoverage: CMTimeRange

        init(_ source: RallySource) async throws {
            guard source.url.isFileURL, FileManager.default.fileExists(atPath: source.url.path) else {
                throw RallyCompositionError.invalidSource
            }
            let asset = AVURLAsset(url: source.url)
            guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw RallyCompositionError.noVideo }
            let (range, transform) = try await video.load(.timeRange, .preferredTransform)
            self.asset = asset
            self.video = video
            self.videoRange = range
            self.transform = transform
            if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                self.audio = audio
                self.audioRange = try await audio.load(.timeRange)
            } else {
                self.audio = nil
                self.audioRange = .zero
            }
            sessionCoverage = CMTimeRange(start: CMTime(value: Int64(source.sessionStartMs), timescale: 1_000), duration: range.duration)
        }
    }
}

private extension Array where Element: Sendable {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        out.reserveCapacity(count)
        for element in self { out.append(try await transform(element)) }
        return out
    }
}
