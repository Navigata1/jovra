import Foundation
import Testing
import JovraCore

/// Behaviour beyond the shared vectors: the calibration value type (record decoding, validity over time, the
/// check kept on the value) and the negative tests the ticket names. Expected values are hand-worked.
@Suite("CourtCalibration")
struct CourtCalibrationTests {
    // Pixels = 40 x court metres + (960, 540): an affine camera looking straight down, so every expected pixel is
    // worked by hand.
    static func pixel(_ p: CourtPoint) -> VideoPixel { VideoPixel(x: 40 * p.x + 960, y: -40 * p.y + 540) }
    static let binding = CameraBinding(lens: .wide, width: 1920, height: 1080, zoomFactor: 1)

    func calibration(offset: Double = 0) throws -> CourtCalibration {
        var taps = CourtGeometry.doublesCorners.map { Self.pixel($0.point) }
        taps[2].x += offset
        return try CourtCalibration(doublesCorners: taps, camera: Self.binding)
    }

    func untapped() -> [CalibrationObservation] {
        CourtIntersection.allCases.filter { !CourtGeometry.doublesCorners.contains($0) }
            .map { CalibrationObservation(court: $0.point, pixel: Self.pixel($0.point)) }
    }

    @Test func exactTapsProjectEveryIntersection() throws {
        let c = try calibration()
        for i in CourtIntersection.allCases {
            let p = try #require(c.project(i.point)), want = Self.pixel(i.point)
            #expect(abs(p.x - want.x) < 1e-9 && abs(p.y - want.y) < 1e-9)
        }
        #expect(c.checked(against: untapped()).check?.verdict == .good)
    }

    @Test func aCalibrationPerturbedBeyondThreePixelsIsAPoorFitAndInvalid() throws {
        let poor = try calibration(offset: 14).checked(against: untapped())
        let check = try #require(poor.check)
        #expect(check.verdict == .poor)
        #expect(try #require(check.rmsePx) > 3)
        #expect(poor.validity(atMs: 0, current: Self.binding) == .invalid(.poorFit))
    }

    @Test func pastItsStaleFromTimeACalibrationIsInvalidWithThatReason() throws {
        var c = try calibration()
        c.staleFromMs = 754_000   // the camera moved at 12:34
        #expect(c.validity(atMs: 753_999, current: Self.binding) == .valid)
        #expect(c.validity(atMs: 754_000, current: Self.binding) == .invalid(.stale(fromMs: 754_000)))
        #expect(c.validity(atMs: 900_000, current: Self.binding).reasonCode == "stale")
    }

    @Test func aDifferentLensFormatOrZoomInvalidates() throws {
        let c = try calibration()
        var other = Self.binding
        other.zoomFactor = Decimal(string: "2")!
        #expect(c.validity(atMs: 0, current: other) == .invalid(.zoomChanged))
        other = Self.binding
        other.height = 720
        #expect(c.validity(atMs: 0, current: other) == .invalid(.formatChanged))
    }

    @Test func nothingMeasuredIsNeverAPass() throws {
        let c = try calibration(offset: 50).checked(against: [])
        #expect(c.check?.verdict == .notMeasurable)
        #expect(c.check?.rmsePx == nil)
    }

    /// Story 66: a bracket dragged across the court twists the quad until the fit puts measured lines beyond its
    /// own horizon. Those lines were measured, so this is the worst fit there is, never "not measurable".
    /// The far right tap (hand-worked true pixel (1179.4, 64.6)) moves to (800, 900), inside the triangle of the
    /// other three taps: a non-convex quad, which no camera looking at a flat court can produce.
    @Test func measuredLinesTheFitPutsBeyondItsHorizonAreAPoorFitAndInvalid() throws {
        var taps = CourtGeometry.doublesCorners.map { Self.pixel($0.point) }
        taps[2] = VideoPixel(x: 800, y: 900)
        let twisted = try CourtCalibration(doublesCorners: taps, camera: Self.binding)
        #expect(twisted.project(CourtIntersection.nearLeftDoubles.point) == nil, "premise: the fit cannot place the opposite tapped corner")
        #expect(twisted.project(CourtIntersection.nearServiceT.point) == nil, "premise: a measured line is unprojectable")

        let checked = twisted.checked(against: untapped())
        let check = try #require(checked.check)
        #expect(check.verdict == .poor)
        #expect(check.rmsePx == nil, "no residual is invented for a line that has no pixel")
        #expect(checked.validity(atMs: 0, current: Self.binding) == .invalid(.poorFit))
    }

    /// The doubles corners as a camera behind the near baseline sees them: a trapezoid, near side 1120 px wide
    /// along y = 1000, far side 480 px wide along y = 300, in `CourtGeometry.doublesCorners` order.
    static let trapezoid = [VideoPixel(x: 400, y: 1000), VideoPixel(x: 1520, y: 1000), VideoPixel(x: 1200, y: 300), VideoPixel(x: 720, y: 300)]

    /// Each set of taps is a quad no camera looking at a flat court can produce: two crossing sides (a bow tie) or
    /// a corner inside the triangle of the other three ((900, 800) is inside the two near corners and the far left one).
    static let twistedTaps: [String: [VideoPixel]] = {
        let t = trapezoid
        return [
            "far brackets swapped": [t[0], t[1], t[3], t[2]],
            "near brackets swapped": [t[1], t[0], t[2], t[3]],
            "far right bracket inside the other three": [t[0], t[1], VideoPixel(x: 900, y: 800), t[3]],
        ]
    }()

    @Test func theTrapezoidItselfIsNotTwisted() throws {
        let c = try CourtCalibration(doublesCorners: Self.trapezoid, camera: Self.binding)
        #expect(!c.isTwisted)
        #expect(c.validity(atMs: 0, current: Self.binding) == .valid)
        #expect(c.checked(against: []).check?.verdict == .notMeasurable)
        // By symmetry the centre mark of each baseline is midway between its corners.
        let mark = try #require(c.project(CourtIntersection.farCentreMark.point))
        #expect(abs(mark.x - 960) < 1e-9 && abs(mark.y - 300) < 1e-9)
    }

    /// On a camera looking straight down (the affine one above) a swapped pair of brackets puts the court centre
    /// exactly on the fit's horizon, so no homography with H[2][2] = 1 exists: refused outright, never valid either.
    @Test func aBowTieCentredOnTheCourtIsRefused() {
        let t = CourtGeometry.doublesCorners.map { Self.pixel($0.point) }
        #expect(throws: CalibrationError.degenerate) { try CourtCalibration(doublesCorners: [t[0], t[1], t[3], t[2]], camera: Self.binding) }
    }

    /// No line detector exists until V02, so nothing is measured for any calibration the app makes today. A
    /// twisted quad has to be caught from the taps alone: never valid, checked or not.
    @Test(arguments: twistedTaps.keys.sorted())
    func aTwistedCalibrationWithNothingMeasuredIsNotValid(_ name: String) throws {
        let taps = try #require(Self.twistedTaps[name])
        let twisted = try CourtCalibration(doublesCorners: taps, camera: Self.binding)
        #expect(CourtGeometry.doublesCorners.contains { twisted.project($0.point) == nil },
                "premise: the fit cannot place one of its own tapped corners")
        #expect(twisted.isTwisted)
        #expect(twisted.check == nil, "premise: nothing was checked")
        #expect(twisted.validity(atMs: 0, current: Self.binding) == .invalid(.poorFit))

        let unmeasured = twisted.checked(against: [])
        #expect(unmeasured.check?.verdict == .poor, "a twisted fit is poor before any line is measured")
        #expect(unmeasured.check?.rmsePx == nil, "no residual is invented")
        #expect(unmeasured.validity(atMs: 0, current: Self.binding) == .invalid(.poorFit))
    }

    /// A record stored `valid`, even with a good stored residual, does not outrank its own taps when reopened.
    @Test(arguments: twistedTaps.keys.sorted())
    func aStoredValidRecordWithTwistedTapsReopensInvalid(_ name: String) throws {
        let taps = try #require(Self.twistedTaps[name])
        for residual in [nil, Decimal(string: "0.4")] {
            let reopened = try reopen(status: .valid, residualPx: residual, taps: taps)
            #expect(reopened.isTwisted)
            #expect(reopened.validity(atMs: 0, current: Self.binding) == .invalid(.poorFit))
        }
    }

    /// The limit of the rule, stated: brackets one place round, or mirrored left to right, still make a convex
    /// quad whose homography places every court point. Only measured lines catch these.
    @Test func rotatedAndMirroredCornerOrdersAreOutOfReachOfTheTwistRule() throws {
        let t = CourtGeometry.doublesCorners.map { Self.pixel($0.point) }
        for taps in [[t[1], t[2], t[3], t[0]], [t[1], t[0], t[3], t[2]]] {
            let c = try CourtCalibration(doublesCorners: taps, camera: Self.binding)
            #expect(!c.isTwisted)
            #expect(c.validity(atMs: 0, current: Self.binding) == .valid)
            #expect(c.checked(against: []).check?.verdict == .notMeasurable)
            #expect(c.checked(against: untapped()).validity(atMs: 0, current: Self.binding) == .invalid(.poorFit))
        }
    }

    /// w = 1 - 0.1 y puts the horizon 10 m beyond the net: the far baseline has no pixel although the four near-half
    /// points are in front of it. A fit that cannot place a court line is twisted whatever was tapped.
    @Test func aFitThatPutsACourtLineBeyondItsHorizonIsTwisted() {
        let tapped = [CourtIntersection.nearLeftSingles, .nearRightSingles, .nearRightService, .nearLeftService].map(\.point)
        let tilted = Homography(matrix: [1, 0, 0, 0, 1, 0, 0, -0.1, 1])
        #expect(tapped.allSatisfy { tilted.project($0) != nil })
        #expect(tilted.project(CourtIntersection.farCentreMark.point) == nil)
        #expect(tilted.isTwisted(tapped: tapped))
        let level = Homography(matrix: [1, 0, 0, 0, 1, 0, 0, -0.05, 1])   // horizon at y = 20
        #expect(!level.isTwisted(tapped: tapped))
        #expect(level.isTwisted(tapped: tapped.dropLast() + [CourtPoint(x: 0, y: 25)]))
    }

    @Test func aRecordWithoutACameraFormatIsRefused() throws {
        let record = SessionCalibration(id: "c", method: .value, frameMs: 0, imagePoints: [], courtPoints: [], status: .valid,
                                        provenance: RecordProvenance(status: .manual, source: "user"))
        #expect(throws: CalibrationError.degenerate) { try CourtCalibration(record: record) }
    }

    @Test(arguments: ["5.44", "3.00000000000000000001", "1e127"])
    func aRecordedPoorFitRemainsInvalidAfterReopening(_ residual: String) throws {
        let residualPx = try #require(Decimal(string: residual))
        let reopened = try reopen(status: .valid, residualPx: residualPx)
        #expect(reopened.validity(atMs: 0, current: Self.binding) == .invalid(.poorFit))
        #expect(reopened.check?.verdict == .poor)
    }

    @Test(arguments: [SessionCalibrationStatus.invalid, .needsReview, .cameraMoved])
    func aRecordedUnusableStateRemainsInvalidWithoutMeasurements(_ status: SessionCalibrationStatus) throws {
        let reopened = try reopen(status: status)
        #expect(reopened.validity(atMs: 0, current: Self.binding).status == "invalid")
        #expect(reopened.check == nil, "A recorded status must not invent a measured residual")
    }

    @Test func recordedCameraMovementWithATimestampInvalidatesFromThatTime() throws {
        let reopened = try reopen(status: .cameraMoved, residualPx: 1, staleFromMs: 120_000)
        #expect(reopened.validity(atMs: 119_999, current: Self.binding) == .valid)
        #expect(reopened.validity(atMs: 120_000, current: Self.binding) == .invalid(.stale(fromMs: 120_000)))
    }

    /// `taps` are 1080p video pixels, stored the way a session record stores them: normalized by the frame.
    private func reopen(status: SessionCalibrationStatus, residualPx: Decimal? = nil,
                        staleFromMs: Int? = nil, taps: [VideoPixel]? = nil) throws -> CourtCalibration {
        let normalized: [(Double, Double)] = taps?.map { ($0.x / 1920, $0.y / 1080) }
            ?? [(0.125, 0.875), (0.875, 0.875), (0.875, 0.125), (0.125, 0.125)]
        let record = SessionCalibration(id: "recorded-court", method: .value, frameMs: 0,
                                        imagePoints: normalized.map { .init(x: Decimal($0.0), y: Decimal($0.1)) },
                                        courtPoints: CourtGeometry.doublesCorners.map { .init(x: Decimal($0.point.x), y: Decimal($0.point.y)) },
            residualPx: residualPx, status: status, staleFromMs: staleFromMs,
            camera: .init(lens: .wide, width: 1920, height: 1080, zoomFactor: "1"),
            provenance: .init(status: .manual, source: "user"))
        let data = try CanonicalJSON.encode(record)
        return try CourtCalibration(record: ContractCodec.decode(SessionCalibration.self, from: data))
    }

    @Test func tapsBecomeVideoPixelsBeforeFitting() throws {
        // A 1920 x 1080 frame shown aspect-fit in a 960 x 600 view: scale 0.5 with 30 pt bars top and bottom.
        let mapping = VideoFrameMapping(viewSize: PlaneSize(width: 960, height: 600), videoSize: PlaneSize(width: 1920, height: 1080))
        let taps = CourtGeometry.doublesCorners.map { mapping.viewPoint(fromVideo: Self.pixel($0.point)) }
        let pixels = try taps.map { try #require(mapping.videoPixel(fromView: $0)) }
        let c = try CourtCalibration(doublesCorners: pixels, camera: Self.binding)
        let t = try #require(c.unproject(Self.pixel(CourtIntersection.farServiceT.point)))
        #expect(abs(t.x) < 1e-9 && abs(t.y - 6.4) < 1e-9)
        #expect(mapping.videoPixel(fromView: PlanePoint(x: 10, y: 10)) == nil)   // the letterbox bar
    }
}
