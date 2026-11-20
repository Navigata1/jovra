import Foundation
import Testing
@testable import JovraCore

/// T21 (story 39): the players editor offers previous opponents, read from sessions saved on this device.
struct RecentPlayersTests {
    static func sample() throws -> SessionDocument {
        let url = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")
        return try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: url))
    }

    static func session(id: String, createdAt: String, opponents: [SessionPlayer], sample: Bool = false) throws -> SessionSummary {
        var document = try Self.sample()
        document.id = id
        document.createdAt = createdAt
        document.players = document.players.filter(\.isSelf) + opponents
        if !sample { document.sample = nil }
        return SessionSummary(document)
    }

    @Test func opponentsComeNewestFirstOncePerNameWithTheirLatestHandedness() throws {
        let older = try Self.session(id: "older", createdAt: "2026-10-01T10:00:00Z", opponents: [
            SessionPlayer(id: "alex-1", displayName: "Alex", handedness: .right, backhand: .twoHanded, isSelf: false),
            SessionPlayer(id: "sam", displayName: "Sam", handedness: .unknown, backhand: .unknown, isSelf: false),
        ])
        let newer = try Self.session(id: "newer", createdAt: "2026-11-01T10:00:00Z", opponents: [
            SessionPlayer(id: "alex-2", displayName: " alex ", handedness: .left, backhand: .oneHanded, isSelf: false),
        ])
        let players = RecentPlayers.from([older, newer])
        #expect(players.map(\.name) == ["alex", "Sam"])
        #expect(players.first?.id == RecentPlayers.id(forName: "Alex"), "a person's id comes from their name, not a session-local id")
        #expect(players.first?.handedness == .left)
        #expect(players.first?.backhand == .oneHanded)
    }

    @Test func thePlayerThemselfSamplePeopleAndBlankNamesAreNeverOffered() throws {
        let sample = try Self.session(id: "demo", createdAt: "2026-11-02T10:00:00Z", opponents: [
            SessionPlayer(id: "demo-alex", displayName: "Demo Alex", handedness: .right, backhand: .twoHanded, isSelf: false),
        ], sample: true)
        let blank = try Self.session(id: "blank", createdAt: "2026-11-03T10:00:00Z", opponents: [
            SessionPlayer(id: "nobody", displayName: "   ", handedness: .unknown, backhand: .unknown, isSelf: false),
        ])
        let players = RecentPlayers.from([sample, blank])
        #expect(players.isEmpty)
        #expect(!RecentPlayers.from([blank]).contains { $0.name == "Jon" })
    }

    @Test func theListIsCapped() throws {
        let many = try (0..<12).map { index in
            try Self.session(id: "s\(index)", createdAt: "2026-10-\(10 + index)T10:00:00Z", opponents: [
                SessionPlayer(id: "p\(index)", displayName: "Player \(index)", handedness: .unknown, backhand: .unknown, isSelf: false),
            ])
        }
        let players = RecentPlayers.from(many, limit: 5)
        #expect(players.map(\.name) == ["Player 11", "Player 10", "Player 9", "Player 8", "Player 7"])
    }

    @Test func aSessionNameIsOptionalAndBoundedLikeTheLibraryTitle() {
        var setup = SessionSetup()
        setup.me.name = "Jon"
        setup.opponent.name = "Alex"
        #expect(setup.isReady, "no session name is needed: the app names the session from the players")
        setup.sessionName = String(repeating: "a", count: SessionSetup.maximumSessionNameLength + 1)
        #expect(setup.problems == [.sessionNameTooLong])
        setup.sessionName = "  Club night  "
        #expect(setup.isReady)
        #expect(setup.trimmedSessionName == "Club night")
    }

    // MARK: Identity (ids as capture and import write them)

    /// Capture writes the recording player as `player-a` and the opponent as `player-b` in every session.
    static func captured(id: String, createdAt: String, opponent: String) throws -> SessionSummary {
        var document = try Self.sample()
        document.id = id
        document.createdAt = createdAt
        document.sample = nil
        document.players = [
            SessionPlayer(id: "player-a", displayName: "Jon", handedness: .right, backhand: .twoHanded, isSelf: true),
            SessionPlayer(id: "player-b", displayName: opponent, handedness: .unknown, backhand: .unknown, isSelf: false),
        ]
        return SessionSummary(document)
    }

    /// An import does not know who the player is: both people are written with `isSelf` false.
    static func imported(id: String, createdAt: String, names: [String]) throws -> SessionSummary {
        var document = try Self.sample()
        document.id = id
        document.createdAt = createdAt
        document.sample = nil
        document.players = names.enumerated().map { index, name in
            SessionPlayer(id: index == 0 ? "player-a" : "player-b", displayName: name, handedness: .unknown, backhand: .unknown, isSelf: false)
        }
        return SessionSummary(document)
    }

    @Test func twoPreviousOpponentsRecordedAsPlayerBGetDistinctIdsThatNeverClashWithTheSetupsSeats() throws {
        let sessions = [
            try Self.captured(id: "one", createdAt: "2026-11-01T10:00:00Z", opponent: "Yan"),
            try Self.captured(id: "two", createdAt: "2026-11-02T10:00:00Z", opponent: "Zed"),
        ]
        let players = RecentPlayers.from(sessions)
        #expect(players.map(\.name) == ["Zed", "Yan"])
        #expect(Set(players.map(\.id)).count == 2, "each person has their own id: \(players.map(\.id))")
        let seatIDs = Set(SetupSeat.allCases.map { SessionSetup()[$0].id })
        #expect(seatIDs.isDisjoint(with: players.map(\.id)), "a recent player's id is never a seat's default id")
        #expect(players.allSatisfy { $0.id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$"#, options: .regularExpression) != nil },
                "ids satisfy the contract's id pattern")
        #expect(RecentPlayers.id(forName: " zed ") == RecentPlayers.id(forName: "Zed"), "the id ignores case and outer spaces")
        #expect(RecentPlayers.id(forName: "Zoë") != RecentPlayers.id(forName: "Zoe"))
    }

    @Test func pickingBothPreviousOpponentsGivesADoublesSetupTheEngineAccepts() throws {
        let sessions = [
            try Self.captured(id: "one", createdAt: "2026-11-01T10:00:00Z", opponent: "Yan"),
            try Self.captured(id: "two", createdAt: "2026-11-02T10:00:00Z", opponent: "Zed"),
        ]
        let players = RecentPlayers.from(sessions)
        var setup = SessionSetup()
        setup.mode = .doublesMatch
        setup.me.name = "Jon"
        setup.partner.name = "Sam"
        setup.opponent = players[0]
        setup.opponentPartner = players[1]
        #expect(setup.problems.isEmpty)
        let match = try setup.matchSetup()
        #expect(Set(match.sides.B).count == 2)
        _ = try ScoringEngine.fold(match.scoringInput(log: setup.openingLog()))
    }

    @Test func theSameIdInTwoSeatsIsASetupProblemSoTheEngineIsNeverHandedIt() throws {
        var setup = SessionSetup()
        setup.mode = .doublesMatch
        setup.me.name = "Jon"
        setup.partner.name = "Sam"
        setup.opponent = .init(id: "player-b", name: "Yan")
        setup.opponentPartner = .init(id: "player-b", name: "Zed")
        #expect(setup.problems == [.samePlayerTwice(.opponentPartner)])
        #expect(!setup.isReady)
        #expect(throws: (any Error).self) { try ScoringEngine.fold(try setup.matchSetup().scoringInput()) }
    }

    @Test func anImportedSessionNeverOffersThePlayerTheirOwnName() throws {
        let imported = try Self.imported(id: "import", createdAt: "2026-11-03T10:00:00Z", names: ["Jon", "Alex"])
        var setup = SessionSetup()
        setup.me.name = " jon "
        let offered = RecentPlayers.offered(RecentPlayers.from([imported]), for: setup)
        #expect(offered.map(\.name) == ["Alex"])
        #expect(offered.first?.id != setup.me.id)
    }

    @Test func someoneAlreadyInTheSetupIsNotOfferedAgain() throws {
        let sessions = [
            try Self.captured(id: "one", createdAt: "2026-11-01T10:00:00Z", opponent: "Yan"),
            try Self.captured(id: "two", createdAt: "2026-11-02T10:00:00Z", opponent: "Zed"),
        ]
        var setup = SessionSetup()
        setup.mode = .doublesMatch
        setup.me.name = "Jon"
        let recents = RecentPlayers.from(sessions)
        setup.opponent = recents[0]
        #expect(RecentPlayers.offered(recents, for: setup).map(\.name) == ["Yan"])
        let many = (0..<12).map { SessionSetup.Player(id: RecentPlayers.id(forName: "P\($0)"), name: "P\($0)") }
        #expect(RecentPlayers.offered(many, for: setup).count == RecentPlayers.defaultLimit)
    }
}
