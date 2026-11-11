import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// SD20 in the project store (S35): a revision the store records runs staleness propagation over the project's stored
/// plans and films in the same transaction. Real (non-sample) fixture sessions from the shipped core library; the
/// plan and film are the Sample's court-memories-final plan and film, re-labelled for each real project.
@Suite("Keepers: staleness through the project store")
struct KeepersStoreStalenessTests {
    struct Fixture {
        let scratch: ProjectScratch
        let sessions: SessionStore
        let store: StudioProjectStore
        let projects: [String]
        let sessionIds: [String]
        let filmIds: [String]
    }

    /// Two real projects, each on its own real match session, each holding the final plan (bound to its project's
    /// current revisions) and a film rendered from it.
    static func fixture() async throws -> Fixture {
        let scratch = try ProjectScratch()
        let sessions = try SessionStore(root: scratch.core)
        let matches = Array(try CoreFixtureSessions.realCopies().filter { !($0.match?.log.isEmpty ?? true) }.prefix(2))
        #expect(matches.count == 2)
        let store = try scratch.store(sessions: sessions)
        var projects: [String] = [], films: [String] = []
        for (n, match) in matches.enumerated() {
            try await CoreFixtureSessions.install(match, bytes: Data("original \(n)".utf8), in: sessions)
            let id = try await store.create(kind: .match, primarySession: match.id).projectId
            try await store.recordSyncRevision(1, for: id)
            try await store.recordKeeperRevision(1, for: id)
            let event = try await store.revisions(id).eventLogVersion
            #expect(event > 0)
            var plan = try JSONSerialization.jsonObject(with: StudioFixtures.data("records/edit-plan.court-memories-final.json")) as! [String: Any]
            plan["projectId"] = id
            plan["sample"] = false
            var bindings = plan["bindings"] as! [String: Any]
            bindings["eventRevision"] = event
            bindings["syncRevision"] = 1
            bindings["keeperCatalogRevision"] = 1
            plan["bindings"] = bindings
            let planBytes = try JSONSerialization.data(withJSONObject: plan, options: [.sortedKeys])
            try await store.writeRecord(planBytes, named: "edit-plan.court-memories-final.json", in: .plans, of: id)
            var film = try StudioContractCodec.decode(DeliveredArtifact.self, from: StudioFixtures.data("records/delivered-artifact.film.json"))
            film.projectId = id
            film.sample = false
            film.artifactId = "film-\(n)"
            film.bindings.editPlanSha256 = systemSHA256Of(try CanonicalJSON.canonicalize(planBytes))
            film.bindings.eventRevision = event
            film.bindings.syncRevision = .value(1)
            try await store.recordFilm(film, in: id)
            projects.append(id)
            films.append(film.artifactId)
        }
        return Fixture(scratch: scratch, sessions: sessions, store: store, projects: projects, sessionIds: matches.map(\.id),
                       filmIds: films)
    }

    /// SHA-256 through the system tool, so the store's own hashing is never the oracle for the film's binding.
    static func systemSHA256Of(_ data: Data) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keepers-plan-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try! data.write(to: url)
        return try! systemSHA256(url)
    }

    /// A void of the session's first point, recorded after everything else: correcting an early point.
    static func voidFirstPoint(of sessionId: String, in sessions: SessionStore) async throws -> String {
        let log = try await sessions.load(sessionId).match!.log
        guard case .point(let first)? = log.first(where: { if case .point = $0 { true } else { false } }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let json: [String: Any] = ["id": "void-\(UUID().uuidString.lowercased())", "seq": (log.map(\.seq).max() ?? 0) + 1,
                                   "type": "void", "target": first.id]
        let event = try JSONDecoder().decode(SessionLogEvent.self, from: JSONSerialization.data(withJSONObject: json))
        try await sessions.append([event], to: sessionId)
        return first.id
    }

    @Test("correcting an early point stales the dependent plan and its film in the same transaction; another session's films stay current")
    func correctionStalesPlanAndFilm() async throws {
        let f = try await Self.fixture(); defer { f.scratch.cleanUp() }
        let (a, b) = (f.projects[0], f.projects[1])
        let before = try await f.store.staleness(a).result
        #expect(before.stalePlanIds.isEmpty && before.staleFilmIds.isEmpty)
        let oldVersion = try await f.store.revisions(a).eventLogVersion

        let voided = try await Self.voidFirstPoint(of: f.sessionIds[0], in: f.sessions)
        let revisions = try await f.store.refreshEventLogVersion(for: a)

        #expect(revisions.eventLogVersion == oldVersion + 1)
        let (after, lastChange) = try await f.store.staleness(a)
        #expect(after.stalePlanIds == ["court-memories-final"])
        #expect(after.plans.first?.reasons == [.eventRevision])
        #expect(after.films.map(\.label) == ["Made before a correction"])
        #expect(after.films.map(\.keptAsVersion) == [true])
        // the film record itself now says so, and is still there
        let film = try #require(try await f.store.films(a).first)
        #expect(film.artifactId == f.filmIds[0])
        #expect(film.stale == .value(DeliveredArtifactStale(reason: .eventRevision, currentEventRevision: oldVersion + 1)))
        // the core fold's recalculation (ScoringEngine.diff) is recorded: voiding the first point moves every later
        // score, so the next point is recalculated; the voided point itself is gone, not recalculated
        #expect(lastChange?.kind == "event" && lastChange?.revision == oldVersion + 1)
        #expect((lastChange?.named.count ?? 0) > 0 && !(lastChange?.named.contains(voided) ?? true))
        // a stale plan is refused for rendering (story 233)
        await #expect(throws: StudioProjectStoreError.planStale("court-memories-final")) {
            try await f.store.requireCurrentPlan("court-memories-final", in: a)
        }

        // the unrelated project's session did not change: its plan and film stay current, its record unlabelled
        _ = try await f.store.refreshEventLogVersion(for: b)
        let other = try await f.store.staleness(b).result
        #expect(other.stalePlanIds.isEmpty && other.staleFilmIds.isEmpty)
        #expect(try await f.store.films(b).first?.stale == .null)
        try await f.store.requireCurrentPlan("court-memories-final", in: b)
    }

    @Test("a sync or keeper change that spares the plan carries it forward; a later change it uses stales it")
    func sparedChangesCarryThePlan() async throws {
        let f = try await Self.fixture(); defer { f.scratch.cleanUp() }
        let a = f.projects[0]
        // the final plan cuts no camera-9 and uses no k-04 (the vectors' keeper-k04-change case)
        try await f.store.recordSyncRevision(2, changedSources: ["camera-9"], for: a)
        try await f.store.recordKeeperRevision(2, changedKeepers: ["k-04"], for: a)
        var now = try await f.store.staleness(a).result
        #expect(now.stalePlanIds.isEmpty && now.staleFilmIds.isEmpty)
        #expect(now.plans.first.map { [$0.bindings.syncRevision, $0.bindings.keeperCatalogRevision] } == [2, 2])

        // k-01 is in the final plan: stale for the keeper reason; the record has no keeper value, so it stays unlabelled
        // while the store's status says "Made before a correction"
        try await f.store.recordKeeperRevision(3, changedKeepers: ["k-01"], for: a)
        now = try await f.store.staleness(a).result
        #expect(now.stalePlanIds == ["court-memories-final"])
        #expect(now.films.first?.reasons == [.keeperRevision])
        #expect(now.films.first?.label == "Made before a correction")
        #expect(try await f.store.films(a).first?.stale == .null)

        // a later sync change on a source the plan uses adds the reason and labels the record
        try await f.store.recordSyncRevision(3, changedSources: ["camera-1"], for: a)
        now = try await f.store.staleness(a).result
        #expect(now.plans.first?.reasons == [.syncRevision, .keeperRevision])
        #expect(try await f.store.films(a).first?.stale.value?.reason == .syncRevision)
    }

    @Test("a correction found at lock time stales what was built before it")
    func lockAfterCorrection() async throws {
        let f = try await Self.fixture(); defer { f.scratch.cleanUp() }
        let a = f.projects[0]
        var manifest = try JSONSerialization.jsonObject(with: StudioFixtures.data("records/source-manifest.json")) as! [String: Any]
        manifest["sample"] = false
        manifest["projectId"] = a
        manifest["revision"] = try await f.store.revisions(a).sourceManifestRevision
        try await f.store.writeRecord(JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]),
                                      named: "source-manifest.json", in: .manifests, of: a)
        let participants = try StudioContractCodec.decode(ProjectLock.self, from: StudioFixtures.data("records/project-lock.json")).participants
        try await f.store.setParticipants(participants, owners: ["camera-1": participants[0].participantId], in: a)

        _ = try await Self.voidFirstPoint(of: f.sessionIds[0], in: f.sessions)
        let lock = try await f.store.lock(profile: ProjectLockProfile(id: .courtMemories, revision: 1),
                                          output: ProjectLockOutput(aspect: .v16_9, height: 1080, durationTargetSeconds: .value(258)), in: a)
        #expect(try await f.store.revisions(a).eventLogVersion == lock.eventRevision)
        #expect(try await f.store.staleness(a).result.staleFilmIds == [f.filmIds[0]])
    }

    @Test("a plan bound ahead of its project is refused and nothing is written")
    func futurePlanIsRefused() async throws {
        let f = try await Self.fixture(); defer { f.scratch.cleanUp() }
        let a = f.projects[0]
        var plan = try JSONSerialization.jsonObject(with: StudioFixtures.data("records/edit-plan.match-broadcast-set-1.json")) as! [String: Any]
        plan["projectId"] = a
        plan["sample"] = false
        var bindings = plan["bindings"] as! [String: Any]
        bindings["eventRevision"] = 10_000
        bindings["syncRevision"] = 1
        bindings["keeperCatalogRevision"] = 1
        plan["bindings"] = bindings
        try await f.store.writeRecord(JSONSerialization.data(withJSONObject: plan, options: [.sortedKeys]),
                                      named: "edit-plan.match-broadcast-set-1.json", in: .plans, of: a)
        let before = try await f.store.revisions(a)
        await #expect(throws: StudioProjectStoreError.stalenessRefused("futureRevision")) {
            try await f.store.recordSyncRevision(2, changedSources: ["camera-1"], for: a)
        }
        #expect(try await f.store.revisions(a) == before)
        #expect(try await f.store.films(a).first?.stale == .null)
    }
}
