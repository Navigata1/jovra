import JovraRoom
import SwiftUI

/// The watch shell (watch spec "Layouts"): a vertical-page TabView, Health → Score → Latest serve → Mark, inside one
/// NavigationStack for "View all" and confirmations, with the connection alert as a full-screen sheet over it.
/// Surface tickets (W04 to W06) replace the shell pages with their features; the frame stays.
struct WatchRootView: View {
    @Bindable var model: WatchAppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        Group {
            if case .launchProblems(let problems) = model.mode {
                HarnessProblemView(problems: problems, registered: WatchStateRegistry.shared.registeredValues)
            } else {
                pages
            }
        }
        .environment(\.watchReduceMotion, model.reduceMotionOverride ?? systemReduceMotion)
        .tint(WatchPalette.chartreuse)
    }

    private var pages: some View {
        NavigationStack(path: $model.path) {
            TabView(selection: $model.page) {
                HealthShellPage(model: model).tag(WatchSurface.health)
                ScoreShellPage(model: model).tag(WatchSurface.score)
                ServeShellPage(model: model).tag(WatchSurface.serve)
                MarkShellPage(model: model).tag(WatchSurface.mark)
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .cameras: CameraListView(model: model)
                }
            }
        }
        .fullScreenCover(item: Binding(get: { model.presentedAlert },
                                       set: { if $0 == nil, let shown = model.presentedAlert { model.dismiss(shown.id) } })) {
            presented in
            AlertShellSheet(model: model, alert: presented.alert)
        }
    }
}

/// The page frame every shell surface shares: a scrolling column (the Digital Crown scrolls it), the surface's
/// identifier for UI tests, and the Sample tag at the bottom when the snapshot is sample data.
struct WatchPage<Content: View>: View {
    let surface: WatchSurface
    let isSample: Bool
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                content
                if isSample { SampleTag().padding(.top, 2) }
            }
            .padding(.horizontal, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .watchPageChrome()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(surface.identifier)
    }
}
