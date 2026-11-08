import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// No delete scope reaches an original (stories 165, 225): every original's bytes and SHA-256 are the same after each
/// scope, hashed by the system tool before and after.
@Suite("Studio project store: delete scopes and films")
struct ProjectDeleteScopeTests {
    /// A project with two real angles, a film, a proxy and a cloud-copy record, plus a link to an original planted
    /// inside the derived folders (a deletion must remove the link, never follow it).
    private struct Fixture {
        let scratch: ProjectScratch
        let store: StudioProjectStore
        let projectId: String
        let originals: [URL]

        static func make() async throws -> Fixture {
            let scratch = try ProjectScratch()
            let sessions = try SessionStore(root: scratch.core)
            let copies = try CoreFixtureSessions.realCopies()
            var originals: [URL] = []
            for (index, session) in copies.prefix(2).enumerated() {
                originals.append(try await CoreFixtureSessions.install(
                    session, bytes: Data((0..<65_536).map { UInt8(truncatingIfNeeded: $0 &* (index + 3)) }), in: sessions))
            }
            let store = try scratch.store(sessions: sessions)
            let id = try await store.create(kind: .match, primarySession: copies[0].id).projectId
            try await store.addSource(sessionId: copies[1].id, slot: .farBaseline, to: id)
            let folder = scratch.studio.appendingPathComponent("projects/\(id)")
            for name in ["films", "proxies", "cloud"] {
                try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            try Data(repeating: 1, count: 2_000).write(to: folder.appendingPathComponent("films/film-a.mp4"))
            try Data(repeating: 2, count: 3_000).write(to: folder.appendingPathComponent("proxies/camera-1.render.mov"))
            try Data("{}".utf8).write(to: folder.appendingPathComponent("cloud/copies.json"))
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("proxies/original-link.mov"),
                                                       withDestinationURL: originals[0])
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("films/session-link"),
                                                       withDestinationURL: originals[1].deletingLastPathComponent())
            return Fixture(scratch: scratch, store: store, projectId: id, originals: originals)
        }

        var folder: URL { scratch.studio.appendingPathComponent("projects/\(projectId)") }
        func hashes() throws -> [String] { try originals.map(systemSHA256) }
        func sizes() throws -> [Int] {
            try originals.map { try (FileManager.default.attributesOfItem(atPath: $0.path)[.size] as! NSNumber).intValue }
        }
    }

    @Test("each delete scope leaves every original's bytes and SHA-256 unchanged", arguments: StudioDeleteScope.allCases)
    func scopesNeverTouchOriginals(scope: StudioDeleteScope) async throws {
        let fixture = try await Fixture.make(); defer { fixture.scratch.cleanUp() }
        let hashesBefore = try fixture.hashes()
        let sizesBefore = try fixture.sizes()
        let bytesBefore = try fixture.originals.map { try Data(contentsOf: $0) }

        try await fixture.store.delete(scope, of: fixture.projectId)

        #expect(try fixture.hashes() == hashesBefore)
        #expect(try fixture.sizes() == sizesBefore)
        #expect(try fixture.originals.map { try Data(contentsOf: $0) } == bytesBefore)
        if ProcessInfo.processInfo.environment["JOVRA_EVIDENCE"] == "1" {
            print("delete(\(scope.rawValue)): originals sha256 before \(hashesBefore) after \(try fixture.hashes())")
        }
    }

    @Test("derived removes films and proxies only; cloudCopies removes the cloud record only; project removes the folder")
    func scopesRemoveTheirFolders() async throws {
        let fixture = try await Fixture.make(); defer { fixture.scratch.cleanUp() }
        let store = fixture.store
        let id = fixture.projectId
        #expect(try await store.storage(id) == StudioProjectStorage(filmsBytes: 2_000, proxiesBytes: 3_000))

        try await store.delete(.derived, of: id)
        let afterDerived = Set(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path))
        #expect(afterDerived == ["studio.json", "cloud"])
        #expect(try await store.storage(id) == StudioProjectStorage(filmsBytes: 0, proxiesBytes: 0))
        #expect(try await store.project(id).sources.count == 2)

        try await store.delete(.cloudCopies, of: id)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["studio.json"])

        try await store.delete(.project, of: id)
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.path))
        #expect(try await store.projects().isEmpty)
        await #expect(throws: StudioProjectStoreError.notFound) { try await store.project(id) }
    }

    @Test("a rebuilt film is kept beside the older version, never overwriting it, and both are listed")
    func filmVersionsKept() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let sample = try StudioContractCodec.decode(DeliveredArtifact.self,
                                                    from: StudioFixtures.data("records/delivered-artifact.film.json"))
        let id = try await store.create(kind: .match).projectId
        var first = sample
        first.projectId = id
        first.sample = false
        var rebuilt = first
        rebuilt.artifactId = "film-court-memories-2"

        try await store.recordFilm(first, in: id)
        await #expect(throws: StudioProjectStoreError.filmExists(first.artifactId)) {
            try await store.recordFilm(first, in: id)
        }
        try await store.recordFilm(rebuilt, in: id)

        #expect(try await store.films(id).map(\.artifactId) == ["film-court-memories", "film-court-memories-2"])
        #expect(try await scratch.store().films(id) == [first, rebuilt])
        var foreign = first
        foreign.artifactId = "film-other"
        foreign.projectId = "another-project"
        await #expect(throws: StudioProjectStoreError.invalidRecord("film-other")) {
            try await store.recordFilm(foreign, in: id)
        }
    }
}
