#if DEBUG
import JovraCore
import SwiftUI

/// An opt-in native gallery for component acceptance checks; absent from release builds.
struct CoreComponentsGalleryHarness: ViewModifier {
    func body(content: Content) -> some View {
        if let rawState = ProcessInfo.processInfo.environment["JOVRA_CORE_COMPONENT_GALLERY"],
           let state = CoreComponentsGallery.Scenario(rawValue: rawState) {
            CoreComponentsGallery(state: state)
        } else {
            content
        }
    }
}

struct CoreComponentsGallery: View {
    enum Scenario: String { case empty, denied, error, unsupported, badges }
    var state: Scenario
    @State private var actionResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                Text(String(localized: "Core components", table: "DesignSystem.Components"))
                    .font(.jovraHeadline)
                    .foregroundStyle(.jovra(.textPrimary))
                    .accessibilityIdentifier("screen.title")
                if state == .badges {
                    badges
                } else {
                    stateCard
                }
                if let actionResult { Text(actionResult).foregroundStyle(.jovra(.textPrimary)) }
            }
            .padding(Space.screenMargin)
        }
        .background(Color.jovra(.background))
    }

    @ViewBuilder private var stateCard: some View {
        switch state {
        case .denied:
            StateCard(symbol: "camera", title: String(localized: "Camera access is off", table: "DesignSystem.Components"),
                      message: String(localized: "Turn on Camera for JOVRA in iOS Settings to record. You can still import videos you already have.", table: "DesignSystem.Components"),
                      primaryAction: .init(title: String(localized: "Open iOS Settings", table: "DesignSystem.Components")) {
                          actionResult = String(localized: "Settings requested", table: "DesignSystem.Components")
                      })
        case .error:
            StateCard(symbol: "exclamationmark.triangle", title: String(localized: "Export didn't finish", table: "DesignSystem.Components"),
                      message: String(localized: "Your video is safe. Try exporting again.", table: "DesignSystem.Components"),
                      primaryAction: .init(title: String(localized: "Retry", table: "DesignSystem.Components")) {
                          actionResult = String(localized: "Retry requested", table: "DesignSystem.Components")
                      })
        case .unsupported:
            StateCard(symbol: "info.circle", title: String(localized: "Speed is not available", table: "DesignSystem.Components"),
                      message: String(localized: "This capability has not passed its checks.", table: "DesignSystem.Components"))
        case .empty:
            StateCard(
                    symbol: "tray",
                    title: String(localized: "No sessions yet", table: "DesignSystem.Components"),
                    message: String(localized: "Record a match or practice, or import a video you already have.", table: "DesignSystem.Components"),
                    primaryAction: .init(title: String(localized: "Record a session", table: "DesignSystem.Components")) {
                        actionResult = String(localized: "Record requested", table: "DesignSystem.Components")
                    },
                    secondaryAction: .init(title: String(localized: "Import a video", table: "DesignSystem.Components")) {
                        actionResult = String(localized: "Import requested", table: "DesignSystem.Components")
                    }
                )
        case .badges:
            badges
        }
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SampleBadge().accessibilityIdentifier("gallery.sample")
            SampleBadge(size: .small)
            FixtureBadge().accessibilityIdentifier("gallery.fixture")
            ForEach([Provenance.manual, .estimated, .reviewed, .validated], id: \.self) {
                ProvenanceBadge(kind: .provenance($0), size: .small)
            }
            EditorialCard {
                SampleBadge(onForest: true)
                ProvenanceBadge(kind: .provenance(.estimated), onForest: true)
            }
            DemoBanner { actionResult = String(localized: "Sample closed", table: "DesignSystem.Components") }
        }
    }
}

#Preview("Core empty") { CoreComponentsGallery(state: .empty) }
#Preview("Core badges dark") { CoreComponentsGallery(state: .badges).preferredColorScheme(.dark) }
#endif
