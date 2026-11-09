import Foundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

final class FilesImportDuplicateChoiceTests: XCTestCase {
    @MainActor
    func testOpenExistingAndNewSelectionPreserveTheOriginalSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let selected = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let original = try await library.importFile(selected, playerName: "Original")
        let first = try await library.load(original)
        let duplicate = try await duplicate(in: library, for: selected)
        let existing = try await library.verifyExistingDuplicate(duplicate)
        XCTAssertEqual(existing, original)
        let initialRows = try await library.sessions()
        XCTAssertEqual(initialRows.map(\.id), [original.rawValue])

        var decision = ImportDuplicateDecision(intent: .practice(playerName: "Separate copy"),
                                               fingerprint: duplicate.fingerprint, existing: duplicate)
        let request = try XCTUnwrap(decision.makeRetryRequest())
        let newSelection = root.appendingPathComponent("Renamed selection.mp4")
        var different = try Data(contentsOf: selected)
        XCTAssertEqual(Array(different[4..<8]), Array("ftyp".utf8))
        different[15] ^= 1
        try different.write(to: newSelection)
        do {
            _ = try await library.importFile(newSelection, playerName: "Separate copy",
                                             importingAgain: request.duplicatePermission)
            XCTFail("A replacement selection must not receive the duplicate authorization")
        } catch FilesImportError.differentDuplicateSelection {}

        let refusedRows = try await library.sessions()
        XCTAssertEqual(refusedRows.map(\.id), [original.rawValue])
        let retry = try XCTUnwrap(decision.makeRetryRequest())
        try Data(contentsOf: selected).write(to: newSelection)
        let copy = try await library.importFile(newSelection, playerName: "Separate copy",
                                                importingAgain: retry.duplicatePermission)
        XCTAssertNotEqual(copy, original)
        let retainedOriginal = try await library.load(original)
        XCTAssertEqual(retainedOriginal, first)
        let finalRows = try await library.sessions()
        XCTAssertEqual(Set(finalRows.map(\.id)), [original.rawValue, copy.rawValue])
    }

    @MainActor
    func testMatchRetryRequiresAndConsumesFreshAttestationBeforePicker() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let selected = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        _ = try await library.importFile(selected, playerName: "Practice")
        let duplicate = try await duplicate(in: library, for: selected)
        let setup = FilesImportMatchSetup(playerA: "Ada", playerB: "Sam", format: .bestOfOne, gameScoring: .noAd,
                                          firstServer: .b, nearPlayer: .a, containsFullMatch: true)
        var decision = ImportDuplicateDecision(intent: .match(setup), fingerprint: duplicate.fingerprint, existing: duplicate)
        XCTAssertNil(decision.makeRetryRequest(), "Original consent cannot arm a second Files selection")
        decision.confirmsFullMatch = true
        let request = try XCTUnwrap(decision.makeRetryRequest())
        XCTAssertEqual(request.duplicatePermission, duplicate.fingerprint)
        guard case .match(let frozen) = request.intent else { return XCTFail("Retry changed the original intent") }
        XCTAssertEqual(frozen.playerA, setup.playerA)
        XCTAssertEqual(frozen.firstServer, setup.firstServer)
        XCTAssertNil(decision.makeRetryRequest(), "Picker cancellation cannot carry the confirmation into a new picker")
    }

    @MainActor
    private func duplicate(in library: LocalCaptureLibrary, for source: URL) async throws -> FilesImportDuplicate {
        do {
            _ = try await library.importFile(source, playerName: "Later")
            XCTFail("Duplicate import published")
            throw CocoaError(.fileWriteFileExists)
        } catch FilesImportError.duplicate(let duplicate) {
            return duplicate
        }
    }
}
