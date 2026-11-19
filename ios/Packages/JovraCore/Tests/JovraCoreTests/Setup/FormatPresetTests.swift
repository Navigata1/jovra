import Foundation
import Testing
@testable import JovraCore

/// T21: every format preset is the format of a scoring fixture, and a session setup built in the app's
/// terms (seats, first server, starting end) is the same match setup the fixture decodes to.
struct FormatPresetTests {
    /// Preset → a scoring fixture played in that format (spec/fixtures/scoring).
    static let fixtures: [(FormatPreset, String)] = [
        (.clubBestOf3, "S09-seven-five"),
        (.matchTiebreakThird, "S15-match-tiebreak"),
        (.noAdMatchTiebreak, "S05-noad-deciding-server"),
        (.bestOf5, "S23-best-of-5"),
        (.proSet8, "S18-pro-set"),
        (.shortSets, "S19-short-set-4-4"),
        (.fast4, "S21-fast4"),
        (.tiebreak7, "S70-standalone-tiebreak-7"),
        (.tiebreak10, "S24-standalone-tiebreak"),
        (.oneSet, "S12-best-of-1-tiebreak-loss"),
    ]

    static func fixture(_ id: String) throws -> ScoringFixture {
        let path = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/scoring/\(id).json")
        return try JSONDecoder().decode(ScoringFixture.self, from: Data(contentsOf: path))
    }

    /// The session setup a player would enter for a singles fixture: the fixture's two players in the
    /// "me" and "opponent" seats, its first server and its starting end.
    static func singlesSetup(for input: ScoringInput, preset: FormatPreset) throws -> SessionSetup {
        let a = try #require(input.players.first { $0.id == input.sides.A[0] })
        let b = try #require(input.players.first { $0.id == input.sides.B[0] })
        var setup = SessionSetup()
        setup.mode = .singlesMatch
        setup.me = .init(id: a.id, name: a.displayName, handedness: a.handedness, backhand: a.backhand)
        setup.opponent = .init(id: b.id, name: b.displayName, handedness: b.handedness, backhand: b.backhand)
        setup.format = FormatChoice(preset: preset)
        setup.firstServer = input.toss.firstServer == a.id ? .me : .opponent
        setup.myTeamStartsNear = input.toss.startingEnds.A == .near
        return setup
    }

    @Test("every preset with a fixture equals the setup decoded from that fixture",
          arguments: fixtures.map { PresetCase(preset: $0.0, fixtureID: $0.1) })
    func presetEqualsFixtureSetup(_ testCase: PresetCase) throws {
        let fixture = try Self.fixture(testCase.fixtureID)
        let decoded = MatchSetup(fixture.input)
        #expect(testCase.preset.format == fixture.input.format, "\(testCase.fixtureID) format")
        let setup = try Self.singlesSetup(for: fixture.input, preset: testCase.preset)
        #expect(try setup.matchSetup() == decoded, "\(testCase.fixtureID)")
    }

    @Test("a canned point sequence folds to the fixture's reference result for every preset",
          arguments: fixtures.map { PresetCase(preset: $0.0, fixtureID: $0.1) })
    func cannedSequenceFoldsToReference(_ testCase: PresetCase) throws {
        let fixture = try Self.fixture(testCase.fixtureID)
        let checkpoints = try #require(fixture.checkpoints)
        #expect(!checkpoints.isEmpty)
        let setup = try Self.singlesSetup(for: fixture.input, preset: testCase.preset)
        let input = try setup.matchSetup().scoringInput(log: fixture.input.log)
        let folds = try ScoringEngine.checkpoints(input, afterSeqs: checkpoints.map(\.afterSeq))
        for (index, fold) in folds.enumerated() {
            #expect(fold == checkpoints[index].expected.fold, "\(testCase.fixtureID) checkpoint \(index)")
        }
    }

    @Test func everyContractPresetIdWithAFixtureIsCovered() {
        // slam_bo3 has a fixture (S17) but no preset in story 42; custom is what an override produces.
        let covered = Set(Self.fixtures.map { $0.0.format.presetId })
        let expected = Set(SessionMatchFormatPresetId.allCases).subtracting([.custom, .slamBo3])
        #expect(covered == expected)
        #expect(Set(Self.fixtures.map(\.0)).union([.practiceSet]) == Set(FormatPreset.allCases))
    }

    @Test func onlyConfirmedPresetsAreOffered() {
        #expect(FormatPreset.fast4.availability == .rulesUnconfirmed)
        #expect(FormatPreset.fast4.format.ruleStatus == .unverified)
        #expect(FormatPreset.practiceSet.availability == .scoringNotBuilt)
        #expect(!FormatPreset.offered.contains(.fast4))
        #expect(!FormatPreset.offered.contains(.practiceSet))
        #expect(FormatPreset.offered.first == .clubBestOf3, "the club format is the default and listed first")
        #expect(FormatPreset.offered.count == FormatPreset.allCases.count - 2)
    }

    @Test func overridesProduceACustomFormatAndKeepThePresetOtherwise() {
        var choice = FormatChoice(preset: .clubBestOf3)
        #expect(choice.format == FormatPreset.clubBestOf3.format)
        choice.gameScoring = .ad
        choice.setEnding = .tiebreak
        choice.lets = .let
        #expect(choice.format.presetId == .clubBo3, "an override equal to the preset is not a change")
        choice.gameScoring = .noAd
        #expect(choice.format.presetId == .custom)
        #expect(choice.format.gameScoring == .noAd)
        choice.setEnding = .advantageSet
        #expect(choice.format.set == .advantageSet(.init(games: 6)))
        #expect(choice.format.finalSet == nil)
        // A match tie-break in lieu of the last set survives an advantage-set override of the other sets.
        var deciding = FormatChoice(preset: .matchTiebreakThird)
        deciding.setEnding = .advantageSet
        #expect(deciding.format.set == .advantageSet(.init(games: 6)))
        #expect(deciding.format.finalSet == .matchTiebreak(.init(tiebreak: .init(points: 10))))
        // A standalone tie-break has no games, so neither override applies.
        var tiebreak = FormatChoice(preset: .tiebreak10)
        tiebreak.setEnding = .advantageSet
        tiebreak.gameScoring = .noAd
        #expect(!tiebreak.allowsSetEndingOverride)
        #expect(!tiebreak.allowsGameScoringOverride)
        #expect(tiebreak.format == FormatPreset.tiebreak10.format)
    }

    @Test func summariesDescribeTheRulesNotThePresetName() {
        #expect(FormatSummary(FormatPreset.clubBestOf3.format)
            == .init(length: .bestOf(3), gameScoring: .ad, setEnding: .tiebreak(at: 6), decider: nil, lets: .let))
        #expect(FormatSummary(FormatPreset.matchTiebreakThird.format).decider == .matchTiebreak(points: 10, set: 3))
        #expect(FormatSummary(FormatPreset.bestOf5.format).decider == .longTiebreak(at: 6, points: 10, set: 5))
        #expect(FormatSummary(FormatPreset.bestOf5.format).length == .bestOf(5))
        #expect(FormatSummary(FormatPreset.proSet8.format).length == .proSet(games: 8))
        #expect(FormatSummary(FormatPreset.proSet8.format).setEnding == .tiebreak(at: 8))
        #expect(FormatSummary(FormatPreset.shortSets.format).length == .shortSets(games: 4, bestOf: 3))
        #expect(FormatSummary(FormatPreset.tiebreak7.format).length == .tiebreakOnly(points: 7))
        #expect(FormatSummary(FormatPreset.oneSet.format).length == .oneSet)
        var advantage = FormatChoice(preset: .clubBestOf3)
        advantage.setEnding = .advantageSet
        #expect(advantage.summary.setEnding == .advantageSet)
        #expect(FormatChoice(preset: .practiceSet).summary.length == .practiceSet)
    }

    @Test func aSetupRoundTripsThroughJSON() throws {
        var setup = SessionSetup()
        setup.mode = .doublesMatch
        setup.format = FormatChoice(preset: .noAdMatchTiebreak, lets: .noLet)
        setup.noAdDecidingSide = .deuce
        setup.doublesOrders.append(DoublesOrder(firstServer: .opponent, secondServer: .partner, deuceReceiverA: .partner, deuceReceiverB: .opponent))
        let decoded = try JSONDecoder().decode(SessionSetup.self, from: JSONEncoder().encode(setup))
        #expect(decoded == setup)
        // A draft saved by an older build (fewer keys) still opens: missing keys take their defaults.
        let old = try JSONDecoder().decode(SessionSetup.self, from: Data(#"{"mode":"servePractice"}"#.utf8))
        #expect(old.mode == .servePractice)
        #expect(old.format == FormatChoice(preset: .clubBestOf3))
    }

    struct PresetCase: Sendable, CustomTestStringConvertible {
        var preset: FormatPreset
        var fixtureID: String
        var testDescription: String { "\(preset.rawValue) ↔ \(fixtureID)" }
    }
}
