import JovraCore
import SwiftUI

struct InsightsView: View {
    private let legend: [(ProvenanceBadge.Kind, String)] = [
        (.sample, "Demo data. Never your own play."),
        (.provenance(.manual), "Entered by you."),
        (.provenance(.estimated), "Measured automatically and not yet checked."),
        (.provenance(.reviewed), "Checked or corrected by you."),
    ]

    var body: some View {
        JovraScreen(title: "Insights", subtitle: "See the work pay off.") {
            ComingLaterCard(
                symbol: "chart.bar",
                message: "Shot placement, Serve Lab, Stroke Lab, progress trends and practice suggestions, each linked to the points they came from."
            )
            VStack(alignment: .leading, spacing: Space.x2) {
                SectionHeader(title: "How JOVRA labels numbers")
                ForEach(legend, id: \.0) { kind, meaning in
                    VStack(alignment: .leading, spacing: Space.half) {
                        ProvenanceBadge(kind: kind)
                        Text(meaning)
                            .font(.subheadline)
                            .foregroundStyle(.jovra(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .jovraCard(padding: Space.x3)
        }
    }
}
