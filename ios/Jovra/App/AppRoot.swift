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
    /// Recordings adopted at this launch after JOVRA stopped while recording (T17's recovered-recording sheet).
    @State private var recoveredRecordings: [RecoveredCaptureReport] = []
    @State private var isShellSettled = false
    @State private var shellSettled: Task<Void, Never>?
    @SceneStorage("jovra.router.state") private var savedState: Data?
    @Environment(\.localCaptureLibrary) private var captureLibrary
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
        #if DEBUG
        .modifier(CoreComponentsGalleryHarness())
        #endif
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: router.preShell == nil)
        .environment(router)
        .onOpenURL { url in
            Task { await router.open(url, sessions: sessions) }
        }
        .task {
            if case .ready(let library) = captureLibrary { recoveredRecordings = await library.reconcileAtStartup().reports }
        }
        .sheet(isPresented: Binding(get: { showsRecoveredRecordings }, set: { _ in })) {
            RecoveredRecordingSheet(reports: recoveredRecordings,
                                    openLibrary: { recoveredRecordings = []; router.show(.tab(.sessions)) },
                                    done: { recoveredRecordings = [] })
        }
        .onChange(of: isShellClear, initial: true) { _, isClear in
            shellSettled?.cancel()
            isShellSettled = false
            guard isClear else { return }
            shellSettled = Task {
                try? await Task.sleep(for: Self.presentationSettleTime)
                if !Task.isCancelled { isShellSettled = true }
            }
        }
        .onAppear(perform: restoreOnce)
        .onChange(of: router.state) { _, state in
            savedState = try? state.restorationData()
        }
    }

    private var reduceMotion: Bool { systemReduceMotion || launch.reduceMotion }

    /// The recovered-recording sheet waits for the shell to be clear: a restored or harness-opened
    /// full-screen route (or another sheet) already owns the presentation, and two presentations at once
    /// would drop this one. The reports are kept until one of the sheet's two answers clears them.
    private var showsRecoveredRecordings: Bool { !recoveredRecordings.isEmpty && isShellClear && isShellSettled }

    private var isShellClear: Bool { router.preShell == nil && router.fullScreenRoute == nil && router.sheet == nil }

    /// Long enough for a closing full-screen route to finish leaving. Presented any sooner, the sheet
    /// would take on that route's forest appearance instead of the app's own.
    private static let presentationSettleTime = Duration.milliseconds(700)

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
