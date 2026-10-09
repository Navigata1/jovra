import Foundation
import JovraMedia
import XCTest
@testable import Jovra

final class CaptureTextBoundaryTests: XCTestCase {
    func testChoicesValidateTrimmedUnicodeScalarLimits() {
        var choices = validChoices()
        choices.title = String(repeating: "a", count: 120)
        XCTAssertTrue(choices.isValid)
        choices.title += "a"
        XCTAssertFalse(choices.isValid, "session title maxLength120")
        choices.title = "Match"
        choices.playerA = String(repeating: "a", count: 60)
        XCTAssertTrue(choices.isValid)
        choices.playerA += "a"
        XCTAssertFalse(choices.isValid, "player displayName maxLength60")
        choices.playerA = String(repeating: "e\u{301}", count: 31)
        XCTAssertFalse(choices.isValid, "31 graphemes are62 Unicode scalars")
        choices.playerA = String(repeating: "🥎", count: 60)
        XCTAssertTrue(choices.isValid, "60 scalars remain valid despite120 UTF16 units")
        choices.title = String(repeating: "e\u{301}", count: 61)
        XCTAssertFalse(choices.isValid, "61 graphemes are122 Unicode scalars")
        choices.title = " Match "
        XCTAssertTrue(choices.isValid)
        XCTAssertEqual(choices.seed.title, "Match", "existing whitespace normalization is explicit")
    }

    func testAuthoritativeSeedRefusesOverlongRetainedTextBeforeCreatingAnySession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let valid = validChoices().seed
        var seeds = [CaptureSessionSeed]()
        for title in [String(repeating: "a", count: 121), String(repeating: "e\u{301}", count: 61), String(repeating: "a", count: 120) + " "] {
            var seed = valid; seed.title = title; seeds.append(seed)
        }
        for name in [String(repeating: "a", count: 61), String(repeating: "e\u{301}", count: 31)] {
            var seed = valid; seed.players[0].displayName = name; seeds.append(seed)
        }
        for seed in seeds {
            do {
                _ = try await library.createCapture(seed, mode: .simulatorFixture)
                XCTFail("schema-invalid retained text was accepted")
            } catch LocalCaptureLibraryError.invalidSinglesSetup { }
            catch { XCTFail("unexpected refusal: \(error)") }
        }
        let summaries = try await library.sessions()
        XCTAssertTrue(summaries.isEmpty, "refusal must precede any persisted session")
    }

    func testAcceptedExactBoundariesRoundTripWithoutSilentTruncation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        var choices = validChoices()
        choices.title = String(repeating: "e\u{301}", count: 60)
        choices.playerA = String(repeating: "🥎", count: 60)
        choices.playerB = String(repeating: "e\u{301}", count: 30)
        XCTAssertTrue(choices.isValid)
        let seed = choices.seed
        let id = try await library.createCapture(seed, mode: .simulatorFixture)
        let saved = try await library.load(id)
        XCTAssertEqual(saved.title, seed.title)
        XCTAssertEqual(saved.title.unicodeScalars.count, 120)
        XCTAssertEqual(saved.players.map { $0.displayName.unicodeScalars.count }, [60, 60])
        XCTAssertEqual(saved.players.map(\.displayName), seed.players.map(\.displayName))
    }

    private func validChoices() -> CaptureSetupChoices {
        var choices = CaptureSetupChoices()
        choices.title = "Match"; choices.playerA = "Jon"; choices.playerB = "Alex"
        return choices
    }
}
