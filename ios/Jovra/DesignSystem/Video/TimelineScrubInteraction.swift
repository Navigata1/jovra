import Foundation

/// Frame mapping and the last coarse target of the currently accepted pan.
struct TimelineScrubInteraction {
    private var lastFrame: Int?

    static func hasHorizontalIntent(_ translation: CGPoint) -> Bool {
        translation.x.isFinite && translation.y.isFinite && abs(translation.x) > abs(translation.y)
    }

    mutating func change(x: CGFloat, width: CGFloat, frameCount: Int) -> Int? {
        guard let target = Self.frame(at: x, width: width, frameCount: frameCount) else { return nil }
        lastFrame = target
        return target
    }

    mutating func end(x: CGFloat, width: CGFloat, frameCount: Int) -> Int? {
        guard let previous = cancel() else { return nil }
        return Self.frame(at: x, width: width, frameCount: frameCount) ?? previous
    }

    /// An interrupted pan lands exactly at its last coarse target and relinquishes it immediately.
    @discardableResult
    mutating func cancel() -> Int? {
        defer { lastFrame = nil }
        return lastFrame
    }

    static func frame(at x: CGFloat, width: CGFloat, frameCount: Int) -> Int? {
        guard width.isFinite, width > 0, x.isFinite, frameCount > 0 else { return nil }
        let last = frameCount - 1
        let progress = min(max(x / width, 0), 1)
        return Int(exactly: (progress * CGFloat(last)).rounded()) ?? last
    }

    static func adjustedFrame(_ frame: Int, increasing: Bool, frameCount: Int) -> Int? {
        guard frameCount > 0, (0..<frameCount).contains(frame) else { return nil }
        if increasing { return frame < frameCount - 1 ? frame + 1 : nil }
        return frame > 0 ? frame - 1 : nil
    }
}
