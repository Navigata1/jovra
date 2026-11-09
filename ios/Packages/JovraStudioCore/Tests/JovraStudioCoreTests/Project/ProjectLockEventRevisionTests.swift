import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// A film records the event revision it was built from (story 162): with the core session store attached, the lock
/// reads the primary session's event log at lock time instead of trusting a stored snapshot.
@Suite("Studio project store: the lock's event revision")
struct ProjectLockEventRevisionTests {
    private static let profile = ProjectLockProfile(id: .courtMemories, revision: 1)
    private static let output = ProjectLockOutput(aspect: .v16_9, height: 1080, durationTargetSeconds: .value(258))

    /// A real match session from the shipped sample library, its Sample label removed (CoreFixtureSessions).
    private static func realMatch() throws -> SessionDocument {
        guard let match = try CoreFixtureSessions.realCopies().first(where: { !($0.match?.log.isEmpty ?? true) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return match
    }

    /// The highest `seq` in a session's log, read from the stored session.json bytes rather than through the store.
    private static func storedMaxSeq(_ id: String, in sessions: SessionStore) async throws -> Int {
        let file = try await sessions.sessionDirectory(id).appendingPathComponent("session.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let log = (json["match"] as? [String: Any])?["log"] as? [[String: Any]] ?? []
        return log.compactMap { $0["seq"] as? Int }.max() ?? 0
    }

    /// Makes `id` lockable: the shipped manifest re-labelled for this real project at its current revision, and the
    /// first sample participant named as the owner of every match source.
    private static func prepareForLock(_ id: String, in store: StudioProjectStore) async throws {
        var manifest = try JSONSerialization.jsonObject(with: StudioFixtures.data("records/source-manifest.json")) as! [String: Any]
        manifest["sample"] = false
        manifest["projectId"] = id
        manifest["revision"] = try await store.revisions(id).sourceManifestRevision
        try await store.writeRecord(JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]),
                                    named: "source-manifest.json", in: .manifests, of: id)
        let participants = try StudioContractCodec.decode(ProjectLock.self, from: StudioFixtures.data("records/project-lock.json")).participants
        let sources = try await store.project(id).sources.filter { $0.role == .match }.map(\.sourceId)
        try await store.setParticipants(participants, owners: Dictionary(uniqueKeysWithValues: sources.map { ($0, participants[0].participantId) }),
                                        in: id)
    }

    /// A copy of the log's last point with a new id and the next `seq`: a correction recorded after the first lock.
    private static func correction(after log: [SessionLogEvent], number: Int) throws -> SessionLogEvent {
        guard let last = log.last(where: { if case .point = $0 { true } else { false } }) else { throw CocoaError(.fileNoSuchFile) }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(last)) as! [String: Any]
        json["id"] = "correction-\(number)-\(UUID().uuidString.lowercased())"
        json["seq"] = (log.map(\.seq).max() ?? 0) + 1
        return try JSONDecoder().decode(SessionLogEvent.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test("create with a primary session seeds the event-log version from that session's log")
    func createSeedsEventLogVersion() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        let real = try Self.realMatch()
        try await CoreFixtureSessions.install(real, bytes: Data("original".utf8), in: sessions)
        let store = try scratch.store(sessions: sessions)

        let project = try await store.create(kind: .match, primarySession: real.id)

        let expected = try await Self.storedMaxSeq(real.id, in: sessions)
        #expect(expected > 0)
        #expect(project.revisions.eventLogVersion == expected)
        #expect(try await store.revisions(project.projectId).eventLogVersion == expected)
    }

    @Test("a lock on a fresh real project records the primary session's current event revision")
    func lockFreshProject() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        let real = try Self.realMatch()
        try await CoreFixtureSessions.install(real, bytes: Data("original".utf8), in: sessions)
        let store = try scratch.store(sessions: sessions)
        let id = try await store.create(kind: .match, primarySession: real.id).projectId
        try await Self.prepareForLock(id, in: store)

        let lock = try await store.lock(profile: Self.profile, output: Self.output, in: id)

        #expect(lock.eventRevision == (try await Self.storedMaxSeq(real.id, in: sessions)))
        #expect(lock.sample == false)
    }

    @Test("a lock taken after the session gains a correction records the newer revision, never the stale snapshot")
    func lockAfterSessionChanges() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        let real = try Self.realMatch()
        try await CoreFixtureSessions.install(real, bytes: Data("original".utf8), in: sessions)
        let store = try scratch.store(sessions: sessions)
        let id = try await store.create(kind: .match, primarySession: real.id).projectId
        try await Self.prepareForLock(id, in: store)
        let first = try await store.lock(profile: Self.profile, output: Self.output, in: id)

        // Two corrections land in the core session after the first film was locked; nothing tells the Studio store.
        var log = try await sessions.load(real.id).match!.log
        for number in 1...2 {
            let event = try Self.correction(after: log, number: number)
            try await sessions.append([event], to: real.id)
            log.append(event)
        }
        let second = try await store.lock(profile: Self.profile, output: Self.output, in: id)

        let current = try await Self.storedMaxSeq(real.id, in: sessions)
        #expect(current == first.eventRevision + 2)
        #expect(second.eventRevision == current)
        #expect(second.revision == first.revision + 1)
        #expect(try await store.revisions(id).eventLogVersion == current)
        // The first lock keeps the revision it was built from, so S35 can label that film "Made before a correction".
        let stored = try #require(try await store.record(named: "project-lock.r1.json", in: .locks, of: id))
        #expect(try StudioContractCodec.decode(ProjectLock.self, from: stored).eventRevision == first.eventRevision)
    }

    @Test("a primary session with no recorded events is refused with eventLogEmpty, not a schema error")
    func lockEmptyLog() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        var empty = try Self.realMatch()
        empty.id = "real-empty-log"
        empty.match?.log = []
        try await CoreFixtureSessions.install(empty, bytes: Data("original".utf8), in: sessions)
        let store = try scratch.store(sessions: sessions)
        let id = try await store.create(kind: .match, primarySession: empty.id).projectId
        try await Self.prepareForLock(id, in: store)
        let before = try await store.project(id)

        await #expect(throws: StudioProjectStoreError.eventLogEmpty) {
            try await store.lock(profile: Self.profile, output: Self.output, in: id)
        }
        #expect(try await store.project(id) == before)
        #expect(try await store.recordNames(in: .locks, of: id).isEmpty)
    }

    @Test("a lock whose primary session was deleted is refused with sessionNotFound")
    func lockMissingSession() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        let real = try Self.realMatch()
        try await CoreFixtureSessions.install(real, bytes: Data("original".utf8), in: sessions)
        let store = try scratch.store(sessions: sessions)
        let id = try await store.create(kind: .match, primarySession: real.id).projectId
        try await Self.prepareForLock(id, in: store)
        try FileManager.default.removeItem(at: try await sessions.sessionDirectory(real.id))

        await #expect(throws: StudioProjectStoreError.sessionNotFound(real.id)) {
            try await store.lock(profile: Self.profile, output: Self.output, in: id)
        }
        #expect(try await store.recordNames(in: .locks, of: id).isEmpty)
    }

    @Test("the Sample project never reads the core session store: its lock keeps the records' event revision")
    func sampleLockIgnoresSessionStore() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        // The core Jon vs Alex sample is installed, with a longer log than the Studio sample's illustrative revision.
        try await CoreFixtureSessions.install(try CoreFixtureSessions.jonVsAlex(), bytes: Data("sample".utf8), in: sessions)
        let store = try scratch.store(sessions: sessions)
        try await StudioSampleContent(records: .load(from: StudioFixtures.url("records"))).install(into: store)

        let lock = try await store.lock(profile: Self.profile, output: Self.output, in: StudioSampleContent.matchProjectID)

        #expect(lock.eventRevision == 3)
        #expect(try await store.refreshEventLogVersion(for: StudioSampleContent.matchProjectID).eventLogVersion == 3)
    }
}
