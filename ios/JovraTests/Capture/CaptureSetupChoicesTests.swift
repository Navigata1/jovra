import Foundation
import XCTest
@testable import Jovra

final class CaptureSetupChoicesTests: XCTestCase {
    func testLegacyRestorationKeepsUnsupportedKindWithoutReplacingItWithSingles() throws {
        let restored = try JSONDecoder().decode(SessionSetupDraft.self, from: Data(#"{"kind":"doublesMatch"}"#.utf8))
        XCTAssertEqual(restored.kind, .doublesMatch)
        XCTAssertNil(restored.captureChoices)
    }

    func testChosenNamesFormatAndTossSurviveRestorationAndSeedTheRecording() throws {
        var choices = CaptureSetupChoices()
        choices.title = "Saturday lesson"
        choices.playerA = "Jon"
        choices.playerB = "Alex"
        choices.format = .bestOfOne
        choices.noAd = true
        choices.firstServer = .b
        choices.nearPlayer = .b
        let draft = SessionSetupDraft(kind: .singlesMatch, captureChoices: choices)
        let restored = try JSONDecoder().decode(SessionSetupDraft.self, from: JSONEncoder().encode(draft))
        let seed = try XCTUnwrap(restored.captureChoices).seed
        XCTAssertEqual(seed.title, "Saturday lesson")
        XCTAssertEqual(seed.players.map(\.displayName), ["Jon", "Alex"])
        XCTAssertEqual(seed.format.presetId, .bestOf1)
        XCTAssertEqual(seed.format.gameScoring, .noAd)
        XCTAssertEqual(seed.toss.firstServer, seed.players[1].id)
        XCTAssertEqual(seed.toss.startingEnds.A, .far)
        XCTAssertEqual(seed.toss.startingEnds.B, .near)
    }
}
