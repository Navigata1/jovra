import Foundation

/// What the app knows about one destination: the ticket that builds it, its name, the file in the
/// owning feature folder that renders it, and the name the launch harness uses for it.
struct RouteInfo: Equatable, Sendable {
    enum Kind: String, Sendable {
        case preShell, tab, push, fullScreen, sheet
    }

    var kind: Kind
    /// `-startRoute` name, e.g. `replay`, `sessions.matchOverview`, `sheet.pointEditor`.
    var launchName: String
    /// The ticket that builds the screen, e.g. "T28".
    var ticket: String
    /// The screen's name, shown as its title.
    var title: String
    /// VoiceOver label of the Close control ("Close replay"); full-screen routes and sheets only.
    var closeLabel: String?
    /// The file that renders the destination, relative to `ios/Jovra`.
    var file: String
    /// False for the tab roots and for T07's own permission sheet, which are not placeholders.
    var isPlaceholder: Bool = true
}

extension AppDestination {
    /// One example of every destination, with launch-harness payloads. Tests visit each of these.
    static let catalog: [AppDestination] = {
        let session = SessionID.launchExample
        let time = MediaTime(value: 754, timescale: 1)
        var all: [AppDestination] = [.preShell(.welcome), .preShell(.onboarding(step: 1))]
        all += AppTab.allCases.map(AppDestination.tab)
        all += [
            .push(.sessions(.importVideos)),
            .push(.sessions(.matchOverview(session))),
            .push(.sessions(.practiceOverview(session))),
            .push(.insights(.shotMap(session))),
            .push(.insights(.serveLab(session))),
            .push(.insights(.strokeLab(session))),
            .push(.insights(.progress)),
            .push(.insights(.drillDetail("launch-drill"))),
            .push(.profile(.racketVault)),
            .push(.profile(.stringJournal)),
            .push(.profile(.storage)),
            .push(.profile(.settings)),
            .push(.profile(.spaceSaver)),
            .push(.profile(.diagnostics)),
            .push(.profile(.recordingRules)),
            .fullScreen(.capture(nil)),
            .fullScreen(.replay(ReplayRequest(session: session, point: "launch-point", filter: .needsReview))),
            .fullScreen(.compare(nil)),
            .fullScreen(.pointReview(session, .needsReview)),
            .fullScreen(.highlightReel(session)),
            .fullScreen(.drillSession("launch-drill")),
            .fullScreen(.processing(session)),
            .sheet(.pointEditor(session, "launch-point")),
            .sheet(.clipExport(session, "launch-point")),
            .sheet(.sharePack(session)),
            .sheet(.capabilityDetail("serve-speed-manual")),
            .sheet(.matchFormat(.sessionSetup)),
            .sheet(.players),
            .sheet(.cameraPreset),
            .sheet(.trash),
            .sheet(.goal(nil)),
            .sheet(.consentAttach(session)),
            .sheet(.calibration(session, time)),
            .sheet(.stringBroke(session, time)),
            .sheet(.restore(nil)),
            .sheet(.comparisonPicker),
            .sheet(.driveAccount),
            .sheet(.account),
            .sheet(.deleteAllData),
        ]
        all += LaunchConfiguration.Permission.allCases.map { .sheet(.permission($0)) }
        return all
    }()

    /// The destination a `-startRoute` name opens (the catalog's example for that name).
    init?(launchName: String) {
        guard let match = Self.catalog.first(where: { $0.info.launchName == launchName }) else { return nil }
        self = match
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    var info: RouteInfo {
        switch self {
        case .preShell(.welcome):
            RouteInfo(kind: .preShell, launchName: "welcome", ticket: "T18",
                      title: String(localized: "Welcome", table: "App", comment: "Screen name"),
                      file: "Features/Welcome/WelcomeScreen.swift")
        case .preShell(.onboarding):
            RouteInfo(kind: .preShell, launchName: "onboarding", ticket: "T18",
                      title: String(localized: "Player onboarding", table: "App", comment: "Screen name"),
                      file: "Features/Onboarding/OnboardingScreen.swift")
        case .tab(let tab):
            tab.rootInfo
        case .push(.sessions(let route)):
            route.info
        case .push(.insights(let route)):
            route.info
        case .push(.profile(let route)):
            route.info
        case .fullScreen(let route):
            route.info
        case .sheet(let route):
            route.info
        }
    }
}

extension SessionID {
    /// The session id the launch harness puts in payloads; no stored session has it.
    static let launchExample: SessionID = "launch-session"
}

private extension AppTab {
    var rootInfo: RouteInfo {
        let (ticket, file): (String, String) = switch self {
        case .home: ("T19", "Features/Home/HomeView.swift")
        case .sessions: ("T20", "Features/Sessions/SessionsView.swift")
        case .record: ("T21", "Features/Record/RecordView.swift")
        case .insights: ("T47", "Features/Insights/InsightsView.swift")
        case .profile: ("T18", "Features/Profile/ProfileView.swift")
        }
        return RouteInfo(kind: .tab, launchName: rawValue, ticket: ticket, title: title, file: file, isPlaceholder: false)
    }
}

private extension SessionsRoute {
    var info: RouteInfo {
        switch self {
        case .importVideos:
            push("sessions.import", "T26", String(localized: "Import videos", table: "App", comment: "Screen name"),
                 "Features/Sessions/Import/ImportScreen.swift")
        case .matchOverview:
            push("sessions.matchOverview", "T22", String(localized: "Match overview", table: "App", comment: "Screen name"),
                 "Features/Sessions/MatchOverview/MatchOverviewScreen.swift")
        case .practiceOverview:
            push("sessions.practiceOverview", "T22", String(localized: "Practice overview", table: "App", comment: "Screen name"),
                 "Features/Sessions/MatchOverview/PracticeOverviewScreen.swift")
        }
    }
}

private extension InsightsRoute {
    var info: RouteInfo {
        switch self {
        case .shotMap:
            push("insights.shotMap", "T41", String(localized: "Shot map", table: "App", comment: "Screen name"),
                 "Features/Insights/ShotMap/ShotMapScreen.swift")
        case .serveLab:
            push("insights.serveLab", "T43", String(localized: "Serve Lab", table: "App", comment: "Screen name"),
                 "Features/Insights/ServeLab/ServeLabScreen.swift")
        case .strokeLab:
            push("insights.strokeLab", "T42", String(localized: "Stroke Lab", table: "App", comment: "Screen name"),
                 "Features/Insights/StrokeLab/StrokeLabScreen.swift")
        case .progress:
            push("insights.progress", "T48", String(localized: "Progress", table: "App", comment: "Screen name"),
                 "Features/Insights/Progress/ProgressScreen.swift")
        case .drillDetail:
            push("insights.drillDetail", "T47", String(localized: "Drill", table: "App", comment: "Screen name"),
                 "Features/Insights/Plan/DrillDetailScreen.swift")
        }
    }
}

private extension ProfileRoute {
    var info: RouteInfo {
        switch self {
        case .racketVault:
            push("profile.racketVault", "T49", String(localized: "Racket Vault", table: "App", comment: "Screen name"),
                 "Features/Equipment/RacketVaultScreen.swift")
        case .stringJournal:
            push("profile.stringJournal", "T49", String(localized: "String journal", table: "App", comment: "Screen name"),
                 "Features/Equipment/StringJournalScreen.swift")
        case .storage:
            push("profile.storage", "T51", String(localized: "Storage and backup", table: "App", comment: "Screen name"),
                 "Features/Storage/StorageScreen.swift")
        case .settings:
            push("profile.settings", "T56", String(localized: "Settings", table: "App", comment: "Screen name"),
                 "Features/Settings/SettingsScreen.swift")
        case .spaceSaver:
            push("profile.spaceSaver", "T55", String(localized: "Space Saver", table: "App", comment: "Screen name"),
                 "Features/Storage/SpaceSaver/SpaceSaverScreen.swift")
        case .diagnostics:
            push("profile.diagnostics", "T57", String(localized: "Diagnostics", table: "App", comment: "Screen name"),
                 "Features/Diagnostics/DiagnosticsScreen.swift")
        case .recordingRules:
            push("profile.recordingRules", "T58", String(localized: "Recording rules", table: "App", comment: "Screen name"),
                 "Features/Profile/RecordingRules/RecordingRulesScreen.swift")
        }
    }
}

private extension FullScreenRoute {
    var info: RouteInfo {
        switch self {
        case .capture:
            cover("capture", "T17", String(localized: "Capture", table: "App", comment: "Screen name"),
                  String(localized: "Close capture", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Capture/CaptureScreen.swift", placeholder: CaptureScreen.isPlaceholder)
        case .replay:
            cover("replay", "T28", String(localized: "Smart replay", table: "App", comment: "Screen name"),
                  String(localized: "Close replay", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Replay/ReplayScreen.swift", placeholder: ReplayScreen.isPlaceholder)
        case .compare:
            cover("compare", "T45", String(localized: "Compare", table: "App", comment: "Screen name"),
                  String(localized: "Close compare", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Compare/CompareScreen.swift")
        case .pointReview:
            cover("pointReview", "T30", String(localized: "Point review", table: "App", comment: "Screen name"),
                  String(localized: "Close point review", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/PointReview/PointReviewScreen.swift")
        case .highlightReel:
            cover("highlightReel", "T37", String(localized: "Highlight reel", table: "App", comment: "Screen name"),
                  String(localized: "Close highlight reel", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Highlights/HighlightReelScreen.swift")
        case .drillSession:
            cover("drillSession", "T47", String(localized: "Drill session", table: "App", comment: "Screen name"),
                  String(localized: "Close drill session", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Insights/DrillSession/DrillSessionScreen.swift")
        case .processing:
            cover("processing", "T27", String(localized: "Processing", table: "App", comment: "Screen name"),
                  String(localized: "Close processing", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Processing/ProcessingScreen.swift")
        }
    }
}

private extension SheetRoute {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    var info: RouteInfo {
        switch self {
        case .pointEditor:
            sheet("pointEditor", "T29", String(localized: "Point editor", table: "App", comment: "Sheet name"),
                  String(localized: "Close point editor", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/PointEditor/PointEditorSheet.swift")
        case .clipExport:
            sheet("clipExport", "T36", String(localized: "Clip export", table: "App", comment: "Sheet name"),
                  String(localized: "Close clip export", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Export/ClipExportSheet.swift", placeholder: ClipExportSheet.isPlaceholder)
        case .sharePack:
            sheet("sharePack", "T38", String(localized: "Share Pack", table: "App", comment: "Sheet name"),
                  String(localized: "Close Share Pack", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/SharePack/SharePackSheet.swift")
        case .capabilityDetail:
            sheet("capabilityDetail", "T12", String(localized: "How this was measured", table: "App", comment: "Sheet name"),
                  String(localized: "Close how this was measured", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/CapabilityDetail/CapabilityDetailSheet.swift")
        case .matchFormat:
            sheet("matchFormat", "T21", String(localized: "Match format", table: "App", comment: "Sheet name"),
                  String(localized: "Close match format", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Record/FormatSheet/FormatSheet.swift")
        case .players:
            sheet("players", "T21", String(localized: "Players", table: "App", comment: "Sheet name"),
                  String(localized: "Close players", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Record/PlayersSheet.swift")
        case .cameraPreset:
            sheet("cameraPreset", "T21", String(localized: "Camera preset", table: "App", comment: "Sheet name"),
                  String(localized: "Close camera preset", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Record/CameraPresetSheet.swift")
        case .trash:
            sheet("trash", "T20", String(localized: "Trash", table: "App", comment: "Sheet name"),
                  String(localized: "Close trash", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Sessions/Library/TrashSheet.swift")
        case .goal:
            sheet("goal", "T48", String(localized: "Goal", table: "App", comment: "Sheet name"),
                  String(localized: "Close goal", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Insights/Progress/GoalSheet.swift")
        case .consentAttach:
            sheet("consentAttach", "T58", String(localized: "Consent", table: "App", comment: "Sheet name"),
                  String(localized: "Close consent", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Consent/ConsentAttachSheet.swift")
        case .calibration:
            sheet("calibration", "T23", String(localized: "Calibration", table: "App", comment: "Sheet name"),
                  String(localized: "Close calibration", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Calibration/CalibrationSheet.swift")
        case .stringBroke:
            sheet("stringBroke", "T50", String(localized: "String broke", table: "App", comment: "Sheet name"),
                  String(localized: "Close string broke", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Equipment/Reminders/StringBrokeSheet.swift")
        case .restore:
            sheet("restore", "T54", String(localized: "Restore a session", table: "App", comment: "Sheet name"),
                  String(localized: "Close restore a session", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Storage/Restore/RestoreSheet.swift")
        case .comparisonPicker:
            sheet("comparisonPicker", "T45", String(localized: "Choose two recordings", table: "App", comment: "Sheet name"),
                  String(localized: "Close choose two recordings", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Compare/ComparisonPickerSheet.swift")
        case .driveAccount:
            sheet("driveAccount", "T53", String(localized: "Google Drive account", table: "App", comment: "Sheet name"),
                  String(localized: "Close Google Drive account", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Storage/Account/DriveAccountSheet.swift")
        case .account:
            sheet("account", "T56", String(localized: "Account", table: "App", comment: "Sheet name"),
                  String(localized: "Close account", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Settings/AccountSheet.swift")
        case .deleteAllData:
            sheet("deleteAllData", "T57", String(localized: "Delete all JOVRA data", table: "App", comment: "Sheet name"),
                  String(localized: "Close delete all JOVRA data", table: "App", comment: "VoiceOver label of the Close control"),
                  "Features/Settings/DataSlot/DeleteAllDataSheet.swift")
        case .permission(let permission):
            RouteInfo(kind: .sheet, launchName: "sheet.permission.\(permission.rawValue)", ticket: "T07",
                      title: PermissionGuidance.name(of: permission),
                      closeLabel: String(localized: "Close", table: "Platform.Permissions", comment: "VoiceOver label of the explanation sheet's Close control"),
                      file: "Platform/Permissions/PermissionExplanationSheet.swift", isPlaceholder: false)
        }
    }
}

private func push(_ name: String, _ ticket: String, _ title: String, _ file: String) -> RouteInfo {
    RouteInfo(kind: .push, launchName: name, ticket: ticket, title: title, file: file)
}

private func cover(_ name: String, _ ticket: String, _ title: String, _ close: String, _ file: String, placeholder: Bool = true) -> RouteInfo {
    RouteInfo(kind: .fullScreen, launchName: name, ticket: ticket, title: title, closeLabel: close, file: file, isPlaceholder: placeholder)
}

private func sheet(_ name: String, _ ticket: String, _ title: String, _ close: String, _ file: String, placeholder: Bool = true) -> RouteInfo {
    RouteInfo(kind: .sheet, launchName: "sheet.\(name)", ticket: ticket, title: title, closeLabel: close, file: file, isPlaceholder: placeholder)
}
