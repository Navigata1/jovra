import Foundation

/// A ground position on the court model in metres (GLOSSARY "Court model"): origin at the centre of the net, `x`
/// across the court (positive to the right of a player at the near end), `y` towards the far baseline.
public struct CourtPoint: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: CourtPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// The ITF court in metres: the single source for diagrams, the framing guide, depth bins and serve zones
/// (screens.md §5.2). Mirrors `spec/reference/jovra_ref/court.py`; `spec/fixtures/calibration/C08-geometry.json`
/// pins every line, intersection and bin.
public enum CourtGeometry {
    /// Net to baseline (court 23.77 m long).
    public static let halfLength = 11.885
    /// Centre line to doubles sideline (court 10.97 m wide).
    public static let doublesHalfWidth = 5.485
    /// Centre line to singles sideline (8.23 m).
    public static let singlesHalfWidth = 4.115
    /// Net to service line.
    public static let serviceLine = 6.40
    /// Length of the centre mark inside each baseline.
    public static let centreMark = 0.10
    /// Net posts 0.914 m outside the doubles sidelines.
    public static let netPostHalfWidth = 6.40

    public enum LineKind: String, Sendable, CaseIterable {
        case baseline, doublesSideline, singlesSideline, serviceLine, centreServiceLine, centreMark, net
    }

    public struct Line: Hashable, Sendable {
        public let id: String
        public let kind: LineKind
        public let from: CourtPoint
        public let to: CourtPoint
    }

    /// Every painted line plus the net, near end first, left before right. The centre service line runs only
    /// between the service lines, through the service boxes.
    public static let lines: [Line] = {
        let d = doublesHalfWidth, s = singlesHalfWidth, l = halfLength, sv = serviceLine
        func line(_ id: String, _ kind: LineKind, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Line {
            Line(id: id, kind: kind, from: CourtPoint(x: x0, y: y0), to: CourtPoint(x: x1, y: y1))
        }
        return [
            line("nearBaseline", .baseline, -d, -l, d, -l),
            line("farBaseline", .baseline, -d, l, d, l),
            line("leftDoublesSideline", .doublesSideline, -d, -l, -d, l),
            line("rightDoublesSideline", .doublesSideline, d, -l, d, l),
            line("leftSinglesSideline", .singlesSideline, -s, -l, -s, l),
            line("rightSinglesSideline", .singlesSideline, s, -l, s, l),
            line("nearServiceLine", .serviceLine, -s, -sv, s, -sv),
            line("farServiceLine", .serviceLine, -s, sv, s, sv),
            line("centreServiceLine", .centreServiceLine, 0, -sv, 0, sv),
            line("nearCentreMark", .centreMark, 0, -l, 0, -l + centreMark),
            line("farCentreMark", .centreMark, 0, l - centreMark, 0, l),
            line("net", .net, -netPostHalfWidth, 0, netPostHalfWidth, 0),
        ]
    }()

    /// The four corners a player taps on the framing screen (S05: brackets on the doubles corners), near left first,
    /// clockwise as seen from behind the near baseline.
    public static let doublesCorners: [CourtIntersection] = [.nearLeftDoubles, .nearRightDoubles, .farRightDoubles, .farLeftDoubles]
    public static let singlesCorners: [CourtIntersection] = [.nearLeftSingles, .nearRightSingles, .farRightSingles, .farLeftSingles]

    public enum DepthBin: String, Sendable, CaseIterable {
        /// Inside the service line.
        case short
        /// Between the service line and the baseline.
        case deep
        /// Beyond the baseline.
        case long
    }

    public struct DepthBand: Hashable, Sendable {
        public let bin: DepthBin
        /// Distance from the net, metres.
        public let fromM: Double
        public let toM: Double
    }

    /// The bands drawn on a half (S11: "Deep" beyond the service line, "Short" inside it).
    public static let depthBands = [DepthBand(bin: .short, fromM: 0, toM: serviceLine), DepthBand(bin: .deep, fromM: serviceLine, toM: halfLength)]

    /// Depth of a landing on either half, by its distance from the net.
    public static func depthBin(y: Double) -> DepthBin {
        let distance = abs(y)
        if distance <= serviceLine { return .short }
        return distance <= halfLength ? .deep : .long
    }

    public enum ServiceZone: String, Sendable, CaseIterable {
        case t, body, wide
    }

    /// Serve zone across a service box (S12): equal thirds from the centre service line.
    public static func serviceZone(x: Double) -> ServiceZone {
        let third = abs(x) / singlesHalfWidth
        if third < 1.0 / 3.0 { return .t }
        return third < 2.0 / 3.0 ? .body : .wide
    }

    public enum ServiceBox: String, Sendable, CaseIterable {
        case deuce, ad
    }

    /// The receiver's box a serve landed in: the deuce box is the receiver's right, so x and y differ in sign.
    public static func serviceBox(of point: CourtPoint) -> ServiceBox {
        point.x * point.y < 0 ? .deuce : .ad
    }

    /// Inside the singles court (the alleys count as out) or the doubles court.
    public static func contains(_ point: CourtPoint, doubles: Bool) -> Bool {
        abs(point.x) <= (doubles ? doublesHalfWidth : singlesHalfWidth) && abs(point.y) <= halfLength
    }
}

/// A named ground point where painted lines meet: what a player can tap, and what the calibration check projects.
public enum CourtIntersection: String, Sendable, CaseIterable {
    case nearLeftDoubles, nearRightDoubles, farRightDoubles, farLeftDoubles
    case nearLeftSingles, nearRightSingles, farRightSingles, farLeftSingles
    case nearLeftService, nearRightService, farRightService, farLeftService
    case nearServiceT, farServiceT
    case nearCentreMark, farCentreMark

    public var point: CourtPoint {
        let d = CourtGeometry.doublesHalfWidth, s = CourtGeometry.singlesHalfWidth
        let l = CourtGeometry.halfLength, sv = CourtGeometry.serviceLine
        return switch self {
        case .nearLeftDoubles: CourtPoint(x: -d, y: -l)
        case .nearRightDoubles: CourtPoint(x: d, y: -l)
        case .farRightDoubles: CourtPoint(x: d, y: l)
        case .farLeftDoubles: CourtPoint(x: -d, y: l)
        case .nearLeftSingles: CourtPoint(x: -s, y: -l)
        case .nearRightSingles: CourtPoint(x: s, y: -l)
        case .farRightSingles: CourtPoint(x: s, y: l)
        case .farLeftSingles: CourtPoint(x: -s, y: l)
        case .nearLeftService: CourtPoint(x: -s, y: -sv)
        case .nearRightService: CourtPoint(x: s, y: -sv)
        case .farRightService: CourtPoint(x: s, y: sv)
        case .farLeftService: CourtPoint(x: -s, y: sv)
        case .nearServiceT: CourtPoint(x: 0, y: -sv)
        case .farServiceT: CourtPoint(x: 0, y: sv)
        case .nearCentreMark: CourtPoint(x: 0, y: -l)
        case .farCentreMark: CourtPoint(x: 0, y: l)
        }
    }
}
