import JovraMedia
import SwiftUI

/// Court mode's slot (T25 replaces this placeholder with the N9 heat ladder). When the engine asks for court
/// mode the preview is covered so the phone does less work; otherwise the slot draws nothing.
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
