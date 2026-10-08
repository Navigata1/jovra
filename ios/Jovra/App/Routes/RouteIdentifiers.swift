import Foundation

/// A typed identifier carried by a route payload. Routes hold identifiers, never documents, so a
/// payload stays small, `Codable` for state restoration, and valid after the document changes.
/// The session store (T08) and its peers mint the values; the router only carries them.
protocol RouteIdentifier: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible where RawValue == String {
    init(rawValue: String)
}

extension RouteIdentifier {
    init(stringLiteral value: String) { self.init(rawValue: value) }
    var description: String { rawValue }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A session in the library (GLOSSARY: Session).
struct SessionID: RouteIdentifier { var rawValue: String }
/// A point of a session's event log (GLOSSARY: Point).
struct PointID: RouteIdentifier { var rawValue: String }
/// A drill of the practice plan (GLOSSARY: Drill).
struct DrillID: RouteIdentifier { var rawValue: String }
/// A saved comparison of two recordings (GLOSSARY: Comparison).
struct ComparisonID: RouteIdentifier { var rawValue: String }
/// A practice goal (GLOSSARY: Goal).
struct GoalID: RouteIdentifier { var rawValue: String }
/// A capability of the registry, such as `serve-speed-manual` (GLOSSARY: Capability).
struct CapabilityID: RouteIdentifier { var rawValue: String }

/// A time in a session's media, kept rational (value / timescale) so a route never rounds a frame
/// time (ios-v1-spec, "Media times are stored as rational values").
struct MediaTime: Hashable, Codable, Sendable {
    var value: Int64
    var timescale: Int32

    /// Whole seconds, for a placeholder's readout only.
    var wholeSeconds: Int64 { timescale > 0 ? value / Int64(timescale) : 0 }
}

/// What was played (GLOSSARY: Session kind).
enum SessionKind: String, Codable, CaseIterable, Sendable {
    case singlesMatch, doublesMatch, servePractice, strokePractice

    var title: String {
        switch self {
        case .singlesMatch: String(localized: "Singles match", table: "App", comment: "Session kind")
        case .doublesMatch: String(localized: "Doubles match", table: "App", comment: "Session kind")
        case .servePractice: String(localized: "Serve practice", table: "App", comment: "Session kind")
        case .strokePractice: String(localized: "Stroke practice", table: "App", comment: "Session kind")
        }
    }

    var isMatch: Bool { self == .singlesMatch || self == .doublesMatch }
}

/// The session setup a capture starts from (session setup, not the racket Setup of the glossary).
/// Nil on the capture route means "the setup screen's current choices".
struct SessionSetupDraft: Hashable, Codable, Sendable {
    var kind: SessionKind
}

/// Which points a review or replay route shows (screen spec N1: Needs review · Unscored · All points).
enum PointFilter: String, Codable, CaseIterable, Sendable {
    case needsReview, unscored, all

    var title: String {
        switch self {
        case .needsReview: String(localized: "Needs review", table: "App", comment: "Point filter")
        case .unscored: String(localized: "Unscored", table: "App", comment: "Point filter")
        case .all: String(localized: "All points", table: "App", comment: "Point filter")
        }
    }
}
