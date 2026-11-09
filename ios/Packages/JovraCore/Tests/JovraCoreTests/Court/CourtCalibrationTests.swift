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

    @Test func aRecordWithoutACameraFormatIsRefused() throws {
        let record = SessionCalibration(id: "c", method: .value, frameMs: 0, imagePoints: [], courtPoints: [], status: .valid,
                                        provenance: RecordProvenance(status: .manual, source: "user"))
        #expect(throws: CalibrationError.degenerate) { try CourtCalibration(record: record) }
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
