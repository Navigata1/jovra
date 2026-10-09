// Placeholder, handed to T18 (welcome, onboarding, profile hub and demo entry). T18 replaces this
// file: the pre-shell shows until a profile exists or the demo is chosen (screen spec §0.1). Until
// then every launch opens the shell; `-startRoute welcome` or `onboarding` opens the pre-shell.

/// Decides whether a launch starts in the pre-shell.
enum WelcomeGate {
    /// The pre-shell route to start on, or nil for the shell.
    static func initialRoute() -> PreShellRoute? { nil }
}
