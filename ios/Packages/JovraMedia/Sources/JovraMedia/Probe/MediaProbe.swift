import AVFoundation
import CoreMedia
import Foundation
import JovraCore

/// What import and the media library need to know about a file before touching it.
public struct MediaInfo: Sendable, Equatable {
    public struct Video: Sendable, Equatable {
        public let codec: VideoCodec
        /// The sample-description four-character code, e.g. `avc1`, `hvc1`, `FFV1`.
        public let fourCC: String
        public let codedWidth: Int
        public let codedHeight: Int
        /// Clockwise rotation the track matrix applies for display (0, 90, 180 or 270).
        public let rotationDegrees: Int
        public let displayWidth: Int
        public let displayHeight: Int
        public let orientation: VideoOrientation
        /// Nominal rate: the median frame duration's rate, snapped to a standard camera rate when within a tick
        /// (see `FrameTiming`). Never 1 / the shortest frame. Nil when the file does not state one.
        public let frameRate: FrameRate?
        /// True when frame durations wander from the median by more than a timescale tick (phone originals
        /// are often VFR). `frameRate` is then the nominal rate, not every frame's.
        public let isVariableFrameRate: Bool
        public let isHDR: Bool
        public let bitDepth: Int
        /// False when this device cannot decode the track (import must refuse it with a reason).
        public let isDecodable: Bool
    }

    public struct Audio: Sendable, Equatable {
        public let fourCC: String
        public let sampleRate: Int
        public let channels: Int
    }

    public let duration: CMTime
    public let video: Video?
    public let audio: Audio?
}

public enum VideoCodec: Sendable, Equatable {
    case h264
    case hevc
    case other(fourCC: String)

    init(fourCC: String) {
        switch fourCC {
        case "avc1", "avc3": self = .h264
        case "hvc1", "hev1": self = .hevc
        default: self = .other(fourCC: fourCC)
        }
    }

    /// Lower-case codec name as the shared contracts spell it (`h264`, `hevc`, else the four-cc lower-cased).
    public var name: String {
        switch self {
        case .h264: "h264"
        case .hevc: "hevc"
        case .other(let fourCC): fourCC.lowercased()
        }
    }
}

public enum VideoOrientation: String, Sendable, Equatable {
    case landscape
    case portrait
    case square
}

public enum MediaProbe {
    public static func probe(_ url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        var videoInfo: MediaInfo.Video?
        if let video { videoInfo = try await probeVideo(video) }
        var audioInfo: MediaInfo.Audio?
        if let audio { audioInfo = try await probeAudio(audio) }
        return MediaInfo(duration: duration, video: videoInfo, audio: audioInfo)
    }

    private static func probeVideo(_ track: AVAssetTrack) async throws -> MediaInfo.Video {
        let (size, transform, minFrameDuration, nominalRate, decodable, formats, characteristics, timeRange) = try await track.load(
            .naturalSize, .preferredTransform, .minFrameDuration, .nominalFrameRate, .isDecodable,
            .formatDescriptions, .mediaCharacteristics, .timeRange
        )
        let format = formats.first
        let fourCC = format.map { fourCharacterCode(CMFormatDescriptionGetMediaSubType($0)) } ?? "????"
        let extensions = format.flatMap { CMFormatDescriptionGetExtensions($0) as? [String: Any] } ?? [:]
        let bitDepth = (extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? Int) ?? 8
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let rotation = rotationDegrees(of: transform)
        let (displayWidth, displayHeight) = rotation % 180 == 0 ? (width, height) : (height, width)
        let orientation: VideoOrientation = displayHeight > displayWidth ? .portrait
            : displayWidth > displayHeight ? .landscape : .square
        let timing = try await sampleTiming(of: track, timescale: timeRange.duration.timescale)
            ?? FrameTiming(nominal: nominalRate, minFrameDuration: minFrameDuration)
        return MediaInfo.Video(
            codec: VideoCodec(fourCC: fourCC), fourCC: fourCC, codedWidth: width, codedHeight: height,
            rotationDegrees: rotation, displayWidth: displayWidth, displayHeight: displayHeight,
            orientation: orientation, frameRate: timing?.frameRate, isVariableFrameRate: timing?.isVariableFrameRate ?? false,
            isHDR: characteristics.contains(.containsHDRVideo), bitDepth: bitDepth, isDecodable: decodable
        )
    }

    private static func probeAudio(_ track: AVAssetTrack) async throws -> MediaInfo.Audio {
        let formats = try await track.load(.formatDescriptions)
        let format = formats.first
        let description = format.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        return MediaInfo.Audio(
            fourCC: format.map { fourCharacterCode(CMFormatDescriptionGetMediaSubType($0)) } ?? "????",
            sampleRate: Int(description?.mSampleRate ?? 0),
            channels: Int(description?.mChannelsPerFrame ?? 0)
        )
    }

    /// The clockwise display rotation of a track matrix, snapped to a right angle.
    static func rotationDegrees(of transform: CGAffineTransform) -> Int {
        let degrees = atan2(transform.b, transform.a) * 180 / .pi
        let snapped = Int((degrees / 90).rounded()) * 90
        return (snapped % 360 + 360) % 360
    }

    /// Reads every sample's presentation time from the track's sample table (no decoding) and derives the
    /// timing from them. Nil when the track cannot provide sample cursors.
    static func sampleTiming(of track: AVAssetTrack, timescale: CMTimeScale) async throws -> FrameTiming? {
        guard try await track.load(.canProvideSampleCursors),
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else { return nil }
        let scale = cursor.presentationTimeStamp.timescale > 0 ? cursor.presentationTimeStamp.timescale : timescale
        var times: [Int64] = []
        repeat {
            let pts = cursor.presentationTimeStamp
            guard pts.isNumeric else { return nil }
            times.append(pts.convertScale(scale, method: .default).value)
        } while cursor.stepInDecodeOrder(byCount: 1) == 1
        return FrameTiming(presentationTimes: times, timescale: Int64(scale))
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// A video track's frame rate, read from its frames' presentation timestamps.
///
/// The shortest frame never sets the rate: an Android 13 original with one 749/30000 s frame would read as
/// 40 fps. Instead:
/// 1. The median frame duration `m` (lower median, exact ticks) is the typical frame.
/// 2. The regular frames are those within one tick of `m`; their mean duration absorbs timescale rounding
///    (29.97 fps at timescale 600 is 20 ticks with every 50th at 21; Android at 90000 is mostly 2999 and 3000).
/// 3. When that mean is within one tick and 0.2% of a standard rate's frame duration (23.976 to 240 fps, NTSC
///    included), the rate is that standard rate, else exactly `timescale / m`.
/// A clip is variable-frame-rate when any frame duration differs from `m` by more than one tick (dropped
/// frames, the odd short or long frame); `frameRate` is then the nominal rate.
public struct FrameTiming: Sendable, Equatable {
    public let frameRate: FrameRate
    public let isVariableFrameRate: Bool

    /// Rates a camera writes, as (frames, perSeconds).
    static let standardRates: [(Int64, Int64)] = [
        (24000, 1001), (24, 1), (25, 1), (30000, 1001), (30, 1), (48, 1), (50, 1), (60000, 1001), (60, 1),
        (100, 1), (120000, 1001), (120, 1), (240, 1),
    ]

    public init(frameRate: FrameRate, isVariableFrameRate: Bool) {
        self.frameRate = frameRate
        self.isVariableFrameRate = isVariableFrameRate
    }

    /// `presentationTimes` in any order (decode order is fine), all in `timescale` ticks per second. Nil with
    /// fewer than two distinct times or a non-positive timescale.
    public init?(presentationTimes: [Int64], timescale: Int64) {
        guard timescale > 0 else { return nil }
        let sorted = presentationTimes.sorted()
        let durations = zip(sorted.dropFirst(), sorted).map { $0 - $1 }.filter { $0 > 0 }
        guard !durations.isEmpty else { return nil }
        let median = durations.sorted()[(durations.count - 1) / 2]
        let regular = durations.filter { abs($0 - median) <= 1 }
        let mean = Double(regular.reduce(0, +)) / Double(regular.count)
        let standard = Self.standardRates
            .map { rate in (rate, Double(timescale) * Double(rate.1) / Double(rate.0)) }
            .filter { abs($0.1 - mean) <= 1 && abs($0.1 - mean) <= 0.002 * $0.1 }
            .min { abs($0.1 - mean) < abs($1.1 - mean) }
        if let (rate, _) = standard {
            frameRate = FrameRate(frames: Int(rate.0), perSeconds: Int(rate.1))
        } else {
            var (a, b) = (median, timescale)
            while b != 0 { (a, b) = (b, a % b) }
            frameRate = FrameRate(frames: Int(timescale / a), perSeconds: Int(median / a))
        }
        isVariableFrameRate = durations.count != regular.count
    }

    /// Fallback when sample timestamps are unavailable: the nominal rate snapped to a whole or NTSC
    /// (n x 1000/1001) rate, variable when the shortest frame is more than 1% faster than that rate.
    public init?(nominal: Float, minFrameDuration: CMTime) {
        guard nominal.isFinite, nominal.rounded() >= 1 else { return nil }
        let ntsc = (nominal * 1.001).rounded()
        if abs(Double(nominal) - Double(ntsc) * 1000 / 1001) < 0.005, abs(nominal - nominal.rounded()) > 0.005 {
            frameRate = FrameRate(frames: Int(ntsc) * 1000, perSeconds: 1001)
        } else {
            frameRate = FrameRate(frames: Int(nominal.rounded()))
        }
        if minFrameDuration.isNumeric, minFrameDuration.seconds > 0 {
            isVariableFrameRate = 1 / minFrameDuration.seconds > frameRate.framesPerSecond * 1.01
        } else {
            isVariableFrameRate = false
        }
    }
}
