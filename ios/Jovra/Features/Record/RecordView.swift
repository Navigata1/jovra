import SwiftUI

struct RecordView: View {
    @Environment(AppRouter.self) private var router
    @State private var choices = CaptureSetupChoices()

    var body: some View {
        JovraScreen(title: String(localized: "Set up your session", table: "Record")) {
            Text("Singles match", tableName: "Capture").font(.jovraHeadline)
            CaptureSetupFields(choices: $choices)
            Button(String(localized: "Frame your court", table: "Capture")) {
                router.present(.capture(.init(kind: .singlesMatch, captureChoices: choices)))
            }
                .buttonStyle(.jovraPrimary)
                .disabled(!choices.isValid)
                .accessibilityIdentifier("record.previewCapture")
        }
    }
}
