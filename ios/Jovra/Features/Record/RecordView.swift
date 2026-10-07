import SwiftUI

struct RecordView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        JovraScreen(title: "Set up your session") {
            ComingLaterCard(
                symbol: "video",
                message: "Choose a singles or doubles match, serve practice or stroke practice, then frame your court and record."
            )
            VStack(alignment: .leading, spacing: Space.x1) {
                SectionHeader(title: "Full-screen flows")
                Text("Capture, replay and compare take over the whole screen and hide the tabs.")
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Preview the capture screen") { router.present(.capturePreview) }
                .buttonStyle(.jovraPrimary)
                .accessibilityIdentifier("record.previewCapture")
        }
    }
}
