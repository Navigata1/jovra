import Foundation

/// The four places a player can stand in a session setup. "A" is always the recording player's side.
public enum SetupSeat: String, Codable, CaseIterable, Hashable, Sendable {
    case me, partner, opponent, opponentPartner

    public var side: Side { self == .me || self == .partner ? .a : .b }

    public var teammate: SetupSeat {
        switch self {
        case .me: .partner
        case .partner: .me
        case .opponent: .opponentPartner
        case .opponentPartner: .opponent
        }
    }
}

/// What a scoring fold starts from: the format, who plays on which side, and the toss. It is the part
/// of a `ScoringInput` that is known before the first point.
public struct MatchSetup: Codable, Equatable, Sendable {
    public var format: SessionMatchFormat
    public var players: [SessionPlayer]
    public var sides: SessionSides
    public var toss: SessionToss

    public init(format: SessionMatchFormat, players: [SessionPlayer], sides: SessionSides, toss: SessionToss) {
        self.format = format; self.players = players; self.sides = sides; self.toss = toss
    }

    public init(_ input: ScoringInput) {
        self.init(format: input.format, players: input.players, sides: input.sides, toss: input.toss)
    }

    public func scoringInput(log: [SessionLogEvent] = []) -> ScoringInput {
        ScoringInput(format: format, players: players, sides: sides, toss: toss, log: log)
    }
}

public enum SetupError: Error, Equatable, Sendable {
    /// A practice session has no score, so it has no match setup.
    case notAMatch
}

/// What stops a setup from being recorded, in the order the screen lists them.
public enum SetupProblem: Equatable, Sendable {
    case missingName(SetupSeat)
    case nameTooLong(SetupSeat)
    case doublesOrder(set: Int, DoublesOrderProblem)
    case sessionNameTooLong
}

/// Everything session setup (screen S04) decides before the camera opens. It is small, `Codable` and
/// `Hashable`: the capture route carries it, and the last one is remembered as the next default.
public struct SessionSetup: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Hashable, Sendable {
        case singlesMatch, doublesMatch, servePractice, strokePractice

        public var isMatch: Bool { self == .singlesMatch || self == .doublesMatch }
    }

    public struct Player: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var handedness: SessionPlayerHandedness
        public var backhand: SessionPlayerBackhand

        public init(id: String, name: String = "", handedness: SessionPlayerHandedness = .unknown,
                    backhand: SessionPlayerBackhand = .unknown) {
            self.id = id; self.name = name; self.handedness = handedness; self.backhand = backhand
        }

        public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Which court the receiver takes for the deciding point of a No-Ad game (user story 45). The point
    /// itself records what happened; this is the side the live scorer offers first.
    public enum DecidingSide: String, Codable, CaseIterable, Hashable, Sendable {
        case receiverChooses, deuce, ad
    }

    public static let maximumNameLength = 60
    /// The library title's limit; a blank name lets the app name the session after its players.
    public static let maximumSessionNameLength = 120
    public static let plannedMinutesRange = 15...180
    public static let plannedMinutesStep = 15

    public var mode: Mode
    /// Optional; blank means the app names the session from the players ("Jon vs Alex").
    public var sessionName: String
    public var me: Player
    public var partner: Player
    public var opponent: Player
    public var opponentPartner: Player
    public var format: FormatChoice
    public var firstServer: SetupSeat
    /// The recording player's side starts at the end nearest the camera.
    public var myTeamStartsNear: Bool
    public var noAdDecidingSide: DecidingSide
    /// Serving order and receivers, one per set from the first; later sets can be added on court.
    public var doublesOrders: [DoublesOrder]
    /// A `CaptureFormatOption` id; nil means the first supported preset.
    public var cameraFormatID: String?
    public var plannedMinutes: Int
    public var purpose: SessionDocumentCapturePurpose
    public var microphoneOn: Bool

    public init() {
        mode = .singlesMatch
        sessionName = ""
        me = Player(id: "player-a")
        opponent = Player(id: "player-b")
        partner = Player(id: "player-c")
        opponentPartner = Player(id: "player-d")
        format = FormatChoice()
        firstServer = .me
        myTeamStartsNear = true
        noAdDecidingSide = .receiverChooses
        doublesOrders = [.standard]
        cameraFormatID = nil
        plannedMinutes = 60
        purpose = .match
        microphoneOn = true
    }

    // MARK: Players

    public subscript(seat: SetupSeat) -> Player {
        get {
            switch seat {
            case .me: me
            case .partner: partner
            case .opponent: opponent
            case .opponentPartner: opponentPartner
            }
        }
        set {
            switch seat {
            case .me: me = newValue
            case .partner: partner = newValue
            case .opponent: opponent = newValue
            case .opponentPartner: opponentPartner = newValue
            }
        }
    }

    /// The seats this mode uses: side A first, as the session document lists its players.
    public var seatsInPlay: [SetupSeat] {
        switch mode {
        case .singlesMatch: [.me, .opponent]
        case .doublesMatch: [.me, .partner, .opponent, .opponentPartner]
        case .servePractice, .strokePractice: [.me]
        }
    }

    public var playerIDs: [SetupSeat: String] {
        Dictionary(uniqueKeysWithValues: SetupSeat.allCases.map { ($0, self[$0].id) })
    }

    public var sessionPlayers: [SessionPlayer] {
        seatsInPlay.map { seat in
            let player = self[seat]
            return SessionPlayer(id: player.id, displayName: player.trimmedName, handedness: player.handedness,
                                 backhand: player.backhand, isSelf: seat == .me)
        }
    }

    /// The seat that serves first, kept inside the seats this mode uses.
    public var effectiveFirstServer: SetupSeat {
        seatsInPlay.contains(firstServer) ? firstServer : (firstServer.side == .a ? .me : .opponent)
    }

    // MARK: What gets recorded

    public var sessionKind: SessionDocumentSessionKind {
        switch mode {
        case .singlesMatch, .doublesMatch: format.preset.sessionKind
        case .servePractice: .servePractice
        case .strokePractice: .strokePractice
        }
    }

    /// The capture purpose the session is stored with: a match is always filmed as a match.
    public var effectivePurpose: SessionDocumentCapturePurpose { mode.isMatch ? .match : purpose }

    public func matchSetup() throws(SetupError) -> MatchSetup {
        guard mode.isMatch else { throw .notAMatch }
        let sides = SessionSides(A: seatsInPlay.filter { $0.side == .a }.map { self[$0].id },
                                 B: seatsInPlay.filter { $0.side == .b }.map { self[$0].id })
        let toss = SessionToss(firstServer: self[effectiveFirstServer].id,
                               startingEnds: .init(A: myTeamStartsNear ? .near : .far, B: myTeamStartsNear ? .far : .near))
        return MatchSetup(format: format.format, players: sessionPlayers, sides: sides, toss: toss)
    }

    /// One `doublesOrder` event per recorded set; empty for anything but a doubles match.
    public func doublesOrderEvents() -> [SessionDoublesOrderEvent] {
        guard mode == .doublesMatch else { return [] }
        let ids = playerIDs
        return doublesOrders.prefix(maximumRecordedSets).enumerated().map { index, order in
            order.event(setIndex: index, seq: index + 1, players: ids)
        }
    }

    /// The events a match's log opens with, before the first point.
    public func openingLog() -> [SessionLogEvent] { doublesOrderEvents().map(SessionLogEvent.doublesOrder) }

    // MARK: Validation

    public var problems: [SetupProblem] {
        var found: [SetupProblem] = []
        for seat in seatsInPlay {
            let name = self[seat].trimmedName
            if name.isEmpty { found.append(.missingName(seat)) }
            else if name.unicodeScalars.count > Self.maximumNameLength { found.append(.nameTooLong(seat)) }
        }
        if trimmedSessionName.unicodeScalars.count > Self.maximumSessionNameLength { found.append(.sessionNameTooLong) }
        if mode == .doublesMatch {
            for (index, order) in doublesOrders.prefix(maximumRecordedSets).enumerated() {
                found += order.problems(setIndex: index, matchFirstServer: effectiveFirstServer).map { .doublesOrder(set: index, $0) }
            }
        }
        return found
    }

    public var isReady: Bool { problems.isEmpty }

    public var trimmedSessionName: String { sessionName.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Doubles orders

    /// The most sets the chosen format can run to.
    public var maximumRecordedSets: Int { format.format.setsToWin.rawValue * 2 - 1 }

    /// Adds the next set's order, starting from the previous set's.
    public mutating func addDoublesOrder() {
        guard doublesOrders.count < maximumRecordedSets, let last = doublesOrders.last else { return }
        doublesOrders.append(last)
    }

    public mutating func removeLastDoublesOrder() {
        guard doublesOrders.count > 1 else { return }
        doublesOrders.removeLast()
    }

    /// Keeps the first set's order in step when the match's first server changes.
    public mutating func alignFirstOrderWithFirstServer() {
        guard !doublesOrders.isEmpty else { doublesOrders = [.standard]; return }
        let server = effectiveFirstServer
        guard doublesOrders[0].firstServer != server else { return }
        doublesOrders[0].firstServer = server
        if doublesOrders[0].secondServer.side == server.side {
            doublesOrders[0].secondServer = server.side == .a ? .opponent : .me
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case mode, sessionName, me, partner, opponent, opponentPartner, format, firstServer, myTeamStartsNear, noAdDecidingSide
        case doublesOrders, cameraFormatID, plannedMinutes, purpose, microphoneOn
    }

    /// A draft saved by an older build may lack keys; each missing key takes its default.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? mode
        sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName) ?? sessionName
        me = try container.decodeIfPresent(Player.self, forKey: .me) ?? me
        partner = try container.decodeIfPresent(Player.self, forKey: .partner) ?? partner
        opponent = try container.decodeIfPresent(Player.self, forKey: .opponent) ?? opponent
        opponentPartner = try container.decodeIfPresent(Player.self, forKey: .opponentPartner) ?? opponentPartner
        format = try container.decodeIfPresent(FormatChoice.self, forKey: .format) ?? format
        firstServer = try container.decodeIfPresent(SetupSeat.self, forKey: .firstServer) ?? firstServer
        myTeamStartsNear = try container.decodeIfPresent(Bool.self, forKey: .myTeamStartsNear) ?? myTeamStartsNear
        noAdDecidingSide = try container.decodeIfPresent(DecidingSide.self, forKey: .noAdDecidingSide) ?? noAdDecidingSide
        let orders = try container.decodeIfPresent([DoublesOrder].self, forKey: .doublesOrders) ?? doublesOrders
        doublesOrders = orders.isEmpty ? [.standard] : orders
        cameraFormatID = try container.decodeIfPresent(String.self, forKey: .cameraFormatID)
        let minutes = try container.decodeIfPresent(Int.self, forKey: .plannedMinutes) ?? plannedMinutes
        plannedMinutes = min(max(minutes, Self.plannedMinutesRange.lowerBound), Self.plannedMinutesRange.upperBound)
        purpose = try container.decodeIfPresent(SessionDocumentCapturePurpose.self, forKey: .purpose) ?? purpose
        microphoneOn = try container.decodeIfPresent(Bool.self, forKey: .microphoneOn) ?? microphoneOn
    }
}

/// Who serves first and second in a set, and who receives in the deuce court on each side (Rules §2.4).
public struct DoublesOrder: Codable, Hashable, Sendable {
    public var firstServer: SetupSeat
    public var secondServer: SetupSeat
    /// The recording player's side.
    public var deuceReceiverA: SetupSeat
    public var deuceReceiverB: SetupSeat

    public init(firstServer: SetupSeat, secondServer: SetupSeat, deuceReceiverA: SetupSeat, deuceReceiverB: SetupSeat) {
        self.firstServer = firstServer; self.secondServer = secondServer
        self.deuceReceiverA = deuceReceiverA; self.deuceReceiverB = deuceReceiverB
    }

    /// The recording player serves first and receives in the deuce court, as does the first opponent.
    public static let standard = DoublesOrder(firstServer: .me, secondServer: .opponent, deuceReceiverA: .me, deuceReceiverB: .opponent)

    /// The same checks the scoring engine makes, so the setup never hands it an order it refuses.
    public func problems(setIndex: Int, matchFirstServer: SetupSeat) -> [DoublesOrderProblem] {
        var found: [DoublesOrderProblem] = []
        if firstServer.side == secondServer.side { found.append(.serversOnSameTeam) }
        if deuceReceiverA.side != .a || deuceReceiverB.side != .b { found.append(.receiverOnWrongTeam) }
        if setIndex == 0, firstServer != matchFirstServer { found.append(.firstServerDiffersFromMatch) }
        return found
    }

    public func event(setIndex: Int, seq: Int, players: [SetupSeat: String]) -> SessionDoublesOrderEvent {
        func id(_ seat: SetupSeat) -> String { players[seat] ?? seat.rawValue }
        return SessionDoublesOrderEvent(id: "setup-doubles-order-\(setIndex + 1)", seq: seq, setIndex: setIndex,
            firstServer: id(firstServer), secondServer: id(secondServer),
            deuceReceivers: .init(A: id(deuceReceiverA), B: id(deuceReceiverB)), source: "setup")
    }
}

public enum DoublesOrderProblem: String, CaseIterable, Equatable, Sendable {
    /// Service alternates between the teams, so the first two servers are never partners.
    case serversOnSameTeam
    /// A deuce-court receiver was picked from the other team.
    case receiverOnWrongTeam
    /// The first set starts with the player who serves first in the match.
    case firstServerDiffersFromMatch
}
