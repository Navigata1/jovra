import Foundation

/// A court point and where its painted line was seen in the video: an input of the reprojection check.
public struct CalibrationObservation: Hashable, Sendable {
    public var court: CourtPoint
    public var pixel: VideoPixel

    public init(court: CourtPoint, pixel: VideoPixel) {
        self.court = court
        self.pixel = pixel
    }
}

/// The check that can fail (ios-v1-spec CourtCalibration, story 66): project the court points the player did not
/// tap and measure how far they land from where those lines are seen. Poor above 3 px RMSE at 1080p, scaled by
/// the frame height (2 px at 720p). With nothing measured it is `notMeasurable`, never a pass.
public struct CalibrationCheck: Hashable, Sendable {
    public static let poorFitPxAt1080p = 3.0

    public enum Verdict: String, Sendable, Hashable {
        case good, poor, notMeasurable
    }

    public let verdict: Verdict
    /// Root mean square pixel distance; nil when nothing was measured or a point projects beyond the horizon.
    public let rmsePx: Double?
    public let thresholdPx: Double

    public init(homography: Homography, observations: [CalibrationObservation], frameHeight: Int) {
        thresholdPx = Self.thresholdPx(frameHeight: frameHeight)
        rmsePx = Self.reprojectionRMSE(homography: homography, observations: observations)
        if let rmsePx {
            verdict = rmsePx <= thresholdPx ? .good : .poor
        } else {
            verdict = .notMeasurable
        }
    }

    public static func thresholdPx(frameHeight: Int) -> Double {
        poorFitPxAt1080p * Double(frameHeight) / 1080
    }

    public static func reprojectionRMSE(homography: Homography, observations: [CalibrationObservation]) -> Double? {
        guard !observations.isEmpty else { return nil }
        var total = 0.0
        for observation in observations {
            guard let p = homography.project(observation.court) else { return nil }
            total += (p.x - observation.pixel.x) * (p.x - observation.pixel.x) + (p.y - observation.pixel.y) * (p.y - observation.pixel.y)
        }
        return (total / Double(observations.count)).squareRoot()
    }
}

/// What a calibration is bound to (technical-feasibility §8): a different lens, format or zoom invalidates it.
public struct CameraBinding: Hashable, Sendable {
    public var lens: SessionCalibrationCameraLens
    public var width: Int
    public var height: Int
    public var zoomFactor: Decimal

    public init(lens: SessionCalibrationCameraLens, width: Int, height: Int, zoomFactor: Decimal) {
        self.lens = lens
        self.width = width
        self.height = height
        self.zoomFactor = zoomFactor
    }
}

/// Whether calibration-dependent features (frame taps, serve speed) may use a calibration now.
public enum CalibrationValidity: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case lensChanged, formatChanged, zoomChanged, poorFit
        /// The camera moved: stale from this session time ("stale from mm:ss").
        case stale(fromMs: Int)

        public var code: String {
            switch self {
            case .lensChanged: "lensChanged"
            case .formatChanged: "formatChanged"
            case .zoomChanged: "zoomChanged"
            case .poorFit: "poorFit"
            case .stale: "stale"
            }
        }
    }

    case valid
    case invalid(Reason)

    public var status: String {
        if case .valid = self { return "valid" }
        return "invalid"
    }

    public var reasonCode: String? {
        if case .invalid(let reason) = self { return reason.code }
        return nil
    }

    /// First failing reason wins, in this order: lens, format, zoom, poor fit, stale.
    public static func evaluate(binding: CameraBinding, current: CameraBinding, checkVerdict: CalibrationCheck.Verdict?,
                                staleFromMs: Int?, atMs: Int) -> CalibrationValidity {
        if binding.lens != current.lens { return .invalid(.lensChanged) }
        if binding.width != current.width || binding.height != current.height { return .invalid(.formatChanged) }
        if binding.zoomFactor != current.zoomFactor { return .invalid(.zoomChanged) }
        if checkVerdict == .poor { return .invalid(.poorFit) }
        if let staleFromMs, atMs >= staleFromMs { return .invalid(.stale(fromMs: staleFromMs)) }
        return .valid
    }
}

/// A 4-tap court calibration: taps in video pixels, the court points they mark, the fitted homography, the camera it
/// is bound to and, once the camera moved, the time it is stale from.
public struct CourtCalibration: Hashable, Sendable {
    public let imagePoints: [VideoPixel]
    public let courtPoints: [CourtPoint]
    public let homography: Homography
    public let camera: CameraBinding?
    public var staleFromMs: Int?
    /// The latest reprojection check, when line pixels were measured.
    public var check: CalibrationCheck?

    public init(imagePoints: [VideoPixel], courtPoints: [CourtPoint], camera: CameraBinding?, staleFromMs: Int? = nil) throws(CalibrationError) {
        self.imagePoints = imagePoints
        self.courtPoints = courtPoints
        self.homography = try Homography.fit(image: imagePoints, court: courtPoints)
        self.camera = camera
        self.staleFromMs = staleFromMs
    }

    /// The four doubles corners, tapped in video pixels in `CourtGeometry.doublesCorners` order.
    public init(doublesCorners taps: [VideoPixel], camera: CameraBinding?) throws(CalibrationError) {
        try self.init(imagePoints: taps, courtPoints: CourtGeometry.doublesCorners.map(\.point), camera: camera)
    }

    /// A session calibration record: normalized image points (0..1, top-left) scaled by its camera format. A
    /// record without a camera format cannot be placed in pixels and is refused as degenerate.
    public init(record: SessionCalibration) throws(CalibrationError) {
        guard let camera = record.camera else { throw .degenerate }
        let w = Double(camera.width), h = Double(camera.height)
        let image = record.imagePoints.map { VideoPixel(x: Self.double($0.x) * w, y: Self.double($0.y) * h) }
        let court = record.courtPoints.map { CourtPoint(x: Self.double($0.x), y: Self.double($0.y)) }
        let zoom = Decimal(string: camera.zoomFactor) ?? 1
        try self.init(imagePoints: image, courtPoints: court,
                      camera: CameraBinding(lens: camera.lens, width: camera.width, height: camera.height, zoomFactor: zoom),
                      staleFromMs: record.staleFromMs)
    }

    public func project(_ point: CourtPoint) -> VideoPixel? { homography.project(point) }
    public func unproject(_ pixel: VideoPixel) -> CourtPoint? { homography.unproject(pixel) }

    /// Runs the reprojection check against measured line pixels and keeps the result.
    public func checked(against observations: [CalibrationObservation]) -> CourtCalibration {
        var copy = self
        copy.check = CalibrationCheck(homography: homography, observations: observations, frameHeight: camera?.height ?? 1080)
        return copy
    }

    /// Usable at `atMs` with the camera configured as `current`? A calibration with no recorded binding can only be
    /// judged on fit and staleness.
    public func validity(atMs: Int, current: CameraBinding) -> CalibrationValidity {
        CalibrationValidity.evaluate(binding: camera ?? current, current: current, checkVerdict: check?.verdict,
                                     staleFromMs: staleFromMs, atMs: atMs)
    }

    private static func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}
