import Foundation

/// What a launch asked for: appearance, demo state, fixture camera, injected permission and archive
/// states, Reduce Motion, a pseudo-locale, the start route, a fresh local library, the processing
/// fixture analyzer, an injected device state for the processing queue, the profile store and an
/// injected Sign in with Apple answer.
///
/// This file is the launch-argument contract between the app and its UI tests and is compiled into
/// both targets (see `ios/project.yml`): UI tests build `arguments` from a value, and the app parses
/// them back with `init(arguments:)`. A value the parser does not understand is recorded in
/// `problems`, never silently ignored. Arguments it does not know (the system's own, such as
/// `-UIPreferredContentSizeCategoryName`) are skipped.
///
/// With no arguments every field means "live behaviour": the player's own appearance preference, no
/// demo, the real camera, real permission and archive states, the system Reduce Motion setting and
/// the library saved on the device.
struct LaunchConfiguration: Equatable, Sendable {
    /// Argument names. `-appearance` doubles as the `appearance` UserDefaults key read by
    /// `@AppStorage`, so the preference itself follows the launch argument.
    enum Key {
        static let appearance = "-appearance"
        static let demo = "-demo"
        static let fixtureCamera = "-fixtureCamera"
        static let permissions = "-permissions"
        static let archiveState = "-archiveState"
        static let reduceMotion = "-reduceMotion"
        static let pseudoLocale = "-pseudoLocale"
        static let startRoute = "-startRoute"
        static let processingAnalyzer = "-processingAnalyzer"
        static let processingDevice = "-processingDevice"
        static let library = "-library"
        static let recordFixtureSession = "-recordFixtureSession"
        static let profile = "-profile"
        static let appleSignIn = "-appleSignIn"
        static let importSelection = "-importSelection"
        static let importStall = "-importStall"
    }

    enum Appearance: String, CaseIterable, Sendable {
        case system, light, dark
    }

    enum DemoState: String, CaseIterable, Sendable {
        /// No sample content (the default).
        case off
        /// The sample library is installed, always badged "Sample".
        case sample
    }

    /// The permissions `PermissionsCenter` adapts (spec: camera, microphone, Photos add-only,
    /// notifications and HealthKit).
    enum Permission: String, CaseIterable, Sendable {
        case camera, microphone, photosAdd, notifications, health
    }

    enum PermissionState: String, CaseIterable, Sendable {
        case notDetermined, denied, restricted, authorized
    }

    /// The archive account states of `ArchiveService` (spec, ArchiveService).
    enum ArchiveState: String, CaseIterable, Sendable {
        case awaitingSetup, notConnected, connecting, connected, needsReconnect
    }

    /// Pseudo-locales use the system pseudolanguages, so every string looked up through a String
    /// Catalog is transformed and any string that bypasses the catalogs stands out unchanged.
    enum PseudoLocale: String, CaseIterable, Sendable {
        /// Accented letters inside `[# … #]` brackets: shows untranslated strings and clipped ends.
        case accented
        /// Every string twice: shows layouts that cannot take translation growth.
        case doubleLength
        /// Right-to-left strings and layout direction.
        case rightToLeft

        /// The Foundation launch arguments that switch the pseudolanguage on.
        var systemArguments: [String] {
            switch self {
            case .accented:
                ["-NSAccentuateLocalizedStrings", "YES", "-NSSurroundLocalizedStrings", "YES"]
            case .doubleLength:
                ["-NSDoubleLocalizedStrings", "YES"]
            case .rightToLeft:
                ["-NSForceRightToLeftLocalizedStrings", "YES", "-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
            }
        }
    }

    /// The fixture analyzer the processing queue registers for UI tests (T27). It writes no results:
    /// it only moves the analyze stage's progress, steadily or failing once at 40 %.
    enum ProcessingAnalyzer: String, CaseIterable, Sendable {
        case steady, failsOnce
    }

    /// A device state the processing queue holds for, injected because the simulator can set neither
    /// Low Power Mode nor the thermal state (T27). Only the processing queue's conditions change.
    enum ProcessingDevice: String, CaseIterable, Sendable {
        /// Low Power Mode on, not charging: analysis waits for a charger.
        case lowPowerOnBattery
        /// Thermal state serious: every stage waits for the iPhone to cool down.
        case tooWarm
    }

    /// Which local library a launch uses.
    enum Library: String, CaseIterable, Sendable {
        /// A new, empty library in a temporary folder for this launch only. The library saved on the
        /// device is neither read nor changed, so a UI test sees no sessions left by an earlier test.
        case fresh
        /// A fresh library seeded with visibly labelled Sample sessions covering every original, analysis,
        /// review and archive state, one session in Trash and one unreadable document set aside in quarantine.
        case facets
    }

    /// The longest headless fixture recording a launch may ask for, in seconds.
    static let maximumFixtureSessionSeconds = 120

    /// Which player profile store a launch uses (T18). The welcome gate reads it: with no profile, the launch opens
    /// on Welcome.
    enum ProfileStoreChoice: String, CaseIterable, Sendable {
        /// A new, empty store in a temporary folder for this launch only: Welcome shows.
        case fresh
        /// A temporary store holding a plain, unnamed profile for this launch only: the shell shows, as before T18.
        case onboarded
        /// The UI-test folder, emptied at launch and kept for the next launch.
        case persistentNew
        /// The UI-test folder as the previous launch left it (a relaunch check).
        case persistent
    }

    /// What "Continue with Apple" answers instead of Apple's sheet (T18). The fixture identity never leaves the device.
    enum AppleSignInFixture: String, CaseIterable, Sendable {
        case succeeded, cancelled, failed
    }

    var appearance: Appearance?
    var demo: DemoState = .off
    /// The fixture clip the simulator fixture camera streams (ADR-0012); nil uses the default source.
    var fixtureCamera: String?
    /// Injected permission states; a permission not listed here uses the live state.
    var permissions: [Permission: PermissionState] = [:]
    var archiveState: ArchiveState?
    /// Forces Reduce Motion on in addition to the system setting.
    var reduceMotion = false
    var pseudoLocale: PseudoLocale?
    /// A tab or full-screen route name to open at launch (resolved by the app shell).
    var startRoute: String?
    /// Registers the fixture analyzer; nil registers none (production has none until a V ticket ships one).
    var processingAnalyzer: ProcessingAnalyzer?
    /// nil reads the device's own power and thermal state.
    var processingDevice: ProcessingDevice?
    /// nil uses the library saved on the device.
    var library: Library?
    /// Records a session of this many seconds through the capture engine and the fixture camera at launch,
    /// with no screen in between (the walking skeleton), then opens the library. nil records nothing.
    var recordFixtureSessionSeconds: Int?
    /// nil uses the profile saved on the device.
    var profile: ProfileStoreChoice?
    /// nil uses Sign in with Apple itself.
    var appleSignIn: AppleSignInFixture?
    /// UI-test seam (T26): absolute paths delivered as the picker's selection instead of presenting the
    /// system Photos or Files picker. A path prefixed `cloud:` is reported as not yet downloaded for a moment.
    var importSelection: [String] = []
    /// UI-test seam (T26): an import stops just before publication, so a test can end the process mid-import.
    var importStall = false

    /// Arguments that could not be understood. Not part of equality.
    private(set) var problems: [String] = []

    init() {}

    /// Parses `ProcessInfo.processInfo.arguments` (the first element, the executable path, is skipped
    /// along with every argument this type does not know).
    init(arguments: [String]) {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let key = arguments[index]
            guard Self.knownKeys.contains(key) else {
                index += 1
                continue
            }
            let valueIndex = index + 1
            guard valueIndex < arguments.endIndex, !Self.knownKeys.contains(arguments[valueIndex]) else {
                problems.append("\(key): missing value")
                index = valueIndex
                continue
            }
            apply(key: key, value: arguments[valueIndex])
            index = valueIndex + 1
        }
    }

    /// The launch arguments that reproduce this configuration, in a fixed order.
    var arguments: [String] {
        var result: [String] = []
        if let appearance { result += [Key.appearance, appearance.rawValue] }
        if demo != .off { result += [Key.demo, demo.rawValue] }
        if let fixtureCamera { result += [Key.fixtureCamera, fixtureCamera] }
        if !permissions.isEmpty {
            let pairs = Permission.allCases.compactMap { permission in
                permissions[permission].map { "\(permission.rawValue)=\($0.rawValue)" }
            }
            result += [Key.permissions, pairs.joined(separator: ",")]
        }
        if let archiveState { result += [Key.archiveState, archiveState.rawValue] }
        if reduceMotion { result += [Key.reduceMotion, "YES"] }
        if let pseudoLocale { result += [Key.pseudoLocale, pseudoLocale.rawValue] + pseudoLocale.systemArguments }
        if let startRoute { result += [Key.startRoute, startRoute] }
        if let processingAnalyzer { result += [Key.processingAnalyzer, processingAnalyzer.rawValue] }
        if let processingDevice { result += [Key.processingDevice, processingDevice.rawValue] }
        if let library { result += [Key.library, library.rawValue] }
        if let recordFixtureSessionSeconds { result += [Key.recordFixtureSession, String(recordFixtureSessionSeconds)] }
        if let profile { result += [Key.profile, profile.rawValue] }
        if let appleSignIn { result += [Key.appleSignIn, appleSignIn.rawValue] }
        if !importSelection.isEmpty { result += [Key.importSelection, importSelection.joined(separator: "|")] }
        if importStall { result += [Key.importStall, "YES"] }
        return result
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.arguments == rhs.arguments
    }

    // MARK: Parsing

    private static let knownKeys: Set<String> = [
        Key.appearance, Key.demo, Key.fixtureCamera, Key.permissions,
        Key.archiveState, Key.reduceMotion, Key.pseudoLocale, Key.startRoute, Key.library, Key.processingAnalyzer,
        Key.processingDevice, Key.recordFixtureSession, Key.profile, Key.appleSignIn, Key.importSelection, Key.importStall,
    ]

    private mutating func apply(key: String, value: String) {
        switch key {
        case Key.appearance: appearance = parse(Appearance.self, value, for: key)
        case Key.demo: demo = parse(DemoState.self, value, for: key) ?? demo
        case Key.fixtureCamera: fixtureCamera = value
        case Key.permissions: parsePermissions(value)
        case Key.archiveState: archiveState = parse(ArchiveState.self, value, for: key)
        case Key.reduceMotion: parseReduceMotion(value)
        case Key.pseudoLocale: pseudoLocale = parse(PseudoLocale.self, value, for: key)
        case Key.startRoute: startRoute = value
        case Key.processingAnalyzer: processingAnalyzer = parse(ProcessingAnalyzer.self, value, for: key)
        case Key.processingDevice: processingDevice = parse(ProcessingDevice.self, value, for: key)
        case Key.library: library = parse(Library.self, value, for: key)
        case Key.recordFixtureSession: parseFixtureSeconds(value)
        case Key.profile: profile = parse(ProfileStoreChoice.self, value, for: key)
        case Key.appleSignIn: appleSignIn = parse(AppleSignInFixture.self, value, for: key)
        case Key.importSelection: importSelection = value.split(separator: "|").map(String.init)
        case Key.importStall:
            guard value == "YES" || value == "NO" else {
                problems.append("\(key): unknown value “\(value)” (expected YES or NO)")
                return
            }
            importStall = value == "YES"
        default: break
        }
    }

    private mutating func parse<Value: RawRepresentable & CaseIterable>(
        _: Value.Type, _ value: String, for key: String
    ) -> Value? where Value.RawValue == String {
        if let parsed = Value(rawValue: value) { return parsed }
        problems.append("\(key): unknown value “\(value)” (expected \(Self.list(Value.self)))")
        return nil
    }

    private mutating func parsePermissions(_ value: String) {
        for pair in value.split(separator: ",") {
            let parts = pair.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else {
                problems.append("\(Key.permissions): “\(pair)” is not permission=state")
                continue
            }
            guard let permission = Permission(rawValue: parts[0]) else {
                problems.append("\(Key.permissions): unknown permission “\(parts[0])” (expected \(Self.list(Permission.self)))")
                continue
            }
            guard let state = PermissionState(rawValue: parts[1]) else {
                problems.append("\(Key.permissions): unknown state “\(parts[1])” for \(parts[0]) (expected \(Self.list(PermissionState.self)))")
                continue
            }
            permissions[permission] = state
        }
    }

    private mutating func parseFixtureSeconds(_ value: String) {
        guard let seconds = Int(value), (1...Self.maximumFixtureSessionSeconds).contains(seconds) else {
            problems.append("\(Key.recordFixtureSession): unknown value “\(value)” (expected whole seconds from 1 to \(Self.maximumFixtureSessionSeconds))")
            return
        }
        recordFixtureSessionSeconds = seconds
    }

    private mutating func parseReduceMotion(_ value: String) {
        switch value.lowercased() {
        case "yes", "true", "1": reduceMotion = true
        case "no", "false", "0": reduceMotion = false
        default: problems.append("\(Key.reduceMotion): unknown value “\(value)” (expected YES or NO)")
        }
    }

    private static func list<Value: RawRepresentable & CaseIterable>(_: Value.Type) -> String where Value.RawValue == String {
        Value.allCases.map(\.rawValue).joined(separator: ", ")
    }
}
