import Foundation
import JovraBenchmark
@testable import JovraLabelKit
import Testing

@Suite("Label document edits")
struct LabelDocumentTests {
    static let recordingHash = "d9db095691ae78dbfbbc8d3bed01cbe609b1c332c9b004658491817690f0b130"

    static func ms(_ value: Int64) -> RationalTime { RationalTime(value: value, timescale: 1000) }

    static func empty() throws -> LabelDocument {
        let recording = BenchmarkLabels.Recording(sha256: recordingHash, byteSize: 1_048_576, duration: RationalTime(value: 120, timescale: 1),
                                                  width: 1280, height: 720, frameRate: .init(num: 30, den: 1), variableFrameRate: false)
        return LabelDocument(labels: try BenchmarkLabels(recording: recording, labelledBy: .init(method: .human, tool: LabelSession.tool)))
    }

    static func refusal(_ body: () throws -> LabelDocument) -> String? {
        do {
            _ = try body()
            return nil
        } catch LabelDocument.Refusal.because(let reason) {
            return reason
        } catch {
            return "\(error)"
        }
    }

    @Test("hits stay in time order whatever order they are marked in, and a second hit on the same frame is refused")
    func hits() throws {
        var document = try Self.empty()
        document = try document.markingHit(at: Self.ms(6500), player: .far)
        document = try document.markingHit(at: Self.ms(5000), player: .near)
        document = try document.markingHit(at: Self.ms(5000), player: .far)
        #expect(document.labels.hits.map(\.time) == [Self.ms(5000), Self.ms(5000), Self.ms(6500)])
        #expect(document.labels.hits.map(\.player) == [.far, .near, .far])
        #expect(Self.refusal { try document.markingHit(at: Self.ms(5000), player: .near) } == "This frame already has a hit by the near player.")
        #expect(document.labels.problems().isEmpty)
    }

    @Test("a stroke type lands on the one hit it names and can be cleared")
    func strokes() throws {
        var document = try Self.empty().markingHit(at: Self.ms(5000), player: .near).markingHit(at: Self.ms(5000), player: .far)
        document = document.settingStroke(.backhand, at: Self.ms(5000), player: .far)
        #expect(document.labels.hits.map(\.stroke) == [.backhand, nil])
        #expect(document.labels.counts.strokes == 1)
        document = document.settingStroke(nil, at: Self.ms(5000), player: .far)
        #expect(document.labels.counts.strokes == 0)
    }

    @Test("a bounce keeps its point to six places, one per frame, and toggles between in play and dead ball")
    func bounces() throws {
        var document = try Self.empty().markingBounce(at: Self.ms(7000), point: ImagePoint(x: 0.25, y: 0.5))
        document = document.markingBounce(at: Self.ms(5500), point: ImagePoint(x: 0.123456789, y: 1.4))
        #expect(document.labels.bounces.map(\.time) == [Self.ms(5500), Self.ms(7000)])
        #expect(document.labels.bounces[0].imagePoint == ImagePoint(x: 0.123457, y: 1))
        #expect(document.labels.bounces[0].inPlay)
        document = document.togglingInPlay(at: Self.ms(5500))
        #expect(!document.labels.bounces[0].inPlay)
        // Marking the same frame again moves the point and keeps the flag.
        document = document.markingBounce(at: Self.ms(5500), point: ImagePoint(x: 0.3, y: 0.3))
        #expect(document.labels.bounces.count == 2)
        #expect(document.labels.bounces[0].imagePoint == ImagePoint(x: 0.3, y: 0.3))
        #expect(!document.labels.bounces[0].inPlay)
    }

    @Test("corners fill far left, far right, near right, near left; the first camera position starts with the recording")
    func corners() throws {
        var document = try Self.empty()
        #expect(document.nextCorner == 0)
        document = document.placingCorner(ImagePoint(x: 0.3, y: 0.2), at: Self.ms(40_000))
        document = document.placingCorner(nil, at: Self.ms(40_000))
        document = document.placingCorner(ImagePoint(x: 0.95, y: 0.9), at: Self.ms(40_000))
        #expect(document.nextCorner == 3)
        document = document.placingCorner(ImagePoint(x: 0.05, y: 0.9), at: Self.ms(40_000))
        #expect(document.nextCorner == 0)
        #expect(document.labels.cameraPositions.count == 1)
        #expect(document.labels.cameraPositions[0].from == Self.ms(0))
        #expect(document.labels.cameraPositions[0].corners.points == [ImagePoint(x: 0.3, y: 0.2), nil, ImagePoint(x: 0.95, y: 0.9), ImagePoint(x: 0.05, y: 0.9)])

        document = try document.startingCameraPosition(at: Self.ms(70_000))
        document = document.placingCorner(ImagePoint(x: 0.31, y: 0.21), at: Self.ms(80_000))
        #expect(document.labels.cameraPositions.map(\.from) == [Self.ms(0), Self.ms(70_000)])
        #expect(document.labels.cameraPositions[1].corners.points == [ImagePoint(x: 0.31, y: 0.21), nil, nil, nil])
        // A corner marked before the move still belongs to the first position.
        document = document.placingCorner(ImagePoint(x: 0.7, y: 0.2), at: Self.ms(10_000))
        #expect(document.labels.cameraPositions[0].corners.points[1] == ImagePoint(x: 0.7, y: 0.2))
        #expect(Self.refusal { try document.startingCameraPosition(at: Self.ms(70_000)) } == "A camera position already starts on this frame.")
        #expect(document.labels.problems().isEmpty)
    }

    @Test("a rally opens with [ and closes with ]; overlaps and backwards rallies are refused with the reason")
    func rallies() throws {
        var document = try Self.empty()
        #expect(Self.refusal { try document.closingRally(at: Self.ms(9000)) } == "No rally is open. Press [ on the frame where the rally starts.")
        document = try document.openingRally(at: Self.ms(4000))
        #expect(document.openRallyStart == Self.ms(4000))
        #expect(document.labels.rallies.isEmpty)
        #expect(Self.refusal { try document.openingRally(at: Self.ms(5000)) } == "A rally is already open since 0:04.000. Press ] where it ends.")
        #expect(Self.refusal { try document.closingRally(at: Self.ms(4000)) } == "A rally ends after it starts (it started at 0:04.000).")
        document = try document.closingRally(at: Self.ms(9000))
        #expect(document.labels.rallies == [.init(start: Self.ms(4000), end: Self.ms(9000))])
        #expect(document.openRallyStart == nil)
        #expect(Self.refusal { try document.openingRally(at: Self.ms(6000)) } == "This frame is inside a rally that is already labelled.")
        document = try document.openingRally(at: Self.ms(2000))
        #expect(Self.refusal { try document.closingRally(at: Self.ms(5000)) } == "This would overlap a rally that is already labelled.")
        document = try document.closingRally(at: Self.ms(3500))
        #expect(document.labels.rallies.map(\.start) == [Self.ms(2000), Self.ms(4000)])
        #expect(document.labels.problems().isEmpty)
    }

    @Test("an open rally is stored as the last rally with no end and comes back as an open rally")
    func openRallyIsKept() throws {
        var document = try Self.empty().openingRally(at: Self.ms(4000)).closingRally(at: Self.ms(9000))
        document = try document.openingRally(at: Self.ms(20_000))
        let stored = document.stored
        #expect(stored.rallies.last == .init(start: Self.ms(20_000), end: nil))
        #expect(stored.problems().isEmpty)
        let reopened = LabelDocument(labels: try JSONDecoder().decode(BenchmarkLabels.self, from: stored.encoded()))
        #expect(reopened.openRallyStart == Self.ms(20_000))
        #expect(reopened.labels.rallies == [.init(start: Self.ms(4000), end: Self.ms(9000))])
        #expect(reopened == document)
    }

    @Test("candidates: a hit confirms the nearest pending one, R rejects it, and deleting the hit makes it pending again")
    func candidates() throws {
        var document = try Self.empty().markingHit(at: Self.ms(1000), player: .near)
        document = document.offering(candidates: [Self.ms(5030), Self.ms(1010), Self.ms(5600), Self.ms(5600), Self.ms(9000)], method: "jovra.audioOnsets.v1")
        let items = { (d: LabelDocument) in d.labels.hitCandidates?.items.map(\.decision) ?? [] }
        #expect(document.labels.hitCandidates?.items.map(\.time) == [Self.ms(1010), Self.ms(5030), Self.ms(5600), Self.ms(9000)])
        #expect(items(document) == [.confirmed, .pending, .pending, .pending])       // 1.010 sits on the hit already labelled

        document = try document.markingHit(at: Self.ms(5000), player: .far)
        #expect(items(document) == [.confirmed, .confirmed, .pending, .pending])
        #expect(document.pendingCandidate(near: Self.ms(5500))?.time == Self.ms(5600))
        document = try document.rejectingCandidate(near: Self.ms(5500))
        #expect(items(document) == [.confirmed, .confirmed, .rejected, .pending])
        #expect(Self.refusal { try document.rejectingCandidate(near: Self.ms(7000)) } == "There is no pending candidate on this frame. Press N for the next one.")
        #expect(document.candidateCounts() == (1, 2, 1))

        document = document.deleting(.hit(time: Self.ms(5000), player: .far))
        #expect(items(document) == [.confirmed, .pending, .rejected, .pending])
        #expect(document.labels.hits.count == 1)
        #expect(document.labels.problems().isEmpty)
    }

    @Test("a hit far from every candidate leaves them alone, and a document without candidates still takes hits")
    func hitsWithoutCandidates() throws {
        let plain = try Self.empty().markingHit(at: Self.ms(5000), player: .near)
        #expect(plain.labels.hitCandidates == nil)
        let offered = plain.offering(candidates: [Self.ms(9000)], method: "jovra.audioOnsets.v1")
        #expect(try offered.markingHit(at: Self.ms(7000), player: .near).labels.hitCandidates?.items.map(\.decision) == [.pending])
    }

    @Test("landmarks list every label in time order; deleting removes exactly the selected one")
    func landmarksAndDelete() throws {
        var document = try Self.empty().markingHit(at: Self.ms(5000), player: .near)
        document = document.markingBounce(at: Self.ms(5500), point: ImagePoint(x: 0.5, y: 0.5))
        document = try document.openingRally(at: Self.ms(4000)).closingRally(at: Self.ms(9000))
        document = document.placingCorner(ImagePoint(x: 0.1, y: 0.1), at: Self.ms(100))
        #expect(document.landmarks == [.cameraPosition(from: Self.ms(0)), .rally(start: Self.ms(4000)), .hit(time: Self.ms(5000), player: .near), .bounce(time: Self.ms(5500))])
        for landmark in document.landmarks {
            #expect(document.contains(landmark))
            let after = document.deleting(landmark)
            #expect(!after.contains(landmark))
            #expect(after.landmarks.count == 3)
        }
    }

    @Test("times read as minutes, seconds and milliseconds")
    func clock() {
        #expect(Self.ms(0).clock == "0:00.000")
        #expect(Self.ms(65_020).clock == "1:05.020")
        #expect(RationalTime(value: 115, timescale: 60).clock == "0:01.916")
        #expect(Self.ms(4_277_700).clock == "71:17.700")
    }
}
