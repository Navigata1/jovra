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
        #expect(players.first?.id == "alex-2", "the newest session's id keeps head-to-head history joined")
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
}
