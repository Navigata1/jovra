import JovraCore
import SwiftUI

/// The demo's processing screen (user story 24): the sample match part-way through analysis, labelled
/// "Demo processing state" and Sample throughout. Nothing runs, nothing is uploaded, and its numbers
/// are fixed sample values from the screen brief, never computed from a recording.
struct DemoProcessingState: View {
    @Environment(AppRouter.self) private var router

    private static let rows: [StageRow] = {
        let locale = Locale.autoupdatingCurrent
        func percent(_ value: Int) -> String { JovraFormat.percent(value, locale: locale) }
        return [
            StageRow(id: "saved", title: String(localized: "Saved locally", table: "Processing"),
                     detail: String(localized: "Video copied to your device", table: "Processing"),
                     indicator: .done, trailing: percent(100), status: String(localized: "Done", table: "Processing")),
            StageRow(id: "prepareReplay", title: String(localized: "Preparing replay", table: "Processing"),
                     detail: String(localized: "Checking video and audio for replay", table: "Processing"),
                     indicator: .done, trailing: percent(100), status: String(localized: "Done", table: "Processing")),
            StageRow(id: "analyze", title: String(localized: "Analyzing points", table: "Processing"),
                     detail: String(localized: "Detecting shots, rallies and key moments", table: "Processing"),
                     indicator: .active(0.62), trailing: percent(62), status: String(localized: "In progress", table: "Processing")),
            StageRow(id: "backup", title: String(localized: "Backing up", table: "Processing"),
                     detail: String(localized: "Queued for your Google Drive archive", table: "Processing"),
                     indicator: .waiting, trailing: "—", status: String(localized: "Waiting", table: "Processing")),
        ]
    }()

    var body: some View {
        Label { Text("Demo processing state", tableName: "Processing") } icon: { Image(systemName: "square.dashed") }
            .font(.jovraLabel)
            .foregroundStyle(.jovra(.textPrimary))
            .padding(.horizontal, Space.x2).padding(.vertical, Space.x1)
            .fixedSize(horizontal: false, vertical: true)
            // A rounded rectangle, not a capsule, so the outline stays even when the label wraps at AX sizes.
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Color.jovra(.textPrimary), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .accessibilityIdentifier("processing.demo")
        SessionVideoCard(title: "Jon vs Alex", meta: String(localized: "54 min · 1080p", table: "Processing"),
                         date: String(localized: "Oct 6, 2026", table: "Processing"), isSample: true,
                         length: "54:00", thumbnail: nil, viewable: false) {}
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeader(title: String(localized: "Analysis progress", table: "Processing"))
            VStack(alignment: .leading, spacing: Space.x3) {
                StageTimeline(rows: Self.rows)
                InfoCard(symbol: "checkmark.shield.fill",
                         title: String(localized: "Recording is safe.", table: "Processing"),
                         message: String(localized: "You can leave this screen.", table: "Processing"),
                         tone: .positive)
                .accessibilityElement(children: .combine)
            }
            .jovraCard(padding: Space.x2 + Space.half)
        }
        Button {
            router.dismissFullScreen()
            router.show(.tab(.sessions))
        } label: {
            Label { Text("Open sample sessions", tableName: "Processing") } icon: { Image(systemName: "arrow.right") }
                .labelStyle(TrailingIconLabelStyle())
        }
        .buttonStyle(.jovraPrimary)
        .accessibilityIdentifier("processing.demo.sessions")
        StatusStrip(items: [
            .init(id: "wifi", symbol: "wifi", title: String(localized: "Wi-Fi only", table: "Processing"),
                  detail: String(localized: "Backup waits for Wi-Fi", table: "Processing")),
            .init(id: "demo", symbol: "chart.bar", title: String(localized: "Demo processing state", table: "Processing"),
                  detail: String(localized: "Sample state — nothing is uploaded", table: "Processing")),
        ])
    }
}
