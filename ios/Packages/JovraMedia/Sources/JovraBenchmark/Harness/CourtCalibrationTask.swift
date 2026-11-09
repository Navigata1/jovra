import Foundation
import JovraCore

/// One simulated calibration of a clip: four corner taps jittered off the truth, and where the fit puts the court
/// points the player did not tap. Integers only, so a record is exact and the Python scorer reads it back exactly.
public struct CourtCalibrationDraw: Codable, Hashable, Sendable {
    /// The four doubles-corner taps in video millipixels, in `CourtGeometry.doublesCorners` order.
    public let tapsMillipx: [[Int64]]
    /// The 12 untapped intersections (in `CourtIntersection.allCases` order, corners skipped), seen at their true
    /// pixels and unprojected through the fit: court millimetres, origin the net centre.
    public let intersectionsMm: [[Int64]]
    /// Every serve bounce of the clip, tapped at its rendered pixel and unprojected: court millimetres.
    public let bouncesMm: [[Int64]]

    public init(tapsMillipx: [[Int64]], intersectionsMm: [[Int64]], bouncesMm: [[Int64]]) {
        self.tapsMillipx = tapsMillipx
        self.intersectionsMm = intersectionsMm
        self.bouncesMm = bouncesMm
    }
}

/// Task `courtCalibration` 1.0.0 (T13): how far from the truth, on court, the 4-tap calibration puts ground points
/// the player did not tap. Pooled over every clip and draw:
/// - `intersections within 0.10 m`: share of untapped line intersections within 100 mm of their ITF position;
/// - `intersection MSE` (mm2): their mean squared on-court error;
/// - `bounces within 0.10 m` and `bounce MSE` (mm2): the same for serve bounces against the renderer's truth.
/// Exact rationals throughout; same rule as `spec/reference/jovra_ref/benchmark.py` `score_court_calibration`.
/// The RMSE is the square root of an MSE (the record keeps exact values only).
public struct CourtCalibrationTask: BenchmarkTask {
    public typealias Output = [CourtCalibrationDraw]

    public static let id = "courtCalibration"
    public static let version = "1.0.0"
    public static let withinMm: Int64 = 100

    let catalog: MediaFixtureCatalog

    public init(catalog: MediaFixtureCatalog) {
        self.catalog = catalog
    }

    public var descriptor: TaskDescriptor { TaskDescriptor(id: Self.id, version: Self.version, tolerance: nil) }

    public func truthDigest(of truth: GroundTruth) -> String { EventTimesTask.truthEventsSha256(truth) }

    /// The untapped intersections in millimetres, the order of `intersectionsMm`.
    public static let untapped: [CourtIntersection] = CourtIntersection.allCases.filter { !CourtGeometry.doublesCorners.contains($0) }

    static func millimetres(_ point: CourtPoint) -> [Int64] {
        [Int64((point.x * 1000).rounded()), Int64((point.y * 1000).rounded())]
    }

    public func score(truths: [GroundTruth], outputs: [[CourtCalibrationDraw]]) throws -> [MetricResult] {
        var intersections = Pool(), bounces = Pool()
        for (truth, draws) in zip(truths, outputs) {
            let serves = try ServeTruth.load(truth, catalog: catalog)
            let truthIntersections = Self.untapped.map { Self.millimetres($0.point) }
            for draw in draws {
                try intersections.add(estimates: draw.intersectionsMm, truths: truthIntersections, what: "intersection")
                try bounces.add(estimates: draw.bouncesMm, truths: serves.map(\.bounceCourtMm), what: "bounce")
            }
        }
        return [
            try MetricResult(name: "intersections within 0.10 m", exact: intersections.withinShare, places: 4),
            try MetricResult(name: "intersection MSE", unit: "mm2", exact: intersections.meanSquare, places: 3),
            try MetricResult(name: "bounces within 0.10 m", exact: bounces.withinShare, places: 4),
            try MetricResult(name: "bounce MSE", unit: "mm2", exact: bounces.meanSquare, places: 3),
        ]
    }

    struct Pool {
        var count: Int64 = 0, within: Int64 = 0, squares: Int64 = 0

        mutating func add(estimates: [[Int64]], truths: [[Int64]], what: String) throws {
            guard estimates.count == truths.count else { throw TaskError.outputCount(what: what, expected: truths.count, got: estimates.count) }
            for (e, t) in zip(estimates, truths) {
                let dx = e[0] - t[0], dy = e[1] - t[1], square = dx * dx + dy * dy
                count += 1
                squares += square
                if square <= CourtCalibrationTask.withinMm * CourtCalibrationTask.withinMm { within += 1 }
            }
        }

        var withinShare: Rational? { count > 0 ? Rational(within, count) : nil }
        var meanSquare: Rational? { count > 0 ? Rational(squares, count) : nil }
    }

    public enum TaskError: Error, Equatable, CustomStringConvertible {
        case outputCount(what: String, expected: Int, got: Int)
        case notBehindBaseline(String)

        public var description: String {
            switch self {
            case .outputCount(let what, let expected, let got): "Expected \(expected) \(what) estimates per draw, got \(got)"
            case .notBehindBaseline(let id): "\(id) is not filmed by the behind-baseline camera; court calibration needs its corners"
            }
        }
    }
}

/// The parts of a ground-truth file the calibration task reads that `GroundTruth` does not decode: the camera
/// angle and every serve bounce (court millimetres from the near baseline centre, and the rendered pixel).
struct ServeTruth: Decodable {
    struct Bounce: Decodable {
        struct MM: Decodable { let x: Int64; let y: Int64 }
        struct Pixel: Decodable { let x: Int64; let y: Int64 }
        let courtMm: MM
        let pixel: Pixel
    }
    struct Serve: Decodable { let bounce: Bounce }
    struct Camera: Decodable { let angle: String }
    struct Document: Decodable { let camera: Camera?; let serves: [Serve]? }

    let bounceCourtMm: [Int64]
    let bouncePixel: VideoPixel

    static func load(_ truth: GroundTruth, catalog: MediaFixtureCatalog) throws -> [ServeTruth] {
        try document(truth, catalog: catalog).serves.map { serves in
            serves.map {
                ServeTruth(bounceCourtMm: [$0.bounce.courtMm.x, $0.bounce.courtMm.y - 11_885],
                           bouncePixel: VideoPixel(x: Double($0.bounce.pixel.x), y: Double($0.bounce.pixel.y)))
            }
        } ?? []
    }

    static func document(_ truth: GroundTruth, catalog: MediaFixtureCatalog) throws -> Document {
        let parts = truth.id.split(separator: "/", maxSplits: 1).map(String.init)
        let url = catalog.truthDirectory.appendingPathComponent(parts[0]).appendingPathComponent("\(parts[1]).truth.json")
        return try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
    }
}

/// The 4-tap calibration as a player makes it (candidate `courtCalibration.fourTap`): each doubles corner tapped
/// up to 2 px off at 1080p (scaled to the clip's height, so the angular error matches a 1080p frame), the
/// homography fitted by JovraCore, then the untapped intersections and the serve bounces read back on court.
/// Corner pixels come from the renderer's behind-baseline pinhole camera (`scripts/media/jovra_media/court3d.py`
/// Camera.looking, eye 15 m behind the near baseline and 7.5 m up, aimed at the far service line, focal 1.05 x
/// width), the same camera `spec/reference/jovra_ref/sample_match.project` mirrors. Jitter comes from a SplitMix64
/// seeded by the clip seed, in whole millipixels inside the disc.
public struct CourtCalibrationEstimator: BenchmarkEstimator {
    public static let draws = 16
    public static let jitterPxAt1080p = 2.0
    let catalog: MediaFixtureCatalog

    public init(catalog: MediaFixtureCatalog) {
        self.catalog = catalog
    }

    public var identity: EstimatorIdentity { EstimatorIdentity(id: "courtCalibration.fourTap", methodVersion: "1.0.0", role: .candidate) }

    public func estimate(_ clip: BenchmarkClip) async throws -> [CourtCalibrationDraw] {
        let document = try ServeTruth.document(clip.truth, catalog: catalog)
        guard document.camera?.angle == "behindBaseline" else { throw CourtCalibrationTask.TaskError.notBehindBaseline(clip.truth.id) }
        let serves = try ServeTruth.load(clip.truth, catalog: catalog)
        let width = Double(clip.truth.video.displayWidth), height = Double(clip.truth.video.displayHeight)
        let camera = BehindBaselineCamera(width: width, height: height)
        let radius = Int64((Self.jitterPxAt1080p * 1000 * height / 1080).rounded(.down))
        var rng = SplitMix64(seed: UInt64(clip.truth.seed ?? 0) &+ 0x7131_3000)
        var draws: [CourtCalibrationDraw] = []
        for _ in 0..<Self.draws {
            var taps: [[Int64]] = []
            for corner in CourtGeometry.doublesCorners {
                let truePixel = camera.project(corner.point)
                var dx: Int64, dy: Int64
                repeat {
                    dx = rng.between(-radius, radius)
                    dy = rng.between(-radius, radius)
                } while dx * dx + dy * dy > radius * radius
                taps.append([Int64((truePixel.x * 1000).rounded()) + dx, Int64((truePixel.y * 1000).rounded()) + dy])
            }
            let homography = try Homography.fit(image: taps.map { VideoPixel(x: Double($0[0]) / 1000, y: Double($0[1]) / 1000) },
                                                court: CourtGeometry.doublesCorners.map(\.point))
            func readBack(_ pixel: VideoPixel) throws -> [Int64] {
                guard let court = homography.unproject(pixel) else { throw CalibrationError.degenerate }
                return CourtCalibrationTask.millimetres(court)
            }
            draws.append(CourtCalibrationDraw(
                tapsMillipx: taps,
                intersectionsMm: try CourtCalibrationTask.untapped.map { try readBack(camera.project($0.point)) },
                bouncesMm: try serves.map { try readBack($0.bouncePixel) }))
        }
        return draws
    }
}

/// The renderer's behind-baseline pinhole camera in court metres (origin the net centre).
struct BehindBaselineCamera {
    let width: Double, height: Double
    let eye = (0.0, -15.0 - CourtGeometry.halfLength, 7.5)
    let target = (0.0, 9.0 - CourtGeometry.halfLength, 0.0)

    func project(_ p: CourtPoint) -> VideoPixel {
        func sub(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) { (a.0 - b.0, a.1 - b.1, a.2 - b.2) }
        func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { a.0 * b.0 + a.1 * b.1 + a.2 * b.2 }
        func unit(_ a: (Double, Double, Double)) -> (Double, Double, Double) { let n = dot(a, a).squareRoot(); return (a.0 / n, a.1 / n, a.2 / n) }
        func cross(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
            (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
        }
        let f = unit(sub(target, eye)), r = unit(cross(f, (0, 0, 1))), u = cross(r, f)
        let d = sub((p.x, p.y, 0), eye), z = dot(d, f), focal = 1.05 * width
        return VideoPixel(x: width / 2 + focal * dot(d, r) / z, y: height / 2 - focal * dot(d, u) / z)
    }
}

/// SplitMix64 (the renderer's and the reference's generator).
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func between(_ low: Int64, _ high: Int64) -> Int64 {
        low + Int64(next() % UInt64(high - low + 1))
    }
}
