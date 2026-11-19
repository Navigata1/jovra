import Foundation

/// Frame mapping and the last coarse target of the currently accepted pan.
struct TimelineScrubInteraction {
    private var lastFrame: Int?

    static func hasHorizontalIntent(_ translation: CGPoint) -> Bool {
        translation.x.isFinite && translation.y.isFinite && abs(translation.x) > abs(translation.y)
    }

    mutating func change(x: CGFloat, width: CGFloat, frameCount: Int, inset: CGFloat = 0) -> Int? {
        guard let target = Self.frame(at: x, width: width, frameCount: frameCount, inset: inset) else { return nil }
        lastFrame = target
        return target
    }

    mutating func end(x: CGFloat, width: CGFloat, frameCount: Int, inset: CGFloat = 0) -> Int? {
        guard let previous = cancel() else { return nil }
        return Self.frame(at: x, width: width, frameCount: frameCount, inset: inset) ?? previous
    }

    /// An interrupted pan lands exactly at its last coarse target and relinquishes it immediately.
    @discardableResult
    mutating func cancel() -> Int? {
        defer { lastFrame = nil }
        return lastFrame
    }

    /// The frame under a touch at `x`. `inset` is the thumb's radius: the thumb travels between `inset` and
    /// `width - inset`, and the margins beside that travel select the first and last frame.
    static func frame(at x: CGFloat, width: CGFloat, frameCount: Int, inset: CGFloat = 0) -> Int? {
        guard width.isFinite, width > 0, x.isFinite, frameCount > 0 else { return nil }
        let last = frameCount - 1
        let inset = usableInset(inset, width: width)
        let progress = min(max((x - inset) / (width - 2 * inset), 0), 1)
        return Int(exactly: (progress * CGFloat(last)).rounded()) ?? last
    }

    /// Where the thumb's centre is drawn for `frame`: the inverse of `frame(at:width:frameCount:inset:)`.
    static func thumbCentre(frame: Int, frameCount: Int, width: CGFloat, inset: CGFloat = 0) -> CGFloat {
        let inset = usableInset(inset, width: width)
        let last = max(frameCount - 1, 0)
        let progress = last > 0 ? CGFloat(min(max(frame, 0), last)) / CGFloat(last) : 0
        return inset + progress * (width - 2 * inset)
    }

    /// A track too narrow to hold its thumb uses its whole width.
    private static func usableInset(_ inset: CGFloat, width: CGFloat) -> CGFloat {
        inset.isFinite && inset > 0 && width > 2 * inset ? inset : 0
    }

    static func adjustedFrame(_ frame: Int, increasing: Bool, frameCount: Int) -> Int? {
        guard frameCount > 0, (0..<frameCount).contains(frame) else { return nil }
        if increasing { return frame < frameCount - 1 ? frame + 1 : nil }
        return frame > 0 ? frame - 1 : nil
    }
}
