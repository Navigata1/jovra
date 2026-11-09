import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

@Suite("Explicit Files match import", .serialized)
struct FilesImportMatchTests {
    private var selected: URL {
        MediaFixtureCatalog.repository().root.appendingPathComponent("ios/Jovra/Resources/Fixtures/fixture-camera-720p30.mp4")
    }

    @Test(arguments: [false, true])
    func incompleteFootageOrMissingPlayerDoesNotPublish(missingPlayer: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let service = FilesImportService(store: store)
        let setup = FilesImportMatchSetup(playerA: "Player A", playerB: missingPlayer ? " " : "Player B",
            format: .bestOfThree, gameScoring: .ad, firstServer: .a, nearPlayer: .b, containsFullMatch: missingPlayer)
        await #expect(throws: FilesImportError.invalidMatchSetup) {
            _ = try await service.importMatch(selected, setup: setup)
        }
        #expect(try await store.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".files-imports").path))
    }
}
