import JovraCore
import SwiftUI

// The words and symbols of the player profile (screens.md S02), shared by onboarding, the Profile hub and the edit
// screen.

extension SessionPlayerHandedness {
    /// The choices onboarding offers; `.unknown` means "not chosen".
    static let choices: [SessionPlayerHandedness] = [.right, .left]

    var title: String {
        switch self {
        case .right: String(localized: "Right-handed", table: "Onboarding", comment: "Playing hand")
        case .left: String(localized: "Left-handed", table: "Onboarding", comment: "Playing hand")
        case .unknown: String(localized: "Not set", table: "Onboarding", comment: "Playing hand not chosen")
        }
    }
}

extension SessionPlayerBackhand {
    static let choices: [SessionPlayerBackhand] = [.oneHanded, .twoHanded]

    var title: String {
        switch self {
        case .oneHanded: String(localized: "One-handed backhand", table: "Onboarding", comment: "Backhand style")
        case .twoHanded: String(localized: "Two-handed backhand", table: "Onboarding", comment: "Backhand style")
        case .unknown: String(localized: "Backhand not set", table: "Onboarding", comment: "Backhand style not chosen")
        }
    }
}

extension SkillLevel {
    var title: String {
        switch self {
        case .beginner: String(localized: "Beginner", table: "Onboarding", comment: "Skill level")
        case .clubPlayer: String(localized: "Club player", table: "Onboarding", comment: "Skill level")
        case .competitive: String(localized: "Competitive", table: "Onboarding", comment: "Skill level")
        }
    }
}

extension PlayerGoal {
    var title: String {
        switch self {
        case .serveConsistency: String(localized: "Serve consistency", table: "Onboarding", comment: "Goal chip")
        case .winMoreMatches: String(localized: "Win more matches", table: "Onboarding", comment: "Goal chip")
        case .improveFitness: String(localized: "Improve fitness", table: "Onboarding", comment: "Goal chip")
        case .matchStrategy: String(localized: "Match strategy", table: "Onboarding", comment: "Goal chip")
        case .playWithBetterPlayers: String(localized: "Play with better players", table: "Onboarding", comment: "Goal chip")
        case .enjoyTheGame: String(localized: "Enjoy the game more", table: "Onboarding", comment: "Goal chip")
        }
    }

    var symbol: String {
        switch self {
        case .serveConsistency: "scope"
        case .winMoreMatches: "trophy"
        case .improveFitness: "dumbbell"
        case .matchStrategy: "chart.bar"
        case .playWithBetterPlayers: "person.3"
        case .enjoyTheGame: "heart"
        }
    }
}

extension UsualFormat {
    var title: String {
        switch self {
        case .singles: String(localized: "Singles", table: "Onboarding", comment: "Usually play")
        case .doubles: String(localized: "Doubles", table: "Onboarding", comment: "Usually play")
        case .both: String(localized: "Both", table: "Onboarding", comment: "Usually play")
        }
    }
}

extension PlayerProfile {
    /// "Right-handed · One-handed backhand · Club player", unset parts left out (N11 subtitle); nil when nothing is set.
    var summary: String? {
        var parts: [String] = []
        if handedness != .unknown { parts.append(handedness.title) }
        if backhand != .unknown { parts.append(backhand.title) }
        if let level { parts.append(level.title) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
