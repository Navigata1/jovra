import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// Sources reference core sessions; each holds at most one camera slot (stories 27, 69); revisions only grow (SD20).
@Suite("Studio project store: sources, slots and revisions")
struct ProjectSourcesAndRevisionsTests {
    @Test("one phone is a complete project: create with a primary session holds it as the primary camera-1")
    func singleCameraProject() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let project = try await scratch.store().create(kind: .match, primarySession: "session-a", segmentIds: ["seg-0"])

        #expect(project.sources == [StudioProjectSource(sourceId: "camera-1", sessionId: "session-a",
                                                        segmentIds: ["seg-0"], slot: nil)])
        #expect(project.primarySource?.sessionId == "session-a")
        #expect(project.revisions == StudioProjectRevisions(sourceManifestRevision: 1))
    }

    @Test("assigning an occupied slot throws slotTaken naming the source that holds it, and changes nothing")
    func assignOccupiedSlot() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let project = try await store.create(kind: .match)
        try await store.addSource(sessionId: "session-a", slot: .nearBaseline, to: project.projectId)
        let second = try await store.addSource(sessionId: "session-b", slot: .farBaseline, to: project.projectId)
        let before = try await store.project(project.projectId)

        await #expect(throws: StudioProjectStoreError.slotTaken(.nearBaseline, heldBy: "camera-1")) {
            try await store.assignSlot(.nearBaseline, to: second.sourceId, in: project.projectId)
        }
        await #expect(throws: StudioProjectStoreError.slotTaken(.farBaseline, heldBy: "camera-2")) {
            try await store.addSource(sessionId: "session-c", slot: .farBaseline, to: project.projectId)
        }
        #expect(try await store.project(project.projectId) == before)
    }

    @Test("a freed slot can be taken, custom may be held twice, and re-assigning a source its own slot is a no-op")
    func slotRules() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let id = try await store.create(kind: .match).projectId
        try await store.addSource(sessionId: "session-a", slot: .nearBaseline, to: id)
        try await store.addSource(sessionId: "session-b", slot: .custom, to: id)
        try await store.addSource(sessionId: "session-c", slot: .custom, to: id)
        #expect(try await store.revisions(id).sourceManifestRevision == 3)

        try await store.assignSlot(.nearBaseline, to: "camera-1", in: id)
        #expect(try await store.revisions(id).sourceManifestRevision == 3)

        try await store.assignSlot(nil, to: "camera-1", in: id)
        let moved = try await store.assignSlot(.nearBaseline, to: "camera-2", in: id)
        #expect(moved.sources.map(\.slot) == [nil, .nearBaseline, .custom])
        #expect(moved.revisions.sourceManifestRevision == 5)
        await #expect(throws: StudioProjectStoreError.unknownSource("camera-9")) {
            try await store.assignSlot(.farBaseline, to: "camera-9", in: id)
        }
    }

    @Test("the first match source becomes the primary; setPrimary moves it and bumps the manifest revision")
    func primary() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let id = try await store.create(kind: .match).projectId
        try await store.addSource(sessionId: "session-broll", slot: nil, role: .broll, to: id)
        try await store.addSource(sessionId: "session-a", slot: .nearBaseline, to: id)
        #expect(try await store.project(id).primarySourceId == "camera-2")

        let changed = try await store.setPrimary("camera-1", in: id)
        #expect(changed.primarySource?.sessionId == "session-broll")
        #expect(changed.revisions.sourceManifestRevision == 3)
        await #expect(throws: StudioProjectStoreError.unknownSource("camera-7")) {
            try await store.setPrimary("camera-7", in: id)
        }
    }

    @Test("sync, keeper and event-log revisions only grow: an older value is refused, the same value changes nothing")
    func monotonicRevisions() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let id = try await store.create(kind: .match, primarySession: "session-a").projectId

        try await store.recordSyncRevision(2, for: id)
        try await store.recordKeeperRevision(1, for: id)
        try await store.recordEventLogVersion(124, for: id)
        try await store.recordEventLogVersion(124, for: id)
        #expect(try await store.revisions(id) == StudioProjectRevisions(sourceManifestRevision: 1, syncRevision: 2,
                                                                         keeperRevision: 1, eventLogVersion: 124))
        await #expect(throws: StudioProjectStoreError.revisionRegressed(current: 2, offered: 1)) {
            try await store.recordSyncRevision(1, for: id)
        }
        await #expect(throws: StudioProjectStoreError.revisionRegressed(current: 124, offered: 3)) {
            try await store.recordEventLogVersion(3, for: id)
        }
        #expect(try await scratch.store().revisions(id).eventLogVersion == 124)
    }

    @Test("with the core session store attached, a source must be an existing session, and the event-log version is read from it")
    func coreSessionReferences() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        let real = try CoreFixtureSessions.realCopies()[0]
        try await CoreFixtureSessions.install(real, bytes: Data("original".utf8), in: sessions)
        let store = try scratch.store(sessions: sessions)

        await #expect(throws: StudioProjectStoreError.sessionNotFound("missing-session")) {
            try await store.create(kind: .match, primarySession: "missing-session")
        }
        let id = try await store.create(kind: .match, primarySession: real.id).projectId
        let revisions = try await store.refreshEventLogVersion(for: id)

        // The highest event seq in the shipped Jon vs Alex log (spec/fixtures/sample/library), read independently.
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: StudioFixtures.repositoryRoot()
            .appendingPathComponent("spec/fixtures/sample/library/sessions/2026-09-09-match.session.json"))) as! [String: Any]
        let log = (expected["match"] as! [String: Any])["log"] as! [[String: Any]]
        #expect(real.title == (expected["title"] as! String))
        #expect(revisions.eventLogVersion == log.map { $0["seq"] as! Int }.max())
        #expect(revisions.eventLogVersion > 0)
    }

    @Test("a source is a reference: no file of the original appears in the project folder")
    func originalsAreNotCopied() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        let real = try CoreFixtureSessions.realCopies()[0]
        try await CoreFixtureSessions.install(real, bytes: Data(repeating: 7, count: 4096), in: sessions)
        let store = try scratch.store(sessions: sessions)
        let id = try await store.create(kind: .match, primarySession: real.id).projectId

        let folder = scratch.studio.appendingPathComponent("projects/\(id)")
        let files = FileManager.default.enumerator(atPath: folder.path)?.allObjects as? [String] ?? []
        #expect(files == ["studio.json"])
    }
}
