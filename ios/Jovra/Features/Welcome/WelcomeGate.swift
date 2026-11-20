/// Decides whether a launch starts in the pre-shell (screen spec §0.1): Welcome shows until a profile exists or the
/// demo is chosen (the demo saves the sample profile). A profile that could not be read never sends the player back to
/// Welcome, where finishing onboarding would overwrite it; the shell opens and the Profile hub explains.
enum WelcomeGate {
    /// The pre-shell route to start on, or nil for the shell.
    static func initialRoute(for state: PlayerProfileModel.State) -> PreShellRoute? {
        state == .loaded(nil) ? .welcome : nil
    }
}
