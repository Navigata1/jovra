import SwiftUI

/// JOVRA for Apple Watch: a mirror and a remote for the wearer's own paired iPhone (ADR-0026). It never joins the
/// room, never hosts and never receives video. Recording and scoring on the phone never depend on it.
@main
struct JovraWatchApp: App {
    @State private var model = WatchAppModel.launch(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
    }
}
