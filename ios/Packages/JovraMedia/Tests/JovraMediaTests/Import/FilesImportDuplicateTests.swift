import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

@Suite("Files import duplicate custody", .serialized)
struct FilesImportDuplicateTests {
    @Test func aRenamedIdenticalSelectionDoesNotPublishASecondSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let service = FilesImportService(store: store)
        let renamed = root.appendingPathComponent("different name.mp4")
        try FileManager.default.copyItem(at: fixture, to: renamed)
        let first = try await service.importVideo(fixture, playerName: "First")
        let duplicate = try await findDuplicate(service, from: renamed)
        #expect(duplicate.sessionID == first)
        #expect(try await service.verifyExistingDuplicate(duplicate) == first)
        #expect(try await store.list().map(\.id) == [first])
        #expect(try stagedImports(in: root).isEmpty)
    }

    @Test func explicitDuplicatePermissionIsBoundToBytesAndPreservesBothSessions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let service = FilesImportService(store: store)
        let first = try await service.importVideo(fixture, playerName: "Practice")
        let original = try await store.load(first)
        let duplicate = try await findDuplicate(service, from: fixture)

        let differentFolder = root.appendingPathComponent("different")
        try FileManager.default.createDirectory(at: differentFolder, withIntermediateDirectories: false)
        let differentBytes = differentFolder.appendingPathComponent(fixture.lastPathComponent)
        var altered = try Data(contentsOf: fixture)
        // The bundled MP4 starts with an 'ftyp' box. Change its minor brand version, leaving length
        // and all encoded media unchanged, so a length-only or name-based lookup cannot pass.
        try #require(Array(altered[4..<8]) == Array("ftyp".utf8))
        altered[15] ^= 1
        try altered.write(to: differentBytes)
        await #expect(throws: FilesImportError.differentDuplicateSelection) {
            _ = try await service.importVideo(differentBytes, playerName: "Different", importingAgain: duplicate.fingerprint)
        }
        #expect(try await store.list().map(\.id) == [first])
        let different = try await service.importVideo(differentBytes, playerName: "Different")
        #expect(different != first)

        let setup = FilesImportMatchSetup(playerA: "Player A", playerB: "Player B", format: .bestOfOne,
            gameScoring: .ad, firstServer: .a, nearPlayer: .b, containsFullMatch: true)
        do {
            _ = try await service.importMatch(fixture, setup: setup)
            Issue.record("Matching bytes must still be offered as a duplicate under a different setup")
        } catch FilesImportError.duplicate(let matchDuplicate) {
            #expect(matchDuplicate.sessionID == first)
        }
        let second = try await service.importMatch(fixture, setup: setup, importingAgain: duplicate.fingerprint)
        let match = try await store.load(second)
        #expect(second != first)
        #expect(match.sessionKind == .match)
        #expect(match.match?.log.isEmpty == true)
        #expect(try await store.load(first) == original)
        for id in [first, second] {
            let directory = try await store.sessionDirectory(id)
            let copy = try Data(contentsOf: directory.appendingPathComponent("originals/source.mp4"))
            #expect(copy == (try Data(contentsOf: fixture)))
        }
        #expect(try stagedImports(in: root).isEmpty)
    }

    @Test func concurrentDefaultImportsOnlyPublishOneSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let service = FilesImportService(store: store)
        let source = fixture
        let results = try await withThrowingTaskGroup(of: (id: String, existing: Bool).self) { group in
            for name in ["First", "Second"] {
                group.addTask {
                    do { return (try await service.importVideo(source, playerName: name), false) }
                    catch FilesImportError.duplicate(let duplicate) { return (duplicate.sessionID, true) }
                }
            }
            return try await group.reduce(into: [(id: String, existing: Bool)]()) { $0.append($1) }
        }
        #expect(results.count == 2)
        #expect(results.filter(\.existing).count == 1)
        #expect(Set(results.map(\.id)).count == 1)
        #expect(try await store.list().count == 1)
        #expect(try stagedImports(in: root).isEmpty)
    }

    enum IncumbentChange: CaseIterable, Sendable { case removed, replaced, linked }

    @Test(arguments: IncumbentChange.allCases)
    func anUnownedOrChangedOriginalIsNeverOfferedForOpening(change: IncumbentChange) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let service = FilesImportService(store: store)
        let first = try await service.importVideo(fixture, playerName: "First")
        let duplicate = try await findDuplicate(service, from: fixture)
        let directory = try await store.sessionDirectory(first)
        let existing = directory.appendingPathComponent("originals/source.mp4")
        switch change {
        case .removed:
            try FileManager.default.removeItem(at: existing)
        case .replaced:
            var changed = try Data(contentsOf: existing)
            changed[changed.count - 1] ^= 1
            try changed.write(to: existing)
        case .linked:
            try FileManager.default.removeItem(at: existing)
            try FileManager.default.createSymbolicLink(at: existing, withDestinationURL: fixture)
        }
        await #expect(throws: FilesImportError.duplicateUnverified(duplicate.fingerprint)) {
            _ = try await service.verifyExistingDuplicate(duplicate)
        }
        await #expect(throws: FilesImportError.duplicateUnverified(duplicate.fingerprint)) {
            _ = try await service.importVideo(fixture, playerName: "Second")
        }
        #expect(try await store.list().map(\.id) == [first])
        #expect(try stagedImports(in: root).isEmpty)
    }

    @Test func trashedAndSampleImportsAreNeverOfferedForOpening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let service = FilesImportService(store: store)
        let first = try await service.importVideo(fixture, playerName: "Original")
        let duplicate = try await findDuplicate(service, from: fixture)

        var sample = try await store.load(first)
        sample.id = "sample"
        sample.sample = .init(synthetic: true, generator: "duplicate-test")
        try await store.create(sample)
        let sampleFolder = try await store.sessionDirectory(sample.id).appendingPathComponent("originals")
        try FileManager.default.createDirectory(at: sampleFolder, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: fixture, to: sampleFolder.appendingPathComponent("source.mp4"))
        try await store.trash(first)

        await #expect(throws: FilesImportError.duplicateUnverified(duplicate.fingerprint)) {
            _ = try await service.verifyExistingDuplicate(duplicate)
        }
        let fresh = try await service.importVideo(fixture, playerName: "Fresh")
        #expect(fresh != first)
        #expect(try await store.load(first).original?.state == .trashed)
        #expect(try await store.load(sample.id) == sample)
        #expect(try stagedImports(in: root).isEmpty)
    }

    @Test func cancelledOrReplacedStagingNeverPublishes() async throws {
        enum Fault: CaseIterable { case cancellation, replacement }
        let originalBytes = try Data(contentsOf: fixture)
        for fault in Fault.allCases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try SessionStore(root: root) { checkpoint in
                guard case .documentRenamed(let url) = checkpoint, url.pathComponents.contains(".files-imports") else { return }
                switch fault {
                case .cancellation:
                    withUnsafeCurrentTask { $0?.cancel() }
                case .replacement:
                    let staged = url.deletingLastPathComponent().appendingPathComponent("originals/source.mp4")
                    try originalBytes.write(to: staged, options: .atomic)
                }
            }
            let source = fixture
            let operation = Task { try await FilesImportService(store: store).importVideo(source, playerName: "Player") }
            do {
                _ = try await operation.value
                Issue.record("Unverified staging was published")
            } catch {
                #expect((error is CancellationError) == (fault == .cancellation))
            }
            #expect(try await store.list().isEmpty)
            #expect(try stagedImports(in: root).isEmpty)
        }
        #expect(try Data(contentsOf: fixture) == originalBytes)
    }

    private func findDuplicate(_ service: FilesImportService, from source: URL) async throws -> FilesImportDuplicate {
        do {
            _ = try await service.importVideo(source, playerName: "Selected")
            throw CocoaError(.fileWriteFileExists)
        } catch FilesImportError.duplicate(let duplicate) {
            return duplicate
        }
    }

    private func stagedImports(in root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".files-imports").path)
    }

    private var fixture: URL {
        MediaFixtureCatalog.repository().root.appendingPathComponent("ios/Jovra/Resources/Fixtures/fixture-camera-720p30.mp4")
    }
}
