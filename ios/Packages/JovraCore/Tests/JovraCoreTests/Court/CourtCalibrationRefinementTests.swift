import Testing
import JovraCore

@Suite("Court calibration refinement")
struct CourtCalibrationRefinementTests {
    static let camera = CameraBinding(lens: .wide, width: 1920, height: 1080, zoomFactor: 1)

    // Independent renderer pixels from C01's 1080p camera, rounded to six places.
    static let cornerPixels = [
        VideoPixel(x: 292.029424, y: 866.918919), VideoPixel(x: 1627.970576, y: 866.918919),
        VideoPixel(x: 1241.781999, y: 313.674257), VideoPixel(x: 678.218001, y: 313.674257)
    ]
    static let fitPixels: [(CourtIntersection, Double, Double)] = [
        (.nearLeftService, 579.274985, 637.002683), (.nearRightService, 1340.725015, 637.002683),
        (.farRightService, 1203.945583, 375.819387), (.farLeftService, 716.054417, 375.819387),
        (.nearServiceT, 960, 637.002683), (.farServiceT, 960, 375.819387),
        (.nearCentreMark, 960, 866.918919), (.farCentreMark, 960, 313.674257)
    ]
    static let heldOutTruth = [
        observation(.nearLeftSingles, x: 458.869841, y: 866.918919),
        observation(.nearRightSingles, x: 1461.130159, y: 866.918919),
        observation(.farRightSingles, x: 1171.400716, y: 313.674257),
        observation(.farLeftSingles, x: 748.599284, y: 313.674257)
    ]
    static let measured = fitPixels.enumerated().map { index, value in
        observation(value.0, x: value.1 + (index.isMultiple(of: 2) ? -0.13 : 0.16),
                    y: value.2 + (index.isMultiple(of: 3) ? -0.18 : 0.17))
    }
    static let heldOut = heldOutTruth.enumerated().map { index, value in
        CalibrationObservation(court: value.court,
                               pixel: VideoPixel(x: value.pixel.x, y: value.pixel.y + (index.isMultiple(of: 2) ? 0.015 : -0.015)))
    }

    @Test(arguments: [-2.0, 2.0])
    func coherentCornerJitterCanBeRefinedAgainstIndependentIntersections(_ jitter: Double) throws {
        let manual = try calibration(jitter: jitter)
        let far = Self.heldOutTruth[2]
        let unrefined = try #require(manual.unproject(far.pixel))
        #expect(unrefined.distance(to: far.court) > 0.20)

        let proposed = try #require(manual.proposedRefinement(fitting: Self.measured, checking: Self.heldOut, current: Self.camera, atMs: 0))
        for truth in Self.heldOutTruth {
            let estimated = try #require(proposed.unproject(truth.pixel))
            #expect(estimated.distance(to: truth.court) <= 0.10)
        }
        #expect(manual.unproject(far.pixel) == unrefined)
    }

    @Test func missingOrDegenerateLineEvidenceKeepsManualCalibration() throws {
        let manual = try calibration(jitter: 2)
        #expect(manual.proposedRefinement(fitting: [], checking: Self.heldOut, current: Self.camera, atMs: 0) == nil)
        #expect(manual.proposedRefinement(fitting: Self.measured, checking: [], current: Self.camera, atMs: 0) == nil)
        let collinear = Self.measured.map {
            CalibrationObservation(court: $0.court, pixel: VideoPixel(x: $0.pixel.x, y: 540))
        }
        #expect(manual.proposedRefinement(fitting: collinear, checking: Self.heldOut, current: Self.camera, atMs: 0) == nil)
    }

    @Test func coherentBadMeasurementsCannotPassIndependentHoldouts() throws {
        let manual = try calibration(jitter: 2)
        let shifted = Self.measured.map {
            CalibrationObservation(court: $0.court, pixel: VideoPixel(x: $0.pixel.x, y: $0.pixel.y + 1.5))
        }
        #expect(manual.proposedRefinement(fitting: shifted, checking: Self.heldOut, current: Self.camera, atMs: 0) == nil)
    }

    @Test func recycledOrOneSidedObservationsCannotStandInForIndependentChecks() throws {
        let manual = try calibration(jitter: 2)
        let recycled = Array(Self.measured.prefix(2)) + Self.heldOut
        #expect(manual.proposedRefinement(fitting: Self.measured, checking: recycled, current: Self.camera, atMs: 0) == nil)
        let nearOnly = Self.heldOut.filter { $0.court.y < 0 }
        #expect(manual.proposedRefinement(fitting: Self.measured, checking: nearOnly, current: Self.camera, atMs: 0) == nil)
    }

    @Test func aDifferentCameraOrStaleCalibrationCannotOfferARefinement() throws {
        var manual = try calibration(jitter: 2)
        var otherCamera = Self.camera
        otherCamera.zoomFactor = 2
        #expect(manual.proposedRefinement(fitting: Self.measured, checking: Self.heldOut, current: otherCamera, atMs: 0) == nil)
        manual.staleFromMs = 10
        #expect(manual.proposedRefinement(fitting: Self.measured, checking: Self.heldOut, current: Self.camera, atMs: 10) == nil)
    }

    func calibration(jitter: Double) throws -> CourtCalibration {
        let taps = Self.cornerPixels.map { VideoPixel(x: $0.x, y: $0.y + jitter) }
        return try CourtCalibration(doublesCorners: taps, camera: Self.camera)
    }

    private static func observation(_ intersection: CourtIntersection, x: Double, y: Double) -> CalibrationObservation {
        CalibrationObservation(court: intersection.point, pixel: VideoPixel(x: x, y: y))
    }

}
