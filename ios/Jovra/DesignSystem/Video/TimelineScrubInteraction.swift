import Foundation

/// A touch makes no seek until it has committed to horizontal scrubbing.
struct TimelineScrubInteraction {
    static let dragThreshold: CGFloat = 10

    private enum Intent {
        case undecided
        case vertical
        case horizontal(lastFrame: Int)
    }

    private var intent = Intent.undecided

    mutating func change(translation: CGSize, x: CGFloat, width: CGFloat, frameCount: Int) -> Int? {
        if case .undecided = intent {
            let horizontal = abs(translation.width)
            let vertical = abs(translation.height)
            guard max(horizontal, vertical) >= Self.dragThreshold else { return nil }
            if vertical >= horizontal {
                intent = .vertical
                return nil
            }
        }
        if case .vertical = intent { return nil }
        guard let frame = Self.frame(at: x, width: width, frameCount: frameCount) else { return nil }
        intent = .horizontal(lastFrame: frame)
        return frame
    }

    mutating func end(x: CGFloat, width: CGFloat, frameCount: Int) -> Int? {
        guard let lastFrame = cancel() else { return nil }
        return Self.frame(at: x, width: width, frameCount: frameCount) ?? lastFrame
    }

    /// If the system interrupts an accepted drag, land exactly on its last coarse target.
    mutating func cancel() -> Int? {
        defer { intent = .undecided }
        if case .horizontal(let lastFrame) = intent { return lastFrame }
        return nil
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
