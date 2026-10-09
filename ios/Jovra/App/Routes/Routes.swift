import Foundation

// The navigation model of screen spec §0.1. Every case here resolves to a view in its owning
// feature folder (see `RouteCatalog`); a feature ticket replaces that one file and never edits the
// router. Every payload is Codable so the whole navigation state survives state restoration.

/// Before the shell: shown until a profile exists or the demo is chosen (T18 decides when).
enum PreShellRoute: Hashable, Codable, Sendable {
    case welcome
    /// Onboarding step, 1-based (screen 02 has three steps).
    case onboarding(step: Int)
}

/// Pushes on the Sessions tab's stack.
enum SessionsRoute: Hashable, Codable, Sendable {
    case importVideos
    case matchOverview(SessionID)
    case practiceOverview(SessionID)
}

/// Pushes on the Insights tab's stack. A nil session means "across sessions".
enum InsightsRoute: Hashable, Codable, Sendable {
    case shotMap(SessionID?)
    case serveLab(SessionID?)
    case strokeLab(SessionID?)
    case progress
    case drillDetail(DrillID)
}

/// Pushes on the Profile tab's stack.
enum ProfileRoute: Hashable, Codable, Sendable {
    case racketVault
    case stringJournal
    case storage
    case settings
    case spaceSaver
    case diagnostics
    case recordingRules
}

/// A push, with the tab whose stack it belongs to.
enum PushRoute: Hashable, Codable, Sendable {
    case sessions(SessionsRoute)
    case insights(InsightsRoute)
    case profile(ProfileRoute)

    var tab: AppTab {
        switch self {
        case .sessions: .sessions
        case .insights: .insights
        case .profile: .profile
        }
    }
}

/// What the replay route opens on.
struct ReplayRequest: Hashable, Codable, Sendable {
    var session: SessionID
    var point: PointID?
    var filter: PointFilter?
}

/// Focused flows that take over the whole screen and remove the tab bar.
enum FullScreenRoute: Hashable, Codable, Sendable, Identifiable {
    /// Framing (S05) → recording (S06). Nil uses the setup screen's current choices.
    case capture(SessionSetupDraft?)
    case replay(ReplayRequest)
    /// Nil starts a new comparison.
    case compare(ComparisonID?)
    case pointReview(SessionID, PointFilter)
    case highlightReel(SessionID)
    case drillSession(DrillID)
    case processing(SessionID)

    /// Changes whenever the payload changes, so presenting another payload replaces the cover.
    var id: String { RouteCoding.key(self) }
}

/// Where the format sheet edits the match format.
enum FormatSheetContext: Hashable, Codable, Sendable {
    /// The session setup draft (S04).
    case sessionSetup
    /// A saved session (S09), where a change recomputes every score and stat.
    case session(SessionID)
}

/// Every sheet the app presents (detents, never a fake system dialog).
enum SheetRoute: Hashable, Codable, Sendable, Identifiable {
    /// Nil adds a new point.
    case pointEditor(SessionID, PointID?)
    /// Nil exports a range chosen in the sheet.
    case clipExport(SessionID, PointID?)
    case sharePack(SessionID)
    case capabilityDetail(CapabilityID)
    case matchFormat(FormatSheetContext)
    case players
    case cameraPreset
    case trash
    /// Nil adds a new goal.
    case goal(GoalID?)
    case consentAttach(SessionID)
    case calibration(SessionID, MediaTime)
    case stringBroke(SessionID, MediaTime)
    /// Nil lists every session in the archive; otherwise offers that one.
    case restore(SessionID?)
    case comparisonPicker
    case driveAccount
    case account
    case deleteAllData
    /// The in-app explanation shown before a system permission prompt (PermissionsCenter, T07).
    case permission(LaunchConfiguration.Permission)

    var id: String { RouteCoding.key(self) }
}

/// Any place the app can be sent: by a button, a deep link, the launch harness or restoration.
enum AppDestination: Hashable, Codable, Sendable {
    case preShell(PreShellRoute)
    case tab(AppTab)
    case push(PushRoute)
    case fullScreen(FullScreenRoute)
    case sheet(SheetRoute)
}

extension AppTab: Codable {}
extension LaunchConfiguration.Permission: Codable {}

/// Stable string keys for route identity.
enum RouteCoding {
    static func key<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: value)
    }
}
