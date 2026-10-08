import SwiftUI

struct RecordView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        JovraScreen(title: String(localized: "Set up your session", table: "Record")) {
            ComingLaterCard(
                symbol: "video",
                message: String(localized: "Choose a singles or doubles match, serve practice or stroke practice, then frame your court and record.", table: "Record")
            )
            VStack(alignment: .leading, spacing: Space.x1) {
                SectionHeader(title: String(localized: "Full-screen flows", table: "Record"))
                Text("Capture, replay and compare take over the whole screen and hide the tabs.", tableName: "Record")
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(String(localized: "Preview the capture screen", table: "Record")) { router.present(.capturePreview) }
                .buttonStyle(.jovraPrimary)
                .accessibilityIdentifier("record.previewCapture")
        }
    }
}
