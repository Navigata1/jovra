import CoreGraphics

/// Pinch zoom on a video surface. It belongs to the screen, not to a frame, so it persists while stepping.
/// Pinching is continuous between `minimum` and `maximum`; the accessible control moves between `levels`,
/// which include both ends, so every zoom a pinch can reach is reachable without one.
struct VideoZoom: Equatable {
    static let minimum: CGFloat = 1
    static let maximum: CGFloat = 4
    static let levels: [CGFloat] = [1, 1.5, 2, 3, 4]

    private(set) var scale: CGFloat = 1
    /// Pan of the zoomed picture, in points of the unzoomed surface.
    private(set) var offset: CGSize = .zero

    var isZoomed: Bool { scale > Self.minimum + 0.001 }
    var percent: Int { Int((scale * 100).rounded()) }

    static func clamped(_ scale: CGFloat) -> CGFloat { min(max(scale, minimum), maximum) }

    /// Sets the scale from a pinch, keeping the pan inside the picture.
    mutating func setScale(_ newScale: CGFloat, in size: CGSize) {
        scale = Self.clamped(newScale)
        offset = Self.limit(offset, scale: scale, size: size)
    }

    mutating func pan(to proposed: CGSize, in size: CGSize) {
        offset = Self.limit(proposed, scale: scale, size: size)
    }

    /// The next level above (or below) the current scale.
    mutating func step(up: Bool, in size: CGSize) {
        let next = up ? Self.levels.first { $0 > scale + 0.001 } : Self.levels.last { $0 < scale - 0.001 }
        setScale(next ?? (up ? Self.maximum : Self.minimum), in: size)
    }

    mutating func reset() {
        scale = Self.minimum
        offset = .zero
    }

    var canZoomIn: Bool { scale < Self.maximum - 0.001 }
    var canZoomOut: Bool { isZoomed }

    private static func limit(_ offset: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        let maxX = max(0, (scale - 1) * size.width / 2), maxY = max(0, (scale - 1) * size.height / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }
}
