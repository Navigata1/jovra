import SwiftUI

/// The framing phase's slot (T23 replaces this placeholder with court framing and calibration). Until then
/// it only says what to do; it draws no court overlay and claims no court check.
struct CaptureFramingSlot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text("Frame your court", tableName: "Capture")
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityAddTraits(.isHeader)
            Text("Position behind the baseline and align the court in the frame. Calibration can be added after recording.", tableName: "Capture")
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.slot.framing")
    }
}
