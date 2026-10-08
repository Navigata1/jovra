import Testing
@testable import Jovra

/// LaunchConfiguration is the contract between the app and its UI tests: the tests build launch
/// arguments with it and the app parses them back. Expected values are hand-written literals.
@Suite("Launch configuration")
struct LaunchConfigurationTests {
    @Test("no arguments means live behaviour everywhere")
    func defaults() {
        let configuration = LaunchConfiguration(arguments: ["/path/to/Jovra"])
        #expect(configuration.appearance == nil)
        #expect(configuration.demo == .off)
        #expect(configuration.fixtureCamera == nil)
        #expect(configuration.permissions.isEmpty)
        #expect(configuration.archiveState == nil)
        #expect(configuration.reduceMotion == false)
        #expect(configuration.pseudoLocale == nil)
        #expect(configuration.startRoute == nil)
        #expect(configuration.problems.isEmpty)
    }

    @Test("parses every supported argument, ignoring system arguments around them")
    func parsesEverything() {
        let configuration = LaunchConfiguration(arguments: [
            "/path/to/Jovra",
            "-appearance", "dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-demo", "sample",
            "-fixtureCamera", "baseline-rally",
            "-permissions", "camera=denied,microphone=notDetermined",
            "-permissions", "health=restricted",
            "-archiveState", "needsReconnect",
            "-reduceMotion", "YES",
            "-pseudoLocale", "accented",
            "-NSAccentuateLocalizedStrings", "YES",
            "-startRoute", "insights",
        ])
        #expect(configuration.appearance == .dark)
        #expect(configuration.demo == .sample)
        #expect(configuration.fixtureCamera == "baseline-rally")
        #expect(configuration.permissions == [.camera: .denied, .microphone: .notDetermined, .health: .restricted])
        #expect(configuration.archiveState == .needsReconnect)
        #expect(configuration.reduceMotion)
        #expect(configuration.pseudoLocale == .accented)
        #expect(configuration.startRoute == "insights")
        #expect(configuration.problems.isEmpty)
    }

    @Test("bad values are reported, never silently ignored", arguments: [
        (["-appearance", "sepia"], "-appearance: unknown value “sepia” (expected system, light, dark)"),
        (["-permissions", "camera=maybe"], "-permissions: unknown state “maybe” for camera (expected notDetermined, denied, restricted, authorized)"),
        (["-permissions", "location=denied"], "-permissions: unknown permission “location” (expected camera, microphone, photosAdd, notifications, health)"),
        (["-permissions", "camera"], "-permissions: “camera” is not permission=state"),
        (["-reduceMotion", "sometimes"], "-reduceMotion: unknown value “sometimes” (expected YES or NO)"),
        (["-archiveState"], "-archiveState: missing value"),
    ])
    func reportsProblems(arguments: [String], problem: String) {
        let configuration = LaunchConfiguration(arguments: ["Jovra"] + arguments)
        #expect(configuration.problems == [problem])
    }

    @Test("the arguments a UI test builds parse back to the same configuration")
    func roundTrip() {
        var configuration = LaunchConfiguration()
        configuration.appearance = .light
        configuration.demo = .sample
        configuration.fixtureCamera = "baseline-rally"
        configuration.permissions = [.photosAdd: .authorized, .notifications: .denied]
        configuration.archiveState = .awaitingSetup
        configuration.reduceMotion = true
        configuration.pseudoLocale = .doubleLength
        configuration.startRoute = "capturePreview"

        let parsed = LaunchConfiguration(arguments: ["Jovra"] + configuration.arguments)
        #expect(parsed == configuration)
        #expect(parsed.problems.isEmpty)
    }

    @Test("a pseudo-locale also switches on the matching system pseudolanguage")
    func pseudoLocaleSystemArguments() {
        var configuration = LaunchConfiguration()
        configuration.pseudoLocale = .accented
        #expect(configuration.arguments == [
            "-pseudoLocale", "accented",
            "-NSAccentuateLocalizedStrings", "YES",
            "-NSSurroundLocalizedStrings", "YES",
        ])
    }

    @Test("the start route selects a tab or a full-screen route; anything else is reported")
    func startRoute() {
        #expect(LaunchConfiguration(arguments: ["Jovra", "-startRoute", "profile"]).startTab == .profile)
        #expect(LaunchConfiguration(arguments: ["Jovra", "-startRoute", "capturePreview"]).startFullScreenRoute == .capturePreview)
        let unknown = LaunchConfiguration(arguments: ["Jovra", "-startRoute", "nowhere"])
        #expect(unknown.startTab == nil)
        #expect(unknown.startFullScreenRoute == nil)
        #expect(unknown.unresolvedStartRoute == "nowhere")
    }

    @Test("every problem the app logs at launch, an unknown start route included")
    func reportedProblems() {
        let unknown = LaunchConfiguration(arguments: ["Jovra", "-startRoute", "nowhere", "-reduceMotion", "sometimes"])
        #expect(unknown.reportedProblems == [
            "-reduceMotion: unknown value “sometimes” (expected YES or NO)",
            "-startRoute: unknown route “nowhere” (expected home, sessions, record, insights, profile, capturePreview)",
        ])
        #expect(LaunchConfiguration(arguments: ["Jovra", "-startRoute", "insights"]).reportedProblems.isEmpty)
        #expect(LaunchConfiguration(arguments: ["Jovra", "-startRoute", "capturePreview"]).reportedProblems.isEmpty)
        #expect(LaunchConfiguration(arguments: ["Jovra"]).reportedProblems.isEmpty)
    }
}
