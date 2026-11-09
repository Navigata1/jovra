import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// `StudioEntitlements.localStudio` (SD2, D-4): true in every build; when a build sets it false, the store refuses new
/// Studio film projects and locks with the stated reason, while originals, exports, films already made and core
/// features stay available.
@Suite("Studio project store: the localStudio entitlement")
struct ProjectEntitlementsTests {
    @Test("localStudio is true in this build unless it is the explicit JOVRA_STUDIO_LOCAL_OFF scratch build")
    func buildValue() {
        #if JOVRA_STUDIO_LOCAL_OFF
        #expect(StudioEntitlements.build.localStudio == false)
        #else
        #expect(StudioEntitlements.build.localStudio == true)
        #endif
    }

    @Test("the entitlement source holds no DEBUG or RELEASE condition, so every build configuration reads the same value")
    func noConfigurationCondition() throws {
        let source = try String(contentsOf: StudioFixtures.repositoryRoot().appendingPathComponent(
            "ios/Packages/JovraStudioCore/Sources/JovraStudioCore/Entitlements/StudioEntitlements.swift"), encoding: .utf8)
        let conditions = source.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#if") }
        #expect(conditions == ["        #if JOVRA_STUDIO_LOCAL_OFF"])
    }

    @Test("a store reading this build's entitlement creates a project, unless this is the localStudio-off scratch build")
    func buildDefaultStore() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try StudioProjectStore(root: scratch.studio)
        #expect(store.entitlements == StudioEntitlements.build)
        #if JOVRA_STUDIO_LOCAL_OFF
        await #expect(throws: StudioProjectStoreError.localStudioUnavailable(reason: StudioEntitlements.localStudioUnavailableReason)) {
            try await store.create(kind: .match)
        }
        #else
        #expect(try await store.create(kind: .match).kind == .match)
        #endif
    }

    @Test("with localStudio off, creating a Studio film project is refused with the stated reason")
    func refusesCreate() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store(entitlements: StudioEntitlements(localStudio: false))

        await #expect(throws: StudioProjectStoreError.localStudioUnavailable(
            reason: "Studio films aren't available in this version of JOVRA. Your recordings, exports and films you already made stay available.")) {
            try await store.create(kind: .match)
        }
        #expect(try await store.projects().isEmpty)
    }

    @Test("with localStudio off, a film already made, the original, its export and the core library stay available")
    func everythingElseStaysAvailable() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        let real = try CoreFixtureSessions.realCopies()[0]
        let original = try await CoreFixtureSessions.install(real, bytes: Data(repeating: 9, count: 8_192), in: sessions)
        let hashBefore = try systemSHA256(original)
        // A project and film made while the entitlement was on.
        let on = try scratch.store(sessions: sessions)
        let id = try await on.create(kind: .match, primarySession: real.id).projectId
        var film = try StudioContractCodec.decode(DeliveredArtifact.self,
                                                  from: StudioFixtures.data("records/delivered-artifact.film.json"))
        film.projectId = id
        film.sample = false
        try await on.recordFilm(film, in: id)

        let off = try scratch.store(entitlements: StudioEntitlements(localStudio: false), sessions: sessions)

        #expect(try await off.films(id) == [film])
        #expect(try await off.project(id).primarySource?.sessionId == real.id)
        await #expect(throws: StudioProjectStoreError.self) {
            try await off.lock(profile: .init(id: .courtMemories, revision: 1),
                               output: .init(aspect: .v16_9, height: 1080, durationTargetSeconds: .null), in: id)
        }
        // Core features: the library lists the session, its original reads back unchanged, a data export is built.
        #expect(try await sessions.list().map(\.id) == [real.id])
        #expect(try systemSHA256(original) == hashBefore)
        let document = try await sessions.load(real.id)
        let export = try DataExporter.exportSession(document)
        #expect(!export.pointsCSV.isEmpty)
        #expect(!export.sessionJSON.isEmpty)
        // Cleanup still works: derived output can be deleted.
        try await off.delete(.derived, of: id)
        #expect(try await off.films(id).isEmpty)
    }
}
