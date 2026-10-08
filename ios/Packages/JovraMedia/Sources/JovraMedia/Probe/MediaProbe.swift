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
        /// Exact rate from the shortest frame duration; nil when the file does not state one.
        public let frameRate: FrameRate?
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
        let (size, transform, minFrameDuration, nominalRate, decodable, formats, characteristics) = try await track.load(
            .naturalSize, .preferredTransform, .minFrameDuration, .nominalFrameRate, .isDecodable,
            .formatDescriptions, .mediaCharacteristics
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
        return MediaInfo.Video(
            codec: VideoCodec(fourCC: fourCC), fourCC: fourCC, codedWidth: width, codedHeight: height,
            rotationDegrees: rotation, displayWidth: displayWidth, displayHeight: displayHeight,
            orientation: orientation, frameRate: frameRate(minFrameDuration: minFrameDuration, nominal: nominalRate),
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

    /// 1 / minFrameDuration as an exact rational (512/15360 s -> 30 fps, 1001/30000 s -> 30000/1001 fps).
    static func frameRate(minFrameDuration: CMTime, nominal: Float) -> FrameRate? {
        if minFrameDuration.isNumeric, minFrameDuration.value > 0, minFrameDuration.timescale > 0 {
            let value = Int(minFrameDuration.value), timescale = Int(minFrameDuration.timescale)
            var (a, b) = (value, timescale)
            while b != 0 { (a, b) = (b, a % b) }
            return FrameRate(frames: timescale / a, perSeconds: value / a)
        }
        guard nominal > 0 else { return nil }
        return FrameRate(frames: Int(nominal.rounded()))
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
