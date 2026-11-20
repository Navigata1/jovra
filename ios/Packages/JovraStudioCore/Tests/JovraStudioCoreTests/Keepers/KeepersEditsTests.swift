import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// The player's keeper edits (spec KeeperSelector: select, exclude, annotate, markBroll; stories 103, 105, 106, 108) as
/// a later plan sees them. Every expected value is a hand-worked literal.
@Suite("Keepers: select, exclude, annotate and markBroll")
struct KeepersEditsTests {
    /// Six points 10 s apart (times in tenths of a second as the vectors write them), a lesson clip on p1, a Mark at
    /// 21.0 s inside p2, all seen by one 60 fps reference camera.
    static let camera = KeeperSource(sourceId: "camera-1", isPrimary: true, syncState: "reference", offsetUs: 0,
                                     rate: KeeperSyncRate(num: 1, den: 1), fps: StudioFrameRate(num: 60, den: 1), frameCount: 3_600)

    static func point(_ id: String, _ start: Int, _ index: Int, rally: Int?, _ prov: Provenance = .reviewed,
                      bp: Bool = false, mp: Bool = false) -> KeeperPoint {
        KeeperPoint(eventId: id, index: index, startUs: start * 100_000, endUs: (start + 40) * 100_000, rallyLength: rally,
                    provenance: prov, breakPoint: bp, matchPoint: mp)
    }

    static let project = KeeperProject(
        sessionDurationUs: 60_000_000, sources: [camera],
        points: [point("p1", 100, 0, rally: 3, .manual), point("p2", 200, 1, rally: 12), point("p3", 300, 2, rally: 7, .estimated),
                 point("p4", 400, 3, rally: 2, bp: true), point("p5", 500, 4, rally: 9, .manual), point("p6", 550, 5, rally: nil, mp: true)],
        shots: [KeeperShot(eventId: "p2", atUs: 22_000_000, provenance: .reviewed)],
        marks: [KeeperMark(markId: "m-1", atUs: 21_000_000)],
        lessonClips: [KeeperLessonClip(clipId: "clip-p1", lessonId: "lesson-0909", eventId: "p1")])

    static let allKeepers = ["k-p1", "k-p2", "k-p3", "k-p4", "k-p5", "k-p6"]

    /// Options that make every profile offer as much as it can, so an exclusion is the only thing that can remove a
    /// keeper from its order.
    static func generousOptions(_ profile: KeeperProfile) -> KeeperRankOptions {
        switch profile {
        case .coachCut:
            KeeperRankOptions(cues: allKeepers.map { .init(cueId: "cue-\($0)", keeperId: $0, provenance: .reviewed) })
        case .progressStory:
            KeeperRankOptions(dates: Dictionary(uniqueKeysWithValues: allKeepers.map { ($0, "2026-10-07") }), selectionRule: "all")
        default:
            KeeperRankOptions()
        }
    }

    @Test("an excluded keeper never appears in any profile's order, in the plan input or in the stored catalog")
    func excludedKeeperIsNeverOffered() throws {
        let candidates = try KeeperSelector.candidates(Self.project)
        #expect(candidates.keepers.map(\.keeperId) == Self.allKeepers)
        for excluded in Self.allKeepers {
            var edits = KeeperEdits()
            #expect(edits.exclude(keeper: excluded) == [excluded])
            let input = KeeperSelector.planInput(candidates, edits: edits)
            #expect(!input.matchFootageIds.contains(excluded))
            for profile in KeeperProfile.allCases {
                let ranked = try KeeperSelector.rank(profile, input, options: Self.generousOptions(profile))
                #expect(!ranked.order.map(\.id).contains(excluded), "\(profile.rawValue) offered \(excluded)")
                // the same through the ranking's own exclusion list over the unedited candidates
                var options = Self.generousOptions(profile)
                options.excluded = [excluded]
                #expect(!(try KeeperSelector.rank(profile, candidates.keepers, options: options)).order.map(\.id).contains(excluded))
            }
            let catalog = KeeperSelector.catalog(candidates, eventVersion: 4, projectId: "real-court-day", revision: 2,
                                                 sample: false, syncRevision: 1, edits: edits)
            #expect(catalog.keepers.count == 5 && !catalog.keepers.map(\.keeperId).contains(excluded))
        }
        // Match Broadcast offers every point when nothing is excluded, so the check above is not vacuous.
        let all = try KeeperSelector.rank(.matchBroadcast, KeeperSelector.planInput(candidates, edits: KeeperEdits()))
        #expect(all.order.map(\.id) == Self.allKeepers)
    }

    @Test("B-roll marked as not from this match is never offered as match footage by a later plan (planner input)")
    func nonMatchBrollIsNeverMatchFootage() throws {
        let candidates = try KeeperSelector.candidates(Self.project)
        var edits = KeeperEdits()
        try edits.markBroll(KeeperBroll(brollId: "b-01", sourceId: "broll-1", window: StudioFrameWindow(inFrame: 0, outFrame: 1800),
                                        depictsThisMatch: true, peopleVisible: ["jon"], chapter: "arrival",
                                        description: "Walking to the court"))
        try edits.markBroll(KeeperBroll(brollId: "b-old", sourceId: "broll-2", window: StudioFrameWindow(inFrame: 0, outFrame: 900),
                                        depictsThisMatch: false, chapter: "arrival", origin: .capturedOtherDay,
                                        description: "Last week's warm-up"))
        try edits.markBroll(KeeperBroll(brollId: "b-02", sourceId: "broll-3", window: StudioFrameWindow(inFrame: 0, outFrame: 2700),
                                        depictsThisMatch: true, chapter: "after"))
        let input = KeeperSelector.planInput(candidates, edits: edits)
        #expect(input.matchFootageIds == Self.allKeepers)
        #expect(input.courtMemoriesBrolls.map(\.brollId) == ["b-01", "b-02"])
        // Court Memories: arrival b-01, the moments (p1 lesson, p2 Mark, p4 break point, p6 match point), after b-02
        let memories = try KeeperSelector.rank(.courtMemories, input)
        #expect(memories.order.map(\.id) == ["b-01", "k-p1", "k-p2", "k-p4", "k-p6", "b-02"])
        #expect(memories.order.filter { $0.chapter == "match" }.allSatisfy { $0.kind == .keeper })
        // even when a caller lists it explicitly, the other day's clip is not taken into a chapter
        let forced = try KeeperSelector.rank(.courtMemories, input, options: KeeperRankOptions(
            brolls: [.init(brollId: "b-old", chapter: "arrival"), .init(brollId: "b-02", chapter: "after")]))
        #expect(forced.order.map(\.id) == ["k-p1", "k-p2", "k-p4", "k-p6", "b-02"])
        #expect(forced.missing == ["arrival-broll"])
        for profile in KeeperProfile.allCases {
            #expect(!(try KeeperSelector.rank(profile, input, options: Self.generousOptions(profile))).order.map(\.id).contains("b-old"))
        }
        // the stored B-roll catalog keeps the clip, labelled as not match footage, and passes the strict encoder
        let record = KeeperSelector.brollCatalog(edits, projectId: "real-court-day", revision: 1, sample: false)
        let old = try #require(record.items.first { $0.brollId == "b-old" })
        #expect(old.depictsThisMatch == false && old.disclosureTemplateId == .value(.value))
        #expect(try StudioContractCodec.encode(record).count > 0)
    }

    @Test("markBroll refuses an empty window, a repeated id, stock footage and another day's clip claimed as this match")
    func markBrollRefusals() throws {
        var edits = KeeperEdits()
        let ok = KeeperBroll(brollId: "b-01", sourceId: "broll-1", window: StudioFrameWindow(inFrame: 0, outFrame: 10),
                             depictsThisMatch: true, chapter: "arrival")
        try edits.markBroll(ok)
        #expect(throws: KeeperRejection(.duplicateId, "B-roll b-01 is already marked")) { try edits.markBroll(ok) }
        var empty = ok; empty.brollId = "b-02"; empty.window = StudioFrameWindow(inFrame: 10, outFrame: 10)
        #expect(throws: KeeperRejection(.badInterval, "B-roll b-02 window")) { try edits.markBroll(empty) }
        var otherDay = ok; otherDay.brollId = "b-03"; otherDay.origin = .capturedOtherDay
        #expect(throws: KeeperRejection(.brollMisrepresented, "only today's footage depicts this match")) { try edits.markBroll(otherDay) }
        var stock = ok; stock.brollId = "b-04"; stock.origin = .stock; stock.depictsThisMatch = false
        #expect((try? edits.markBroll(stock)) == nil)
        #expect(edits.brolls.map(\.brollId) == ["b-01"])
    }

    @Test("excluding a person or the location removes every B-roll clip that shows them from later plans")
    func excludePersonAndLocation() throws {
        let candidates = try KeeperSelector.candidates(Self.project)
        var edits = KeeperEdits()
        try edits.markBroll(KeeperBroll(brollId: "b-jon", sourceId: "broll-1", window: StudioFrameWindow(inFrame: 0, outFrame: 60),
                                        depictsThisMatch: true, peopleVisible: ["jon"], chapter: "arrival"))
        try edits.markBroll(KeeperBroll(brollId: "b-venue", sourceId: "broll-2", window: StudioFrameWindow(inFrame: 0, outFrame: 60),
                                        depictsThisMatch: true, locationVisible: true, chapter: "after"))
        try edits.markBroll(KeeperBroll(brollId: "b-bag", sourceId: "broll-3", window: StudioFrameWindow(inFrame: 0, outFrame: 60),
                                        depictsThisMatch: true, chapter: "after"))
        #expect(KeeperSelector.planInput(candidates, edits: edits).brolls.map(\.brollId) == ["b-jon", "b-venue", "b-bag"])
        edits.exclude(person: "jon")
        #expect(KeeperSelector.planInput(candidates, edits: edits).brolls.map(\.brollId) == ["b-venue", "b-bag"])
        edits.excludeLocation()
        let input = KeeperSelector.planInput(candidates, edits: edits)
        #expect(input.brolls.map(\.brollId) == ["b-bag"])
        #expect(try KeeperSelector.rank(.courtMemories, input).order.map(\.id) == ["k-p1", "k-p2", "k-p4", "k-p6", "b-bag"])
    }

    @Test("select and annotate keep a keeper with the player's note; each edit names the keepers it changed")
    func selectAndAnnotate() throws {
        let candidates = try KeeperSelector.candidates(Self.project)
        var edits = KeeperEdits()
        #expect(edits.exclude(keeper: "k-p3") == ["k-p3"])
        #expect(edits.select("k-p3") == ["k-p3"])            // selecting brings an excluded keeper back
        #expect(edits.select("k-p3") == [])                  // nothing changed the second time
        #expect(edits.annotate("k-p5", note: "  Great backhand down the line ") == ["k-p5"])
        #expect(edits.annotate("k-p5", note: "Great backhand down the line") == [])
        #expect(edits.notes == ["k-p5": "Great backhand down the line"])
        let input = KeeperSelector.planInput(candidates, edits: edits)
        #expect(input.matchFootageIds.contains("k-p3") && input.notes["k-p5"] == "Great backhand down the line")
        let catalog = KeeperSelector.catalog(candidates, eventVersion: 4, projectId: "real-court-day", revision: 2, sample: false,
                                             syncRevision: 1, edits: edits)
        #expect(catalog.keepers.filter { $0.selection == .manual }.map(\.keeperId) == ["k-p3", "k-p5"])
        #expect(edits.annotate("k-p5", note: nil) == ["k-p5"])
        #expect(edits.notes.isEmpty)
    }

    @Test("candidates(project, eventVersion) is a jovra.keeper-catalog/1 record the strict encoder accepts")
    func catalogRecord() throws {
        let catalog = try KeeperSelector.catalog(Self.project, eventVersion: 7, projectId: "real-court-day", revision: 1,
                                                 sample: false, syncRevision: 1)
        #expect(catalog.eventRevision == 7 && catalog.syncRevision == .value(1))
        // p1 is 10.0-14.0 s: 8.5-16.5 s with the default rolls, frames 510-990 at 60 fps
        let p1 = try #require(catalog.keepers.first { $0.keeperId == "k-p1" })
        #expect(p1.session == StudioIntervalUs(startUs: 8_500_000, endUs: 16_500_000))
        #expect(p1.views == [KeeperCatalogKeeperView(sourceId: "camera-1", window: StudioFrameWindow(inFrame: 510, outFrame: 990), primary: true)])
        #expect(p1.provenance == .manual && p1.selection == .heuristic)
        // p2's reviewed contact at 22.0 s is frame 1320 on camera 1
        #expect(catalog.keepers.first { $0.keeperId == "k-p2" }?.contacts == [KeeperCatalogKeeperContact(sourceId: "camera-1", frame: 1320)])
        let bytes = try StudioContractCodec.encode(catalog)
        #expect(try StudioContractCodec.decode(KeeperCatalog.self, from: bytes) == catalog)
        // a keeper no angle can show is left out of the record (a catalog keeper needs a view)
        var blind = Self.project
        blind.sources = []
        #expect(try KeeperSelector.catalog(blind, eventVersion: 7, projectId: "real-court-day", revision: 1, sample: false,
                                           syncRevision: nil).keepers.isEmpty)
    }
}
