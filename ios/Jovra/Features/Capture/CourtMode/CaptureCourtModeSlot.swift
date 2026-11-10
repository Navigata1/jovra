import JovraMedia
import SwiftUI

/// Court mode's slot (T25 replaces this placeholder with the N9 heat ladder). When the engine asks for court
/// mode the recording phase removes the preview and this slot says so, so the phone does less work; otherwise
/// the slot draws nothing. The engine's reading is live (the route re-reads the budget while recording).
struct CaptureCourtModeSlot: View {
    var previewMode: CapturePreviewMode

    var body: some View {
        if previewMode == .courtMode {
            ZStack {
                Color.jovra(.background)
                Label {
                    Text("Phone hot · Preview off to keep recording", tableName: "Capture")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "thermometer.high").accessibilityHidden(true)
                }
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.attentionInk))
                .padding(Space.x3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture.slot.courtMode")
        }
    }
}
