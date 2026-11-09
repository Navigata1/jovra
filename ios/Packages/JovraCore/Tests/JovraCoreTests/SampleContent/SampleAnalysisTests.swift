import Foundation
import Testing
import JovraCore

/// T40 acceptance: the analysis overlays install with the library, the Swift summary of the installed sample equals
/// the reference analysis oracle, the fractions move with the data (so they are not constants), and every serve mark
/// sits within one frame of the renderer's ground truth. Expected values come from the oracle or the brief's literals
/// (screens.md §0.6), never from recomputing here.
private func repository() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { url.deleteLastPathComponent() }
    return url
}

private let samplePath = "spec/fixtures/sample"
private let jonVsAlex = "b75c57d3-04df-5b4d-b969-32ed5cbfd97a"
private let oct4ServePractice = "c80aad59-ede9-5b4b-9672-57f157bd3a92"
private let jon = "e75faf7e-1ce8-5d45-b003-af3f331b1082"

private func sampleRoot() -> URL { repository().appendingPathComponent(samplePath) }

private func analysisRecords() throws -> [SampleAnalysisRecord] {
    try SampleAnalysisRecord.loadAll(from: sampleRoot().appendingPathComponent("analysis"))
}

private func library(analysis: [SampleAnalysisRecord]? = nil) throws -> SampleLibrary {
    let root = sampleRoot()
    let plain = try SampleLibrary.load(from: root.appendingPathComponent("library"),
                                       mediaManifest: root.appendingPathComponent("media-manifest.json"))
    return try SampleLibrary(sessions: plain.sessions, equipment: plain.equipment, practicePlan: plain.practicePlan,
                             mediaManifest: plain.mediaManifest, analysis: try analysis ?? analysisRecords())
}

private struct Oracle: Decodable { let expected: SampleAnalysisSummary }
private func oracle() throws -> SampleAnalysisSummary {
    let url = sampleRoot().appendingPathComponent("analysis/analysis.expected.json")
    return try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: url)).expected
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func installedSessions(_ store: SessionStore) async throws -> [SessionDocument] {
    var documents: [SessionDocument] = []
    for summary in try await store.list() { documents.append(try await store.load(summary.id)) }
    return documents
}

// MARK: install

@Test func theInstalledSampleSummarisesToTheReferenceAnalysisOracle() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let content = SampleContent(library: try library())
    try await content.install(into: store)

    let installed = try await installedSessions(store)
    let summary = try SampleAnalysisSummary.compute(sessions: installed, mediaManifest: content.library.mediaManifest)
    #expect(summary == (try oracle()))
}

@Test func theInstalledSampleCarriesTheBriefsForehandPlacementsAndTwelveServeMarks() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await SampleContent(library: try library()).install(into: store)
    let summary = try SampleAnalysisSummary.compute(sessions: try await installedSessions(store),
                                                    mediaManifest: try library().mediaManifest)

    let forehands = try #require(summary.shotPlacement.first { $0.hitter == jon && $0.stroke == "forehand" })
    #expect(forehands.sessionId == jonVsAlex)
    #expect((forehands.placed, forehands.tagged) == (50, 133))
    #expect([forehands.deep.display, forehands.short.display, forehands.out.display] == ["62%", "24%", "14%"])
    #expect([forehands.deep.n, forehands.short.n, forehands.out.n] as [Int] == [31, 12, 7])
    let marks = try #require(summary.serveMarks.first)
    #expect(marks.sessionId == oct4ServePractice)
    #expect((marks.marked, marks.complete) == (12, 12))
    #expect(summary.comparisons.map { [$0.left.date, $0.right.date] } == [["2026-10-06", "2026-09-28"]])
    #expect(summary.sample)
}

@Test func resetRestoresTheAnalysisRecordsAndRemoveTakesThemAway() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let content = SampleContent(library: try library())
    try await content.install(into: store)
    var edited = try await store.load(jonVsAlex)
    edited.shots = []
    let file = try await store.sessionDirectory(jonVsAlex).appendingPathComponent("session.json")
    try CanonicalJSON.encode(edited).write(to: file, options: .atomic)
    #expect(try await store.load(jonVsAlex).shots?.isEmpty == true)

    try await content.reset(in: store)
    #expect(try await store.load(jonVsAlex).shots?.count == 386)

    try await content.remove(from: store)
    #expect(try await store.list().isEmpty)
}

@Test func withoutTheOverlaysTheLibraryHasNoAnalysisAndTheSummaryIsEmpty() throws {
    let plain = try library(analysis: [])
    let summary = try SampleAnalysisSummary.compute(sessions: plain.sessions, mediaManifest: plain.mediaManifest)
    #expect(summary.shotPlacement.isEmpty && summary.servePlacement.isEmpty && summary.serveMarks.isEmpty)
    #expect(summary.keyMoments.isEmpty && summary.comparisons.isEmpty)
}

// MARK: refusals

@Test func anOverlayForASessionOutsideTheLibraryIsRefused() throws {
    var records = try analysisRecords()
    records[0].sessionId = "not-a-library-session"
    #expect(throws: SampleContentError.invalidLibrary("analysis names no library session: not-a-library-session")) {
        try library(analysis: records)
    }
}

@Test func anOverlayThatIsNotFlaggedSampleIsRefused() throws {
    var records = try analysisRecords()
    records[0].sample = nil
    #expect(throws: SampleContentError.notSample("analysis \(records[0].sessionId)")) { try library(analysis: records) }
}

@Test func anOverlayRepeatingAnIDTheSessionAlreadyHasIsRefused() throws {
    var records = try analysisRecords()
    let index = try #require(records.firstIndex { !$0.shots.isEmpty })
    records[index].shots.append(records[index].shots[0])
    #expect(throws: SampleContentError.self) { try library(analysis: records) }
}

// MARK: the fractions follow the data

@Test func movingOnePlacementInACopyOfTheFixtureChangesTheOracleFractions() throws {
    var records = try analysisRecords()
    let index = try #require(records.firstIndex { $0.sessionId == jonVsAlex })
    let shot = try #require(records[index].shots.firstIndex {
        $0.stroke == .forehand && $0.placement?.inOut == .in && abs($0.placement!.court.y) > 6.4
    })
    let y = records[index].shots[shot].placement!.court.y
    records[index].shots[shot].placement!.court.y = y > 0 ? 3 : -3

    let moved = try library(analysis: records)
    let summary = try SampleAnalysisSummary.compute(sessions: moved.sessions, mediaManifest: moved.mediaManifest)
    let forehands = try #require(summary.shotPlacement.first)
    #expect([forehands.deep.n, forehands.short.n] as [Int] == [30, 13])
    #expect([forehands.deep.display, forehands.short.display] == ["60%", "26%"])
    #expect(summary != (try oracle()))
}

// MARK: ground truth

private struct Truth: Decodable {
    struct Serve: Decodable { struct Moment: Decodable { let frame: Int }; let contact: Moment; let bounce: Moment; let side: String }
    let serves: [Serve]
}

@Test func everyServeMarkIsWithinOneFrameOfTheRenderedServe() throws {
    let url = repository().appendingPathComponent("spec/fixtures/media/sample/2026-10-04-behind-baseline-12-serves.truth.json")
    let truth = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: url))
    let manifest = try library().mediaManifest
    let clip = try #require(manifest.media.first { $0.mediaId == "sample-media.2026-10-04-behind-baseline-12-serves" })
    let session = try #require(try library().sessions.first { $0.id == oct4ServePractice })
    let marks = try #require(session.serveMarks)
    #expect(marks.count == truth.serves.count && marks.count == 12)
    let fps = Int64(clip.frameRate.num / clip.frameRate.den)
    let base = Int64(clip.coversSessionMs.fromMs) * fps / 1000
    for (mark, serve) in zip(marks, truth.serves) {
        let contact = try #require(mark.contactFrame), bounce = try #require(mark.bounceFrame)
        #expect(Int64(contact.timescale) == fps && Int64(bounce.timescale) == fps)
        #expect(abs(contact.value - base - Int64(serve.contact.frame)) <= 1, "\(mark.id) contact")
        #expect(abs(bounce.value - base - Int64(serve.bounce.frame)) <= 1, "\(mark.id) bounce")
        #expect(mark.servedTo?.rawValue == serve.side)
    }
}
