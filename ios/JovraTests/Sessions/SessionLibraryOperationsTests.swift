import Foundation
import JovraCore
import Testing
@testable import Jovra

/// The library's operations through the app's one local store: listing entries, Trash with Undo, the
/// confirmed purge, quarantine and the launch seeds the UI tests use.
@Suite("Session library operations")
struct SessionLibraryOperationsTests {
    private func makeLibrary(seed: LibraryLaunchSeed? = nil) throws -> (LocalCaptureLibrary, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        return (try LocalCaptureLibrary(root: root, launchSeed: seed), root)
    }

    @Test("the facet seed covers every original, analysis, review and archive state, all labelled Sample")
    func facetSeedCoversEveryState() async throws {
        let (library, root) = try makeLibrary(seed: .facets)
        defer { try? FileManager.default.removeItem(at: root) }
        let listing = try await library.libraryEntries()
        let all = listing.entries + listing.trashed
        #expect(all.allSatisfy { $0.isSample })
        #expect(Set(all.compactMap(\.original)) == Set(SessionOriginalStateState.allCases))
        #expect(Set(all.map(\.analysis)) == Set(SessionAnalysisState.allCases))
        #expect(Set(all.map(\.review)) == Set(SessionReviewState.allCases))
        #expect(Set(all.map(\.archive)) == Set(SessionArchiveStateState.allCases))
        #expect(listing.trashed.map(\.id) == [LibraryFixtures.trashedID])
        #expect(listing.quarantined.map(\.sessionID) == [LibraryFixtures.quarantinedID])
        #expect(listing.quarantined.first?.reason.isEmpty == false)
        #expect(!listing.entries.contains { $0.id == LibraryFixtures.quarantinedID }, "the others still list")
    }

    @Test("delete moves to Trash, Undo restores the exact original state, purge needs the store's confirmation")
    func trashUndoPurge() async throws {
        let (library, root) = try makeLibrary(seed: .facets)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try #require(try await library.libraryEntries().entries.first { $0.original == .savedWithGaps })
        try await library.trash(SessionID(rawValue: first.id))
        var listing = try await library.libraryEntries()
        #expect(!listing.entries.contains { $0.id == first.id })
        #expect(listing.trashed.contains { $0.id == first.id })
        try await library.restore(SessionID(rawValue: first.id))
        listing = try await library.libraryEntries()
        #expect(listing.entries.first { $0.id == first.id }?.original == .savedWithGaps)

        try await library.trash(SessionID(rawValue: first.id))
        try await library.purge(SessionID(rawValue: first.id))
        listing = try await library.libraryEntries()
        #expect(!(listing.entries + listing.trashed).contains { $0.id == first.id })
    }

    @Test("Trash is never emptied by listing or relaunching")
    func trashIsKept() async throws {
        let (library, root) = try makeLibrary(seed: .facets)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await library.libraryEntries()
        let reopened = try LocalCaptureLibrary(root: root)
        #expect(try await reopened.libraryEntries().trashed.map(\.id) == [LibraryFixtures.trashedID])
    }

    @Test("a lost index is rebuilt from the session folders")
    func lostIndexIsRebuilt() async throws {
        let (library, root) = try makeLibrary(seed: .facets)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try await library.libraryEntries().entries.map(\.id)
        try? FileManager.default.removeItem(at: root.appendingPathComponent("index.json"))
        let reopened = try LocalCaptureLibrary(root: root)
        #expect(try await reopened.libraryEntries().entries.map(\.id) == before)
    }

    @Test("the deep-link lookup reads the stored library: the newest real match, never a sample")
    func lookupReadsTheLibrary() async throws {
        let (library, root) = try makeLibrary(seed: .facets)
        defer { try? FileManager.default.removeItem(at: root) }
        let lookup = LibrarySessionLookup(library: .ready(library))
        let summaries = await lookup.summaries()
        #expect(!summaries.isEmpty)
        #expect(summaries.allSatisfy { $0.isSample })
        #expect(await lookup.newestRealMatch() == nil)
    }

    @Test("launch arguments for the walking skeleton and the facet library parse and round-trip")
    func launchArguments() {
        let parsed = LaunchConfiguration(arguments: ["Jovra", "-library", "facets", "-recordFixtureSession", "10"])
        #expect(parsed.library == .facets)
        #expect(parsed.recordFixtureSessionSeconds == 10)
        #expect(parsed.problems.isEmpty)
        #expect(LaunchConfiguration(arguments: ["Jovra"] + parsed.arguments) == parsed)
        #expect(LaunchConfiguration(arguments: ["Jovra", "-recordFixtureSession", "0"]).problems ==
                ["-recordFixtureSession: unknown value “0” (expected whole seconds from 1 to 120)"])
    }
}
