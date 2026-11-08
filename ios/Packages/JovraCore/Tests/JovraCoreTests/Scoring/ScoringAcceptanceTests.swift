import Foundation
import Testing
@testable import JovraCore

/// T04 acceptance checks that sit beside the fixture runner: they read the golden fixtures, which the Python
/// reference engine wrote, and never compare the native fold with values the native fold produced.
private struct LoadedScoringFixture {
    let name: String
    let fixture: ScoringFixture
}

private func scoringFixtures() throws -> [LoadedScoringFixture] {
    let folder = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/scoring")
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { .init(name: $0.lastPathComponent, fixture: try JSONDecoder().decode(ScoringFixture.self, from: Data(contentsOf: $0))) }
}

private func sampleInput() throws -> ScoringInput {
    let path = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")
    return try ScoringInput(session: ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: path)))
}

/// Appends the user's winner flip of the point at `position` (1-based), the way the review screen records it.
private func flippingWinner(of input: ScoringInput, atPoint position: Int) throws -> ScoringInput {
    let points = input.log.compactMap { event -> SessionPointEvent? in if case .point(let v) = event { return v }; return nil }
    var flip = points[position - 1]
    guard var outcome = flip.reviewed else { throw ScoringError(.outcomeMissing, flip.id) }
    outcome.winner = outcome.winner == .a ? .b : .a
    outcome.provenance = .reviewed
    flip.supersedes = flip.id
    flip.id = "flip-p\(position)"
    flip.seq = (input.log.last?.seq ?? 0) + 1
    flip.reviewed = outcome
    flip.reviewState = .reviewed
    var edited = input
    edited.log.append(.point(flip))
    return edited
}

@Test func errorFixturesThrowTheirTypedCode() throws {
    let refusals = try scoringFixtures().filter { $0.fixture.expectError != nil }
    #expect(refusals.count == 18)
    for item in refusals {
        do { _ = try ScoringEngine.fold(item.fixture.input); Issue.record("\(item.name) folded") }
        catch let error as ScoringError { #expect(error.code.rawValue == item.fixture.expectError?.code, "\(item.name)") }
    }
    print("Scoring refusals: \(refusals.count) fixtures threw their typed code")
}

@Test func foldingTwiceIsByteIdenticalForEveryFixture() throws {
    var folds = 0
    for item in try scoringFixtures() where item.fixture.expectError == nil {
        let first = try CanonicalJSON.encode(ScoringEngine.fold(item.fixture.input))
        let second = try CanonicalJSON.encode(ScoringEngine.fold(item.fixture.input))
        #expect(first == second, "\(item.name)")
        folds += 1
    }
    let sample = try sampleInput()
    #expect(try CanonicalJSON.encode(ScoringEngine.fold(sample)) == CanonicalJSON.encode(ScoringEngine.fold(sample)))
    #expect(folds == 93)
    print("Scoring determinism: \(folds) fixture folds and the sample fold byte-identical on refold")
}

@Test func everyContractConflictKindComesFromAPassingFixture() throws {
    var produced = Set<String>()
    for item in try scoringFixtures() {
        for checkpoint in item.fixture.checkpoints ?? [] {
            let fold = checkpoint.expected.fold
            produced.formUnion(fold.conflicts.map(\.type.rawValue))
            if case .value(let changes)? = fold.changes {
                if !changes.tiebreakAppeared.isEmpty { produced.insert("tiebreakAppeared") }
                if !changes.tiebreakVanished.isEmpty { produced.insert("tiebreakVanished") }
                if changes.matchIncomplete { produced.insert("matchIncomplete") }
            }
        }
    }
    // ios-v1-spec "Conflicts", every kind it names; sideMismatch comes from S71 (Rule 27a, decision 25).
    let specKinds: Set = ["serverMismatch", "tiebreakAppeared", "tiebreakVanished", "pointsAfterMatchEnd",
                          "matchIncomplete", "checkpointConflict", "doublesOrderConflict", "sideMismatch"]
    #expect(specKinds.isSubset(of: produced), "missing \(specKinds.subtracting(produced).sorted())")
    #expect(Set(TimelineConflictType.allCases.map(\.rawValue)).isSubset(of: produced))
}

@Test func everyNamedFormatPresetHasAPassingFixture() throws {
    let covered = Set(try scoringFixtures().filter { $0.fixture.checkpoints?.isEmpty == false }.map(\.fixture.input.format.presetId))
    let named = Set(SessionMatchFormatPresetId.allCases).subtracting([.custom])
    #expect(named.isSubset(of: covered), "uncovered \(named.subtracting(covered).map(\.rawValue).sorted())")
}

@Test func rulesAndAsPlayedModesBothMatchTheServerOverrideFixtures() throws {
    let overrides = try scoringFixtures().filter { $0.name.hasPrefix("O") && $0.fixture.expectError == nil }
    #expect(overrides.count == 22)
    #expect(overrides.filter { $0.name.hasSuffix("-rules.json") }.count == 11)
    for item in overrides {
        let expected = try #require(item.fixture.checkpoints?.last).expected.fold
        var actual = try ScoringEngine.fold(item.fixture.input, mode: item.fixture.input.resolutionMode ?? .rules)
        actual.changes = expected.changes
        #expect(actual == expected, "\(item.name)")
    }
}

@Test func reanalysisLeavesTheReviewedPointUntouched() throws {
    let item = try #require(try scoringFixtures().first { $0.name == "S67-reanalysis-keeps-reviewed.json" })
    var input = item.fixture.input
    let reviewedOnly = Array(input.log.prefix(3))
    input.log = reviewedOnly
    let baseline = try ScoringEngine.fold(input)
    let rerun = try ScoringEngine.fold(item.fixture.input)
    #expect(rerun.points[0] == baseline.points[0])
    #expect(rerun.points[0].provenance == .reviewed)
    #expect(rerun.points[1].id == "e006")
}

@Test func pointFortyTwoWinnerFlipDiffListsScoringChangesOnly() throws {
    let input = try sampleInput()
    let before = try ScoringEngine.fold(input)
    let after = try ScoringEngine.fold(flippingWinner(of: input, atPoint: 42))
    let changes = ScoringEngine.diff(before: before, after: after)

    // Independent expectation: the Python reference fold of the same two logs (spec/reference/jovra_ref) changes
    // every point from the 42nd on (83 of 124), games 8-10 of set 1 and all ten games of set 2, both sets
    // (6-4 6-3 becomes 6-3 6-4) and the result's scoreline.
    let points = changes.compactMap { if case .point(let id) = $0 { return id }; return nil }
    #expect(points.count == 83)
    #expect(points.first == "flip-p42")
    #expect(points == Array(after.points[41...].map(\.id)))
    let games: [[Int]] = changes.compactMap { if case .game(let set, let game) = $0 { return [set, game] }; return nil }
    let expectedGames: [[Int]] = [[0, 7], [0, 8], [0, 9]] + (0...9).map { [1, $0] }
    #expect(games == expectedGames)
    #expect(changes.compactMap { if case .set(let index) = $0 { return index }; return nil } == [0, 1])
    #expect(changes.filter { $0 == ChangedValue.result }.count == 1)
    #expect(before.match.scoreline == .value("6-4 6-3") && after.match.scoreline == .value("6-3 6-4"))
    #expect(changes.count == 83 + 13 + 2 + 1, "a scoring diff has no stats entries")

    #expect(ScoringEngine.diff(before: before, after: before).isEmpty)
    var undone = try flippingWinner(of: input, atPoint: 42)
    undone.log.append(.void(.init(id: "undo-flip", seq: undone.log.last!.seq + 1, target: "flip-p42")))
    #expect(ScoringEngine.diff(before: before, after: try ScoringEngine.fold(undone)).isEmpty)
}
