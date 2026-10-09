import Foundation
import Testing
@testable import Jovra

@MainActor
@Suite("App router")
struct AppRouterTests {
    /// Every destination of screen spec §0.1 and ticket T07, by launch name, with the ticket that
    /// builds it (from the owned areas in docs/spec/tickets.md). Written out by hand: the catalog must
    /// match this list, not the other way round.
    static let expectedTickets: [String: String] = [
        "welcome": "T18", "onboarding": "T18",
        "home": "T19", "sessions": "T20", "record": "T21", "insights": "T47", "profile": "T18",
        "sessions.import": "T26", "sessions.matchOverview": "T22", "sessions.practiceOverview": "T22",
        "insights.shotMap": "T41", "insights.serveLab": "T43", "insights.strokeLab": "T42",
        "insights.progress": "T48", "insights.drillDetail": "T47",
        "profile.racketVault": "T49", "profile.stringJournal": "T49", "profile.storage": "T51",
        "profile.settings": "T56", "profile.spaceSaver": "T55", "profile.diagnostics": "T57",
        "profile.recordingRules": "T58",
        "capture": "T17", "replay": "T28", "compare": "T45", "pointReview": "T30",
        "highlightReel": "T37", "drillSession": "T47", "processing": "T27",
        "sheet.pointEditor": "T29", "sheet.clipExport": "T36", "sheet.sharePack": "T38",
        "sheet.capabilityDetail": "T12", "sheet.matchFormat": "T21", "sheet.players": "T21",
        "sheet.cameraPreset": "T21", "sheet.trash": "T20", "sheet.goal": "T48",
        "sheet.consentAttach": "T58", "sheet.calibration": "T23", "sheet.stringBroke": "T50",
        "sheet.restore": "T54", "sheet.comparisonPicker": "T45", "sheet.driveAccount": "T53",
        "sheet.account": "T56", "sheet.deleteAllData": "T57",
        "sheet.permission.camera": "T07", "sheet.permission.microphone": "T07",
        "sheet.permission.photosAdd": "T07", "sheet.permission.notifications": "T07",
        "sheet.permission.health": "T07",
    ]

    static let expectedCloseLabels: [String: String] = [
        "capture": "Close capture", "replay": "Close replay", "compare": "Close compare",
        "pointReview": "Close point review", "highlightReel": "Close highlight reel",
        "drillSession": "Close drill session", "processing": "Close processing",
    ]

    nonisolated static var fullScreenRoutes: [FullScreenRoute] {
        AppDestination.catalog.compactMap { if case .fullScreen(let route) = $0 { route } else { nil } }
    }

    // MARK: The catalog

    @Test("tabs are Home, Sessions, Record, Insights, Profile in that order")
    func tabOrder() {
        #expect(AppTab.allCases.map(\.title) == ["Home", "Sessions", "Record", "Insights", "Profile"])
    }

    @Test("the catalog has exactly the destinations of §0.1, each once, with the ticket that builds it")
    func catalogMatchesTheSpec() {
        let names = AppDestination.catalog.map(\.info.launchName)
        #expect(names.count == Set(names).count, "launch names are unique")
        #expect(Set(names) == Set(Self.expectedTickets.keys))
        for destination in AppDestination.catalog {
            #expect(destination.info.ticket == Self.expectedTickets[destination.info.launchName], "\(destination.info.launchName)")
        }
        #expect(Self.fullScreenRoutes.count == 7, "capture, replay, compare, pointReview, highlightReel, drillSession, processing")
    }

    @Test("every launch name opens its own destination")
    func launchNamesResolve() {
        for destination in AppDestination.catalog {
            #expect(AppDestination(launchName: destination.info.launchName) == destination)
        }
        #expect(AppDestination(launchName: "capturePreview") == nil, "the foundation's preview route is gone")
    }

    @Test("every full-screen route has a Close control labelled 'Close <screen>'")
    func closeLabels() {
        for route in Self.fullScreenRoutes {
            let info = AppDestination.fullScreen(route).info
            #expect(info.closeLabel == Self.expectedCloseLabels[info.launchName], "\(info.launchName)")
        }
    }

    @Test("every placeholder lives in its owning feature folder and names its ticket")
    func placeholderFiles() throws {
        let appSources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Jovra")
        for destination in AppDestination.catalog {
            let info = destination.info
            let url = appSources.appendingPathComponent(info.file)
            let source = try String(contentsOf: url, encoding: .utf8)
            if info.isPlaceholder {
                #expect(info.file.hasPrefix("Features/"), "\(info.launchName) renders from a feature folder")
                #expect(source.contains("handed to \(info.ticket)"), "\(info.file) names \(info.ticket)")
                #expect(source.contains("RoutePlaceholder("), "\(info.file) is still the placeholder")
            }
        }
    }

    // MARK: Full-screen routes, sheets, pushes and the pre-shell

    @Test("starts on Home with no full-screen route, sheet or pre-shell")
    func initialState() {
        let router = AppRouter()
        #expect(router.selectedTab == .home)
        #expect(router.fullScreenRoute == nil)
        #expect(router.sheet == nil)
        #expect(router.preShell == nil)
        #expect(router.isTabBarVisible)
    }

    @Test("presenting any full-screen route hides the tab bar; dismissing restores it on the same tab",
          arguments: AppRouterTests.fullScreenRoutes)
    func presentAndDismiss(route: FullScreenRoute) {
        let router = AppRouter()
        router.select(.insights)
        router.present(route)
        #expect(router.fullScreenRoute == route)
        #expect(!router.isTabBarVisible)
        router.dismissFullScreen()
        #expect(router.fullScreenRoute == nil)
        #expect(router.isTabBarVisible)
        #expect(router.selectedTab == .insights)
    }

    @Test("a sheet over a full-screen route closes with it; a sheet never hides the tab bar")
    func sheetOverFullScreen() {
        let router = AppRouter()
        router.present(sheet: .trash)
        #expect(router.isTabBarVisible)
        router.present(.replay(ReplayRequest(session: "s1")))
        #expect(router.sheet == nil, "presenting a cover replaces a sheet")
        router.present(sheet: .pointEditor("s1", "p4"))
        #expect(router.sheet == .pointEditor("s1", "p4"))
        router.dismissFullScreen()
        #expect(router.sheet == nil)
        #expect(router.isTabBarVisible)
    }

    @Test("a push selects its tab and grows that tab's stack only")
    func pushes() {
        let router = AppRouter()
        router.push(.sessions(.matchOverview("s1")))
        router.push(.sessions(.importVideos))
        router.push(.profile(.settings))
        #expect(router.selectedTab == .profile)
        #expect(router.state.sessionsPath == [.matchOverview("s1"), .importVideos])
        #expect(router.state.profilePath == [.settings])
        #expect(router.state.insightsPath.isEmpty)
        #expect(router.isTabBarVisible, "pushes keep the tab bar")
    }

    @Test("showing a push replaces its tab's stack and leaves any focused flow")
    func showPush() {
        let router = AppRouter()
        router.push(.insights(.progress))
        router.present(.compare(nil))
        router.show(.push(.insights(.serveLab("s2"))))
        #expect(router.state.insightsPath == [.serveLab("s2")])
        #expect(router.fullScreenRoute == nil)
        #expect(router.selectedTab == .insights)
    }

    @Test("the pre-shell has no tab bar; entering the shell shows it")
    func preShell() {
        let router = AppRouter()
        router.show(.preShell(.onboarding(step: 2)))
        #expect(router.preShell == .onboarding(step: 2))
        #expect(!router.isTabBarVisible)
        router.enterShell()
        #expect(router.preShell == nil)
        #expect(router.isTabBarVisible)
    }

    // MARK: State restoration

    @Test("every destination's payload round-trips through state restoration",
          arguments: AppDestination.catalog)
    func restoration(destination: AppDestination) throws {
        let router = AppRouter()
        router.push(.profile(.storage))
        router.show(destination)
        let data = try router.state.restorationData()
        let restored = AppRouter(state: try RouterState(restorationData: data))
        #expect(restored.state == router.state)
        #expect(restored.isTabBarVisible == router.isTabBarVisible)
    }

    @Test("a full navigation state with every kind of payload survives restoration")
    func fullStateRestoration() throws {
        var state = RouterState()
        state.selectedTab = .sessions
        state.sessionsPath = [.matchOverview("m1"), .practiceOverview("p1"), .importVideos]
        state.insightsPath = [.shotMap(nil), .drillDetail("d1")]
        state.profilePath = [.racketVault, .spaceSaver]
        state.fullScreen = .replay(ReplayRequest(session: "m1", point: "pt9", filter: .unscored))
        state.sheet = .calibration("m1", MediaTime(value: 90_090, timescale: 30_000))
        let restored = try RouterState(restorationData: state.restorationData())
        #expect(restored == state)
        #expect(restored.sheet == .calibration("m1", MediaTime(value: 90_090, timescale: 30_000)), "rational time kept exactly")
    }

    @Test("saved state that no longer decodes is rejected, never half-restored")
    func corruptRestoration() {
        #expect(throws: (any Error).self) { try RouterState(restorationData: Data("{\"selectedTab\":\"nowhere\"}".utf8)) }
    }

    @Test("only a launch without harness arguments restores saved state")
    func restorationOnlyWithoutHarnessArguments() {
        #expect(AppRoot.restoresSavedState(launch: LaunchConfiguration(arguments: ["Jovra"])))
        #expect(!AppRoot.restoresSavedState(launch: LaunchConfiguration(arguments: ["Jovra", "-appearance", "dark"])))
        #expect(!AppRoot.restoresSavedState(launch: LaunchConfiguration(arguments: ["Jovra", "-startRoute", "replay"])))
    }

    // MARK: Deep links

    static let library = FixedSessionLookup(sessions: [
        SessionSummary(id: "match-old", kind: .singlesMatch, startedAt: date("2026-09-20T10:00:00Z"), isSample: false),
        SessionSummary(id: "match-new", kind: .doublesMatch, startedAt: date("2026-10-05T10:00:00Z"), isSample: false),
        SessionSummary(id: "practice-newest", kind: .servePractice, startedAt: date("2026-10-06T10:00:00Z"), isSample: false),
        SessionSummary(id: "sample-match", kind: .singlesMatch, startedAt: date("2026-10-07T10:00:00Z"), isSample: true),
    ])

    @Test("'Start singles recording' opens the Record tab and presents capture(setup: singles)")
    func startSinglesRecording() async throws {
        let router = AppRouter()
        router.push(.profile(.settings))
        let opened = await router.open(try #require(URL(string: "jovra://record/singles")), sessions: Self.library)
        #expect(opened)
        #expect(router.selectedTab == .record)
        #expect(router.fullScreenRoute == .capture(SessionSetupDraft(kind: .singlesMatch)))
        #expect(!router.isTabBarVisible)
    }

    @Test("'Show last match' pushes the overview of the newest real match, never a sample or a practice")
    func showLastMatch() async throws {
        let router = AppRouter()
        router.present(.highlightReel("match-old"))
        await router.open(try #require(URL(string: "jovra://sessions/last-match")), sessions: Self.library)
        #expect(router.selectedTab == .sessions)
        #expect(router.state.sessionsPath == [.matchOverview("match-new")])
        #expect(router.fullScreenRoute == nil)
    }

    @Test("'Show last match' with no real match opens the library")
    func showLastMatchWithoutMatches() async throws {
        let onlySample = FixedSessionLookup(sessions: [
            SessionSummary(id: "sample-match", kind: .singlesMatch, startedAt: Self.date("2026-10-07T10:00:00Z"), isSample: true),
        ])
        let router = AppRouter()
        await router.open(try #require(URL(string: "jovra://sessions/last-match")), sessions: onlySample)
        #expect(router.selectedTab == .sessions)
        #expect(router.state.sessionsPath.isEmpty)
    }

    @Test("a Share Pack link opens the session's overview with the Share Pack sheet")
    func sharePackLink() async throws {
        let router = AppRouter()
        await router.open(try #require(URL(string: "jovra://share-pack/practice-newest")), sessions: Self.library)
        #expect(router.state.sessionsPath == [.practiceOverview("practice-newest")])
        #expect(router.sheet == .sharePack("practice-newest"))
    }

    @Test("links JOVRA does not own change nothing",
          arguments: ["https://example.com/record/singles", "jovra://nowhere", "jovra://record/badminton",
                      "jovra://share-pack/..%2Fsecret", "jovra://share-pack/", "com.googleusercontent.apps.123:/oauth2redirect"])
    func unknownLinks(link: String) async throws {
        let router = AppRouter()
        router.push(.insights(.progress))
        let before = router.state
        let opened = await router.open(try #require(URL(string: link)), sessions: Self.library)
        #expect(!opened)
        #expect(router.state == before)
    }

    @Test("each deep link's URL parses back to the same link")
    func deepLinkURLs() {
        let links: [DeepLink] = SessionKind.allCases.map(DeepLink.startRecording) + [.showLastMatch, .sharePack("m1")]
        for link in links {
            #expect(DeepLink(url: link.url) == link)
        }
        #expect(DeepLink.startRecording(.singlesMatch).url.absoluteString == "jovra://record/singles")
        #expect(DeepLink.showLastMatch.url.absoluteString == "jovra://sessions/last-match")
    }

    private static func date(_ text: String) -> Date {
        (try? Date(text, strategy: .iso8601)) ?? .distantPast
    }
}
