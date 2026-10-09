import Foundation

/// The closed schema stores each trailing momentum observation as exactly [won, size].
public struct StatsMomentumPair: Codable, Equatable, Sendable {
    public var pointsWon: Int
    public var pointsInWindow: Int
    public init(pointsWon: Int, pointsInWindow: Int) {
        self.pointsWon = pointsWon; self.pointsInWindow = pointsInWindow
    }
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        pointsWon = try values.decode(Int.self); pointsInWindow = try values.decode(Int.self)
        guard values.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: "Momentum requires exactly two integers")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(pointsWon); try values.encode(pointsInWindow)
    }
}
