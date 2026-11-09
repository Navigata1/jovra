import CoreGraphics

/// The 8-point spacing scale (with a 4-point half step for tight pairs).
enum Space {
    static let half: CGFloat = 4
    static let x1: CGFloat = 8
    static let x2: CGFloat = 16
    static let x3: CGFloat = 24
    static let x4: CGFloat = 32
    static let x5: CGFloat = 40
    static let x6: CGFloat = 48
    /// Horizontal screen margin.
    static let screenMargin: CGFloat = 20
}

enum Radius {
    /// Cards and editorial panels.
    static let card: CGFloat = 22
    /// Inputs, thumbnails and inner tiles.
    static let control: CGFloat = 14
    /// Sheet corners.
    static let sheet: CGFloat = 28
    /// A capsule: any radius at least half the height.
    static let pill: CGFloat = .infinity
}

enum HitTarget {
    /// Apple HIG and CLAUDE.md rule 8: every control is at least 44×44 pt.
    static let minimum: CGFloat = 44
    /// Capture controls used at arm's length (Mark point, Pause, ScorePad).
    static let capture: CGFloat = 64
    /// The Stop disc.
    static let stop: CGFloat = 76
}

/// Video review metrics (screens.md §5.3).
enum VideoMetrics {
    /// The frame-quantized scrubber; never at the bottom edge.
    static let jogStripHeight: CGFloat = 48
    static let timelineToJogGap: CGFloat = 16
}
