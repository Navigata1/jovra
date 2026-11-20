import XCTest

/// T18 (#20): Welcome, three-step onboarding, the Profile hub and the demo entry. Every launch here names its profile
/// store (`-profile fresh` for a first run) so no test reads or leaves a profile on the simulator. Screenshots named
/// `sNN-...` pair with reference NN in evidence/ios/18-welcome-onboarding-profile/side-by-side.html.
final class WelcomeOnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: First run

    @MainActor
    func testGetStartedThreeStepsThenHomeWithNoPermissionRequest() throws {
        let app = XCUIApplication.jovra {
            $0.appearance = .light
            $0.profile = .fresh
            $0.library = .fresh
            // Every permission injected, so any request would reach the fake center and be counted.
            $0.permissions = [.camera: .notDetermined, .microphone: .notDetermined, .photosAdd: .notDetermined,
                              .notifications: .notDetermined, .health: .notDetermined]
        }
        app.launchEnvironment["JOVRA_PERMISSION_PROBE"] = "1"
        app.launch()

        XCTAssertTrue(app.heading("See your game.").waitForExistence(timeout: 10), "a first run opens on Welcome")
        XCTAssertFalse(app.otherElements["tabBar"].exists, "Welcome is before the shell")
        app.buttons["welcome.getStarted"].tap()

        XCTAssertTrue(app.heading("Make it your game").waitForExistence(timeout: 5))
        let rail = app.descendants(matching: .any)["onboarding.stepRail"]
        XCTAssertEqual(rail.label, "Step 2 of 3, Profile", "VoiceOver reads the step")
        XCTAssertEqual(probe(app), "0")
        app.buttons["onboarding.continue"].tap()

        XCTAssertTrue(app.heading("How you play").waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["onboarding.stepRail"].label, "Step 3 of 3, Play")
        XCTAssertTrue(element("onboarding.promise", in: app).exists, "the own-your-footage promise is stated")
        XCTAssertTrue(element("onboarding.icloud", in: app).label.contains("excluded from your iCloud device backup by default"))
        XCTAssertEqual(probe(app), "0", "onboarding asked for no permission (story 17)")
        app.buttons["onboarding.lookAround"].tap()

        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 8), "onboarding ends on Home")
        XCTAssertTrue(app.otherElements["tabBar"].exists)
        XCTAssertTrue(element("home.emptyState", in: app).waitForExistence(timeout: 8), "a new player sees the real empty state")
        XCTAssertFalse(element("home.demoBanner", in: app).exists)
    }

    @MainActor
    func testACancelledAppleSignInReturnsToWelcomeWithAPlainMessage() throws {
        for (fixture, message) in [(LaunchConfiguration.AppleSignInFixture.cancelled,
                                    "Sign in with Apple was cancelled. You can continue without an account."),
                                   (.failed, "Sign in with Apple didn't finish. You can continue without an account.")] {
            let app = XCUIApplication.launchJovra {
                $0.appearance = .light
                $0.profile = .fresh
                $0.appleSignIn = fixture
            }
            let apple = app.buttons["welcome.continueWithApple"]
            XCTAssertTrue(apple.waitForExistence(timeout: 10))
            apple.tap()
            let notice = element("welcome.notice", in: app)
            XCTAssertTrue(notice.waitForExistence(timeout: 5), "\(fixture): a plain message")
            XCTAssertTrue(app.staticTexts[message].exists, "\(fixture): “\(message)”")
            XCTAssertTrue(app.heading("See your game.").exists, "\(fixture): still on Welcome")
            XCTAssertTrue(app.buttons["welcome.getStarted"].isEnabled, "\(fixture): Get started still works")
            attachScreenshot(app, name: "s01-light-welcome-apple-\(fixture.rawValue)")
            try auditScreen(app)
            app.buttons["welcome.getStarted"].tap()
            XCTAssertTrue(app.heading("Make it your game").waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testANewAppleSignInOpensOnboardingWithTheNameFilledIn() {
        let app = XCUIApplication.launchJovra { $0.appearance = .light; $0.profile = .fresh; $0.appleSignIn = .succeeded }
        XCTAssertTrue(app.buttons["welcome.continueWithApple"].waitForExistence(timeout: 10))
        app.buttons["welcome.continueWithApple"].tap()
        XCTAssertTrue(app.heading("Make it your game").waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["onboarding.name"].value as? String, "Jon", "Apple's given name is filled in")
    }

    // MARK: Profile persists and is editable

    @MainActor
    func testLeftHandedOneHandedBackhandPersistsAcrossRelaunchAndCanBeEdited() {
        var app = XCUIApplication.launchJovra { $0.appearance = .light; $0.profile = .persistentNew; $0.library = .fresh }
        XCTAssertTrue(app.buttons["welcome.getStarted"].waitForExistence(timeout: 10))
        app.buttons["welcome.getStarted"].tap()
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Sam\n")
        app.buttons["onboarding.hand.1"].tap()       // Left-handed
        app.buttons["onboarding.backhand.0"].tap()   // One-handed backhand
        XCTAssertTrue(app.buttons["onboarding.hand.1"].isSelected)
        XCTAssertTrue(app.buttons["onboarding.backhand.0"].isSelected)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.lookAround"].waitForExistence(timeout: 5))
        app.buttons["onboarding.lookAround"].tap()
        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 8))
        app.terminate()

        app = XCUIApplication.launchJovra { $0.appearance = .light; $0.profile = .persistent; $0.library = .fresh }
        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 10), "a saved profile skips Welcome")
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.heading("Sam").waitForExistence(timeout: 5), "the hub is titled with the player's name")
        XCTAssertTrue(app.staticTexts["Left-handed · One-handed backhand"].exists, "handedness and backhand survived the relaunch")

        app.buttons["profile.row.player"].tap()
        XCTAssertTrue(app.heading("Your player profile").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.hand.1"].isSelected, "the edit screen opens on Left-handed")
        app.buttons["onboarding.hand.0"].tap()
        XCTAssertTrue(element("profile.edit.handednessNote", in: app).waitForExistence(timeout: 3),
                      "changing handedness says the filters will update")
        app.buttons["profile.edit.save"].tap()
        XCTAssertTrue(app.staticTexts["Right-handed · One-handed backhand"].waitForExistence(timeout: 5), "the edit is saved")
        app.terminate()

        app = XCUIApplication.launchJovra { $0.appearance = .light; $0.profile = .persistent; $0.library = .fresh; $0.startRoute = "profile" }
        XCTAssertTrue(app.staticTexts["Right-handed · One-handed backhand"].waitForExistence(timeout: 10), "the edit survived a relaunch")
    }

    // MARK: Copy

    @MainActor
    func testCopyOfScreens01And02MatchesTheBrief() throws {
        let app = XCUIApplication.launchJovra { $0.appearance = .light; $0.profile = .fresh }
        XCTAssertTrue(app.heading("See your game.").waitForExistence(timeout: 10))
        try assertBriefCopy(screen: 1, in: app)

        app.buttons["welcome.getStarted"].tap()
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Jon\n")
        // Nothing is preselected (screens.md S02); the reference's selections are made here as the player would.
        app.buttons["onboarding.hand.0"].tap()
        app.buttons["onboarding.backhand.0"].tap()
        app.buttons["onboarding.level.1"].tap()
        tapGoal("serveConsistency", in: app)
        tapGoal("matchStrategy", in: app)
        try assertBriefCopy(screen: 2, in: app, corrections: [
            // The brief quotes it without the full stop the spec's caption has.
            "Change these anytime": .replace(with: ["Change these anytime."]),
        ])
        XCTAssertTrue(app.buttons["onboarding.goal.serveConsistency"].isSelected, "Serve consistency is selected")
        XCTAssertTrue(app.buttons["onboarding.goal.matchStrategy"].isSelected, "Match strategy is selected")

        // A fourth goal is refused and says why.
        tapGoal("improveFitness", in: app)
        tapGoal("winMoreMatches", in: app)
        XCTAssertFalse(app.buttons["onboarding.goal.winMoreMatches"].isSelected)
        XCTAssertTrue(element("onboarding.goals.limit", in: app).exists)
    }

    // MARK: Helpers

    @MainActor
    private func tapGoal(_ goal: String, in app: XCUIApplication) {
        tapChip(goal, in: app)
    }

    @MainActor
    private func probe(_ app: XCUIApplication) -> String? {
        element("harness.permissionRequests", in: app).value as? String
    }
}

/// T18: "Explore a demo", the DemoBanner and "Make it yours".
final class DemoEntryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testExploreADemoInstallsEightBadgedSampleSessionsAndShowsTheBanner() {
        let app = XCUIApplication.launchJovra { $0.appearance = .light; $0.profile = .fresh; $0.library = .fresh; $0.demo = .sample }
        enterDemo(app)
        XCTAssertTrue(element("home.demoBanner", in: app).exists, "Home shows the DemoBanner")
        XCTAssertTrue(app.staticTexts["You're exploring sample data"].exists)
        attachScreenshot(app, name: "t18-light-home-demo")

        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.heading("Jon").waitForExistence(timeout: 5), "the sample player Jon")
        XCTAssertTrue(element("profile.demoBanner", in: app).exists, "the Profile hub shows the DemoBanner")
        XCTAssertTrue(element("profile.demoBanner", in: app).staticTexts["Sample"].exists, "the sample profile is badged Sample")

        assertEightSampleSessions(app)
    }

    @MainActor
    func testMakeItYoursEndsTheDemoAndKeepsTheSamplesBadged() {
        let app = XCUIApplication.launchJovra { $0.appearance = .light; $0.profile = .fresh; $0.library = .fresh }
        enterDemo(app)
        element("home.demoBanner", in: app).buttons["Make it yours"].tap()
        XCTAssertTrue(app.heading("Make it your game").waitForExistence(timeout: 5), "Make it yours starts onboarding")
        let name = app.textFields["onboarding.name"]
        XCTAssertEqual(name.value as? String, "First name", "onboarding starts empty, not with the sample Jon")
        name.tap(); name.typeText("Sam\n")
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.lookAround"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.exploreSample"].exists, "the sample is already installed")
        app.buttons["onboarding.lookAround"].tap()

        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 8))
        XCTAssertTrue(element("home.emptyState", in: app).waitForExistence(timeout: 8), "Home shows the real empty state")
        XCTAssertFalse(element("home.demoBanner", in: app).exists, "the DemoBanner is gone")
        XCTAssertTrue(app.staticTexts["Your first session shows up here."].exists)
        attachScreenshot(app, name: "t18-light-home-after-make-it-yours")
        assertEightSampleSessions(app)
    }

    @MainActor
    private func enterDemo(_ app: XCUIApplication) {
        let explore = app.buttons["welcome.exploreDemo"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 20), "the demo opens on Home")
        XCTAssertTrue(element("home.demoBanner", in: app).waitForExistence(timeout: 5))
    }

    /// The library lists exactly what the store holds: 8 sessions, every one badged Sample.
    @MainActor
    private func assertEightSampleSessions(_ app: XCUIApplication) {
        app.buttons["tab.sessions"].tap()
        XCTAssertTrue(app.heading("Your sessions").waitForExistence(timeout: 5))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 8, "8 sample sessions in the store")
        for row in rows.allElementsBoundByIndex {
            XCTAssertTrue(row.label.contains("Sample"), "“\(row.label)” is badged Sample")
        }
    }
}

/// T18: accessibility audits and evidence screenshots for Welcome, each onboarding step and the Profile hub, in light,
/// dark and AX5, plus iPhone landscape (text clipping) and Reduce Motion.
final class WelcomeOnboardingAuditUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private static let variants: [(LaunchConfiguration.Appearance, ContentSize?, String)] = [
        (.light, nil, "light"), (.dark, nil, "dark"), (.light, .accessibility5, "ax5"),
    ]

    @MainActor
    func testWelcomeAndOnboardingStepsPassTheAuditInLightDarkAndAX5() throws {
        for (appearance, size, variant) in Self.variants {
            let app = XCUIApplication.launchJovra(contentSize: size) { $0.appearance = appearance; $0.profile = .fresh }
            XCTAssertTrue(app.heading("See your game.").waitForExistence(timeout: 10))
            attachScreenshot(app, name: "s01-\(variant)-welcome")
            assertHitTargets(in: app)
            try auditScreen(app)

            app.buttons["welcome.getStarted"].tap()
            XCTAssertTrue(app.heading("Make it your game").waitForExistence(timeout: 5))
            if size == nil {
                let name = app.textFields["onboarding.name"]
                name.tap(); name.typeText("Jon\n")
                app.buttons["onboarding.hand.0"].tap()
                app.buttons["onboarding.backhand.0"].tap()
                app.buttons["onboarding.level.1"].tap()
                for goal in ["serveConsistency", "matchStrategy"] { tapChip(goal, in: app) }
                for _ in 0..<4 { app.swipeDown(velocity: .fast) }
            }
            attachScreenshot(app, name: "s02-\(variant)-onboarding-profile")
            assertHitTargets(in: app)
            try auditScreen(app, pageTop: onboardingTop(app))

            app.buttons["onboarding.continue"].tap()
            XCTAssertTrue(app.heading("How you play").waitForExistence(timeout: 5))
            attachScreenshot(app, name: "s02-\(variant)-onboarding-play")
            assertHitTargets(in: app)
            try auditScreen(app, pageTop: onboardingTop(app))
            app.terminate()
        }
    }

    @MainActor
    func testTheProfileHubPassesTheAuditInLightDarkAndAX5() throws {
        for (appearance, size, variant) in Self.variants {
            let app = XCUIApplication.launchJovra(contentSize: size) {
                $0.appearance = appearance; $0.profile = .fresh; $0.library = .fresh
            }
            let explore = app.buttons["welcome.exploreDemo"]
            XCTAssertTrue(explore.waitForExistence(timeout: 10))
            explore.tap()
            XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 20))
            attachScreenshot(app, name: "t18-\(variant)-home-demo")
            app.buttons["tab.profile"].tap()
            XCTAssertTrue(app.heading("Jon").waitForExistence(timeout: 5))
            attachScreenshot(app, name: "t18-\(variant)-profile-hub")
            assertHitTargets(in: app)
            try auditScreen(app)

            app.buttons["profile.row.player"].tap()
            XCTAssertTrue(app.heading("Your player profile").waitForExistence(timeout: 5))
            // The push slides the page in; audit it once it has stopped moving.
            waitForScrollingToSettle(app.heading("Your player profile"))
            attachScreenshot(app, name: "t18-\(variant)-profile-edit")
            try auditScreen(app, pageTop: app.buttons["profile.edit.back"].frame.minY - 8, allowUnattributedCropContrast: true)
            app.terminate()
        }
    }

    @MainActor
    func testLandscapeIPhoneHasNoClippedText() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication.launchJovra { $0.appearance = .light; $0.profile = .fresh; $0.library = .fresh }
        XCTAssertTrue(app.heading("See your game.").waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(app)
        XCTAssertTrue(app.buttons["welcome.getStarted"].waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "the app is in landscape")
        XCTAssertGreaterThan(app.heading("See your game.").frame.minX, window.width * 0.4,
                             "S01 landscape: the panel sits on the trailing side of the hero")
        attachScreenScreenshot(name: "s01-light-landscape-welcome")
        try app.performAccessibilityAudit(for: .textClipped)

        app.buttons["welcome.getStarted"].tap()
        XCTAssertTrue(app.heading("Make it your game").waitForExistence(timeout: 5))
        attachScreenScreenshot(name: "s02-light-landscape-onboarding-profile")
        try app.performAccessibilityAudit(for: .textClipped)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.heading("How you play").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: .textClipped)
        app.buttons["onboarding.lookAround"].tap()

        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 8))
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.heading("Profile").waitForExistence(timeout: 5))
        attachScreenScreenshot(name: "t18-light-landscape-profile-hub")
        try app.performAccessibilityAudit(for: .textClipped)
    }

    @MainActor
    func testWithReduceMotionTheFlowStillCompletes() {
        let app = XCUIApplication.launchJovra { $0.appearance = .dark; $0.profile = .fresh; $0.library = .fresh; $0.reduceMotion = true }
        XCTAssertTrue(app.buttons["welcome.getStarted"].waitForExistence(timeout: 10))
        app.buttons["welcome.getStarted"].tap()
        XCTAssertTrue(app.heading("Make it your game").waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.heading("How you play").waitForExistence(timeout: 5))
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.heading("Make it your game").waitForExistence(timeout: 5), "Back returns to step 2")
        app.buttons["onboarding.continue"].tap()
        app.buttons["onboarding.lookAround"].tap()
        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 5))
    }
}

/// Where an onboarding page stops scrolling under its status-bar backdrop: the top of the Back row, less its 8 pt inset.
@MainActor
private func onboardingTop(_ app: XCUIApplication) -> CGFloat {
    app.buttons["onboarding.back"].frame.minY - 8
}

extension XCTestCase {
    /// A landscape capture from the screen itself (the app snapshot came back portrait-framed in landscape here).
    @MainActor
    func attachScreenScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Waits until the rotation has finished: the window is wider than tall and has stopped changing.
@MainActor
private func waitForLandscape(_ app: XCUIApplication) {
    let window = app.windows.firstMatch
    for _ in 0..<20 where !(window.frame.width > window.frame.height) { Thread.sleep(forTimeInterval: 0.25) }
    Thread.sleep(forTimeInterval: 1)
}

/// Scrolls a goal chip into view, waits for the page to stop moving, then taps it.
@MainActor
private func tapChip(_ goal: String, in app: XCUIApplication) {
    let chip = app.buttons["onboarding.goal.\(goal)"]
    // Clear of the bottom action bar, which stays over the scrolling page.
    let bar = app.buttons["onboarding.continue"]
    for _ in 0..<6 where !(chip.isHittable && chip.frame.maxY < bar.frame.minY - 24) {
        app.swipeUp(velocity: .slow)
    }
    var previous = chip.frame.minY
    for _ in 0..<10 {
        Thread.sleep(forTimeInterval: 0.3)
        if abs(chip.frame.minY - previous) < 0.5 { break }
        previous = chip.frame.minY
    }
    chip.tap()
}

@MainActor
private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}
