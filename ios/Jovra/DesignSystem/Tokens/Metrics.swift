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
}

enum HitTarget {
    /// Apple HIG and CLAUDE.md rule 8: every control is at least 44×44 pt.
    static let minimum: CGFloat = 44
}
