import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// studio.json is written temp-then-rename (ADR-0002 pattern): a process that dies between the flushed temporary file
/// and the rename leaves the previous document intact, and the index is a disposable cache rebuilt from folders.
@Suite("Studio project store: durability and the index")
struct ProjectStoreDurabilityTests {
    @Test("a created project reloads from its folder in a new store with the same kind and no sources")
    func createReloads() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let project = try await scratch.store().create(kind: .match)

        let reloaded = try await scratch.store().project(project.projectId)

        #expect(reloaded == project)
        #expect(reloaded.kind == .match)
        #expect(reloaded.sources.isEmpty)
        #expect(reloaded.sample == false)
        #expect(reloaded.createdAt == "2026-10-07T22:30:00Z")
        let studioJSON = scratch.studio.appendingPathComponent("projects/\(project.projectId)/studio.json")
        #expect(FileManager.default.fileExists(atPath: studioJSON.path))
    }

    @Test("a process killed after the temporary write and before the rename leaves the previous studio.json loadable")
    func killBeforeRenameKeepsPrevious() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let project = try await scratch.store().create(kind: .match)
        let file = scratch.studio.appendingPathComponent("projects/\(project.projectId)/studio.json")
        let before = try Data(contentsOf: file)

        let dying = try scratch.store(writeFault: { checkpoint in
            if case .temporaryFileFlushed = checkpoint { throw SimulatedProcessDeath() }
        })
        await #expect(throws: SimulatedProcessDeath.self) {
            try await dying.addSource(sessionId: "session-a", slot: .nearBaseline, to: project.projectId)
        }

        // The process "restarts": a new store reads the untouched previous document; the orphan temp file is ignored.
        #expect(try Data(contentsOf: file) == before)
        let reloaded = try await scratch.store().project(project.projectId)
        #expect(reloaded == project)
        #expect(reloaded.revisions.sourceManifestRevision == 0)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            .filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.count == 1)
        if ProcessInfo.processInfo.environment["JOVRA_EVIDENCE"] == "1" {
            print("fault-injection: died at temporaryFileFlushed; studio.json bytes unchanged (\(before.count) B);",
                  "orphan temp file \(leftovers[0]) ignored; reloaded revision", reloaded.revisions.sourceManifestRevision)
        }
    }

    @Test("a process killed after the rename has committed the new studio.json")
    func killAfterRenameCommitted() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let project = try await scratch.store().create(kind: .match)
        let dying = try scratch.store(writeFault: { checkpoint in
            if case .documentRenamed = checkpoint { throw SimulatedProcessDeath() }
        })
        await #expect(throws: SimulatedProcessDeath.self) {
            try await dying.addSource(sessionId: "session-a", slot: .nearBaseline, to: project.projectId)
        }

        let reloaded = try await scratch.store().project(project.projectId)
        #expect(reloaded.sources.map(\.sessionId) == ["session-a"])
        #expect(reloaded.revisions.sourceManifestRevision == 1)
    }

    @Test("a corrupted index is rebuilt from the project folders with the same project list")
    func corruptedIndexRebuilt() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let a = try await store.create(kind: .match)
        let b = try await store.create(kind: .lessonSeries)
        let before = try await store.projects()
        #expect(Set(before.map(\.projectId)) == [a.projectId, b.projectId])

        let index = scratch.studio.appendingPathComponent("index.json")
        try Data("{\"projects\": [ truncated".utf8).write(to: index)
        let after = try await scratch.store().projects()

        #expect(after == before)
        // The rebuilt index is readable again.
        #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: index)) is [String: Any])
    }

    @Test("a missing index, or one that names a folder that is gone, is rebuilt from folders")
    func missingOrStaleIndexRebuilt() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        let a = try await store.create(kind: .match)
        let b = try await store.create(kind: .match)
        let index = scratch.studio.appendingPathComponent("index.json")
        let stale = try Data(contentsOf: index)

        try FileManager.default.removeItem(at: index)
        #expect(Set(try await scratch.store().projects().map(\.projectId)) == [a.projectId, b.projectId])

        try FileManager.default.removeItem(at: scratch.studio.appendingPathComponent("projects/\(b.projectId)"))
        try stale.write(to: index)
        #expect(try await scratch.store().projects().map(\.projectId) == [a.projectId])
    }

    @Test("an unknown project id is refused, and a path-like id never reaches the filesystem")
    func unknownAndUnsafeIDs() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let store = try scratch.store()
        await #expect(throws: StudioProjectStoreError.notFound) { try await store.project("no-such-project") }
        await #expect(throws: StudioProjectStoreError.invalidID) { try await store.project("../core") }
    }
}
