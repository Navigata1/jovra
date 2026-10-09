import JovraCore
import SwiftUI

struct InsightsView: View {
    private let legend: [(ProvenanceBadge.Kind, String)] = [
        (.sample, String(localized: "Demo data. Never your own play.", table: "Insights")),
        (.provenance(.manual), String(localized: "Entered by you.", table: "Insights")),
        (.provenance(.estimated), String(localized: "Measured automatically and not yet checked.", table: "Insights")),
        (.provenance(.reviewed), String(localized: "Checked or corrected by you.", table: "Insights")),
    ]

    var body: some View {
        JovraScreen(title: String(localized: "Insights", table: "Insights"), subtitle: String(localized: "See the work pay off.", table: "Insights")) {
            ComingLaterCard(
                symbol: "chart.line.uptrend.xyaxis",
                message: String(localized: "Shot placement, Serve Lab, Stroke Lab, progress trends and practice suggestions, each linked to the points they came from.", table: "Insights")
            )
            VStack(alignment: .leading, spacing: Space.x2) {
                SectionHeader(title: String(localized: "How JOVRA labels numbers", table: "Insights"))
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
