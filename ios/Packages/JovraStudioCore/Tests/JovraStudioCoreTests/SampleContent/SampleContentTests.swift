import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// The removable Studio sample (stories 13-16): installed with `isSample`, scored by the core fold, removed in one
/// action, and kept out of the player's stats and trends (the core sample-scope rule).
@Suite("Studio sample content")
struct SampleContentTests {
    static func content() throws -> StudioSampleContent {
        try StudioSampleContent(records: StudioSampleRecords.load(from: StudioFixtures.root().appendingPathComponent("records")))
    }

    @Test("installing yields a match project whose score from the core fold reads Jon 6 6 / Alex 4 3, Final")
    func matchScore() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        try await Self.content().install(into: store)

        let summary = try #require(try await store.projects(sample: true).first { $0.kind == .match })
        let project = try await store.project(summary.projectId)
        #expect(project.isSample)
        #expect(project.primarySource?.sessionId == StudioSampleContent.matchSessionID)

        let session = try StudioSampleContent.matchSession(in: CoreFixtureSessions.sampleLibrary())
        let score = try StudioMatchScore.compute(project: project, session: session)
        #expect(score.rows == [.init(name: "Jon", games: [6, 6]), .init(name: "Alex", games: [4, 3])])
        #expect(score.statusLabel == "Final")
        #expect(session.match?.log.filter { if case .point = $0 { true } else { false } }.count == 124)
    }

    @Test("every installed project and every installed record is flagged Sample, byte for byte as shipped")
    func everythingIsSample() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let content = try Self.content()
        try await content.install(into: store)

        let projects = try await store.projects()
        #expect(Set(projects.map(\.projectId)) == ["sample-court-day", "sample-lesson-series"])
        #expect(projects.allSatisfy { $0.sample })
        let kinds = Set(projects.map(\.kind))
        #expect(kinds == Set<StudioProjectKind>([.match, .lessonSeries]))
        let records = scratch.studio.appendingPathComponent("projects")
        var installed = 0
        let paths = (FileManager.default.enumerator(atPath: records.path)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".json") }
        for path in paths {
            let data = try Data(contentsOf: records.appendingPathComponent(path))
            if path.hasSuffix("/studio.json") {
                #expect(try JSONDecoder().decode(StudioProject.self, from: data).sample)
                continue
            }
            let header = try StudioRecordHeader(json: data)
            #expect(header.isSample, "\(path)")
            let shipped = path.hasSuffix("project-lock.r1.json") ? "project-lock.json" : URL(fileURLWithPath: path).lastPathComponent
            #expect(data == content.records.files[shipped], "\(path)")
            installed += 1
        }
        #expect(installed == StudioSampleIdentity.allCases.flatMap(\.recordNames).count)
    }

    @Test("the match project's revisions, slots and owners come from the stored sample records")
    func matchProjectFromRecords() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        try await Self.content().install(into: store)
        let project = try await store.project(StudioSampleContent.matchProjectID)

        // Literals read from spec/studio/fixtures/records (source-manifest, sync-map, keeper-catalog, project-lock).
        #expect(project.revisions == StudioProjectRevisions(sourceManifestRevision: 1, syncRevision: 2,
                                                             keeperRevision: 1, eventLogVersion: 3))
        #expect(project.lockRevision == 1)
        #expect(project.sources.map(\.sourceId) == ["camera-1", "camera-2", "camera-3", "broll-1", "broll-2"])
        #expect(project.sources.map(\.role) == [.match, .match, .match, .broll, .broll])
        #expect(project.sources.map(\.ownerParticipantId) == ["jon", "alex", "jon", nil, nil])
        #expect(project.sources.map(\.slot) == [.nearBaseline, .farBaseline, .nearLeftCorner, nil, nil])
        #expect(project.primarySourceId == "camera-1")
        #expect(project.sources.dropFirst().allSatisfy { $0.sessionId == nil })
        #expect(try await store.films(project.projectId).map(\.titleText.value) == ["A good day on court"])
    }

    @Test("locking the installed sample reproduces the shipped lock as revision 2, with the reference's manifest hash")
    func lockMatchesReference() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        try await Self.content().install(into: store)
        var expected = try StudioContractCodec.decode(ProjectLock.self, from: StudioFixtures.data("records/project-lock.json"))
        expected.revision = 2

        let lock = try await store.lock(profile: .init(id: .courtMemories, revision: 1),
                                        output: .init(aspect: .v16_9, height: 1080, durationTargetSeconds: .value(258)),
                                        in: StudioSampleContent.matchProjectID)

        #expect(lock == expected)
        #expect(lock.sourceManifest.sha256 == "09229dc97139261f36893fcf788fc514626091e0a7ab5d4af074cc496fcee271")
        #expect(try await store.record(named: "project-lock.r2.json", in: .locks, of: StudioSampleContent.matchProjectID) != nil)
        #expect(try await store.project(StudioSampleContent.matchProjectID).lockRevision == 2)
    }

    @Test("removing deletes every Sample project in one call and leaves real projects untouched")
    func removeLeavesRealProjects() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let real = try await store.create(kind: .match, primarySession: "session-real")
        try await store.addSource(sessionId: "session-real-2", slot: .farBaseline, to: real.projectId)
        let realBefore = try await store.project(real.projectId)
        let realFile = scratch.studio.appendingPathComponent("projects/\(real.projectId)/studio.json")
        let realBytes = try Data(contentsOf: realFile)
        let content = try Self.content()
        try await content.install(into: store)
        #expect(try await StudioSampleContent.isInstalled(in: store))

        let removed = try await content.remove(from: store)

        #expect(removed == ["sample-court-day", "sample-lesson-series"])
        #expect(try await store.projects().map(\.projectId) == [real.projectId])
        #expect(try await store.project(real.projectId) == realBefore)
        #expect(try Data(contentsOf: realFile) == realBytes)
        #expect(try await !StudioSampleContent.isInstalled(in: store))
    }

    @Test("installing twice keeps the installed sample; a real project holding a sample id is never overwritten")
    func installIsIdempotentAndSafe() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let content = try Self.content()
        try await content.install(into: store)
        try await store.recordKeeperRevision(5, for: StudioSampleContent.matchProjectID)
        try await content.install(into: store)
        #expect(try await store.revisions(StudioSampleContent.matchProjectID).keeperRevision == 5)

        // A real project that somehow holds the sample's id.
        try await content.remove(from: store)
        let folder = scratch.studio.appendingPathComponent("projects/sample-court-day")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var impostor = try content.matchProject()
        impostor.sample = false
        try CanonicalJSON.encode(impostor).write(to: folder.appendingPathComponent("studio.json"))
        await #expect(throws: StudioProjectStoreError.idInUse("sample-court-day")) { try await content.install(into: store) }
        try await content.remove(from: store)
        #expect(try await store.project("sample-court-day").sample == false)
    }

    @Test("a record that is not flagged Sample is refused, and so is a missing one")
    func refusesNonSample() throws {
        var files = try Self.content().records.files
        let lock = String(decoding: files["project-lock.json"]!, as: UTF8.self)
        files["project-lock.json"] = Data(lock.replacingOccurrences(of: "\"sample\": true", with: "\"sample\": false").utf8)
        #expect(throws: StudioSampleContentError.notSample("project-lock.json")) { try StudioSampleRecords(files: files) }
        files["project-lock.json"] = nil
        #expect(throws: StudioSampleContentError.missingRecord("project-lock.json")) { try StudioSampleRecords(files: files) }
    }

    @Test("each identity is made of records of the sample project, and the identities do not share a record")
    func identities() throws {
        let names = StudioSampleIdentity.allCases.flatMap(\.recordNames)
        #expect(Set(names).count == names.count)
        #expect(StudioSampleIdentity.allCases.count == 10)
        #expect(StudioSampleIdentity.lesson.projectId == "sample-lesson-series")
        let records = try Self.content().records
        // The import sample: three 60-minute match angles of 3.6 GB each (8 Mbps x 3,600 s / 8 / 1,000).
        let angles = records.sourceManifest.sources.filter { $0.role == .match }
        #expect(angles.map(\.original.sizeBytes) == [3_600_000_000, 3_600_000_000, 3_600_000_000])
        #expect(angles.map(\.original.durationUs) == [3_600_000_000, 3_600_000_000, 3_600_000_000])
        #expect(records.lessons.map(\.title) == ["First serve foundation", "Recovery step", "Serve rhythm"])
    }
}
