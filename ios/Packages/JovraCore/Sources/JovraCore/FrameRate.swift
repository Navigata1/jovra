import Foundation

/// A video frame rate held as an exact rational (`frames` per `perSeconds` seconds), so
/// broadcast rates such as 29.97 fps (30000/1001) stay frame-accurate over long recordings.
public struct FrameRate: Hashable, Sendable {
    public let frames: Int
    public let perSeconds: Int

    /// - Precondition: both values are positive.
    public init(frames: Int, perSeconds: Int = 1) {
        precondition(frames > 0 && perSeconds > 0, "FrameRate needs positive frames and seconds")
        self.frames = frames
        self.perSeconds = perSeconds
    }

    public static let fps30 = FrameRate(frames: 30)
    public static let fps60 = FrameRate(frames: 60)
    public static let fps120 = FrameRate(frames: 120)
    public static let fps240 = FrameRate(frames: 240)

    public var framesPerSecond: Double { Double(frames) / Double(perSeconds) }

    /// Presentation time, in seconds, at which `frame` starts.
    public func seconds(atFrame frame: Int) -> Double {
        Double(frame) * Double(perSeconds) / Double(frames)
    }

    /// The frame on screen at `seconds`. A time within a nanosecond of a frame boundary counts as
    /// that boundary, which absorbs floating-point error when converting back and forth.
    public func frame(atSeconds seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let exact = seconds * Double(frames) / Double(perSeconds)
        let tolerance = 1e-9 * Double(frames) / Double(perSeconds)
        return Int((exact + tolerance).rounded(.down))
    }
}
