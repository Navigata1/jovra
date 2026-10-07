import JovraCore
import SwiftUI

/// Every design-system component in one place, for Xcode previews in light and dark.
/// Values here are illustrative and visibly badged "Sample" (CLAUDE.md rule 1).
struct ComponentGallery: View {
    enum Range: String, CaseIterable, Identifiable {
        case weeks = "4 weeks", months = "3 months", year = "Year"
        var id: String { rawValue }
    }

    @State private var range = Range.weeks

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                JovraLockup(height: 40)
                Text("Components").jovraDisplayTitle()
                EditorialCard {
                    Text("Ready for your next session?")
                        .font(.jovraEditorial)
                        .foregroundStyle(.jovra(.textOnEditorial))
                    Button("Record a session") {}.buttonStyle(.jovraAccent)
                }
                HStack(spacing: Space.x1) {
                    StatTile(value: DurationLabel.compact(seconds: 24_120), label: "On court", symbol: "clock", badge: .sample)
                    StatTile(value: "67%", label: "First serves", symbol: "scope", badge: .provenance(.estimated))
                }
                SectionHeader(title: "Latest session") {
                    Button("View all") {}.font(.jovraLabel).frame(minHeight: HitTarget.minimum)
                }
                FilterPills(options: Range.allCases, selection: $range) { $0.rawValue }
                VStack(alignment: .leading, spacing: Space.x1) {
                    StatusPill(text: "On device · Backed up", tone: .positive)
                    StatusPill(text: "Needs review", tone: .attention)
                    StatusPill(text: "Queued", tone: .neutral)
                }
                HStack {
                    ForEach([ProvenanceBadge.Kind.sample, .provenance(.manual), .provenance(.estimated), .provenance(.reviewed)], id: \.self) {
                        ProvenanceBadge(kind: $0)
                    }
                }
                VStack(spacing: 0) {
                    SettingsRow(symbol: "camera", title: "Camera", subtitle: "Allowed")
                    Divider()
                    SettingsRow(symbol: "trash", title: "Delete account", titleRole: .attentionInk)
                }
                .jovraCard()
                HStack {
                    AvatarInitial(initial: "J")
                    AvatarInitial(initial: nil)
                }
                Button("Continue") {}.buttonStyle(.jovraPrimary)
                Button("Pause analysis") {}.buttonStyle(.jovraSecondary)
            }
            .padding(Space.screenMargin)
        }
        .background(Color.jovra(.background))
    }
}

#Preview("Light") { ComponentGallery().preferredColorScheme(.light) }
#Preview("Dark") { ComponentGallery().preferredColorScheme(.dark) }
