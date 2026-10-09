import SwiftUI

// Placeholder service key, handed to T20 (session library). T20 replaces `live()` with a lookup over
// the session store's index and `fake(for:)` with the sample library's sessions; the key name and
// the environment property stay, so the router (T07) never changes. Until then the library is empty,
// and "Show last match" opens the library.
struct SessionLookupKey: ServiceKey {
    static let defaultValue: any SessionLookup = resolve(.current)

    static func live() -> any SessionLookup { FixedSessionLookup() }

    static func fake(for configuration: LaunchConfiguration) -> any SessionLookup { FixedSessionLookup() }
}

extension EnvironmentValues {
    /// The library index deep links resolve against.
    var sessionLookup: any SessionLookup {
        get { self[SessionLookupKey.self] }
        set { self[SessionLookupKey.self] = newValue }
    }
}
