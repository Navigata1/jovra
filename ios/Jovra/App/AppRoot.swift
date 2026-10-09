import OSLog
import SwiftUI

/// The app's two roots: the pre-shell (welcome and onboarding) and the shell, swapped with a
/// cross-fade (none with Reduce Motion). Owns the router, opens deep links, and saves and restores
/// the navigation state.
///
/// Where a launch starts, in order: the `-startRoute` the launch harness names; otherwise the state
/// restoration saved (only for a launch with no harness arguments, so a UI test always starts where
/// its arguments say); otherwise the welcome gate (`WelcomeGate`, T18) decides between pre-shell and
/// Home.
struct AppRoot: View {
    @State private var router: AppRouter = AppRoot.initialRouter(launch: .current)
    @State private var hasRestored = false
    @SceneStorage("jovra.router.state") private var savedState: Data?
    @Environment(\.sessionLookup) private var sessions
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.launchConfiguration) private var launch

    var body: some View {
        ZStack {
            if let route = router.preShell {
                PreShellDestination(route: route)
                    .transition(.opacity)
            } else {
                AppShell()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: router.preShell == nil)
        .environment(router)
        .onOpenURL { url in
            Task { await router.open(url, sessions: sessions) }
        }
        .onAppear(perform: restoreOnce)
        .onChange(of: router.state) { _, state in
            savedState = try? state.restorationData()
        }
    }

    private var reduceMotion: Bool { systemReduceMotion || launch.reduceMotion }

    private func restoreOnce() {
        guard !hasRestored else { return }
        hasRestored = true
        guard Self.restoresSavedState(launch: .current), let savedState else { return }
        do {
            router.state = try RouterState(restorationData: savedState)
        } catch {
            Logger(subsystem: "com.islanddevcrew.jovra", category: "Restoration")
                .notice("Saved navigation state did not decode; starting fresh. \(String(describing: error), privacy: .public)")
        }
    }

    /// A launch with harness arguments starts where they say, never where a previous run left off.
    static func restoresSavedState(launch: LaunchConfiguration) -> Bool {
        launch == LaunchConfiguration()
    }

    static func initialRouter(launch: LaunchConfiguration) -> AppRouter {
        let router = AppRouter()
        if let destination = launch.startDestination {
            router.show(destination)
        } else if let route = WelcomeGate.initialRoute() {
            router.show(.preShell(route))
        }
        return router
    }
}
