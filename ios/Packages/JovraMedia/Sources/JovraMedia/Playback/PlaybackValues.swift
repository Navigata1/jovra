import CoreMedia
import JovraCore

/// The four study rates (user story 156).
public enum PlaybackRate: Int, CaseIterable, Sendable, Comparable {
    case quarter, half, normal, double

    public var value: Float {
        switch self {
        case .quarter: 0.25
        case .half: 0.5
        case .normal: 1
        case .double: 2
        }
    }

    /// Slower than real time: needs an item that can play slow forward.
    public var isSlow: Bool { self < .normal }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// An A–B loop over whole frames, both ends inclusive and ordered.
public struct FrameLoop: Equatable, Sendable {
    public let start: Int
    public let end: Int

    /// Nil unless both frames lie inside the clip and are different frames.
    public init?(start: Int, end: Int, frameCount: Int) {
        let low = min(start, end), high = max(start, end)
        guard low >= 0, high < frameCount, low < high else { return nil }
        self.start = low
        self.end = high
    }

    public func contains(_ frame: Int) -> Bool { (start...end).contains(frame) }
}

/// What the frame readout shows: "f 46,000 · 12:46.67 · 60 fps", plus the rate when it is not 1×.
/// The time is the exact start of the frame on the clip's rational clock.
public struct PlaybackReadout: Equatable, Sendable {
    public let frame: Int
    public let frameRate: FrameRate
    public let rate: PlaybackRate

    public init(frame: Int, frameRate: FrameRate, rate: PlaybackRate) {
        self.frame = frame
        self.frameRate = frameRate
        self.rate = rate
    }

    public var time: CMTime { CMTime(frame: frame, at: frameRate) }
    public var seconds: Double { frameRate.seconds(atFrame: frame) }
}

/// One repeat of an A–B loop as it happened: the frame playback stopped on, and the frame it restarted from.
public struct LoopWrap: Equatable, Sendable {
    public let endedAt: Int
    public let restartedAt: Int
}

public enum PlaybackOpenError: Error, Equatable, Sendable {
    /// The file is not on this device.
    case missingFile
    /// The file has no decodable video track.
    case noVideo
    /// Exact frame stepping needs a constant frame rate; variable-rate imports need a presentation index first.
    case variableFrameRate
    case unreadable
}

/// The short-GOP proxy's lifecycle. Playback never waits for it.
public enum ProxyState: Equatable, Sendable {
    case none, building, ready, failed
}
