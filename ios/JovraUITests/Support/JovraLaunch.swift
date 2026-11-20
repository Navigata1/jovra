import XCTest

/// Text sizes UI tests launch at.
enum ContentSize: String {
    case large = "UICTContentSizeCategoryL"
    /// The largest accessibility size, AX5.
    case accessibility5 = "UICTContentSizeCategoryAccessibilityXXXL"
}

extension XCUIApplication {
    /// The app, configured through `LaunchConfiguration` (the same type the app parses, compiled into
    /// this target) and optionally at a Dynamic Type size.
    @MainActor
    static func jovra(
        contentSize: ContentSize? = nil,
        _ configure: (inout LaunchConfiguration) -> Void = { _ in }
    ) -> XCUIApplication {
        var configuration = LaunchConfiguration()
        configure(&configuration)
        let app = XCUIApplication()
        app.launchArguments += configuration.arguments
        // Every launch starts from the default session setup (T21 remembers the last one); a test of
        // that memory sets this to "0" before relaunching.
        app.launchEnvironment["JOVRA_SETUP_RESET"] = "1"
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        }
        return app
    }

    /// Launches the app configured as above and returns it.
    @MainActor
    static func launchJovra(
        contentSize: ContentSize? = nil,
        _ configure: (inout LaunchConfiguration) -> Void = { _ in }
    ) -> XCUIApplication {
        let app = jovra(contentSize: contentSize, configure)
        app.launch()
        return app
    }
}

/// The five tabs as the shell shows them (identifier, slug for screenshot names, English heading).
enum ShellTab: CaseIterable {
    case home, sessions, record, insights, profile

    var identifier: String { "tab.\(slug)" }
    var slug: String { String(describing: self) }
    var label: String { slug.prefix(1).uppercased() + slug.dropFirst() }
    var heading: String {
        switch self {
        case .home: "Home"
        case .sessions: "Your sessions"
        case .record: "Set up your session"
        case .insights: "Insights"
        case .profile: "Profile"
        }
    }
}

extension XCUIApplication {
    /// The screen's display title (every `JovraScreen` marks it `screen.title`).
    @MainActor
    var screenTitle: XCUIElement {
        staticTexts.matching(identifier: "screen.title").firstMatch
    }

    /// The display title when it reads exactly `text`. Home's title is its greeting (S03, T19: "Good morning, Jon."),
    /// which follows the time of day and the player's name, so `heading("Home")` matches any greeting.
    @MainActor
    func heading(_ text: String) -> XCUIElement {
        let predicate = text == ShellTab.home.heading
            ? NSPredicate(format: "label MATCHES %@", "^Good (morning|afternoon|evening)[.,].*")
            : NSPredicate(format: "label == %@", text)
        return staticTexts.matching(identifier: "screen.title").matching(predicate).firstMatch
    }
}
