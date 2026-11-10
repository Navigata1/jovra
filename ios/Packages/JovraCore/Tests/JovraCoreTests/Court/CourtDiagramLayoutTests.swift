import Foundation
import Testing
import JovraCore

/// T13 acceptance: the diagram's line positions match CourtGeometry; the centre service line runs only through the
/// service boxes, and the doubles alleys are drawn. Expected positions are worked by hand from ITF dimensions.
@Suite("CourtDiagramLayout")
struct CourtDiagramLayoutTests {
    // Full court at 13.37 m drawn (10.97 + 2 x 1.2 run-off) over 267.4 pt: exactly 20 pt per metre.
    let full = CourtDiagramLayout(variant: .full, width: 267.4)

    private func segment(_ id: String, in layout: CourtDiagramLayout) throws -> CourtDiagramLayout.Segment {
        try #require(layout.segments.first { $0.id == id })
    }

    @Test func scaleAndHeightFollowTheCourt() {
        #expect(abs(full.scale - 20) < 1e-9)
        // 23.77 m + 2 x 1.6 m run-off = 26.97 m tall.
        #expect(abs(full.size.height - 539.4) < 1e-9)
    }

    @Test func centreServiceLineRunsOnlyBetweenTheServiceLines() throws {
        let centre = try segment("centreServiceLine", in: full)
        let near = try segment("nearServiceLine", in: full), far = try segment("farServiceLine", in: full)
        // Service lines at y = +/- 6.40 m: 1.6 + 11.885 - 6.40 = 7.085 m and 1.6 + 11.885 + 6.40 = 19.885 m from the top.
        #expect(abs(far.from.y - 141.7) < 1e-9 && abs(near.from.y - 397.7) < 1e-9)
        let top = min(centre.from.y, centre.to.y), bottom = max(centre.from.y, centre.to.y)
        #expect(abs(top - far.from.y) < 1e-9 && abs(bottom - near.from.y) < 1e-9)
        // Centre x: 1.2 + 5.485 = 6.685 m from the left edge.
        #expect(abs(centre.from.x - 133.7) < 1e-9 && centre.from.x == centre.to.x)
        // The only other lines on x = 0 are the 10 cm centre marks at the baselines.
        let onCentre = full.segments.filter { abs($0.from.x - 133.7) < 1e-9 && $0.from.x == $0.to.x }
        #expect(Set(onCentre.map(\.kind)) == [.centreServiceLine, .centreMark])
        for mark in onCentre where mark.kind == .centreMark { #expect(abs(abs(mark.to.y - mark.from.y) - 2) < 1e-9) }
    }

    @Test func doublesAlleysAreDrawnOutsideTheSinglesSidelines() throws {
        let leftDoubles = try segment("leftDoublesSideline", in: full), leftSingles = try segment("leftSinglesSideline", in: full)
        let rightDoubles = try segment("rightDoublesSideline", in: full), rightSingles = try segment("rightSinglesSideline", in: full)
        // Alleys are 1.37 m wide: 27.4 pt at 20 pt per metre.
        #expect(abs((leftSingles.from.x - leftDoubles.from.x) - 27.4) < 1e-9)
        #expect(abs((rightDoubles.from.x - rightSingles.from.x) - 27.4) < 1e-9)
        #expect(abs(leftDoubles.from.x - 24) < 1e-9 && abs(rightDoubles.from.x - 243.4) < 1e-9)
        // Sidelines run baseline to baseline.
        #expect(abs(abs(leftDoubles.to.y - leftDoubles.from.y) - 475.4) < 1e-9)
        #expect(full.segments.count == CourtGeometry.lines.count)
    }

    @Test func everySegmentIsTheGeometryLineMapped() {
        for (segment, line) in zip(full.segments, CourtGeometry.lines) {
            #expect(segment.id == line.id)
            #expect(segment.from == full.point(line.from) && segment.to == full.point(line.to))
        }
    }

    @Test func depthBandsSplitTheFarHalfAtTheServiceLine() throws {
        let bands = full.bands
        #expect(bands.map(\.bin) == [.short, .deep])
        let short = bands[0], deep = bands[1]
        #expect(abs(short.size.height - 128) < 1e-9 && abs(deep.size.height - 109.7) < 1e-9)   // 6.40 m and 5.485 m
        #expect(abs(deep.origin.y - 32) < 1e-9)   // the far baseline, 1.6 m from the top
    }

    @Test func serviceBoxVariantDrawsOnlyThatBoxWithThirds() throws {
        let deuce = CourtDiagramLayout(variant: .serviceBox(.deuce), width: 205.75)   // 4.115 m at 50 pt per metre
        #expect(abs(deuce.scale - 50) < 1e-9 && abs(deuce.size.height - 320) < 1e-9)
        #expect(Set(deuce.segments.map(\.id)) == ["leftSinglesSideline", "farServiceLine", "centreServiceLine", "net"])
        #expect(deuce.zones.map(\.zone) == [.t, .body, .wide])
        // T sits against the centre service line (the right edge for the deuce box as the server sees it).
        let t = deuce.zones[0]
        #expect(abs(t.origin.x + t.size.width - 205.75) < 1e-9)
        let ad = CourtDiagramLayout(variant: .serviceBox(.ad), width: 205.75)
        #expect(abs(ad.zones[0].origin.x) < 1e-9)
    }

    @Test func outliersClampToTheEdgeAndSayItAndTapsRoundTrip() {
        let inside = full.place(CourtPoint(x: -3, y: 10))
        #expect(!inside.clamped)
        let far = full.place(CourtPoint(x: 20, y: 30))
        #expect(far.clamped && abs(far.point.x - 267.4) < 1e-9 && abs(far.point.y) < 1e-9)
        let back = full.court(full.point(CourtPoint(x: 1.5, y: -4.25)))
        #expect(abs(back.x - 1.5) < 1e-9 && abs(back.y + 4.25) < 1e-9)
    }
}
