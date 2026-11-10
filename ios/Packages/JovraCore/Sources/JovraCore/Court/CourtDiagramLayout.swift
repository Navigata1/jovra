import Foundation

/// Where every court line, band, zone and marker of a top-down court diagram sits, in diagram points (origin top-left,
/// the hitter's end at the bottom). The design system's CourtDiagram draws exactly these segments, so the drawing
/// cannot drift from `CourtGeometry` (T13 acceptance: the centre service line runs only through the service boxes and
/// the doubles alleys are drawn). Scales with width only; the height follows the court's proportions.
public struct CourtDiagramLayout: Hashable, Sendable {
    public enum Variant: Hashable, Sendable {
        /// The whole court (S11).
        case full
        /// The far half, net at the bottom (compact maps).
        case half
        /// The receiver's service box on the far half, net at the bottom, with T / Body / Wide zones (S12).
        case serviceBox(CourtGeometry.ServiceBox)
    }

    public struct Segment: Hashable, Sendable {
        public let id: String
        public let kind: CourtGeometry.LineKind
        public let from: PlanePoint
        public let to: PlanePoint
    }

    public struct Band: Hashable, Sendable {
        public let bin: CourtGeometry.DepthBin
        public let origin: PlanePoint
        public let size: PlaneSize
    }

    public struct Zone: Hashable, Sendable {
        public let zone: CourtGeometry.ServiceZone
        public let origin: PlanePoint
        public let size: PlaneSize
    }

    public struct Placed: Hashable, Sendable {
        public let point: PlanePoint
        /// The landing lies outside the drawn area and was clamped to its edge (S11 "Outliers").
        public let clamped: Bool
    }

    public let variant: Variant
    public let size: PlaneSize
    /// Diagram points per metre.
    public let scale: Double
    /// The court area drawn, in metres: x from `minX` to `maxX`, y from `minY` to `maxY`.
    public let minX: Double, maxX: Double, minY: Double, maxY: Double

    /// Run-off drawn around the court so out markers have room (metres).
    public static let runOffSides = 1.2
    public static let runOffEnds = 1.6
    public static let netOverhang = 0.0

    public init(variant: Variant, width: Double) {
        self.variant = variant
        let d = CourtGeometry.doublesHalfWidth, l = CourtGeometry.halfLength
        let s = CourtGeometry.singlesHalfWidth, sv = CourtGeometry.serviceLine
        switch variant {
        case .full:
            (minX, maxX, minY, maxY) = (-d - Self.runOffSides, d + Self.runOffSides, -l - Self.runOffEnds, l + Self.runOffEnds)
        case .half:
            (minX, maxX, minY, maxY) = (-d - Self.runOffSides, d + Self.runOffSides, 0, l + Self.runOffEnds)
        case .serviceBox(let box):
            // The far receiver's deuce box is on the server's left (x < 0) as drawn from the near end.
            (minX, maxX, minY, maxY) = box == .deuce ? (-s, 0, 0, sv) : (0, s, 0, sv)
        }
        scale = width / (maxX - minX)
        size = PlaneSize(width: width, height: (maxY - minY) * scale)
    }

    /// Court metres to diagram points (y flipped: the far end is at the top).
    public func point(_ court: CourtPoint) -> PlanePoint {
        PlanePoint(x: (court.x - minX) * scale, y: (maxY - court.y) * scale)
    }

    /// Diagram points back to court metres (a tap on the diagram).
    public func court(_ point: PlanePoint) -> CourtPoint {
        CourtPoint(x: point.x / scale + minX, y: maxY - point.y / scale)
    }

    /// A marker's position, clamped to the drawn area when the landing lies outside it.
    public func place(_ court: CourtPoint) -> Placed {
        let x = min(max(court.x, minX), maxX), y = min(max(court.y, minY), maxY)
        return Placed(point: point(CourtPoint(x: x, y: y)), clamped: x != court.x || y != court.y)
    }

    /// Every court line inside the drawn area, clipped to it.
    public var segments: [Segment] {
        CourtGeometry.lines.compactMap { line in
            guard let (a, b) = clip(line.from, line.to) else { return nil }
            return Segment(id: line.id, kind: line.kind, from: point(a), to: point(b))
        }
    }

    /// Depth bands on the far half (full and half variants).
    public var bands: [Band] {
        if case .serviceBox = variant { return [] }
        let d = CourtGeometry.doublesHalfWidth
        return CourtGeometry.depthBands.map { band in
            let topLeft = point(CourtPoint(x: -d, y: band.toM))
            let bottomRight = point(CourtPoint(x: d, y: band.fromM))
            return Band(bin: band.bin, origin: topLeft, size: PlaneSize(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y))
        }
    }

    /// T / Body / Wide thirds of the service box (service-box variant).
    public var zones: [Zone] {
        guard case .serviceBox = variant else { return [] }
        let third = CourtGeometry.singlesHalfWidth / 3, sign: Double = maxX > 0 ? 1 : -1
        return [CourtGeometry.ServiceZone.t, .body, .wide].enumerated().map { index, zone in
            let a = point(CourtPoint(x: sign * Double(index) * third, y: CourtGeometry.serviceLine))
            let b = point(CourtPoint(x: sign * Double(index + 1) * third, y: 0))
            return Zone(zone: zone, origin: PlanePoint(x: min(a.x, b.x), y: a.y), size: PlaneSize(width: abs(b.x - a.x), height: b.y - a.y))
        }
    }

    private func clip(_ a: CourtPoint, _ b: CourtPoint) -> (CourtPoint, CourtPoint)? {
        // Court lines are axis-aligned, so clipping is per axis.
        let x0 = max(min(a.x, b.x), minX), x1 = min(max(a.x, b.x), maxX)
        let y0 = max(min(a.y, b.y), minY), y1 = min(max(a.y, b.y), maxY)
        guard x0 <= x1, y0 <= y1 else { return nil }
        if a.x == b.x { return (CourtPoint(x: a.x, y: y0), CourtPoint(x: a.x, y: y1)) }
        return (CourtPoint(x: x0, y: a.y), CourtPoint(x: x1, y: a.y))
    }
}
