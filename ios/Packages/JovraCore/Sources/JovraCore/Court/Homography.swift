import Foundation

/// A position in the recorded video in pixels: origin top-left, x right, y down, in the display-oriented frame.
/// Taps are converted to video pixels (`VideoFrameMapping`) before any fit, never fitted in view points.
public struct VideoPixel: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Why court points and taps do not fix a homography. Shared codes with `spec/fixtures/calibration`.
public enum CalibrationError: String, Error, Sendable, Equatable {
    /// Fewer than four pairs.
    case tooFewPoints
    /// Unequal numbers of taps and court points.
    case countMismatch
    /// Collinear or repeated points: no unique plane-to-plane mapping.
    case degenerate
}

/// The plane-to-plane mapping from court metres to video pixels (GLOSSARY "Homography"), valid for ground points
/// only. Fitted by the normalized DLT (Hartley & Zisserman, algorithm 4.2) with the inhomogeneous solution in the
/// normalized frames: exact through four points, least squares through more. Mirrors
/// `spec/reference/jovra_ref/court.py` so both platforms reproduce `spec/fixtures/calibration`.
public struct Homography: Hashable, Sendable {
    static let pivotEpsilon = 1e-10
    static let collinearEpsilon = 1e-9

    /// Row major, `matrix[8] == 1`: court (x, y, 1) -> video (u w, v w, w).
    public let matrix: [Double]

    public init(matrix: [Double]) {
        precondition(matrix.count == 9, "A homography has nine entries")
        self.matrix = matrix
    }

    public static func fit(image: [VideoPixel], court: [CourtPoint]) throws(CalibrationError) -> Homography {
        guard image.count == court.count else { throw .countMismatch }
        guard image.count >= 4 else { throw .tooFewPoints }
        let courtPairs = court.map { ($0.x, $0.y) }, imagePairs = image.map { ($0.x, $0.y) }
        let tc = try normalizer(courtPairs), ti = try normalizer(imagePairs)
        for (t, points) in [(tc, courtPairs), (ti, imagePairs)] {
            let normalized = points.map { apply(t, $0.0, $0.1) }.map { ($0.0, $0.1) }
            if hasCollinearTriple(normalized, every: points.count == 4) { throw .degenerate }
        }
        var rows: [[Double]] = [], rhs: [Double] = []
        for ((u, v), (x, y)) in zip(imagePairs, courtPairs) {
            let (cx, cy, _) = apply(tc, x, y), (iu, iv, _) = apply(ti, u, v)
            rows.append([cx, cy, 1, 0, 0, 0, -iu * cx, -iu * cy]); rhs.append(iu)
            rows.append([0, 0, 0, cx, cy, 1, -iv * cx, -iv * cy]); rhs.append(iv)
        }
        let h: [Double]
        if image.count == 4 {
            h = try solve(rows, rhs)
        } else {
            var ata = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
            var atb = [Double](repeating: 0, count: 8)
            for i in 0..<8 {
                for j in 0..<8 { ata[i][j] = zip(rows, rows).reduce(0) { $0 + $1.0[i] * $1.1[j] } }
                atb[i] = zip(rows, rhs).reduce(0) { $0 + $1.0[i] * $1.1 }
            }
            h = try solve(ata, atb)
        }
        let hn = [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1.0]]
        let m = multiply(try inverse(ti), multiply(hn, tc))
        let largest = m.flatMap { $0 }.map(abs).max() ?? 0
        guard abs(m[2][2]) > pivotEpsilon * largest else { throw .degenerate }
        return Homography(matrix: m.flatMap { $0 }.map { $0 / m[2][2] })
    }

    /// Court metres -> video pixels; nil for a point on or beyond the horizon.
    public func project(_ point: CourtPoint) -> VideoPixel? {
        let (u, v, w) = Self.apply(rows, point.x, point.y)
        guard w > Self.pivotEpsilon else { return nil }
        return VideoPixel(x: u / w, y: v / w)
    }

    /// Video pixels -> court metres on the ground plane; nil above the horizon (no ground point there).
    public func unproject(_ pixel: VideoPixel) -> CourtPoint? {
        guard let inverse = try? Self.inverse(rows) else { return nil }
        let (x, y, w) = Self.apply(inverse, pixel.x, pixel.y)
        guard w > Self.pivotEpsilon else { return nil }
        return CourtPoint(x: x / w, y: y / w)
    }

    private var rows: [[Double]] { [Array(matrix[0..<3]), Array(matrix[3..<6]), Array(matrix[6..<9])] }

    // MARK: - Linear algebra (same order of operations as the Python reference)

    static func apply(_ m: [[Double]], _ x: Double, _ y: Double) -> (Double, Double, Double) {
        (m[0][0] * x + m[0][1] * y + m[0][2], m[1][0] * x + m[1][1] * y + m[1][2], m[2][0] * x + m[2][1] * y + m[2][2])
    }

    static func multiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0) { $0 + a[i][$1] * b[$1][j] } } }
    }

    static func inverse(_ m: [[Double]]) throws(CalibrationError) -> [[Double]] {
        let (a, b, c) = (m[0][0], m[0][1], m[0][2])
        let (d, e, f) = (m[1][0], m[1][1], m[1][2])
        let (g, h, i) = (m[2][0], m[2][1], m[2][2])
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        guard det != 0 else { throw .degenerate }
        let adjugate = [[e * i - f * h, c * h - b * i, b * f - c * e],
                        [f * g - d * i, a * i - c * g, c * d - a * f],
                        [d * h - e * g, b * g - a * h, a * e - b * d]]
        return adjugate.map { $0.map { $0 / det } }
    }

    /// Moves the centroid to the origin with mean distance sqrt(2) (Hartley normalization).
    static func normalizer(_ points: [(Double, Double)]) throws(CalibrationError) -> [[Double]] {
        let n = Double(points.count)
        let cx = points.reduce(0) { $0 + $1.0 } / n, cy = points.reduce(0) { $0 + $1.1 } / n
        let mean = points.reduce(0) { $0 + (($1.0 - cx) * ($1.0 - cx) + ($1.1 - cy) * ($1.1 - cy)).squareRoot() } / n
        guard mean != 0 else { throw .degenerate }
        let s = 2.0.squareRoot() / mean
        return [[s, 0, -s * cx], [0, s, -s * cy], [0, 0, 1]]
    }

    /// Exactly four points: no three may be collinear. More: not all of them may be.
    static func hasCollinearTriple(_ points: [(Double, Double)], every: Bool) -> Bool {
        var flat: [Bool] = []
        for i in points.indices {
            for j in points.indices where j > i {
                for k in points.indices where k > j {
                    let (a, b, c) = (points[i], points[j], points[k])
                    flat.append(abs((b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)) <= collinearEpsilon)
                }
            }
        }
        return every ? flat.contains(true) : !flat.contains(false)
    }

    /// Gaussian elimination with partial pivoting.
    static func solve(_ m: [[Double]], _ rhs: [Double]) throws(CalibrationError) -> [Double] {
        let n = m.count
        var a = zip(m, rhs).map { $0 + [$1] }
        for col in 0..<n {
            let scale = (0..<n).map { abs(a[$0][col]) }.max() ?? 0
            let pivot = (col..<n).max { abs(a[$0][col]) < abs(a[$1][col]) } ?? col
            guard scale != 0, abs(a[pivot][col]) > pivotEpsilon * scale else { throw .degenerate }
            a.swapAt(col, pivot)
            for k in (col + 1)..<max(n, col + 1) where k < n {
                let f = a[k][col] / a[col][col]
                if f != 0 { for j in col...n { a[k][j] -= f * a[col][j] } }
            }
        }
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var s = a[i][n]
            for j in (i + 1)..<max(n, i + 1) where j < n { s -= a[i][j] * x[j] }
            x[i] = s / a[i][i]
        }
        return x
    }
}
