// fixture-kind: jovra.fixture.calibration
import Foundation
import Testing
import JovraCore

/// spec/fixtures/calibration/C*.json (T13): every court geometry, homography, check, validity, tap-mapping and
/// placement-word vector the Python reference wrote must come out of JovraCore, floats within the fixture's
/// tolerance, refusals with the same code.
struct CalibrationRunner: FixtureRunner {
    let kind = "jovra.fixture.calibration"

    struct XY: Decodable { var x: Double; var y: Double }
    struct Size: Decodable { var width: Double; var height: Double }
    struct Tolerance: Decodable { var px: Double; var m: Double?; var homographyRelative: Double? }
    struct Projected: Decodable { var id: String; var court: XY; var pixel: XY? }
    struct Unprojected: Decodable { var id: String; var pixel: XY; var court: XY?; var truth: XY; var errorM: Double; var withinTenCm: Bool }
    struct FitExpected: Decodable { var homography: [Double]; var project: [Projected]; var unproject: [Unprojected] }
    struct Observation: Decodable { var court: XY; var pixel: XY }
    struct CheckExpected: Decodable { var verdict: String; var rmsePx: Double?; var thresholdPx: Double }
    struct Binding: Decodable { var lens: SessionCalibrationCameraLens; var width: Int; var height: Int; var zoomFactor: String }
    struct CheckRef: Decodable { var verdict: String }
    struct ValidityExpected: Decodable { var status: String; var reason: String?; var staleFromMs: Int? }
    struct Line: Decodable { var id: String; var kind: String; var from: XY; var to: XY }
    struct NamedPoint: Decodable { var id: String; var point: XY }
    struct Corners: Decodable { var doubles: [String]; var singles: [String] }
    struct Band: Decodable { var id: String; var fromM: Double; var toM: Double }
    struct Geometry: Decodable { var lines: [Line]; var intersections: [NamedPoint]; var tappedCorners: Corners; var depthBins: [Band] }
    struct Classified: Decodable { var depth: String; var serviceZone: String; var serviceBox: String; var inSingles: Bool; var inDoubles: Bool }
    struct Described: Decodable { var depth: String; var direction: String; var wide: Bool; var result: String; var english: String }

    struct Case: Decodable {
        var op: String
        var name: String
        var record: SessionCalibration?
        var imagePoints: [XY]?
        var courtPoints: [XY]?
        var expectedError: String?
        var tolerance: Tolerance?
        // check
        var frameHeight: Int?
        var observations: [Observation]?
        // validity
        var binding: Binding?
        var current: Binding?
        var staleFromMs: Int?
        var atMs: Int?
        var recordedStatus: SessionCalibrationStatus?
        var check: CheckRef?
        // mapping
        var gravity: VideoGravity?
        var view: Size?
        var video: Size?
        var point: XY?
        // describe
        var landing: XY?
        var hitterX: Double?
        var result: PlacementResult?
        var doubles: Bool?
        var expected: Expected?

        enum Expected {
            case fit(FitExpected), check(CheckExpected), validity(ValidityExpected), map(XY?), geometry(Geometry)
            case classify(Classified), describe(Described)
        }

        enum CodingKeys: String, CodingKey {
            case op, name, record, imagePoints, courtPoints, expectedError, tolerance, frameHeight, observations, binding,
                 current, staleFromMs, atMs, recordedStatus, check, gravity, view, video, point, landing, hitterX, result, doubles, expected
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            op = try c.decode(String.self, forKey: .op)
            name = try c.decode(String.self, forKey: .name)
            record = try c.decodeIfPresent(SessionCalibration.self, forKey: .record)
            imagePoints = try c.decodeIfPresent([XY].self, forKey: .imagePoints)
            courtPoints = try c.decodeIfPresent([XY].self, forKey: .courtPoints)
            expectedError = try c.decodeIfPresent(String.self, forKey: .expectedError)
            tolerance = try c.decodeIfPresent(Tolerance.self, forKey: .tolerance)
            frameHeight = try c.decodeIfPresent(Int.self, forKey: .frameHeight)
            observations = try c.decodeIfPresent([Observation].self, forKey: .observations)
            binding = try c.decodeIfPresent(Binding.self, forKey: .binding)
            current = try c.decodeIfPresent(Binding.self, forKey: .current)
            staleFromMs = try c.decodeIfPresent(Int.self, forKey: .staleFromMs)
            atMs = try c.decodeIfPresent(Int.self, forKey: .atMs)
            recordedStatus = try c.decodeIfPresent(SessionCalibrationStatus.self, forKey: .recordedStatus)
            check = try c.decodeIfPresent(CheckRef.self, forKey: .check)
            gravity = try c.decodeIfPresent(VideoGravity.self, forKey: .gravity)
            view = try c.decodeIfPresent(Size.self, forKey: .view)
            video = try c.decodeIfPresent(Size.self, forKey: .video)
            point = try c.decodeIfPresent(XY.self, forKey: .point)
            landing = try c.decodeIfPresent(XY.self, forKey: .landing)
            hitterX = try c.decodeIfPresent(Double.self, forKey: .hitterX)
            result = try c.decodeIfPresent(PlacementResult.self, forKey: .result)
            doubles = try c.decodeIfPresent(Bool.self, forKey: .doubles)
            guard c.contains(.expected) else { expected = nil; return }
            switch op {
            case "fit": expected = .fit(try c.decode(FitExpected.self, forKey: .expected))
            case "check": expected = .check(try c.decode(CheckExpected.self, forKey: .expected))
            case "validity": expected = .validity(try c.decode(ValidityExpected.self, forKey: .expected))
            case "viewToVideo", "videoToView": expected = .map(try c.decodeIfPresent(XY.self, forKey: .expected))
            case "geometry": expected = .geometry(try c.decode(Geometry.self, forKey: .expected))
            case "classify": expected = .classify(try c.decode(Classified.self, forKey: .expected))
            case "describe": expected = .describe(try c.decode(Described.self, forKey: .expected))
            default: expected = nil
            }
        }
    }

    private struct Fixture: Decodable { var id: String; var cases: [Case] }

    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        var fits = 0
        for c in fixture.cases {
            let label = "\(fixture.id) '\(c.name)'"
            switch (c.op, c.expected) {
            case ("fit", _):
                try runFit(c, label: label)
                fits += 1
            case ("check", .check(let expected)?):
                let image = try #require(c.imagePoints).map { VideoPixel(x: $0.x, y: $0.y) }
                let court = try #require(c.courtPoints).map { CourtPoint(x: $0.x, y: $0.y) }
                let homography = try Homography.fit(image: image, court: court)
                let observations = try #require(c.observations).map {
                    CalibrationObservation(court: CourtPoint(x: $0.court.x, y: $0.court.y), pixel: VideoPixel(x: $0.pixel.x, y: $0.pixel.y))
                }
                let result = CalibrationCheck(homography: homography, observations: observations, frameHeight: try #require(c.frameHeight))
                #expect(result.verdict.rawValue == expected.verdict, "\(label)")
                #expect(close(result.rmsePx, expected.rmsePx, try #require(c.tolerance).px), "\(label): RMSE \(String(describing: result.rmsePx))")
                #expect(abs(result.thresholdPx - expected.thresholdPx) <= 1e-9, "\(label)")
            case ("validity", .validity(let expected)?):
                let b = try #require(c.binding), now = try #require(c.current)
                let verdict = c.check.flatMap { CalibrationCheck.Verdict(rawValue: $0.verdict) }
                let validity = CalibrationValidity.evaluate(
                    binding: CameraBinding(lens: b.lens, width: b.width, height: b.height, zoomFactor: try #require(Decimal(string: b.zoomFactor))),
                    current: CameraBinding(lens: now.lens, width: now.width, height: now.height, zoomFactor: try #require(Decimal(string: now.zoomFactor))),
                    checkVerdict: verdict, staleFromMs: c.staleFromMs, atMs: try #require(c.atMs),
                    recordedStatus: c.recordedStatus)
                #expect(validity.status == expected.status, "\(label)")
                #expect(validity.reasonCode == expected.reason, "\(label)")
                if case .invalid(.stale(let from)) = validity { #expect(from == expected.staleFromMs, "\(label)") }
            case ("viewToVideo", .map(let expected)), ("videoToView", .map(let expected)):
                let view = try #require(c.view), video = try #require(c.video), point = try #require(c.point)
                let mapping = VideoFrameMapping(viewSize: PlaneSize(width: view.width, height: view.height),
                                                videoSize: PlaneSize(width: video.width, height: video.height),
                                                gravity: try #require(c.gravity))
                let got: (x: Double, y: Double)?
                if c.op == "viewToVideo" {
                    got = mapping.videoPixel(fromView: PlanePoint(x: point.x, y: point.y)).map { ($0.x, $0.y) }
                } else {
                    let p = mapping.viewPoint(fromVideo: VideoPixel(x: point.x, y: point.y))
                    got = (p.x, p.y)
                }
                let tol = try #require(c.tolerance).px
                #expect((got == nil) == (expected == nil), "\(label)")
                if let got, let expected { #expect(abs(got.x - expected.x) <= tol && abs(got.y - expected.y) <= tol, "\(label): \(got)") }
            case ("geometry", .geometry(let expected)?):
                checkGeometry(expected, label: label)
            case ("classify", .classify(let expected)?):
                let p = try #require(c.point)
                let point = CourtPoint(x: p.x, y: p.y)
                #expect(CourtGeometry.depthBin(y: p.y).rawValue == expected.depth, "\(label)")
                #expect(CourtGeometry.serviceZone(x: p.x).rawValue == expected.serviceZone, "\(label)")
                #expect(CourtGeometry.serviceBox(of: point).rawValue == expected.serviceBox, "\(label)")
                #expect(CourtGeometry.contains(point, doubles: false) == expected.inSingles, "\(label)")
                #expect(CourtGeometry.contains(point, doubles: true) == expected.inDoubles, "\(label)")
            case ("describe", .describe(let expected)?):
                let l = try #require(c.landing)
                let words = PlacementWords(landing: CourtPoint(x: l.x, y: l.y), hitterX: c.hitterX,
                                           result: try #require(c.result), doubles: try #require(c.doubles))
                #expect(words.depth.rawValue == expected.depth, "\(label)")
                #expect(words.direction.rawValue == expected.direction, "\(label)")
                #expect(words.wide == expected.wide, "\(label)")
                #expect(words.result.rawValue == expected.result, "\(label)")
                #expect(words.englishSentence == expected.english, "\(label)")
            default:
                Issue.record("Unknown calibration operation \(c.op) in \(fixture.id)")
            }
        }
        print("calibration vectors \(fixture.id): \(fixture.cases.count) (fits \(fits))")
    }

    private func runFit(_ c: Case, label: String) throws {
        let image: [VideoPixel], court: [CourtPoint]
        var calibration: CourtCalibration?
        if let record = c.record {
            let made = try CourtCalibration(record: record)
            calibration = made
            image = made.imagePoints
            court = made.courtPoints
        } else {
            image = try #require(c.imagePoints).map { VideoPixel(x: $0.x, y: $0.y) }
            court = try #require(c.courtPoints).map { CourtPoint(x: $0.x, y: $0.y) }
        }
        let homography: Homography
        do {
            homography = try calibration?.homography ?? Homography.fit(image: image, court: court)
        } catch let error as CalibrationError {
            #expect(error.rawValue == c.expectedError, "\(label): refused with \(error.rawValue)")
            return
        }
        #expect(c.expectedError == nil, "\(label): expected \(c.expectedError ?? "") but fitted")
        guard case .fit(let expected)? = c.expected, let tolerance = c.tolerance else { return }
        let px = tolerance.px, m = tolerance.m ?? 1e-6, relative = tolerance.homographyRelative ?? 1e-7
        for (got, want) in zip(homography.matrix, expected.homography) {
            #expect(abs(got - want) <= relative * max(1, abs(want)), "\(label): H \(homography.matrix) vs \(expected.homography)")
        }
        if image.count == 4 {
            for (tap, point) in zip(image, court) {
                let back = try #require(homography.project(point))
                #expect(abs(back.x - tap.x) <= 1e-6 && abs(back.y - tap.y) <= 1e-6, "\(label): tap \(tap) reprojects to \(back)")
            }
        }
        for p in expected.project {
            let got = homography.project(CourtPoint(x: p.court.x, y: p.court.y))
            #expect((got == nil) == (p.pixel == nil), "\(label): \(p.id)")
            if let got, let want = p.pixel { #expect(abs(got.x - want.x) <= px && abs(got.y - want.y) <= px, "\(label): \(p.id) -> \(got)") }
        }
        for p in expected.unproject {
            let got = homography.unproject(VideoPixel(x: p.pixel.x, y: p.pixel.y))
            #expect((got == nil) == (p.court == nil), "\(label): \(p.id)")
            if let got, let want = p.court {
                #expect(abs(got.x - want.x) <= m && abs(got.y - want.y) <= m, "\(label): \(p.id) -> \(got)")
                let error = got.distance(to: CourtPoint(x: p.truth.x, y: p.truth.y))
                #expect(abs(error - p.errorM) <= m, "\(label): \(p.id) error \(error)")
                #expect((error <= 0.10) == p.withinTenCm, "\(label): \(p.id) within 0.10 m")
            }
        }
    }

    private func checkGeometry(_ expected: Geometry, label: String) {
        let lines = CourtGeometry.lines
        #expect(lines.map(\.id) == expected.lines.map(\.id), "\(label): line ids")
        for (line, want) in zip(lines, expected.lines) {
            #expect(line.kind.rawValue == want.kind, "\(label): \(line.id) kind")
            #expect(abs(line.from.x - want.from.x) < 1e-9 && abs(line.from.y - want.from.y) < 1e-9 &&
                    abs(line.to.x - want.to.x) < 1e-9 && abs(line.to.y - want.to.y) < 1e-9, "\(label): \(line.id)")
        }
        #expect(CourtIntersection.allCases.map(\.rawValue) == expected.intersections.map(\.id), "\(label): intersections")
        for (point, want) in zip(CourtIntersection.allCases, expected.intersections) {
            #expect(abs(point.point.x - want.point.x) < 1e-9 && abs(point.point.y - want.point.y) < 1e-9, "\(label): \(want.id)")
        }
        #expect(CourtGeometry.doublesCorners.map(\.rawValue) == expected.tappedCorners.doubles, "\(label)")
        #expect(CourtGeometry.singlesCorners.map(\.rawValue) == expected.tappedCorners.singles, "\(label)")
        #expect(CourtGeometry.depthBands.map(\.bin.rawValue) == expected.depthBins.map(\.id), "\(label)")
        for (band, want) in zip(CourtGeometry.depthBands, expected.depthBins) {
            #expect(abs(band.fromM - want.fromM) < 1e-9 && abs(band.toM - want.toM) < 1e-9, "\(label): \(want.id)")
        }
    }

    private func close(_ a: Double?, _ b: Double?, _ tolerance: Double) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a - b) <= tolerance
        default: false
        }
    }
}
