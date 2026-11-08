import Foundation
import Testing
import JovraCore

/// T09 acceptance: the demo library installs, resets byte-for-byte and removes only sample objects; its Swift
/// summary equals the reference library oracle; one sample-scope rule decides what counts. Expected values are
/// the brief's literals (screens.md §0.6) or the reference generator's oracle, never recomputed here.
private func repository() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { url.deleteLastPathComponent() }
    return url
}

private let libraryPath = "spec/fixtures/sample/library"
private let jonVsAlex = "b75c57d3-04df-5b4d-b969-32ed5cbfd97a"
private let sep17JonVsAlex = "e138e0e8-82f9-598a-a5c7-88495e6c93df"
private let jon = "e75faf7e-1ce8-5d45-b003-af3f331b1082"
private let alex = "970100b1-ee8c-50cb-99b5-5ab260ddcee6"

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func shippedLibrary() throws -> SampleLibrary {
    let root = repository().appendingPathComponent(libraryPath)
    return try SampleLibrary.load(from: root, mediaManifest: root.appendingPathComponent("../media-manifest.json"))
}

private struct LibraryOracle: Decodable { let expected: LibrarySummary }
private func oracle() throws -> LibrarySummary {
    let url = repository().appendingPathComponent("\(libraryPath)/library.expected.json")
    return try JSONDecoder().decode(LibraryOracle.self, from: Data(contentsOf: url)).expected
}

/// A real (not sample) match: the shipped Jon vs Alex events under a new id, with the sample flag removed.
private func realMatch(id: String = "real-match") throws -> SessionDocument {
    let url = repository().appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: url))
    document.id = id
    document.sample = nil
    document.marks = []
    return document
}

private func installedSessions(_ store: SessionStore) async throws -> [SessionDocument] {
    var documents: [SessionDocument] = []
    for summary in try await store.list() { documents.append(try await store.load(summary.id)) }
    return documents
}

private func sessionBytes(_ root: URL, _ id: String) throws -> Data {
    try Data(contentsOf: root.appendingPathComponent("sessions/\(id)/session.json"))
}

// MARK: install, reset, remove

@Test func installCreatesEightSampleSessionsPlusTheEquipmentAndPracticePlan() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let content = SampleContent(library: try shippedLibrary())
    #expect(try await content.isInstalled(in: store) == false)

    try await content.install(into: store)

    let sessions = try await store.list()
    #expect(sessions.count == 8)
    #expect(sessions.allSatisfy { $0.sample })
    #expect(Set(sessions.map(\.title)) == ["Jon vs Alex", "Serve practice", "Forehand session", "Jon vs Chris",
                                           "Stroke practice", "Jon vs Sam"])
    let equipment = try #require(try await SampleContent.installedEquipment(in: store))
    #expect(equipment.sample != nil)
    #expect(equipment.stringJobs.map(\.strungOn) == ["2026-09-09"])
    let plan = try #require(try await SampleContent.installedPracticePlan(in: store))
    #expect(plan.sample == true)
    #expect(plan.items.map(\.drill.title) == ["Toss consistency", "Wide serve targets", "Serve + first ball"])
    #expect(try await content.isInstalled(in: store))
}

@Test func installingTwiceKeepsThePlayersSampleEdits() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let content = SampleContent(library: try shippedLibrary())
    try await content.install(into: store)
    try await store.update(jonVsAlex, facet: .review(.init(state: .complete, updatedAt: "2026-10-08T12:00:00Z")))
    let edited = try sessionBytes(root, jonVsAlex)

    try await content.install(into: store)

    #expect(try sessionBytes(root, jonVsAlex) == edited)
    #expect(try await store.list().count == 8)
}

@Test func resetRestoresAnEditedSampleDocumentByteForByte() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let content = SampleContent(library: try shippedLibrary())
    try await content.install(into: store)
    let shipped = try CanonicalJSON.canonicalize(Data(contentsOf: repository()
        .appendingPathComponent("\(libraryPath)/sessions/jon-vs-alex.session.json")))
    let installed = try sessionBytes(root, jonVsAlex)
    #expect(installed == shipped)
    let equipmentURL = root.appendingPathComponent("sample-content/equipment.json")
    let installedEquipment = try Data(contentsOf: equipmentURL)

    try await store.update(jonVsAlex, facet: .review(.init(state: .complete, updatedAt: "2026-10-08T12:00:00Z")))
    try await store.trash(sep17JonVsAlex)
    try Data("{}".utf8).write(to: equipmentURL)
    #expect(try sessionBytes(root, jonVsAlex) != installed)

    try await content.reset(in: store)

    #expect(try sessionBytes(root, jonVsAlex) == shipped)
    #expect(try Data(contentsOf: equipmentURL) == installedEquipment)
    let restored = try await store.load(sep17JonVsAlex)
    #expect(restored.original == nil)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions/\(sep17JonVsAlex)/.trash.json").path))
    #expect(try await store.list().count == 8)
}

@Test func removeDeletesOnlySampleObjectsAndARealSessionSurvives() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await store.create(realMatch())
    let content = SampleContent(library: try shippedLibrary())
    try await content.install(into: store)
    #expect(try await store.list().count == 9)

    try await content.remove(from: store)

    #expect(try await store.list().map(\.id) == ["real-match"])
    #expect(try await SampleContent.installedEquipment(in: store) == nil)
    #expect(try await SampleContent.installedPracticePlan(in: store) == nil)
    #expect(try await content.isInstalled(in: store) == false)
}

@Test func installRefusesALibraryDocumentThatIsNotFlaggedSample() async throws {
    let shipped = try shippedLibrary()
    var sessions = shipped.sessions
    let index = try #require(sessions.firstIndex { $0.id == jonVsAlex })
    sessions[index].sample = nil
    #expect(throws: SampleContentError.notSample(jonVsAlex)) {
        try SampleLibrary(sessions: sessions, equipment: shipped.equipment, practicePlan: shipped.practicePlan,
                          mediaManifest: shipped.mediaManifest)
    }
}

@Test func installNeverOverwritesARealSessionThatSharesASampleID() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await store.create(realMatch(id: jonVsAlex))
    let content = SampleContent(library: try shippedLibrary())
    await #expect(throws: SampleContentError.idInUse(jonVsAlex)) { try await content.install(into: store) }
    try await content.remove(from: store)
    #expect(try await store.load(jonVsAlex).sample == nil)
}

// MARK: the library oracle

@Test func installedLibrarySummaryEqualsTheReferenceLibraryOracle() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await SampleContent(library: try shippedLibrary()).install(into: store)
    let equipment = try #require(try await SampleContent.installedEquipment(in: store))

    let summary = try LibrarySummary.compute(sessions: try await installedSessions(store), equipment: [equipment])

    #expect(summary == (try oracle()))
    // The brief's literals (screens.md §0.6), independent of the generator.
    #expect(summary.sample)
    #expect(summary.sessionCount == 8)
    #expect(summary.totalMinutes == 402)
    #expect(summary.weeklyFirstServeIn.map { [$0.value.n, $0.value.d] } == [[24, 50], [33, 60], [38, 60], [40, 60]])
    #expect(summary.weeklyFirstServeIn.map(\.value.display) == ["48%", "55%", "63%", "67%"])
    #expect(summary.firstServeInDelta == "+4 percentage points")
    #expect(summary.stringJobs.count == 1)
    #expect(summary.stringJobs.first?.strungOn == "2026-09-09")
    #expect(summary.stringJobs.first?.linkedSessionIds.count == 8)
    #expect(summary.stringJobs.first?.loggedMinutes == 402)
}

@Test func everyMediaIDInTheInstalledSessionsExistsInTheSampleMediaManifest() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let library = try shippedLibrary()
    try await SampleContent(library: library).install(into: store)
    let known = Set(library.mediaManifest.media.map(\.mediaId))

    let sessions = try await installedSessions(store)
    let ids = sessions.flatMap { $0.sample?.mediaIds ?? [] }
    #expect(ids.count == 11)
    #expect(Set(ids).isSubset(of: known))
    for session in sessions {
        let owners = Set(library.mediaManifest.media.filter { session.sample?.mediaIds?.contains($0.mediaId) == true }.map(\.sessionId))
        #expect(owners == [session.id], "\(session.title) names another session's media")
    }
}

// MARK: the sample-scope rule

@Test func anAllSampleScopeCountsSamplesAndIsFlaggedSample() {
    let scoped = SampleScope.resolve(["s1", "s2"], isSample: { _ in true })
    #expect(scoped.items == ["s1", "s2"])
    #expect(scoped.isSample)
}

@Test func aMixedScopeCountsOnlyTheRealItems() {
    let scoped = SampleScope.resolve(["s1", "real", "s2"], isSample: { $0 != "real" })
    #expect(scoped.items == ["real"])
    #expect(!scoped.isSample)
}

@Test func anEmptyScopeIsNotSample() {
    let scoped = SampleScope.resolve([String](), isSample: { _ in true })
    #expect(scoped.items.isEmpty)
    #expect(!scoped.isSample)
}

@Test func aScopeMixingOneRealSessionWithSamplesCountsOnlyTheRealSession() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await SampleContent(library: try shippedLibrary()).install(into: store)
    try await store.create(realMatch())
    let equipment = try #require(try await SampleContent.installedEquipment(in: store))

    let summary = try LibrarySummary.compute(sessions: try await installedSessions(store), equipment: [equipment])

    #expect(!summary.sample)
    #expect(summary.sessionCount == 1)
    #expect(summary.totalMinutes == 54)
    #expect(summary.sessions.map(\.id) == ["real-match"])
    #expect(summary.weeklyFirstServeIn.map { [$0.value.n, $0.value.d] } == [[0, 0], [0, 0], [0, 0], [40, 60]])
    #expect(summary.weeklyFirstServeIn.last?.sessionIds == ["real-match"])
    #expect(summary.firstServeInDelta == "—")
    // The sample string job has no real session linked, and a sample equipment document beside real data is
    // left out entirely.
    #expect(summary.stringJobs.isEmpty)
}

@Test func headToHeadExcludesSamplesUnlessAsked() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    try await SampleContent(library: try shippedLibrary()).install(into: store)

    #expect(try await store.headToHead(playerID: jon, opponentID: alex).isEmpty)
    let asked = try await store.headToHead(playerID: jon, opponentID: alex, includeSamples: true)
    #expect(asked.map(\.id) == [jonVsAlex, sep17JonVsAlex])
}

// MARK: sample media

@Test func aMissingSampleFileIsTheMissingMediaStateNotAnError() throws {
    let library = try shippedLibrary()
    let empty = temporaryRoot()
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }
    let catalog = SampleMediaCatalog(manifest: library.mediaManifest, directory: empty)
    #expect(catalog.availability(mediaID: "sample-media.jon-vs-alex") == .missing(fileName: "sample-jon-vs-alex.mp4"))
    try Data("synthetic".utf8).write(to: empty.appendingPathComponent("sample-jon-vs-alex.mp4"))
    #expect(catalog.availability(mediaID: "sample-media.jon-vs-alex")
            == .available(empty.appendingPathComponent("sample-jon-vs-alex.mp4")))
    #expect(catalog.availability(mediaID: "sample-media.nope") == .unknown)
}

@Test func pointsOutsideAnOlderSessionsShortClipAreNotInTheSampleVideo() throws {
    let catalog = SampleMediaCatalog(manifest: try shippedLibrary().mediaManifest, directory: nil)
    let sep9 = "591c33e0-889c-5daf-b36d-03f90029d213"
    #expect(catalog.coverage(sessionID: sep9, timeMs: 12_000) == .inSampleVideo(mediaID: "sample-media.2026-09-09-match", offsetMs: 12_000))
    #expect(catalog.coverage(sessionID: sep9, timeMs: 20_000) == .notInSampleVideo)
    #expect(catalog.coverage(sessionID: jonVsAlex, timeMs: 1_103_730)
            == .inSampleVideo(mediaID: "sample-media.jon-vs-alex", offsetMs: 1_103_730))
    #expect(catalog.coverage(sessionID: "real-match", timeMs: 0) == .notInSampleVideo)
}
