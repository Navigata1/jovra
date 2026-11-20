import Foundation
import JovraCore

/// Why a selected file cannot become a session. Every case names the specific thing to convert, so the
/// player is never told only "unsupported" (story 107).
public enum ImportUnsupportedReason: Equatable, Sendable {
    /// The container is not MOV or MP4; carries the file extension as selected (may be empty).
    case container(String)
    /// The file has no video track.
    case noVideoTrack
    /// The video codec is not H.264 or HEVC; carries the codec's display name (for example `FFV1`).
    case codec(String)
    /// H.264 or HEVC this device cannot decode (for example a profile beyond the hardware).
    case notDecodable(String)
    /// The nominal frame rate is outside 24–240 fps, or the file states none.
    case frameRate(FrameRate?)
    /// Larger than 4096 on the long side or smaller than 240 on the short side.
    case resolution(width: Int, height: Int)
}

/// The acceptance rules for imported originals. Pure, so tests and the UI share one definition.
public enum ImportValidation {
    public static let containers: Set<String> = ["mov", "mp4"]
    public static let frameRates: ClosedRange<Double> = 23.5...240.5
    public static let maximumLongSide = 4096
    public static let minimumShortSide = 240

    public static func container(of url: URL) -> ImportUnsupportedReason? {
        let ext = url.pathExtension.lowercased()
        return containers.contains(ext) ? nil : .container(ext)
    }

    /// Nil when the probed video is acceptable. Order matters: the codec explains more than decodability.
    public static func reason(for info: MediaInfo) -> ImportUnsupportedReason? {
        guard let video = info.video else { return .noVideoTrack }
        if case .other(let fourCC) = video.codec { return .codec(codecDisplayName(fourCC)) }
        guard video.isDecodable else { return .notDecodable(codecDisplayName(video.fourCC)) }
        guard let rate = video.frameRate, rate.perSeconds > 0,
              frameRates.contains(Double(rate.frames) / Double(rate.perSeconds)) else { return .frameRate(video.frameRate) }
        let long = max(video.codedWidth, video.codedHeight), short = min(video.codedWidth, video.codedHeight)
        guard long <= maximumLongSide, short >= minimumShortSide else {
            return .resolution(width: video.displayWidth, height: video.displayHeight)
        }
        return nil
    }

    /// A readable name for a sample-description four-character code.
    public static func codecDisplayName(_ fourCC: String) -> String {
        switch fourCC.trimmingCharacters(in: .whitespaces) {
        case "avc1", "avc3": "H.264"
        case "hvc1", "hev1": "HEVC"
        case "ap4h", "ap4x", "apch", "apcn", "apcs", "apco": "Apple ProRes"
        case "vp08": "VP8"
        case "vp09": "VP9"
        case "av01": "AV1"
        case "mp4v": "MPEG-4 Part 2"
        case "mjpa", "mjpb", "jpeg": "Motion JPEG"
        case "": "an unknown codec"
        default: fourCC.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }
}
