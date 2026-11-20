import Foundation

/// You, the player whose stats, trends and practice the library tracks (GLOSSARY: Player), as onboarding (screen S02)
/// and the Profile hub (N11) record it. Everything is optional: nothing is preselected, because a default would
/// silently mislabel a left-hander (screens.md S02, deliberate differences). Stored on this iPhone only.
public struct PlayerProfile: Codable, Equatable, Sendable {
    /// The file format version. A newer one is refused rather than half read.
    public static let currentVersion = 1
    /// Goals are a short, ordered list (S02: "Your goals (select up to 3)").
    public static let maximumGoals = 3

    public var version: Int
    /// The first name; empty when not given (Home then greets without a name).
    public var name: String
    /// `.unknown` until chosen; Profile shows "Not set" and Stroke Lab asks before mirroring.
    public var handedness: SessionPlayerHandedness
    public var backhand: SessionPlayerBackhand
    public var level: SkillLevel?
    /// At most three, in the order chosen. They only reorder practice suggestions; they never change a stat.
    public var goals: [PlayerGoal]
    /// The mode Session setup starts on (S02 step 3, "Usually play").
    public var usualFormat: UsualFormat?
    /// How the player signed in on this iPhone. Apple sign-in is local only: no server, no token (open question 1).
    public var account: ProfileAccount
    /// The demo's profile (S01 "Explore a demo"): fictional, always labelled Sample, replaced by onboarding.
    public var isSample: Bool

    public init(name: String = "", handedness: SessionPlayerHandedness = .unknown, backhand: SessionPlayerBackhand = .unknown,
                level: SkillLevel? = nil, goals: [PlayerGoal] = [], usualFormat: UsualFormat? = nil,
                account: ProfileAccount = .none, isSample: Bool = false) {
        version = Self.currentVersion
        self.name = name
        self.handedness = handedness
        self.backhand = backhand
        self.level = level
        self.goals = goals
        self.usualFormat = usualFormat
        self.account = account
        self.isSample = isSample
    }

    /// The demo library's player (screens.md §0.6): Jon, right-handed, one-handed backhand, a club player working on
    /// serve consistency and match strategy, as reference 02 draws him.
    public static let sample = PlayerProfile(name: "Jon", handedness: .right, backhand: .oneHanded, level: .clubPlayer,
                                             goals: [.serveConsistency, .matchStrategy], usualFormat: .singles,
                                             isSample: true)

    /// The name with surrounding spaces removed.
    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The avatar letter: the name's first character, upper-cased; nil when there is no name.
    public var initial: String? { trimmedName.first.map { String($0).uppercased() } }

    public enum GoalToggle: Equatable, Sendable {
        case selected, deselected
        /// A fourth goal: the tap is refused and the screen says why.
        case refusedLimitReached
    }

    /// Selects or deselects `goal`, keeping the order goals were chosen in.
    @discardableResult
    public mutating func toggleGoal(_ goal: PlayerGoal) -> GoalToggle {
        if let index = goals.firstIndex(of: goal) {
            goals.remove(at: index)
            return .deselected
        }
        guard goals.count < Self.maximumGoals else { return .refusedLimitReached }
        goals.append(goal)
        return .selected
    }

    private enum CodingKeys: String, CodingKey {
        case version, name, handedness, backhand, level, goals, usualFormat, account, isSample
    }

    /// Fields a newer build of the same version adds later are optional here, so an older file still reads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else { throw ProfileStoreError.unsupportedVersion(version) }
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        handedness = try container.decodeIfPresent(SessionPlayerHandedness.self, forKey: .handedness) ?? .unknown
        backhand = try container.decodeIfPresent(SessionPlayerBackhand.self, forKey: .backhand) ?? .unknown
        level = try container.decodeIfPresent(SkillLevel.self, forKey: .level)
        goals = try container.decodeIfPresent([PlayerGoal].self, forKey: .goals) ?? []
        usualFormat = try container.decodeIfPresent(UsualFormat.self, forKey: .usualFormat)
        account = try container.decodeIfPresent(ProfileAccount.self, forKey: .account) ?? .none
        isSample = try container.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
    }
}

/// S02 "Skill level". Pitches suggestions; it is never a rating.
public enum SkillLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case beginner, clubPlayer, competitive
}

/// What the player wants from the game (S02 goal chips). Distinct from a progress Goal on a stat (GLOSSARY: Goal):
/// these only reorder practice suggestions.
public enum PlayerGoal: String, Codable, CaseIterable, Hashable, Sendable {
    case serveConsistency, winMoreMatches, improveFitness, matchStrategy, playWithBetterPlayers, enjoyTheGame
}

/// S02 step 3 "Usually play".
public enum UsualFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case singles, doubles, both
}

/// S20 account row: "Apple sign-in" or "No account".
public enum ProfileAccount: String, Codable, Hashable, Sendable {
    case none, apple
}
