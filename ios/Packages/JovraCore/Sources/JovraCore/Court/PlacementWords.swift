import Foundation

/// How a placement was judged: In, Out or Needs review (shape-first markers, S11).
public enum PlacementResult: String, Sendable, Codable, Hashable, CaseIterable {
    case `in`, out, needsReview
}

/// What VoiceOver says about a placement (story 364, "Deep cross-court, in"), as values the app localizes.
/// Mirrors `placement_words` in `spec/reference/jovra_ref/court.py` (fixture C09).
public struct PlacementWords: Hashable, Sendable {
    public enum Direction: String, Sendable, Hashable {
        /// With the hitter's position known.
        case crossCourt, downTheLine
        /// Within the central third of the singles court.
        case middle
        /// Without the hitter's position: sides as seen from the hitter's end (the bottom of the diagram).
        case left, right
    }

    public let depth: CourtGeometry.DepthBin
    public let direction: Direction
    /// Beyond the sideline that counts (singles: the alley is out; doubles: in).
    public let wide: Bool
    public let result: PlacementResult

    /// - Parameters:
    ///   - landing: the bounce on the court model (shot maps normalize landings onto the far half).
    ///   - hitterX: where across the court the hitter stood, when known.
    public init(landing: CourtPoint, hitterX: Double?, result: PlacementResult, doubles: Bool) {
        depth = CourtGeometry.depthBin(y: landing.y)
        if abs(landing.x) < CourtGeometry.singlesHalfWidth / 3 {
            direction = .middle
        } else if let hitterX, hitterX != 0 {
            direction = (landing.x > 0) == (hitterX > 0) ? .downTheLine : .crossCourt
        } else {
            direction = landing.x > 0 ? .right : .left
        }
        wide = abs(landing.x) > (doubles ? CourtGeometry.doublesHalfWidth : CourtGeometry.singlesHalfWidth)
        self.result = result
    }

    /// The English sentence, the source text of the String Catalog entries (and of the Python reference):
    /// "Deep cross-court, in", "Long middle, out", "Deep cross-court, wide, out".
    public var englishSentence: String {
        let depthWord = switch depth { case .short: "Short"; case .deep: "Deep"; case .long: "Long" }
        let directionWord = switch direction {
        case .crossCourt: "cross-court"; case .downTheLine: "down the line"; case .middle: "middle"
        case .left: "left"; case .right: "right"
        }
        let resultWord = switch result { case .in: "in"; case .out: "out"; case .needsReview: "needs review" }
        return "\(depthWord) \(directionWord)" + (wide ? ", wide" : "") + ", \(resultWord)"
    }
}
