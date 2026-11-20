import Foundation
import Testing
@testable import JovraCore

/// T21: a doubles setup records teams, the serving order and the receivers for each set; an invalid
/// order is refused with a reason, and a valid one becomes `doublesOrder` events the engine folds.
struct DoublesSetupTests {
    /// S26's four players in the setup's seats: ann (me) and amy against ben and bob.
    static func setup(from input: ScoringInput) throws -> SessionSetup {
        func player(_ id: String) throws -> SessionSetup.Player {
            let found = try #require(input.players.first { $0.id == id })
            return .init(id: found.id, name: found.displayName, handedness: found.handedness, backhand: found.backhand)
        }
        var setup = SessionSetup()
        setup.mode = .doublesMatch
        setup.me = try player(input.sides.A[0])
        setup.partner = try player(input.sides.A[1])
        setup.opponent = try player(input.sides.B[0])
        setup.opponentPartner = try player(input.sides.B[1])
        setup.format = FormatChoice(preset: .clubBestOf3)
        setup.firstServer = .me
        setup.myTeamStartsNear = input.toss.startingEnds.A == .near
        return setup
    }

    @Test func aValidOrderIsSavedAsDoublesOrderEventsPerSetAndFoldsToTheReference() throws {
        let fixture = try FormatPresetTests.fixture("S26-doubles-new-order-per-set")
        var setup = try Self.setup(from: fixture.input)
        // Set 1: ann then ben serve; amy and bob receive in the deuce court. Set 2: the partners swap.
        setup.doublesOrders = [
            DoublesOrder(firstServer: .me, secondServer: .opponent, deuceReceiverA: .partner, deuceReceiverB: .opponentPartner),
            DoublesOrder(firstServer: .partner, secondServer: .opponentPartner, deuceReceiverA: .me, deuceReceiverB: .opponent),
        ]
        #expect(setup.problems.isEmpty)
        #expect(try setup.matchSetup() == MatchSetup(fixture.input))

        let events = setup.doublesOrderEvents()
        #expect(events.map(\.setIndex) == [0, 1])
        let recorded = fixture.input.log.compactMap { event -> SessionDoublesOrderEvent? in
            if case .doublesOrder(let order) = event { order } else { nil }
        }
        #expect(events.map(\.firstServer) == recorded.map(\.firstServer))
        #expect(events.map(\.secondServer) == recorded.map(\.secondServer))
        #expect(events.map(\.deuceReceivers) == recorded.map(\.deuceReceivers))

        // The setup's events replace the fixture's own order events in place; everything else is unchanged.
        var replacements = events.makeIterator()
        let log = fixture.input.log.map { event -> SessionLogEvent in
            guard case .doublesOrder(let original) = event, var mine = replacements.next() else { return event }
            mine.id = original.id; mine.seq = original.seq
            return .doublesOrder(mine)
        }
        let checkpoints = try #require(fixture.checkpoints)
        let folds = try ScoringEngine.checkpoints(try setup.matchSetup().scoringInput(log: log), afterSeqs: checkpoints.map(\.afterSeq))
        #expect(folds.last == checkpoints.last?.expected.fold)
    }

    @Test func theOpeningLogCarriesEveryRecordedOrderBeforeTheFirstPoint() throws {
        let fixture = try FormatPresetTests.fixture("S26-doubles-new-order-per-set")
        var setup = try Self.setup(from: fixture.input)
        setup.doublesOrders = [.standard, DoublesOrder(firstServer: .partner, secondServer: .opponentPartner, deuceReceiverA: .me, deuceReceiverB: .opponent)]
        let log = setup.openingLog()
        #expect(log.map(\.seq) == [1, 2])
        #expect(log.map(\.id) == ["setup-doubles-order-1", "setup-doubles-order-2"])
        // The engine accepts a match that opens with these events and derives the first server from them.
        let timeline = try ScoringEngine.fold(try setup.matchSetup().scoringInput(log: log))
        #expect(timeline.next.value?.server == setup.me.id)
        #expect(timeline.match.doubles)
    }

    @Test func aSinglesSetupHasNoOrderEvents() {
        var setup = SessionSetup()
        setup.me.name = "Jon"; setup.opponent.name = "Alex"
        #expect(setup.doublesOrderEvents().isEmpty)
        #expect(setup.openingLog().isEmpty)
        #expect(setup.problems.isEmpty)
    }

    @Test func twoServersFromTheSameTeamAreRefusedWithTheReason() throws {
        let fixture = try FormatPresetTests.fixture("S26-doubles-new-order-per-set")
        var setup = try Self.setup(from: fixture.input)
        setup.doublesOrders = [DoublesOrder(firstServer: .me, secondServer: .partner, deuceReceiverA: .partner, deuceReceiverB: .opponent)]
        #expect(setup.problems == [.doublesOrder(set: 0, .serversOnSameTeam)])
        #expect(!setup.isReady)
        // The engine refuses the same order, so the setup never hands it one.
        let log = setup.doublesOrders[0].event(setIndex: 0, seq: 1, players: setup.playerIDs)
        #expect(throws: ScoringError.self) {
            _ = try ScoringEngine.fold(try setup.matchSetup().scoringInput(log: [.doublesOrder(log)]))
        }
    }

    @Test func theFirstSetMustStartWithTheMatchsFirstServer() throws {
        let fixture = try FormatPresetTests.fixture("S26-doubles-new-order-per-set")
        var setup = try Self.setup(from: fixture.input)
        setup.firstServer = .opponent
        setup.doublesOrders = [.standard] // still says "me" serves first
        #expect(setup.problems == [.doublesOrder(set: 0, .firstServerDiffersFromMatch)])
        // Later sets may start with anyone, as long as the servers alternate teams.
        setup.doublesOrders = [
            DoublesOrder(firstServer: .opponent, secondServer: .me, deuceReceiverA: .me, deuceReceiverB: .opponent),
            DoublesOrder(firstServer: .partner, secondServer: .opponent, deuceReceiverA: .me, deuceReceiverB: .opponent),
        ]
        #expect(setup.problems.isEmpty)
    }

    @Test func aReceiverMustStandOnTheirOwnTeamsSide() throws {
        let fixture = try FormatPresetTests.fixture("S26-doubles-new-order-per-set")
        var setup = try Self.setup(from: fixture.input)
        setup.doublesOrders = [DoublesOrder(firstServer: .me, secondServer: .opponent, deuceReceiverA: .opponent, deuceReceiverB: .opponentPartner)]
        #expect(setup.problems == [.doublesOrder(set: 0, .receiverOnWrongTeam)])
    }

    @Test func missingAndOverlongNamesAreProblemsOnlyForTheSeatsInPlay() {
        var setup = SessionSetup()
        #expect(setup.problems == [.missingName(.me), .missingName(.opponent)])
        setup.me.name = "  Jon "; setup.opponent.name = String(repeating: "a", count: 61)
        #expect(setup.problems == [.nameTooLong(.opponent)])
        setup.opponent.name = "Alex"
        #expect(setup.isReady)
        setup.mode = .doublesMatch
        #expect(setup.problems == [.missingName(.partner), .missingName(.opponentPartner)])
        setup.mode = .servePractice
        setup.opponent.name = ""
        #expect(setup.isReady, "practice needs only the player")
        #expect(setup.seatsInPlay == [.me])
    }

    @Test func sessionKindFollowsTheModeAndTheFormat() {
        var setup = SessionSetup()
        #expect(setup.sessionKind == .match)
        setup.format = FormatChoice(preset: .tiebreak7)
        #expect(setup.sessionKind == .tiebreakOnly)
        setup.mode = .strokePractice
        #expect(setup.sessionKind == .strokePractice)
        #expect(throws: SetupError.notAMatch) { _ = try setup.matchSetup() }
    }

    @Test func removingASetsOrderNeverRemovesTheFirst() {
        var setup = SessionSetup()
        setup.mode = .doublesMatch
        #expect(setup.maximumRecordedSets == 3)
        setup.addDoublesOrder(); setup.addDoublesOrder(); setup.addDoublesOrder()
        #expect(setup.doublesOrders.count == 3, "never more orders than the format has sets")
        setup.removeLastDoublesOrder(); setup.removeLastDoublesOrder(); setup.removeLastDoublesOrder()
        #expect(setup.doublesOrders.count == 1)
    }
}
